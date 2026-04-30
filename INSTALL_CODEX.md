# Install on Codex CLI

This repository was originally structured for Claude Code, but it can also be installed cleanly in Codex CLI.

In Codex, the setup is split into two parts:

- Skills are discovered from `~/.agents/skills/`
- Slash commands are exposed through a local plugin declared in `~/.agents/plugins/`

## What Gets Installed

### Skills

The top-level custom skills from this repository:

- `commit`
- `jira`
- `jira-link`
- `pr`
- `pr-comments`
- `pr-review`
- `pr-screenshots`
- `refactor-code`
- `refactor-components`
- `security-review`
- `slack`
- `todo-resolver`

Third-party skill from `thirdparty-skills.json`:

- `frontend-slides`

### Commands

This repository also contains Claude-style command files in `commands/`.

Important: in current `codex-cli` builds, local plugin installation can succeed, but plugin-provided slash commands are not surfaced in the `/` command popup the same way Claude Code commands are. In practice, use the `commit` and `pr` skills instead of relying on `/commit` or `/pr` appearing in Codex CLI.

## Prerequisites

- Codex CLI installed
- Git installed
- This repository cloned locally
- `python3` available

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/BrOrlandi/my-claude-skills.git ~/Projects/my-claude-skills
cd ~/Projects/my-claude-skills
```

### 2. Clone or update third-party skills

```bash
./update-thirdparty.sh
```

### 3. Install skills into Codex skill discovery

```bash
mkdir -p ~/.agents/skills

