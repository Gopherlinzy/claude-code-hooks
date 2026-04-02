#!/usr/bin/env node
// select-modules.js — Interactive checkbox selector for hook modules
// Usage: node select-modules.js [--output file]
// Without --output: prints JSON to stdout (non-interactive or direct run)
// With --output: renders TUI to stdout, writes JSON to file (for $() avoidance)
// Controls: ↑↓/jk navigate, Space toggle, Enter confirm, a toggle all
'use strict';

const fs = require('fs');
const tty = require('tty');

const MODULES = [
  { key: 'stop',   label: 'Stop notification',    desc: 'Notify when Claude Code task completes', script: 'cc-stop-hook.sh', on: true },
  { key: 'safety', label: 'Safety gate (Bash)',    desc: 'Block dangerous bash commands',          script: 'cc-safety-gate.sh', on: true },
  { key: 'guard',  label: 'Large file guard',      desc: 'Prevent reading auto-generated/noise files', script: 'guard-large-files.sh', on: true },
  { key: 'notify', label: 'Wait notification',     desc: 'Notify on permission prompts & waits',  script: 'wait-notify.sh', on: true },
  { key: 'cancel', label: 'Cancel wait',           desc: 'Dismiss notification on user activity',  script: 'cancel-wait.sh', on: true },
];

// Parse --output argument
let outputFile = null;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === '--output' && process.argv[i + 1]) {
    outputFile = process.argv[i + 1];
    break;
  }
}

// ─── Setup I/O ───
// When --output is used: TUI renders to stdout normally, result goes to file
// When no --output: non-interactive fallback (output JSON to stdout)
let ttyIn, ttyOut;

if (outputFile) {
  // --output mode: stdout IS the terminal (install.sh runs us directly, not via $())
  ttyOut = process.stdout;

  // Input from /dev/tty or stdin
  if (process.stdin.isTTY) {
    ttyIn = process.stdin;
  } else {
    try {
      const fd = fs.openSync('/dev/tty', 'r');
      ttyIn = new tty.ReadStream(fd);
    } catch {
      // No TTY (Git Bash / CI / pipe) — show message and use defaults
      const defaults = MODULES.map(m => m.key);
      console.error('\x1b[33m⚠\x1b[0m  Terminal does not support interactive selection (no /dev/tty).');
      console.error('    All modules enabled by default: ' + defaults.join(', '));
      console.error('    Tip: Run inside Claude Code for a better install experience.');
      fs.writeFileSync(outputFile, JSON.stringify(defaults));
      process.exit(0);
    }
  }
} else {
  // No --output: just print defaults as JSON to stdout (non-interactive)
  console.log(JSON.stringify(MODULES.map(m => m.key)));
  process.exit(0);
}

let cursor = 0;
let totalLines = 0;

function render() {
  // Clear previous render by moving up and clearing
  if (totalLines > 0) {
    ttyOut.write(`\x1b[${totalLines}A`);  // Move up
    ttyOut.write('\x1b[J');                // Clear to end
  }

  const lines = [];
  lines.push('\x1b[90m  ↑↓ navigate  ␣ toggle  a all/none  Enter confirm\x1b[0m');
  lines.push('');
  for (let i = 0; i < MODULES.length; i++) {
    const m = MODULES[i];
    const pointer = i === cursor ? '\x1b[36m❯\x1b[0m' : ' ';
    const check = m.on ? '\x1b[32m✔\x1b[0m' : ' ';
    const label = i === cursor ? `\x1b[1m${m.label}\x1b[0m` : m.label;
    const desc = `\x1b[90m${m.desc}\x1b[0m`;
    lines.push(`  ${pointer} [${check}] ${label.padEnd(30)} ${desc}`);
  }

  const output = lines.join('\n') + '\n';
  ttyOut.write(output);
  totalLines = lines.length;
}

function finish() {
  ttyIn.setRawMode(false);
  ttyIn.pause();
  const enabled = MODULES.filter(m => m.on).map(m => m.key);
  // Visual confirmation
  ttyOut.write(`\n  \x1b[32m✔\x1b[0m Selected: ${enabled.join(', ') || 'none'}\n`);
  // Write result to file
  fs.writeFileSync(outputFile, JSON.stringify(enabled));
  // Clean up
  if (ttyIn !== process.stdin) try { ttyIn.destroy(); } catch {}
  process.exit(0);
}

ttyIn.setRawMode(true);
ttyIn.resume();
ttyIn.setEncoding('utf8');

render();

ttyIn.on('data', (key) => {
  if (key === '\x03') { // Ctrl+C
    ttyIn.setRawMode(false);
    if (ttyIn !== process.stdin) try { ttyIn.destroy(); } catch {}
    process.exit(130);
  }
  if (key === '\r' || key === '\n') { finish(); return; }
  if (key === ' ') { MODULES[cursor].on = !MODULES[cursor].on; render(); return; }
  if (key === 'a' || key === 'A') {
    const allOn = MODULES.every(m => m.on);
    MODULES.forEach(m => { m.on = !allOn; });
    render(); return;
  }
  if (key === '\x1b[A' || key === 'k') { cursor = (cursor - 1 + MODULES.length) % MODULES.length; render(); }
  else if (key === '\x1b[B' || key === 'j') { cursor = (cursor + 1) % MODULES.length; render(); }
});
