# My Claude Skills

A personal collection of [Claude Code](https://claude.ai/claude-code) **skills**, **commands**,
**hooks** and a custom **statusline** — installed as symlinks into `~/.claude/`, so they work in
every project and update with a `git pull`.

| Part | What it gives you |
| ---- | ----------------- |
| [**Skills**](#skills) | Workflow skills Claude can run or trigger on its own — commits, pull requests, Jira, refactors, security review, releases |
| [**Commands**](#commands) | Slash commands you type yourself |
| [**Hooks**](#hooks) | Sounds when Claude needs you or finishes a turn, last-prompt capture for the statusline, and (macOS) keeping the Mac awake while it works |
| [**Statusline**](#statusline) | Project · branch · model · context bar · rate-limit usage · your last prompt — every row optional |
| [**Third-party skills**](#third-party-skills) | Community skills this repo tracks as separate clones |

## Install by prompt

The install is interactive: it asks what you want, explains each piece before asking, and never
edits your settings without showing you the change. Paste this into Claude Code (or Codex) and let
it drive:

```text
Install the skills, hooks and statusline from https://github.com/BrOrlandi/my-claude-skills.

First work out which agent you are, and pick the matching playbook:
- Claude Code → https://raw.githubusercontent.com/BrOrlandi/my-claude-skills/main/INSTALL_CLAUDE.md
- Codex CLI   → https://raw.githubusercontent.com/BrOrlandi/my-claude-skills/main/INSTALL_CODEX.md

Read that file — fetch the URL, or clone the repo and read it from the clone — and follow it step by
step. Check which operating system I am on before offering anything platform-specific, and adapt to
it: skip the parts that don't apply, and use the commands my system actually has. It is an
interactive install, so as you go:

- ask me what to install at each stage: skills, commands, hooks + sounds, statusline;
- for the skills, list every one with a one-line description of what it does, then ask whether I
  want all of them, a subset I name, or to be walked through them one at a time;
- for the hooks, explain what each one does before asking, and offer to play the notification sound
  with a player my OS has so I can hear it. Don't offer hooks that only work on another OS — say
  they were skipped and why;
- for the statusline, show me a live preview and let me choose which rows to display;
- never edit ~/.claude/settings.json without showing me the exact block first, and back the file up
  before the first edit;
- if something is already installed but differs from the GitHub version, show me what changed and
  ask whether to update it.

Install nothing I have not agreed to.
```

Already installed and want to catch up with what changed since? Use this one instead:

```text
Update my install of https://github.com/BrOrlandi/my-claude-skills.

Pull the repo (find my clone, or clone it if I don't have one), then follow the "Already installed
but out of date" step of INSTALL_CLAUDE.md: show me what changed since my last update, diff anything
I have as a real file instead of a symlink, and ask before updating each one. Then tell me which new
skills, hooks or statusline options landed that I don't have yet, and offer to install them.
```

### Manual install

Same thing, without the questions — installs everything:

```bash
git clone https://github.com/BrOrlandi/my-claude-skills.git ~/Projects/my-claude-skills
cd ~/Projects/my-claude-skills
./update-thirdparty.sh  # clone the third-party skill repos
./install.sh            # symlink skills, commands, hook scripts, sounds, statusline
```

`install.sh` creates symlinks in `~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/hooks/` and
`~/.claude/sounds/`, plus `~/.claude/statusline.js`. Skills and commands are live after a restart;
**hooks and the statusline also need an entry in `~/.claude/settings.json`** — see
[`hooks/README.md`](hooks/README.md) and [`statusline/README.md`](statusline/README.md), or let the
install prompt above write them for you.

Codex CLI users: [INSTALL_CODEX.md](INSTALL_CODEX.md).

## Skills

| Skill                   | Description                                                                                                             | Invocation |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------- |
| **commit**              | Create structured git commits using conventional commit format with branch and PR checks. Learns whether the repo commits straight to its default branch and, once you confirm, records it in `CLAUDE.md`/`AGENTS.md` and stops asking | Autonomous |
| **pr**                  | Create or update GitHub pull requests against the repo's default base branch (`main`, `develop`, etc.), using the commit workflow when local changes exist. Supports `review` to approve title/body before creating | Autonomous |
| **release**             | Establish and then run a repository's release convention — version bump, changelog, tag, GitHub release, store notes. Records the convention in `.claude/release.json` on first run | Autonomous |
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
| **autonomous-mode**     | Carry a task to completion without mid-flight questions — decide on ambiguities, log the calls, park real doubts for a single review at the end. Triggers on "modo autônomo", "não me interrompa", "work autonomously", "just finish it" and similar | Autonomous |
| **skill-creator**       | Guide for creating effective skills that extend Claude's capabilities. From [Anthropic's skills repo](https://github.com/anthropics/skills/tree/main/skills/skill-creator) | Autonomous |

- **Autonomous**: Claude can activate the skill on its own when it detects a relevant context (e.g., linking a PR to Jira after creating it).
- **Explicit only**: The skill only runs when you invoke it directly (e.g., `/pr-review 123`). Claude will not trigger it autonomously.

### Default PR Reviewers

The **pr** skill can request the same reviewer team on every PR opened in a given GitHub
organization. That mapping is personal, so it lives in `pr/config.json`, which is
**gitignored** and never published. Start from the committed template:

```bash
cp pr/config.example.json pr/config.json
```

```json
{
  "orgs": {
    "acme-inc": {
      "team_reviewers": ["acme-inc/developers"],
      "reviewers": []
    }
  }
}
```

Repos owned by an org that isn't listed get no reviewers. See
[pr/references/config-format.md](pr/references/config-format.md) for the full format.

## Commands

The git workflows now live in the `commit` and `pr` skills (invoke with `/commit` and `/pr`, or let Claude trigger them autonomously). The remaining commands:

| Command                 | Description                                                                                 |
| ----------------------- | ------------------------------------------------------------------------------------------- |
| **/sync-env-to-github** | Sync environment variables to GitHub environment secrets (Production/staging)               |

## Hooks

Hooks run a command on a session event — a prompt submitted, a tool about to run, the turn ending.
Everything this repo ships lives in [`hooks/`](hooks/): the scripts, the sounds they play, and the
`settings.json` blocks that wire them up. They are opt-in — a symlink alone does nothing.

| Hook group | Event(s) | Platform | What it does |
| ---------- | -------- | -------- | ------------ |
| **Sounds** | `Notification`, `Stop`, `PreCompact` | macOS (`afplay`) | Plays `bell-notification.wav` when Claude needs you, a muted marimba tap when a turn ends, and the Imperial March beep right before a context compaction |
| **Last prompt** | `UserPromptSubmit`, `SessionEnd` | any (needs `jq`) | Saves your last prompt locally so the statusline can show it back to you |
| **Caffeinate** | `UserPromptSubmit`, `PreToolUse`, `Stop`, `SessionEnd` | macOS only | Keeps the Mac awake while Claude is working, and lets it sleep the moment the turn ends |
| **RTK rewrite** | `PreToolUse` (Bash) | any, third-party | Optional: rewrites shell commands to their token-cheap [`rtk`](https://github.com/rtk-ai/rtk) equivalent. Documented here, installed from RTK |

See [`hooks/README.md`](hooks/README.md) for what each one does in detail, the exact JSON, and how
to merge it into an existing `settings.json`.

## Statusline

A custom Claude Code statusline lives in [`statusline/`](statusline/):

```
my-claude-skills │ main │ Claude Opus 5 (1M context) · xhigh │ █████████░░░░░░░░░░░ 45%
current: ●●●●◍◍◍◍○○○○○○○○○○○○ 22% ↓ | weekly: ●●●●●●●●●◍○○○○○○○○○○ 45% | pace: ↓
resets 4:00pm (4h10m)               | resets Thu, 4:00pm | caveman off
❯ review the auth middleware and tell me what breaks under load
```

Project, git branch, model + effort, a context bar that goes red before auto-compact, 5-hour and
7-day rate-limit usage, each with its own pace arrow and a dim `◍` region showing the time that
passed unspent, reset times, and the prompt you last sent (that last row
needs the last-prompt hooks). **Every row can be turned off** in `statusline/config.json` — see
[`statusline/README.md`](statusline/README.md).

`install.sh` symlinks it to `~/.claude/statusline.js`; you enable it with a `statusLine` block in
`~/.claude/settings.json`.

For Codex, the equivalent native status-line configuration lives in
[`codex-statusline/`](codex-statusline/): project, branch, model/reasoning, context usage and
usage-limit items in `~/.codex/config.toml`.

## Third-Party Skills

Curated skills from the community, cloned as independent repositories into `thirdparty/`. See [THIRDPARTY.md](THIRDPARTY.md) for instructions on adding new ones.

| Skill                   | Description                                                        | Repository |
| ----------------------- | ------------------------------------------------------------------ | ---------- |
| **frontend-slides**     | Create animation-rich HTML presentations without design expertise  | [zarazhangrui/frontend-slides](https://github.com/zarazhangrui/frontend-slides) |

```bash
./update-thirdparty.sh
```

Pulls the latest changes for every third-party repository listed in `thirdparty-skills.json`.

## Updating

```bash
cd ~/Projects/my-claude-skills
git pull
./install.sh   # only needed to pick up new skills, commands or hook scripts
```

Because everything is symlinked, `git pull` alone updates what you already have.

## Uninstall

```bash
cd ~/Projects/my-claude-skills
./uninstall.sh
```

It removes only the symlinks that point back into this repo — local files are left alone, and the
`hooks` / `statusLine` entries in `~/.claude/settings.json` are yours to remove.

## Adding to a specific project

You can also copy individual skills/commands into a project's `.claude/skills/` or `.claude/commands/` directory if you prefer project-level installation.

## Changelog

What changed, grouped by day: [CHANGELOG.md](CHANGELOG.md).
