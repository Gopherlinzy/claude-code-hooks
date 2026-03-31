---
name: claude-code-hooks
description: A collection of Claude Code hooks for task lifecycle management, security gates, wait-timeout notifications, and progress tracking. Includes stop notification, permission-request alerts, safety gates, large-file guards, task dispatch, orphan reaping, and skill index generation. Works with OpenClaw or any notification backend.
version: 1.2.0
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

### 🔔 `cc-stop-hook.sh` — Stop Hook (Task Completion Notification)
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
- **🆕 Git Worktree isolation** — auto-creates an isolated worktree per task in git repos, protecting against [Claude Code's silent `git reset --hard` bug](https://github.com/anthropics/claude-code/issues/40710)
- **🆕 Git safety assertion** — injects HEAD tracking instructions into Claude's prompt, detecting unexpected resets

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
Scans `~/.claude/scripts/claude-hooks/skills/*/SKILL.md` and generates a cached index for injection into Claude's system prompt.

**Features:**
- Lazy caching (only rebuilds when skills change)
- YAML frontmatter parsing
- Security: whitelist character filtering, 200-char truncation

## Quick Start

### Option A: One-Line Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
```

This will:
1. Clone the repo and copy scripts to `~/.claude/scripts/claude-hooks/`
2. Interactively configure your notification channel and target
3. Print the hooks config to add to `~/.claude/settings.json`

For non-interactive mode (CI/automation):
```bash
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash -s -- --non-interactive
```

### Option B: Manual Install

#### 1. Install scripts

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks && ./install.sh
```

Or manually:```bash
# Clone and copy scripts
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
```

#### 2. Configure notification target

```bash
# Create notify.conf (Claude Code hook subprocesses do NOT inherit ~/.zshrc env vars!)
cat > ~/.claude/scripts/claude-hooks/notify.conf << 'EOF'
# Notification target — set YOUR open_id / chat_id / user_id here
CC_NOTIFY_TARGET="YOUR_TARGET_ID"
CC_WAIT_NOTIFY_SECONDS=30
CC_NOTIFY_CHANNEL="feishu"
EOF
chmod 600 ~/.claude/scripts/claude-hooks/notify.conf
```

#### 3. Register hooks in `~/.claude/settings.json`

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/scripts/claude-hooks/cc-stop-hook.sh"
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
            "command": "~/.claude/scripts/claude-hooks/guard-large-files.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/scripts/claude-hooks/cc-safety-gate.sh",
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
            "command": "~/.claude/scripts/claude-hooks/wait-notify.sh",
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
            "command": "~/.claude/scripts/claude-hooks/wait-notify.sh",
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
            "command": "~/.claude/scripts/claude-hooks/cancel-wait.sh",
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
            "command": "~/.claude/scripts/claude-hooks/cancel-wait.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

#### 4. Restart Claude Code

New hooks are loaded when a new `claude` session starts. Existing sessions won't pick up changes.

## Configuration

### `notify.conf`

| Variable | Description | Default |
|----------|-------------|---------|
| `CC_NOTIFY_TARGET` | Notification target (Feishu open_id, chat_id, etc.) | _(required)_ |
| `CC_WAIT_NOTIFY_SECONDS` | Seconds before sending wait-timeout alert | `30` |
| `CC_NOTIFY_CHANNEL` | Notification channel (`feishu`, `telegram`, etc.) | `feishu` |
| `CC_GATEWAY_PORT` | OpenClaw gateway port (skip wake call if unset) | _(unset)_ |

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
  └── Stop ─────────────── cc-stop-hook.sh → .done file + notification
```

## Notification Backend

All hooks use a **universal notification dispatcher** (`send-notification.sh`) that supports 7 backends out of the box. **No OpenClaw required** — pick whichever you already use:

| Backend | Config Variable | Example |
|---------|----------------|---------|
| **Auto** | `CC_NOTIFY_BACKEND=auto` | Detects first available backend |
| **OpenClaw** | `CC_NOTIFY_TARGET` | Feishu / Telegram / any OpenClaw channel |
| **Slack** | `CC_SLACK_WEBHOOK_URL` | Slack Incoming Webhook |
| **Telegram** | `CC_TELEGRAM_BOT_TOKEN` + `CC_TELEGRAM_CHAT_ID` | Telegram Bot API |
| **Discord** | `CC_DISCORD_WEBHOOK_URL` | Discord Webhook |
| **Bark** | `CC_BARK_URL` | iOS push via [Bark](https://github.com/Finb/Bark) |
| **Webhook** | `CC_WEBHOOK_URL` | Any HTTP endpoint (customizable method/body) |
| **Command** | `CC_NOTIFY_COMMAND` | Any CLI tool (message via $1 + stdin) |

Set `CC_NOTIFY_BACKEND=auto` (default) and the dispatcher auto-detects the first configured backend.

Example for Slack:
```bash
# notify.conf
CC_NOTIFY_BACKEND="slack"
CC_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

Example for Telegram:
```bash
# notify.conf
CC_NOTIFY_BACKEND="telegram"
CC_TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
CC_TELEGRAM_CHAT_ID="987654321"
```

See `scripts/notify.conf.example` for all options.

## Comparison with Claude Code `--channels`

Claude Code 2.1.80+ includes a `--channels` feature (research preview) that allows MCP servers to push messages into your session and relay permission approvals to your phone via claude.ai.

| Feature | CC `--channels` | These Hooks |
|---------|----------------|-------------|
| **Status** | Research preview | Production-ready |
| **Notification channels** | claude.ai mobile only | Feishu / Telegram / Slack / any |
| **Permission approval** | ✅ Approve from phone | Notification only (approve in terminal) |
| **Task completion alerts** | ❌ | ✅ |
| **Security gates** | ❌ | ✅ Dangerous command blocking |
| **Large file guards** | ❌ | ✅ Auto-generated file filtering |
| **Progress tracking** | ❌ | ✅ |
| **Orphan cleanup** | ❌ | ✅ |
| **Dependencies** | MCP server + claude.ai account | bash + jq only |

**TL;DR:** No conflict. `--channels` solves "approve from phone". These hooks are a full task lifecycle toolkit. They can run side by side.

## Phase 1 Hardening (v1.1)

All hooks have been hardened with the following improvements:

### Explicit Fail-Open
Every hook declares `# FAIL_MODE=open` — if a hook itself crashes, it silently passes through instead of blocking Claude Code. No more silent failures swallowed by `|| true` with zero record.

### JSONL Structured Audit Log
All hooks now write structured audit events to `~/.claude/scripts/claude-hooks/logs/hooks-audit.jsonl`:
```json
{"ts":"2026-03-30T01:00:00+08:00","hook":"cc-safety-gate","action":"deny","rule":"rm -rf /","cmd":"rm -rf /tmp"}
```
Uses `jq -nc` when available, falls back to `printf` formatting. The `_log_jsonl()` function is itself fail-safe (`2>/dev/null || true`).

### Externalized Safety Rules
`cc-safety-gate.sh` now supports loading custom rules from `safety-rules.conf`:
```bash
cp scripts/safety-rules.conf.example scripts/safety-rules.conf
# Edit to add/remove blacklist patterns and protected paths
```
Built-in defaults are **always preserved** — external config only overrides, never replaces. If the config file is missing or unreadable, the built-in rules remain active.

### Dynamic Gateway Port
`cc-stop-hook.sh` no longer has a hardcoded gateway port. Set `CC_GATEWAY_PORT` in `notify.conf` — if unset, the gateway wake call is skipped entirely.

### Async Dispatch Quote Fix
`dispatch-claude.sh` now writes prompts to a `mktemp` temporary file instead of embedding them in `nohup bash -c '...'`, eliminating quote-escaping bugs. Temporary files are cleaned up via `trap EXIT`.

## Dependencies

### Required

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `bash` | 4.0+ | All hook scripts (macOS ships with bash 3.2 — install via `brew install bash`) |
| `curl` | any | Notification delivery (Feishu, WeCom, Slack, Telegram, Discord, Bark, webhook) |
| `python3` | 3.6+ | JSON escaping in notification backends and `dispatch-claude.sh` |
| Claude Code CLI | latest | `claude` command — the hooks are designed for Claude Code |

### Recommended

| Dependency | Purpose |
|-----------|---------|
| `jq` | JSON parsing in hooks (gracefully degrades to `printf` fallback if missing) |
| `openssl` | HMAC-SHA256 signing for Feishu webhook (only needed if `NOTIFY_FEISHU_SECRET` is set) |
| `git` | Worktree isolation in `dispatch-claude.sh` (non-git dirs unaffected) |

### Optional

| Dependency | Purpose |
|-----------|---------|
| `openclaw` CLI | Only needed if using `openclaw` as notification backend |

### Platform Notes

- **macOS**: Default bash is 3.2 (GPLv2). Install bash 4+ via `brew install bash`. Other deps (`curl`, `python3`, `git`, `openssl`) are pre-installed.
- **Linux (Ubuntu/Debian)**: All required deps available via `apt`. `bash` 4+ is default.
- **Windows (WSL)**: Fully supported under WSL2 with Ubuntu.

## Changelog

### v1.2.0 (2026-03-31)

**🌍 Feishu & WeCom Webhook + Full Decoupling from OpenClaw**

Phase 1 — New notification backends:
- Added `_notify_feishu()` — Feishu (飞书) custom bot webhook with optional HMAC-SHA256 signing
- Added `_notify_wecom()` — WeCom (企业微信) group bot webhook (zero auth)
- Auto-detection priority: `openclaw → feishu → wecom → slack → telegram → discord → bark → webhook → command`
- Total supported backends: **9** (up from 7)

Phase 2 — OpenClaw decoupling:
- Renamed `notify-openclaw.sh` → `cc-stop-hook.sh` (git history preserved)
- All paths neutralized: `/tmp/openclaw-hooks/` → `/tmp/cchooks/`, `~/.openclaw/` → `~/.cchooks/`
- Fixed pre-existing bug: `HOOK_DIR` used `~` inside double quotes (tilde doesn't expand — changed to `${HOME}`)
- `generate-skill-index.sh` now uses `CC_SKILLS_DIR` env var with fallback
- `install.sh` updated to use `~/.cchooks/` paths
- Project now runs completely standalone — no OpenClaw dependency required

Phase 3 — User experience:
- First-run hint: when no notification backend is configured, a one-shot stderr message guides setup
- `install.sh` now prints post-install configuration guide with Feishu/WeCom/Slack one-liner commands

### v1.1.0 (2026-03-30)

**🛡️ Git Worktree Isolation (P0 Security)**

Addresses [Claude Code issue #40710](https://github.com/anthropics/claude-code/issues/40710) — Claude Code CLI may silently execute `git reset --hard origin/main` every ~10 minutes via internal `libgit2` calls, destroying uncommitted changes.

- `dispatch-claude.sh`: Auto-detects git repos and creates isolated worktrees (`git worktree add .worktrees/wt-{task_id} HEAD`)
- Graceful degradation: if worktree creation fails, falls back to original working directory
- Auto-appends `.worktrees/` to `.gitignore` to prevent tracking worktree contents
- Git safety assertion injected into Claude's prompt: tracks HEAD before/after each step, flags `⚠️ GIT_RESET_DETECTED` on unexpected resets
- Non-git directories are completely unaffected

### v1.0.0 (2026-03-29)

Initial release with full hook suite.

## License

MIT
