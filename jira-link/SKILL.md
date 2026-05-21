---
name: jira-link
description: Link GitHub PRs to Jira tasks and normalize the Jira key position in PR titles. ALWAYS use this skill proactively, without waiting for the user to ask, in any of these situations: (1) immediately after creating, opening, or pushing a PR (including via /pr or `gh pr create`); (2) whenever a PR title is being set, edited, or proposed and the repo's GitHub org has a Jira project configured; (3) whenever the user mentions a Jira issue key like `BE-123` in the same conversation as a PR; (4) when transitioning, commenting on, or updating the status of a Jira issue that may have an associated PR; (5) when the user asks anything resembling "link this PR to Jira", "connect this with the task", "associate the PR with the issue", or similar. Adds the Jira issue key to the START of the PR title (format: `KEY: rest of title`), normalizes any pre-existing key already in the title (e.g. moves `[BE-111]` from the end to the start), and adds the PR URL as a remote link on the Jira issue. Only activates for repositories belonging to GitHub organizations that have a configured Jira project mapping; silently skips otherwise.
---

# Jira-Link

Bidirectional linking between GitHub PRs and Jira issues: ensures the Jira key is at the **start** of the PR title (the convention GitHub's Development panel and most Jira automations expect) and adds the PR URL as a remote link on the Jira issue.

## When This Skill Applies

Trigger this skill **proactively, without being asked**, in any of these scenarios:

1. **A PR was just created** — even if the title already contains a Jira key, run the skill to verify the key is at the start (and move it if not).
2. **A PR title is being authored or edited** — propose `KEY: <title>` form rather than embedding the key elsewhere.
3. **The user mentions a Jira key (e.g. `BE-123`) alongside a PR or branch** — assume they want it linked and offer to link without making them ask.
4. **A Jira issue is being transitioned or commented on** — if a PR exists on the current branch and isn't yet linked, link it before/after the transition.
5. **The user explicitly asks** to link, connect, or associate a PR with a Jira task.

## When to Skip

- The repository does not belong to a configured GitHub organization (e.g., personal projects).
- No PR exists on the current branch and none was just created.
- The PR title is already in the canonical form `KEY: <rest>` (key at the very start, followed by `:` and a space) AND a remote link for that issue already exists on the Jira side.

## Jira Status Transitions Around PRs

The Jira status of an issue should track real-world progress, not just GitHub state. Default status flow tied to PR events:

- **PR created (or moved out of draft)** — transition issue to **In Progress** (if not already there) so the kanban reflects active work.
- **PR approved / ready to merge** — transition issue to **Review**.
- **PR merged into the integration branch** (e.g. `develop`) — **leave the issue in Review**, do NOT move to Done. Merging to `develop` only means the change has shipped to staging; it has not reached production yet.
- **Deploy to production** (typically when `develop` → `main` is merged/deployed) — transition issue to **Done**. This is the only moment that closes the loop, because production is the user-facing surface.

When unsure which step the user is at, ask before transitioning. If the user explicitly tells you "move to Done" after a `develop` merge, surface this convention so they can confirm — they may be skipping the production-deploy gate intentionally, or they may have forgotten the rule.

If the project's branching model differs (e.g. trunk-based with no `develop`), substitute the equivalent: integration branch merge keeps **Review**, production deploy moves to **Done**.

## Configuration

Org-to-Jira mapping is stored in `~/.config/jira-link/config.json`. See `references/config-format.md` for format details.

### First-Time Setup

If config file does not exist or the current repo's GitHub org is not mapped:

1. Detect the GitHub org: `gh repo view --json owner -q '.owner.login'`
2. Ask the user: "This repo belongs to **{org}**. Do you use Jira for this organization? If so, what is the Jira project key (e.g., BE)?"
3. If yes, save the mapping to `~/.config/jira-link/config.json` and proceed.
4. If no, skip silently. Do not ask again in this conversation.

## Linking Process

### Step 1: Check Applicability

```bash
# Get the GitHub org for the current repo
ORG=$(gh repo view --json owner -q '.owner.login')
```

Read `~/.config/jira-link/config.json` and check if `ORG` exists in `orgs`. If not, run First-Time Setup above.

### Step 2: Identify the PR

If a PR was just created (called from /pr), use that PR number. Otherwise:

```bash
gh pr list --head "$(git branch --show-current)" --json number,title,url --limit 1
```

### Step 3: Detect Existing Jira Key in the PR Title

Scan the PR title for the pattern `{PROJECT_PREFIX}-\d+` (case-insensitive). Three outcomes:

- **Canonical** — title starts with `KEY:` followed by a space (e.g. `BE-111: fix(...)`). Skip retitling. Proceed to Step 6B to ensure the remote link exists, then stop.
- **Misplaced** — title contains a Jira key but **not** at the canonical position. Examples: `fix(...): something [BE-111]`, `[BE-111] fix(...)`, `fix(BE-111): something`, or any embedded form. Strip the key and surrounding decoration (brackets, parens, trailing colons, leading/trailing whitespace, redundant separators) and continue with that key — go straight to Step 6A to retitle. Do **not** ask the user to pick an issue: the title already names one.
- **Absent** — no key found. Continue to Step 4 to find a candidate.

When stripping a misplaced key, also clean up adjacent artifacts so the result reads naturally:
- `fix(...): something [BE-111]` → strip `[BE-111]` and any leading whitespace before it → `fix(...): something`
- `[BE-111] fix(...)` → strip `[BE-111] ` → `fix(...)`
- `fix(BE-111): something` (key inside a conventional-commit scope) → leave alone (the key is part of the scope by intent); treat as canonical-enough and only ensure the remote link exists.

### Step 4: Find Candidate Jira Issues

Query Jira for in-progress issues assigned to the current user:

```bash
jira issue list -p {PROJECT_PREFIX} -q "assignee = currentUser() AND status != Done" --plain --no-truncate
```

### Step 5: Ask User to Select

Present the list of candidate issues and ask which one to link. Allow the user to:
- Select one issue from the list
- Type a specific issue key manually
- Skip linking

### Step 6: Apply the Link (bidirectional)

**A) Set the PR title with the Jira key at the start.**

