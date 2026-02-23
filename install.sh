#!/bin/bash
# Install all skills and commands as symlinks in ~/.claude/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"

GREEN='\033[0;32m'
NC='\033[0m'

# Install skills
mkdir -p "$SKILLS_DIR"

skills_already_installed=0

for skill_dir in "$SCRIPT_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"

  # Skip hidden directories, commands dir, and non-skill dirs
  [[ "$skill_name" == .* ]] && continue
  [[ "$skill_name" == "commands" ]] && continue
  [ ! -f "$skill_dir/SKILL.md" ] && continue

  target="$SKILLS_DIR/$skill_name"

  if [ -L "$target" ]; then
    if [ "$(readlink "$target")" = "$skill_dir" ]; then
      skills_already_installed=$((skills_already_installed + 1))
      continue
    fi
    rm "$target"
  elif [ -d "$target" ]; then
    echo "Skipping $skill_name (directory already exists, not a symlink)"
    continue
  fi

  ln -s "$skill_dir" "$target"
  echo -e "${GREEN}New Skill installed $skill_name!${NC}"
done

[ $skills_already_installed -gt 0 ] && echo "All other skills already installed."

# Install commands
if [ -d "$SCRIPT_DIR/commands" ]; then
  mkdir -p "$COMMANDS_DIR"

  cmds_already_installed=0

  for cmd_file in "$SCRIPT_DIR"/commands/*.md; do
    [ ! -f "$cmd_file" ] && continue
    cmd_name="$(basename "$cmd_file")"
    target="$COMMANDS_DIR/$cmd_name"

    if [ -L "$target" ]; then
      if [ "$(readlink "$target")" = "$cmd_file" ]; then
        cmds_already_installed=$((cmds_already_installed + 1))
        continue
      fi
      rm "$target"
    elif [ -f "$target" ]; then
      echo "Skipping $cmd_name (file already exists, not a symlink)"
      continue
    fi

    ln -s "$cmd_file" "$target"
    echo -e "${GREEN}New Command installed $cmd_name!${NC}"
  done

  [ $cmds_already_installed -gt 0 ] && echo "All other commands already installed."
fi

echo ""
echo "Done! Skills and commands are now available globally in Claude Code."
