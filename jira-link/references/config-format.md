# Jira-Link Configuration

The skill stores org mapping in `~/.config/jira-link/config.json`.

## Format

```json
{
  "orgs": {
    "github-org-name": {
      "jira_project_prefix": "PROJ",
      "jira_site": "https://acme.atlassian.net",
      "jira_board": "PROJ board"
    }
  }
}
```

- `orgs`: Maps GitHub organization names (lowercase) to their Jira configuration.
- `jira_project_prefix`: The Jira project key prefix (e.g., "PROJ") used to filter issues.
- `jira_site`: The Atlassian base URL, no trailing slash. Used to build `{jira_site}/browse/{KEY}` links in PR bodies. Falls back to `$JIRA_URL` or the `server:` field of the jira CLI config when absent — set it here so the body link works without the jira CLI installed.
- `jira_board`: Optional. The Jira board name for context.

## Example

A user working in `acme-inc` GitHub org with Jira project `PROJ`:

```json
{
  "orgs": {
    "acme-inc": {
      "jira_project_prefix": "PROJ",
      "jira_site": "https://acme.atlassian.net"
    }
  }
}
```

Multiple orgs can be configured:

```json
{
  "orgs": {
    "acme-inc": {
      "jira_project_prefix": "PROJ"
    },
    "another-org": {
      "jira_project_prefix": "AO"
    }
  }
}
```
