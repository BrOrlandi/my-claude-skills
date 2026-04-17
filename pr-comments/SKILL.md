---
name: pr-comments
description: Fetch PR review comments in sequential order, perform deep analysis with code context and impact assessment, suggest concrete solutions with alternatives, enter Plan mode for complex changes, and auto-resolve threads on GitHub.
disable-model-invocation: false
argument-hint: "[PR number]"
---

# PR Comments Resolver

You are a PR review assistant. Your job is to fetch all review comments from a GitHub Pull Request, analyze each one deeply with code context and impact assessment, present them in PR order, and resolve them sequentially — entering Plan mode for complex changes and auto-resolving threads on GitHub.

## Arguments

- `$ARGUMENTS` (optional): The PR number to analyze, optionally prefixed with `full-auto`. If not provided, detect the PR associated with the current branch.
  - Examples: `77`, `full-auto`, `full-auto 77`
- **Mode detection**: If `$ARGUMENTS` contains `full-auto`, run in Full-Auto Mode (see below). Otherwise, run in normal interactive mode.

## Full-Auto Mode

When `$ARGUMENTS` contains `full-auto`, the skill runs autonomously without asking for confirmation on each comment. It processes all open comments, commits, pushes, resolves threads, comments on the PR, and then polls for new CodeRabbit reviews — repeating until there are no more open comments.

**In full-auto mode, Steps 1–4 remain the same. Steps 5–8 are replaced by the phases below.**

### Phase 1: Autonomous Processing (replaces Steps 5–6)

Process each open comment **autonomously** using these decision criteria:

| Decision                           | When to apply                                                                                                                                                                      |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Fix automatically**              | Bugs, a11y issues, error handling, stale closures, missing validation, security issues, concrete improvements with clear intent                                                    |
| **Decline**                        | Stylistic opinions, over-engineering suggestions, changes that conflict with CLAUDE.md conventions                                                                                 |
| **Ask the user (AskUserQuestion)** | Ambiguous comments, business logic changes (pricing, permissions, workflows, domain validation, feature flags), architectural decisions with broad impact, unclear reviewer intent, any comment where the "correct" behavior depends on domain knowledge or could be interpreted multiple ways |

For each comment:

- **If fixing**: Apply the code change. Do NOT resolve the thread yet — resolution happens after commit+push in Phase 2.
- **If declining**: Reply on the thread explaining the reasoning, but do **not** resolve the thread (let the reviewer decide).
- **If asking**: Present what the reviewer said, what the code does, and why it's ambiguous. Wait for user confirmation via AskUserQuestion before proceeding. Never guess business rules — ask first. Apply only after approval.

### Phase 2: Commit and Push

After processing all comments in the current batch:

1. Stage all modified files and create a commit with a descriptive message (e.g., `fix: address PR review comments (round N)`).
2. Push to the remote branch.

### Phase 3: Comment on the PR

Post a summary comment on the PR mentioning the reviewer:

```
@coderabbitai[bot] Addressed review comments:

**Fixed (N):**
- file.ts:L — description of fix
- file2.ts:L — description of fix

**Declined (M):**
- file3.ts:L — reason for declining

Commit: abc1234
```

Use `gh pr comment <NUMBER> --body "..."` to post the comment.

### Phase 4: Poll for New Review

1. Launch the polling script in background:

   ```bash
   ~/.claude/skills/pr-comments/poll-pr-comments.sh {owner} {repo} {pr_number}
   ```

   Use `Bash` with `run_in_background: true`.

2. Wait for the result using `TaskOutput` with `timeout: 600000` (10 minutes).

3. Parse the output:
   - **`NEW_COMMENTS:<count>`** — New open threads found. Go back to **Step 2: Fetch Review Comments** and repeat from Phase 1.
   - **`ALL_CLEAR`** — CodeRabbit finished with no new comments. Proceed to Phase 5.
   - **`TIMEOUT`** — Polling timed out. Inform the user and stop.

### Phase 5: Final Summary

Present a complete summary across **all rounds**:

```md
## PR #123 — Full-Auto Resolution Summary

### Round 1

| #   | Tag | File           | Action                         | Thread      |
| --- | --- | -------------- | ------------------------------ | ----------- |
| 1   | 🔴  | src/auth.ts:45 | Fixed: added null check        | ✅ Resolved |
| 2   | 🟡  | src/api.ts:80  | Declined: stylistic preference | ⏳ Open     |

Commit: abc1234

### Round 2

| #   | Tag | File           | Action                        | Thread      |
| --- | --- | -------------- | ----------------------------- | ----------- |
| 3   | ✨  | src/auth.ts:50 | Fixed: improved error message | ✅ Resolved |

Commit: def5678

### Totals

- **Fixed**: N comments across M rounds
- **Declined**: N comments
- **Asked user**: N comments
- **Files modified**: list of files
```

