# Hooks

Claude Code hooks fire on session events (a prompt is submitted, a tool is about to run, the turn
ends). This folder holds every hook this collection ships: the scripts, the sounds they play, and
the exact `~/.claude/settings.json` blocks that wire them up.

Hooks are **opt-in**. Symlinking a script does nothing until you add its entry to
`~/.claude/settings.json`. The interactive installer ([INSTALL_CLAUDE.md](../INSTALL_CLAUDE.md))
walks through them one by one and merges the JSON for you.

## What's here

| Hook group | Event(s) | Platform | Needs | What it does |
| ---------- | -------- | -------- | ----- | ------------ |
| **Sounds** | `Notification`, `Stop`, `PreCompact` | macOS (`afplay`) | — | Plays a sound when Claude needs you, when a turn ends, and before a context compaction |
| **Last prompt** | `UserPromptSubmit`, `SessionEnd` | any | `jq` | Saves your last prompt so the statusline can show it back to you |
| **Caffeinate** | `UserPromptSubmit`, `PreToolUse`, `Stop`, `SessionEnd` | macOS only | — | Keeps the Mac awake while Claude is working, releases it when the turn ends |
| **RTK rewrite** | `PreToolUse` (Bash) | any | [rtk](https://github.com/rtk-ai/rtk), `jq` | Optional, third-party: rewrites shell commands to their token-cheap `rtk` equivalent |

```
hooks/
├── scripts/
│   ├── caffeinate-guard.sh      → ~/.claude/hooks/caffeinate-guard.sh
│   ├── caffeinate-release.sh    → ~/.claude/hooks/caffeinate-release.sh
│   ├── save-last-prompt.sh      → ~/.claude/hooks/save-last-prompt.sh
│   └── cleanup-last-prompt.sh   → ~/.claude/hooks/cleanup-last-prompt.sh
└── sounds/
    ├── bell-notification.wav          → ~/.claude/sounds/bell-notification.wav
    ├── stop-marimba-muted.wav         → ~/.claude/sounds/stop-marimba-muted.wav
    └── starwars/imperial-march-beep.wav → ~/.claude/sounds/starwars/…
```

`../install.sh` creates those symlinks (scripts into `~/.claude/hooks/`, sounds into
`~/.claude/sounds/`, subfolders preserved). Files that already exist at the target and are **not**
symlinks are left untouched — the script prints a `Skipping …` line so you can decide what to do
with your local copy.

---

## Sounds

macOS plays `.wav` files with the built-in `afplay`. The trailing `&` backgrounds playback so the
hook returns immediately and never blocks the session.

| Sound | Hook | When it plays |
| ----- | ---- | ------------- |
| `bell-notification.wav` | `Notification` | Claude needs your attention — a permission prompt, or it has been idle waiting on you |
| `stop-marimba-muted.wav` | `Stop` | Claude finished the turn — a damped marimba tap, 260 ms, deliberately quiet |
| `starwars/imperial-march-beep.wav` | `PreCompact` | Right before the context window is compacted |

`Stop` fires at the end of *every* turn, a one-line answer included, so the sound that goes there
has to be shorter and quieter than a notification you are meant to react to — hence the muted
marimba rather than the bell.

Take them one at a time: each sound is one independent entry in `settings.json`, so wiring the
turn-end tap and skipping the bell (or any other combination) is fine, and removing one later means
deleting its entry — the others keep working. Swapping the file itself needs no rewiring: point the
command at a different `.wav` under `~/.claude/sounds/`.

Hear them before deciding:

```bash
afplay ~/.claude/sounds/bell-notification.wav
afplay ~/.claude/sounds/stop-marimba-muted.wav
afplay ~/.claude/sounds/starwars/imperial-march-beep.wav
```

Wiring:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "afplay ~/.claude/sounds/bell-notification.wav &" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "afplay ~/.claude/sounds/stop-marimba-muted.wav &" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "afplay ~/.claude/sounds/starwars/imperial-march-beep.wav &" }
        ]
      }
    ]
  }
}
```

If you also wired the caffeinate hooks, `Stop` already exists — add the `afplay` command to that
event's `hooks` array instead of creating a second `"Stop"` key, which would silently replace the
first.

**Other events that take the same `afplay` command**, if you want more feedback:

| Event | Fires when |
| ----- | ---------- |
| `Notification` | Claude needs attention |
| `Stop` | Claude finishes responding |
| `SubagentStop` | A subagent finishes |
| `PreCompact` | Before context compaction |
| `SessionEnd` | The session ends |

**Not on macOS?** Swap `afplay` for `paplay` (PulseAudio) or `aplay` (ALSA) on Linux, or
`powershell -c (New-Object Media.SoundPlayer '<path>').PlaySync()` on Windows.

---

## Last prompt

`save-last-prompt.sh` (`UserPromptSubmit`) writes the prompt you just sent to
`~/.claude/last-prompts/<session_id>.txt`; `cleanup-last-prompt.sh` (`SessionEnd`) deletes that
file when the session ends. Nothing leaves your machine.

The [statusline](../statusline/) reads it and prints it back as the last row (`❯ your prompt…`,
truncated to 120 characters) — useful when you have several sessions open and want to see at a
glance which one is doing what. **Without these hooks the statusline simply omits that row**, so
they are only worth installing if you use the statusline.

Requires `jq` on `PATH`.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/save-last-prompt.sh" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/cleanup-last-prompt.sh" }
        ]
      }
    ]
  }
}
```

