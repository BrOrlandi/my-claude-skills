# GH-follow service

A single personal service, **GH-follow**, on the Oracle VPS at `https://gh-follow.brorlandi.xyz`,
code in the private repo `BrOrlandi/GH-follow` (its `README.md` and `docs/deploy.md` are the
operating reference). It follows the PRs the `gh-follow` skill registers and merges the user's
own PRs under the policy in `merge-after-approval.md`. The Mac only registers and queries.

As built, it differs from the design below in three places. Passwords are hashed with
**scrypt** (N=2^17, r=8, p=1), which ships with Node, instead of Argon2id, so there are no native
dependencies. Storage is **SQLite** (`node:sqlite`) instead of Postgres. Sessions are
server-side rows (random cookie id, only its hash stored) instead of `@fastify/secure-session`,
on plain `node:http` with no npm dependencies. Merges ship **disabled** (dry run) until enabled
in the panel or with `gh-follow merges enable`.

## Constraints

- Hosted on the Oracle VPS (`infra-orlandi`), not on the HomeServer or the Mac.
- No GitHub App on the followed repos or their organizations, no webhooks, no change to any
  repo or org setting, no dependence on native auto-merge.
- Follows only PRs explicitly registered. No automatic discovery.
- Merges only the user's own PRs, each authorized individually and pinned to its HEAD SHA.
  Approves nothing.
- No model calls in the routine loop.
- No new open ports. No passwords or tokens in chat, scripts, git, images or logs.

## Two separate credentials

| | Panel login | GitHub credential |
| --- | --- | --- |
| Protects | The web panel and the API the skill calls | Reading PRs and merging them on GitHub |
| Who uses it | The user's browser; the skill (API token) | Only the service, through `gh` |
| What it is | A password (Argon2id hash) + session cookie; random API tokens (hashed) | A `gh` OAuth token from `gh auth login` on the VPS |
| Where it lives | Hashes in the database | `hosts.yml` in a dedicated Docker volume |
| Revoked by | Changing the password, revoking the API token in the panel | `gh auth logout` (local) + revoking on github.com |

Logging into the panel never gives access to the GitHub token, and the GitHub token is never
shown in the panel or sent to the Mac.

## Architecture

```text
Mac (skill / browser) --HTTPS 443--> Traefik (web-secure, Let's Encrypt)
                                         |
                              gh-follow container (Node, runs as non-root)
                                |- Fastify: panel + API
                                |- worker loop
                                `- gh CLI  <-- GH_CONFIG_DIR on volume "gh-follow-gh"
                                         |
                              Postgres (Dokploy-managed, backups to OCI Object Storage)
