---
name: jira-link
description: Link GitHub PRs to Jira tasks and normalize the Jira key position in PR titles. ALWAYS use this skill proactively, without waiting for the user to ask, in any of these situations: (1) immediately after creating, opening, or pushing a PR (including via /pr or `gh pr create`); (2) whenever a PR title is being set, edited, or proposed and the repo's GitHub org has a Jira project configured; (3) whenever the user mentions a Jira issue key like `PROJ-123` in the same conversation as a PR; (4) when transitioning, commenting on, or updating the status of a Jira issue that may have an associated PR; (5) when the user asks anything resembling "link this PR to Jira", "connect this with the task", "associate the PR with the issue", or similar. Adds the Jira issue key to the START of the PR title (format: `KEY: rest of title`), normalizes any pre-existing key already in the title (e.g. moves `[PROJ-111]` from the end to the start), turns the key mentioned in the PR body into a clickable markdown link to the Jira issue (when the current user authored the PR), and adds the PR URL as a remote link on the Jira issue. Only activates for repositories belonging to GitHub organizations that have a configured Jira project mapping; silently skips otherwise.
---

# Jira-Link

Bidirectional linking between GitHub PRs and Jira issues: ensures the Jira key is at the **start** of the PR title (the convention GitHub's Development panel and most Jira automations expect), makes the key **clickable in the PR body** so any reviewer can open the task in one click, and adds the PR URL as a remote link on the Jira issue.

## When This Skill Applies

Trigger this skill **proactively, without being asked**, in any of these scenarios:

1. **A PR was just created** — even if the title already contains a Jira key, run the skill to verify the key is at the start (and move it if not).
2. **A PR title is being authored or edited** — propose `KEY: <title>` form rather than embedding the key elsewhere.
3. **The user mentions a Jira key (e.g. `PROJ-123`) alongside a PR or branch** — assume they want it linked and offer to link without making them ask.
4. **A Jira issue is being transitioned or commented on** — if a PR exists on the current branch and isn't yet linked, link it before/after the transition.
5. **The user explicitly asks** to link, connect, or associate a PR with a Jira task.

## When to Skip

- The repository does not belong to a configured GitHub organization (e.g., personal projects).
- No PR exists on the current branch and none was just created.
- The PR title is already in the canonical form `KEY: <rest>` (key at the very start, followed by `:` and a space) AND the PR body already links the key to Jira AND a remote link for that issue already exists on the Jira side.

Partial skips: each of the three actions (title, body, remote link) is independently skippable. A canonical title is not a reason to skip the body link, and vice versa.

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
2. Ask the user: "This repo belongs to **{org}**. Do you use Jira for this organization? If so, what is the Jira project key (e.g., PROJ)?"
3. If yes, save the mapping to `~/.config/jira-link/config.json` — including `jira_site` (the Atlassian base URL, e.g. `https://acme.atlassian.net`) — and proceed.
4. If no, skip silently. Do not ask again in this conversation.

### Resolving the Jira Base URL

Needed for both the body link and the remote link. Use the first source that yields an absolute `https://…` URL:

```bash
JIRA_LINK_CONFIG="$HOME/.config/jira-link/config.json"
JIRA_CONFIG="${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"
ENV_JIRA_URL="${JIRA_URL:-}"   # capture before overwriting

# 1) jira_site for this org in the jira-link config
JIRA_URL=$(python3 -c "
import json
cfg = json.load(open('$JIRA_LINK_CONFIG'))
print(cfg['orgs'].get('$ORG', {}).get('jira_site', '').rstrip('/'))
" 2>/dev/null)

# 2) the JIRA_URL env var, if it was already exported
[ -n "$JIRA_URL" ] || JIRA_URL="$ENV_JIRA_URL"

# 3) the jira CLI config — parsed with sed, since PyYAML is not always installed
[ -n "$JIRA_URL" ] || JIRA_URL=$(sed -n 's/^server:[[:space:]]*//p' "$JIRA_CONFIG" 2>/dev/null \
  | tr -d '"'"'"' ' | head -1 | sed 's:/*$::')

echo "$JIRA_URL"   # must be an absolute https:// URL before continuing
```

If all three come up empty, ask the user for the Atlassian base URL once and persist it as `jira_site` under the org in `~/.config/jira-link/config.json`. Do not proceed with an empty URL — a relative `/browse/KEY` link is broken on GitHub.

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

- **Canonical** — title starts with `KEY:` followed by a space (e.g. `PROJ-111: fix(...)`). Skip retitling. Proceed to Step 6B (body link) and Step 6C (remote link), then stop.
- **Misplaced** — title contains a Jira key but **not** at the canonical position. Examples: `fix(...): something [PROJ-111]`, `[PROJ-111] fix(...)`, `fix(PROJ-111): something`, or any embedded form. Strip the key and surrounding decoration (brackets, parens, trailing colons, leading/trailing whitespace, redundant separators) and continue with that key — go straight to Step 6A to retitle. Do **not** ask the user to pick an issue: the title already names one.
- **Absent** — no key found. Continue to Step 4 to find a candidate.

When stripping a misplaced key, also clean up adjacent artifacts so the result reads naturally:
- `fix(...): something [PROJ-111]` → strip `[PROJ-111]` and any leading whitespace before it → `fix(...): something`
- `[PROJ-111] fix(...)` → strip `[PROJ-111] ` → `fix(...)`
- `fix(PROJ-111): something` (key inside a conventional-commit scope) → leave alone (the key is part of the scope by intent); treat as canonical-enough and only ensure the body link and remote link exist.

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

`{CLEANED_TITLE}` is the original title with any misplaced occurrence of the same key (and surrounding brackets/whitespace) removed per the rules in Step 3. Never produce duplicates like `PROJ-111: fix(...) [PROJ-111]`.

**Examples:**
- Original: `fix(shipments): redesign review step [PROJ-111]` → New: `PROJ-111: fix(shipments): redesign review step`
- Original: `[PROJ-111] feat(api): add webhook` → New: `PROJ-111: feat(api): add webhook`
- Original: `feat(api): add webhook` (no key) → New: `PROJ-111: feat(api): add webhook`

**B) Make the Jira key clickable in the PR body.**

