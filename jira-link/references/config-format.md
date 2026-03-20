# Jira-Link Configuration

The skill stores org mapping in `~/.config/jira-link/config.json`.

## Format

```json
{
  "orgs": {
    "github-org-name": {
      "jira_project_prefix": "BE",
      "jira_board": "BE board"
    }
  }
}
```

- `orgs`: Maps GitHub organization names (lowercase) to their Jira configuration.
- `jira_project_prefix`: The Jira project key prefix (e.g., "BE") used to filter issues.
- `jira_board`: Optional. The Jira board name for context.

## Example

A user working in `beuni-tecnologia` GitHub org with Jira project `BE`:

```json
{
  "orgs": {
    "beuni-tecnologia": {
      "jira_project_prefix": "BE"
    }
  }
}
```

Multiple orgs can be configured:

```json
{
  "orgs": {
    "beuni-tecnologia": {
      "jira_project_prefix": "BE"
    },
    "another-org": {
      "jira_project_prefix": "AO"
    }
  }
}
```
