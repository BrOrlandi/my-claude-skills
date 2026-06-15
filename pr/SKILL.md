---
name: pr
description: Create or update a GitHub pull request from the current branch. Use when the user asks to create a PR, open a pull request, run /pr, prepare PR content, update an existing PR, or publish branch changes for review.
argument-hint: [mode] [include-how-to-test] [review]
---

# PR

Create a well-structured pull request against the repository's default base branch (commonly `main`, but may be `develop` or another branch), committing local changes first when needed.

## Arguments

If the user provides mode-like wording, treat it as the creation mode:
- draft: create a draft PR
- ready/open: create a normal PR

If the user asks to include testing instructions, include a `How to Test` section. Otherwise include it when there are obvious verification steps or recent verification output.

If the user passes `review` (or `preview` / wording like "let me review first" / "don't create yet"), enable **review mode**: draft the title and body, show them, and wait for approval or edits before creating the PR. Default (no such wording) is to create the PR directly.

## Workflow

1. Detect the repository's default branch — that is the base, not a hardcoded `main`:
   ```bash
   BASE="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
   ```
   It may be `main`, `develop`, or anything else. Use `$BASE` everywhere below.
2. Inspect the current branch and changes (substitute the detected base for `$BASE`):
   ```bash
   git branch --show-current
   git status --short
   git diff --stat "$BASE...HEAD"
   git diff "$BASE...HEAD"
   git log --oneline "$BASE..HEAD"
   gh pr list --state all --head "$(git branch --show-current)" --json number,title,url,state,isDraft,headRefName
   ```
3. If there are uncommitted changes, commit them first using the `commit` skill workflow (conventional commits, logical grouping).
4. Use the detected default branch as the base unless the user explicitly names a different base branch.
5. If a PR already exists for the branch, update its title/body when useful instead of creating a duplicate.
6. Generate a PR title from the branch commits using conventional commit style when possible. Keep it short and reviewer-facing.
7. Draft the PR body. Default: do NOT ask the user to approve the title or body first — create the PR directly, then show the final title and body so the user can review and request edits afterward. In **review mode** (see Arguments): show the drafted title and body and wait for approval or edits before creating.
8. Create or update the PR with `gh`, targeting the detected base branch:
   ```bash
   gh pr create --base "$BASE" --title "<title>" --body-file <body-file>
   gh pr create --base "$BASE" --draft --title "<title>" --body-file <body-file>
   gh pr edit <number> --title "<title>" --body-file <body-file>
   ```
9. After creating the PR, use the `jira-link` skill when applicable to offer Jira linking for repositories with configured Jira integration.
10. Open the PR in the browser:
   ```bash
   gh pr view -w
   ```

Always: detect the repository's default base branch, list existing PRs for the current branch, commit first when there are local changes, compare against that base branch, create or update the PR without pre-approval, show the final PR content afterward for review, honor the requested PR mode, and offer Jira linking after creation.

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
- Keep generated content specific to the actual diff between the base branch and the current branch.

## Completion

Report the PR URL, whether it was created or updated, whether it is draft or ready for review, and whether Jira linking was completed, skipped, or not applicable.
