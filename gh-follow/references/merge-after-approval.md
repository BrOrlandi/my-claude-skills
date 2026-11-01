# Merge after approval

How `gh-follow` decides between GitHub's native auto-merge and its own local auto-merge, what each
one depends on, and what polling costs. Everything here is read-only except the final
`gh pr merge`, which needs the user's go-ahead.

## Detection (read-only, one query per PR)

```bash
gh api graphql -F n=<N> -f o=<owner> -f r=<repo> -f query='
query($o: String!, $r: String!, $n: Int!) {
  repository(owner: $o, name: $r) {
    autoMergeAllowed squashMergeAllowed mergeCommitAllowed rebaseMergeAllowed viewerPermission
    pullRequest(number: $n) {
      author { login } isDraft state baseRefName reviewDecision mergeStateStatus
      viewerCanEnableAutoMerge
      autoMergeRequest { enabledAt mergeMethod enabledBy { login } }
    }
  }
}'
```

| Field | Meaning |
| --- | --- |
| `autoMergeAllowed` | The repo setting "Allow auto-merge". Off by default; only a repo admin turns it on, and org policy may forbid it. |
| `viewerCanEnableAutoMerge` | GitHub's own answer for this user and PR (write access, setting on, PR state). |
| `reviewDecision` | `REVIEW_REQUIRED` / `CHANGES_REQUESTED` / `APPROVED` when the base branch rules require reviews; `null` when nothing requires a review. Readable with plain read access, so it is the signal to use, rather than the branch protection or rulesets endpoints. |
| `mergeStateStatus` | `BLOCKED` while requirements are missing, `DIRTY` on conflicts, `CLEAN` when mergeable now. |
| `autoMergeRequest` | Non-null when auto-merge is already on (who enabled it, which method). |
| `*MergeAllowed` | Merge methods the repo accepts; pick one of these for `--<method>`. |

## Decision

| Situation | Use |
| --- | --- |
| `autoMergeAllowed` and `viewerCanEnableAutoMerge`, not draft, `reviewDecision` is `REVIEW_REQUIRED` or `CHANGES_REQUESTED` | Native: `gh pr merge <N> --repo <owner/repo> --auto --<method>` after the user says yes |
| `reviewDecision` is `null` | Local `--auto-merge`. Native would merge as soon as the PR is mergeable, with no approval at all |
| `autoMergeAllowed` is `false` | Local `--auto-merge`. Do not enable the setting without the user's explicit authorization for that repo |
| `reviewDecision` is `APPROVED` and `mergeStateStatus` is `CLEAN` | Nothing to wait for: ask whether to merge now |
| Draft PR | Neither: auto-merge waits for "ready for review", say so |

## What native auto-merge does and does not guarantee

- It is a **per-repo setting**, plus whatever the branch protection or rulesets of the base
  branch require. GitHub merges when *those* requirements are met: required approvals,
  required status checks, no conflicts. It does not add requirements of its own.
- **It does not guarantee a human approval.** If the base branch does not require a review,
  nothing waits for one. That is why the flow only uses it when `reviewDecision` is non-null.
- Branch protection and rulesets on **private repos need a paid plan** (GitHub Pro, Team or
  Enterprise). On a Free personal account the rulesets API answers `403 Upgrade to GitHub Pro`,
  private repos have no required reviews, and so native auto-merge has nothing to wait for.
- Required checks are only the ones the rules list. A workflow that is not a required check can
  fail and the PR still merges.
- Whether stale approvals are dismissed after a new push depends on the branch rule.
- On a PR that is already mergeable (`CLEAN`), GitHub does not queue auto-merge, and `gh` may
  merge right away. Check `mergeStateStatus` first. Not verified by merging a real PR.
- GitHub turns auto-merge off when someone without write access pushes to the head branch, and
  the merge is recorded as done by the user who enabled it.
- If the base branch uses a merge queue, `gh pr merge` adds the PR to the queue instead.

