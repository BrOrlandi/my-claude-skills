#!/bin/bash
# Poll a GitHub PR for new CodeRabbit review comments after a push.
#
# Usage: poll-pr-comments.sh <owner> <repo> <pr_number>
#
# Output (stdout, last line):
#   NEW_COMMENTS:<count>  — CodeRabbit finished and left open threads
#   ALL_CLEAR             — CodeRabbit finished with no open threads
#   TIMEOUT               — 10-minute timeout reached (exit 1)

set -euo pipefail

OWNER="$1"
REPO="$2"
PR_NUMBER="$3"
MAX_WAIT=600   # 10 minutes
INTERVAL=15    # start at 15s, increase progressively
INTERVAL_STEP=10
INTERVAL_CAP=60
ELAPSED=0
STATUS_CHECKS=0

GRAPHQL_QUERY='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
        }
      }
    }
  }
}'

while [ $ELAPSED -lt $MAX_WAIT ]; do
  # Get latest commit SHA for the PR
  HEAD_SHA=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid -q '.headRefOid' 2>/dev/null || echo "")

  if [ -z "$HEAD_SHA" ]; then
    echo "ERROR: Could not fetch PR head SHA"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
    continue
  fi

  # Check CodeRabbit status on the latest commit
  CR_STATE=$(gh api "repos/$OWNER/$REPO/commits/$HEAD_SHA/status" \
    --jq '.statuses[] | select(.context | test("coderabbit"; "i")) | .state' 2>/dev/null || echo "")

  STATUS_CHECKS=$((STATUS_CHECKS + 1))

  # Fallback: if no commit status found after 3 checks, look for a CodeRabbit review directly
  if [ -z "$CR_STATE" ] && [ "$STATUS_CHECKS" -ge 3 ]; then
    CR_REVIEW_STATE=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
      --jq '[.[] | select(.user.login == "coderabbitai[bot]")] | sort_by(.submitted_at) | last | .state' 2>/dev/null || echo "")
    if [ "$CR_REVIEW_STATE" = "COMMENTED" ] || [ "$CR_REVIEW_STATE" = "CHANGES_REQUESTED" ] || [ "$CR_REVIEW_STATE" = "APPROVED" ]; then
      CR_STATE="success"
    fi
  fi

  if [ "$CR_STATE" = "success" ]; then
    # CodeRabbit finished — count open, non-outdated review threads
    OPEN_COUNT=$(gh api graphql \
      -f query="$GRAPHQL_QUERY" \
      -f owner="$OWNER" \
      -f repo="$REPO" \
      -F number="$PR_NUMBER" \
      --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false and .isOutdated == false)] | length' 2>/dev/null || echo "0")

    if [ "$OPEN_COUNT" -gt 0 ]; then
      echo "NEW_COMMENTS:$OPEN_COUNT"
      exit 0
    else
      echo "ALL_CLEAR"
      exit 0
    fi
  fi

  # Still pending or no status yet — wait and retry with progressive backoff
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
  INTERVAL=$((INTERVAL + INTERVAL_STEP))
  if [ "$INTERVAL" -gt "$INTERVAL_CAP" ]; then
    INTERVAL=$INTERVAL_CAP
  fi
done

echo "TIMEOUT"
exit 1
