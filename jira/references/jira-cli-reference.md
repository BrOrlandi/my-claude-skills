# Jira CLI Reference

## Common Commands

### View an issue
```bash
jira issue view ISSUE-KEY
jira issue view ISSUE-KEY --raw  # JSON output with full details (account IDs, etc.)
```

### List issues
```bash
jira issue list --plain --no-truncate  # Plain text, all columns
jira issue list -s "In Progress"       # Filter by status
jira issue list -a "user@email.com"    # Filter by assignee
jira issue list -q "JQL query"         # Raw JQL
jira issue list --raw                  # JSON output
```

### Create an issue
```bash
jira issue create -tTask -s "Summary" --no-input
jira issue create -tBug -s "Summary" -yHigh --no-input
```

### Move/transition an issue
```bash
jira issue move ISSUE-KEY "In Progress" --no-input
jira issue move ISSUE-KEY "Done" --no-input
```

### Assign an issue
```bash
jira issue assign ISSUE-KEY "user@email.com"
jira issue assign ISSUE-KEY x  # Unassign
```

### Add comment (simple, no mentions)
```bash
jira issue comment add ISSUE-KEY "Comment text" --no-input
```

### Sprints
```bash
jira sprint list --plain
jira sprint list --state active --plain
```

## Important Flags

- `--no-input`: Skip interactive prompts (required for non-interactive use)
- `--raw`: Output raw JSON (useful for extracting account IDs and other metadata)
- `--plain`: Plain text table output
- `-p PROJECT`: Override default project

## Configuration

Config file: `~/.config/.jira/.config.yml`

Contains: server URL, login email, default project, board ID.

## Limitations

- The `jira issue comment add` command does NOT support @mentions. Comments added this way render `@Name` as plain text without notifications.
- No built-in way to search users by name to get their account ID.
- Interactive commands (without `--no-input`) will hang in non-interactive environments.