The canonical format is `KEY: <rest of title>`. The key always goes at the very beginning, separated by `: ` (colon + space). This is what GitHub's Development panel and Jira automations expect, and it keeps merge-commit messages searchable by Jira key.

```bash
gh pr edit {PR_NUMBER} --repo {OWNER}/{REPO} --title "{ISSUE_KEY}: {CLEANED_TITLE}"
```

`{CLEANED_TITLE}` is the original title with any misplaced occurrence of the same key (and surrounding brackets/whitespace) removed per the rules in Step 3. Never produce duplicates like `BE-111: fix(...) [BE-111]`.

**Examples:**
- Original: `fix(shipments): redesign review step [BE-111]` → New: `BE-111: fix(shipments): redesign review step`
- Original: `[BE-111] feat(api): add webhook` → New: `BE-111: feat(api): add webhook`
- Original: `feat(api): add webhook` (no key) → New: `BE-111: feat(api): add webhook`

**B) Add PR as remote link on Jira issue:**

```bash
JIRA_CONFIG="${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"
JIRA_URL=$(python3 -c "import yaml; print(yaml.safe_load(open('$JIRA_CONFIG'))['server'].rstrip('/'))")
JIRA_EMAIL=$(python3 -c "import yaml; print(yaml.safe_load(open('$JIRA_CONFIG'))['login'])")

curl -s -X POST -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "object": {
      "url": "{PR_URL}",
      "title": "PR #{PR_NUMBER}: {PR_TITLE}",
      "icon": {"url16x16": "https://github.com/favicon.ico", "title": "GitHub PR"}
    }
  }' \
  "$JIRA_URL/rest/api/3/issue/{ISSUE_KEY}/remotelink"
```

### Step 7: Confirm

Report to the user:
- PR title updated with issue key
- Remote link added to Jira issue
- Provide the Jira issue URL: `{JIRA_URL}/browse/{ISSUE_KEY}`
