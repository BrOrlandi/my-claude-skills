# Sounds

Notification sounds for Claude Code hooks. macOS plays them with the built-in `afplay`.

## Contents

| File | Hook | When it plays |
| ---- | ---- | ------------- |
| `bell-notification.wav` | `Notification` | Claude needs your attention — permission prompt or waiting on idle input |
| `starwars/imperial-march-beep.wav` | `PreCompact` | Right before the context window is compacted |

## Install

`install.sh` at the repo root symlinks every `.wav` under `sounds/` into `~/.claude/sounds/`, keeping the subfolder structure:

```bash
cd ~/Projects/my-claude-skills
./install.sh
```

Result:

```
~/.claude/sounds/bell-notification.wav                -> <repo>/sounds/bell-notification.wav
~/.claude/sounds/starwars/imperial-march-beep.wav     -> <repo>/sounds/starwars/imperial-march-beep.wav
```

Files that already exist at the target path and are **not** symlinks are left untouched (the script prints a `Skipping sound ...` line). That way sounds you keep locally outside this repo are never clobbered. To adopt a repo version over a local file, delete the local file first and re-run `./install.sh`.

## Enable the hooks

Symlinking only puts the files in place — Claude Code does not play anything until the hooks are wired up. Add this to `~/.claude/settings.json` (merge into an existing `hooks` object if you already have one):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "afplay ~/.claude/sounds/bell-notification.wav &"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "afplay ~/.claude/sounds/starwars/imperial-march-beep.wav &"
          }
        ]
      }
    ]
  }
}
```

The trailing `&` backgrounds playback so the hook returns immediately and never blocks the session.

Restart Claude Code (or start a new session) for settings changes to take effect.

## Verify

Play the files directly to confirm the symlinks resolve and audio works:

```bash
afplay ~/.claude/sounds/bell-notification.wav
afplay ~/.claude/sounds/starwars/imperial-march-beep.wav
```

## Other hooks you can bind

Any hook event accepts the same `afplay` command — useful ones for sounds:

| Event | Fires when |
| ----- | ---------- |
| `Notification` | Claude needs attention |
| `Stop` | Claude finishes responding |
| `SubagentStop` | A subagent finishes |
| `PreCompact` | Before context compaction |
| `SessionEnd` | Session ends |

## Uninstall

`./uninstall.sh` removes only the symlinks that point back into this repo; local (non-symlink) sound files are left alone. Remove the `hooks` entries from `~/.claude/settings.json` separately.

## Platform note

`afplay` is macOS-only. On Linux, swap the command for `paplay` (PulseAudio) or `aplay` (ALSA).
