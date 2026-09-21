# Stacked PRs — execution

Read this once the parent is known: `SKILL.md` carries the detection, this file carries everything
that happens after a parent is found or the user asked for a stack.

## Confirm before stacking

Stacking changes what reviewers see, so state the finding and get a yes:

> This branch sits on top of **#123 — `<title>`** (`feat/auth`), still open. I'll base this PR on `feat/auth` so the diff shows only your changes, and link the two as a stack. Say the word if you'd rather target `main` directly.

Proceed on approval, or immediately when the user already asked for a stack (`stack` argument, or naming the parent). If they decline, open against the trunk and note in the body that the diff includes #123's commits.

## Extension check

The stack commands come from a `gh` extension:

```bash
gh extension list | grep -q 'gh-stack' || echo missing
```

If it is missing, offer the install once — never install without approval:

> Stacking needs the `gh stack` extension: `gh extension install github/gh-stack`. Install it?

Declining does not cancel the stack. `gh pr create --base <parent-branch>` still gives the correct base and diff; what is lost is GitHub's stack view and the cascading rebases. Say that in one line and continue.

## Create the stacked PR

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

## When to suggest splitting

A single branch whose commits fall into clearly separable phases — a refactor followed by the feature that needs it, a migration followed by its consumer — reviews faster as a stack. Say so in one sentence and let the user decide:

> These 14 commits split cleanly into "extract the client" and "add the retry policy". Want two stacked PRs instead of one?

Never rewrite history or move commits to build that stack without approval.
