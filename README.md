---
name: claude-code-hooks
description: Production-ready Claude Code hooks for task lifecycle, security gates, and multi-channel notifications.
version: 2.0.0
---

# Claude Code Hooks

A production-ready collection of [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) that transform Claude Code from a bare CLI into a managed, observable, and secure development environment.

## What This Solves

| Problem | Solution |
|---------|----------|
| **Silent completion** — Tasks finish, you don't know | 🔔 Stop hook → push notification |
| **Permission stalls** — Claude waits, you're away | ⏰ Wait-timeout → alert after 30s |
| **Dangerous commands** — No guardrails against `rm -rf /` | 🛡️ Safety gate → auto-block |
| **Large file waste** — Reads 10k-line generated files | 📏 File guard → deny noisy reads |
| **Orphan processes** — Async tasks hang forever | 🧹 Reaper → auto-cleanup |
| **No progress visibility** — Black box execution | 📊 Dispatch → progress tracking |

## Quick Start

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
```

> 🇨🇳 **China / Slow GitHub?** Use mirror:
> ```bash
> curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
> ```

The installer walks you through **6 steps**:

```
[1/6] Checking environment...        ← Verifies bash, node, curl, python3
[2/6] Installing hook scripts...     ← Clones repo → copies scripts
[3/6] Select hook modules...         ← Interactive TUI checkbox selector
[4/6] Injecting hooks into settings  ← Deep-merges into settings.json (non-destructive)
[5/6] Configure notifications...     ← Set up Feishu / Slack / Telegram / etc.
[6/6] Verifying installation...      ← Validates all scripts + permissions
```

**Module selector** (Step 3):

```
  ↑↓ navigate  ␣ toggle  a all/none  Enter confirm

  ❯ [✔] Stop notification     Notify when Claude Code task completes
    [✔] Safety gate (Bash)    Block dangerous bash commands
    [✔] Large file guard      Prevent reading auto-generated/noise files
    [✔] Wait notification     Notify on permission prompts & waits
    [✔] Cancel wait           Dismiss notification on user activity
```

**Key features of the installer:**
- 🔀 **Deep merge** — preserves your existing `settings.json` hooks (won't overwrite custom rules)
- 🔒 **Atomic writes** — tmp → validate → mv (no corruption on crash/Ctrl+C)
- 📋 **Diff preview** — shows exact changes before modifying settings.json
- 🔄 **Rollback** — auto-restores backup on failure

### Installer Commands

```bash
./install.sh                  # Interactive install (default)
./install.sh --non-interactive  # CI/automation mode (all defaults)
./install.sh --status         # Show current installation status
./install.sh --update         # Update scripts only, keep config
./install.sh --uninstall      # Remove hooks from settings.json
./install.sh --uninstall --purge  # Full removal including notify.conf
```

### Alternative: Manual Install

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks && ./install.sh
```

Or fully manual (no installer):
```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
# Then manually edit ~/.claude/settings.json — see "Hook Registration" below
```

## Platform Support

### 🍎 macOS

Works out of the box. One caveat: macOS ships bash 3.2, but hooks need 4.0+.

```bash
bash --version           # Check — if < 4.0:
brew install bash        # Upgrade
```

### 🐧 Linux

```bash
sudo apt-get install -y bash curl python3 jq   # Debian/Ubuntu
# Then run the one-liner install above
```

### 🪟 Windows

**WSL2 (Recommended):** Full functionality, works like native Linux.

```powershell
wsl --install -d Ubuntu   # PowerShell (Admin)
```
```bash
# Inside WSL2:
sudo apt-get install -y nodejs jq python3 curl
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
```

**Git Bash (Limited):** Hooks work, but background timers and orphan reaping are less reliable.

```bash
# In Git Bash:
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks && ./install.sh
```

> **Git Bash notes:**
> - No `jq` needed — all scripts auto-fallback to Python for JSON parsing
> - Use Windows-style paths in settings.json: `bash /c/Users/USERNAME/.claude/scripts/claude-hooks/cc-stop-hook.sh`
> - Background timers (`wait-notify.sh`) may be unreliable if Git Bash window is closed
> - For full task lifecycle management, use WSL2

## Post-Install Configuration

### 1. Configure Notification Backend

```bash
# Edit notify.conf (hook subprocesses do NOT inherit ~/.zshrc env vars!)
vim ~/.claude/scripts/claude-hooks/notify.conf
```

```bash
CC_NOTIFY_BACKEND=auto          # Discover all backends, broadcast to all
CC_WAIT_NOTIFY_SECONDS=30       # Seconds before wait-timeout alert

# Enable one or more backends:
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
# CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
# CC_BARK_URL=https://api.day.app/YOUR_KEY
# CC_TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
# CC_TELEGRAM_CHAT_ID=987654321
```

### 2. Test