---

## Step 1: Identify the PR

1. Get the repository from the git remote:
   ```bash
   gh repo view --json nameWithOwner -q '.nameWithOwner'
   ```
2. If a PR number was provided in `$ARGUMENTS`, use it directly.
3. If no PR number was provided, detect the PR for the current branch:
   ```bash
   gh pr list --head "$(git branch --show-current)" --json number,title,url --limit 1
   ```
4. If no PR is found, inform the user and stop.
5. Show the PR title and URL for confirmation:
   ```bash
   gh pr view <NUMBER> --json number,title,url,headRefName,baseRefName,author
   ```

## Step 2: Fetch Review Comments

Collect all review feedback automatically — never ask the user before fetching.

1. **Review threads with resolution status** (via GraphQL — preferred source for inline comments):

   ```graphql
   gh api graphql -f query='
     query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $number) {
           reviewThreads(first: 100, after: $cursor) {
             pageInfo { hasNextPage endCursor }
             nodes {
               id
               isResolved
               isOutdated
               path
               line
               comments(first: 100) {
                 nodes {
                   id
                   body
                   author { login }
                   createdAt
                   diffHunk
                 }
               }
             }
           }
         }
       }
     }' -f owner='{owner}' -f repo='{repo}' -F number={number}
   ```

   This returns review threads with `id` (needed for resolving), `isResolved`, `isOutdated`, `path`, `line`, and all comments in each thread. Paginate using `pageInfo.hasNextPage` and `endCursor` if needed.

2. **Review summaries** (top-level review bodies):

   ```bash
   gh api repos/{owner}/{repo}/pulls/{number}/reviews --paginate
   ```

   This returns reviews with `body`, `state` (APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED), and `user.login`.

3. **PR conversation comments** (general discussion, not tied to code):
   ```bash
   gh pr view <NUMBER> --json comments
   ```

### Filtering

- **Skip resolved threads** — only process threads where `isResolved` is `false`.
- **Skip outdated threads** — threads where `isOutdated` is `true` refer to code that has since changed and are likely no longer relevant.
- **Detect already-addressed comments** — for each unresolved thread, check `comments.nodes` for replies authored by the PR author (compare `author.login` against the PR author from Step 1). If the PR author has replied to the thread, mark it as **"likely addressed"** and deprioritize it. These comments should be collected separately and presented at the end of the comment list (in Step 5) with a note: _"These may already be addressed — verify only."_ They still appear in the analysis but are processed last and with the expectation that no further action is needed.
- **Keep AI review bot comments** — bots like `coderabbitai[bot]`, `copilot[bot]`, or other AI code review tools provide actionable feedback and should be treated the same as human reviewer comments.
- Ignore **non-review bots** (e.g., `github-actions[bot]`, `dependabot[bot]`, `netlify[bot]`, `vercel[bot]`) — these are CI/deployment bots, not code reviewers.
- In each thread, the first comment defines the request; subsequent comments are context/replies.
- **Keep the PR author's own comments** — they may have been generated by AI review tools (e.g., `/pr-review` skill). Treat them the same as any other reviewer comment.

## Step 3: Order and Tag Comments

Unify all comment sources (GraphQL threads, REST reviews, PR conversation comments) into a **single list ordered by `createdAt`** (the chronological order they appear in the PR).

For each comment, assign **one** inline category tag based on its content:

| Tag              | Meaning                                                       |
| ---------------- | ------------------------------------------------------------- |
| 🔴 Critical      | Bugs, security issues, logic errors — must fix                |
| 🟡 Minor         | Nitpicks, style preferences, non-blocking suggestions         |
| 🔒 Security      | Security-specific concerns (auth, injection, secrets)         |
| ♿ Accessibility | Accessibility improvements (a11y, ARIA, contrast)             |
| 🐛 Bug           | Explicit bug reports in the code                              |
| ✨ Improvement   | Refactor suggestions, better patterns, enhancements           |
| ❓ Question      | Clarification requests — may need a reply, not a code change  |
| 👍 Praise        | Positive feedback — no action needed                          |
| ⚡ Performance   | Performance concerns (N+1 queries, unnecessary renders, etc.) |
| 🧪 Testing       | Missing tests, test improvements, coverage concerns           |
| 📝 Documentation | Missing or incorrect docs, JSDoc, README updates              |

Each comment carries its tag inline rather than being grouped into separate sections.

## Step 4: Deep Analysis

For each actionable comment (everything except 👍 Praise), perform analysis at a depth **tiered by comment severity** to avoid wasting tokens on minor issues:

