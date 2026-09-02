#!/usr/bin/env bash
# UserPromptSubmit hook: save last prompt indexed by session_id.
# Statusline reads ~/.claude/last-prompts/<session_id>.txt.

set -e
DIR="$HOME/.claude/last-prompts"
mkdir -p "$DIR"

payload=$(cat)
sid=$(printf '%s' "$payload" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0

printf '%s' "$payload" | jq -r '.prompt // empty' > "$DIR/$sid.txt"
