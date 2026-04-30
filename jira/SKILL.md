---
name: jira
description: Interact with Jira using the jira CLI and REST API. View, create, list, transition, and comment on issues. Supports proper @mentions that notify users. Query activity reports showing who did what (created, edited, commented, moved issues, etc.) over a time period. Use when the user wants to work with Jira issues — view a ticket, add a comment, mention someone, list issues, create tasks, move issues between statuses, assign issues, or check recent activity/what was done.
---

# Jira

Manage Jira issues via the `jira` CLI ([ankitpokhrel/jira-cli](https://github.com/ankitpokhrel/jira-cli)) and the Jira REST API v3 for advanced features like @mentions.

## Setup

Before first use, check if the jira CLI is installed and configured:

```bash
jira me
```

If this returns the user's info, setup is complete. Otherwise, follow these steps:

### 1. Install the jira CLI

```bash
# macOS
brew install ankitpokhrel/jira-cli/jira-cli

# Linux / other
go install github.com/ankitpokhrel/jira-cli/cmd/jira@latest
```

### 2. Create a Jira API token

Go to https://id.atlassian.com/manage-profile/security/api-tokens and create a new token.

### 3. Set the API token as environment variable

Add to `~/.zshrc` or `~/.bashrc`:

```bash
export JIRA_API_TOKEN="your-token-here"
```

Then reload: `source ~/.zshrc`

### 4. Initialize the jira CLI

```bash
jira init
```

This will prompt for:

- **Installation type**: Cloud
- **Jira server URL**: `https://YOUR-SITE.atlassian.net`
- **Login email**: your Atlassian email
- **Default project**: your project key (e.g. `PROJ`)
- **Default board**: select your board

### 5. Verify

```bash
jira me
jira issue list --plain --paginate 5
```

## Project Selection

The skill stores the last used project in `.config.json` (gitignored). Before creating or listing issues, read this file to get the default project:

```bash
cat /Users/brunoorlandi/Projects/my-claude-skills/jira/.config.json
```

Use the `lastProject` value as the default `-p` flag. After successfully using a different project, update the file.

## Creating Issues

When creating issues, follow this process:

1. **Draft first, create after approval.** Always present the full title and description to the user for review before creating the issue in Jira. Never create an issue without explicit user approval of the content.
2. **Use default priority.** Do not set priority (let Jira use its default, typically Medium) unless the user explicitly specifies a priority level.
3. **Pre-creation duplicate check (MANDATORY).** Before POSTing, query the 5 most recent issues created by the current user in the same project and verify no existing issue matches the summary. If a match is found, STOP and ask the user whether to abort, proceed, or link to the existing issue.
4. After approval, create the issue via REST API with ADF description format, following the robust-call protocol below.
5. **Post-creation verification (MANDATORY).** After the POST returns, re-query the 5 most recent issues and confirm exactly one new issue matches the summary. If two appear, delete the duplicate immediately and inform the user.

### Robust-call protocol (prevents accidental duplicates)

Shell output may be summarized, truncated, or wrapped by proxies (e.g. `rtk`, pagers). Never retry a create/mutation call just because the response looked "weird" — always inspect the HTTP status and parse the key from a file. If unsure, run the pre/post duplicate check before retrying.

```bash
# 1. Pre-check: list last 5 issues reported by me in project $PROJECT
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -X POST -H "Content-Type: application/json" \
  -d "{\"jql\":\"project = $PROJECT AND reporter = currentUser() ORDER BY created DESC\",\"fields\":[\"summary\",\"created\"],\"maxResults\":5}" \
  "$JIRA_URL/rest/api/3/search/jql" -o /tmp/jira_precheck.json
python3 -c "
import json,sys
d=json.load(open('/tmp/jira_precheck.json'))
target=sys.argv[1].strip().lower()
for i in d.get('issues',[]):
    s=i['fields']['summary'].strip().lower()
    if s==target:
        print('DUPLICATE FOUND:', i['key'], i['fields']['summary'])
        sys.exit(1)
print('OK: no duplicate in last 5')
" "SUMMARY HERE" || exit 1

# 2. Create — ALWAYS write body to file and capture HTTP status separately
HTTP=$(curl -s -X POST -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -H "Content-Type: application/json" \
  -d @/tmp/jira_task_payload.json \
  "$JIRA_URL/rest/api/3/issue" -o /tmp/jira_create_result.json -w "%{http_code}")
echo "HTTP $HTTP"
KEY=$(python3 -c "import json; print(json.load(open('/tmp/jira_create_result.json')).get('key',''))")
echo "Created: $KEY"

# 3. Post-check: confirm no duplicate was created
# (same query as step 1; assert the summary appears exactly once)
```

**Rules:**
- Treat HTTP 201 as success — do **not** re-run the POST, even if the stdout looks empty/odd.
- If HTTP is missing or non-2xx, run the pre-check query again to see what actually exists before retrying.
- Never run `curl ... | python3` for create/mutation calls — pipes can swallow response bodies on proxy interference. Always `-o <file>` then parse.

## Assignee Suggestion

When creating or assigning issues, proactively suggest the logged-in user as assignee. After running `jira me` to confirm setup, use the result to offer assignment without requiring the user to specify. For example, if the user asks to create tasks, ask if they want them assigned to themselves.

To assign via REST API (the CLI `--no-input` flag is not supported on `jira issue move`):

```bash
JIRA_CONFIG="${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"
JIRA_URL=$(python3 -c "import yaml; print(yaml.safe_load(open('$JIRA_CONFIG'))['server'].rstrip('/'))")
JIRA_EMAIL=$(python3 -c "import yaml; print(yaml.safe_load(open('$JIRA_CONFIG'))['login'])")

# Get current user's account ID
ACCOUNT_ID=$(curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_URL/rest/api/3/myself" | python3 -c "import sys,json; print(json.load(sys.stdin)['accountId'])")

# Assign issue
curl -s -X PUT -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -H "Content-Type: application/json" \
  -d "{\"fields\":{\"assignee\":{\"accountId\":\"$ACCOUNT_ID\"}}}" \
  "$JIRA_URL/rest/api/3/issue/ISSUE-KEY"
```

To assign to another user, search by name first:

```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_URL/rest/api/3/user/search?query=NAME"
```

## Quick Reference

### View an issue

```bash
jira issue view ISSUE-KEY
jira issue view ISSUE-KEY --raw  # Full JSON with account IDs
```

### List issues

```bash
jira issue list --plain --no-truncate
jira issue list -s "In Progress" --plain
jira issue list -q "assignee = currentUser() AND status != Done" --plain
```

### Add a simple comment (no mention)

```bash
jira issue comment add ISSUE-KEY "Comment text" --no-input
```

### Move/transition an issue

```bash
jira issue move ISSUE-KEY "In Progress"
```

**Note:** `jira issue move` does NOT support `--no-input`. If the CLI prompts interactively, use the REST API instead:

```bash
# First, get available transitions for the issue
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_URL/rest/api/3/issue/ISSUE-KEY/transitions"

# Then transition using the transition ID
curl -s -X POST -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -H "Content-Type: application/json" \
  -d '{"transition":{"id":"TRANSITION_ID"}}' \
  "$JIRA_URL/rest/api/3/issue/ISSUE-KEY/transitions"
```

### Create an issue

```bash
jira issue create -tTask -s "Summary text" --no-input
```

## Comments with @Mentions

The jira CLI does **not** support @mentions — text like `@Name` renders as plain text without notifications. Use the REST API or the bundled script instead.

### Step-by-step process

1. **Find the user's account ID** from the issue data:

```bash
jira issue view ISSUE-KEY --raw
```

Look for `accountId` in `creator`, `reporter`, `assignee`, or comment `author` fields.

2. **Add comment with mention** using the bundled script:

```bash
scripts/jira_comment_with_mention.sh ISSUE-KEY "ACCOUNT_ID" "Display Name" "Comment text"
```

Or use curl directly with ADF format — see `references/jira-rest-api.md` for the JSON structure.

### If the user is not on the issue

Search for users via REST API:

```bash
JIRA_CONFIG="${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"
JIRA_URL=$(python3 -c "import yaml; print(yaml.safe_load(open('$JIRA_CONFIG'))['server'].rstrip('/'))")
JIRA_EMAIL=$(python3 -c "import yaml; print(yaml.safe_load(open('$JIRA_CONFIG'))['login'])")

curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$JIRA_URL/rest/api/3/user/search?query=NAME"
```

## Activity Report

To see all activities performed on Jira issues over a time period, use the bundled script:

```bash
scripts/jira_activity_report.sh [DAYS] [PROJECT]
```

- `DAYS` — Number of days to look back (default: 3)
- `PROJECT` — Jira project key to filter (optional, searches all projects if omitted)

**Examples:**

```bash
# All activities in the last 3 days across all projects
scripts/jira_activity_report.sh

# Last 7 days, only project BE
scripts/jira_activity_report.sh 7 BE

# Today only
scripts/jira_activity_report.sh 1
```

The script uses the REST API v3 (`/rest/api/3/search/jql` POST endpoint + `/rest/api/3/issue/{key}/changelog`) to fetch issues updated in the period, then collects changelogs in parallel. It detects and reports these activity types:

- **Issue creation** — who created, issue type
- **Status changes** — kanban column moves (e.g. Backlog -> In Progress -> Done)
- **Assignee changes** — who reassigned to whom
- **Title/description edits** — content modifications
- **Priority changes**
- **Sprint changes** — moved between sprints
- **Label changes**
- **Board reordering** — Rank changes
- **Resolution changes**
- **Attachments and links** — files and remote links (e.g. PRs)
- **Parent/component changes**
- **Comments** — with text preview (first 80 chars)
- **Due date and story point changes**

Output is grouped by user, with a summary count of each action type and chronological detail.

**Important API notes:**
- The old `/rest/api/3/search` GET endpoint has been removed. Always use `POST /rest/api/3/search/jql` with JSON body.
- Pagination uses `nextPageToken` / `isLast` fields (not `startAt`).
- Changelogs are fetched per-issue via `GET /rest/api/3/issue/{key}/changelog`.
- Datetime strings from Jira may use offset format without colon (e.g. `-0300` instead of `-03:00`). The script handles both.

## Important Notes

- Always use `--no-input` flag to avoid interactive prompts that hang.
- Always use `--raw` when you need to extract structured data (account IDs, status IDs, etc.).
- For full CLI command reference, see `references/jira-cli-reference.md`.
- For REST API details (ADF format, auth, delete/edit comments), see `references/jira-rest-api.md`.
