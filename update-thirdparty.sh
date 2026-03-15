#!/bin/bash
# Update all third-party skill repositories by pulling latest changes

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON_FILE="$SCRIPT_DIR/thirdparty-skills.json"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ ! -f "$JSON_FILE" ]; then
  echo "No thirdparty-skills.json found."
  exit 1
fi

# Parse JSON entries (requires python3 for reliable JSON parsing)
count=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(len(data))")

for i in $(seq 0 $((count - 1))); do
  name=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(data[$i]['name'])")
  path=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(data[$i]['path'])")
  repo=$(python3 -c "import json; data=json.load(open('$JSON_FILE')); print(data[$i]['repo'])")

  full_path="$SCRIPT_DIR/$path"

  if [ -d "$full_path/.git" ]; then
    echo "Updating $name..."
    if git -C "$full_path" pull --ff-only; then
      echo -e "${GREEN}Updated $name${NC}"
    else
      echo -e "${RED}Failed to update $name (may have local changes or diverged)${NC}"
    fi
  else
    echo "Cloning $name..."
    mkdir -p "$(dirname "$full_path")"
    if git clone "$repo" "$full_path"; then
      echo -e "${GREEN}Cloned $name${NC}"
    else
      echo -e "${RED}Failed to clone $name${NC}"
    fi
  fi

  echo ""
done

echo "Done! All third-party skills are up to date."
