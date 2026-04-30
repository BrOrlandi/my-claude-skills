# My Claude Skills

A collection of reusable [Claude Code](https://claude.ai/claude-code) skills and commands.

## Skills

| Skill                   | Description                                                                                                             | Invocation |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------- |
| **commit**              | Create structured git commits using conventional commit format with branch and PR checks                                | Autonomous |
| **pr**                  | Create or update GitHub pull requests against `main`, using the commit workflow when local changes exist                | Autonomous |
| **refactor-components** | Find large React components (.tsx/.jsx) and refactor them into smaller, focused components                              | Explicit only |
| **refactor-code**       | Find large non-React code files (.ts/.js) and refactor them into smaller, focused files (routes, services, utils, etc.) | Explicit only |
| **jira**                | Interact with Jira using the jira CLI and REST API. View, create, list, transition, and comment on issues with proper @mentions | Autonomous |
| **jira-link**           | Link GitHub PRs to Jira tasks bidirectionally. Adds Jira issue key to PR title and PR URL as remote link on Jira issue. Auto-triggered after `/pr` for configured orgs | Autonomous |
| **pr-comments**         | Fetch PR review comments, perform deep analysis with code context, suggest solutions, auto-resolve threads on GitHub. Supports a full-auto mode that autonomously processes comments, commits, pushes, and polls for new CodeRabbit reviews in a loop | Autonomous |
| **pr-review**           | Review a GitHub PR and submit a single review with inline comments identifying bugs, security vulnerabilities, performance issues, and suggesting improvements | Autonomous |
| **todo-resolver**       | Find TODO/FIXME/HACK comments in the codebase, analyze their impact and complexity, and resolve them                    | Explicit only |
| **pr-screenshots**      | Capture screenshots or GIF recordings of UI features, upload them losslessly to a dedicated GitHub orphan branch (`pr-assets`), and add a labeled Screenshots section to the current PR description. Images are served via `raw.githubusercontent.com` — no compression, opens inline (no forced download). Infers what to capture from conversation context, PR diff analysis, or user clarification. | Explicit only |
| **security-review**     | Scan code for security vulnerabilities (hardcoded secrets, env var exposure, injection, auth issues), generate SECURITY.md guidelines, or verify compliance with existing security rules | Autonomous |
| **slack**               | Send messages, upload files, read conversations, react to messages, and manage Slack workspaces using SlackCLI | Autonomous |
| **skill-creator**       | Guide for creating effective skills that extend Claude's capabilities. From [Anthropic's skills repo](https://github.com/anthropics/skills/tree/main/skills/skill-creator) | Autonomous |

- **Autonomous**: Claude can activate the skill on its own when it detects a relevant context (e.g., linking a PR to Jira after creating it).
- **Explicit only**: The skill only runs when you invoke it directly (e.g., `/pr-review 123`). Claude will not trigger it autonomously.

## Third-Party Skills

Curated skills from the community, cloned as independent repositories into `thirdparty/`. See [THIRDPARTY.md](THIRDPARTY.md) for instructions on adding new ones.

| Skill                   | Description                                                        | Repository |
| ----------------------- | ------------------------------------------------------------------ | ---------- |
| **frontend-slides**     | Create animation-rich HTML presentations without design expertise  | [zarazhangrui/frontend-slides](https://github.com/zarazhangrui/frontend-slides) |

## Statusline

A custom Claude Code statusline lives in [`statusline/`](statusline/). It shows `project │ branch │ model · effort │ context-bar`. `install.sh` symlinks it to `~/.claude/statusline.js`; you enable it by adding a `statusLine` block to `~/.claude/settings.json` (see [`statusline/README.md`](statusline/README.md)).

## Commands

Claude Code slash command versions of the git workflows. Codex users should use the `commit` and `pr` skills instead.

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
./update-thirdparty.sh  # Clone all third-party skill repos
./install.sh            # Symlink all skills and commands
```

This creates symlinks in `~/.claude/skills/` and `~/.claude/commands/`, making everything available globally across all your projects.

### Updating Third-Party Skills

```bash
./update-thirdparty.sh
```

This pulls the latest changes for all third-party skill repositories listed in `thirdparty-skills.json`.

## Uninstall

```bash
cd ~/Projects/my-claude-skills
./uninstall.sh
```

## Adding to a specific project

You can also copy individual skills/commands into a project's `.claude/skills/` or `.claude/commands/` directory if you prefer project-level installation.
