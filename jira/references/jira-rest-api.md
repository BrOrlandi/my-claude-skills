# Jira REST API v3 Reference

Use the REST API when the jira CLI doesn't support a feature (e.g., mentions, searching users).

## Authentication

The jira CLI authenticates via:
- **Config file** (`~/.config/.jira/.config.yml`): stores `server` URL and `login` email
- **Environment variable** `JIRA_API_TOKEN`: the API token

To get credentials for REST API calls:
```bash
# Server URL and email from jira CLI config
JIRA_CONFIG="${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"
JIRA_URL=$(python3 -c "import yaml; print(yaml.safe_load(open('$JIRA_CONFIG'))['server'].rstrip('/'))")
JIRA_EMAIL=$(python3 -c "import yaml; print(yaml.safe_load(open('$JIRA_CONFIG'))['login'])")

# API token from environment (required)
echo $JIRA_API_TOKEN
```

All API calls use Basic Auth: `-u "$JIRA_EMAIL:$JIRA_API_TOKEN"`

If the user hasn't set up the jira CLI, they can set all three env vars instead: `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`.

## Finding User Account IDs

Required for mentions. Extract from issue JSON:

```bash
# From issue raw output - look for creator, reporter, assignee, or comment authors
jira issue view ISSUE-KEY --raw | python3 -c "
import sys, json
data = json.load(sys.stdin)
fields = data['fields']
for role in ['creator', 'reporter', 'assignee']:
    user = fields.get(role)
    if user:
        print(f\"{role}: {user['displayName']} -> {user['accountId']}\")
"
```

Or search via REST API:
```bash
curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_URL/rest/api/3/user/search?query=NAME" \
  | python3 -m json.tool
```

## Adding Comments with Mentions

The Jira REST API v3 uses ADF (Atlassian Document Format). A mention node looks like:

```json
{
  "body": {
    "type": "doc",
    "version": 1,
    "content": [{
      "type": "paragraph",
      "content": [
        {
          "type": "mention",
          "attrs": {
            "id": "ACCOUNT_ID",
            "text": "@Display Name",
            "accessLevel": ""
          }
        },
        {
          "type": "text",
          "text": " Rest of the comment"
        }
      ]
    }]
  }
}
```

```bash
curl -s -X POST \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/3/issue/ISSUE-KEY/comment" \
  -d '{ ... ADF body ... }'
```

Use `scripts/jira_comment_with_mention.sh` for convenience.

## Deleting a Comment

```bash
curl -s -X DELETE \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "$JIRA_URL/rest/api/3/issue/ISSUE-KEY/comment/COMMENT_ID"
```

## Editing a Comment

```bash
curl -s -X PUT \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/3/issue/ISSUE-KEY/comment/COMMENT_ID" \
  -d '{ ... ADF body ... }'
```
