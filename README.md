---
name: claude-code-hooks
description: Keep Claude Code on a leash — task notifications, security gates, and cross-platform hooks.
version: 1.0.1
---

# 🦞 Claude Code Hooks

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

### 🔴 Core Hooks (Auto-enabled on install)

| Hook | Trigger | What it actually does |
|------|---------|----------------------|
| 🔔 **cc-stop-hook.sh** | Task ends | Pings you on Feishu/Slack/Telegram/etc. No more staring at terminals. |
| ⏰ **wait-notify.sh** | Needs permission | "Hey, Claude's been waiting for you for 30 seconds..." |
| 🛑 **cancel-wait.sh** | You respond | Cancels the nag. It knows you're back. |
| 🛡️ **cc-safety-gate.sh** | Runs bash | Blocks `rm -rf /`, `sudo`, `eval`, pipe-to-shell, and 20+ other patterns. |
| 📏 **guard-large-files.sh** | Reads files | "No, you don't need to read `node_modules/`. Trust me." |

### 🟡 Extended Security (Optional - enable via settings.json)

| Hook | Trigger | Function |
|------|---------|----------|
| 🔐 **config-change-guard.sh** | Config changes | Prevent accidental settings.json modification |
| 🛡️ **mcp-guard.sh** | MCP tool calls | Block dangerous MCP operations |
| 🔍 **injection-scan.sh** | User input | Detect prompt injection patterns |
| 📁 **project-context-guard.sh** | File writes | Protect critical project files (.env, .git, etc) |
| 💰 **openrouter-cost-summary.sh** | Task end | Show API costs per session |

### 🟢 Tools & Utilities

| Tool | Trigger | Function |
|------|---------|----------|
| 🚀 **dispatch-claude.sh** | Manual | Spawn isolated sub-tasks with git worktree |
| 📊 **check-claude-status.sh** | Manual | Quick task status check |
| 🧹 **reap-orphans.sh** | Cron / manual | Clean zombie processes ⚠️ needs cron setup |
| 📚 **generate-skill-index.sh** | Manual / cron | Build skill directory index |
| 💰 **[statusline/](tools/statusline/)** | claude-hud | Real-time OpenRouter credit monitor |

**📖 Full script reference:** See [CLAUDE-SCRIPTS-REFERENCE.md](CLAUDE-SCRIPTS-REFERENCE.md)

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

### 🎯 Choose Your Installation Path

#### 🟢 Path 1: Interactive Selection (Recommended)
**Best for:** Users who want to customize what gets installed  
**Time:** 5-10 minutes  
**Difficulty:** ⭐⭐ (interactive prompts)

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks
bash install-interactive.sh
```

This guided installer will:
- ✅ Detect your OS
- ✅ Ask which modules you want (core + optional + tools)
- ✅ Configure settings.json automatically
- ✅ Verify everything works

Choose from:
- **Core only** (5 min): Notifications + security
- **Core + extended** (10 min): Add advanced guards
- **Core + tools** (10 min): Add task management
- **Everything** (15 min): Full suite + statusline

---

### ⚡ Path 1b: Quick Install (All Defaults)
**Best for:** Users who want everything  
**Time:** 5 minutes

```bash
bash install.sh 2>/dev/null | grep -E "✓|✗|Error"
```

Installs everything and configures settings.json.

---

### 🤖 Path 2: Let Claude Code Install It For You (Zero CLI Knowledge Required)

**Best for:** Anyone who prefers to just describe what they want instead of running shell commands  
**Time:** ~3 minutes  
**Difficulty:** ⭐ (just type in Claude Code)

Clone the repo, open it in Claude Code, and ask it to read the install guide. Claude will run every step and ask you what you need.

```bash
# Step 1 — clone (pick one)
git clone https://github.com/Gopherlinzy/claude-code-hooks.git ~/projects/claude-code-hooks

