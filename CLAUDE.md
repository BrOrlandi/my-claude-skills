# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A personal collection of reusable Claude Code **skills** and **commands**, installed globally via symlinks to `~/.claude/skills/` and `~/.claude/commands/`.

## Repository Structure

- **Top-level skill folders** (`refactor-components/`, `refactor-code/`, `pr-comments/`, `pr-review/`): Custom skills authored in this repo. Each contains a `SKILL.md`.
- **`commands/`**: Custom slash commands (`.md` files) — `/sync-env-to-github`.
- **`commit/` and `pr/`**: The `commit` and `pr` skills (structured commits; create/update pull requests against the repo's default base branch). Invoked via `/commit` and `/pr` or auto-triggered; replaced the former `/commit` and `/pr` commands.
- **`skills/`**: Git submodule pointing to [Anthropic's skills repo](https://github.com/anthropics/skills). Contains the `skill-creator` skill and many reference skills. This is a separate git repo — do not modify files inside it directly.
- **`install.sh` / `uninstall.sh`**: Symlink management scripts that link skill folders and command files into `~/.claude/`.

## How Install Works

`install.sh` iterates top-level directories containing a `SKILL.md` file (skipping hidden dirs and `commands/`), creating symlinks in `~/.claude/skills/`. It also symlinks each `.md` file in `commands/` to `~/.claude/commands/`. The `uninstall.sh` script reverses this by removing only symlinks that point back to this repo.

## Creating New Skills

A skill is a directory with a `SKILL.md` file containing YAML frontmatter (`name`, `description`, optional `disable-model-invocation`, `argument-hint`) followed by markdown instructions. Place new skill directories at the repo root, then re-run `./install.sh`.

## Creating New Commands

A command is a single `.md` file in `commands/` with YAML frontmatter (`allowed-tools`, `description`, optional `argument-hint`) followed by markdown instructions. The filename (minus `.md`) becomes the slash command name.

## Conventions

- Skills use `disable-model-invocation: true` when they should only run through explicit user invocation.
- Commands declare `allowed-tools` in frontmatter to specify which tools they can use (e.g., `Bash(git add:*)`).
- The `commit` skill uses conventional commit format: `type(scope): description`.
- The `pr` skill targets the repository's default base branch (detected via `gh`, e.g. `main` or `develop`), not a hardcoded `main`.