### Analysis tiers

| Tier | Tags | Context window | PR diff | Dependency tracing |
|------|------|---------------|---------|-------------------|
| **Light** | 👍 Praise, 🟡 Minor, 📝 Documentation | ± 10 lines | Skip | Skip |
| **Standard** | ✨ Improvement, ❓ Question, 🧪 Testing, ⚡ Performance | ± 30 lines | File diff only | Only if comment explicitly mentions other files |
| **Deep** | 🔴 Critical, 🔒 Security, 🐛 Bug, ♿ Accessibility | ± 50 lines | File diff | Full — grep for dependencies, impact assessment |

### Analysis steps (scaled by tier)

1. **Read the code** at the referenced `path:line` plus surrounding context according to the tier above using the Read tool.
2. **Read the PR diff** for the file (Standard and Deep tiers only):
   ```bash
   gh pr diff <NUMBER> -- <path>
   ```
3. **Evaluate the comment** — does the reviewer's feedback make sense given the current code? Is it still relevant?
4. **Assess impact** (Deep tier only, or Standard tier when the comment explicitly references other files) — what other files, functions, or modules would be affected by the change? Use Grep/Glob to trace dependencies if needed.
5. **Suggest a concrete solution** if the reviewer didn't propose one. If the reviewer did suggest a fix, evaluate it and refine if needed.
6. **List 2-3 alternatives** with brief pros/cons when the fix isn't obvious (Standard and Deep tiers only — skip for Light tier).
7. **Ambiguity Detection** — evaluate whether the comment or the code it references contains ambiguity in business rules. Ask yourself:
   - Is the expected behavior clearly defined, or could it be interpreted in more than one way?
   - Does the reviewer assume a business rule that isn't explicitly documented in the code?
   - Could applying this fix change business behavior in a way that isn't obvious?
   - Is there a contradiction between what the code does, what the comment says, and what the business rule should be?
   If any of these are true, mark the comment as **⚠️ Ambiguous — needs user validation** in your analysis. Do NOT propose a fix yet — this will be validated with the user in the triage step.
8. **Business Logic Awareness** — if the change touches business rules (pricing, permissions, workflows, validation logic, feature flags), flag it clearly and alert the user before proposing any modification. Business logic changes require explicit user confirmation even if the reviewer requested them.

## Step 5: Present Comments

Display ALL comments in **sequential PR order** (not grouped by category). For each comment show:

```md
### #N — [TAG] file/path.ts:line

**Reviewer**: @username
**Comment**: [reviewer's text, abbreviated if very long]

**Analysis**: [Your assessment — does it make sense? Is it still relevant?]
**Suggested Fix**: [Concrete code change or action to take]
**Impact**: [Other files/functions affected]
**Alternatives**:

1. [Option A] — pros / cons
2. [Option B] — pros / cons
```

For 👍 Praise comments, show a single-line entry:

```md
### #N — 👍 file/path.ts:line — @username: "Nice work!"
```

After presenting all comments, proceed to the triage step.

## Step 5.5: Point-by-Point Triage with the User

Before resolving anything, walk through the comments **one by one** with the user to validate understanding and alignment — especially for comments flagged as ambiguous or touching business logic.

1. **Group comments into two buckets:**
   - **Straightforward** — clear bug fixes, typos, missing null checks, style issues where the intent is unambiguous.
   - **Needs validation** — anything flagged as ⚠️ Ambiguous in Step 4, business logic changes, comments where the reviewer's intent could be interpreted multiple ways, or where the "correct" behavior depends on domain knowledge you don't have.

2. **Present a triage summary** to the user using AskUserQuestion:

   > I found **N** open comments. Here's my assessment:
   >
   > **Can resolve directly (N):**
   > - #1 — 🔴 src/auth.ts:45 — null check missing (clear fix)
   > - #3 — 🟡 src/api.ts:12 — style nit (optional chaining)
   >
   > **Need your input first (M):**
   > - #2 — ⚠️ src/pricing.ts:80 — reviewer says discount should cap at 30%, but code allows 50%. Which is correct?
   > - #4 — ⚠️ src/permissions.ts:22 — ambiguous: should admins bypass this validation or not?
   >
   > Want to go through the items that need validation point by point?

3. **For each "needs validation" item**, use AskUserQuestion to clarify **before** proposing any code change. Present:
   - What the reviewer said
   - What the code currently does
   - Why it's ambiguous (the specific question or contradiction)
   - Ask the user what the correct behavior should be

   Only after the user confirms the expected behavior should you propose a concrete fix.

4. **For "straightforward" items**, confirm with the user that they agree these can be resolved directly. The user may move items between buckets.

