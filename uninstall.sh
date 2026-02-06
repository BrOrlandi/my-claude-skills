#!/bin/bash
# Remove symlinks from ~/.claude/skills/ that point to this repo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

for skill_dir in "$SCRIPT_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"

  [[ "$skill_name" == .* ]] && continue
  [ ! -f "$skill_dir/SKILL.md" ] && continue

  target="$SKILLS_DIR/$skill_name"

  if [ -L "$target" ]; then
    rm "$target"
    echo "Removed: $target"
  fi
done

echo ""
echo "Done! Symlinks removed."
