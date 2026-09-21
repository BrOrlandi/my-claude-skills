---
name: commit
description: Create structured git commits from the current repository changes. Use when the user asks to commit, create a commit, prepare commits, run the old /commit workflow, or turn local staged/unstaged changes into one or more conventional commits.
---

# Commit

Create coherent, reviewable commits after inspecting the current branch, local changes, and recent history.

## Workflow

1. Inspect the repository state:
   ```bash
   git branch --show-current
   git status --short
   git diff --stat HEAD
   git diff HEAD
   git log --oneline -10
   ```
2. Check whether the current branch already has a merged PR:
   ```bash
   gh pr list --state merged --head "$(git branch --show-current)" --json number,title,url,mergedAt
   ```
   If a merged PR exists for this branch, ask the user whether to proceed or switch/create another branch.
3. Resolve the default-branch commit policy (see [Default-Branch Commit Policy](#default-branch-commit-policy))
   before touching the default branch. With no recorded policy, do not commit automatically on the default
   branch (`main`, `master`, or whatever the repo uses) — ask the user for explicit confirmation first.
4. Compare the branch name with the changed files and diff. If the changes clearly do not match the branch purpose, stop and explain the mismatch.
5. Analyze the diff and group changes into logical, atomic commits. Prefer one commit when the change is a single coherent unit; split only when the groups are independently understandable and testable.
6. Stage only the files belonging to the commit being created, and review the staged diff with `git diff --cached` before committing.
7. Commit using conventional commit format:
   ```bash
   git commit -m "type(scope): imperative summary"
   ```

## Commit Message Rules

Use `type(scope): description`. Allowed types, and no others: `feat`, `fix`, `docs`, `style`,
`refactor`, `test`, `chore`.

Choose a concise scope from the package, feature, module, or component affected. Use imperative mood in the description. Do not mention AI assistance in the commit message.

For complex changes, add a short commit body explaining why the change was needed, relevant tradeoffs, or migration notes.

## Multi-Commit Guidance

Split commits by behavior or purpose, not by file type: a refactor apart from the behavior change
that follows it, an unrelated package in a monorepo, generated or lockfile updates only alongside
the source change that caused them. Avoid partial commits that leave the repository in a broken
state — tests ship with the code they cover.

## Default-Branch Commit Policy

Some repositories are worked on straight from the default branch and never see a feature branch.
Record that convention once, then follow it silently.

**Read the marker first**, before step 3:

```bash
grep -rns 'claude-skill:commit default-branch-policy' CLAUDE.md AGENTS.md .claude/CLAUDE.md 2>/dev/null
```

- `=direct` — commit on the default branch without asking, and never propose creating a branch.
- `=branch-first` — keep the guard: ask for explicit confirmation.
- No marker — apply the guard, then detect the convention **after** the commit lands.

**Detect**, only when no marker exists:

```bash
DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$DEFAULT" ] || DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git log --first-parent -30 --format='%H|%ae|%p|%s' "$DEFAULT"
git config user.email
```

A commit went through a PR when it is a merge commit (two parents in `%p`) or its subject ends in
`(#123)`, the suffix a GitHub squash merge leaves; everything else counts as direct. Propose
recording `direct` only when the sample holds at least 10 commits, at least 70% of them are direct,
and at least 5 of those are authored by the current `user.email`.

Repos that rebase-merge leave neither marker, so their PR commits look direct. Before proposing,
sample up to 3 commits classified as direct — if any returns a PR, the repo uses a PR flow, so
record nothing and keep the guard:

```bash
gh api "repos/{owner}/{repo}/commits/<sha>/pulls" --jq 'length'
```

**Ask once**, never writing without explicit confirmation:

> The last 30 commits on `main` are 27 direct commits, 18 of them yours — this repo does not use
> feature branches. Want me to record that in `CLAUDE.md` so I stop asking before every commit on
> `main`? It is a tracked file, so the rule ships to everyone working in this repo.

On a "no", record nothing, keep asking on later runs, and do not re-propose in the same session.

**Write the marker** into an existing `CLAUDE.md`, else an existing `AGENTS.md`, else a new
`CLAUDE.md`, keeping it on its own line so later runs can grep it:

```markdown
## Git workflow

<!-- claude-skill:commit default-branch-policy=direct -->

Work lands directly on the default branch. Commit to it without asking for confirmation, and do not
propose creating a feature branch first.
```

Use `default-branch-policy=branch-first` with the opposite sentence when the user wants the guard
kept permanently. Leave the edit uncommitted and report it; offer to commit it on its own as
`chore(docs): record the direct-to-default-branch commit convention`, never folded into the commit
the user asked for.

## After Committing

Run `git status --short` and report:
- commit hash and message for each commit created
- any remaining uncommitted files
- any verification that was run, or that verification was not run
- whether a default-branch policy was recorded, and which file it went into