```bash
~/.claude/scripts/claude-hooks/send-notification.sh "Hello from Claude Code Hooks!"
```

### 3. Restart Claude Code

New hooks load when a new `claude` session starts. Existing sessions won't pick up changes.

## Hooks Reference

### Core Hooks

| Hook | Event | What It Does |
|------|-------|-------------|
| 🔔 **cc-stop-hook.sh** | `Stop` | Sends notification on task completion. Dedup lock (60s TTL), session name detection, audit log. |
| ⏰ **wait-notify.sh** | `PermissionRequest` `Notification` | Background timer — if you don't respond in N seconds, sends an alert. Non-blocking. |
| 🛑 **cancel-wait.sh** | `PostToolUse` `UserPromptSubmit` | Cancels pending wait-timeout when you respond. 5s grace period prevents false cancellation. |
| 🛡️ **cc-safety-gate.sh** | `PreToolUse` (Bash) | Blocks dangerous commands: `rm -rf /`, `sudo`, `chmod 777`, pipe-to-shell, etc. |
| 📏 **guard-large-files.sh** | `PreToolUse` (Read/Edit/Write) | Blocks auto-generated files (`*.pb.go`, `*.min.js`), noise dirs (`node_modules/`, `vendor/`), files >1000 lines. |

### Extended Hooks

| Hook | What It Does |
|------|-------------|
| 🚀 **dispatch-claude.sh** | Task dispatch wrapper with git worktree isolation, progress tracking, env sanitization. |
| 📊 **check-claude-status.sh** | Query dispatched task status: `running` / `completed` / `dead` / `unknown`. |
| 🧹 **reap-orphans.sh** | Scans for timed-out Claude processes and terminates them safely (PID reuse protection). |
| 📚 **generate-skill-index.sh** | Generates skill index from `skills/*/SKILL.md` for system prompt injection. |

## Hook Registration

The installer auto-generates this in `settings.json`. For manual setup:

```json
{
  "hooks": {
    "Stop": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cc-stop-hook.sh", "timeout": 10 }] }
    ],
    "PreToolUse": [
      { "matcher": "Read|Edit|Write", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/guard-large-files.sh", "timeout": 5 }] },
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cc-safety-gate.sh", "timeout": 5 }] }
    ],
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/wait-notify.sh", "timeout": 5 }] }
    ],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/wait-notify.sh", "timeout": 5 }] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cancel-wait.sh", "timeout": 3 }] }
    ],
    "UserPromptSubmit": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cancel-wait.sh", "timeout": 3 }] }
    ]
  }
}
```

> **Tip:** Set Notification matcher to `"permission_prompt"` (not `"*"`). Using `"*"` also matches `idle_prompt`, which fires after task completion and causes false "waiting for action" alerts.

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
  │   (permission_prompt)
  │
  ├── PostToolUse ──────── cancel-wait.sh → [cancel timer]
  │
  ├── UserPromptSubmit ─── cancel-wait.sh → [cancel timer]
  │
  └── Stop ─────────────── cc-stop-hook.sh → .done file + notification
