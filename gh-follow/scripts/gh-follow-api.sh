#!/usr/bin/env bash
# Client for the GH-follow service (https://gh-follow.brorlandi.xyz). The service follows the
# registered PRs and merges authorized ones; this machine only registers and queries.
#
# Usage: gh-follow-api.sh <command> [args]
#
#   status                         Service status (GitHub login on the server, merges on/off)
#   follow <PR ...>                Register PRs (URL, owner/repo#N, or N in the current repo)
#   unfollow <PR>                  Stop following a PR
#   list                           Followed PRs, one line each
#   show <PR>                      One PR as JSON (including authorization blockers)
#   authorize <PR> [--method squash|merge|rebase] [--checks all|required|names]
#             [--check-name NAME ...] [--head SHA]
#                                  Authorize merging the PR at its current HEAD (read locally
#                                  with gh, or --head). Prints the SHA that was authorized.
#   revoke <PR>                    Revoke the PR's authorization
#   events [--since ID]            Events after ID (default: after the saved cursor)
#   watch [--interval S] [--until-event]
#                                  Print new events as they arrive (polls the service, never
#                                  GitHub). With --until-event, exit after the first batch.
#
# Config: ${GH_FOLLOW_CONFIG:-~/.claude/skills/gh-follow/config.json} with "service_url" and
# "api_token". Exit code 3 when the config is missing (the skill then uses the local watcher).
# The event cursor is kept in ${XDG_CACHE_HOME:-~/.cache}/gh-follow/service-cursor.

set -uo pipefail

CONFIG="${GH_FOLLOW_CONFIG:-$HOME/.claude/skills/gh-follow/config.json}"
CURSOR_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/gh-follow/service-cursor"

if [ ! -f "$CONFIG" ]; then
  echo "NO_CONFIG $CONFIG not found" >&2
  exit 3
fi
URL=$(jq -r '.service_url // empty' "$CONFIG" | sed 's:/*$::')
TOKEN=$(jq -r '.api_token // empty' "$CONFIG")
if [ -z "$URL" ] || [ -z "$TOKEN" ]; then
  echo "NO_CONFIG service_url or api_token missing in $CONFIG" >&2
  exit 3
fi

# The token goes to curl through a header file, never on the command line (ps would show it).
HDR=$(mktemp)
trap 'rm -f "$HDR"' EXIT
chmod 600 "$HDR"
printf 'Authorization: Bearer %s\n' "$TOKEN" > "$HDR"

