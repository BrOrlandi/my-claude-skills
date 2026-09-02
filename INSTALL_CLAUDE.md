# Interactive install — Claude Code

**This file is a script for an agent, not a manual for a human.** Paste the install prompt from the
[README](README.md#install-by-prompt) into Claude Code and it will fetch this file and walk you
through the steps below, asking what you want at each stage.

Prefer to do it by hand? [Manual install](README.md#manual-install) is the four-command version.

---

## Instructions for the agent

You are installing [`BrOrlandi/my-claude-skills`](https://github.com/BrOrlandi/my-claude-skills)
into the user's Claude Code setup. Work through the steps in order.

**Rules of engagement**

1. **Nothing is installed without a yes.** Every step asks first. "Install everything" is a valid
   answer, but the user has to give it.
2. **Explain before asking.** The user has never seen this repo. Before each choice, say in one or
   two lines what the thing does and what it costs them (a new symlink, an edit to
   `settings.json`, a dependency like `jq`).
3. **Use `AskUserQuestion`** for the choices, with the options spelled out. Fall back to plain
   questions when an answer is free-form (a path, a list of skill names).
4. **Never clobber.** If a target exists and is not a symlink into this repo, stop and ask. Back up
   `~/.claude/settings.json` before the first edit of the session
   (`cp ~/.claude/settings.json ~/.claude/settings.json.bak-$(date +%Y%m%d%H%M%S)`) and tell the
   user where the backup is.
5. **Always diff what's already there.** Before touching anything already installed, compare it to
   the repo version and show the user what would change. Details in
   [Step 2](#step-2--skills) and [Step 7](#step-7--already-installed-but-out-of-date).
6. **Show the settings JSON before writing it.** Print the exact block being added and get a yes.
7. **Speak the user's language** — if they wrote to you in Portuguese, run the whole install in
   Portuguese.
8. **Be brief.** Lists and short lines, not essays. This is an install, not a tour.

---

## Step 0 — Preflight

Check and report in one short block (don't ask anything yet):

```bash
uname -s                                  # Darwin = macOS, Linux, etc.
git --version; node --version; jq --version
ls -d ~/.claude 2>/dev/null               # existing Claude Code config?
ls ~/.claude/skills 2>/dev/null | head -30
```

What each result means for later:

- **the OS from `uname -s`** decides every platform-specific step below — never assume macOS. On
  `Darwin` everything applies as written. Anything else (Linux, WSL, Git Bash on Windows) → skip the
  caffeinate hooks entirely, and swap the `afplay` in the sound examples for a player that exists
  there: `paplay` or `aplay` on Linux, or
  `powershell -c (New-Object Media.SoundPlayer '<path>').PlaySync()` on Windows. Check which one is
  installed (`command -v paplay aplay`) before offering the sound hooks at all.
- **no `node`** → the statusline can't run. Offer to continue without it.
- **no `jq`** → the last-prompt hooks can't run, and you'll have to edit `settings.json` with a
  different tool. Mention it now, decide in Step 4.
- **`~/.claude/skills` already has entries** → some may be from an older copy of this repo. Keep the
  list; you'll need it in Step 2.

Then show the user the menu of what this repo can install, and ask where they want to start:

| Part | What it is |
| ---- | ---------- |
| **Skills** | ~15 workflow skills — commits, PRs, Jira, refactors, security review, releases |
| **Commands** | Slash commands (currently `/sync-env-to-github`) |
| **Hooks** | Sounds when Claude needs you and when a turn ends, last-prompt capture, and (macOS) keeping the Mac awake while it works |
| **Statusline** | A custom status line: project, branch, model, context bar, rate-limit usage, last prompt |
| **Third-party skills** | Community skills this repo tracks as separate clones |

Offer: *everything*, *let me choose section by section* (default), or *just one section*.

---

## Step 1 — Get the repository

Ask where to clone, defaulting to `~/Projects/my-claude-skills`.

```bash
git clone https://github.com/BrOrlandi/my-claude-skills.git ~/Projects/my-claude-skills
```

If the directory already exists and is this repo, don't re-clone — fetch and report where they
stand:

```bash
cd ~/Projects/my-claude-skills
git fetch origin
git status --short --branch
git log --oneline HEAD..origin/main | head -20
```

If they're behind, show what's new in one or two lines and ask whether to `git pull` before
installing. If the working tree is dirty, say so and let them decide — never stash or discard.

Everything else in this file runs from that directory. Call it `$REPO`.

---

## Step 2 — Skills

Skills are folders with a `SKILL.md`. Installing one means a symlink in `~/.claude/skills/`, which
makes it available in every project.

**Build the list from the repo, not from this file** — it must not go stale:

```bash
cd $REPO
for d in */; do
  [ -f "$d/SKILL.md" ] || continue
  sed -n '1,12p' "$d/SKILL.md"   # frontmatter: name, description, disable-model-invocation
done
```

Present them as a table: **skill · what it does (one line, from `description`) · how it triggers**.
`disable-model-invocation: true` means *explicit only* (the user has to type `/name`); everything
else Claude can trigger on its own when the context fits.

Then check what's already there. For each skill, `~/.claude/skills/<name>` is one of:

| State | What to do |
| ----- | ---------- |
| missing | offer to install |
| symlink into `$REPO` | already installed — say so, nothing to do |
| symlink somewhere else | another copy of this repo. Show both paths, ask which one wins |
| a real directory | a copied (not linked) install. Go to [Step 7](#step-7--already-installed-but-out-of-date) — diff it first |

Now ask how they want to pick:

- **All of them** — install every skill.
- **Pick from the list** — they name the ones they want.
- **One by one** — walk through each skill: name, what it does, when it fires, a concrete example of
  using it; ask yes/no; move on. Use this when they say they don't know what any of it does.
- **None** — skip to the next step.

Install each chosen skill:

```bash
ln -s "$REPO/<skill>/" ~/.claude/skills/<skill>
```

Two skills read an optional private config that is **gitignored** and never published. Mention them
only if the user installed them:

- **`pr`** — `pr/config.json` sets default reviewers per GitHub org.
  `cp $REPO/pr/config.example.json $REPO/pr/config.json`, then fill in the org. Without it, PRs get
  no reviewers requested. See `pr/references/config-format.md`.
- Any other skill shipping a `config.example.json` follows the same pattern.

Finally, tell them skills are available after a **restart of Claude Code** (or `/exit` and reopen).

---

## Step 3 — Commands

Same idea, one file each, symlinked into `~/.claude/commands/`:

```bash
ls $REPO/commands/*.md
```

Read the `description` from each file's frontmatter, list them, ask which to install:

```bash
ln -s "$REPO/commands/<name>.md" ~/.claude/commands/<name>.md
```

There is only one right now (`/sync-env-to-github`), so this step is quick — the git workflows that
used to be commands are the `commit` and `pr` **skills**.

---

## Step 4 — Hooks

Hooks are the part people don't know they want, so **demo before asking**.

Say what a hook is in one line: a command Claude Code runs on an event — a prompt submitted, a tool
about to run, the turn ending. Full reference: [`hooks/README.md`](hooks/README.md).

The scripts get symlinked into `~/.claude/hooks/`, the sounds into `~/.claude/sounds/`:

```bash
mkdir -p ~/.claude/hooks
ln -s "$REPO/hooks/scripts/<script>.sh" ~/.claude/hooks/<script>.sh
mkdir -p ~/.claude/sounds/starwars
ln -s "$REPO/hooks/sounds/bell-notification.wav" ~/.claude/sounds/bell-notification.wav
ln -s "$REPO/hooks/sounds/stop-marimba-muted.wav" ~/.claude/sounds/stop-marimba-muted.wav
ln -s "$REPO/hooks/sounds/starwars/imperial-march-beep.wav" ~/.claude/sounds/starwars/imperial-march-beep.wav
```

Link only what the user picked — a hook they said no to gets no symlink either.

Linking does nothing on its own — the hook only fires once its entry is in
`~/.claude/settings.json`. Do that per group, with the user's yes, using the JSON blocks in
`hooks/README.md`.

### 4a. Sounds

Three sounds, three separate events, and **each one is its own yes or no** — nobody has to take
the set. Some people want the turn-end tap and nothing else; some want only the bell. Ask per sound,
not once for the group.

Pitch the group in one line: *"Claude plays a short sound on a specific moment — it needs you, it
finished, it's about to compact the context. Useful when you send it off on a long task and go do
something else."*

**Play each one before asking about it.** Use the player for their OS (from Step 0) — `afplay` on
macOS, `paplay`/`aplay` on Linux, `powershell -c (New-Object Media.SoundPlayer '<path>').PlaySync()`
on Windows — and play from the repo when the file isn't linked yet:

```bash
afplay ~/.claude/sounds/bell-notification.wav        # macOS, once linked
afplay $REPO/hooks/sounds/bell-notification.wav      # macOS, straight from the clone
paplay $REPO/hooks/sounds/bell-notification.wav      # Linux (PulseAudio); aplay for ALSA
```

| Sound | Event | Play it, then say |
| ----- | ----- | ----------------- |
| `bell-notification.wav` | `Notification` | Claude needs you — a permission prompt, or it has gone idle waiting on an answer. 1.5 s, the loudest of the three |
| `stop-marimba-muted.wav` | `Stop` | Claude finished the turn. A 260 ms damped marimba tap — *"you look away, it finishes, you hear it"*. Warn that `Stop` fires on **every** turn, a one-line answer included, which is exactly why this one is quiet and short and not the bell |
| `starwars/imperial-march-beep.wav` | `PreCompact` | Right before the context window is compacted — the session is about to lose detail |

Then ask with `AskUserQuestion`, **multi-select, one option per sound**, so any combination is
reachable: the bell, the turn-end tap, the compaction beep. Selecting none is a valid answer and
means skip 4a entirely. Only link and wire the ones they picked.

Two things to say while asking:

- Each sound is one independent entry in `settings.json`. Turning one off later means deleting its
  entry (or the whole event key, if nothing else sits under it) — the other two keep working. Say
  this out loud; people accept a sound more readily once they know it's one line to remove.
- Any of the three files can be swapped for another `.wav` without touching the wiring: same path,
  different file, or point the command at a new one in `$REPO/hooks/sounds/`.

Write the hook command with their player, not with `afplay`, and say the non-macOS players are
untested here. No working player on the machine → say so and skip the sound hooks rather than wiring
a command that fails silently.

If they take the `Stop` sound *and* the caffeinate hooks from 4c, both commands go in the same
`Stop` array — one event key, two entries, never a second `"Stop"` key.

### 4b. Last prompt

Pitch: *"Saves the prompt you just sent to a local file so the statusline can show it back to you —
handy when several sessions are open and you're trying to work out which one is doing what. Nothing
leaves your machine, and the file is deleted when the session ends."*

Two scripts, `save-last-prompt.sh` (`UserPromptSubmit`) and `cleanup-last-prompt.sh` (`SessionEnd`).
Needs `jq`. **Only worth it with the statusline** — say so, and if the user already declined the
statusline in the menu, offer to skip this.

### 4c. Caffeinate — macOS only

**Skip this section entirely when `uname -s` isn't `Darwin`.** Don't offer it, don't explain it;
`caffeinate` is a macOS binary. If asked, the equivalents are `systemd-inhibit` on Linux and
`powercfg`/`SetThreadExecutionState` on Windows, and neither is shipped here.

Pitch: *"Keeps the Mac awake while Claude is working, and lets it sleep again the moment the turn
ends. Without it, a long autonomous run dies when the screen locks and the machine sleeps."*

Four entries, two scripts: `caffeinate-guard.sh` on `UserPromptSubmit` + `PreToolUse`,
`caffeinate-release.sh` on `Stop` + `SessionEnd`. Worth mentioning that it can't leak — the
assertion is tied to the Claude process and expires after 30 minutes on its own.

### 4d. RTK — optional, third party

Don't install this one; it belongs to another project. Mention it in one or two lines only if the
user asks what else is possible, or if `command -v rtk` already finds it:

*"[RTK](https://github.com/rtk-ai/rtk) is a separate CLI that runs common dev commands and returns a
compacted version of their output. Its `PreToolUse` hook swaps `git status` for `rtk git status` and
so on, which cuts a good chunk of the tokens an agent burns on shell output. Install it from RTK's
own installer — this repo only documents it."*

If `rtk` is already installed but the hook isn't wired, show the block from `hooks/README.md` and
offer to add it (note the `"matcher": "Bash"`, unlike the others).

### 4e. Write the settings

Merge into `~/.claude/settings.json` — **never overwrite the file**. It has one `hooks` object;
each event key is an array; several scripts can share one event (that's how `save-last-prompt.sh`
and `caffeinate-guard.sh` both sit under `UserPromptSubmit`).

Back it up first, show the exact resulting `hooks` block, get a yes, then write it (with `jq`, or by
editing the file if `jq` is missing). Validate afterwards:

```bash
jq . ~/.claude/settings.json > /dev/null && echo "settings.json is valid"
```

Tell the user hooks are only picked up on a **new session**.

---

## Step 5 — Statusline

Pitch it by **showing it**, not describing it. Run the real thing with a sample payload:

```bash
echo '{"model":{"display_name":"Claude Opus 5"},"workspace":{"current_dir":"'$REPO'","project_dir":"'$REPO'"},"context_window":{"remaining_percentage":60,"total_tokens":1000000},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":'$(($(date +%s)+7200))'},"seven_day":{"used_percentage":45,"resets_at":'$(($(date +%s)+300000))'}}}' | node $REPO/statusline/statusline.js
```

Then walk the rows:

| Row | Shows |
| --- | ----- |
| 1 | project · git branch · model + effort level · context bar (colour-coded, goes 💀 red past 80%) |
| 2 | rate-limit usage — 5-hour window, 7-day window, and a pace arrow projecting whether you'll blow the weekly limit (Pro/Max only) |
| 3 | when each limit resets, plus the active [caveman](https://github.com/JuliusBrussee/caveman) mode if that plugin is installed |
| 4 | `❯ your last prompt`, truncated — needs the last-prompt hooks from Step 4b |

Ask **which rows they want**, offering "all of it" as the default and letting them drop any of:
`project`, `branch`, `model`, `effort`, `context`, `rateLimits`, `pace`, `resets`, `caveman`,
`lastPrompt`.

If they drop anything, write their choice to `$REPO/statusline/config.json` (gitignored, survives a
`git pull`, template in `config.example.json`) — only the keys set to `false` are needed:

```json
{ "caveman": false, "pace": false }
```

Re-run the preview command so they see the result, and adjust if they change their mind.

Then link the script and wire it up:

```bash
ln -s "$REPO/statusline/statusline.js" ~/.claude/statusline.js
```

```json
{
  "statusLine": { "type": "command", "command": "node /Users/<you>/.claude/statusline.js" }
}
```

Use the absolute path — `~` doesn't expand there. Requires Node on `PATH`, no dependencies.

**Codex user?** The native Codex status line is configured separately, in
[`codex-statusline/`](codex-statusline/).

---

## Step 6 — Third-party skills

Community skills tracked as independent clones under `thirdparty/` (gitignored — they are not part
of this repo's history). List what `thirdparty-skills.json` declares, say what each does, and ask
whether to fetch them:

```bash
cd $REPO && ./update-thirdparty.sh
```

Then symlink the ones they want the same way as Step 2, or just run `./install.sh`, which picks up
every third-party skill that has been cloned.

---

## Step 7 — Already installed but out of date

Run this check whenever something is already present, and at the end of the install as a sweep.

**Symlinked into `$REPO`** — the file *is* the repo file, so there's nothing to diff. It's current
as of the last `git pull`. If Step 1 found the clone behind `origin/main`, offer the pull; that
updates every linked skill at once.

**A real file or directory** (someone copied the files, or an older install predates symlinking):

```bash
diff -ru ~/.claude/skills/<name> $REPO/<name> | head -60      # skills
diff ~/.claude/hooks/<script>.sh $REPO/hooks/scripts/<script>.sh
diff ~/.claude/statusline.js $REPO/statusline/statusline.js
```

For each one that differs, tell the user **what actually changed** — "the repo version adds X", not
a wall of diff — and ask:

- **Update** — back the local copy up (`mv <path> <path>.bak-$(date +%Y%m%d%H%M%S)`), then symlink
  the repo version.
- **Keep mine** — leave it, and note that it won't get future updates.
- **Show me the full diff** — print it, then ask again.

Never delete a local copy without moving it aside first, and never resolve this on your own
judgement: their copy may carry local edits they care about.

---

## Step 8 — Wrap up

Report in a short list:

- what was installed (skills, commands, hooks, statusline) and where the symlinks point
- what was **skipped** and how to add it later (`./install.sh`, or re-run this install prompt)
- anything still needed by hand: a missing `jq`/`node`, `pr/config.json` for default reviewers,
  a sound player for their OS
- **restart Claude Code** — skills, hooks and the statusline are read at session start

Then a one-liner on staying current:

```bash
cd $REPO && git pull && ./install.sh
```

Symlinks mean the pull is the update; `./install.sh` only picks up things that are *new*.

To remove everything: `./uninstall.sh` deletes only the symlinks pointing back into the repo. The
`hooks` and `statusLine` entries in `settings.json` are the user's to remove.