```

## Notification Backends

**9 backends** with auto-discovery broadcast. Configure in `notify.conf`:

| Backend | Config Variable | Protocol |
|---------|----------------|----------|
| **Auto** | `CC_NOTIFY_BACKEND=auto` | Discover all configured, broadcast to all |
| **Feishu** | `NOTIFY_FEISHU_URL` | Webhook (optional HMAC signing) |
| **WeCom** | `NOTIFY_WECOM_URL` | 企业微信 group bot webhook |
| **Slack** | `CC_SLACK_WEBHOOK_URL` | Incoming Webhook |
| **Telegram** | `CC_TELEGRAM_BOT_TOKEN` + `CC_TELEGRAM_CHAT_ID` | Bot API |
| **Discord** | `CC_DISCORD_WEBHOOK_URL` | Discord Webhook |
| **Bark** | `CC_BARK_URL` | iOS push ([Bark](https://github.com/Finb/Bark)) |
| **Webhook** | `CC_WEBHOOK_URL` | Any HTTP endpoint |
| **Command** | `CC_NOTIFY_COMMAND` | Any CLI tool (message via $1) |
| **OpenClaw** | `CC_NOTIFY_TARGET` | Feishu / Telegram / any OpenClaw channel |

**Broadcast mode** (default): each backend fires independently — one failure doesn't block others.

```bash
# Example: simultaneous Feishu + Bark
CC_NOTIFY_BACKEND=auto
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
CC_BARK_URL=https://api.day.app/YOUR_KEY
```

## Claude Code Hook Events

| Event | When It Fires | `matcher` Matches Against |
|-------|--------------|--------------------------|
| **PreToolUse** | Before a tool executes | Tool name (`Bash`, `Read`, etc.) |
| **PostToolUse** | After a tool executes (success) | Tool name |
| **PostToolUseFailure** | After a tool executes (failure) | Tool name |
| **Stop** | Session/task ends | Stop reason |
| **Notification** | CC sends a notification | `permission_prompt` / `idle_prompt` / `auth_success` / `elicitation_dialog` |
| **PermissionRequest** | CC asks user for permission | Tool name |
| **UserPromptSubmit** | User submits input | `*` |

### Tool Names (for matchers)

`Bash` · `Read` · `Write` · `Edit` · `MultiEdit` · `Glob` · `Grep` · `WebFetch` · `WebSearch` · `Task` · `NotebookRead` · `NotebookEdit` · `TodoWrite`

### Matcher Syntax

- `"*"` — match all
- `"Bash"` — exact match
- `"Read|Edit|Write"` — pipe-separated OR
- `""` — ⚠️ **avoid** (undefined behavior, may prevent hooks from firing)

## Comparison with Claude Code `--channels`

| Feature | CC `--channels` (Preview) | These Hooks |
|---------|--------------------------|-------------|
| Notification channels | claude.ai mobile only | 9 backends (Feishu/Slack/Telegram/etc.) |
| Multi-channel broadcast | ❌ | ✅ |
| Permission approval | ✅ Approve from phone | Notification only |
| Task completion alerts | ❌ | ✅ |
| Security gates | ❌ | ✅ |
| Large file guards | ❌ | ✅ |
| Progress tracking | ❌ | ✅ |
| Dependencies | MCP + claude.ai account | bash + curl |

No conflict — they complement each other.

## Hardening

- **Fail-open:** Every hook declares `FAIL_MODE=open` — hook crash never blocks Claude Code
- **Audit log:** Structured JSONL at `~/.cchooks/logs/hooks-audit.jsonl`
- **Atomic writes:** All JSON writes use tmp → validate → mv
- **Dedup locks:** Stop hook uses TTL-based lock to prevent duplicate notifications
- **Externalized rules:** `cc-safety-gate.sh` loads custom rules from `safety-rules.conf`

## Changelog

### v2.0.0 (2026-04-02)

**🚀 Interactive Installer + Security Audit**

- **`install.sh` v2**: Complete rewrite with 6-step interactive flow
  - TUI checkbox module selector (powered by `tools/select-modules.js`)
  - Deep-merge hooks into `settings.json` (won't overwrite user customizations)
  - `--status` / `--update` / `--uninstall` / `--purge` subcommands
  - Atomic writes with rollback on failure
  - Unified trap management (EXIT/INT/TERM/ERR)
  - `curl | bash` compatible with fd3 tty input

- **Security audit (P0+P1+P2)**:
  - `guard-large-files.sh`: Fixed deny format (`decision`+`reason` instead of `hookSpecificOutput`)
  - `cc-stop-hook.sh`: Dedup lock TTL 60→300s, proper cleanup
  - `send-notification.sh`: 7× curl calls hardened with `--connect-timeout 3 --max-time 8`
  - `dispatch-claude.sh`: git add excludes `.env*/key/pem/secret`
  - `cc-safety-gate.sh`: Expanded blacklist patterns
  - `wait-notify.sh`: Fixed NOTIFY_MESSAGE/TYPE + cooldown period
  - `reap-orphans.sh`: 7-day .done cleanup + PID reuse protection

### v1.3.1 (2026-04-01)

**🪟 Windows Git Bash Compatibility**

- Python3 shim: auto-detect `python` when `python3` missing
- jq fallback: 5 scripts fallback to Python for JSON parsing
- Fixed matcher `""` → `"*"` (empty string caused hooks to never fire)
- Fixed `cc-safety-gate.sh` regex false positives (`curl.*|.*sh`)
- `.gitattributes`: Force LF line endings for `.sh` files

### v1.3.0 (2026-03-31)

**📡 Broadcast Mode**

- `send-notification.sh` v2: Auto-discover + broadcast to all configured backends
- `cancel-wait.sh`: 5s grace period
- `wait-notify.sh`: Fixed `exit 0` killing Notification events

### v1.2.0 (2026-03-31)

Feishu & WeCom webhook + decoupled from OpenClaw.

### v1.1.0 (2026-03-30)

Git worktree isolation (P0 security).

### v1.0.0 (2026-03-29)

Initial release.

## Dependencies

| Dependency | Required | Purpose |
|-----------|----------|---------|
| `bash` 4.0+ | ✅ | All hook scripts |
| `node` 14+ | ✅ | Installer TUI + hooks merge |
| `curl` | ✅ | Notification delivery |
| `python3` | ✅ | JSON escaping (auto-detects `python` on Windows) |
| `jq` | Recommended | JSON parsing (graceful Python fallback) |
| `git` | Optional | Worktree isolation in dispatch |
| `openssl` | Optional | HMAC-SHA256 signing for Feishu |

## License

MIT
