# Changelog

What changed in this collection of Claude Code skills, commands, hooks and statusline, written
for whoever installs them: what a skill now does differently, not how it was implemented.

Entries are grouped by the day the work landed, newest first. The collection carries **no version
number and no tags** — you install whatever `main` has, with `./install.sh`
(see [Install](README.md#install-by-prompt)).

History starts here: earlier work is in the git log, not in this file.

## 2026-09-01

### Changed

- **`pr-comments` skill** — replies to reviewers are no longer walls of text. An inline thread
  reply is now capped at 1 to 3 sentences that state the outcome only ("fixed, here", "declined,
  this rule says so"), with no headings, lists or rehashing of what the reviewer just wrote. The
  reasoning that used to bloat those replies moves to a single PR-level comment per round, itself
  kept to one line per item. When a reviewer comes back on a thread you already answered, the skill
  now spots that follow-up and lifts the cap so the doubt can be settled properly.

## 2026-08-21

### Changed

- **`release` skill** — a repository that keeps no version number at all is now a complete
  convention rather than a gap: `bump.policy: "none"` says so, and the change collector reports
  "no version to bump" instead of proposing one it cannot apply. It also warns when the commits it
  found are dated the same day as the changelog entry it anchored on, since those are usually
  already described there.

## 2026-08-20

### Added

- **`release` skill** — works out how a repository releases and writes that down, then runs it.
  The first run in a repo reads the stack (web app, mobile app, desktop binary, library, or a
  monorepo with several apps), settles the convention with you, and records it in
  `.claude/release.json` plus a section in that repo's `CLAUDE.md` — so a later session that never
  triggers the skill still bumps the right file and tags correctly. From then on it writes the
  changelog entries from the commits since the last release, bumps the version, tags, and handles
  the publish channels the repo actually has. Everything past the version number is optional: a
  repo that only wants a version, or only a local changelog, stops there and is never asked again.

### Changed

- **`pr`** — a branch cut from another branch that is still under review now opens against that
  parent instead of the trunk, so the diff no longer repeats the parent's commits. `stack` and
  `no-stack` force either path.
- **`pr`** — after opening a PR it offers to update the changelog, but only in repositories that
  have a release convention recorded. Repos without one are left alone.