---

## Caffeinate (macOS only)

The problem: you send a long task off to Claude, walk away, and the Mac goes to sleep mid-run.

`caffeinate-guard.sh` starts a `caffeinate -dimsu` assertion when a turn starts
(`UserPromptSubmit`) and refreshes it while tools keep running (`PreToolUse` heartbeat).
`caffeinate-release.sh` kills it when the turn ends (`Stop`) or the session ends (`SessionEnd`),
so your Mac is only kept awake while Claude is actually working.

Three layers keep the assertion from leaking:

1. `-w <claude pid>` — it dies with Claude if the CLI is closed, killed or hangs.
2. `-t 1800` — a 30-minute backstop, in case nothing else kills it.
3. `caffeinate-release.sh` — the normal path, on `Stop` and `SessionEnd`.

The guard is idempotent: it only restarts `caffeinate` when the current assertion is older than
5 minutes or already dead.

**This is macOS-specific** — `caffeinate` is a macOS binary. On Linux the equivalent would be
`systemd-inhibit`, on Windows `powercfg` / `SetThreadExecutionState`; neither is shipped here.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/caffeinate-guard.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/caffeinate-guard.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/caffeinate-release.sh" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/caffeinate-release.sh" }
        ]
      }
    ]
  }
}
```

Verify it works: start a long task and run `pmset -g assertions | grep caffeinate` — you should
see an assertion while the turn runs and none a few seconds after it ends.

---

## RTK rewrite (optional, third-party)

[RTK](https://github.com/rtk-ai/rtk) ("Rust Token Killer") is a separate open-source CLI that
proxies common dev commands and returns a compacted version of their output — `rtk git status`
instead of `git status`, and so on. On noisy commands it cuts most of the output tokens, which
matters when the agent runs dozens of them per session.

Its `PreToolUse` hook intercepts every Bash command, asks `rtk rewrite` whether there is a cheaper
equivalent, and swaps the command in when there is. The hook is a thin wrapper — all rewrite rules
live in the `rtk` binary itself.

**Not shipped here**, deliberately: the script is versioned alongside the binary (it checks for
`rtk >= 0.23.0` and carries its own checksum), so vendoring a copy in this repo would go stale.
Install it from RTK's own installer, which writes `~/.claude/hooks/rtk-rewrite.sh` and can wire the
settings entry for you:

```bash
# see https://github.com/rtk-ai/rtk#installation
rtk --version   # must be >= 0.23.0
```

The resulting settings entry looks like this — note the `Bash` matcher, unlike the others here:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/rtk-rewrite.sh" }
        ]
      }
    ]
  }
}
```

Requires `jq`. If `rtk` or `jq` is missing the hook prints a warning and passes the command through
unchanged, so a broken install degrades to "no rewriting" rather than to a broken session.

> Heads-up: there is a name collision with a different `rtk` (Rust Type Kit). If `rtk gain` fails,
> you have the wrong binary.

---

## Merging into an existing settings.json

`~/.claude/settings.json` has a single `hooks` object; every event key holds an **array**, and each
entry holds its own `hooks` array. Multiple scripts can share one event — that is exactly how
`save-last-prompt.sh` and `caffeinate-guard.sh` both live under `UserPromptSubmit`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/save-last-prompt.sh" },
          { "type": "command", "command": "~/.claude/hooks/caffeinate-guard.sh" }
        ]
      }
    ]
  }
}
```

Back the file up before editing it (`cp ~/.claude/settings.json ~/.claude/settings.json.bak`), and
**restart Claude Code** afterwards — hook changes are read at session start.

Plugins can register hooks too (they live in the plugin's own `plugin.json`, not in your settings).
`claude --debug` prints every hook that fired, which is the quickest way to see the full picture.

## Uninstall

`../uninstall.sh` removes only the symlinks that point back into this repo; local (non-symlink)
files are left alone. The `hooks` entries in `~/.claude/settings.json` are yours to remove
separately.
