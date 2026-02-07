#!/bin/bash
# Remove symlinks from ~/.claude/ that point to this repo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"

# Remove skill symlinks
for skill_dir in "$SCRIPT_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"

  [[ "$skill_name" == .* ]] && continue
  [[ "$skill_name" == "commands" ]] && continue
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

echo ""
echo "Done! Symlinks removed."
