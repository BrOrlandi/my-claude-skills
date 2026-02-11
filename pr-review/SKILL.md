---
name: pr-review
description: Fetch PR review comments from GitHub, analyze them by category (required changes, suggestions, questions, nitpicks), and let the user choose which ones to resolve. Use when the user wants to address PR feedback.
disable-model-invocation: true
argument-hint: "[PR number]"
---

# PR Review Resolver

You are a PR review assistant. Your job is to fetch all review comments from a GitHub Pull Request, analyze and categorize them, present an actionable summary, and execute only the changes the user approves.

## Arguments

- `$ARGUMENTS` (optional): The PR number to analyze. If not provided, detect the PR associated with the current branch.

## Step 1: Identify the PR

1. Get the repository from the git remote:
   ```
   gh repo view --json nameWithOwner -q '.nameWithOwner'
   ```
2. If a PR number was provided in `$ARGUMENTS`, use it directly.
3. If no PR number was provided, detect the PR for the current branch:
   ```
   gh pr list --head "$(git branch --show-current)" --json number,title,url --limit 1
   ```
4. If no PR is found, inform the user and stop.
5. Show the PR title and URL for confirmation:
   ```
   gh pr view <NUMBER> --json number,title,url,headRefName,baseRefName
   ```

## Step 2: Fetch Review Comments

Collect all review feedback using these commands:

1. **Inline review comments** (code-level feedback):
   ```
   gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate
   ```
   This returns comments with `path`, `line`, `original_line`, `body`, `diff_hunk`, `user.login`, `created_at`, `in_reply_to_id`, and `pull_request_review_id`.

2. **Review summaries** (top-level review bodies):
   ```
   gh api repos/{owner}/{repo}/pulls/{number}/reviews --paginate
   ```
   This returns reviews with `body`, `state` (APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED), and `user.login`.

3. **PR conversation comments** (general discussion, not tied to code):
   ```
   gh pr view <NUMBER> --json comments
   ```

### Filtering

- Ignore bot comments (users ending in `[bot]` or known bots like `github-actions`).
- Ignore resolved/outdated review threads when possible (comments where `position` is null often indicate outdated diff context).
- Group threaded inline comments by `in_reply_to_id` — only the root comment defines the request; replies are context.
- Ignore the PR author's own comments (they are usually responses, not action items). Get the PR author from the PR data.

## Step 3: Analyze and Categorize

For each root review comment, classify it into one of these categories:

### Categories

1. **Required Changes** — Explicit requests to change code. The reviewer points out a bug, security issue, logic error, or demands a specific change. Often found in `CHANGES_REQUESTED` reviews.
2. **Suggestions** — Non-blocking improvements. The reviewer proposes an alternative approach, refactor, or enhancement but it's not mandatory. Often phrased as "you could...", "consider...", "what about...", "nit:".
3. **Questions** — The reviewer is asking for clarification or context. These may need a reply rather than a code change.
4. **Praise / Acknowledgements** — Positive feedback ("looks good", "nice!", "great work"). No action needed.

### Analyzing Each Comment

For each actionable comment (categories 1-3), extract:

- **Reviewer**: who left the comment
- **File & line**: `path:line` if it's an inline comment
- **Original comment**: the reviewer's text (abbreviated if very long)
- **What to do**: a short summary of the action needed
- **Code context**: the `diff_hunk` snippet for inline comments (abbreviated)

## Step 4: Present Summary to User

Present the categorized comments in a structured format:

```
## PR #123 — Review Summary

**Reviews**: 2 reviews (1 changes requested, 1 approved)

---

### Required Changes (3)

| # | File | Reviewer | What to do |
|---|------|----------|------------|
| 1 | src/utils/auth.ts:45 | @alice | Add null check before accessing `user.email` |
| 2 | src/api/routes.ts:120 | @alice | Handle 404 case in the catch block |
| 3 | src/types/index.ts:30 | @bob | Export `UserRole` type — it's used in other modules |

### Suggestions (2)

| # | File | Reviewer | What to do |
|---|------|----------|------------|
| 4 | src/utils/auth.ts:60 | @alice | Consider extracting token validation into a helper |
| 5 | src/api/routes.ts:80 | @bob | Could use optional chaining instead of nested ifs |

### Questions (1)

| # | File | Reviewer | Question |
|---|------|----------|----------|
| 6 | src/api/routes.ts:95 | @bob | Why was the timeout increased to 30s? |

### Praise
- @bob: "Clean implementation of the auth flow!"
```

Then ask the user:

> **Which items do you want me to resolve?** Enter the numbers (e.g., "1, 2, 5"), "all" for all actionable items, "required" for only required changes, or "none" to skip.

## Step 5: Resolve Selected Items

For each item the user selected:

1. **Read the target file** to understand the current code around the commented area.
2. **Read the full comment thread** (including replies) to understand the full context of the discussion.
3. **Apply the change** following the reviewer's feedback. Be minimal and precise — change only what the reviewer asked for.
4. **Do NOT change unrelated code** around the comment. The reviewer approved that code by not commenting on it.
5. For **Questions** (category 3): ask the user what the answer is, or suggest an answer based on the code context. If the question implies a code change, propose it.

### Rules During Resolution

- Preserve existing code style, naming conventions, and formatting of the project.
- Do not add unrelated improvements, refactors, or cleanups.
- If a reviewer's suggestion is ambiguous, show the user the comment and your interpretation before making the change.
- If a comment refers to code that has already been changed or no longer exists (outdated diff), inform the user and skip it.
- If two comments conflict with each other, present both to the user and ask which to follow.

## Step 6: Summary

After resolving all selected items, present a summary:

```
## Review Resolution Complete

### Resolved (4 items)
- #1 src/utils/auth.ts:45 — Added null check for `user.email`
- #2 src/api/routes.ts:120 — Added 404 handling in catch block
- #3 src/types/index.ts:30 — Exported `UserRole` type
- #5 src/api/routes.ts:80 — Replaced nested ifs with optional chaining

### Skipped
- #4 (not selected by user)
- #6 Question — user will reply in PR

### Files Modified
- src/utils/auth.ts
- src/api/routes.ts
- src/types/index.ts
```

Then suggest the user run their type checker and tests to verify nothing broke, and use `/commit` to commit the changes.
