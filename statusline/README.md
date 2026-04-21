# Statusline

Custom Claude Code statusline showing project, branch, model · effort, context usage, and rate-limit tracking with pace projection.

```
my-claude-skills │ main │ Claude Opus 4.7 (1M context) · xhigh │ ████░░░░░░ 45%
current: ○○○○○○○○○○ 0% | weekly: ●●●●●○○○○○ 45% | pace: ↓
resets 4:00pm (4h10m) | resets Thu, 4:00pm
```

## Line 1 — project │ branch │ model · effort │ context

1. **Project** (cyan) — basename of `workspace.project_dir`
2. **Branch** (magenta) — current git branch/short SHA (omitted outside a repo)
3. **Model · effort** (dim) — `model.display_name` from the Claude Code payload plus `effortLevel` read from `~/.claude/settings.json`
4. **Context bar** — 10-segment bar scaled to the usable context (accounts for the ~16.5% auto-compact buffer, or `CLAUDE_CODE_AUTO_COMPACT_WINDOW` when set)
   - green <50% · yellow <65% · orange <80% · blinking red 💀 ≥80%

## Line 2 — rate limit usage (Pro/Max only)

Appears only when the Claude Code payload includes `rate_limits` (Pro/Max subscribers, after the first API response).

- **current** — 5-hour window usage as a dot bar + percentage
- **weekly** — 7-day window usage as a dot bar + percentage
- **pace** — arrow projecting weekly usage at the current daily burn rate:
  - `↓` green — on track (projected <95%)
  - `→` yellow — borderline (projected 95–105%)
  - `↑` red — over pace (projected >105%)

Dot-bar colors (current): dim <30% · green <60% · yellow <80% · orange <90% · red ≥90%.

## Line 3 — reset times

- 5-hour reset as `h:mmam/pm` with time remaining in parentheses
- 7-day reset as `h:mmam/pm` if within 24h, otherwise `Weekday, h:mmam/pm`

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
