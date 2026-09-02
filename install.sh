#!/bin/bash
# Install all skills and commands as symlinks in ~/.claude/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$HOME/.claude/hooks"

GREEN='\033[0;32m'
NC='\033[0m'

# Install skills
mkdir -p "$SKILLS_DIR"

skills_already_installed=0

for skill_dir in "$SCRIPT_DIR"/*/; do
  skill_name="$(basename "$skill_dir")"

  # Skip hidden directories, non-skill dirs, and dirs without SKILL.md
  [[ "$skill_name" == .* ]] && continue
  [[ "$skill_name" == "commands" ]] && continue
  [[ "$skill_name" == "statusline" ]] && continue
  [[ "$skill_name" == "hooks" ]] && continue
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

# Install statusline
STATUSLINE_SRC="$SCRIPT_DIR/statusline/statusline.js"
STATUSLINE_TARGET="$CLAUDE_DIR/statusline.js"

if [ -f "$STATUSLINE_SRC" ]; then
  mkdir -p "$CLAUDE_DIR"

  if [ -L "$STATUSLINE_TARGET" ] && [ "$(readlink "$STATUSLINE_TARGET")" = "$STATUSLINE_SRC" ]; then
    echo "Statusline already installed."
  elif [ -e "$STATUSLINE_TARGET" ] && [ ! -L "$STATUSLINE_TARGET" ]; then
    echo "Skipping statusline (file already exists at $STATUSLINE_TARGET, not a symlink)"
  else
    [ -L "$STATUSLINE_TARGET" ] && rm "$STATUSLINE_TARGET"
    ln -s "$STATUSLINE_SRC" "$STATUSLINE_TARGET"
    echo -e "${GREEN}Statusline installed at $STATUSLINE_TARGET${NC}"
    echo "  Add this to ~/.claude/settings.json to enable it:"
    echo '    "statusLine": { "type": "command", "command": "node '"$STATUSLINE_TARGET"'" }'
  fi
fi

# Install hook scripts
HOOK_SCRIPTS_SRC="$SCRIPT_DIR/hooks/scripts"

if [ -d "$HOOK_SCRIPTS_SRC" ]; then
  mkdir -p "$HOOKS_DIR"

  hooks_already_installed=0

  for hook_file in "$HOOK_SCRIPTS_SRC"/*.sh; do
    [ ! -f "$hook_file" ] && continue
    hook_name="$(basename "$hook_file")"
    target="$HOOKS_DIR/$hook_name"

    if [ -L "$target" ]; then
      if [ "$(readlink "$target")" = "$hook_file" ]; then
        hooks_already_installed=$((hooks_already_installed + 1))
        continue
      fi
      rm "$target"
    elif [ -f "$target" ]; then
      echo "Skipping hook $hook_name (file already exists, not a symlink)"
      continue
    fi

    ln -s "$hook_file" "$target"
    echo -e "${GREEN}New Hook script installed $hook_name!${NC}"
  done

  [ $hooks_already_installed -gt 0 ] && echo "All other hook scripts already installed."
fi

# Install sounds
SOUNDS_SRC="$SCRIPT_DIR/hooks/sounds"
SOUNDS_TARGET="$CLAUDE_DIR/sounds"

if [ -d "$SOUNDS_SRC" ]; then
  sounds_already_installed=0

  while IFS= read -r sound_file; do
    rel="${sound_file#$SOUNDS_SRC/}"
    target="$SOUNDS_TARGET/$rel"

    mkdir -p "$(dirname "$target")"

    if [ -L "$target" ]; then
      if [ "$(readlink "$target")" = "$sound_file" ]; then
        sounds_already_installed=$((sounds_already_installed + 1))
        continue
      fi
      rm "$target"
    elif [ -f "$target" ]; then
      echo "Skipping sound $rel (file already exists, not a symlink)"
      continue
    fi

    ln -s "$sound_file" "$target"
    echo -e "${GREEN}New Sound installed $rel!${NC}"
  done < <(find "$SOUNDS_SRC" -type f -name '*.wav')

  [ $sounds_already_installed -gt 0 ] && echo "All other sounds already installed."
fi

# Install third-party skills
JSON_FILE="$SCRIPT_DIR/thirdparty-skills.json"

if [ -f "$JSON_FILE" ]; then
  tp_already_installed=0
  count=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(len(data))")

  for i in $(seq 0 $((count - 1))); do
    name=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(data[$i]['name'])")
    path=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(data[$i]['path'])")
    skill_dir=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(data[$i]['skill_dir'])")

    if [ "$skill_dir" = "." ]; then
      full_path="$SCRIPT_DIR/$path"
    else
      full_path="$SCRIPT_DIR/$path/$skill_dir"
    fi

    if [ ! -d "$full_path" ] || [ ! -f "$full_path/SKILL.md" ]; then
      echo "Skipping third-party skill $name (not cloned yet, run ./update-thirdparty.sh)"
      continue
    fi

    target="$SKILLS_DIR/$name"

    # Ensure full_path ends with /
    full_path="${full_path%/}/"

    if [ -L "$target" ]; then
      if [ "$(readlink "$target")" = "$full_path" ]; then
        tp_already_installed=$((tp_already_installed + 1))
        continue
      fi
      rm "$target"
    elif [ -d "$target" ]; then
      echo "Skipping $name (directory already exists, not a symlink)"
      continue
    fi

    ln -s "$full_path" "$target"
    echo -e "${GREEN}New Third-party Skill installed $name!${NC}"
  done

  [ $tp_already_installed -gt 0 ] && echo "All other third-party skills already installed."
fi

echo ""
echo "Done! Skills and commands are now available globally in Claude Code."
echo "Hook scripts and sounds are linked, but stay inactive until you wire them up in"
echo "~/.claude/settings.json - see hooks/README.md (or run the interactive install prompt"
echo "from the README, which does it for you)."
