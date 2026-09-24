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
   before touching the default branch (`main`, `master`, or whatever the repo uses). The policy decides
   whether committing there needs confirmation — never ask on top of a policy that already answered.
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
Learn that convention from the history and follow it, rather than turning it into a question.

**Read the marker first**, before step 3:

```bash
grep -rns 'claude-skill:commit default-branch-policy' CLAUDE.md AGENTS.md .claude/CLAUDE.md 2>/dev/null
```

- `=direct` — commit on the default branch without asking, and never propose creating a branch.
- `=branch-first` — keep the guard: ask for explicit confirmation.
- No marker — run the detection below **now**, before deciding whether to ask anything.

**Detect**, only when no marker exists:

```bash
DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$DEFAULT" ] || DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git log --first-parent -30 --format='%H|%ae|%p|%s' "$DEFAULT"
git config user.email
```

A commit went through a PR when it is a merge commit (two parents in `%p`) or its subject ends in
`(#123)`, the suffix a GitHub squash merge leaves; everything else counts as direct. The convention
is `direct` when the sample holds at least 10 commits, at least 70% of them are direct, and at least
5 of those are authored by the current `user.email` — that last threshold is what keeps the rule
from being inferred in a repo the user barely commits to.

Repos that rebase-merge leave neither marker, so their PR commits look direct. Before concluding,
sample up to 3 commits classified as direct — if any belongs to a PR, the repo uses a PR flow:

```bash
gh api "repos/{owner}/{repo}/commits/<sha>/pulls" --jq 'length'
```

An error or an empty response counts as **no PR**: an unpushed commit answers `422 No commit found`,
which is not evidence of a PR.

**Record it silently.** When the thresholds hold, write the marker and commit on the default branch
without asking. The history already answered the question, so do not put it to the user — no
"can I record this?", no confirmation step. Report the write in one line in the completion summary
(see **After Committing**) so the user knows a tracked file changed, and leave the edit uncommitted
so they see it before it ships; offer to commit it on its own as
`chore(docs): record the direct-to-default-branch commit convention`, never folded into the commit
the user asked for.

When the thresholds do not hold, or the sample shows a PR flow, write nothing and keep the guard:
ask for explicit confirmation before committing on the default branch. An explicit user instruction
always wins — record nothing if they say not to, and record `branch-first` if they want the guard
kept permanently.

**Write the marker** into an existing `CLAUDE.md`, else an existing `AGENTS.md`, else a new
`CLAUDE.md`, keeping it on its own line so later runs can grep it:

```markdown
## Git workflow

<!-- claude-skill:commit default-branch-policy=direct -->

Work lands directly on the default branch. Commit to it without asking for confirmation, and do not
propose creating a feature branch first.
```

## After Committing

Run `git status --short` and report:
- commit hash and message for each commit created
- any remaining uncommitted files
- any verification that was run, or that verification was not run
- whether a default-branch policy was recorded, and which file it went into
