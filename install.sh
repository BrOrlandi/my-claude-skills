#!/bin/bash
# Install all skills and commands as symlinks in ~/.claude/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"

# Install skills
mkdir -p "$SKILLS_DIR"

for skill_dir in "$SCRIPT_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"

  # Skip hidden directories, commands dir, and non-skill dirs
  [[ "$skill_name" == .* ]] && continue
  [[ "$skill_name" == "commands" ]] && continue
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
  echo "Linked skill: $skill_name -> $target"
done

# Install commands
if [ -d "$SCRIPT_DIR/commands" ]; then
  mkdir -p "$COMMANDS_DIR"

  for cmd_file in "$SCRIPT_DIR"/commands/*.md; do
    [ ! -f "$cmd_file" ] && continue
    cmd_name="$(basename "$cmd_file")"
    target="$COMMANDS_DIR/$cmd_name"

    if [ -L "$target" ]; then
      echo "Updating symlink: $cmd_name"
      rm "$target"
    elif [ -f "$target" ]; then
      echo "Skipping $cmd_name (file already exists, not a symlink)"
      continue
    fi

    ln -s "$cmd_file" "$target"
    echo "Linked command: $cmd_name -> $target"
  done
fi

echo ""
echo "Done! Skills and commands are now available globally in Claude Code."
