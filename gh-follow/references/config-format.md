# gh-follow config

Optional file `~/.claude/skills/gh-follow/config.json` (through the install symlink, so it lives
in `gh-follow/config.json` in this repo, gitignored by `**/config.json`). When it is absent the
skill uses the local watcher (`scripts/gh-follow.sh`) and nothing else changes.

```json
{
  "service_url": "https://gh-follow.brorlandi.xyz",
  "api_token": "ghf_..."
}
```

| Key | Meaning |
| --- | --- |
| `service_url` | Base URL of the GH-follow service. |
| `api_token` | API token created in the service panel (API tokens → Create). Shown once; revoke it there. Keep the file `chmod 600`. |

`GH_FOLLOW_CONFIG` overrides the path (used by tests). `scripts/gh-follow-api.sh` passes the
token to `curl` through a temporary header file, so it never appears in the process list.
