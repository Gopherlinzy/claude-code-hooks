---
name: claude-code-hooks
description: A collection of Claude Code hooks for task lifecycle management, security gates, wait-timeout notifications, and progress tracking. Includes stop notification, permission-request alerts, safety gates, large-file guards, task dispatch, orphan reaping, and skill index generation. Works with OpenClaw or any notification backend.
version: 1.3.0
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
Fires when Claude Code finishes a task. Writes a `.done` JSON file, sends a notification via configured backends, and optionally wakes a local gateway.

**Features:**
- Deduplication lock (60s TTL) prevents duplicate notifications
- Session name detection from Claude's session files
- Audit logging
- Configurable notification channels and targets

### ⏰ `wait-notify.sh` — PermissionRequest / Notification Hook
When Claude asks for permission (or triggers a notification) and you don't respond within N seconds, sends a reminder notification.

**Features:**
- Background timer (non-blocking, won't stall Claude)
- 60-second deduplication (no spam from rapid permission requests)
- Marker-file-based cancellation (if you respond, the timer is cancelled)
- Configurable timeout, channel, and target via `notify.conf`

### 🛑 `cancel-wait.sh` — PostToolUse / UserPromptSubmit Hook
Cancels pending wait-timeout notifications when you respond. Paired with `wait-notify.sh`.

**Features:**
- Grace period (5s) — prevents premature cancellation when PermissionRequest and PostToolUse fire near-simultaneously

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
- **Git Worktree isolation** — auto-creates an isolated worktree per task in git repos, protecting against [Claude Code's silent `git reset --hard` bug](https://github.com/anthropics/claude-code/issues/40710)
- **Git safety assertion** — injects HEAD tracking instructions into Claude's prompt, detecting unexpected resets

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

Or manually:
```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
```

#### 2. Configure notification backends

```bash
# Create notify.conf (Claude Code hook subprocesses do NOT inherit ~/.zshrc env vars!)
cat > ~/.claude/scripts/claude-hooks/notify.conf << 'EOF'
# auto = discover all configured backends, broadcast to all
CC_NOTIFY_BACKEND=auto
CC_WAIT_NOTIFY_SECONDS=30

# --- Enable one or more backends below ---
# Feishu:
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN

# Slack:
# CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK

# Bark (iOS):
# CC_BARK_URL=https://api.day.app/YOUR_KEY
EOF
chmod 600 ~/.claude/scripts/claude-hooks/notify.conf
```

#### 3. Register hooks in `~/.claude/settings.json`

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/scripts/claude-hooks/cc-stop-hook.sh",
            "timeout": 10
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

> **Note:** All matchers use `"*"` (match all). Use specific patterns like `"Bash"` or `"Read|Edit|Write"` only for targeted hooks. Empty string `""` should be avoided — its behavior is undefined and may prevent hooks from firing.

#### 4. Restart Claude Code

New hooks are loaded when a new `claude` session starts. Existing sessions won't pick up changes.

## Configuration

### `notify.conf`

| Variable | Description | Default |
|----------|-------------|---------|
| `CC_NOTIFY_BACKEND` | Backend selection (see below) | `auto` |
| `CC_WAIT_NOTIFY_SECONDS` | Seconds before sending wait-timeout alert | `30` |
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
  ├── Notification ─────── wait-notify.sh → [30s timer] → notification
  │
  ├── PostToolUse ──────── cancel-wait.sh → [cancel timer]
  │
  ├── UserPromptSubmit ─── cancel-wait.sh → [cancel timer]
  │
  └── Stop ─────────────── cc-stop-hook.sh → .done file + notification
```

## Notification Backend

All hooks use a **universal notification dispatcher** (`send-notification.sh`) that supports **9 backends** and **broadcasts to all configured channels simultaneously**.

| Backend | Config Variable | Example |
|---------|----------------|---------|
| **Auto** | `CC_NOTIFY_BACKEND=auto` | Discover all configured backends, broadcast to all |
| **OpenClaw** | `CC_NOTIFY_TARGET` | Feishu / Telegram / any OpenClaw channel |
| **Feishu** | `NOTIFY_FEISHU_URL` | Feishu custom bot webhook (optional HMAC signing) |
| **WeCom** | `NOTIFY_WECOM_URL` | WeCom (企业微信) group bot webhook |
| **Slack** | `CC_SLACK_WEBHOOK_URL` | Slack Incoming Webhook |
| **Telegram** | `CC_TELEGRAM_BOT_TOKEN` + `CC_TELEGRAM_CHAT_ID` | Telegram Bot API |
| **Discord** | `CC_DISCORD_WEBHOOK_URL` | Discord Webhook |
| **Bark** | `CC_BARK_URL` | iOS push via [Bark](https://github.com/Finb/Bark) |
| **Webhook** | `CC_WEBHOOK_URL` | Any HTTP endpoint (customizable method/body) |
| **Command** | `CC_NOTIFY_COMMAND` | Any CLI tool (message via $1 + stdin) |

### Broadcast Mode (v1.3.0+)

By default (`CC_NOTIFY_BACKEND=auto`), the dispatcher **discovers all configured backends** and **broadcasts to every one of them**. Each backend fires independently — if one fails, the others still deliver.

```bash
# Example: notify.conf — broadcasts to both Feishu AND Bark simultaneously
CC_NOTIFY_BACKEND=auto
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
CC_BARK_URL=https://api.day.app/YOUR_KEY
# → Both Feishu and Bark receive every notification
```

You can also explicitly control which backends fire:

```bash
# Explicit list — only these two, in broadcast mode
CC_NOTIFY_BACKEND=feishu,bark

# Single backend — backward-compatible
CC_NOTIFY_BACKEND=feishu
```

### Backend Examples

**Feishu (飞书):**
```bash
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
NOTIFY_FEISHU_SECRET=your_sign_secret  # optional, for signed webhooks
```

**Slack:**
```bash
CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
```

**Telegram:**
```bash
CC_TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
CC_TELEGRAM_CHAT_ID=987654321
```

**Bark (iOS push):**
```bash
CC_BARK_URL=https://api.day.app/YOUR_KEY
CC_BARK_TITLE="Claude Code"  # optional
```

See `scripts/notify.conf.example` for all options.

## Comparison with Claude Code `--channels`

Claude Code 2.1.80+ includes a `--channels` feature (research preview) that allows MCP servers to push messages into your session and relay permission approvals to your phone via claude.ai.

| Feature | CC `--channels` | These Hooks |
|---------|----------------|-------------|
| **Status** | Research preview | Production-ready |
| **Notification channels** | claude.ai mobile only | Feishu / Slack / Telegram / any |
| **Multi-channel broadcast** | ❌ | ✅ All configured backends fire simultaneously |
| **Permission approval** | ✅ Approve from phone | Notification only (approve in terminal) |
| **Task completion alerts** | ❌ | ✅ |
| **Security gates** | ❌ | ✅ Dangerous command blocking |
| **Large file guards** | ❌ | ✅ Auto-generated file filtering |
| **Progress tracking** | ❌ | ✅ |
| **Orphan cleanup** | ❌ | ✅ |
| **Dependencies** | MCP server + claude.ai account | bash + jq only |

**TL;DR:** No conflict. `--channels` solves "approve from phone". These hooks are a full task lifecycle toolkit. They can run side by side.

## Hardening Notes

### Explicit Fail-Open
Every hook declares `# FAIL_MODE=open` — if a hook itself crashes, it silently passes through instead of blocking Claude Code.

### JSONL Structured Audit Log
All hooks write structured audit events to `~/.cchooks/logs/hooks-audit.jsonl`:
```json
{"ts":"2026-03-30T01:00:00+08:00","hook":"cc-safety-gate","action":"deny","rule":"rm -rf /","cmd":"rm -rf /tmp"}
```

### Externalized Safety Rules
`cc-safety-gate.sh` supports loading custom rules from `safety-rules.conf`. Built-in defaults are always preserved — external config only overrides, never replaces.

### Dynamic Gateway Port
Set `CC_GATEWAY_PORT` in `notify.conf` — if unset, the gateway wake call is skipped entirely.

### Async Dispatch Quote Fix
`dispatch-claude.sh` writes prompts to a `mktemp` temporary file instead of embedding them in `nohup bash -c '...'`, eliminating quote-escaping bugs.

## Dependencies

### Required

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `bash` | 4.0+ | All hook scripts (macOS ships with bash 3.2 — install via `brew install bash`) |
| `curl` | any | Notification delivery |
| `python3` | 3.6+ | JSON escaping in notification backends |
| Claude Code CLI | latest | `claude` command |

### Recommended

| Dependency | Purpose |
|-----------|---------|
| `jq` | JSON parsing (gracefully degrades if missing) |
| `openssl` | HMAC-SHA256 signing for Feishu webhook |
| `git` | Worktree isolation in `dispatch-claude.sh` |

### Platform Notes

- **macOS**: Default bash is 3.2 (GPLv2). Install bash 4+ via `brew install bash`. Other deps pre-installed.
- **Linux (Ubuntu/Debian)**: All deps available via `apt`. `bash` 4+ is default.
- **Windows (WSL)**: Fully supported under WSL2 with Ubuntu.

## Platform Installation Guides

### 🍎 macOS

```bash
# 1. Check bash version (need 4.0+)
bash --version
brew install bash  # if needed

# 2. Install hooks
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash

# 3. Configure backends
echo 'NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN' >> ~/.claude/scripts/claude-hooks/notify.conf

# 4. Test
~/.claude/scripts/claude-hooks/send-notification.sh "Hello from macOS!"
```

### 🪟 Windows (WSL2)

```bash
# Inside WSL2 Ubuntu:
sudo apt-get install -y jq python3 curl openssl
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
echo 'NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN' >> ~/.claude/scripts/claude-hooks/notify.conf
~/.claude/scripts/claude-hooks/send-notification.sh "Hello from WSL2!"
```

## Changelog

### v1.3.0 (2026-03-31)

**📡 Broadcast Mode — Multi-Channel Simultaneous Notifications**

- **`send-notification.sh` v2**: Complete rewrite of backend selection logic
  - `auto` mode now discovers **all** configured backends and broadcasts to every one of them simultaneously
  - Each backend fires independently — one failure doesn't block others
  - Supports comma-separated explicit lists: `CC_NOTIFY_BACKEND=feishu,slack,bark`
  - Single backend still works for backward compatibility
  - All backend functions now return proper exit codes instead of `|| true` swallowing errors
  - Warning messages on per-backend failures (visible in stderr, won't block Claude Code)

- **`cancel-wait.sh`**: Added 5-second grace period to prevent premature cancellation when PermissionRequest and PostToolUse events fire near-simultaneously

- **`wait-notify.sh`**: Removed hardcoded `exit 0` that was silently killing all Notification events. Notification hook now works correctly with `matcher: "*"`.

- **`notify.conf.example`**: Updated with broadcast mode documentation and all 9 backend examples

- **`settings.json` fixes applied in this release**:
  - `Stop` hook: Now correctly registers `cc-stop-hook.sh` (was missing — only a no-op SUPERSET command was registered)
  - `Notification` matcher: `""` → `"*"` (empty string prevented hook from firing)
  - Removed all dead SUPERSET_HOME_DIR commands (5 instances across 4 events)
  - Removed `/tmp/debug-*.sh` references (security risk — writable by any local user)
  - `PermissionRequest`: Debug wrapper replaced with `wait-notify.sh` for timeout notifications

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
- `install.sh` now prints post-install configuration guide

### v1.1.0 (2026-03-30)

**🛡️ Git Worktree Isolation (P0 Security)**

Addresses [Claude Code issue #40710](https://github.com/anthropics/claude-code/issues/40710).

- `dispatch-claude.sh`: Auto-detects git repos and creates isolated worktrees
- Graceful degradation: falls back to original working directory if worktree creation fails
- Git safety assertion injected into Claude's prompt
- Non-git directories completely unaffected

### v1.0.0 (2026-03-29)

Initial release with full hook suite.

## License

MIT
