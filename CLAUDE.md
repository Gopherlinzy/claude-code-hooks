# Claude Code Hooks — Agent Installation Guide

> This file is for Claude Code (the AI agent) to read.
> If a user asks you to install claude-code-hooks, follow these steps.

## Installation Steps

### 0. Check if already cloned

**If the user already has the files locally:**
```bash
ls -d ~/projects/claude-code-hooks 2>/dev/null && echo "✓ Already cloned" || echo "✗ Need to clone"
```

**Choose your path:**
- **Already cloned locally?** → Skip to step 2 (use your local path instead of `/tmp/claude-code-hooks`)
- **Need to clone?** → Continue to step 1
- **Want one-line install?** → Use `install.sh` from the repo directly

### 1. Clone the repo

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
```

If in China or GitHub is slow:
```bash
git clone https://ghfast.top/https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
```

### 2. Copy scripts

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
mkdir -p "${INSTALL_DIR}"
cp /tmp/claude-code-hooks/scripts/*.sh "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}"/*.sh

# Copy statusline tools
mkdir -p "${INSTALL_DIR}/statusline"
cp /tmp/claude-code-hooks/tools/statusline/*.sh "${INSTALL_DIR}/statusline/"
chmod +x "${INSTALL_DIR}/statusline"/*.sh

# Copy utility tools (for future updates)
cp /tmp/claude-code-hooks/tools/merge-hooks.js "${INSTALL_DIR}/"
cp /tmp/claude-code-hooks/tools/select-modules.js "${INSTALL_DIR}/"
```

### 3. Create notify.conf

Ask the user which notification backend they want. Common options:
- **Feishu (飞书)**: needs `NOTIFY_FEISHU_URL`
- **Slack**: needs `CC_SLACK_WEBHOOK_URL`
- **Telegram**: needs `CC_TELEGRAM_BOT_TOKEN` + `CC_TELEGRAM_CHAT_ID`
- **Bark (iOS)**: needs `CC_BARK_URL`
- **WeCom (企业微信)**: needs `NOTIFY_WECOM_URL`

```bash
cat > "${INSTALL_DIR}/notify.conf" << 'EOF'
CC_NOTIFY_BACKEND=auto
CC_NOTIFY_TARGET=""
CC_WAIT_NOTIFY_SECONDS=30
CC_NOTIFY_CHANNEL="feishu"
# Add backend URLs below:
EOF
chmod 600 "${INSTALL_DIR}/notify.conf"
```

If the user provides a webhook URL with a token/secret, put it in secrets.env instead:
```bash
mkdir -p "${HOME}/.cchooks"
cat > "${HOME}/.cchooks/secrets.env" << EOF
NOTIFY_FEISHU_URL=<user-provided-url>
EOF
chmod 600 "${HOME}/.cchooks/secrets.env"
```

### 4. Merge hooks into settings.json

Use the merge tool (preserves existing hooks):
```bash
SETTINGS="${HOME}/.claude/settings.json"

# Cross-platform temporary file (Windows: $TEMP, Unix: /tmp)
PATCH_FILE="${TMPDIR:-${TEMP:-/tmp}}/hooks-patch.json"
mkdir -p "$(dirname "$PATCH_FILE")" || exit 1

# Detect platform → decide command prefix
# Windows (Git Bash/MSYS/Cygwin): .sh files need "bash " prefix
# macOS/Linux: direct execution works
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) CMD_PREFIX="bash " ;;
    *)                     CMD_PREFIX="" ;;
esac

# Generate hooks-patch.json (platform-aware)
# Pass paths via environment to avoid Node.js path mangling in inline scripts
INSTALL_DIR_ENV="${INSTALL_DIR}" PREFIX_ENV="${CMD_PREFIX}" PATCH_FILE_ENV="$PATCH_FILE" node -e "
const fs = require('fs');
const path = require('path');

// Get values from environment (safer than shell variable substitution)
const dir = process.env.INSTALL_DIR_ENV;
const prefix = process.env.PREFIX_ENV || '';
const patchFile = process.env.PATCH_FILE_ENV;

if (!dir || !patchFile) {
  console.error('Error: INSTALL_DIR_ENV or PATCH_FILE_ENV not set');
  process.exit(1);
}

const cmd = (script) => prefix + path.join(dir, script).replace(/\\\\/g, '/');
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

fs.writeFileSync(patchFile, JSON.stringify(hooks, null, 2));
console.log('OK — platform: ' + (prefix ? 'Windows (bash prefix)' : 'Unix (direct)'));
"

# Deep merge
node "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" "$PATCH_FILE" "${SETTINGS}"
rm -f "$PATCH_FILE"
```

### 4b. Configure StatusLine for OpenRouter Monitoring (Optional)

If the user wants real-time OpenRouter credit monitoring in their statusline:

**Prerequisites: Install and configure claude-hud plugin first**

