# My Claude Skills

A collection of reusable [Claude Code](https://claude.ai/claude-code) skills and commands.

## Skills

| Skill                   | Description                                                                                                             |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **refactor-components** | Find large React components (.tsx/.jsx) and refactor them into smaller, focused components                              |
| **refactor-code**       | Find large non-React code files (.ts/.js) and refactor them into smaller, focused files (routes, services, utils, etc.) |
| **pr-comments**         | Fetch PR review comments in sequential order, perform deep analysis with code context, suggest solutions, enter Plan mode for complex changes, and auto-resolve threads on GitHub |
| **todo-resolver**       | Find TODO/FIXME/HACK comments in the codebase, analyze their impact and complexity, and resolve them                    |
| **pr-screenshots**      | Capture screenshots or GIF recordings of UI features, upload them losslessly to a dedicated GitHub orphan branch (`pr-assets`), and add a labeled Screenshots section to the current PR description. Images are served via `raw.githubusercontent.com` — no compression, opens inline (no forced download). Infers what to capture from conversation context, PR diff analysis, or user clarification. |
| **skill-creator**       | Guide for creating effective skills that extend Claude's capabilities. From [Anthropic's skills repo](https://github.com/anthropics/skills/tree/main/skills/skill-creator) |

## Commands

| Command                 | Description                                                                                 |
| ----------------------- | ------------------------------------------------------------------------------------------- |
| **/commit**             | Create structured git commits using conventional commit format with smart branch validation |
| **/pr**                 | Create well-structured pull requests with context and testing instructions                  |
| **/sync-env-to-github** | Sync environment variables to GitHub environment secrets (Production/staging)               |

## Installation

Clone the repository and run the install script to symlink all skills and commands to your personal Claude Code directory:

```bash
git clone https://github.com/BrOrlandi/my-claude-skills.git ~/Projects/my-claude-skills
cd ~/Projects/my-claude-skills
./install.sh
```

This creates symlinks in `~/.claude/skills/` and `~/.claude/commands/`, making everything available globally across all your projects.

## Uninstall

```bash
cd ~/Projects/my-claude-skills
./uninstall.sh
```

## Adding to a specific project

You can also copy individual skills/commands into a project's `.claude/skills/` or `.claude/commands/` directory if you prefer project-level installation.