# 🇨🇳 GitHub slow?
git clone https://ghfast.top/https://github.com/Gopherlinzy/claude-code-hooks.git ~/projects/claude-code-hooks

# Step 2 — open the project in Claude Code
cd ~/projects/claude-code-hooks
claude
```

Then just tell Claude what you want, for example:

```
Please read CLAUDE.md and install claude-code-hooks for me.
I use Feishu for notifications. My webhook URL is https://...
```

Claude will:
1. Read `CLAUDE.md` (the AI-readable install guide in this repo)
2. Copy scripts to the right place
3. Ask you which notification backend you want
4. Patch `~/.claude/settings.json` with the correct hooks
5. Verify everything works

> **Note:** `CLAUDE.md` is a machine-readable install guide — it describes every step so Claude Code can execute the full installation on your behalf.

---

### Choose Your Path

Not all installations are created equal. Pick the one that fits your style:

#### 🚀 Path A: One Line, Zero Regrets (Recommended)

**Best for:** Most users, including Windows Git Bash  
**Time:** ~2 minutes  
**Difficulty:** ⭐  

Just copy-paste one command. The installer handles everything: environment checks, script installation, module selection, hook registration, and notification setup.

**Pros:**
- ✅ Fully automated with interactive TUI
- ✅ Automatic rollback on errors
- ✅ Module selection built-in
- ✅ Supports Windows Git Bash natively
- ✅ One command, walk away

**Cons:**
- ❌ Less control over what gets installed
- ❌ Requires piping to bash (though fully auditable)

**[→ See detailed instructions below](#one-line-zero-regrets)**

---

#### 🛠️ Path B: Step-by-Step Manual (I Want Control)

**Best for:** Advanced users, CI/CD integration, custom deployments  
**Time:** ~10 minutes  
**Difficulty:** ⭐⭐  

Clone the repo and run each step manually. Full control over placement, configuration, and which modules to enable.

**Pros:**
- ✅ Complete control — decide what goes where
- ✅ Easy to integrate into CI/CD pipelines
- ✅ Audit every step before it runs
- ✅ Perfect for air-gapped environments (if pre-downloaded)
- ✅ Windows Git Bash fully supported

**Cons:**
- ❌ Requires 6 steps instead of 1 command
- ❌ Manual error recovery
- ❌ Needs basic bash knowledge

**Steps:**
1. Clone the repository
2. Copy scripts to `~/.claude/scripts/claude-hooks/`
3. Create `notify.conf` with your notification backend
4. Merge hooks into `~/.claude/settings.json`
5. (Optional) Configure StatusLine for OpenRouter credit monitoring
6. Verify everything with test commands

**[→ See detailed instructions below](#step-by-step-manual-i-want-control)**

---

#### 📦 Path C: Fully Offline (Air-Gapped Systems)

**Best for:** Offline development, air-gapped CI/CD, isolated networks  
**Time:** ~15 minutes (mostly waiting for download)  
**Difficulty:** ⭐⭐  

Pre-download on a machine with internet, then transfer to the offline system. Identical to Path B after the download step.

**Pros:**
- ✅ Works completely offline (after initial download)
- ✅ Same manual control as Path B
- ✅ No network calls on target machine
- ✅ Audit-friendly

**Cons:**
- ❌ Requires two machines (one with internet)
- ❌ Manual transfer of files
- ❌ Same 6-step setup as Path B

**Key difference:** Download on connected machine, then transfer the `claude-code-hooks/` directory via USB, scp, etc.

**[→ See detailed instructions below](#fully-offline-air-gapped-systems)**

---

### Path Comparison

| Aspect | Path 0 | Path A | Path B | Path C |
|--------|--------|--------|--------|--------|
| **Time** | ~3 min | ~2 min | ~10 min | ~15 min |
| **Difficulty** | ⭐ | ⭐ | ⭐⭐ | ⭐⭐ |
| **How** | Chat with Claude | One curl command | Manual steps | Pre-download then manual |
| **Control** | Claude decides | Low | High | High |
| **Error recovery** | Claude handles it | Automatic | Manual | Manual |
| **Internet required** | During | During | During | No (if pre-downloaded) |
| **Best for** | Non-CLI users | Most users | Power users, CI/CD | Air-gapped |
| **Windows Git Bash** | ✅ | ✅ | ✅ Recommended | ✅ |
| **Dependencies check** | Claude checks | Automatic | Manual | Manual |
| **Module selection** | Ask Claude | TUI | Manual editing | Manual editing |

---

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

---

### Step-by-Step Manual (I Want Control)

This is the detailed version of **Path B**. Follow all 6 steps for full control.

#### Step 1: Clone the Repository

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
cd /tmp/claude-code-hooks
```

