# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A personal collection of reusable Claude Code **skills**, **commands**, **hooks** and a custom **statusline**, installed globally via symlinks into `~/.claude/`. Two install paths: `./install.sh` (links everything) and an interactive, prompt-driven one (`INSTALL_CLAUDE.md`) that asks section by section and also writes the `~/.claude/settings.json` entries.

## Repository Structure

- **Top-level skill folders** (`refactor-components/`, `refactor-code/`, `pr-comments/`, `pr-review/`): Custom skills authored in this repo. Each contains a `SKILL.md`.
- **`commands/`**: Custom slash commands (`.md` files) — `/sync-env-to-github`.
- **`commit/` and `pr/`**: The `commit` and `pr` skills (structured commits; create/update pull requests against the repo's default base branch). Invoked via `/commit` and `/pr` or auto-triggered; replaced the former `/commit` and `/pr` commands.
- **`skills/`**: Git submodule pointing to [Anthropic's skills repo](https://github.com/anthropics/skills). Contains the `skill-creator` skill and many reference skills. This is a separate git repo — do not modify files inside it directly.
- **`hooks/`**: Everything hook-related. `hooks/scripts/*.sh` are symlinked into `~/.claude/hooks/` (caffeinate guard/release — macOS only; save/cleanup last prompt — feeds the statusline, needs `jq`). `hooks/sounds/*.wav` are symlinked per-file into `~/.claude/sounds/` preserving subfolders. Symlinking alone activates nothing: every hook needs an entry in `~/.claude/settings.json`. RTK's `PreToolUse` rewrite hook is documented in `hooks/README.md` but deliberately **not** vendored — it ships with the `rtk` binary.
- **`statusline/`**: `statusline.js`, symlinked to `~/.claude/statusline.js`. Reads an optional `statusline/config.json` (gitignored, template in `config.example.json`) of booleans that turn individual rows off. `codex-statusline/` is the Codex-native equivalent.
- **`INSTALL_CLAUDE.md` / `INSTALL_CODEX.md`**: Agent playbooks, not human manuals. The README carries a copy-paste prompt that tells an agent to fetch the matching file and run an interactive install (asks per section, demos sounds, previews the statusline, diffs anything already installed).
- **`install.sh` / `uninstall.sh`**: Symlink management scripts that link skill folders, command files, hook scripts, sounds and the statusline into `~/.claude/`.

## How Install Works

`install.sh` iterates top-level directories containing a `SKILL.md` file (skipping hidden dirs, `commands/`, `statusline/` and `hooks/`), creating symlinks in `~/.claude/skills/`. It also symlinks each `.md` file in `commands/` to `~/.claude/commands/`, each `hooks/scripts/*.sh` to `~/.claude/hooks/`, each `hooks/sounds/**/*.wav` to `~/.claude/sounds/`, and `statusline/statusline.js` to `~/.claude/statusline.js`. Targets that already exist and are not symlinks are skipped with a message, never overwritten. The `uninstall.sh` script reverses this by removing only symlinks that point back to this repo.

The interactive path (`INSTALL_CLAUDE.md`) does the same linking, but one section at a time and with the `settings.json` wiring that `install.sh` cannot do on its own.

## Creating New Skills

A skill is a directory with a `SKILL.md` file containing YAML frontmatter (`name`, `description`, optional `disable-model-invocation`, `argument-hint`) followed by markdown instructions. Place new skill directories at the repo root, then re-run `./install.sh`.

## Creating New Commands

A command is a single `.md` file in `commands/` with YAML frontmatter (`allowed-tools`, `description`, optional `argument-hint`) followed by markdown instructions. The filename (minus `.md`) becomes the slash command name.

## Conventions

- Skills use `disable-model-invocation: true` when they should only run through explicit user invocation.
- Commands declare `allowed-tools` in frontmatter to specify which tools they can use (e.g., `Bash(git add:*)`).
- The `commit` skill uses conventional commit format: `type(scope): description`.
- The `pr` skill targets the repository's default base branch (detected via `gh`, e.g. `main` or `develop`), not a hardcoded `main`.
- Docs and code comments are written in English, including the hook scripts.
- When a skill, hook or statusline option changes, the copy in `README.md`, the folder's own `README.md` and `INSTALL_CLAUDE.md` must stay in sync — the install prompt reads them out loud to whoever is installing.
- **Private, work-specific settings go in a skill-local `config.json`**, which `.gitignore` excludes via `**/config.json`. Commit a `config.example.json` next to it as the public template, and document the schema in the skill's `references/config-format.md`. Skills read it through the install symlink at `~/.claude/skills/<skill>/config.json` and must degrade silently when it is absent. Examples: `pr/config.json` maps a GitHub org to its default PR reviewers; `statusline/config.json` picks which statusline rows to render.

## Release & Changelog

Structured convention: `.claude/release.json` (read by the `release` skill).

- One release unit: the whole collection. **No version number and no tags** — installation is
  `git clone` + `./install.sh`, so there is nothing for a version to pin.
- Changelog: `CHANGELOG.md` at the root, grouped by the day the work landed (`## YYYY-MM-DD`),
  newest first, in English, written for whoever installs the skills.
- What earns an entry: a change someone installing this would notice — a new skill or command, a
  skill that behaves differently, new statusline or sound behaviour. Repo plumbing does not:
  install-script internals, README formatting, and the vendored `skills/` submodule and
  `thirdparty/` contents.
- When a change and its changelog entry ship together, they belong in the same commit.

## Git workflow

<!-- claude-skill:commit default-branch-policy=direct -->

Work lands directly on the default branch. Commit to it without asking for confirmation, and do not
propose creating a feature branch first.
