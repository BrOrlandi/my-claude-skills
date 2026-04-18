#!/bin/bash
# Remove symlinks from ~/.claude/ that point to this repo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"
CLAUDE_DIR="$HOME/.claude"

# Remove skill symlinks
for skill_dir in "$SCRIPT_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"

  [[ "$skill_name" == .* ]] && continue
  [[ "$skill_name" == "commands" ]] && continue
  [[ "$skill_name" == "statusline" ]] && continue
  [ ! -f "$skill_dir/SKILL.md" ] && continue

  target="$SKILLS_DIR/$skill_name"

  if [ -L "$target" ]; then
    rm "$target"
    echo "Removed skill: $target"
  fi
done

# Remove command symlinks
if [ -d "$SCRIPT_DIR/commands" ]; then
  for cmd_file in "$SCRIPT_DIR"/commands/*.md; do
    [ ! -f "$cmd_file" ] && continue
    cmd_name="$(basename "$cmd_file")"
    target="$COMMANDS_DIR/$cmd_name"

    if [ -L "$target" ]; then
      rm "$target"
      echo "Removed command: $target"
    fi
  done
fi

# Remove statusline symlink
STATUSLINE_SRC="$SCRIPT_DIR/statusline/statusline.js"
STATUSLINE_TARGET="$CLAUDE_DIR/statusline.js"

if [ -L "$STATUSLINE_TARGET" ] && [ "$(readlink "$STATUSLINE_TARGET")" = "$STATUSLINE_SRC" ]; then
  rm "$STATUSLINE_TARGET"
  echo "Removed statusline: $STATUSLINE_TARGET"
fi

# Remove third-party skill symlinks
JSON_FILE="$SCRIPT_DIR/thirdparty-skills.json"

if [ -f "$JSON_FILE" ]; then
  count=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(len(data))")

  for i in $(seq 0 $((count - 1))); do
    name=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(data[$i]['name'])")
    target="$SKILLS_DIR/$name"

    if [ -L "$target" ]; then
      rm "$target"
      echo "Removed third-party skill: $target"
    fi
  done
fi

echo ""
echo "Done! Symlinks removed."
