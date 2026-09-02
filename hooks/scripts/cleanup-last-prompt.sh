#!/usr/bin/env bash
# SessionEnd hook: remove last-prompt file for this session.

set -e
DIR="$HOME/.claude/last-prompts"
sid=$(jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0
rm -f "$DIR/$sid.txt"