A key in the title is not clickable — GitHub renders titles as plain text. Reviewers who want to read the task have to copy the key and paste it into Jira. So the body must always carry a markdown link to the issue: `[KEY](JIRA_URL/browse/KEY)`.

**Only edit the body when the current user is the PR author.** Rewriting someone else's PR description is intrusive even with write access.

```bash
VIEWER=$(gh api user -q '.login')
AUTHOR=$(gh pr view {PR_NUMBER} --repo {OWNER}/{REPO} --json author -q '.author.login')
```

If `VIEWER` != `AUTHOR`, skip this step. Mention the missing link to the user and offer to post it as a PR comment instead — do not edit the body.

If the user authored the PR, apply the edit with the helper script (it reads the body from `--body-file` or stdin and writes the updated body to stdout). Resolve `JIRA_URL` as described in **Resolving the Jira Base URL** — this step needs no Jira credentials, only the site URL.

```bash
SKILL_DIR="$HOME/.claude/skills/jira-link"

gh pr view {PR_NUMBER} --repo {OWNER}/{REPO} --json body -q '.body' > /tmp/pr-body.md
python3 "$SKILL_DIR/scripts/link_jira_in_body.py" \
  --key {ISSUE_KEY} --jira-url "$JIRA_URL" --body-file /tmp/pr-body.md > /tmp/pr-body-linked.md
# stderr reports: linked | inserted | unchanged
gh pr edit {PR_NUMBER} --repo {OWNER}/{REPO} --body-file /tmp/pr-body-linked.md
```

Skip the `gh pr edit` when the script reports `unchanged`.

What the script does, and what to reproduce if editing the body by hand:

- **Key already mentioned in prose** → wrap that mention in a markdown link. `Closes PROJ-123.` → `Closes [PROJ-123](https://acme.atlassian.net/browse/PROJ-123).`
- **Key not mentioned at all** → prepend a `Jira: [KEY](url)` line at the top of the body, followed by a blank line.
- **Key already linked** (a markdown link or a raw URL pointing at `/browse/KEY`) → leave the body untouched.
- **Only the first bare mention gets linked.** Repeating the same link on every mention is noise.
- **Never rewrite mentions inside code fences, inline code, existing links, autolinks or URLs.** A key inside a code sample or a branch name is content, not a reference.
- **Change nothing else in the body.** This step inserts a link; it does not reword, reformat or re-summarize the description.

**C) Add PR as remote link on Jira issue:**

Unlike the body link, this step needs credentials. `JIRA_URL` comes from **Resolving the Jira Base URL**; the login email comes from the jira CLI config or `$JIRA_EMAIL`:

```bash
JIRA_CONFIG="${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"
JIRA_EMAIL="${JIRA_EMAIL:-$(sed -n 's/^login:[[:space:]]*//p' "$JIRA_CONFIG" 2>/dev/null | tr -d '"'"'"' ' | head -1)}"

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
- Jira link added to the PR body (or: skipped because the PR belongs to another author)
- Remote link added to Jira issue
- Provide the Jira issue URL: `{JIRA_URL}/browse/{ISSUE_KEY}`

State which steps were no-ops rather than implying all three were applied.
