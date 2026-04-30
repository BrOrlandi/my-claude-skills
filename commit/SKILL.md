---
name: commit
description: Create structured git commits from the current repository changes. Use when the user asks to commit, create a commit, prepare commits, run the old /commit workflow, or turn local staged/unstaged changes into one or more conventional commits.
---

# Commit

Create coherent, reviewable commits after inspecting the current branch, local changes, and recent history. This is the Codex-compatible equivalent of `commands/commit.md`; keep the Claude Code command file separate and unchanged unless the user explicitly asks to edit it.

## Workflow

1. Inspect the repository state:
   ```bash
   git branch --show-current
   git status --short
   git diff --stat HEAD
   git diff HEAD
   git log --oneline -10
   ```
2. Check whether the current branch already has a merged PR:
   ```bash
   gh pr list --state merged --head "$(git branch --show-current)" --json number,title,url,mergedAt
   ```
   If a merged PR exists for this branch, ask the user whether to proceed or switch/create another branch.
3. Do not commit automatically on `main` or `master`. Ask the user for explicit confirmation first.
4. Compare the branch name with the changed files and diff. If the changes clearly do not match the branch purpose, stop and explain the mismatch.
5. Analyze the diff and group changes into logical, atomic commits. Prefer one commit when the change is a single coherent unit; split only when the groups are independently understandable and testable.
6. Stage only the files for the commit being created:
   ```bash
   git add <paths>
   git diff --cached
   ```
7. Commit using conventional commit format:
   ```bash
   git commit -m "type(scope): imperative summary"
   ```

Match the old `/commit` behavior: validate the branch, inspect staged and unstaged changes, consider recent commits, use conventional commits, and split into logical commits only when the diff clearly calls for it.

## Commit Message Rules

Use `type(scope): description`.

Allowed types:
- `feat`: user-facing feature or new capability
- `fix`: bug fix
- `docs`: documentation-only change
- `style`: formatting or styling change with no behavioral impact
- `refactor`: code restructuring without intended behavior change
- `test`: test-only change
- `chore`: maintenance, build, tooling, or dependency work

Choose a concise scope from the package, feature, module, or component affected. Use imperative mood in the description. Do not mention AI assistance in the commit message.

For complex changes, add a short commit body explaining why the change was needed, relevant tradeoffs, or migration notes.

## Multi-Commit Guidance

Split commits by behavior or purpose, not by file type. Good splits include:
- feature implementation separate from tests
- refactor separate from behavior change
- unrelated package changes in a monorepo
- generated or lockfile updates only when they support a specific source change

Avoid partial commits that leave the repository in a broken state.

## After Committing

Run `git status --short` and report:
- commit hash and message for each commit created
- any remaining uncommitted files
- any verification that was run, or that verification was not run
