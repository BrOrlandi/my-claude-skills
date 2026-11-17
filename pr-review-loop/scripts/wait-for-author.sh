#!/bin/bash
# Wait until someone answers a review: a new commit, a human comment or review, a reaction on one of the
# reviewer's comments, a re-request of the reviewer's review, or the PR leaving the OPEN state.
#
# Usage: wait-for-author.sh <owner> <repo> <pr_number> <reviewer_login> <since_iso_utc>
#   since_iso_utc: when the reviewer's last review was posted (e.g. 2026-11-17T21:12:41Z). Only activity
#                  after it counts.
#
# Environment (all optional):
#   MAX_WAIT  seconds before giving up            (default 86400 = 24h)
#   INTERVAL  seconds between polls               (default 60)
#   QUIET     seconds with no further change before reporting, so a burst of pushes and replies is
#             answered once, not once per event   (default 180)
#
# Output (stdout, last line):
#   ACTIVITY:<kinds>   comma-separated: push, comment, reaction, rerequest (a new request only)
#   CLOSED:<state>     MERGED or CLOSED
#   TIMEOUT            MAX_WAIT reached with no activity (exit 1)

set -uo pipefail

OWNER="$1"
REPO="$2"
PR="$3"
ME="$4"
SINCE="$5"
MAX_WAIT="${MAX_WAIT:-86400}"
INTERVAL="${INTERVAL:-60}"
QUIET="${QUIET:-180}"
API="repos/$OWNER/$REPO"

# Sum the numbers printed one per line (gh --paginate prints one result per page).
sum() { awk '{ s += $1 } END { print s + 0 }'; }

# Human activity after $SINCE that is not the reviewer's own and not a bot's.
# gh's --jq takes no --arg, so the login is spliced in (GitHub logins are [A-Za-z0-9-] only).
HUMAN_AFTER="select(.user.login != \"$ME\" and .user.type != \"Bot\")"

snapshot() {
  local view state head rerequest comments issue_comments reviews reactions
  view=$(gh pr view "$PR" --repo "$OWNER/$REPO" --json state,headRefOid,reviewRequests 2>/dev/null) || return 1
  state=$(jq -r '.state' <<<"$view")
  head=$(jq -r '.headRefOid' <<<"$view")
  rerequest=$(jq -r --arg me "$ME" '[.reviewRequests[]? | select(.login == $me)] | length' <<<"$view")

  comments=$(gh api --paginate "$API/pulls/$PR/comments" \
    --jq "[.[] | $HUMAN_AFTER | select(.created_at > \"$SINCE\")] | length" 2>/dev/null | sum) || return 1
  issue_comments=$(gh api --paginate "$API/issues/$PR/comments" \
    --jq "[.[] | $HUMAN_AFTER | select(.created_at > \"$SINCE\")] | length" 2>/dev/null | sum) || return 1
  reviews=$(gh api --paginate "$API/pulls/$PR/reviews" \
    --jq "[.[] | $HUMAN_AFTER | select(.submitted_at > \"$SINCE\")] | length" 2>/dev/null | sum) || return 1
  reactions=$(gh api --paginate "$API/pulls/$PR/comments" \
    --jq "[.[] | select(.user.login == \"$ME\") | .reactions.total_count] | add // 0" 2>/dev/null | sum) || return 1

  echo "$state $head $((comments + issue_comments + reviews)) $reactions $rerequest"
}

# The kinds of change between two snapshots.
kinds() {
  local -a a b out=()
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  [ "${a[1]}" != "${b[1]}" ] && out+=(push)
  [ "${a[2]}" != "${b[2]}" ] && out+=(comment)
  [ "${a[3]}" != "${b[3]}" ] && out+=(reaction)
  [ "${b[4]}" -gt 0 ] && [ "${a[4]}" = 0 ] && out+=(rerequest)
  (IFS=,; echo "${out[*]-}")
}

ELAPSED=0
BASE=""
until BASE=$(snapshot); do
  # GitHub unreachable or rate limited: back off, and count it against MAX_WAIT.
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
  [ "$ELAPSED" -ge "$MAX_WAIT" ] && { echo "TIMEOUT"; exit 1; }
done
# Human comments already posted after $SINCE (the author answered before the wait started) count as
# activity. A review request that is already there does not: it may be one this loop already answered.
read -r -a base_parts <<<"$BASE"
LAST="$BASE"
CHANGED_AT=-1
[ "${base_parts[2]}" -gt 0 ] && CHANGED_AT=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  if [ "$CHANGED_AT" -lt 0 ] || [ $((ELAPSED - CHANGED_AT)) -lt "$QUIET" ]; then
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  fi

  if ! NOW=$(snapshot); then
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
    continue
  fi
  read -r -a now_parts <<<"$NOW"

  if [ "${now_parts[0]}" != "OPEN" ]; then
    echo "CLOSED:${now_parts[0]}"
    exit 0
  fi

  if [ "$NOW" != "$LAST" ]; then
    LAST="$NOW"
    CHANGED_AT=$ELAPSED
    echo "change seen at ${ELAPSED}s: $(kinds "$BASE" "$NOW"); waiting ${QUIET}s for it to settle" >&2
    continue
  fi

  if [ "$CHANGED_AT" -ge 0 ] && [ $((ELAPSED - CHANGED_AT)) -ge "$QUIET" ]; then
    K=$(kinds "$BASE" "$NOW")
    if [ -z "$K" ]; then
      if [ "${base_parts[2]}" -gt 0 ]; then
        K="comment" # answered before the wait started
      else
        CHANGED_AT=-1 # the change undid itself (a reaction added and removed): keep waiting
        continue
      fi
    fi
    echo "ACTIVITY:$K"
    exit 0
  fi
done

echo "TIMEOUT"
exit 1
