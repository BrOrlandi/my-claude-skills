# Central service (design, not built)

A single personal service on the Oracle VPS that follows the PRs the `gh-follow` skill
registers and merges the user's own PRs under the policy in `merge-after-approval.md`. The Mac
only registers and queries; the Mac can sleep. Nothing here exists yet: no repository,
container, domain or token has been created.

## Constraints

- Hosted on the Oracle VPS (`infra-orlandi`), not on the HomeServer or the Mac.
- No GitHub App on the followed repos, no webhooks, no change to any repo or org setting, no
  dependence on native auto-merge.
- Follows only PRs explicitly registered. No `--mine`-style discovery.
- Merges only the user's own PRs, each authorized individually with its HEAD SHA. Approves
  nothing.
- No model calls in the routine loop.
- No new open ports, and no assumption about credentials that do not exist yet.

## Architecture

```text
Mac (skill / browser)  --HTTPS 443-->  Traefik (web-secure, Let's Encrypt)
                                           |
                                    pr-follow service (one container)
                                      |- API + panel
                                      |- scheduler/worker loop
                                      `- GitHub client (REST + GraphQL, user token)
                                           |
                                    Postgres (Dokploy-managed, backups to OCI Object Storage)
```

- **One container** with three parts sharing a process: the HTTP API, a server-rendered panel,
  and the worker loop. Suggested stack: TypeScript on Node (Hono or Fastify), plain `fetch` to
  the GitHub API. Calling the API directly lets the merge pin the SHA and read rate-limit
  headers, so the server does not need the `gh` CLI. `gh` stays on the Mac for the skill.
- **Postgres** as both the store and the persistent queue. It is a Dokploy-managed database,
  so it gets the existing scheduled backups to the `OCI Object Storage (sa-saopaulo)`
  destination with no new tooling. SQLite plus Litestream to the same bucket is the lighter
  alternative if a second database container is unwelcome.

### Data

| Table | Holds |
| --- | --- |
| `followed_prs` | `owner`, `repo`, `number` (unique: deduplication), status, last snapshot (JSON), `next_check_at`, backoff counter, `etag` |
| `merge_authorizations` | PR, `head_sha`, `merge_method`, checks policy (`all` / `required` / names), `authorized_at`, `authorized_via` (panel or API client), `revoked_at` |
| `events` | Derived events (approved, checks, conflict, merged, authorization lapsed…), shown in the panel and returned to the skill |
| `merge_attempts` | Audit: PR, SHA, the policy snapshot evaluated, GitHub response code, result. Never request headers |
| `api_clients` | Name, hash of the API token (argon2/bcrypt), created/last used, revoked |

### Worker loop

- Picks due PRs with `SELECT … WHERE next_check_at <= now() FOR UPDATE SKIP LOCKED`, so a
  restart or a second replica never checks the same PR twice and nothing is lost on restart.
- **Trigger**: one `GET /notifications` per `X-Poll-Interval` (60 s) with `If-Modified-Since`.
  A `304` costs nothing. A notification about a registered PR moves its `next_check_at` to now.
  This covers comments and reviews; CI is not covered, hence the schedule below.
- **Adaptive schedule per PR**: 60 s while checks are running or right after a trigger, 5 min
  while waiting for a review, 30 min after a day without changes, stop when merged or closed.
  On errors, exponential backoff up to 30 min. Honor `Retry-After` and pause everything when
  `X-RateLimit-Remaining` gets low.
- **Merge step**, only for a PR with a live authorization: re-fetch everything in one query,
  evaluate the policy, then `PUT …/pulls/{n}/merge` with `sha` = authorized HEAD. On a moved
  HEAD the authorization lapses and an event asks the user to re-authorize. Every attempt is
  recorded in `merge_attempts`. The step is idempotent per (PR, SHA).

### API (for the skill) and panel

- `POST /api/prs` register a PR · `DELETE /api/prs/:id` stop following ·
  `GET /api/prs` status of all · `GET /api/events?since=` news since a cursor ·
  `POST /api/prs/:id/authorize` (body: `head_sha`, method, checks policy) ·
  `POST /api/prs/:id/revoke`.
- The panel lists registered PRs by org and repo with their state (review, checks, conflicts,
  authorization), and lets the user authorize, showing the exact HEAD SHA being authorized, or
  revoke.
- The skill keeps `gh-follow.sh` for local use. With the service configured, "follow and merge
  once approved" becomes register + authorize through the API, and "any news?" becomes
  `GET /api/events`. The skill would read the service URL and its API token from
  `~/.claude/skills/gh-follow/config.json` (gitignored, schema in a future
  `references/config-format.md`) and fall back to the local watcher when it is absent.

## Security

**Panel authentication**: a single user. Recommended: passkey (WebAuthn) login with a TOTP
fallback, sessions in `HttpOnly; Secure; SameSite=Strict` cookies, CSRF tokens on forms, rate
limiting and lockout on login. Optional second layer: restrict the panel's router in Traefik
with an `ipAllowList` (for example the WireGuard range). Traffic through Traefik keeps the real
client IP, but whether WireGuard clients reach the domain from the VPN range has to be checked
before relying on it. Basic auth alone is not enough for a page that authorizes merges.

**API authentication**: per-client bearer tokens (one for the Mac's skill), stored only as a
hash, revocable from the panel, scoped to the API routes (the panel does not accept them). On
the Mac the token lives in the gitignored skill `config.json`, or in the macOS Keychain.

**GitHub token**:

- A token is needed that can read the PRs and merge them in every repo that will be
  registered. Options to decide with the user, none created yet:
  - fine-grained PATs: least privilege (Pull requests read/write, Contents read/write, Checks
    and Commit statuses read, Metadata read), but one token per resource owner (one for
    `BrOrlandi`, one per organization), and organizations can require approving them;
  - a classic PAT with `repo` (plus `notifications`): one token for everything, but far broader,
    and organizations with SSO require authorizing it for SSO.
- Stored as a Dokploy environment secret, read once at start, held in memory, never written to
  the database, never in the image or the repo. Dokploy keeps env values in its own database,
  so access to Dokploy is access to the token; the VPS backups of Dokploy must be treated as
  sensitive. Optional hardening: keep it in the database encrypted with a key that only lives
  in the environment.
- Rotation: new token in Dokploy, redeploy, revoke the old one on GitHub. An expiry date on
  the token is recommended, with an alert from the service when it nears expiry or starts
  failing with `401`.

**Logs**: structured JSON to stdout (read in Dozzle), with a redaction filter on
`authorization`, `cookie`, `set-cookie` and anything token-shaped. They hold PR refs, states,
SHAs and response codes, never comment bodies (third-party text) or request headers.

## Cost

- **VPS**: one Node container (~80–150 MB RAM, near-idle CPU) plus a Postgres container
  (~100 MB). It runs on the existing machine, with no new cost.
- **GitHub API**, 10 registered PRs: notifications 60 requests/hour, mostly free `304`s; PR
  checks about 120/hour while waiting for review (5 min), bursts at 60 s during CI, falling to
  20/hour when idle. Typically under 5% of the GraphQL budget, against 12% for checking every
  PR every minute.
- **Mac**: no polling. Only occasional API calls from the skill.

## MVP scope

In: register/stop/list PRs; adaptive checks with notifications as trigger; events feed;
per-PR authorization pinned to HEAD with the policy above; SHA-pinned merge; audit table;
passkey/TOTP panel; API tokens; health endpoint; Dokploy deploy with Postgres backups.

Out: approving PRs (anyone's), discovering PRs automatically, updating branches or resolving
conflicts, multi-user, webhooks, GitHub App, push notifications (ntfy on the VPS could be
added later), native auto-merge.

## Deployment steps (to review, none executed)

1. Create a private repo for the service in the user's account (name to choose).
2. In Dokploy, create a project with a Postgres database and attach the existing
   `OCI Object Storage (sa-saopaulo)` backup destination to it on a schedule.
3. Create the compose app from the repo through the existing `Dokploy-Orlandi-servers` GitHub
   App. That App sits on the user's own account to deploy his repos; nothing is installed on
   the followed repos. The compose joins the external `dokploy-network`.
4. Add the domain through the API (`domain.create` with `customEntrypoint=web-secure`,
   `letsencrypt`), not the Domains UI, per `infra-orlandi`'s Traefik notes. Port 443 is
   already open, so the OCI Security List stays as is and `docs/ports.md` does not change.
5. Set env vars in Dokploy: database URL, session secret, WebAuthn origin, GitHub token(s).
   The user creates the GitHub token(s); nothing is presumed.
6. First visit: register the passkey, generate the Mac's API token, put it in the skill's
   `config.json`.
7. Add an Uptime Kuma monitor on `/health`, and record the service in `infra-orlandi` (service
   inventory and backup strategy docs).
8. Trial on one personal repo PR before registering organization PRs.
