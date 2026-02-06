# My Claude Skills

A collection of reusable [Claude Code](https://claude.ai/claude-code) skills.

## Skills

| Skill | Description |
|-------|-------------|
| **refactor-components** | Find large React components (.tsx/.jsx) and refactor them into smaller, focused components |
| **refactor-code** | Find large non-React code files (.ts/.js) and refactor them into smaller, focused files (routes, services, utils, etc.) |

## Installation

Clone the repository and run the install script to symlink all skills to your personal Claude Code skills directory:

```bash
git clone https://github.com/YOUR_USERNAME/my-claude-skills.git ~/Projects/my-claude-skills
cd ~/Projects/my-claude-skills
./install.sh
```

This creates symlinks in `~/.claude/skills/`, making all skills available globally across all your projects.

## Uninstall

```bash
cd ~/Projects/my-claude-skills
./uninstall.sh
```

## Adding to a specific project

You can also copy individual skills into a project's `.claude/skills/` directory if you prefer project-level installation.
