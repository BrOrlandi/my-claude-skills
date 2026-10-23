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
#   --interval <seconds>   Poll interval (default 60)
#   --once                 Check once, print what changed since the last check, exit
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
# State is kept per PR in ${XDG_CACHE_HOME:-~/.cache}/gh-follow/, so a restarted follow
# reports what happened while it was not running instead of starting blind.

set -uo pipefail

INTERVAL=60
ONCE=0
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
    --once) ONCE=1 ;;
    --auto-merge) AUTO_MERGE=1 ;;
    --merge-method) MERGE_METHOD="$2"; shift ;;
    --delete-branch) DELETE_BRANCH=1 ;;
    --include-self) INCLUDE_SELF=1 ;;
    --notify) NOTIFY=1 ;;
    --reset) RESET=1 ;;
    -h|--help) sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# --- Main loop -------------------------------------------------------------------------

if [ "$RESET" = 1 ]; then
  for ref in "${REFS[@]}"; do rm -f "$(state_file "$ref")"; done
fi

# Per-PR consecutive failure counters, kept in a parallel array (bash 3.2 has no maps).
FAILS_BY=()
for i in "${!REFS[@]}"; do FAILS_BY[$i]=0; done

while :; do
  ACTIVE=()
  ACTIVE_FAILS=()
  for i in "${!REFS[@]}"; do
    FAILS=${FAILS_BY[$i]}
    if check_pr "${REFS[$i]}"; then
      ACTIVE+=("${REFS[$i]}")
      ACTIVE_FAILS+=("$FAILS")
    fi
  done

  if [ ${#ACTIVE[@]} -eq 0 ]; then
    echo "DONE every followed pull request is merged or closed"
    exit 0
  fi
  [ "$ONCE" = 1 ] && exit 0

  REFS=("${ACTIVE[@]}")
  FAILS_BY=("${ACTIVE_FAILS[@]}")
  sleep "$INTERVAL"
done
