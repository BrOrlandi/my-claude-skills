# Changelog

What changed in this collection of Claude Code skills, commands, hooks and statusline, written
for whoever installs them: what a skill now does differently, not how it was implemented.

Entries are grouped by the day the work landed, newest first. The collection carries **no version
number and no tags** — you install whatever `main` has, with `./install.sh`
(see [Install](README.md#install-by-prompt)).

History starts here: earlier work is in the git log, not in this file.

## 2026-09-04

### Changed

- **Statusline: a pace arrow for the current session too.** The 5-hour `current:` bar now ends with
  a bare arrow — green `↓`, yellow `→`, red `↑` — projecting where the session lands at the burn
  rate so far, the same reading the weekly `pace:` arrow gives for the week. No label, just the
  arrow. It shows up 15 minutes into a window, once there is enough elapsed time for the projection
  to mean anything, and the `pace` key in `statusline/config.json` turns both arrows off together.

## 2026-09-02

### Added

- **A sound for the end of a turn.** `hooks/sounds/stop-marimba-muted.wav` on the `Stop` hook — a
  260 ms damped marimba tap that plays when Claude finishes responding, so you can look away during
  a long task and hear when it lands. It is deliberately quieter and much shorter than the
  notification bell, because `Stop` fires on every turn, including a one-line answer. Wiring is in
  [`hooks/README.md`](hooks/README.md#sounds); if you already run the caffeinate hooks, the sound
  joins the `Stop` array they are in rather than replacing it.

### Changed

- **The install prompt now asks about each sound separately.** It plays the bell, the turn-end tap
  and the compaction beep one at a time and takes a yes or no on each, instead of treating the
  sounds as one block you either take or skip. Only the ones you pick get linked and wired, and it
  tells you which single entry to delete to turn one off later.

## 2026-09-01

### Added

- **Hooks are part of the collection now.** A new `hooks/` folder ships the scripts, the sounds they
  play and the exact `settings.json` blocks that turn them on: a notification bell when Claude needs
  you, the Imperial March right before a context compaction, last-prompt capture that feeds the
  statusline, and — on macOS only — a caffeinate guard that keeps the Mac awake while Claude is
  working and releases it the moment the turn ends. `./install.sh` links the scripts into
  `~/.claude/hooks/`; wiring them up stays your call. RTK's command-rewrite hook is documented there
  too, without vendoring a copy that would go stale.
- **Install by prompt.** The README now carries a copy-paste prompt: hand it to Claude Code (or
  Codex) and it runs an interactive install from `INSTALL_CLAUDE.md` — listing every skill with what
  it does before asking which ones you want, playing the notification sound so you can hear it
  before deciding, previewing the statusline with your own data, and skipping the macOS-only pieces
  when you are not on a Mac. It never touches `~/.claude/settings.json` without showing you the
  block first, and anything already installed gets diffed against GitHub so you can choose what to
  update. A second prompt handles just the update pass.
- **The statusline is configurable.** `statusline/config.json` (gitignored, template in
  `config.example.json`) turns individual rows off — project, branch, model, effort, context bar,
  rate-limit bars, pace arrow, reset times, caveman badge, last prompt. Leave it out and you get
  everything, as before.

### Changed

- The sounds moved from `sounds/` to `hooks/sounds/`, so it is obvious what plays them. They still
  land in `~/.claude/sounds/` with the same names — re-run `./install.sh` after pulling and the old
  symlinks are replaced.
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
