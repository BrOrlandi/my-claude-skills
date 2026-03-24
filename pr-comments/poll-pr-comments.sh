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
INTERVAL=30
ELAPSED=0

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

  # Still pending or no status yet — wait and retry
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "TIMEOUT"
exit 1