1. Add claude-hud to the plugin marketplace:
```bash
/plugin marketplace add jarrodwatts/claude-hud
```

2. Install the claude-hud plugin:
```bash
/plugin install claude-hud
```

3. Configure claude-hud (auto-setup):
```bash
/claude-hud:setup
```

**Then configure OpenRouter credit monitoring**

Once claude-hud is installed, use the recommended method:

```bash
/claude-hud:setup
```

Or run the setup tool:
```bash
~/.claude/scripts/claude-hooks/setup-statusline.sh
```

This automatically:
- Detects your platform (Windows/macOS/Linux)
- Finds the installed claude-hud plugin
- Generates correct command paths for openrouter-status.sh
- Updates settings.json safely

**Check: Is claude-hud installed?**

```bash
# Verify claude-hud is installed before proceeding
if [ ! -d "${HOME}/.claude/plugins/cache/claude-hud" ]; then
    echo "❌ claude-hud not found. Install it first:"
    echo "  /plugin marketplace add jarrodwatts/claude-hud"
    echo "  /plugin install claude-hud"
    echo "  /claude-hud:setup"
    exit 1
fi
echo "✅ claude-hud found"
```

**Alternative: Manual setup** (if automated setup unavailable)

```bash
SETTINGS="${HOME}/.claude/settings.json"
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"

# Find claude-hud plugin directory
PLUGIN_DIR=$(ls -d "${HOME}/.claude/plugins/cache/claude-hud/claude-hud"/*/ 2>/dev/null | sort -V | tail -1)

if [ -z "$PLUGIN_DIR" ]; then
    echo "❌ claude-hud plugin not found. Please install it first:"
    echo "  /plugin marketplace add jarrodwatts/claude-hud"
    echo "  /plugin install claude-hud"
    echo "  /claude-hud:setup"
    exit 1
fi

# Platform detection
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) 
        CMD="bash ${INSTALL_DIR}/statusline/openrouter-status.sh" 
        ;;
    *)
        CMD="${INSTALL_DIR}/statusline/openrouter-status.sh"
        ;;
esac

# Save to settings.json (simple jq command)
jq ".statusLine = {
    command: \"bash -c 'plugin_dir=${PLUGIN_DIR}; exec node \${plugin_dir}dist/index.js --extra-cmd \\\"${CMD}\\\"'\",
    type: \"command\"
}" "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "✅ StatusLine configured"
```

**Platform notes:**
- **Windows (Git Bash/MSYS)**: Commands use `bash` prefix; paths converted to forward slashes
- **macOS/Linux**: Direct execution; no prefix needed

### 5. Verify

```bash
# Syntax check all scripts
for f in "${INSTALL_DIR}"/*.sh; do bash -n "$f" && echo "✅ $(basename $f)" || echo "❌ $(basename $f)"; done

# Check settings.json is valid
python3 -c "import json; json.load(open('${SETTINGS}')); print('✅ settings.json valid')"

# Test notification (if configured)
"${INSTALL_DIR}/send-notification.sh" "Claude Code Hooks installed successfully! 🦞"
```

### 6. Clean up

```bash
rm -rf /tmp/claude-code-hooks
```

## Quick Decision Tree

To help users choose the right path:

```
Q: Do you already have claude-code-hooks cloned locally?
├─ YES  → Use your local path in step 2, skip step 1
└─ NO   → Clone it in step 1

Q: Do you want OpenRouter credit monitoring in statusline?
├─ YES  → Also do step 4b (requires claude-hud plugin)
│        └─ Check: Is claude-hud installed?
│           ├─ YES → Run setup-statusline.sh or /claude-hud:setup
│           └─ NO  → First install: /plugin marketplace add → /plugin install → /claude-hud:setup
└─ NO   → Skip step 4b entirely

Q: Is this Windows (Git Bash)?
├─ YES  → Remember bash prefixes in step 4
└─ NO   → Direct execution works fine
```

## Module Selection

Hook modules are enabled by default. StatusLine is optional (disabled by default). If the user wants to modify:

| Module | Type | Default | To Disable... |
|--------|------|---------|---|
| Stop notification | Hook | ON | Skip `Stop` event in step 4 |
| Safety gate | Hook | ON | Skip `PreToolUse` Bash matcher |
| Large file guard | Hook | ON | Skip `PreToolUse` Read\|Edit\|Write matcher |
| Wait notification | Hook | ON | Skip `PermissionRequest` + `Notification` events |
| Cancel wait | Hook | ON | Skip `PostToolUse` + `UserPromptSubmit` events |
| OpenRouter Credits | StatusLine | OFF | Don't run step 4b, or use installer to deselect |

## Updating

```bash
cd /tmp && git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cp /tmp/claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
rm -rf /tmp/claude-code-hooks
```

Config files (`notify.conf`, `secrets.env`) are never overwritten by updates.