for skill_dir in "$PWD"/*/; do
  skill_name="$(basename "$skill_dir")"
  [[ "$skill_name" == .* ]] && continue
  [[ "$skill_name" == "commands" ]] && continue
  [ ! -f "$skill_dir/SKILL.md" ] && continue

  target="$HOME/.agents/skills/$skill_name"

  if [ -L "$target" ] || [ -e "$target" ]; then
    rm -f "$target"
  fi

  ln -s "$skill_dir" "$target"
done

if [ -f "$PWD/thirdparty/frontend-slides/SKILL.md" ]; then
  rm -f "$HOME/.agents/skills/frontend-slides"
  ln -s "$PWD/thirdparty/frontend-slides/" "$HOME/.agents/skills/frontend-slides"
fi
```

### 4. Optional: install commands as a local Codex plugin

This step installs the command bundle as a Codex plugin.

At the time of writing, Codex can recognize the plugin itself, but the TUI does not expose these command files in the `/` popup as first-class slash commands. Keep this as optional plumbing for future compatibility, not as a guaranteed working command UI.

Create the local plugin directory:

```bash
mkdir -p ~/.agents/plugins/.codex/plugins/my-claude-skills/.codex-plugin
```

Link the `commands/` directory from this repo:

```bash
rm -f ~/.agents/plugins/.codex/plugins/my-claude-skills/commands
ln -s "$PWD/commands" ~/.agents/plugins/.codex/plugins/my-claude-skills/commands
```

Create `~/.agents/plugins/.codex/plugins/my-claude-skills/.codex-plugin/plugin.json`:

```json
{
  "name": "my-claude-skills",
  "version": "1.0.0",
  "description": "Personal local commands sourced from the my-claude-skills repository.",
  "author": {
    "name": "Bruno Orlandi",
    "url": "https://github.com/BrOrlandi"
  },
  "homepage": "https://github.com/BrOrlandi/my-claude-skills",
  "repository": "https://github.com/BrOrlandi/my-claude-skills",
  "license": "MIT",
  "keywords": ["commands", "workflow", "git", "github"],
  "interface": {
    "displayName": "My Claude Skills",
    "shortDescription": "Personal slash commands for git and GitHub workflows",
    "longDescription": "Local plugin that exposes the personal command set from the my-claude-skills repository inside Codex.",
    "developerName": "Bruno Orlandi",
    "category": "Productivity",
    "capabilities": ["Interactive", "Write"],
    "websiteURL": "https://github.com/BrOrlandi/my-claude-skills",
    "privacyPolicyURL": "https://openai.com/policies/row-privacy-policy/",
    "termsOfServiceURL": "https://openai.com/policies/row-terms-of-use/",
    "defaultPrompt": [
      "Use /my-claude-skills:commit to prepare a structured commit",
      "Use /my-claude-skills:pr to create a pull request",
      "Use /my-claude-skills:sync-env-to-github to sync environment secrets"
    ],
    "brandColor": "#1F6FEB",
    "screenshots": []
  }
}
```

Create `~/.agents/plugins/marketplace.json`:

```json
{
  "name": "personal-local",
  "interface": {
    "displayName": "Personal Local Plugins"
  },
  "plugins": [
    {
      "name": "my-claude-skills",
      "source": {
        "source": "local",
        "path": "./.codex/plugins/my-claude-skills"
      },
      "policy": {
        "installation": "INSTALLED_BY_DEFAULT",
        "authentication": "ON_INSTALL"
      },
      "category": "Productivity"
    }
  ]
}
```

### 5. Enable the plugin in Codex

First, enable Codex's plugin feature:

```bash
codex features enable plugins
```

Add this block to `~/.codex/config.toml`:

```toml
[plugins."my-claude-skills@personal-local"]
enabled = true
```

You should also have this in the same file:

```toml
[features]
plugins = true
```

### 6. Restart Codex

Quit and reopen Codex CLI so it reloads:

- skills from `~/.agents/skills`
- local plugins from `~/.agents/plugins`

## Verify Installation

Check the skill symlinks:

```bash
find ~/.agents/skills -maxdepth 1 -mindepth 1 \( -type l -o -type d \) | sort
```

Check the plugin structure:

```bash
find ~/.agents/plugins -maxdepth 4 \( -type f -o -type d -o -type l \) | sort
```

After restarting Codex, verify:

- the skills are available through Codex skill discovery
- the local plugin is installed and enabled
- do not assume `/commit` or `/pr` will appear in the `/` popup

## Updating

Update the repository:

```bash
cd ~/Projects/my-claude-skills
git pull
./update-thirdparty.sh
```

Because the installation uses symlinks, updated skills and commands will point to the latest local files. Restart Codex after updates.

## Uninstall

Remove the installed skill symlinks:

```bash
rm -f ~/.agents/skills/jira
rm -f ~/.agents/skills/jira-link
rm -f ~/.agents/skills/commit
rm -f ~/.agents/skills/pr
rm -f ~/.agents/skills/pr-comments
rm -f ~/.agents/skills/pr-review
rm -f ~/.agents/skills/pr-screenshots
rm -f ~/.agents/skills/refactor-code
rm -f ~/.agents/skills/refactor-components
rm -f ~/.agents/skills/security-review
rm -f ~/.agents/skills/slack
rm -f ~/.agents/skills/todo-resolver
rm -f ~/.agents/skills/frontend-slides
```

Remove the local plugin:

```bash
rm -rf ~/.agents/plugins/.codex/plugins/my-claude-skills
rm -f ~/.agents/plugins/marketplace.json
```

Remove the plugin enablement block from `~/.codex/config.toml`:

```toml
[plugins."my-claude-skills@personal-local"]
enabled = true
```

Restart Codex after uninstalling.

## Notes

- Local plugins depend on the `plugins` feature being enabled in Codex CLI.
- In `codex-cli 0.120.0`, plugin installation and enablement work, but plugin command files still do not appear in the `/` popup as top-level slash commands.
- This repo still contains Claude-oriented wording in some skills and commands. They are installable in Codex, but some instructions may need adaptation over time.
- Codex already ships a system `skill-creator`, so this repository does not need to install a separate copy of that skill.
- If you want, this repository can later gain a dedicated `install_codex.sh` script to automate the full setup above.
