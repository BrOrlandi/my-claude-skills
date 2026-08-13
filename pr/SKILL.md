---
name: pr
description: Create or update a GitHub pull request from the current branch. Use when the user asks to create a PR, open a pull request, run /pr, prepare PR content, update an existing PR, or publish branch changes for review.
argument-hint: [mode] [include-how-to-test] [review]
---

# PR

Create a well-structured pull request against the repository's default base branch (commonly `main`, but may be `develop` or another branch), committing local changes first when needed.

## Arguments

If the user provides mode-like wording, treat it as the creation mode:
- draft: create a draft PR
- ready/open: create a normal PR

If the user asks to include testing instructions, include a `How to Test` section. Otherwise include it when there are obvious verification steps or recent verification output.

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
5. Use the detected default branch as the base, unless the user names a different base or the repo's docs specify one (some repos default to `main` but require feature PRs to target `develop`). Precedence: user's choice → documented rule → detected default. When a documented rule overrides the detected default, say so when reporting the PR.
6. If a PR already exists for the branch, update its title/body when useful instead of creating a duplicate.
7. Generate a PR title from the branch commits using conventional commit style when possible — unless the repo documents a different title convention. Keep it short and reviewer-facing.
8. Draft the PR body in the repo's format (template if one exists, otherwise the default below). Default: do NOT ask the user to approve the title or body first — create the PR directly, then show the final title and body so the user can review and request edits afterward. In **review mode** (see Arguments): show the drafted title and body and wait for approval or edits before creating.
9. Create or update the PR with `gh`, targeting the detected base branch:
   ```bash
   gh pr create --base "$BASE" --title "<title>" --body-file <body-file>
   gh pr create --base "$BASE" --draft --title "<title>" --body-file <body-file>
   gh pr edit <number> --title "<title>" --body-file <body-file>
   ```
10. Request the default reviewers configured for the repository's GitHub org — see **Default Reviewers** below.
11. After creating the PR, use the `jira-link` skill when applicable to offer Jira linking for repositories with configured Jira integration.
12. Open the PR in the browser:
   ```bash
   gh pr view -w
   ```

Always: detect the repository's default base branch, read the repo's PR conventions, list existing PRs for the current branch, commit first when there are local changes, compare against that base branch, create or update the PR without pre-approval, show the final PR content afterward for review, honor the requested PR mode, request the org's default reviewers, and offer Jira linking after creation.

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

Report the PR URL, whether it was created or updated, whether it is draft or ready for review, and whether Jira linking was completed, skipped, or not applicable.
