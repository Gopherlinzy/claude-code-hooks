# Claude Code Hooks — Agent Installation Guide

> This file is for Claude Code (the AI agent) to read.
> If a user asks you to install claude-code-hooks, follow these steps.

## Installation Steps

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

# Copy tools (for future updates)
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

# Generate hooks-patch.json
node -e "
const fs = require('fs');
const dir = '${INSTALL_DIR}'.replace(/'/g, '');
const hooks = {
  hooks: {
    Stop: [{ matcher: '*', hooks: [{ type: 'command', command: dir + '/cc-stop-hook.sh', timeout: 15 }] }],
    PreToolUse: [
      { matcher: 'Bash', hooks: [{ type: 'command', command: dir + '/cc-safety-gate.sh', timeout: 5 }] },
      { matcher: 'Read|Edit|Write', hooks: [{ type: 'command', command: dir + '/guard-large-files.sh', timeout: 5 }] }
    ],
    PermissionRequest: [{ matcher: '*', hooks: [{ type: 'command', command: dir + '/wait-notify.sh', timeout: 5 }] }],
    Notification: [{ matcher: '*', hooks: [{ type: 'command', command: dir + '/wait-notify.sh', timeout: 5 }] }],
    PostToolUse: [{ matcher: '*', hooks: [{ type: 'command', command: dir + '/cancel-wait.sh', timeout: 3 }] }],
    UserPromptSubmit: [{ matcher: '*', hooks: [{ type: 'command', command: dir + '/cancel-wait.sh', timeout: 3 }] }]
  }
};
fs.writeFileSync('/tmp/hooks-patch.json', JSON.stringify(hooks, null, 2));
console.log('OK');
"

# Deep merge
node "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" /tmp/hooks-patch.json "${SETTINGS}"
rm -f /tmp/hooks-patch.json
```

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

## Module Selection

All modules are enabled by default. If the user wants to disable specific modules, skip the corresponding hooks in step 4:

| Module | Skip hooks for... |
|--------|-------------------|
| Stop notification | `Stop` event |
| Safety gate | `PreToolUse` Bash matcher |
| Large file guard | `PreToolUse` Read\|Edit\|Write matcher |
| Wait notification | `PermissionRequest` + `Notification` events |
| Cancel wait | `PostToolUse` + `UserPromptSubmit` events |

## Updating

```bash
cd /tmp && git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cp /tmp/claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
rm -rf /tmp/claude-code-hooks
```

Config files (`notify.conf`, `secrets.env`) are never overwritten by updates.
