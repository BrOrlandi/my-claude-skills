#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CONFIG_DIR/config.toml"
STATUS_LINE='["project-name", "git-branch", "model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit"]'

mkdir -p "$CONFIG_DIR"
touch "$CONFIG_FILE"

backup="$CONFIG_FILE.bak-statusline-$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$backup"

CONFIG_FILE="$CONFIG_FILE" STATUS_LINE="$STATUS_LINE" python3 - <<'PY'
from pathlib import Path
import os
import re

path = Path(os.environ["CONFIG_FILE"])
status_line = os.environ["STATUS_LINE"]
text = path.read_text()

line = f"status_line = {status_line}"

section_re = re.compile(r"(?m)^\[tui\]\s*$")
match = section_re.search(text)

if not match:
    if text and not text.endswith("\n"):
        text += "\n"
    text += f"\n[tui]\n{line}\n"
else:
    start = match.end()
    next_section = re.search(r"(?m)^\[[^\]]+\]\s*$", text[start:])
    end = start + next_section.start() if next_section else len(text)
    body = text[start:end]

    status_re = re.compile(r"(?m)^status_line\s*=.*$")
    if status_re.search(body):
        body = status_re.sub(line, body, count=1)
    else:
        if body and not body.endswith("\n"):
            body += "\n"
        body += f"{line}\n"

    text = text[:start] + body + text[end:]

path.write_text(text)
PY

echo "Updated $CONFIG_FILE"
echo "Backup: $backup"
echo "Restart Codex to see the status line."
