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

If the user asks to include testing instructions, include a `How to Test` section (or fill the template's testing section, when the repo has a template). Otherwise include it when there are obvious verification steps or recent verification output.

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
3. **Read the repository's own PR conventions** before drafting anything — see **Repository Conventions** below. Locate the PR template and any PR command or convention doc, and read them from the PR's base branch. The repo's rules outrank this skill's defaults.
4. **Audit environment variable changes** — new, removed, or consumed differently. Document new ones in the project and commit that before the PR exists. See **Environment Variables** below.
5. If there are uncommitted changes, commit them first using the `commit` skill workflow (conventional commits, logical grouping).
6. **Check whether this branch belongs on top of another open PR.** A branch built on an unmerged branch must target that branch, not the trunk — see **Stacked PRs** below. When a parent is found, the base for this PR becomes the parent PR's head branch.
7. Use the detected default branch as the base, unless the user names a different base or the repo's docs specify one (some repos default to `main` but require feature PRs to target `develop`). Precedence: user's choice → detected stack parent → documented rule → detected default. When a documented rule overrides the detected default, say so when reporting the PR.
8. If a PR already exists for the branch, update its title/body when useful instead of creating a duplicate.
9. Generate a PR title from the branch commits using conventional commit style when possible — unless the repo documents a different title convention. Keep it short and reviewer-facing.
10. Draft the PR body. **If the repo has a PR template, the body is that template filled in** (see **Following a PR Template**); the default format below is only for repos without one. Before creating or editing, run the template self-check from that section and fix what it reports. Default: do NOT ask the user to approve the title or body first — create the PR directly, then show the final title and body so the user can review and request edits afterward. In **review mode** (see Arguments): show the drafted title and body and wait for approval or edits before creating.
11. Create or update the PR with `gh`, targeting the detected base branch:
   ```bash
   gh pr create --base "$BASE" --title "<title>" --body-file <body-file>
   gh pr create --base "$BASE" --draft --title "<title>" --body-file <body-file>
   gh pr edit <number> --title "<title>" --body-file <body-file>
   ```
   For a stacked PR the base is the parent's head branch and the chain is linked afterward — the
   commands live in **Stacked PRs** below.
12. Request the default reviewers configured for the repository's GitHub org — see **Default Reviewers** below.
13. After creating the PR, use the `jira-link` skill when applicable to offer Jira linking for repositories with configured Jira integration.
14. If the repository has `.claude/release.json` and the branch's commits touch an app with changelog targets, offer the changelog update in one sentence using the `release` skill, and let the user decide. Stay quiet when there is no manifest — a repo without a release convention is not asking for one at PR time.
15. Open the PR in the browser:
   ```bash
   gh pr view -w
   ```

## Stacked PRs

A branch built on top of another branch that is still under review must target **that branch**, not
the trunk. Against the trunk the diff carries the parent's commits too: the reviewer reads the same
code twice, and every revision of the parent churns this PR. Default: **when a parent is detected,
create the PR as part of the stack.** Flat-against-trunk is the fallback, not the preference.

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

### Then read the reference

Once a parent is found — or the user asked for a stack — read `references/stacked-prs.md` before
creating anything. It carries the confirmation wording, the `gh stack` extension check, the
create-and-link commands, the rules that keep `gh stack submit` from inventing titles or
un-drafting someone else's PR, and when to suggest splitting one branch into a stack.

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

## Environment Variables

Every PR states its environment variable changes. A variable that appears only in code reaches
production as a crash or a silent fallback, and whoever deploys has no way to know it exists. Run
this audit on every PR, including updates to an existing one.

### Find the changes

Scan the full branch diff plus anything still uncommitted (untracked files included), and look at
both added and removed lines:

```bash
ENV_RE='process\.env|import\.meta\.env|Deno\.env|Bun\.env|os\.environ|os\.getenv|getenv\(|ENV\[|ENV\.fetch|System\.getenv|env::var|env\(|\benv\.[A-Z]|secrets\.[A-Z]|vars\.[A-Z]|\$\{?[A-Z][A-Z0-9_]{2,}|^[+-]?[[:space:]]*(export[[:space:]]+)?[A-Z][A-Z0-9_]{2,}=|^[+-]?[[:space:]]*(ENV|ARG)[[:space:]]|^[+-]?[[:space:]]*-?[[:space:]]*[A-Z][A-Z0-9_]{2,}:'
{ git diff "$BASE...HEAD"; git diff HEAD; } | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' | grep -E "$ENV_RE"
git ls-files -z --others --exclude-standard | xargs -0 -r grep -HnE "$ENV_RE"   # untracked files
```

The grep is a starting point, not the answer. Also read the diff for:

- **Env files and templates** — `.env.example`, `.env.sample`, `.env.template`, `.env.*`.
- **Config schemas** — zod/envalid/t3-env schemas, pydantic `BaseSettings`, `config/*.ts`,
  Rails/Laravel config files, `settings.py`. A field added there is a new variable even when no
  `process.env` line changed.
- **Deploy and CI files** — `Dockerfile` `ENV`/`ARG`, `docker-compose*.yml`, Helm values, k8s
  manifests, Terraform, `.github/workflows/*` `env:` and `secrets.*`, Vercel/Netlify/Fly config.
- **Framework prefixes** — `NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, `EXPO_PUBLIC_`: these are inlined
  at build time, so adding or renaming one means a rebuild, not just a restart.

Classify every variable you find:

- **Added** — read by the code for the first time on this branch.
- **Removed** — no longer read anywhere. Confirm with a repo-wide search (`git grep -n VAR_NAME`)
  before calling it removed; a line deleted in one file may still be read in another.
- **Changed** — still read, but consumed differently: renamed, default added/changed/removed,
  optional became required (or the reverse), new format or type (string to JSON, seconds to ms,
  comma-separated list, URL now needs a scheme), moved between build time and runtime, moved to a
  different service or container, or split/merged with another variable. When in doubt, it is
  Changed: any touched line that alters how the variable is read, validated, defaulted or set
  (including a value changed only in an env template, CI or deploy file) goes in the report.

Ignore variables only referenced in tests or test fixtures, and ones the platform provides
(`NODE_ENV`, `PATH`, `HOME`, `CI`, `GITHUB_*`), unless the branch changes how they are used.

### Document them in the project

Before the PR is created, the project's own docs must match the code:

1. Find where the repo documents its variables: `.env.example` (or sibling template), a README
   "Environment"/"Configuration" section, `docs/`, `CLAUDE.md`/`AGENTS.md`, a config schema with
   descriptions, deploy manifests. Follow that existing pattern; do not invent a new location
   when one exists.
2. **Added** — add each one with a short description, whether it is required, its default, and an
   example value. Never write a real secret; use a placeholder like `your-api-key`.
3. **Removed** — delete it from the same docs and templates.
4. **Changed** — update the docs to the new name, default, or format.
5. If the repo documents variables nowhere, add the new ones to `.env.example` (create it) and say
   so in the PR.
6. Commit these doc changes with the `commit` skill (e.g. `docs(env): document STRIPE_WEBHOOK_SECRET`)
   so they ship in the same PR.

### Report them in the PR

Add an **Environment Variables** section to the PR body whenever there is at least one Added,
Changed or Removed variable, even when the repo uses a template: fill the template's own
env/config section if it has one, otherwise append it **after** the template's last section. List
each variable once:

```md
## Environment Variables
**Added**
- `STRIPE_WEBHOOK_SECRET` (required, server) — signs incoming Stripe webhooks. Documented in `.env.example`.

**Removed**
- `LEGACY_API_URL` — no longer read; safe to delete from every environment after deploy.

**Changed**
- `CACHE_TTL` — now in milliseconds (was seconds). Update `3600` to `3600000`.
- `API_URL` renamed to `BACKEND_URL`; the old name is no longer read.

**Deploy action**: set `STRIPE_WEBHOOK_SECRET` in staging and production before merging.
```

Omit empty groups. The `Deploy action` line says what someone has to do in each environment
(set, rename, delete, rebuild) and in which order relative to the merge. A removed variable is
deleted **after** the deploy, a new required one is set **before**.

When nothing changed, add no section and no "no env changes" line. Mention it in the completion
report instead. When updating an existing PR, rebuild the section from the whole branch: drop
entries the branch no longer makes, add ones from the new commits.

## Repository Conventions

Every repo documents how it wants PRs written. Read those docs before drafting — a PR that ignores the house style is rework for the author and noise for the reviewer.

Find them. Read the PR template and PR docs from the **PR's base branch**, not the working tree:
the base is what reviewers hold the PR to, and it may not be the repo's default branch (some repos
open PRs against `staging` or `develop`). If the docs say PRs target a different branch than the
one you checked, re-read from that branch.

```bash
git fetch origin "$BASE" --quiet
ls CLAUDE.md AGENTS.md CONTRIBUTING.md README.md 2>/dev/null

# PR templates, plus PR commands and convention docs written for agents or humans
git ls-tree -r --name-only "origin/$BASE" | grep -iE \
  '^(\.github/|docs/)?pull_request_template(/[^/]+)?\.md$|(^|/)[^/]*(pr|pull[-_]?request)[-_](conventions?|guidelines?|create)[^/]*\.(md|mdc)$'

git show "origin/$BASE:<path>"   # read each match from the base branch

# conventions local to the directories this PR touches
git diff --name-only "$BASE...HEAD" | xargs -r -n1 dirname | sort -u \
  | while read -r d; do ls "$d"/CLAUDE.md "$d"/AGENTS.md "$d"/README.md 2>/dev/null; done
```

Read what exists. Skip re-reading any `CLAUDE.md` already loaded into your context. A PR command
or convention doc (e.g. `.ai/commands/**/pr-create*.md`, `.ai/context/pr-conventions.mdc`) is
the team's own instructions for writing PRs: follow it like a template, including how it says to
fill each section. When `PULL_REQUEST_TEMPLATE/` holds several templates, pick the one those docs
name for this kind of change, or the one matching it.

What to take from each:

- **A PR template is binding, and is followed exactly.** See **Following a PR Template** below.
  When a template exists, this skill's default body format does not apply at all.
- **`CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md`** — title format (conventional commits, ticket prefix, or something else), required sections, base-branch rules (e.g. features target `develop`), whether PRs open as draft, screenshot or changelog requirements, labels and reviewers to set.
- **READMEs of the touched directories** — the vocabulary that module uses. Name things the way the module names them, so reviewers recognize what changed.
- **Language.** If the repo's docs and recent merged PRs are written in a language other than English, write the PR in that language. Check with `gh pr list --state merged --limit 5 --json title,body`.

Precedence when these disagree: **explicit user instruction → repo template and PR command/convention docs → repo docs (`CLAUDE.md`, `CONTRIBUTING.md`) → this skill's default format.**

Do not fake compliance. If a required section can't be filled from the actual diff, say what is missing and why instead of inventing content to fill the heading.

### Following a PR Template

Teams put items in their template on purpose (a security team may require its checklist on every
PR), and a body in any other shape gets sent back. Start the body from the template file itself,
not from memory, and fill it in place:

- **Every heading, in order**, with its exact text and level. Do not rename, merge, reorder or
  add headings between them.
- **Every placeholder replaced** — `REPLACE_ME`, `<describe…>`, `TODO`, empty `Jira:`/`Figma:`
  slots. A slot the diff cannot fill gets a short honest note (`Figma: n/a`), never the
  placeholder.
- **Every checklist item kept.** Boxes the template ships pre-checked (`- [x]`) stay checked
  exactly as they are. Tick an unchecked box only when it is true for this PR; never delete one.
- **Sections are removed only when the template says so** (e.g. "delete this section if there is
  no UX change"). Otherwise an inapplicable section stays with a one-line reason.
- **Instructions in the template** (HTML comments, italic hints) are followed. Leaving the
  comments in is fine; they do not render.
- **The skill's own additions go after the template's last section**: Environment Variables,
  ticket link, stack note, How to Test. When the template already has a slot for one of them (a
  `Jira` line, a testing or config section), fill that slot instead of adding a section.
- **Updating a PR** whose body does not follow the template (e.g. an earlier body in this skill's
  default format): rebuild it on the template, carrying over what still applies.

**Self-check before `gh pr create` / `gh pr edit`.** With the template's path in `$TEMPLATE` and
the drafted body in `$BODY_FILE`:

```bash
TPL="$(git show "origin/$BASE:$TEMPLATE")"
heads()   { grep -E '^#{1,6} ' | sed 's/[[:space:]]*$//'; }
checked() { grep -E '^[[:space:]]*[-*] \[[xX]\]' | sed 's/[[:space:]]*$//'; }
diff <(printf '%s\n' "$TPL" | heads) <(heads < "$BODY_FILE")                  # headings
grep -Fxv -f <(checked < "$BODY_FILE") <(printf '%s\n' "$TPL" | checked)      # pre-checked boxes lost
grep -n 'REPLACE_ME' "$BODY_FILE"                                             # placeholders left
```

In the heading diff, a `<` line is a template heading that is missing or out of order: fix the
body unless the template itself allows removing that section, or the heading is itself an
instruction to the author (e.g. `#### Remove this section if…`). `>` lines are fine only at the end
(the skill's additions). The other two commands must print nothing. Fix and re-run until clean.

## PR Body Format

Use this structure **only when the repo has no PR template or documented format**. If the repo has a template, never use these headings in place of the template's:

```md
## Context
- What changed and why
- Related issues, tickets, or requirements
- Breaking changes or important reviewer notes, if any

## Environment Variables
(only when the branch adds, removes or changes one, see Environment Variables above)

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

Report the PR URL, whether it was created or updated, whether it is draft or ready for review, which PR template the body follows (path and branch it was read from) or that the repo has none, the environment variable changes (or that there were none) and any deploy action they need, and whether Jira linking was completed, skipped, or not applicable. When the PR is stacked, also report the base branch, the parent PR, and this PR's position in the stack (e.g. "2 of 3").
