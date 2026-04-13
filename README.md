---
name: claude-code-hooks
description: Keep Claude Code on a leash — task notifications, security gates, and cross-platform hooks.
version: 1.0.1
---

# 🦞 Claude Code Hooks

[中文文档 / Chinese Documentation](https://github.com/Gopherlinzy/claude-code-hooks/blob/main/README_CN.md)

> "I gave Claude Code `sudo` access once. Once."

A battle-tested collection of [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) that adds guardrails, notifications, and sanity to your AI coding assistant — so you can walk away from the terminal without walking into disaster.

## The Problem

You fire up Claude Code, assign it a complex task, and go grab coffee. When you come back:

- ☕ Your task finished 20 minutes ago. Nobody told you.
- 🔐 Claude's been politely waiting for permission. For 20 minutes. In silence.
- 💀 Or worse — it ran `rm -rf` on something it shouldn't have.
- 📖 It burned half your context window reading a 15,000-line `bundle.min.js`.
- 👻 Three orphan processes are still alive from yesterday's async tasks.

**This repo fixes all of that.**

## What's in the Box

| Hook | Trigger | What it actually does |
|------|---------|----------------------|
| 🔔 **cc-stop-hook.sh** | Task ends | Pings you on Feishu/Slack/Telegram/etc. No more staring at terminals. |
| ⏰ **wait-notify.sh** | Needs permission | "Hey, Claude's been waiting for you for 30 seconds..." |
| 🛑 **cancel-wait.sh** | You respond | Cancels the nag. It knows you're back. |
| 🛡️ **cc-safety-gate.sh** | Runs bash | Blocks `rm -rf /`, `sudo`, `eval`, pipe-to-shell, and [22 other patterns](#safety-gate-patterns). |
| 📏 **guard-large-files.sh** | Reads files | "No, you don't need to read `node_modules/`. Trust me." |
| 🚀 **dispatch-claude.sh** | You | Spawn isolated sub-tasks with git worktree, progress tracking, the works. |
| 📊 **check-claude-status.sh** | You | "Is that thing still running?" Quick answer. |
| 🧹 **reap-orphans.sh** | Cron / manual | Finds zombie Claude processes and puts them down humanely. |
| 📚 **generate-skill-index.sh** | Lazy | Builds a skill directory so Claude knows what tools it has. |
| 💰 **[statusline/](tools/statusline/)** | claude-hud display | Real-time OpenRouter credit monitor with visual progress bar. |

## 🎨 Statusline Tools (Optional)

### OpenRouter Credit Monitor for claude-hud

Enhance your Claude Code statusline with real-time OpenRouter API balance monitoring. This feature requires `claude-hud` (Claude's official statusline plugin).

```
Claude Haiku 4.5 │ .openclaw │ 💰 394.34/500 ▓▓▓▓▓▓▓░░░ 79% │ context: 42%
```

**What you get:**
- ✅ Real-time credit balance display
- ✅ Visual 10-char progress bar
- ✅ 60-second smart caching (minimal API calls)
- ✅ Works offline gracefully
- ✅ Cross-platform (macOS/Linux/Windows)

### Quick Setup (3 steps)

**Step 1: Install claude-hud plugin**

In Claude Code, run:
```
/plugin marketplace add jarrodwatts/claude-hud
/plugin install claude-hud
```

Then configure the statusline:
```
/claude-hud:setup
```

**Step 2: Run the OpenRouter setup tool**

```bash
~/.claude/scripts/claude-hooks/setup-statusline.sh
```

This tool will:
- ✅ Verify claude-hud is installed
- ✅ Generate the correct `statusLine` config for your OS
- ✅ Guide you to add `OPENROUTER_API_KEY` to your shell
- ✅ Show you exactly where to paste the config

**Step 3: Paste config into settings.json**

The tool outputs a JSON snippet you can copy directly into `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "command": "bash -c 'node /path/to/claude-hud/index.js --extra-cmd \"...\"'",
    "type": "command"
  }
}
```

### Manual Setup (if you prefer)

If you want to configure manually, see [tools/statusline/README.md](tools/statusline/) for detailed instructions.

**Requirements:**
- `OPENROUTER_API_KEY` environment variable set (or `ANTHROPIC_AUTH_TOKEN` as fallback)
- `claude-hud` plugin (auto-installed by Claude Code)
- Node.js 18+ (already required by Claude Code)

> **macOS/Linux:** `jq` is auto-detected from PATH
>
> **Windows (Git Bash):** Manual jq installation required
> ```bash
> mkdir -p ~/.claude/scripts
> curl -fsSL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe \
>   -o ~/.claude/scripts/jq.exe
> chmod +x ~/.claude/scripts/jq.exe
> ```
> The statusline script will auto-detect it after restart.

## Quick Start

### One Line, Zero Regrets

```bash
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
```

> 🇨🇳 **In China / GitHub is slow?**
> ```bash
> curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
> ```

The installer does everything:

```
[1/6] Environment check     ← bash, node, python3, curl — got it?
[2/6] Install scripts        ← Clone → copy → chmod. Done.
[3/6] Pick your modules      ← TUI with checkboxes! Very fancy.
[4/6] Patch settings.json    ← Deep merge. Your existing hooks? Untouched.
[5/6] Notification setup     ← Feishu, Slack, Telegram, Bark, Discord...
[6/6] Verify                 ← Green checkmarks or we roll back.
```

```
  ↑↓ navigate  ␣ toggle  a all/none  Enter confirm

  ❯ [✔] Stop notification       Because silence is not golden
    [✔] Safety gate (Bash)       Because rm -rf / is never the answer
    [✔] Large file guard         Because bundle.min.js is not light reading
    [✔] Wait notification        Because Claude is too polite to yell
    [✔] Cancel wait              Because you came back, good human
```

### Installer Tricks

```bash
./install.sh                    # Interactive install
./install.sh --non-interactive  # CI mode — all modules, no questions
./install.sh --status           # "Am I installed correctly?"
./install.sh --update           # Update scripts, keep your config
./install.sh --uninstall        # Clean exit
./install.sh --uninstall --purge  # Nuclear option
```

### DIY Install (I Don't Trust Pipe-to-Bash)

Fair. Respect.

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks && ./install.sh
```

Or fully manual, no installer at all:
```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
# Then hand-edit ~/.claude/settings.json — see Hook Registration below
```

## Platform Support

| Platform | Status | Installation | Notes | Issues |
|----------|--------|--------------|-------|--------|
| 🍎 **macOS** | ✅ Full | `./install.sh` | Needs bash 4.0+ (`brew install bash` if on 3.2) | None known |
| 🐧 **Linux** | ✅ Full | `./install.sh` | `apt install bash curl python3 jq` | None known |
| 🪟 **WSL2** | ✅ Full | `./install.sh` (Linux mode) | Plugin cache in WSL Linux home, not Windows | None known |
| 🪟 **Git Bash** | ✅ Hooks + ⚠️ StatusLine | `./install.sh` or manual | Hooks ✅ work; StatusLine has [known bugs](docs/TROUBLESHOOTING.md#bug-2-statusline-command-cascading-quotes-v101) | [See Git Bash issues](docs/TROUBLESHOOTING.md#windows-git-bash-specific) |
| 🪟 **PowerShell / cmd** | ❌ | Use WSL2 | Not supported — hook scripts are bash only | Use [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/) |

**Key differences:**

- **macOS/Linux:** Full support, everything works out-of-the-box
- **WSL2:** Full support, use Linux instructions (plugin cache must be in WSL filesystem)
- **Git Bash:** Hooks work ✅, StatusLine configuration has known path escaping issues (v1.0.1). [See workarounds](docs/TROUBLESHOOTING.md#windows-git-bash-specific)
- **PowerShell:** Not supported. Use WSL2 for Windows native development.

> **Windows users:** Most issues are path-related and [documented in TROUBLESHOOTING](docs/TROUBLESHOOTING.md#windows-git-bash-specific). If install fails, [check the Windows troubleshooting section](docs/TROUBLESHOOTING.md#installation-failures).

### v1.0.1: Cross-Platform Shim & Security Hardening

New in v3: `platform-shim.sh` provides portable replacements for platform-specific commands. All hook scripts automatically use the shim — no manual configuration needed.

```bash
# These just work everywhere now:
_date_iso          # date -Iseconds (broken on MSYS2)
_kill_check $PID   # kill -0 (not on Git Bash)
_ps_command_of $PID  # ps -p PID -o command= (ditto)
_stat_mtime $FILE  # stat -f %m / stat -c %Y
_env_clean cmd     # env -i (Windows? What's that?)
_sleep_frac 0.05   # Fractional sleep (MSYS2 says no)
```

## Post-Install: Set Up Notifications

Edit `notify.conf` — this is where hook subprocesses look for config (**they don't inherit your shell env**):

```bash
vim ~/.claude/scripts/claude-hooks/notify.conf
```

```bash
CC_NOTIFY_BACKEND=auto          # Auto-discover all configured backends
CC_WAIT_NOTIFY_SECONDS=30       # How long before "hey, Claude's waiting"

# Uncomment the ones you want:
# NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
# CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../xxx
# CC_BARK_URL=https://api.day.app/YOUR_KEY
# CC_TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
# CC_TELEGRAM_CHAT_ID=987654321
# CC_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

> 🔒 **Secrets management (v1.0.1):** For sensitive URLs/tokens, put them in `~/.cchooks/secrets.env` (chmod 600) instead of `notify.conf`. The scripts auto-load both, with integrity checks.

Test it:
```bash
~/.claude/scripts/claude-hooks/send-notification.sh "Hello from Claude Code Hooks! 🦞"
```

## 9 Notification Backends

**Broadcast mode** (default): fires all configured backends simultaneously. One failing? Others don't care.

| Backend | Config Variable | What |
|---------|----------------|------|
| **Feishu** 飞书 | `NOTIFY_FEISHU_URL` | Webhook (supports HMAC signing) |
| **WeCom** 企业微信 | `NOTIFY_WECOM_URL` | Group bot webhook |
| **Slack** | `CC_SLACK_WEBHOOK_URL` | Incoming Webhook |
| **Telegram** | `CC_TELEGRAM_BOT_TOKEN` + `CHAT_ID` | Bot API |
| **Discord** | `CC_DISCORD_WEBHOOK_URL` | Webhook |
| **Bark** | `CC_BARK_URL` | iOS push — [Bark](https://github.com/Finb/Bark) |
| **Webhook** | `CC_WEBHOOK_URL` | Any HTTP endpoint you fancy |
| **Command** | `CC_NOTIFY_COMMAND` | Pipe message to any CLI tool |
| **OpenClaw** | `CC_NOTIFY_TARGET` | Route through OpenClaw channels |

```bash
# Example: Feishu + Bark simultaneously
CC_NOTIFY_BACKEND=auto
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
CC_BARK_URL=https://api.day.app/YOUR_KEY
# → Both get every notification. Redundancy is love.
```

## Safety Gate Patterns

The safety gate (`cc-safety-gate.sh`) blocks these on sight:

| Category | Examples |
|----------|---------|
| **Destructive** | `rm -rf /`, `rm -rf ~/`, `mkfs`, `dd if=` |
| **Privilege escalation** | `sudo`, `/usr/bin/sudo`, `\sudo`, `chmod 777` |
| **Code injection** | `eval`, `source <(...)`, `. <(...)`, `base64 ... \| bash` |
| **Remote execution** | `curl \| sh`, `wget \| bash`, download-and-exec chains |
| **Wrapper bypass** | `bash -c "rm ..."`, `sh -c "sudo ..."`, `python3 -c "os.system(...)"` |
| **Path protection** | Writes to `.ssh/`, `SOUL.md`, `IDENTITY.md`, `/etc/`, `/System/` |

Plus external rules via `safety-rules.conf` for your own patterns.

> ⚠️ **Honest disclaimer:** Blacklists are inherently bypassable. A determined attacker (or a creative LLM) can find ways around them. This is a speed bump, not a wall. Use `--permission-mode` for real security boundaries.

## Architecture

```
Claude Code Session
  │
  ├── PreToolUse ─────┬── cc-safety-gate.sh ── "Nope, not running that."
  │                   └── guard-large-files.sh ── "Put down the bundle.min.js."
  │
  ├── PermissionRequest ── wait-notify.sh ──→ ⏱️ 30s ──→ 📱 "Come back!"
  │
  ├── Notification ─────── wait-notify.sh ──→ ⏱️ 30s ──→ 📱 "Still waiting..."
  │
  ├── PostToolUse ──────── cancel-wait.sh ──→ ⏱️❌ "Never mind, they're here."
  │
  ├── UserPromptSubmit ─── cancel-wait.sh ──→ ⏱️❌ "They typed something!"
  │
  └── Stop ─────────────── cc-stop-hook.sh ──→ 📱 "Done! Here's what happened."
```

## Hook Registration (settings.json)

The installer handles this, but for the manual crowd:

```json
{
  "hooks": {
    "Stop": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cc-stop-hook.sh", "timeout": 15 }] }
    ],
    "PreToolUse": [
      { "matcher": "Read|Edit|Write", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/guard-large-files.sh", "timeout": 5 }] },
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cc-safety-gate.sh", "timeout": 5 }] }
    ],
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/wait-notify.sh", "timeout": 5 }] }
    ],
    "Notification": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/wait-notify.sh", "timeout": 5 }] }
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

### StatusLine Configuration (Optional)

To add real-time OpenRouter credit monitoring to claude-hud statusline:

**macOS / Linux:**
```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print $(NF-1) \"\\t\" $(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"/usr/local/bin/node\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
```

**Windows (Git Bash / MSYS2):**
```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print $(NF-1) \"\\t\" $(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"node\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
```

**Requirements:**
- `OPENROUTER_API_KEY` environment variable must be set
- `claude-hud` plugin must be installed
- Node.js 18+ available in PATH

See [tools/statusline/README.md](tools/statusline/) for full setup guide.

## Hardening

Things we're proud of:

- 🛟 **Fail-open everywhere** — A hook crash never blocks Claude Code. Ever.
- 📝 **JSONL audit log** — Everything goes to `~/.cchooks/logs/hooks-audit.jsonl`
- 🔒 **Secrets isolation** — Credentials live in `~/.cchooks/secrets.env` (600), not in script dirs
- 🧬 **Integrity checks** — `source` won't load files containing `$(` or backticks
- ⚛️ **Atomic writes** — tmp → validate → mv (crash-safe)
- 🔑 **API key quarantine** — Hooks unset `ANTHROPIC_API_KEY` before doing anything
- 🌍 **Cross-platform shim** — `platform-shim.sh` makes everything work on macOS/Linux/WSL2/Git Bash

## Claude Code Hook Events

| Event | When | Matcher matches... |
|-------|------|-------------------|
| **PreToolUse** | Before tool runs | Tool name (`Bash`, `Read`, etc.) |
| **PostToolUse** | After tool succeeds | Tool name |
| **Stop** | Session ends | Stop reason |
| **Notification** | CC sends notification | `permission_prompt` / `idle_prompt` / etc. |
| **PermissionRequest** | CC needs approval | Tool name |
| **UserPromptSubmit** | You type something | `*` |

**Matcher syntax:** `"*"` (all) · `"Bash"` (exact) · `"Read|Edit|Write"` (OR) · `""` (don't — undefined behavior)

## vs Claude Code `--channels`

| | `--channels` (Preview) | These Hooks |
|-|----------------------|-------------|
| Notification channels | claude.ai mobile | 9 backends |
| Multi-channel | ❌ | ✅ Broadcast |
| Remote approval | ✅ | Notification only |
| Security gates | ❌ | ✅ 22 patterns |
| File guards | ❌ | ✅ |
| Progress tracking | ❌ | ✅ |
| Dependencies | MCP + claude.ai | bash + curl |

They're complementary, not competing. Use both.

## Dependencies

| What | Required? | Why |
|------|-----------|-----|
| `bash` 4.0+ | ✅ | Everything is bash. macOS ships 3.2 — `brew install bash` |
| `node` 14+ | ✅ | Installer TUI + hooks merge |
| `curl` | ✅ | Sending notifications |
| `python3` | ✅ | JSON escaping (detects `python` on Windows) |
| `jq` | Recommended | JSON parsing (graceful Python fallback without it) |
| `git` | Optional | Worktree isolation |
| `openssl` | Optional | HMAC signing for Feishu |

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed release notes, bug fixes, and version history.

**Latest (v1.0.0 - 2026-04-12):**
- 4 P0 bug fixes (quality score 7.5 → 8.5)
- Multi-account Git support (GitHub + GitLab)
- SSH key routing configuration
- Cross-platform compatibility improvements

## License

MIT — Do whatever you want. Just don't `rm -rf /`.
