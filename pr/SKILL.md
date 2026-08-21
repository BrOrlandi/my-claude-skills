---
name: pr
description: Create or update a GitHub pull request from the current branch, stacking it on an open PR when the branch builds on one. Use when the user asks to create a PR, open a pull request, run /pr, prepare PR content, update an existing PR, stack or chain PRs, or publish branch changes for review.
argument-hint: [mode] [include-how-to-test] [review] [stack|no-stack]
---

# PR

Create a well-structured pull request against the repository's default base branch (commonly `main`, but may be `develop` or another branch), committing local changes first when needed.

## Arguments

If the user provides mode-like wording, treat it as the creation mode:
- draft: create a draft PR
- ready/open: create a normal PR

If the user asks to include testing instructions, include a `How to Test` section. Otherwise include it when there are obvious verification steps or recent verification output.

If the user passes `stack` (or `empilhar`, or names a parent like "on top of #123" / "depends on that PR"), use the stacked flow without asking — see **Stacked PRs**. `no-stack` / `flat` forces a PR against the trunk even when a parent is detected.

If the user passes `review` (or `preview` / wording like "let me review first" / "don't create yet"), enable **review mode**: draft the title and body, show them, and wait for approval or edits before creating the PR. Default (no such wording) is to create the PR directly.

## Workflow

1. Detect the repository's default branch — that is the base, not a hardcoded `main`:
   ```bash
   BASE="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
   ```
   It may be `main`, `develop`, or anything else. Use `$BASE` everywhere below.
2. Inspect the current branch and changes (substitute the detected base for `$BASE`):
   ```bash
   git branch --show-current
   git status --short
   git diff --stat "$BASE...HEAD"
   git diff "$BASE...HEAD"
   git log --oneline "$BASE..HEAD"
   gh pr list --state all --head "$(git branch --show-current)" --json number,title,url,state,isDraft,headRefName
   ```
3. **Read the repository's own PR conventions** before drafting anything — see **Repository Conventions** below. The repo's rules outrank this skill's defaults.
4. If there are uncommitted changes, commit them first using the `commit` skill workflow (conventional commits, logical grouping).
5. **Check whether this branch belongs on top of another open PR.** A branch built on an unmerged branch must target that branch, not the trunk — see **Stacked PRs** below. When a parent is found, the base for this PR becomes the parent PR's head branch.
6. Use the detected default branch as the base, unless the user names a different base or the repo's docs specify one (some repos default to `main` but require feature PRs to target `develop`). Precedence: user's choice → detected stack parent → documented rule → detected default. When a documented rule overrides the detected default, say so when reporting the PR.
7. If a PR already exists for the branch, update its title/body when useful instead of creating a duplicate.
8. Generate a PR title from the branch commits using conventional commit style when possible — unless the repo documents a different title convention. Keep it short and reviewer-facing.
9. Draft the PR body in the repo's format (template if one exists, otherwise the default below). Default: do NOT ask the user to approve the title or body first — create the PR directly, then show the final title and body so the user can review and request edits afterward. In **review mode** (see Arguments): show the drafted title and body and wait for approval or edits before creating.
10. Create or update the PR with `gh`, targeting the detected base branch:
   ```bash
   gh pr create --base "$BASE" --title "<title>" --body-file <body-file>
   gh pr create --base "$BASE" --draft --title "<title>" --body-file <body-file>
   gh pr edit <number> --title "<title>" --body-file <body-file>
   ```
   Stacked PR — the base is the parent's head branch, and the chain is linked afterward:
   ```bash
   gh pr create --base "<parent-branch>" --title "<title>" --body-file <body-file>
   gh stack submit --auto
   ```
11. Request the default reviewers configured for the repository's GitHub org — see **Default Reviewers** below.
12. After creating the PR, use the `jira-link` skill when applicable to offer Jira linking for repositories with configured Jira integration.
13. Open the PR in the browser:
   ```bash
   gh pr view -w
   ```

Always: detect the repository's default base branch, read the repo's PR conventions, list existing PRs for the current branch, check whether the branch stacks on an open PR and target that branch when it does, commit first when there are local changes, compare against that base branch, create or update the PR without pre-approval, show the final PR content afterward for review, honor the requested PR mode, request the org's default reviewers, and offer Jira linking after creation.

## Stacked PRs

A branch built on top of another branch that is still under review must target **that branch**, not the trunk. Against the trunk, the diff carries the parent's commits too: the reviewer reads the same code twice, and every revision of the parent churns this PR. Stacking fixes both — base this PR on the parent's head branch and link the chain so GitHub shows the order.

Default: **when a parent is detected, create the PR as part of the stack.** Flat-against-trunk is the fallback, not the preference.

### Detect the parent

Run this before deciding the base:

