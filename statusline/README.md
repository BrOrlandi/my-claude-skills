# Statusline

Custom Claude Code statusline showing project, branch, model · effort, context usage, rate-limit
tracking with pace projection on both windows, and the prompt you last sent. Every row can be turned off — see
[Customize](#customize-which-rows-you-see).

```
my-claude-skills │ main │ Claude Opus 4.7 (1M context) · xhigh │ █████████░░░░░░░░░░░ 45%
current: ●●●●◍◍◍◍○○○○○○○○○○○○ 22% ↓ | weekly: ●●●●●●●●●◍○○○○○○○○○○ 45% | pace: ↓
resets 4:00pm (4h10m) | resets Thu, 4:00pm | caveman off
❯ review the auth middleware and tell me what breaks under load
```

## Line 1 — project │ branch │ model · effort │ context

1. **Project** (cyan) — basename of `workspace.project_dir`
2. **Branch** (magenta) — current git branch/short SHA (omitted outside a repo)
3. **Model · effort** (dim) — `model.display_name` and the live session `effort.level`, both from the Claude Code payload (falling back to `effortLevel` in `~/.claude/settings.json` on older CLI versions)
4. **Context bar** — 20-segment bar scaled to the usable context (accounts for the ~16.5% auto-compact buffer, or `CLAUDE_CODE_AUTO_COMPACT_WINDOW` when set)
   - green <50% · yellow <65% · orange <80% · blinking red 💀 ≥80%

## Line 2 — rate limit usage (Pro/Max only)

Appears only when the Claude Code payload includes `rate_limits` (Pro/Max subscribers, after the first API response).

- **current** — 5-hour window usage as a dot bar + percentage, followed by a bare pace arrow
- **weekly** — 7-day window usage as a dot bar + percentage
- **pace** — arrow projecting weekly usage at the current daily burn rate

### Dot bars

Each bar is twenty dots — one dot per 5% — and reads left to right:

| Dot | Means |
| --- | ----- |
| `●` | Usage already spent in the window |
| `◍` (dim) | Time that has passed in the window without being spent |
| `○` | Neither spent nor elapsed |

So `●●●●●◍◍◍◍◍○○○○○○○○○○ 25%` means a quarter of the allowance is gone, half the
window has elapsed, and you are running at half the pace the window allows. When usage runs ahead of the
clock there is nothing to shade, and the bar is plain `●`/`○`. The shaded region follows the
`pace` config key, so turning the arrows off turns it off too.

Both arrows project the window's usage at the burn rate so far — usage spent divided by time
elapsed, extrapolated to the end of the window:

  - `↓` green — on track (projected <95%)
  - `→` yellow — borderline (projected 95–105%)
  - `↑` red — over pace (projected >105%)

The session arrow appears 15 minutes into a 5-hour window, the weekly one an hour into the week —
before that there is too little elapsed time for the projection to mean anything.

Dot-bar colors (current): dim <30% · green <60% · yellow <80% · orange <90% · red ≥90%.

## Line 3 — reset times + caveman badge

- 5-hour reset as `h:mmam/pm` with time remaining in parentheses
- 7-day reset as `h:mmam/pm` if within 24h, otherwise `Weekday, h:mmam/pm`
- **`caveman <mode>`** (dim, lowercase) — shows the active mode of the [caveman](https://github.com/JuliusBrussee/caveman) plugin (`caveman full`, `caveman ultra`, …), or `caveman off` when inactive. Reads `$CLAUDE_CONFIG_DIR/.caveman-active` (default `~/.claude/.caveman-active`); symlinks rejected, contents capped at 64 bytes, mode whitelisted. If no rate-limits row exists, the badge falls back to its own line.

## Line 4 — your last prompt

`❯ <the prompt you last sent>`, dimmed and truncated to 120 characters. Handy when several
sessions are open and you want to see at a glance which one is doing what.

It appears only if the **last-prompt hooks** from [`hooks/`](../hooks/) are installed — they write
`~/.claude/last-prompts/<session_id>.txt`, which this script reads. No hooks, no row.

## Customize which rows you see

Every segment above is on by default. To hide some, copy the template and flip the ones you don't
want:

```bash
cp statusline/config.example.json statusline/config.json
```

```json
{
  "project": true,
  "branch": true,
  "model": true,
  "effort": true,
  "context": true,
  "rateLimits": true,
  "pace": true,
  "resets": true,
  "caveman": true,
  "lastPrompt": true
}
```

| Key | Turns off |
| --- | --------- |
| `project` | The project name (line 1) |
| `branch` | The git branch (line 1) |
| `model` | The model name (line 1) — takes `effort` with it |
| `effort` | Just the `· xhigh` effort suffix, keeping the model name |
| `context` | The context bar (line 1) |
| `rateLimits` | The `current:` / `weekly:` usage bars (line 2) |
| `pace` | Both pace arrows — the bare one after `current:` and `pace: ↓` — and the dim `◍` elapsed-time region inside both dot bars (line 2) |
| `resets` | The reset-times row (line 3) |
| `caveman` | The caveman badge (line 3) |
| `lastPrompt` | The `❯ your last prompt…` row |

`config.json` is **gitignored**, so your choices survive a `git pull` and never get published. Any
key you leave out keeps its default (`true`), and a missing or malformed file just means "show
everything". Changes apply on the next statusline render — no restart needed.

`lastPrompt` needs the last-prompt hooks from [`hooks/`](../hooks/) to be installed; without them
that row simply never appears.

## Install

`install.sh` symlinks `statusline.js` to `~/.claude/statusline.js`. Then add this block to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "node /Users/<you>/.claude/statusline.js"
  }
}
```

Requires Node.js on `PATH`. No dependencies.

## Test

```bash
echo '{"model":{"display_name":"Claude Opus 4.7"},"workspace":{"current_dir":"/tmp","project_dir":"/tmp"},"context_window":{"remaining_percentage":60,"total_tokens":1000000},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":9999999999},"seven_day":{"used_percentage":45,"resets_at":9999999999}}}' | node statusline.js
```