Observed on 2026-11-01 for the PRs probed (`birdie-ai/application-frontend`,
`application-backend`, `iac-core`, `BrOrlandi/banco-bruno`, `BrOrlandi/RaceFriends`,
`paulogdm/world-cup-2026-bracket`): `autoMergeAllowed` was `false` in all six. The three
birdie-ai repos require 1 approval (two also require named checks), so they would qualify once
the setting is on. The two personal private repos have no rules (`reviewDecision: null`), so
native auto-merge would not wait for an approval there even if enabled.

## Polling cost (measured 2026-11-01)

One check of one PR is one `gh pr view` → one GraphQL request, about **1 point** of the
5,000-point/hour GraphQL budget, about 1.1 s of latency, 7–14 KB of JSON, about 0.1–0.3 s of
CPU and a short-lived `gh` process peaking near 45 MB. The script checks PRs one after
another and ticks every 2 s with a `date` call in between.

| PRs at 60 s | Requests/hour | Share of the GraphQL budget | Data/hour |
| --- | --- | --- | --- |
| 1 | 60 | 1.2% | ~0.6 MB |
| 10 | 600 | 12% | ~6 MB |
| 100 | ~3,300 (a round takes ~110 s, longer than the interval) | ~66% | ~40 MB |

The budget is shared with every other use of the same token (other sessions, `gh` commands,
CI tooling run locally), so 100 PRs at 60 s is not viable. With webhooks on owned repos, a PR
costs 12 checks/hour (safety interval of 300 s) plus one per delivery.

### Notifications API

`GET /notifications` is per user and covers PRs where the user is the author, was asked to
review, was mentioned or subscribed, in any repo, without installing anything. GitHub sends
`X-Poll-Interval: 60` and `Last-Modified`/`ETag`. A conditional request that gets
`304 Not Modified` does not count against the rate limit (checked: 4,931 remaining before and
after). It tells *that* a PR changed, not *what*, so a PR fetch still follows.

It does **not** cover CI: check runs and statuses do not create notifications for the PR
author (at most a failed Actions run the user triggered). So it can replace the per-PR "is
there news?" poll for comments and reviews, but CI and merge readiness still need a per-PR
check on a slower schedule.

## Fallback considered: a central service on the HomeServer (not built)

For when merges must happen while the Mac sleeps and native auto-merge is not available. Only
a design; nothing is deployed.

| | Daemon on the Mac (today) | Service on the HomeServer |
| --- | --- | --- |
| Mac asleep / offline | Stops; catches up on wake (state persists) | Keeps running |
| Credentials | Existing `gh` login, nothing new stored | A token stored on the server: fine-grained PAT limited to the repos and to Pull requests read/write + Contents read/write (merge), Checks/Commit statuses read. Orgs may require approving fine-grained tokens; a classic `repo` token works everywhere but is far broader |
| GitHub calls | One poll per followed PR per interval, per running session (two sessions on one PR poll twice) | Deduplicated: one poll per registered PR, whatever asks for it |
| Maintenance | None beyond the skill | A container, its token rotation, logs, backups of a small SQLite file |
| Interface | The Claude session | A small web page plus the skill registering PRs through an API |

Shape of the service, kept to what the user asked for:

- Follows only PRs **explicitly registered** (by the skill or the web page), keyed by
  `owner/repo#N`, so the same PR is never polled twice.
- One notifications poll per `X-Poll-Interval` with `If-Modified-Since`; a PR named in a new
  notification is checked right away.
- Per-PR checks with an adaptive interval: about 60 s while CI is running or right after a
  notification, 5 min while waiting for a review, 30 min when nothing moved for a day, and
  exponential backoff on errors or `Retry-After`. Stops when the PR is merged or closed.
- Auto-merge per PR is an explicit toggle. It enables native auto-merge when the detection
  above says it is usable; otherwise it merges itself after approval + green checks + no
  conflicts, using the same rules as `gh-follow.sh`.
- No GitHub App, no webhooks on organization repos, no model calls in the polling loop.
- Approving other people's PRs is out of scope. It would need per-PR criteria and the user's
  explicit authorization for each PR, and is not automated.

MVP if it is built: one container with the poller, a SQLite table of registered PRs
(`ref`, `auto_merge`, `merge_method`, last snapshot, next check), a two-route API (register,
toggle) and one page listing the PRs by org and repo. The `gh-follow` skill would keep working
on its own and could later register PRs there instead of watching them itself.
