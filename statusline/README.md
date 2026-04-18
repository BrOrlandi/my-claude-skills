# Statusline

Custom Claude Code statusline showing project, branch, model · effort, and a color-coded context usage bar.

```
my-project-name │ main │ Claude Opus 4.7 · xhigh │ ████░░░░░░ 48%
```

## Columns

1. **Project** (cyan) — basename of `workspace.project_dir`
2. **Branch** (magenta) — current git branch/short SHA (omitted outside a repo)
3. **Model · effort** (dim) — `model.display_name` from the Claude Code payload plus `effortLevel` read from `~/.claude/settings.json`
4. **Context bar** — 10-segment bar scaled to the usable context (accounts for the ~16.5% auto-compact buffer, or `CLAUDE_CODE_AUTO_COMPACT_WINDOW` when set)
   - green <50% · yellow <65% · orange <80% · blinking red 💀 ≥80%

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
echo '{"model":{"display_name":"Claude Opus 4.7"},"workspace":{"current_dir":"/tmp","project_dir":"/tmp"},"context_window":{"remaining_percentage":60,"total_tokens":1000000}}' | node statusline.js
```
