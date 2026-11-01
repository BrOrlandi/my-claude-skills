#!/usr/bin/env bash
# Follow one or more GitHub pull requests and print one line per event: new comments,
# reviews (approval, changes requested, inline comments), CI result changes, merge
# conflicts, the PR becoming ready to merge, and the PR being merged or closed.
# Optionally merges a PR on its own as soon as it is approved and mergeable.
#
# Usage: gh-follow.sh [options] [PR ...]
#
# PR can be a URL (https://github.com/owner/repo/pull/12), owner/repo#12, or a bare
# number (resolved against the current repo). With no PR and no --mine, the PR of the
# current branch is followed.
#
# Options:
#   --mine                 Also follow every open PR authored by you
#   --interval <seconds>   Poll interval without a live webhook (default 60)
#   --safety-interval <s>  Poll interval for repos with a live webhook (default 300)
#   --no-webhook           Never start webhook forwarders; poll only
#   --once                 Check once, print what changed since the last check, exit
#   --until-event          Keep polling silently; exit right after the first round that
#                          produced an event (FOLLOWING does not count)
#   --auto-merge           Merge a PR as soon as it becomes READY
#   --merge-method <m>     squash | merge | rebase (default squash)
#   --delete-branch        Delete the head branch after an auto-merge
#   --include-self         Also report your own comments and reviews
#   --notify               Also show a macOS notification for each event
#   --reset                Forget the saved state of the given PRs before starting
#
# Output (stdout), one event per line, "<EVENT> owner/repo#N ...":
#   FOLLOWING          initial status of a PR (first time it is seen)
#   COMMENT            new conversation comment
#   APPROVED           new approving review
#   CHANGES_REQUESTED  new review requesting changes
#   REVIEW             new review with comments (body or inline comments)
#   CHECKS             CI finished: success | failure
#   CONFLICT           the branch now has merge conflicts
#   READY              approved, checks green, mergeable
#   AUTO_MERGED / AUTO_MERGE_FAILED
#   MERGED / CLOSED    the PR left the open state; it stops being followed
#   ERROR              repeated failures fetching a PR
#   DONE               nothing left to follow (exit 0)
#
# Webhooks: when the gh-webhook extension is installed (gh extension install cli/gh-webhook),
# a `gh webhook forward` runs per repo owned by you (never on organizations or other people's
# repos, which are always polled). Each delivery triggers an immediate check of the PR it
# is about, so a repo with a live forwarder is only polled every --safety-interval. A repo
# whose forwarder cannot start (no admin, extension missing) or dies falls back to
# --interval polling, and a new forwarder is tried every 10 minutes. The forwarder creates a
# temporary repo webhook (name "cli"); it is deleted on exit. Webhook status goes to stderr
# and to ${XDG_CACHE_HOME:-~/.cache}/gh-follow/webhooks.log, never to stdout.
#
# State is kept per PR in ${XDG_CACHE_HOME:-~/.cache}/gh-follow/, so a restarted follow
# reports what happened while it was not running instead of starting blind.

set -uo pipefail

INTERVAL=60
SAFETY_INTERVAL=300
WEBHOOK=1
ONCE=0
UNTIL_EVENT=0
GOT_EVENT=0
MINE=0
AUTO_MERGE=0
MERGE_METHOD="squash"
DELETE_BRANCH=0
INCLUDE_SELF=0
NOTIFY=0
RESET=0
ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --mine) MINE=1 ;;
    --interval) INTERVAL="$2"; shift ;;
    --safety-interval) SAFETY_INTERVAL="$2"; shift ;;
    --no-webhook) WEBHOOK=0 ;;
    --once) ONCE=1 ;;
    --until-event) UNTIL_EVENT=1 ;;
    --auto-merge) AUTO_MERGE=1 ;;
    --merge-method) MERGE_METHOD="$2"; shift ;;
    --delete-branch) DELETE_BRANCH=1 ;;
    --include-self) INCLUDE_SELF=1 ;;
    --notify) NOTIFY=1 ;;
    --reset) RESET=1 ;;
    -h|--help) sed -n '2,51p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

