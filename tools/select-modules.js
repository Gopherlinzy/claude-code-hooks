#!/usr/bin/env node
// select-modules.js — Interactive checkbox selector for hook modules
// Usage: node select-modules.js
// Output: JSON array of enabled module keys to stdout
// Controls: ↑↓ navigate, Space toggle, Enter confirm, a toggle all
//
// TUI renders to /dev/tty (not stdout), so $() capture works correctly.
// On Windows Git Bash, /dev/tty maps to Console but ANSI may be limited.
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

// ─── Setup TTY I/O (separate from stdout so $() capture works) ───
let ttyIn, ttyOut;

// Output: TUI renders to /dev/tty, final JSON goes to stdout (process.stdout)
try {
  const ttyWfd = fs.openSync('/dev/tty', 'w');
  ttyOut = new tty.WriteStream(ttyWfd);
} catch {
  // Fallback: stderr if it's a TTY
  if (process.stderr.isTTY) {
    ttyOut = process.stderr;
  } else {
    // Truly headless — skip TUI, output all defaults
    console.log(JSON.stringify(MODULES.map(m => m.key)));
    process.exit(0);
  }
}

// Input: read keystrokes from /dev/tty (stdin may be pipe in curl|bash)
if (process.stdin.isTTY) {
  ttyIn = process.stdin;
} else {
  try {
    const ttyRfd = fs.openSync('/dev/tty', 'r');
    ttyIn = new tty.ReadStream(ttyRfd);
  } catch {
    // No TTY for input — output all defaults
    console.log(JSON.stringify(MODULES.map(m => m.key)));
    process.exit(0);
  }
}

let cursor = 0;

function render() {
  // Move cursor up to overwrite previous render (except first time)
  if (render._drawn) {
    ttyOut.write(`\x1b[${MODULES.length + 2}A`);
  }
  render._drawn = true;

  ttyOut.write('\x1b[2K\x1b[90m  ↑↓ navigate  ␣ toggle  a all/none  Enter confirm\x1b[0m\n');
  ttyOut.write('\x1b[2K\n');

  for (let i = 0; i < MODULES.length; i++) {
    const m = MODULES[i];
    const pointer = i === cursor ? '\x1b[36m❯\x1b[0m' : ' ';
    const check = m.on ? '\x1b[32m✔\x1b[0m' : ' ';
    const label = i === cursor ? `\x1b[1m${m.label}\x1b[0m` : m.label;
    const desc = `\x1b[90m${m.desc}\x1b[0m`;
    ttyOut.write(`\x1b[2K  ${pointer} [${check}] ${label.padEnd(30)} ${desc}\n`);
  }
}

function finish() {
  ttyIn.setRawMode(false);
  ttyIn.pause();
  const enabled = MODULES.filter(m => m.on).map(m => m.key);
  // Visual confirmation on ttyOut
  ttyOut.write(`\n  \x1b[32m✔\x1b[0m Selected: ${enabled.join(', ') || 'none'}\n\n`);
  // Clean up tty fds
  if (ttyOut !== process.stdout && ttyOut !== process.stderr) {
    try { ttyOut.end(); } catch {}
  }
  if (ttyIn !== process.stdin) {
    try { ttyIn.destroy(); } catch {}
  }
  // Output to stdout (not ttyOut) — this is what $() captures
  console.log(JSON.stringify(enabled));
  process.exit(0);
}

ttyIn.setRawMode(true);
ttyIn.resume();
ttyIn.setEncoding('utf8');

render();

ttyIn.on('data', (key) => {
  // Ctrl+C
  if (key === '\x03') {
    ttyIn.setRawMode(false);
    if (ttyIn !== process.stdin) try { ttyIn.destroy(); } catch {}
    process.exit(130);
  }

  // Enter
  if (key === '\r' || key === '\n') {
    finish();
    return;
  }

  // Space — toggle current
  if (key === ' ') {
    MODULES[cursor].on = !MODULES[cursor].on;
    render();
    return;
  }

  // 'a' — toggle all
  if (key === 'a' || key === 'A') {
    const allOn = MODULES.every(m => m.on);
    MODULES.forEach(m => { m.on = !allOn; });
    render();
    return;
  }

  // Arrow keys (escape sequences) + vi keys
  if (key === '\x1b[A' || key === 'k') { // Up
    cursor = (cursor - 1 + MODULES.length) % MODULES.length;
    render();
  } else if (key === '\x1b[B' || key === 'j') { // Down
    cursor = (cursor + 1) % MODULES.length;
    render();
  }
});
