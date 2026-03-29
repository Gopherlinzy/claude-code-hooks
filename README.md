---
name: claude-code-hooks
description: A collection of Claude Code hooks for task lifecycle management, security gates, wait-timeout notifications, and progress tracking. Includes stop notification, permission-request alerts, safety gates, large-file guards, task dispatch, orphan reaping, and skill index generation. Works with OpenClaw or any notification backend.
version: 1.0.0
---

# Claude Code Hooks — Task Lifecycle & Security Toolkit

A production-ready collection of Claude Code hooks that transform Claude Code from a bare CLI into a managed, observable, and secure development environment.

## What This Solves

When running Claude Code for long tasks, you face these problems:
1. **Silent completion** — Tasks finish but you don't know unless watching the terminal
2. **Permission stalls** — Claude asks for permission, you walk away, it waits forever
3. **Dangerous commands** — No guardrails against `rm -rf /` or writing to protected files
4. **Large file waste** — Claude reads 10,000-line generated files, burning context window
5. **Orphan processes** — Async tasks hang forever with no cleanup
6. **No progress visibility** — Black box execution with no way to check status mid-task

## Hooks Included

### 🔔 `notify-openclaw.sh` — Stop Hook (Task Completion Notification)
Fires when Claude Code finishes a task. Writes a `.done` JSON file, sends a notification via `openclaw message send` (configurable), and optionally wakes a local gateway.

**Features:**
- Deduplication lock (60s TTL) prevents duplicate notifications
- Session name detection from Claude's session files
- Audit logging
- Configurable notification channel and target

### ⏰ `wait-notify.sh` — PermissionRequest / Notification Hook
When Claude asks for permission and you don't respond within N seconds, sends a reminder notification.

