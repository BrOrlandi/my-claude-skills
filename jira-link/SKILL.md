---
name: jira-link
description: Link GitHub PRs to Jira tasks and vice-versa. Automatically triggered after creating a PR (via /pr) or when working on Jira task status updates. Adds the Jira issue key to the PR title and adds the PR URL as a remote link on the Jira issue. Only activates for repositories belonging to GitHub organizations that have a configured Jira project mapping. Use when creating PRs, linking PRs to Jira, or when the user mentions connecting a PR with a Jira task.
---

# Jira-Link

Bidirectional linking between GitHub PRs and Jira issues: adds the Jira key to the PR title (for the Development panel) and adds the PR URL as a remote link on the Jira issue.

## When This Skill Applies

1. **After creating a PR** — check if the repo org has Jira configured, then offer to link.
2. **When explicitly asked** — user asks to link a PR to a Jira task.
3. **When updating Jira task status** — remind user to link if no PR is associated.

## When to Skip

- The repository does not belong to a configured GitHub organization (e.g., personal projects).
- The PR title already contains a Jira issue key.

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

### Step 3: Check if Already Linked

Check if the PR title already contains a Jira issue key matching the pattern `{PROJECT_PREFIX}-\d+`. If yes, inform the user it is already linked and stop.

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

**A) Add Jira key to PR title:**

```bash
gh pr edit {PR_NUMBER} --repo {OWNER}/{REPO} --title "{ISSUE_KEY} {ORIGINAL_TITLE}"
```

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