This triage ensures you never apply a "fix" that introduces a different bug because the business rule was misunderstood. The goal is: **when in doubt, ask first — never guess business rules.**

## Step 5.9: Batch Detection for Simple Fixes

Before starting sequential resolution, scan all triaged comments for **simple fixes** — changes that meet ALL of these criteria:

- Single file affected
- Less than 10 lines changed
- Clear, unambiguous intent (not flagged as ⚠️ Ambiguous)
- No business logic involved
- No architectural impact
- Was categorized as "straightforward" in the triage step

If **3 or more** simple fixes are detected, present a batch offer to the user:

> **N comments are straightforward fixes** (typos, null checks, style nits, etc.). Apply all at once?
>
> | # | Tag | File | Fix |
> |---|-----|------|-----|
> | 1 | 🟡 | src/api.ts:12 | Add optional chaining |
> | 3 | 📝 | src/utils.ts:5 | Fix JSDoc typo |
> | 7 | 🟡 | src/auth.ts:30 | Remove unused import |
>
> **[yes]** — Apply all and resolve threads | **[no]** — Process one by one | **[pick]** — Choose which to batch

- **yes**: Apply all simple fixes, commit, push, resolve all their threads, then continue with the remaining complex comments in Step 6.
- **no**: Skip batching — process everything sequentially in Step 6.
- **pick**: Let the user select which of the simple fixes to batch. Apply selected ones, then continue with the rest sequentially.

If fewer than 3 simple fixes are detected, skip this step and go directly to Step 6.

## Step 6: Resolve Sequentially

Process remaining comments (those not already batch-resolved in Step 5.9) **one by one** in PR order, respecting the triage decisions from Step 5.5:

1. **Show a recap** of the current comment (tag, file, reviewer, what was asked).
2. **If this comment was flagged as "needs validation"** and was already validated in the triage step, use the user's confirmed answer to propose the fix. If it wasn't validated yet (e.g., the user skipped triage), use AskUserQuestion now — do NOT guess the correct business behavior.
3. **Propose the change** — show the specific edit you intend to make.
4. **Ask for confirmation** with these options:
   - **yes** — Apply the change as proposed
   - **no** — Skip this comment entirely
   - **modify** — Let the user adjust the proposed change before applying
   - **skip** — Skip for now, come back later
   - **reply-only** — Don't change code; draft a reply to the reviewer instead

5. **Enter Plan mode** when any of these conditions apply:
   - The change spans **multiple files**
   - The change involves **30+ lines** of modifications
   - The change has **architectural impact** (new patterns, structural changes)
   - The change affects **business logic** (pricing, permissions, workflows)
   - The comment is **ambiguous** and could be interpreted multiple ways
   - Two or more comments **conflict** with each other

   In Plan mode: analyze the full scope, present the plan to the user, and only proceed after approval.

6. **After applying the change**, commit and push before resolving the thread. A comment should only be marked as resolved on GitHub after the fix is committed and pushed to the PR branch (see Step 7).

## Step 7: Auto-Resolve Threads

Use the GraphQL mutation `resolveReviewThread` to mark threads as resolved on GitHub:

```graphql
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: { threadId: $threadId }) {
      thread {
        isResolved
      }
    }
  }' -f threadId='{threadId}'
```

The `threadId` comes from the `id` field on the `reviewThreads > nodes` fetched in Step 2.

### Rules for resolving:

- **Only resolve after commit+push** — a thread should only be marked resolved on GitHub after the corresponding code change has been committed and pushed to the PR branch. Never resolve a thread for a change that only exists locally.
- **Do NOT resolve** threads where the user chose **reply-only** — these need the reviewer's acknowledgment.
- **Do NOT resolve** threads tagged ❓ Question that were answered with reply-only.
- Only resolve threads that had actual code changes applied, committed, and pushed.

## Step 8: Summary

After resolving all selected items, present a summary table:

```md
## PR #123 — Resolution Summary

| #   | Tag | File            | Action Taken             | Thread      |
| --- | --- | --------------- | ------------------------ | ----------- |
| 1   | 🔴  | src/auth.ts:45  | Added null check         | ✅ Resolved |
| 2   | 🟡  | src/api.ts:80   | Used optional chaining   | ✅ Resolved |
| 3   | ❓  | src/api.ts:95   | Replied with explanation | ⏳ Open     |
| 4   | 👍  | src/auth.ts:60  | —                        | —           |
| 5   | ✨  | src/utils.ts:30 | Skipped by user          | ⏳ Open     |

### Files Modified

- src/auth.ts
- src/api.ts

### Next Steps

- Run your type checker and tests to verify nothing broke
- Use `/commit` to commit the changes
```