> 🇨🇳 **In China or GitHub is slow?**
> ```bash
> git clone https://ghfast.top/https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
> cd /tmp/claude-code-hooks
> ```

#### Step 2: Copy Scripts

Create the installation directory and copy all scripts:

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
mkdir -p "${INSTALL_DIR}"

# Copy main hook scripts
cp scripts/*.sh "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}"/*.sh

# Copy statusline tools (optional, for OpenRouter credit monitoring)
mkdir -p "${INSTALL_DIR}/statusline"
cp tools/statusline/*.sh "${INSTALL_DIR}/statusline/"
chmod +x "${INSTALL_DIR}/statusline"/*.sh

# Copy utility tools (for future updates)
cp tools/merge-hooks.js "${INSTALL_DIR}/"
cp tools/select-modules.js "${INSTALL_DIR}/"
```

**Windows (Git Bash) note:** The paths above work as-is in Git Bash. No special handling needed.

#### Step 3: Create notify.conf

Choose your notification backend and configure it:

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
cat > "${INSTALL_DIR}/notify.conf" << 'EOF'
CC_NOTIFY_BACKEND=auto
CC_WAIT_NOTIFY_SECONDS=30

# Uncomment and configure your backend(s):
# NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
# CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../xxx
# CC_BARK_URL=https://api.day.app/YOUR_KEY
# CC_TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
# CC_TELEGRAM_CHAT_ID=987654321
# CC_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
EOF
```

**For sensitive credentials** (webhook URLs with tokens), put them in `~/.cchooks/secrets.env` instead:

```bash
mkdir -p "${HOME}/.cchooks"
cat > "${HOME}/.cchooks/secrets.env" << 'EOF'
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../xxx
EOF
chmod 600 "${HOME}/.cchooks/secrets.env"
```

#### Step 4: Merge Hooks into settings.json

This step registers all hooks into your Claude Code settings file (preserving any existing hooks).

**macOS / Linux / WSL2:**

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"

node "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" \
  <(node -e "
const fs = require('fs');
const dir = '${INSTALL_DIR}'.replace(/'/g, '');
const cmd = (script) => dir + '/' + script;
const hooks = {
  hooks: {
    Stop: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cc-stop-hook.sh'), timeout: 15 }] }],
    PreToolUse: [
      { matcher: 'Bash', hooks: [{ type: 'command', command: cmd('cc-safety-gate.sh'), timeout: 5 }] },
      { matcher: 'Read|Edit|Write', hooks: [{ type: 'command', command: cmd('guard-large-files.sh'), timeout: 5 }] }
    ],
    PermissionRequest: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('wait-notify.sh'), timeout: 5 }] }],
    Notification: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('wait-notify.sh'), timeout: 5 }] }],
    PostToolUse: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cancel-wait.sh'), timeout: 3 }] }],
    UserPromptSubmit: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cancel-wait.sh'), timeout: 3 }] }]
  }
};
fs.writeFileSync('/dev/stdout', JSON.stringify(hooks, null, 2));
") \
  "${SETTINGS}"
```

**Windows (Git Bash):**

For Windows, add `bash ` prefix to all hook commands:

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"

node -e "
const fs = require('fs');
const dir = '${INSTALL_DIR}'.replace(/'/g, '');
const prefix = 'bash ';
const cmd = (script) => prefix + dir + '/' + script;
const hooks = {
  hooks: {
    Stop: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cc-stop-hook.sh'), timeout: 15 }] }],
    PreToolUse: [
      { matcher: 'Bash', hooks: [{ type: 'command', command: cmd('cc-safety-gate.sh'), timeout: 5 }] },
      { matcher: 'Read|Edit|Write', hooks: [{ type: 'command', command: cmd('guard-large-files.sh'), timeout: 5 }] }
    ],
    PermissionRequest: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('wait-notify.sh'), timeout: 5 }] }],
    Notification: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('wait-notify.sh'), timeout: 5 }] }],
    PostToolUse: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cancel-wait.sh'), timeout: 3 }] }],
    UserPromptSubmit: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cancel-wait.sh'), timeout: 3 }] }]
  }
};
fs.writeFileSync('/tmp/hooks-patch.json', JSON.stringify(hooks, null, 2));
" && node "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" /tmp/hooks-patch.json "${SETTINGS}"
rm -f /tmp/hooks-patch.json
```

#### Step 5: (Optional) Configure StatusLine for OpenRouter Credits

If you want real-time OpenRouter credit monitoring in your claude-hud statusline:

**macOS / Linux / WSL2:**

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"
PLUGIN_DIR=$(ls -d "${HOME}/.claude/plugins/cache/claude-hud/claude-hud/"*/ 2>/dev/null | \
    awk -F/ '{ print $(NF-1) "\t" $(0) }' | \
    sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | \
    tail -1 | cut -f2-)

