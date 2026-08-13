# PR Skill Config Format

Local, private configuration for the `pr` skill. Lives at `pr/config.json` inside this
repo (reachable at `~/.claude/skills/pr/config.json` through the install symlink) and is
**gitignored** — it holds work-specific settings that must not reach the public repo.

`config.example.json` is the committed template. Copy it and fill in your own values:

```bash
cp ~/.claude/skills/pr/config.example.json ~/.claude/skills/pr/config.json
```

## Format

```json
{
  "orgs": {
    "acme-inc": {
      "team_reviewers": ["acme-inc/developers"],
      "reviewers": ["octocat"]
    }
  }
}
```

### Fields

| Field | Type | Description |
| ----- | ---- | ----------- |
| `orgs` | object | Keyed by GitHub organization login, exactly as `gh repo view --json owner -q '.owner.login'` returns it (case-sensitive). |
| `orgs.<org>.team_reviewers` | string[] | Teams to request review from, in `org/team-slug` form — the form `gh --add-reviewer` expects. A bare `developers` will not resolve. |
| `orgs.<org>.reviewers` | string[] | Individual GitHub usernames to request review from. |

Both list fields are optional; omit or leave empty when unused.

## Resolution Rules

- The org key must match the repository owner. Repos under an unlisted owner (personal
  projects, other orgs) get no reviewers — the skill skips the step silently.
- `team_reviewers` and `reviewers` are merged into a single request.
- The PR author is never requested as a reviewer; GitHub rejects that.
- Reviewers already requested on the PR are not re-requested, to avoid re-notifying them.

## Adding an Org

When creating a PR in an org that isn't in the config, the skill asks once whether you
want default reviewers for that org. Answering with a team or username persists it here;
declining records nothing and the skill stops asking for the rest of the conversation.