```bash
CURRENT="$(git branch --show-current)"
git fetch origin --quiet

# Already tracked in a local stack? Then the stack itself names the parent.
gh stack view --short 2>/dev/null

# Otherwise: any open PR whose head branch is an ancestor of HEAD is a parent layer.
gh pr list --state open --json number,title,headRefName --jq '.[] | [.number, .headRefName, .title] | @tsv' \
| while IFS=$'\t' read -r num head title; do
    [ "$head" = "$CURRENT" ] && continue
    git merge-base --is-ancestor "origin/$head" HEAD 2>/dev/null \
      && echo "stacks on #$num ($head) — $title"
  done
```

Several matches mean several layers of one stack: the **closest** ancestor is the immediate parent — the candidate with the most commits of its own, `git rev-list --count "$BASE..origin/$head"`, highest wins. The others sit below it.

Other signals worth acting on:

- The user says so — "stack", "empilhar", "on top of #123", "depends on that PR".
- `git log --oneline "$BASE..HEAD"` contains commits that already appear in another open PR — the branch was cut from that PR's branch.
- The branch was created off a non-trunk branch that has an open PR (`git reflog show "$CURRENT" | tail -1`, or the branch's configured upstream).

No match means the branch is independent: open it against the trunk and say nothing about stacks.

### Confirm before stacking

Stacking changes what reviewers see, so state the finding and get a yes:

> This branch sits on top of **#123 — `<title>`** (`feat/auth`), still open. I'll base this PR on `feat/auth` so the diff shows only your changes, and link the two as a stack. Say the word if you'd rather target `main` directly.

Proceed on approval, or immediately when the user already asked for a stack (`stack` argument, or naming the parent). If they decline, open against the trunk and note in the body that the diff includes #123's commits.

### Extension check

The stack commands come from a `gh` extension:

```bash
gh extension list | grep -q 'gh-stack' || echo missing
```

If it is missing, offer the install once — never install without approval:

> Stacking needs the `gh stack` extension: `gh extension install github/gh-stack`. Install it?

Declining does not cancel the stack. `gh pr create --base <parent-branch>` still gives the correct base and diff; what is lost is GitHub's stack view and the cascading rebases. Say that in one line and continue.

### Create the stacked PR

Adopt the branches into a local stack bottom-to-top, then create this layer's PR with the title and body drafted the normal way:

```bash
# Adopt the chain, trunk-adjacent branch first. Skip when `gh stack view` already tracks it.
gh stack init --base "$BASE" <bottom-branch> ... <this-branch>

git push -u origin HEAD
gh pr create --base "<parent-branch>" --title "<title>" --body-file <body-file>   # --draft for draft mode

# Link the chain into a stack on GitHub. With every branch already carrying a PR this
# creates no PRs and invents no titles — it pushes, fixes the bases, records the stack.
gh stack submit --auto
```

Rules:

- **Write the title and body yourself.** `gh stack submit --auto` auto-generates titles for branches that have no PR yet, so never let it open the PR: `gh pr create` first, submit afterwards only to link.
- **Never pass `--open` to `gh stack submit`.** It marks *existing* PRs ready for review too, silently un-drafting a draft elsewhere in the stack.
- **Name the parent in the body.** A `Stacked on #123` line at the top of the Context section (in the repo's language) tells a reviewer landing here what precedes it.
- **Report the real base.** The base is the parent's head branch, not the trunk — a reviewer expecting `main` needs to be told.
- **`gh stack sync` force-pushes.** It cascade-rebases and pushes every branch in the stack with `--force-with-lease --atomic`. Use it to bring the stack up to date after the parent moves, and confirm first when someone is already reviewing. `gh stack rebase` is the narrower tool for resolving conflicts.
- **One layer per run.** This skill opens the PR for the current branch. It does not restructure existing branches or split commits without an explicit ask.

### When to suggest splitting

A single branch whose commits fall into clearly separable phases — a refactor followed by the feature that needs it, a migration followed by its consumer — reviews faster as a stack. Say so in one sentence and let the user decide:

> These 14 commits split cleanly into "extract the client" and "add the retry policy". Want two stacked PRs instead of one?

Never rewrite history or move commits to build that stack without approval.

## Default Reviewers

Some organizations want every PR routed to the same team. That mapping is personal and
work-specific, so it lives in a **gitignored** config file rather than in this skill:
`~/.claude/skills/pr/config.json` (see `references/config-format.md`; `config.example.json`
is the committed template).

```json
{
  "orgs": {
    "acme-inc": {
      "team_reviewers": ["acme-inc/developers"],
      "reviewers": []
    }
  }
}
```

Apply it **after** the PR exists, never as a flag on `gh pr create`: an unresolvable
reviewer makes `gh pr create` fail outright, which would lose the PR over a config typo.

```bash
ORG=$(gh repo view --json owner -q '.owner.login')
PR_CONFIG="$HOME/.claude/skills/pr/config.json"

REVIEWERS=$(ORG="$ORG" PR_CONFIG="$PR_CONFIG" python3 -c '
import json, os, sys
try:
    cfg = json.load(open(os.environ["PR_CONFIG"]))
except (FileNotFoundError, ValueError):
    sys.exit(0)
org = cfg.get("orgs", {}).get(os.environ["ORG"], {})
print(",".join(org.get("team_reviewers", []) + org.get("reviewers", [])))
' 2>/dev/null)

[ -n "$REVIEWERS" ] && gh pr edit <number> --add-reviewer "$REVIEWERS"
```

Rules:

- **Org not in the config, or no config file** — skip silently. Personal repos and
  unconfigured orgs get no reviewers; this is not an error worth reporting.
- **Teams use `org/team-slug`** (e.g. `acme-inc/developers`). A bare slug does not resolve.
- **Never request the PR author.** GitHub rejects it and the whole call fails. Drop the
  author's login from `reviewers` before calling `gh`.
- **Do not re-request reviewers already on the PR** — it re-notifies them. Check first;
  teams come back as `slug` in the same `org/team` form the config stores, users as `login`,
  so the output compares directly against the configured values:
  ```bash
  gh pr view <number> --json reviewRequests -q '.reviewRequests[] | .slug // .login'
  ```
- **Draft PRs still get the request.** GitHub records it and notifies when the PR is marked
  ready, so drafts are configured the same way.
- **A reviewer failure never fails the PR.** If `gh pr edit --add-reviewer` errors (team
  renamed, insufficient permission, org restricts review requests), report the error and
  continue with the rest of the workflow.
- **The user's explicit instruction wins.** If they name reviewers, or ask for none, honor
  that instead of the config.

### First-Time Setup

If the repo's org has no entry in the config, ask once: "This repo belongs to **{org}**.
Should every PR here request a default reviewer team? If so, which one (e.g.
`{org}/developers`)?" Persist the answer under `orgs.{org}`; if they decline, record
nothing and do not ask again in this conversation.

## Repository Conventions

Every repo documents how it wants PRs written. Read those docs before drafting — a PR that ignores the house style is rework for the author and noise for the reviewer.

Find them:

```bash
ls CLAUDE.md AGENTS.md CONTRIBUTING.md README.md 2>/dev/null
ls .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md \
   .github/PULL_REQUEST_TEMPLATE/*.md docs/PULL_REQUEST_TEMPLATE.md 2>/dev/null

# conventions local to the directories this PR touches
git diff --name-only "$BASE...HEAD" | xargs -r -n1 dirname | sort -u \
  | while read -r d; do ls "$d"/CLAUDE.md "$d"/AGENTS.md "$d"/README.md 2>/dev/null; done
```

Read what exists. Skip re-reading any `CLAUDE.md` already loaded into your context.

What to take from each:

- **A PR template is binding.** If one exists, use its headings, order and checklists verbatim instead of the default format below. Fill every section; keep checklist items and tick only the ones that are actually true.
- **`CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md`** — title format (conventional commits, ticket prefix, or something else), required sections, base-branch rules (e.g. features target `develop`), whether PRs open as draft, screenshot or changelog requirements, labels and reviewers to set.
- **READMEs of the touched directories** — the vocabulary that module uses. Name things the way the module names them, so reviewers recognize what changed.
- **Language.** If the repo's docs and recent merged PRs are written in a language other than English, write the PR in that language. Check with `gh pr list --state merged --limit 5 --json title,body`.

Precedence when these disagree: **explicit user instruction → repo template → repo docs (`CLAUDE.md`, `CONTRIBUTING.md`) → this skill's default format.**

Do not fake compliance. If a required section can't be filled from the actual diff, say what is missing and why instead of inventing content to fill the heading.

## PR Body Format

Use this structure **only when the repo has no PR template or documented format**:

```md
## Context
- What changed and why
- Related issues, tickets, or requirements
- Breaking changes or important reviewer notes, if any

## How to Test
- Specific verification steps
- Setup requirements or test data
- Expected behavior
```

Omit empty bullets. If there are no meaningful manual test steps, say what automated checks or inspection were performed.

## Review Quality

Write for reviewers:
- Explain behavior and motivation, not just file names.
- Link tickets or discussions when visible from branch names, commit messages, or user input.
- Mention risks, migrations, or follow-up work explicitly.
- Keep generated content specific to the actual diff between the base branch and the current branch.

## Completion

Report the PR URL, whether it was created or updated, whether it is draft or ready for review, and whether Jira linking was completed, skipped, or not applicable. When the PR is stacked, also report the base branch, the parent PR, and this PR's position in the stack (e.g. "2 of 3").