if [ -z "$PLUGIN_DIR" ]; then
    echo "⚠️  claude-hud plugin not found — StatusLine skipped"
else
    node -e "
const fs = require('fs');
const settings = JSON.parse(fs.readFileSync('${SETTINGS}', 'utf8'));
settings.statusLine = {
    command: 'bash -c \"plugin_dir=${PLUGIN_DIR}; exec node \\\${plugin_dir}dist/index.js --extra-cmd \\\"bash ${INSTALL_DIR}/statusline/openrouter-status.sh\\\"\"',
    type: 'command'
};
fs.writeFileSync('${SETTINGS}', JSON.stringify(settings, null, 2) + '\\n');
" && echo "✅ StatusLine configured"
fi
```

**Windows (Git Bash):**

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"
PLUGIN_DIR=$(ls -d "${HOME}/.claude/plugins/cache/claude-hud/claude-hud/"*/ 2>/dev/null | \
    awk -F/ '{ print $(NF-1) "\t" $(0) }' | \
    sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | \
    tail -1 | cut -f2-)

if [ -z "$PLUGIN_DIR" ]; then
    echo "⚠️  claude-hud plugin not found — StatusLine skipped"
else
    node -e "
const fs = require('fs');
const settings = JSON.parse(fs.readFileSync('${SETTINGS}', 'utf8'));
settings.statusLine = {
    command: 'bash -c \"plugin_dir=${PLUGIN_DIR}; exec node \\\${plugin_dir}dist/index.js --extra-cmd \\\"bash ${INSTALL_DIR}/statusline/openrouter-status.sh\\\"\"',
    type: 'command'
};
fs.writeFileSync('${SETTINGS}', JSON.stringify(settings, null, 2) + '\\n');
" && echo "✅ StatusLine configured"
fi
```

#### Step 6: Verify Installation

Run these checks to ensure everything is set up correctly:

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"