```

- **One container**: TypeScript on Node with Fastify, the same base as the Run app
  (`RunClient`). GitHub calls go through the `gh` CLI inside the container (`gh api graphql`,
  `gh api -X PUT …/merge`, `gh api -i` for `ETag`, `Last-Modified` and rate-limit headers). The
  token never passes through the service's code, environment or logs; `gh` reads it from its
  own config. Each call costs a short-lived process (~0.1–0.3 s CPU), negligible for tens of PRs.
- **Postgres** as store and persistent queue, a Dokploy-managed database included in the
  existing scheduled backups to `OCI Object Storage (sa-saopaulo)`. SQLite plus Litestream to
  the same bucket is the lighter alternative.
- **Domain**: `*.brorlandi.xyz` already resolves to the VPS (`144.22.175.42`; checked: an
  arbitrary subdomain resolves too), so `gh-follow.brorlandi.xyz` needs no DNS change. The
  route and certificate come from creating the domain in Dokploy.

### Data

| Table | Holds |
| --- | --- |
| `followed_prs` | `owner`, `repo`, `number` (unique: deduplication), status, last snapshot (JSON), `next_check_at`, backoff counter |
| `merge_authorizations` | PR, `head_sha`, `merge_method`, checks policy (`all` / `required` / names), `authorized_at`, `authorized_via` (panel or API client), `revoked_at` |
| `events` | Derived events (approved, checks, conflict, merged, authorization lapsed, GitHub credential invalid…) for the panel and the skill |
| `merge_attempts` | Audit: PR, SHA, policy snapshot evaluated, GitHub status code, result |
| `panel_user` | One row: Argon2id password hash, failed-attempt counter, lock-until |
| `api_clients` | Name, SHA-256 of the API token (tokens are 256-bit random, so a fast hash is enough), created/last used, revoked |
| `poll_state` | `Last-Modified` of the notifications endpoint, last rate-limit reading |

### Worker loop

- Due PRs are claimed with `SELECT … WHERE next_check_at <= now() FOR UPDATE SKIP LOCKED`, so
  a restart never loses or duplicates a check.
- Trigger: `gh api -i notifications` every `X-Poll-Interval` (60 s) with `If-Modified-Since`.
  A `304` costs no rate limit (verified). A notification about a registered PR schedules it now.
  This covers comments and reviews, but not CI.
- Adaptive schedule per PR: 60 s while checks run or right after a trigger, 5 min while waiting
  for a review, 30 min after a day without changes, stop when merged or closed. Exponential
  backoff on errors (cap 30 min). Honors `Retry-After` and pauses when `X-RateLimit-Remaining`
  gets low.
- Merge step, only with a live authorization: re-fetch everything in one query, evaluate the
  policy, then `gh api -X PUT repos/{o}/{r}/pulls/{n}/merge -f sha=<authorized HEAD>
  -f merge_method=<method>`. A moved HEAD makes GitHub answer `409`; the authorization lapses
  and an event asks for a new one. Idempotent per (PR, SHA). Every attempt goes to
  `merge_attempts`.
- A `401` from GitHub (token revoked or expired) stops all merges, raises a "GitHub credential
  invalid" event and a banner in the panel, and keeps retrying reads hourly until someone logs
  in again.

### API (for the skill) and panel

- `POST /api/prs` register · `DELETE /api/prs/:id` stop · `GET /api/prs` status ·
  `GET /api/events?since=` news · `POST /api/prs/:id/authorize` (`head_sha`, method, checks
  policy) · `POST /api/prs/:id/revoke`.
- The panel lists the registered PRs by org and repo (review, checks, conflicts,
  authorization), lets the user authorize (showing the exact HEAD SHA) or revoke, manage API
  tokens, and shows whether the GitHub credential works.
- The skill reads the service URL and its API token from
  `~/.claude/skills/gh-follow/config.json` (gitignored; schema to document in
  `references/config-format.md`) and falls back to the local watcher when it is absent.

## Panel login

The Run pattern, hardened. Run uses Fastify with `@fastify/secure-session` (an encrypted
cookie keyed by a 32-byte `SESSION_SECRET`) and one password from the environment. But it
compares that password in plain text and has no login rate limit or CSRF protection. GH-follow
keeps the shape and fixes those gaps:

- **Password**: stored only as an **Argon2id** hash (`argon2` package, at least 19 MiB memory, 2
  iterations, per OWASP), in the `panel_user` row. It is set by running an interactive command
  inside the container on the VPS (`gh-follow set-password`, reads without echo, asks twice).
  Never in an env var, file, git or chat. Changing it re-runs the same command and invalidates
  existing sessions (session version bump).
- **Session**: `@fastify/secure-session` with `SESSION_SECRET` (64 hex chars from
  `openssl rand -hex 32`, a Dokploy env var), cookie `HttpOnly; Secure; SameSite=Strict`, 12 h
  idle timeout and 7-day absolute lifetime, a new session on login.
- **CSRF**: `@fastify/csrf-protection` on every state-changing panel route. The API routes take
  only `Authorization: Bearer` and never the cookie, so they are not exposed to CSRF.
- **Rate limit**: `@fastify/rate-limit` on `POST /api/login` (5 attempts per 15 min per client
  IP, taken from `X-Forwarded-For` as set by Traefik), plus a global lock after 20 failures in
  an hour, released by time or by `set-password`.
- Also `@fastify/helmet` headers and timing-safe comparisons.

Login with GitHub would need an OAuth App created on the user's account (client ID/secret,
callback URL) and an allowlist with only `BrOrlandi`. That works without any org involvement,
but it adds more moving parts than a password for one user, so it stays out of the MVP.

## GitHub credential: `gh auth login` on the VPS, once

- **How**: an interactive helper inside the container, run once over SSH:
  `docker exec -it <container> gh-follow gh-login`. It runs
  `gh auth login --hostname github.com --git-protocol https --web --insecure-storage`. The
  container has no browser, so `gh` prints a one-time code. The user opens
  `https://github.com/login/device` on the Mac, enters the code and approves "GitHub CLI".
  Then the helper runs `gh auth status` and a read-only smoke test: `gh api user`, plus one PR
  read per organization the user plans to use.
- **Where it is kept**: there is no keyring in the container, and `gh` falls back to a plain
  text `hosts.yml` when no credential store is found (stated in `gh auth login --help`).
  `--insecure-storage` makes that choice explicit instead of accidental. `GH_CONFIG_DIR=/data/gh`
  points at the named volume `gh-follow-gh`: directory `0700`, file `0600`, owned by the
  non-root service user. Named volumes survive container restarts and Dokploy redeploys, so
  the login is done once.
- **What it never touches**: the setup script (no token in it), git, the image, env vars, logs
  (the helper prints only `gh auth status`, which masks the token) and the database. Do not add
  `gh-follow-gh` to Dokploy volume backups. If it is lost, log in again.
- **Scopes**: the GitHub CLI app asks for `repo`, `read:org` and `gist` (its minimum). `repo`
  covers reading PRs, merging, and the notifications API. The token acts as the user, so it can
  only do what the user can do in each repo, and branch rules still apply. `gist` is unused but
  part of `gh`'s minimum.
