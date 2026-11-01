# Merge after approval

What "merge it once approved" means in `gh-follow`, today (the local watcher) and in the planned
central service (`central-service.md`). The automation is personal and repository-agnostic:
it never depends on GitHub's native auto-merge and never changes anything in a repository.

## Ground rules

- Only the user's own PRs, and only those the user authorized one by one.
- No GitHub App, no webhooks, no change to repo or org settings (auto-merge setting, branch
  protection, rulesets). The repo's existing rules still apply: GitHub refuses a merge they do
  not allow, and the automation never tries to bypass them (no admin override).
- No approving PRs, neither the user's nor anyone else's. Approving third-party PRs would be a
  separate scope with per-PR criteria and explicit authorization; it is not planned.
- Routine checks never run the model: plain API calls compared against saved snapshots.

## Merge policy (per PR, explicit)

A PR is merged only when every condition holds at the moment of the merge:

1. **Authorization**: the user authorized this PR, and the authorization records the HEAD
   commit SHA it was given for. If the HEAD changes, the authorization lapses and the PR waits
   for a new one; nothing pushed after the authorization is merged without the user seeing it.
2. **Valid approval**: at least one review in state `APPROVED` whose commit is the current HEAD,
   from someone other than the author, not a bot, with write access to the repo (author
   association `OWNER`, `MEMBER` or `COLLABORATOR`). No reviewer's latest review is
   `CHANGES_REQUESTED`. If the repo requires reviews, `reviewDecision` must be `APPROVED` too.
3. **Checks**, per the policy chosen when authorizing:
   - `all` (default): every check run and commit status on HEAD finished as `SUCCESS`,
     `NEUTRAL` or `SKIPPED`; none pending, none failed.
   - `required`: only what the branch rules require (GitHub enforces it at merge time).
   - an explicit list of check names that must be green.
4. **No conflicts and mergeable**: `mergeable` is `MERGEABLE` and `mergeStateStatus` is
   `CLEAN` (or `HAS_HOOKS`). `BEHIND`, `BLOCKED`, `DIRTY`, `UNSTABLE` or `UNKNOWN` mean wait. The
   automation does not update the branch on its own.
5. **Not a draft, still open.**

Right before merging, everything above is fetched again in one query (no cached decision), and
the merge call pins the SHA: `PUT /repos/{owner}/{repo}/pulls/{n}/merge` with
`sha=<authorized HEAD>` and the chosen `merge_method`. GitHub answers `409` if the head moved
in between, so a commit pushed in the last second cannot slip in.

## Today: the local watcher (`gh-follow.sh --auto-merge`)

Runs only while a Claude session and the Mac are up. It merges on `READY` (approved, checks
green, mergeable) with `gh pr merge`. Gaps compared with the policy above, to close when the
central service exists: it does not pin the authorized HEAD, it accepts the repo's
`reviewDecision` (or any latest approval when the repo requires none) without checking the
approval's commit or the reviewer's access, and its checks policy is fixed to "all".

## Detection fields (read-only, one GraphQL query per PR)

```graphql
query($o: String!, $r: String!, $n: Int!) {
  repository(owner: $o, name: $r) {
    viewerPermission squashMergeAllowed mergeCommitAllowed rebaseMergeAllowed
    pullRequest(number: $n) {
      author { login } state isDraft headRefOid baseRefName
      reviewDecision mergeable mergeStateStatus
      latestReviews(first: 50) { nodes { state author { login __typename } authorAssociation commit { oid } } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 100) {
        nodes { __typename ... on CheckRun { name status conclusion } ... on StatusContext { context state } }
      } } } } }
    }
  }
}
```

`viewerPermission` must be `WRITE`, `MAINTAIN` or `ADMIN` for the merge to be possible at all.
The `*MergeAllowed` fields say which merge methods the repo accepts.

## Native auto-merge: not used

Kept here because it explains why the automation does its own merging. Native auto-merge is a
per-repo setting ("Allow auto-merge"), off in all six repos probed on 2026-11-01
(`birdie-ai/application-frontend`, `application-backend`, `iac-core`,
`BrOrlandi/banco-bruno`, `BrOrlandi/RaceFriends`, `paulogdm/world-cup-2026-bracket`). Turning
it on is an admin change, and it waits only for what the branch rules require, so on repos
without required reviews (every private repo on a Free plan) it would merge with no approval.

## Polling cost (measured 2026-11-01)

One check of one PR: one GraphQL request, about 1 point of the 5,000-point/hour budget,
~1.1 s, 7–14 KB, 0.1–0.3 s of CPU in a short-lived `gh` (~45 MB peak).

| PRs checked every 60 s | Requests/hour | GraphQL budget | Data/hour |
| --- | --- | --- | --- |
| 1 | 60 | 1.2% | ~0.6 MB |
| 10 | 600 | 12% | ~6 MB |
| 100 | ~3,300 (a sequential round takes ~110 s) | ~66% | ~40 MB |

The budget is shared with everything else using the same token. `--mine` reads at most 100
open PRs once at start (133 were open on 2026-11-01), so naming PRs explicitly is preferred.

`GET /notifications` sends `X-Poll-Interval: 60`, and a conditional request
(`If-Modified-Since`/`ETag`) answered `304` costs no rate limit (checked). It flags new
comments and reviews on PRs the user authored or was asked to review, in any repo. It does not
cover CI: check runs and statuses do not notify the PR author, so CI and mergeability still
need per-PR checks.