# Check all scripts are executable
echo "=== Checking hook scripts ==="
for f in "${INSTALL_DIR}"/*.sh; do
    if bash -n "$f" 2>/dev/null; then
        echo "✅ $(basename "$f")"
    else
        echo "❌ $(basename "$f") — syntax error"
    fi
done

# Check settings.json is valid JSON
echo "=== Checking settings.json ==="
if python3 -c "import json; json.load(open('${SETTINGS}'))" 2>/dev/null; then
    echo "✅ settings.json is valid JSON"
else
    echo "❌ settings.json is invalid"
fi

# Test a notification (if configured)
echo "=== Testing notification ==="
if "${INSTALL_DIR}/send-notification.sh" "Claude Code Hooks test message 🦞"; then
    echo "✅ Notification sent"
else
    echo "⚠️  Notification backend not configured yet"
fi
```

**If any checks fail,** see [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for solutions.

---

### Fully Offline (Air-Gapped Systems)

This is the detailed version of **Path C**. Use this when the target system has no internet access.

#### Step 0: Prepare on a Machine with Internet

On a machine with internet access:

```bash
# Clone the repository
git clone https://github.com/Gopherlinzy/claude-code-hooks.git

# Optionally, compress for transfer (if space is a concern)
tar czf claude-code-hooks.tar.gz claude-code-hooks/
```

Transfer the `claude-code-hooks/` directory (or the compressed tar.gz) to the target machine via USB, scp, or another method.

#### Steps 1-6: Same as Path B

Once you have the `claude-code-hooks/` directory on the offline machine, follow **Path B steps 1-6** exactly as written:

1. ✅ Clone → Skip (already have the directory)
2. ✅ Copy scripts
3. ✅ Create notify.conf
4. ✅ Merge hooks into settings.json
5. ✅ (Optional) Configure StatusLine
6. ✅ Verify installation

**The only difference:** Instead of cloning from GitHub in Step 1, just navigate to wherever you transferred the `claude-code-hooks/` directory:

```bash
# Instead of: git clone https://github.com/.../claude-code-hooks.git /tmp/claude-code-hooks
# You already have it, so just:
cd /path/to/claude-code-hooks
# Then continue with Step 2 (copy scripts) and beyond
```

---

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

**Recommended:** Use the built-in setup skill
```bash
/claude-hud:setup
```
This automatically detects your platform and generates the correct command.

---

**Manual configuration (if needed):**

**macOS / Linux:**
```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print $(NF-1) \"\\t\" $(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"node\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
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

> **Note:** On Windows, if the command has errors, see [StatusLine Command Errors](docs/TROUBLESHOOTING.md#statusline-command-errors).

**Requirements:**
- `OPENROUTER_API_KEY` environment variable must be set
- `claude-hud` plugin must be installed
- Node.js 18+ available in PATH

See [tools/statusline/README.md](tools/statusline/) for full setup guide.

## Troubleshooting

**Something not working?** Start here for quick answers.

### Quick Links

- 🔧 **Hooks registered but not firing?** → [Hooks Not Firing](docs/TROUBLESHOOTING.md#hooks-not-firing)
- 💻 **Installation failed on Windows?** → [Installation Failures](docs/TROUBLESHOOTING.md#installation-failures)
- 📊 **StatusLine not showing?** → [StatusLine Command Errors](docs/TROUBLESHOOTING.md#statusline-command-errors)
- 🪟 **Windows-specific issues?** → [Windows Git Bash Specific](docs/TROUBLESHOOTING.md#windows-git-bash-specific)
- 📖 **Full troubleshooting guide:** [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

### Quick Checklist

Before opening an issue:

- [ ] Restart Claude Code after installing hooks
- [ ] Check `~/.claude/settings.json` contains `"hooks"` key
- [ ] Verify `notify.conf` is readable: `cat ~/.claude/scripts/claude-hooks/notify.conf`
- [ ] Test a hook manually: `bash -n ~/.claude/scripts/claude-hooks/cc-stop-hook.sh`
- [ ] On Windows? Verify Node.js in PATH: `node --version`

**Still stuck?** See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) or [open a GitHub issue](https://github.com/Gopherlinzy/claude-code-hooks/issues).

---

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