case "$MERGE_METHOD" in
  squash|merge|rebase) ;;
  *) echo "Invalid --merge-method: $MERGE_METHOD" >&2; exit 2 ;;
esac

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gh-follow"
mkdir -p "$STATE_DIR"

ME=$(gh api user --jq .login 2>/dev/null || echo "")
if [ -z "$ME" ]; then
  echo "ERROR gh is not authenticated (run: gh auth login)" >&2
  exit 1
fi

# --- Resolve PR references to owner/repo#N ---------------------------------------------

REFS=()

add_ref() {
  local ref="$1" existing
  for existing in ${REFS[@]+"${REFS[@]}"}; do
    [ "$existing" = "$ref" ] && return
  done
  REFS+=("$ref")
}

current_repo() {
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null
}

for arg in ${ARGS[@]+"${ARGS[@]}"}; do
  if [[ "$arg" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    add_ref "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}#${BASH_REMATCH[3]}"
  elif [[ "$arg" =~ ^([^/#]+)/([^/#]+)#([0-9]+)$ ]]; then
    add_ref "$arg"
  elif [[ "$arg" =~ ^#?([0-9]+)$ ]]; then
    repo=$(current_repo)
    [ -z "$repo" ] && { echo "Cannot resolve '$arg': not inside a GitHub repo" >&2; exit 2; }
    add_ref "$repo#${BASH_REMATCH[1]}"
  else
    echo "Unrecognized PR reference: $arg" >&2
    exit 2
  fi
done

if [ "$MINE" = 1 ]; then
  while IFS= read -r url; do
    [[ "$url" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]] &&
      add_ref "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}#${BASH_REMATCH[3]}"
  done < <(gh search prs --author "@me" --state open --limit 100 --json url --jq '.[].url' 2>/dev/null)
fi

if [ ${#REFS[@]} -eq 0 ] && [ "$MINE" = 0 ]; then
  url=$(gh pr view --json url -q .url 2>/dev/null || echo "")
  if [[ "$url" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    add_ref "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}#${BASH_REMATCH[3]}"
  fi
fi

if [ ${#REFS[@]} -eq 0 ]; then
  echo "DONE no open pull requests to follow"
  exit 0
fi

# --- Helpers ---------------------------------------------------------------------------

state_file() {
  echo "$STATE_DIR/$(echo "$1" | tr '/#' '__').json"
}

emit() {
  echo "$1"
  [ "${1%% *}" != "FOLLOWING" ] && GOT_EVENT=1
  if [ "$NOTIFY" = 1 ] && command -v osascript >/dev/null 2>&1; then
    local text="${1//\\/\\\\}"
    text="${text//\"/\\\"}"
    osascript -e "display notification \"$text\" with title \"gh-follow\"" >/dev/null 2>&1 || true
  fi
}

FIELDS="number,url,title,state,isDraft,reviewDecision,mergeable,mergeStateStatus,statusCheckRollup,comments,reviews,latestReviews"

# Turns the previous and current snapshots of a PR into event lines. With no previous
# snapshot it only prints FOLLOWING (and READY when it already is).
DIFF_JQ='
def flat: gsub("<!--[\\s\\S]*?-->"; "") | gsub("<[^>]+>"; "") | gsub("\\s+"; " ")
  | ltrimstr(" ") | rtrimstr(" ") | if length > 160 then .[0:157] + "..." else . end;
def checks: (.statusCheckRollup // []) as $c
  | if ($c | length) == 0 then "none"
    elif any($c[]; ((.conclusion // .state // "") | test("^(FAILURE|ERROR|CANCELLED|TIMED_OUT|ACTION_REQUIRED|STARTUP_FAILURE)$"))) then "failure"
    elif any($c[]; (.__typename == "CheckRun" and .status != "COMPLETED")
                   or (.__typename == "StatusContext" and (.state == "PENDING" or .state == "EXPECTED"))) then "pending"
    else "success" end;
def approved: .reviewDecision == "APPROVED"
  or ((.reviewDecision // "") == ""
      and any(.latestReviews[]?; .state == "APPROVED")
      and (any(.latestReviews[]?; .state == "CHANGES_REQUESTED") | not));
def ready: .state == "OPEN" and (.isDraft | not) and approved
  and (.mergeStateStatus == "CLEAN" or .mergeStateStatus == "HAS_HOOKS");
def summary: "state=\(.state)\(if .isDraft then " draft" else "" end) review=\(if (.reviewDecision // "") == "" then "none" else .reviewDecision end) checks=\(checks) merge=\(.mergeStateStatus)";
def others: select($self or .author.login != $me);
def said: (.body // "" | flat) as $b | if $b == "" then "" else ": " + $b end;

$cur as $c
| if $prev == null then
    "FOLLOWING \($ref) \"\($c.title)\" \($c | summary) \($c.url)",
    (if ($c | ready) then "READY \($ref) approved, checks \($c | checks), mergeable \($c.url)" else empty end)
  else
    ($prev.comments | map(.id)) as $seenC
    | ($prev.reviews | map(.id)) as $seenR
    | ($c.comments[] | select(.id as $i | $seenC | index($i) | not) | others
        | "COMMENT \($ref) @\(.author.login)\(said) \(.url)"),
      ($c.reviews[] | select(.id as $i | $seenR | index($i) | not) | others
        | if .state == "APPROVED" then "APPROVED \($ref) @\(.author.login)\(said) \($c.url)"
          elif .state == "CHANGES_REQUESTED" then "CHANGES_REQUESTED \($ref) @\(.author.login)\(said) \($c.url)"
          elif .state == "COMMENTED" then
            (if (.body // "" | flat) == "" then "REVIEW \($ref) @\(.author.login) left inline comments \($c.url)"
             else "REVIEW \($ref) @\(.author.login)\(said) \($c.url)" end)
          else empty end),
      (if ($prev | checks) != ($c | checks) and (($c | checks) == "success" or ($c | checks) == "failure")
       then "CHECKS \($ref) \($c | checks) \($c.url)" else empty end),
      (if $prev.mergeStateStatus != "DIRTY" and $c.mergeStateStatus == "DIRTY" and $c.state == "OPEN"
       then "CONFLICT \($ref) the branch has merge conflicts \($c.url)" else empty end),
      (if ($prev | ready | not) and ($c | ready)
       then "READY \($ref) approved, checks \($c | checks), mergeable \($c.url)" else empty end)
  end,
  (if $c.state == "MERGED" then "MERGED \($ref) \($c.url)"
   elif $c.state == "CLOSED" then "CLOSED \($ref) \($c.url)"
   else empty end)
'

auto_merge() {
  local ref="$1" repo="${1%#*}" number="${1##*#}" out flags=("--$MERGE_METHOD")
  [ "$DELETE_BRANCH" = 1 ] && flags+=("--delete-branch")
  if out=$(gh pr merge "$number" --repo "$repo" "${flags[@]}" 2>&1); then
    emit "AUTO_MERGED $ref ($MERGE_METHOD)"
  else
    emit "AUTO_MERGE_FAILED $ref: $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
  fi
}

# Checks one PR. Returns 0 while it is still open, 1 once it is merged or closed.
check_pr() {
  local ref="$1" repo="${1%#*}" number="${1##*#}" file cur prev events line
  file=$(state_file "$ref")

  if ! cur=$(gh pr view "$number" --repo "$repo" --json "$FIELDS" 2>&1); then
    FAILS=$((FAILS + 1))
    echo "fetch failed for $ref: $cur" >&2
    [ "$FAILS" -eq 5 ] && emit "ERROR $ref: $(echo "$cur" | head -1)"
    return 0
  fi
  FAILS=0

  prev="null"
  [ -s "$file" ] && prev=$(cat "$file")

  events=$(jq -rn --argjson cur "$cur" --argjson prev "$prev" --arg ref "$ref" \
    --arg me "$ME" --argjson self "$([ "$INCLUDE_SELF" = 1 ] && echo true || echo false)" "$DIFF_JQ")
  echo "$cur" > "$file"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    emit "$line"
    if [ "$AUTO_MERGE" = 1 ] && [ "${line%% *}" = "READY" ]; then
      auto_merge "$ref"
    fi
  done <<< "$events"

  case "$(jq -r .state <<< "$cur")" in
    MERGED|CLOSED) rm -f "$file"; return 1 ;;
  esac
  return 0
}

# --- Webhook forwarders ----------------------------------------------------------------

FORWARDER_URL="https://webhook-forwarder.github.com/hook"
WEBHOOK_EVENTS="pull_request,pull_request_review,pull_request_review_comment,pull_request_review_thread,issue_comment,check_suite,status"
WEBHOOK_LOG="$STATE_DIR/webhooks.log"
WEBHOOK_RETRY=600
WEBHOOK_CONNECT_WAIT=60
WEBHOOK_PING_WAIT=30

# Parallel arrays, one entry per repo (bash 3.2 has no maps).
# WH_STATE: starting (connecting) | pinged (own ping sent, awaiting it) | live | failed (retried) | denied (no admin, never retried)
WH_REPOS=(); WH_PID=(); WH_STATE=(); WH_SINCE=(); WH_LINES=()
RUN_DIR=""

wh_log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "webhook: $*" >&2
  echo "$line" >> "$WEBHOOK_LOG"
}

# Deletes forwarder hooks left on a repo (gh webhook forward never removes its own, and a
# leftover one makes the next forward fail with "Hook already exists"). Fails without admin.
wh_delete_hooks() {
  local repo="$1" ids id
  ids=$(gh api "repos/$repo/hooks" --jq ".[] | select(.config.url == \"$FORWARDER_URL\") | .id" 2>/dev/null) || return 1
  for id in $ids; do
    gh api -X DELETE "repos/$repo/hooks/$id" >/dev/null 2>&1 || true
  done
}

wh_ping() {
  local repo="$1" id
  for id in $(gh api "repos/$repo/hooks" --jq ".[] | select(.config.url == \"$FORWARDER_URL\") | .id" 2>/dev/null); do
    gh api -X POST "repos/$repo/hooks/$id/pings" >/dev/null 2>&1 || true
  done
}

wh_start() {
  local i="$1" repo="${WH_REPOS[$1]}" slug
  slug=$(echo "$repo" | tr '/' '_')
  WH_SINCE[$i]=$(date +%s)
  WH_LINES[$i]=0
  if ! wh_delete_hooks "$repo"; then
    WH_STATE[$i]=denied
    wh_log "$repo: cannot manage webhooks (needs admin on the repo), polling every ${INTERVAL}s"
    return
  fi
  : > "$RUN_DIR/$slug.events"
  gh webhook forward --repo="$repo" --events="$WEBHOOK_EVENTS" \
    > "$RUN_DIR/$slug.events" 2> "$RUN_DIR/$slug.err" &
  WH_PID[$i]=$!
  WH_STATE[$i]=starting
}

wh_stop() {
  local i="$1"
  if [ -n "${WH_PID[$i]:-}" ]; then
    # `gh webhook forward` runs the extension as a child that outlives gh; kill it too, or
    # the orphan keeps the connection and swallows the next forwarder's deliveries.
    pkill -TERM -P "${WH_PID[$i]}" 2>/dev/null || true
    kill "${WH_PID[$i]}" 2>/dev/null || true
    wait "${WH_PID[$i]}" 2>/dev/null || true
    WH_PID[$i]=""
  fi
  wh_delete_hooks "${WH_REPOS[$i]}" || true
}

cleanup() {
  local i
  for ((i = 0; i < ${#WH_REPOS[@]}; i++)); do
    case "${WH_STATE[$i]}" in failed|denied) ;; *) wh_stop "$i" ;; esac
  done
  [ -n "$RUN_DIR" ] && rm -rf "$RUN_DIR"
}

repo_live() {
  local repo="$1" i
  for ((i = 0; i < ${#WH_REPOS[@]}; i++)); do
    [ "${WH_REPOS[$i]}" = "$repo" ] && [ "${WH_STATE[$i]}" = live ] && return 0
  done
  return 1
}

# Maps one delivery to the PRs it concerns: "owner/repo#N", "owner/repo#*" when the event
# does not name a PR (a commit status), or "PING" for the hook's creation ping.
TRIGGER_JQ='
if .zen then "PING"
else .repository.full_name as $r
  | ([.pull_request.number?, (if .issue.pull_request? then .issue.number else empty end),
      (.check_suite.pull_requests[]?.number)] | map(select(. != null)) | unique) as $n
  | if ($n | length) > 0 then ($n[] | "\($r)#\(.)") else "\($r)#*" end
end'

# Reads new deliveries of every forwarder, updates its health, and prints triggered refs.
wh_poll() {
  local i repo slug file total now err line
  now=$(date +%s)
  for ((i = 0; i < ${#WH_REPOS[@]}; i++)); do
    repo="${WH_REPOS[$i]}"
    slug=$(echo "$repo" | tr '/' '_')
    file="$RUN_DIR/$slug.events"

    [ "${WH_STATE[$i]}" = denied ] && continue
    if [ "${WH_STATE[$i]}" = failed ]; then
      if [ $((now - WH_SINCE[$i])) -ge "$WEBHOOK_RETRY" ]; then
        wh_log "$repo: retrying the webhook forwarder"
        wh_start "$i"
      fi
      continue
    fi

    total=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
    total=${total:-0}
    if [ "$total" -gt "${WH_LINES[$i]}" ]; then
      while IFS= read -r line; do
        if [ "$line" = PING ]; then
          if [ "${WH_STATE[$i]}" != live ]; then
            WH_STATE[$i]=live
            wh_log "$repo: webhook live, polling only every ${SAFETY_INTERVAL}s"
          fi
        else
          echo "$line"
        fi
      done < <(tail -n "+$((WH_LINES[$i] + 1))" "$file" | head -n "$((total - WH_LINES[$i]))" \
                 | jq -r "$TRIGGER_JQ" 2>/dev/null)
      WH_LINES[$i]=$total
    fi

    if ! kill -0 "${WH_PID[$i]}" 2>/dev/null; then
      err=$(grep -v -e '^notice:' -e '^Forwarding' -e '^\[LOG\]' "$RUN_DIR/$slug.err" 2>/dev/null | head -2 | tr '\n' ' ')
      wh_log "$repo: webhook forwarder stopped (${err:-no error output}), polling every ${INTERVAL}s"
      WH_PID[$i]=""
      wh_delete_hooks "$repo" || true
      WH_STATE[$i]=failed
      WH_SINCE[$i]=$now
    elif [ "${WH_STATE[$i]}" = starting ]; then
      # GitHub's creation ping can arrive before the forwarder is connected and get lost, so
      # once connected send our own ping: a delivery that comes back proves the whole path.
      if grep -q '^Forwarding' "$RUN_DIR/$slug.err" 2>/dev/null; then
        wh_ping "$repo"
        WH_STATE[$i]=pinged
        WH_SINCE[$i]=$now
      elif [ $((now - WH_SINCE[$i])) -ge "$WEBHOOK_CONNECT_WAIT" ]; then
        wh_log "$repo: forwarder did not connect in ${WEBHOOK_CONNECT_WAIT}s, polling every ${INTERVAL}s"
        wh_stop "$i"
        WH_STATE[$i]=failed
        WH_SINCE[$i]=$now
      fi
    elif [ "${WH_STATE[$i]}" = pinged ] && [ $((now - WH_SINCE[$i])) -ge "$WEBHOOK_PING_WAIT" ]; then
      wh_log "$repo: ping not delivered after ${WEBHOOK_PING_WAIT}s, polling every ${INTERVAL}s"
      wh_stop "$i"
      WH_STATE[$i]=failed
      WH_SINCE[$i]=$now
    fi
  done
}

# --- Main loop -------------------------------------------------------------------------

if [ "$RESET" = 1 ]; then
  for ref in "${REFS[@]}"; do rm -f "$(state_file "$ref")"; done
fi

# Per-PR state in parallel arrays: consecutive fetch failures, next check (epoch seconds),
# a pending re-check after a webhook trigger, and whether the PR is still followed.
FAILS_BY=(); NEXT_BY=(); RECHECK_BY=(); OPEN_BY=()
for i in "${!REFS[@]}"; do FAILS_BY[$i]=0; NEXT_BY[$i]=0; RECHECK_BY[$i]=0; OPEN_BY[$i]=1; done

if [ "$ONCE" = 0 ] && [ "$WEBHOOK" = 1 ]; then
  if gh extension list 2>/dev/null | grep -q 'gh-webhook'; then
    RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gh-follow.XXXXXX")
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    me_lower=$(echo "$ME" | tr '[:upper:]' '[:lower:]')
    for ref in "${REFS[@]}"; do
      repo="${ref%#*}"
      # Webhooks only on repos owned by the user: never on organizations or other people's
      # repos, even where the user is admin. Those are polled.
      if [ "$(echo "${repo%%/*}" | tr '[:upper:]' '[:lower:]')" != "$me_lower" ]; then
        wh_log "$repo: not owned by $ME, no webhook, polling every ${INTERVAL}s"
        continue
      fi
      seen=0
      for r in ${WH_REPOS[@]+"${WH_REPOS[@]}"}; do [ "$r" = "$repo" ] && seen=1; done
      [ "$seen" = 0 ] && WH_REPOS+=("$repo")
    done
    for ((i = 0; i < ${#WH_REPOS[@]}; i++)); do wh_start "$i"; done
  else
    wh_log "gh-webhook extension not installed (gh extension install cli/gh-webhook), polling every ${INTERVAL}s"
  fi
fi

while :; do
  now=$(date +%s)
  checked=0

  if [ -n "$RUN_DIR" ]; then
    # Redirect instead of a pipe: wh_poll must run in this shell to keep forwarder state.
    wh_poll > "$RUN_DIR/triggers"
    while IFS= read -r trig; do
      for i in "${!REFS[@]}"; do
        [ "${OPEN_BY[$i]}" = 1 ] || continue
        if [ "${REFS[$i]}" = "$trig" ] || [ "${REFS[$i]%#*}#*" = "$trig" ]; then
          # Give GitHub's API a moment to reflect the change, then re-check once more later
          # for state it computes lazily (merge status, review decision).
          [ "${NEXT_BY[$i]}" -gt $((now + 3)) ] && NEXT_BY[$i]=$((now + 3))
          RECHECK_BY[$i]=1
        fi
      done
    done < "$RUN_DIR/triggers"
  fi

  for i in "${!REFS[@]}"; do
    [ "${OPEN_BY[$i]}" = 1 ] || continue
    [ "${NEXT_BY[$i]}" -le "$now" ] || continue
    FAILS=${FAILS_BY[$i]}
    check_pr "${REFS[$i]}" || OPEN_BY[$i]=0
    FAILS_BY[$i]=$FAILS
    checked=1
    if [ "${RECHECK_BY[$i]}" = 1 ]; then
      NEXT_BY[$i]=$((now + 30)); RECHECK_BY[$i]=0
    elif repo_live "${REFS[$i]%#*}"; then
      NEXT_BY[$i]=$((now + SAFETY_INTERVAL))
    else
      NEXT_BY[$i]=$((now + INTERVAL))
    fi
  done

  if [ "$checked" = 1 ]; then
    still=0
    for i in "${!REFS[@]}"; do [ "${OPEN_BY[$i]}" = 1 ] && still=1; done
    if [ "$still" = 0 ]; then
      echo "DONE every followed pull request is merged or closed"
      exit 0
    fi
    [ "$ONCE" = 1 ] && exit 0
    [ "$UNTIL_EVENT" = 1 ] && [ "$GOT_EVENT" = 1 ] && exit 0
  fi

  sleep 2
done