**Features:**
- Background timer (non-blocking, won't stall Claude)
- 60-second deduplication (no spam from rapid permission requests)
- Marker-file-based cancellation (if you respond, the timer is cancelled)
- Configurable timeout, channel, and target via `notify.conf`

### 🛑 `cancel-wait.sh` — PostToolUse / UserPromptSubmit Hook
Cancels pending wait-timeout notifications when you respond. Paired with `wait-notify.sh`.

### 🛡️ `cc-safety-gate.sh` — PreToolUse Hook (Bash Command Safety Gate)
Blocks dangerous Bash commands before execution.

**Blocked patterns:**
- `rm -rf /`, `rm -rf ~`, `sudo`, `chmod 777`
- Pipe-to-shell: `curl ... | sh`, `wget ... | sh`
- Destructive: `mkfs`, `dd if=`, `> /etc/`

**Protected paths:**
- `.ssh`, `SOUL.md`, `IDENTITY.md`, `USER.md`, `/etc/`, `/System/`

### 📏 `guard-large-files.sh` — PreToolUse Hook (File Size & Noise Guard)
Prevents Claude from reading auto-generated files, noise directories, and oversized files.

**Blocks:**
- Generated files: `*_gen.go`, `*.pb.go`, `*.min.js`, `*.min.css`
- Noise directories: `vendor/`, `node_modules/`, `dist/`, `.git/`
- Files > 1000 lines: warns instead of blocking

### 🚀 `dispatch-claude.sh` — Task Dispatch Wrapper
Wraps `claude --print` with lifecycle management for both sync and async execution.

**Features:**
- Environment sanitization (strips sensitive env vars)
- Auto-generated `.claudeignore` for noise filtering
- Progress tracking injection (`.claude-progress.md`)
- Skill index auto-loading
- Async mode with nohup/disown + timeout
- Task metadata files for external monitoring

### 📊 `check-claude-status.sh` — Task Status Checker
Queries the current state of a dispatched Claude Code task.

**Status values:** `not-dispatched` | `running` | `running-no-progress` | `completed` | `dead` | `unknown`

### 🧹 `reap-orphans.sh` — Orphan Process Cleaner
Scans for timed-out Claude Code processes and terminates them safely.

**Safety features:**
- PID reuse protection (verifies process command contains "claude")
- Skips already-completed tasks (`.done` file exists)
- Configurable timeout via `REAP_TIMEOUT` env var (default: 30 minutes)

### 📚 `generate-skill-index.sh` — Skills Index Generator
Scans `~/.openclaw/skills/*/SKILL.md` and generates a cached index for injection into Claude's system prompt.

**Features:**
- Lazy caching (only rebuilds when skills change)
- YAML frontmatter parsing
- Security: whitelist character filtering, 200-char truncation

## Quick Start

### 1. Install scripts

```bash
# Clone and copy scripts
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.openclaw/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.openclaw/scripts/claude-hooks/
chmod +x ~/.openclaw/scripts/claude-hooks/*.sh
```

### 2. Configure notification target

```bash
# Create notify.conf (Claude Code hook subprocesses do NOT inherit ~/.zshrc env vars!)
cat > ~/.openclaw/scripts/claude-hooks/notify.conf << 'EOF'
# Notification target — set YOUR open_id / chat_id / user_id here
CC_NOTIFY_TARGET="YOUR_TARGET_ID"
CC_WAIT_NOTIFY_SECONDS=30
CC_NOTIFY_CHANNEL="feishu"
EOF
chmod 600 ~/.openclaw/scripts/claude-hooks/notify.conf
```

### 3. Register hooks in `~/.claude/settings.json`

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.openclaw/scripts/claude-hooks/notify-openclaw.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "~/.openclaw/scripts/claude-hooks/guard-large-files.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.openclaw/scripts/claude-hooks/cc-safety-gate.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.openclaw/scripts/claude-hooks/wait-notify.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.openclaw/scripts/claude-hooks/wait-notify.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.openclaw/scripts/claude-hooks/cancel-wait.sh",
            "timeout": 3
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.openclaw/scripts/claude-hooks/cancel-wait.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

### 4. Restart Claude Code

New hooks are loaded when a new `claude` session starts. Existing sessions won't pick up changes.

## Configuration

### `notify.conf`

| Variable | Description | Default |
|----------|-------------|---------|
| `CC_NOTIFY_TARGET` | Notification target (Feishu open_id, chat_id, etc.) | _(required)_ |
| `CC_WAIT_NOTIFY_SECONDS` | Seconds before sending wait-timeout alert | `30` |
| `CC_NOTIFY_CHANNEL` | Notification channel (`feishu`, `telegram`, etc.) | `feishu` |

### Environment Variables

| Variable | Used By | Description |
|----------|---------|-------------|
| `REAP_TIMEOUT` | `reap-orphans.sh` | Orphan timeout in seconds (default: 1800) |

## Architecture

```
Claude Code Session
  │
  ├── PreToolUse ─────┬── cc-safety-gate.sh (Bash commands)
  │                   └── guard-large-files.sh (Read/Edit/Write)
  │
  ├── PermissionRequest ── wait-notify.sh → [30s timer] → notification
  │
  ├── PostToolUse ──────── cancel-wait.sh → [cancel timer]
  │
  ├── UserPromptSubmit ─── cancel-wait.sh → [cancel timer]
  │
  └── Stop ─────────────── notify-openclaw.sh → .done file + notification
```

## Notification Backend

These hooks use `openclaw message send` for notifications. To use a different backend, modify the notification commands in `notify-openclaw.sh` and `wait-notify.sh`.

**Alternatives:**
- Slack: Replace with `curl` to Slack webhook
- Telegram: Replace with Telegram Bot API call
- Discord: Replace with Discord webhook
- Email: Replace with `sendmail` or similar
- Custom: Any command that accepts a message string

## Dependencies

- `bash` 4+
- `jq` (for JSON parsing; gracefully degrades if missing)
- `python3` (for `dispatch-claude.sh` JSON encoding)
- `openclaw` CLI (for notifications; replaceable)
- Claude Code CLI (`claude`)

## License

MIT
