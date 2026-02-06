#!/bin/bash
# Install all skills as symlinks in ~/.claude/skills/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

mkdir -p "$SKILLS_DIR"

for skill_dir in "$SCRIPT_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"

  # Skip hidden directories and non-skill dirs
  [[ "$skill_name" == .* ]] && continue
  [ ! -f "$skill_dir/SKILL.md" ] && continue

  target="$SKILLS_DIR/$skill_name"

  if [ -L "$target" ]; then
    echo "Updating symlink: $skill_name"
    rm "$target"
  elif [ -d "$target" ]; then
    echo "Skipping $skill_name (directory already exists, not a symlink)"
    continue
  fi

  ln -s "$skill_dir" "$target"
  echo "Linked: $skill_name -> $target"
done

echo ""
echo "Done! Skills are now available globally in Claude Code."
