# Codex Statusline

Codex-native status line configuration that approximates the custom Claude Code statusline in `statusline/`.

Codex does not currently use a `statusLine.command` script like Claude Code. Instead, Codex reads an ordered list of native status-line item identifiers from `~/.codex/config.toml`.

This configuration shows:

```text
project-name · git-branch · model-with-reasoning · context-used · five-hour-limit · weekly-limit
```

That maps to:

- project name
- current git branch
- model with reasoning effort
- context usage
- 5-hour usage limit
- weekly usage limit

## Install

From the repository root:

```bash
./codex-statusline/install.sh
```

The installer:

1. Backs up `~/.codex/config.toml` to `~/.codex/config.toml.bak-statusline-YYYYMMDDHHMMSS`
2. Adds or updates:

   ```toml
   [tui]
   status_line = ["project-name", "git-branch", "model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit"]
   ```

3. Leaves unrelated config untouched.

Restart Codex after installing.

## Manual Install

Edit `~/.codex/config.toml` and add:

```toml
[tui]
status_line = ["project-name", "git-branch", "model-with-reasoning", "context-used", "five-hour-limit", "weekly-limit"]
```

If `[tui]` already exists, add only the `status_line = ...` line under that table.

## Notes

- Codex joins status-line items with ` · `.
- Items that are not available yet, such as rate limits before the first API response, are omitted by Codex.
- The custom bars, colors, reset formatting, and pace projection from the Claude Code `statusline/statusline.js` are not available through Codex's native status-line configuration.
- In the Codex TUI, `/statusline` can also be used to customize the selected items interactively.