- **Organizations**:
  - The org must allow the GitHub CLI OAuth app if it restricts OAuth app access. On
    2026-11-01 the Mac's `gh` token reads `birdie-ai` (Team plan) and `KasselLabs` (Free)
    without restriction, and a login on the VPS is the same app under the same policy. If an
    org turns restrictions on later, the token loses access to that org until an owner approves
    the app. GH-follow reports it as a read error per repo and merges nothing there.
  - SAML SSO: no `X-GitHub-SSO` challenge on either org today, and enforcing SAML needs GitHub
    Enterprise Cloud (`birdie-ai` is on Team). If an org adopts it, the token has to be
    authorized for SSO on github.com.
  - Org 2FA requirements (`birdie-ai` requires 2FA) concern the user's account, which already
    complies. Nothing for the token.
- **Revoking**:
  - `gh auth logout` (or deleting the volume) removes the token from the VPS only. It does
    **not** revoke it on GitHub (also stated by `gh auth logout --help`).
  - Revoking it on GitHub is done at github.com/settings/applications → GitHub CLI → Revoke.
    That revokes **every** GitHub CLI token of the account, including the Mac's, which then
    needs a new `gh auth login`.
  - If the VPS credential should be revocable on its own, use a classic PAT instead (scopes
    `repo`, `read:org`, `gist`, with an expiry date), entered with
    `gh auth login --with-token` from a hidden prompt in the same helper. It is stored the same
    way, and can be revoked individually at github.com/settings/tokens. Fine-grained PATs are
    a poor fit: one per resource owner, and `gh` itself warns about them with `--with-token`.

## Cost

- **VPS**: one Node container (~80–150 MB RAM, near-idle CPU, short `gh` processes) plus
  Postgres (~100 MB). No new cost.
- **GitHub API**, 10 PRs: notifications 60 requests/hour, mostly free `304`s. PR checks about
  120/hour while waiting for reviews, bursts at 60 s during CI, about 20/hour when idle.
  Typically under 5% of the 5,000/hour GraphQL budget.
- **Mac**: no polling, only occasional API calls from the skill.

## MVP scope

In: register/stop/list PRs; adaptive checks with notifications as the trigger; events feed;
per-PR authorization pinned to HEAD with the policy above; SHA-pinned merge; audit table;
password panel (Argon2id, secure session, CSRF, rate limit); hashed API tokens; `gh-login`
and `set-password` helpers; health endpoint; Dokploy deploy with Postgres backups.

Out: approving PRs (anyone's), discovering PRs automatically, updating branches or resolving
conflicts, GitHub login for the panel, multi-user, webhooks, GitHub App, native auto-merge,
push notifications (ntfy on the VPS could come later).

## Simplest path to production (to review, none executed)

Agent work, once implementation is authorized:

1. Create the private repo `BrOrlandi/gh-follow-service` (name to confirm) with the service,
   its Dockerfile (Node + `gh`, non-root user) and a compose file on the external
   `dokploy-network`, with the named volume `gh-follow-gh`.
2. In Dokploy (API key from `infra-orlandi/dokploy-api-key`): create a project `GH-follow`,
   a Postgres database with a scheduled backup to the existing OCI destination, and the compose
   app from the repo through the existing `Dokploy-Orlandi-servers` GitHub App. That App is on
   the user's own account, for deploying his repos. Nothing gets installed on the followed repos.
3. Set env vars: `DATABASE_URL`, `SESSION_SECRET` (generated on the server, not shown in
   chat), `PUBLIC_URL=https://gh-follow.brorlandi.xyz`, `GH_CONFIG_DIR=/data/gh`.
4. `domain.create` for `gh-follow.brorlandi.xyz` with `customEntrypoint=web-secure` and
   `letsencrypt`. No DNS change (wildcard). No Security List change: port 443 is already open,
   and `docs/ports.md` stays the same.
5. Add an Uptime Kuma monitor on `/health`, and record the service in `infra-orlandi` (service
   inventory, backup strategy).

Human actions that cannot be skipped:

1. **Authorize the implementation** and confirm the repo name.
2. **Set the panel password**: `ssh ubuntu@orlandi1.brorlandi.xyz`, then
   `docker exec -it <container> gh-follow set-password`. Typed only in that terminal.
3. **Log the VPS into GitHub**: `docker exec -it <container> gh-follow gh-login`, then enter
   the device code at github.com/login/device and approve GitHub CLI (or paste a classic PAT
   at the hidden prompt, if you choose the PAT option).
4. **Create the skill's API token** in the panel and put it in
   `~/.claude/skills/gh-follow/config.json` on the Mac (or let the skill save it to the
   Keychain).
5. **First trial**: register one personal-repo PR, authorize it, and watch the merge before
   adding organization PRs.