api() {
  local method="$1" path="$2" body="${3:-}" out code
  if [ -n "$body" ]; then
    out=$(curl -sS -X "$method" -H @"$HDR" -H 'Content-Type: application/json' --data "$body" -w '\n%{http_code}' "$URL$path") || return 1
  else
    out=$(curl -sS -X "$method" -H @"$HDR" -w '\n%{http_code}' "$URL$path") || return 1
  fi
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  if [ "${code:0:1}" != "2" ]; then
    echo "ERROR HTTP $code: $(jq -r '.error // .' <<< "$out" 2>/dev/null || echo "$out")" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

# PR reference → owner/repo#N
resolve() {
  local arg="$1" repo
  if [[ "$arg" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}#${BASH_REMATCH[3]}"
  elif [[ "$arg" =~ ^([^/#]+)/([^/#]+)#([0-9]+)$ ]]; then
    echo "$arg"
  elif [[ "$arg" =~ ^#?([0-9]+)$ ]]; then
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || { echo "ERROR cannot resolve '$arg' outside a GitHub repo" >&2; return 1; }
    echo "$repo#${BASH_REMATCH[1]}"
  else
    echo "ERROR unrecognized PR reference: $arg" >&2
    return 1
  fi
}

path_of() {
  local ref="$1"
  echo "/api/prs/${ref%%/*}/$(echo "${ref#*/}" | cut -d'#' -f1)/${ref##*#}"
}

LINE_JQ='"\(.ref) \(.status) review=\(.review_decision // "none") checks=\(.checks // "?") merge=\(.merge_state // "?") head=\((.head_sha // "?")[0:7])" + (if .authorization then " authorized=\(.authorization.head_sha[0:7]) \(.authorization.merge_method) checks:\(.authorization.checks)" + (if (.authorization.blockers | length) > 0 then " waiting: " + (.authorization.blockers | join("; ")) else " ready" end) else "" end) + " \(.url)"'

print_events() {
  jq -r '.events[] | "\(.type) \(.message)"'
}

save_cursor() {
  local last
  last=$(jq -r '[.events[].id] | max // empty')
  if [ -n "$last" ]; then
    mkdir -p "$(dirname "$CURSOR_FILE")"
    echo "$last" > "$CURSOR_FILE"
  fi
}

cmd="${1:-}"
shift || true

case "$cmd" in
  status)
    api GET /api/status | jq -r '"github=\(.github_status)\(if .github_login then " (" + .github_login + ")" else "" end) merges=\(if .merges_enabled then "enabled" else "disabled (dry run)" end) followed=\(.followed)"'
    ;;
  follow)
    [ $# -gt 0 ] || { echo "usage: follow <PR ...>" >&2; exit 2; }
    for arg in "$@"; do
      ref=$(resolve "$arg") || exit 2
      api POST /api/prs "$(jq -nc --arg ref "$ref" '{ref: $ref}')" | jq -r '"FOLLOWING \(.ref)"' || exit 1
    done
    ;;
  unfollow)
    ref=$(resolve "${1:?usage: unfollow <PR>}") || exit 2
    api DELETE "$(path_of "$ref")" > /dev/null && echo "UNFOLLOWED $ref"
    ;;
  list)
    api GET /api/prs | jq -r ".prs[] | $LINE_JQ"
    ;;
  show)
    ref=$(resolve "${1:?usage: show <PR>}") || exit 2
    api GET "$(path_of "$ref")" | jq .
    ;;
  authorize)
    ref=$(resolve "${1:?usage: authorize <PR> [--method m] [--checks p] [--check-name n] [--head sha]}") || exit 2
    shift
    method=squash checks=all head="" names=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --method) method="$2"; shift ;;
        --checks) checks="$2"; shift ;;
        --check-name) names+=("$2"); shift ;;
        --head) head="$2"; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
      esac
      shift
    done
    if [ -z "$head" ]; then
      head=$(gh pr view "${ref##*#}" --repo "${ref%#*}" --json headRefOid -q .headRefOid) || { echo "ERROR cannot read the HEAD of $ref" >&2; exit 1; }
    fi
    body=$(jq -nc --arg h "$head" --arg m "$method" --arg c "$checks" '{head_sha: $h, merge_method: $m, checks: $c, check_names: $ARGS.positional}' --args ${names[@]+"${names[@]}"})
    api POST "$(path_of "$ref")/authorize" "$body" | jq -r "\"AUTHORIZED \" + ($LINE_JQ)"
    ;;
  revoke)
    ref=$(resolve "${1:?usage: revoke <PR>}") || exit 2
    api POST "$(path_of "$ref")/revoke" | jq -r --arg ref "$ref" 'if .revoked then "REVOKED \($ref)" else "NO_AUTHORIZATION \($ref)" end'
    ;;
  events)
    since=""
    [ "${1:-}" = "--since" ] && since="${2:-0}"
    [ -z "$since" ] && since=$(cat "$CURSOR_FILE" 2>/dev/null || echo 0)
    out=$(api GET "/api/events?since=$since&limit=200") || exit 1
    print_events <<< "$out"
    save_cursor <<< "$out"
    ;;
  watch)
    interval=60 until_event=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --interval) interval="$2"; shift ;;
        --until-event) until_event=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
      esac
      shift
    done
    if [ ! -f "$CURSOR_FILE" ]; then
      # First watch: start from now instead of replaying history.
      out=$(api GET "/api/events?limit=1") && save_cursor <<< "$out"
    fi
    while :; do
      since=$(cat "$CURSOR_FILE" 2>/dev/null || echo 0)
      if out=$(api GET "/api/events?since=$since&limit=200"); then
        if [ "$(jq '.events | length' <<< "$out")" -gt 0 ]; then
          print_events <<< "$out"
          save_cursor <<< "$out"
          [ "$until_event" = 1 ] && exit 0
        fi
      fi
      sleep "$interval"
    done
    ;;
  *)
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
    [ -z "$cmd" ] && exit 0 || exit 2
    ;;
esac
