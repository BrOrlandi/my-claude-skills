---
name: jira
description: Interact with Jira using the jira CLI and REST API. View, create, list, transition, and comment on issues. Supports proper @mentions that notify users. Use when the user wants to work with Jira issues — view a ticket, add a comment, mention someone, list issues, create tasks, move issues between statuses, or assign issues.
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
3. After approval, create the issue via REST API with ADF description format.

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

## Important Notes

- Always use `--no-input` flag to avoid interactive prompts that hang.
- Always use `--raw` when you need to extract structured data (account IDs, status IDs, etc.).
- For full CLI command reference, see `references/jira-cli-reference.md`.
- For REST API details (ADF format, auth, delete/edit comments), see `references/jira-rest-api.md`.
