#!/usr/bin/env node
// Claude Code Statusline
// Layout: project │ branch │ model · effort │ context bar

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

function gitBranch(dir) {
  try {
    const out = execSync('git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null', {
      cwd: dir,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 500,
    }).trim();
    return out || null;
  } catch (e) {
    return null;
  }
}

function readEffort() {
  try {
    const settingsPath = path.join(os.homedir(), '.claude', 'settings.json');
    const s = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    return s.effortLevel || null;
  } catch (e) {
    return null;
  }
}

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => (input += chunk));
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const model = data.model?.display_name || 'Claude';
    const dir = data.workspace?.current_dir || process.cwd();
    const remaining = data.context_window?.remaining_percentage;
    const totalCtx = data.context_window?.total_tokens || 1_000_000;

    // Column 1: project name
    const projectDir = data.workspace?.project_dir || dir;
    const project = path.basename(projectDir);

    // Column 2: git branch
    const branch = gitBranch(dir);

    // Column 3: model · effort
    const effort = readEffort();
    const modelSegment = effort ? `${model} · ${effort}` : model;

    // Column 4: context bar
    const acw = parseInt(process.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW || '0', 10);
    const AUTO_COMPACT_BUFFER_PCT = acw > 0 ? Math.min(100, (acw / totalCtx) * 100) : 16.5;
    let ctx = '';
    if (remaining != null) {
      const usableRemaining = Math.max(0, ((remaining - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100);
      const used = Math.max(0, Math.min(100, Math.round(100 - usableRemaining)));
      const filled = Math.floor(used / 10);
      const bar = '█'.repeat(filled) + '░'.repeat(10 - filled);

      if (used < 50) {
        ctx = `\x1b[32m${bar} ${used}%\x1b[0m`;
      } else if (used < 65) {
        ctx = `\x1b[33m${bar} ${used}%\x1b[0m`;
      } else if (used < 80) {
        ctx = `\x1b[38;5;208m${bar} ${used}%\x1b[0m`;
      } else {
        ctx = `\x1b[5;31m💀 ${bar} ${used}%\x1b[0m`;
      }
    }

    const sep = ' \x1b[2m│\x1b[0m ';
    const parts = [
      `\x1b[36m${project}\x1b[0m`,
      branch ? `\x1b[35m${branch}\x1b[0m` : null,
      `\x1b[2m${modelSegment}\x1b[0m`,
      ctx || null,
    ].filter(Boolean);

    process.stdout.write(parts.join(sep));
  } catch (e) {
    // Silent fail - don't break statusline on parse errors
  }
});
