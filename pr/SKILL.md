---
name: pr
description: Create or update a GitHub pull request from the current branch. Use when the user asks to create a PR, open a pull request, run the old /pr workflow, prepare PR content, update an existing PR, or publish branch changes for review.
---

# PR

Create a well-structured pull request against `main`, committing local changes first when needed. This is the Codex-compatible equivalent of `commands/pr.md`; keep the Claude Code command file separate and unchanged unless the user explicitly asks to edit it.

## Arguments

If the user provides mode-like wording, treat it as the creation mode:
- draft: create a draft PR
- ready/open: create a normal PR

If the user asks to include testing instructions, include a `How to Test` section. Otherwise include it when there are obvious verification steps or recent verification output.

## Workflow

1. Inspect the current branch and changes:
   ```bash
   git branch --show-current
   git status --short
   git diff --stat main...HEAD
   git diff main...HEAD
   git log --oneline main..HEAD
   gh pr list --state all --head "$(git branch --show-current)" --json number,title,url,state,isDraft,headRefName
   ```
2. If there are uncommitted changes, use the `commit` skill workflow first. Do not refer to `/commit`; Codex should apply the commit skill directly.
3. Always use `main` as the base branch unless the user explicitly instructs otherwise.
4. If a PR already exists for the branch, update its title/body when useful instead of creating a duplicate.
5. Generate a PR title from the branch commits using conventional commit style when possible. Keep it short and reviewer-facing.
6. Draft the PR body and show it to the user before creating or updating the PR.
7. Create or update the PR with `gh`:
   ```bash
   gh pr create --base main --title "<title>" --body-file <body-file>
   gh pr create --base main --draft --title "<title>" --body-file <body-file>
   gh pr edit <number> --title "<title>" --body-file <body-file>
   ```
8. After creating the PR, use the `jira-link` skill when applicable to offer Jira linking for repositories with configured Jira integration.
9. Open the PR in the browser:
   ```bash
   gh pr view -w
   ```

Match the old `/pr` behavior: list existing PRs for the current branch, run the commit workflow first, always compare against `main`, show the PR content before creating or updating it, honor the requested PR mode, and offer Jira linking after creation.

## PR Body Format

Use this structure:

```md
## Context
- What changed and why
- Related issues, tickets, or requirements
- Breaking changes or important reviewer notes, if any

## How to Test
- Specific verification steps
- Setup requirements or test data
- Expected behavior
```

Omit empty bullets. If there are no meaningful manual test steps, say what automated checks or inspection were performed.

## Review Quality

Write for reviewers:
- Explain behavior and motivation, not just file names.
- Link tickets or discussions when visible from branch names, commit messages, or user input.
- Mention risks, migrations, or follow-up work explicitly.
- Keep generated content specific to the actual diff between `main` and the current branch.

## Completion

Report the PR URL, whether it was created or updated, whether it is draft or ready for review, and whether Jira linking was completed, skipped, or not applicable.
