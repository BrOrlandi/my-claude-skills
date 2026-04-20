#!/usr/bin/env node
// Claude Code Statusline
// Line 1: project │ branch │ model · effort │ context bar
// Line 2: current: <bar> % | weekly: <bar> %
// Line 3: resets <time> (<remaining>) | resets <weekday>, <time>

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function formatTime(date) {
  let h = date.getHours();
  const m = date.getMinutes();
  const ampm = h >= 12 ? 'pm' : 'am';
  h = h % 12 || 12;
  return `${h}:${m.toString().padStart(2, '0')}${ampm}`;
}

function formatRemaining(seconds) {
  if (seconds <= 0) return '0m';
  if (seconds < 60) return `${Math.floor(seconds)}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remMin = minutes % 60;
  return remMin > 0 ? `${hours}h${remMin}m` : `${hours}h`;
}

function dotBar(pct) {
  const filled = Math.max(0, Math.min(10, Math.round(pct / 10)));
  return '●'.repeat(filled) + '○'.repeat(10 - filled);
}

function colorByPct(pct) {
  if (pct < 30) return '\x1b[2m';          // dim gray
  if (pct < 60) return '\x1b[32m';         // green
  if (pct < 80) return '\x1b[33m';         // yellow
  if (pct < 90) return '\x1b[38;5;208m';   // orange
  return '\x1b[31m';                       // red
}

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

    let output = parts.join(sep);

    // Rate limits (only present for Pro/Max subscribers after first API response)
    const rl = data.rate_limits;
    const fh = rl?.five_hour;
    const sd = rl?.seven_day;
    if ((fh && typeof fh.used_percentage === 'number') ||
        (sd && typeof sd.used_percentage === 'number')) {
      const now = Date.now() / 1000;
      const limSep = ' \x1b[2m|\x1b[0m ';
      const limParts = [];
      const resetParts = [];

      if (fh && typeof fh.used_percentage === 'number') {
        const pct = Math.round(fh.used_percentage);
        const color = colorByPct(pct);
        limParts.push(`\x1b[2mcurrent:\x1b[0m ${color}${dotBar(pct)} ${pct}%\x1b[0m`);
        if (typeof fh.resets_at === 'number') {
          const d = new Date(fh.resets_at * 1000);
          const rem = formatRemaining(fh.resets_at - now);
          resetParts.push(`\x1b[2mresets ${formatTime(d)} (${rem})\x1b[0m`);
        }
      }

      if (sd && typeof sd.used_percentage === 'number') {
        const pct = Math.round(sd.used_percentage);
        // Colored variant: limParts.push(`\x1b[2mweekly:\x1b[0m ${colorByPct(pct)}${dotBar(pct)} ${pct}%\x1b[0m`);
        limParts.push(`\x1b[2mweekly: ${dotBar(pct)} ${pct}%\x1b[0m`);
        if (typeof sd.resets_at === 'number') {
          const d = new Date(sd.resets_at * 1000);
          const diff = sd.resets_at - now;
          const label = diff < 24 * 3600
            ? formatTime(d)
            : `${WEEKDAYS[d.getDay()]}, ${formatTime(d)}`;
          resetParts.push(`\x1b[2mresets ${label}\x1b[0m`);

          // Pace: project weekly usage at current daily burn rate
          const WEEK_SEC = 7 * 24 * 3600;
          const elapsedSec = Math.max(0, WEEK_SEC - diff);
          if (elapsedSec > 3600) {
            const projected = sd.used_percentage * (WEEK_SEC / elapsedSec);
            let paceColor, arrow;
            if (projected < 95) { paceColor = '\x1b[32m'; arrow = '↓'; }
            else if (projected <= 105) { paceColor = '\x1b[33m'; arrow = '→'; }
            else { paceColor = '\x1b[31m'; arrow = '↑'; }
            limParts.push(`\x1b[2mpace:\x1b[0m ${paceColor}${arrow}\x1b[0m`);
          }
        }
      }

      if (limParts.length) output += '\n' + limParts.join(limSep);
      if (resetParts.length) output += '\n' + resetParts.join(limSep);
    }

    process.stdout.write(output);
  } catch (e) {
    // Silent fail - don't break statusline on parse errors
  }
});
