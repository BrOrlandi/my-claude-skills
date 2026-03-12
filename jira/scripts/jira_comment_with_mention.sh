#!/bin/bash
# Add a Jira comment with proper user mentions (ADF format)
# Usage: jira_comment_with_mention.sh <ISSUE_KEY> <ACCOUNT_ID> <DISPLAY_NAME> <COMMENT_TEXT>
#
# The jira CLI does not support @mentions natively. This script uses the
# Jira REST API v3 with ADF (Atlassian Document Format) to create comments
# that properly mention and notify users.
#
# Authentication (checked in order):
# 1. Environment variables: JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN
# 2. jira CLI config (~/.config/.jira/.config.yml) for server/login + JIRA_API_TOKEN env var

set -euo pipefail

ISSUE_KEY="${1:?Usage: $0 <ISSUE_KEY> <ACCOUNT_ID> <DISPLAY_NAME> <COMMENT_TEXT>}"
ACCOUNT_ID="${2:?Missing ACCOUNT_ID}"
DISPLAY_NAME="${3:?Missing DISPLAY_NAME}"
COMMENT_TEXT="${4:?Missing COMMENT_TEXT}"

# Resolve credentials
# Try explicit env vars first
if [ -n "${JIRA_URL:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ]; then
  JIRA_URL="${JIRA_URL%/}"
# Fall back to jira CLI config + JIRA_API_TOKEN
else
  JIRA_CONFIG="${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"
  if [ ! -f "$JIRA_CONFIG" ]; then
    echo "Error: No jira CLI config found at $JIRA_CONFIG" >&2
    echo "Run 'jira init' to configure, or set JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN env vars." >&2
    exit 1
  fi

  JIRA_URL=$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)
print(cfg.get('server', '').rstrip('/'))
" "$JIRA_CONFIG")

  JIRA_EMAIL=$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)
print(cfg.get('login', ''))
" "$JIRA_CONFIG")

  : "${JIRA_API_TOKEN:?JIRA_API_TOKEN env var is required. Get one at https://id.atlassian.com/manage-profile/security/api-tokens}"

  if [ -z "$JIRA_URL" ] || [ -z "$JIRA_EMAIL" ]; then
    echo "Error: Could not read server/login from $JIRA_CONFIG" >&2
    exit 1
  fi
fi

# Build ADF body with mention node
BODY=$(python3 -c "
import json, sys
body = {
    'body': {
        'type': 'doc',
        'version': 1,
        'content': [{
            'type': 'paragraph',
            'content': [
                {
                    'type': 'mention',
                    'attrs': {
                        'id': sys.argv[1],
                        'text': '@' + sys.argv[2],
                        'accessLevel': ''
                    }
                },
                {
                    'type': 'text',
                    'text': ' ' + sys.argv[3]
                }
            ]
        }]
    }
}
print(json.dumps(body))
" "$ACCOUNT_ID" "$DISPLAY_NAME" "$COMMENT_TEXT")

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}/comment" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "Comment added to ${ISSUE_KEY} with mention to @${DISPLAY_NAME}"
  echo "$RESPONSE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"Comment ID: {d['id']}\")" 2>/dev/null || true
else
  echo "Error (HTTP ${HTTP_CODE}):" >&2
  echo "$RESPONSE_BODY" >&2
  exit 1
fi
