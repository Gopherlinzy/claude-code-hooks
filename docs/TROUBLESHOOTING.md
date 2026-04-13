# 🔧 Claude Code Hooks Troubleshooting Guide

> This guide covers common installation and runtime issues, with deep diagnostics for Windows Git Bash users.
>
> **Version:** v1.0.1 | **Updated:** 2026-04-13

## Table of Contents

- [Installation Failures](#installation-failures)
- [Windows Git Bash Specific](#windows-git-bash-specific)
- [Hooks Not Firing](#hooks-not-firing)
- [StatusLine Command Errors](#statusline-command-errors)
- [Recovery & Rollback](#recovery--rollback)
- [Reporting Issues](#reporting-issues)

---

## Installation Failures

### "ENOENT: no such file or directory" Error

**Symptom:** Installation fails with file not found during hook merge.

```
Error: ENOENT: no such file or directory, open '/tmp/hooks-patch.json'
  at Object.openSync (fs.js:xxx:xxx)
```

**Diagnosis:**
1. Check if `/tmp` directory exists:
   ```bash
   ls -ld /tmp
   ```

2. On Windows Git Bash, check if `/tmp` is accessible:
   ```bash
   # Should show path like /tmp or D:\tmp
   echo $TMPDIR
   echo $TEMP
   ```

3. Verify the installation directory path has no spaces:
   ```bash
   echo "$HOME/.claude/scripts/claude-hooks"
   ```

**Solutions:**

- **On Linux/macOS:** Ensure `/tmp` exists and is writable:
  ```bash
  mkdir -p /tmp && chmod 1777 /tmp
  ```

- **On Windows Git Bash:** Create temp directory:
  ```bash
  mkdir -p /tmp
  ```

- **If home directory has spaces:** Reinstall to a path without spaces, or use the manual installation method from README.md.

---

### "Command not found: node" Error

**Symptom:** Installer fails because Node.js is not in PATH.

```
node: not found
```

**Diagnosis:**
1. Check if Node.js is installed:
   ```bash
   which node
   node --version
   ```

2. If `which node` returns nothing, Node.js is not in PATH.

3. Check common installation locations:
   - **Windows:** `C:\Program Files\nodejs`
   - **macOS (homebrew):** `/usr/local/bin/node`
   - **Linux:** Various locations depending on package manager

**Solutions:**

- **Install Node.js 18+:** Follow the official [nodejs.org](https://nodejs.org/) instructions for your platform.

- **Add Node.js to PATH (if already installed):**
  ```bash
  # On macOS/Linux, add to ~/.bashrc or ~/.zshrc:
  export PATH="/usr/local/bin:$PATH"
  
  # Then reload:
  source ~/.bashrc
  ```

- **Windows Git Bash:** Node.js should be auto-detected. If not:
  ```bash
  # Verify installation
  "C:\Program Files\nodejs\node.exe" --version
  
  # Add to PATH if needed in git-bash.exe shortcut properties
  # Environment: PATH=C:\Program Files\nodejs;%PATH%
  ```

---

### Settings.json Merge Fails

**Symptom:** Installer aborts with JSON parsing or merge error.

```
SyntaxError: Unexpected token } in JSON at position 123
```

**Diagnosis:**
1. Check if settings.json exists and is valid JSON:
   ```bash
   python3 -m json.tool ~/.claude/settings.json
   ```

2. Look for common JSON errors:
   - Trailing commas
   - Missing closing braces
   - Unescaped quotes in strings

**Solution:**
- Manually fix the JSON syntax, or
- Start fresh:
  ```bash
  # Backup existing
  cp ~/.claude/settings.json ~/.claude/settings.json.broken
  
  # Create new
  echo '{}' > ~/.claude/settings.json
  
  # Re-run installer
  ./install.sh
  ```

---

## Windows Git Bash Specific

### Bug #1: Node.js Path Escaping (v1.0.1)

**Affected:** Windows Git Bash users installing statusline configuration  
**Status:** ✅ Fixed in v1.0.1

**Problem:** Inline Node.js scripts in statusline configuration had unescaped POSIX paths that Node.js on Windows couldn't interpret.

**Example of broken command:**
```bash
# Before v1.0.1: Node.js sees Windows path as directory separator issues
node -e "const fs = require('fs'); 
  const path = '${HOME}/.claude/plugins/cache/claude-hud/...';
  fs.readFileSync(path); // Node.js tries D:\Users\..., gets confused"
```

**What was fixed:**
- Proper escaping of paths in inline scripts
- Platform detection (MINGW/MSYS/CYGWIN) to use native Node.js vs bash node
- JSON escaping for Windows path separators

**How to verify you're on v1.0.1+:**
```bash
grep "v1.0.1" ~/.claude/scripts/claude-hooks/setup-statusline.sh
```

**If you installed before v1.0.1:**
1. Update scripts:
   ```bash
   ./install.sh --update
   ```

2. Re-run statusline setup:
   ```bash
   ~/.claude/scripts/claude-hooks/setup-statusline.sh
   ```

---

### Bug #2: StatusLine Command Cascading Quotes (v1.0.1)

**Affected:** Windows Git Bash users with statusline enabled  
**Status:** ✅ Fixed in v1.0.1

**Problem:** Quote escaping was nested 4+ layers deep in bash/Node.js command chains, causing syntax errors:

```bash
# Before v1.0.1: Quote hell
bash -c 'node ... --extra-cmd "bash -c '\''"nested"\'\'""'
# Too many quotes! → Syntax error in subprocess
```

**Symptoms:**
- StatusLine command fails to parse
- Error: `Unexpected token '` or similar
- StatusLine display shows nothing or error message

**What was fixed:**
- Unified quote escaping strategy across bash→node→bash chains
- Used consistent single-quote wrapping with proper `'\''` escaping
- Platform-specific command generation for Windows vs Unix

**Manual fix (if upgrading from v1.0.0):**
1. Check your settings.json statusLine command:
   ```bash
   grep -A5 '"statusLine"' ~/.claude/settings.json
   ```

2. Look for deeply nested quotes. If it looks like quote soup, update:
   ```bash
   ./install.sh --update
   ~/.claude/scripts/claude-hooks/setup-statusline.sh
   ```

3. Compare the new command against the README.md example for your OS.

---

### Bug #3: Large File Guard Slowness (Known Limitation)

**Affected:** All Windows users with large repos  
**Status:** 🟡 Known limitation (not a bug, by design)

**Problem:** `guard-large-files.sh` reads directory statistics recursively, which is slow on Windows networks due to NTFS performance characteristics.

**Symptoms:**
- First Read/Edit/Write operation takes 5-10 seconds
- Subsequent operations are normal
- Only affects Windows (macOS/Linux are fast)

**Why this happens:**
- `find` command must traverse entire directory tree
- NTFS on Windows has slower syscalls than ext4/APFS
- Network storage (e.g., WSL2 mounts) exacerbates the issue

**Workaround options:**

**Option 1: Disable the guard (if you're careful)**
```bash
# Edit ~/.claude/settings.json
# Remove the PreToolUse guard-large-files.sh entry
vim ~/.claude/settings.json

# Remove this block:
# "PreToolUse": [
#   { "matcher": "Read|Edit|Write", "hooks": [...guard-large-files.sh...] }
# ]
```

**Option 2: Exclude directories from scanning**
```bash
# Edit ~/.claude/scripts/claude-hooks/safety-rules.conf
# Add these patterns (if file doesn't exist, create it):
cat >> ~/.claude/scripts/claude-hooks/safety-rules.conf << 'EOF'
# Exclude patterns (one per line, shell globs)
node_modules/*
.git/*
vendor/*
dist/*
build/*
target/*
EOF
```

**Option 3: Use WSL2 instead of Git Bash**
- WSL2 provides native Linux filesystem speed
- All hooks work optimally on WSL2

**Monitoring startup time:**
```bash
# Profile hook execution (v1.0.1+)
# Check audit logs:
tail -100 ~/.cchooks/logs/hooks-audit.jsonl | grep guard-large-files
```

---

## Hooks Not Firing

### Checklist: Why Your Hooks Aren't Working

Before assuming a bug, verify these in order:

#### 1. Verify hooks are registered in settings.json

```bash
python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
    hooks = s.get('hooks', {})
    print(f'Registered events: {list(hooks.keys())}')
    for event, matchers in hooks.items():
        print(f'  {event}: {len(matchers)} matcher(s)')
"
```

Expected output should show: Stop, PreToolUse, PermissionRequest, Notification, PostToolUse, UserPromptSubmit

#### 2. Restart Claude Code

Hooks are loaded at session start. If you just updated settings.json:
1. Close Claude Code completely (all windows)
2. Wait 5 seconds
3. Reopen Claude Code

#### 3. Check script permissions

```bash
# All scripts should be executable (-x)
ls -la ~/.claude/scripts/claude-hooks/*.sh | head -5
```

Expected: `-rwxr-xr-x` (executable for all)

If not executable:
```bash
chmod +x ~/.claude/scripts/claude-hooks/*.sh
```

#### 4. Verify scripts are reachable

```bash
# Each script should run without errors
bash -n ~/.claude/scripts/claude-hooks/cc-stop-hook.sh
bash -n ~/.claude/scripts/claude-hooks/cc-safety-gate.sh
bash -n ~/.claude/scripts/claude-hooks/wait-notify.sh

# If syntax errors, check recent updates
```

#### 5. Check timeout settings

If a hook times out, it fails silently. Default timeouts:
- PreToolUse: 5 seconds
- Stop: 15 seconds
- PermissionRequest/Notification: 5 seconds
- PostToolUse/UserPromptSubmit: 3 seconds

If your system is slow, increase in settings.json:
```json
{
  "hooks": {
    "Stop": [{ 
      "matcher": "*", 
      "hooks": [{ 
        "type": "command", 
        "command": "~/.claude/scripts/claude-hooks/cc-stop-hook.sh", 
        "timeout": 30
      }] 
    }]
  }
}
```

#### 6. Check audit logs

Hooks write diagnostic logs:
```bash
# View recent hook executions
tail -20 ~/.cchooks/logs/hooks-audit.jsonl | python3 -m json.tool

# Filter by event type
grep '"event":"Stop"' ~/.cchooks/logs/hooks-audit.jsonl | tail -5
```

Look for `"status": "error"` entries to see what failed.

---

### notify.conf Missing or Invalid

**Problem:** Notifications aren't being sent, or hooks crash silently.

**Check if notify.conf exists:**
```bash
cat ~/.claude/scripts/claude-hooks/notify.conf
```

**If file doesn't exist or is incomplete:**

1. Create or update notify.conf:
   ```bash
   cat > ~/.claude/scripts/claude-hooks/notify.conf << 'EOF'
   CC_NOTIFY_BACKEND=auto
   CC_WAIT_NOTIFY_SECONDS=30
   CC_NOTIFY_CHANNEL="feishu"
   # CC_SLACK_WEBHOOK_URL=
   # NOTIFY_FEISHU_URL=
   # CC_TELEGRAM_BOT_TOKEN=
   # CC_TELEGRAM_CHAT_ID=
   # CC_BARK_URL=
   EOF
   chmod 644 ~/.claude/scripts/claude-hooks/notify.conf
   ```

2. Add your backend credentials:
   ```bash
   # Option A: In notify.conf (less secure)
   echo "NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN" \
     >> ~/.claude/scripts/claude-hooks/notify.conf
   
   # Option B: In secrets.env (recommended, v1.0.1+)
   mkdir -p ~/.cchooks
   cat > ~/.cchooks/secrets.env << 'EOF'
   NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
   EOF
   chmod 600 ~/.cchooks/secrets.env
   ```

3. Test notifications:
   ```bash
   ~/.claude/scripts/claude-hooks/send-notification.sh "Test message"
   ```

---

## StatusLine Command Errors

### StatusLine Not Displaying

**Symptoms:**
- Statusline appears blank where credits should show
- No error messages in Claude Code

**Step 1: Verify claude-hud is installed**

```bash
ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/
```

Should show at least one version directory. If empty:
1. Restart Claude Code (forces plugin cache refresh)
2. Wait 30 seconds
3. Check again

**Step 2: Test statusLine command manually**

Extract the command from settings.json and run it:

```bash
# Get the statusLine command
grep -A2 '"statusLine"' ~/.claude/settings.json | tail -1

# Run it manually (paste the command value):
bash -c 'plugin_dir=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\'{ print $(NF-1) "\t" $(0) }'\'  | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec node "${plugin_dir}dist/index.js" --extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh"'
```

**Step 3: Test the openrouter-status.sh script directly**

```bash
# Test script syntax
bash -n ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh

# Run it directly (requires OPENROUTER_API_KEY set)
export OPENROUTER_API_KEY="sk-or-v1-..."
bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh
```

Expected output: JSON with `balance` and `used` fields

**Step 4: Verify OPENROUTER_API_KEY is set**

```bash
# Check if environment variable is set
echo $OPENROUTER_API_KEY

# If empty, add to ~/.bashrc or ~/.zshrc:
echo 'export OPENROUTER_API_KEY="sk-or-v1-..."' >> ~/.bashrc
source ~/.bashrc
```

---

### OpenRouter Authentication Fails

**Symptoms:**
- statusline shows "Auth error" or "401"
- Script output contains "Unauthorized"

**Diagnosis:**

1. Verify API key format:
   ```bash
   echo $OPENROUTER_API_KEY
   # Should start with: sk-or-v1-
   ```

2. Test API key directly:
   ```bash
   curl -s "https://api.openrouter.ai/api/v1/auth/key" \
     -H "Authorization: Bearer $OPENROUTER_API_KEY" \
     -H "HTTP-Referer: https://github.com/Gopherlinzy/claude-code-hooks"
   ```

   Should return JSON with `data.limit` field, not an error.

3. Check if using fallback (ANTHROPIC_AUTH_TOKEN):
   ```bash
   # statusline tries OPENROUTER_API_KEY first, then ANTHROPIC_AUTH_TOKEN
   echo $ANTHROPIC_AUTH_TOKEN
   ```

**Solution:**

- Get a fresh API key from [openrouter.ai/keys](https://openrouter.ai/keys)
- Ensure it's set correctly:
  ```bash
  export OPENROUTER_API_KEY="sk-or-v1-YOUR_NEW_KEY"
  
  # Verify
  echo $OPENROUTER_API_KEY
  ```
- Restart Claude Code to reload environment

---

### StatusLine Command Parse Errors on Windows

**Symptom:** Settings.json is valid but statusLine command has quote issues.

See [Bug #2: StatusLine Command Cascading Quotes](#bug-2-statusline-command-cascading-quotes-v101) above.

**Quick fix:**
```bash
./install.sh --update
~/.claude/scripts/claude-hooks/setup-statusline.sh
```

---

## Recovery & Rollback

### Automatic Backup Recovery

**When:** Every time you run `./install.sh`, a backup is created.

**View available backups:**
```bash
ls -lh ~/.claude/settings.json.bak.*
```

**Restore from a specific backup:**
```bash
# List backups with timestamps
ls -lh ~/.claude/settings.json.bak.* | awk '{print $9, $6, $7, $8}'

# Restore a specific one
cp ~/.claude/settings.json.bak.1712345678 ~/.claude/settings.json
```

**Clean up old backups:**
```bash
# Keep only 5 newest, delete older
ls -t ~/.claude/settings.json.bak.* | tail -n +6 | xargs rm -f
```

---

### Manual Recovery

**If installation failed halfway and backups are lost:**

**Option 1: Restore from version control (if you checked in settings.json)**
```bash
git checkout ~/.claude/settings.json
```

**Option 2: Start fresh**
```bash
# Remove all hook configurations
rm ~/.claude/settings.json

# Recreate minimal config
echo '{"hooks":{}}' > ~/.claude/settings.json

# Re-run installer
./install.sh --non-interactive
```

**Option 3: Hand-edit settings.json to remove bad hooks**
```bash
# Open in editor
vim ~/.claude/settings.json

# Manually remove malformed hook entries in the "hooks" object
# Ensure valid JSON (no trailing commas, balanced braces)

# Validate syntax
python3 -m json.tool ~/.claude/settings.json > /dev/null && echo "OK"
```

---

### Complete Uninstall

**Remove all traces of claude-code-hooks:**

```bash
# Option 1: Keep config (in case you reinstall later)
./install.sh --uninstall

# Option 2: Nuclear option (remove everything including logs and config)
./install.sh --uninstall --purge
```

**What gets removed:**

With `--uninstall`:
- Scripts: `~/.claude/scripts/claude-hooks/`
- Hook registrations in settings.json

With `--uninstall --purge` (also removes):
- Configuration: `notify.conf`, `safety-rules.conf`
- Logs: `~/.cchooks/logs/hooks-audit.jsonl`
- Secrets: `~/.cchooks/secrets.env`

**Manual cleanup (if installer doesn't work):**
```bash
rm -rf ~/.claude/scripts/claude-hooks
rm -rf ~/.cchooks

# Remove hook registrations from settings.json manually
# (open in editor, delete the "hooks" object)
```

---

### Reverting to a Previous Version

**If v1.0.1 has a regression and you need v1.0.0:**

```bash
cd /path/to/claude-code-hooks
git log --oneline | grep -E 'v1\.0\.[01]'

# Check out specific version tag
git checkout v1.0.0

# Reinstall from that version
./install.sh --update
```

---

## Reporting Issues

### Before Opening an Issue

**Run this diagnostic script to gather information:**

```bash
# Save as ~/diagnose-hooks.sh
cat > ~/diagnose-hooks.sh << 'EOF'
#!/bin/bash
set -e

echo "=== Claude Code Hooks Diagnostics ==="
echo "Date: $(date -Iseconds)"
echo ""

# System info
echo "## System"
echo "OS: $(uname -s)"
echo "Shell: $SHELL"
echo "Bash version: $BASH_VERSION"
echo ""

# Installation
echo "## Installation Status"
if [ -d ~/.claude/scripts/claude-hooks ]; then
    echo "✅ Scripts installed"
    ls -1 ~/.claude/scripts/claude-hooks/*.sh | wc -l | xargs echo "Scripts count:"
else
    echo "❌ Scripts not found"
fi

if [ -f ~/.claude/settings.json ]; then
    echo "✅ settings.json exists"
    python3 -c "import json; s=json.load(open('$HOME/.claude/settings.json')); print(f'Hooks registered: {len(s.get(\"hooks\",{}))} events')" 2>/dev/null || echo "⚠️  Invalid JSON"
else
    echo "❌ settings.json not found"
fi

echo ""

# Verify scripts
echo "## Script Syntax Check"
for script in ~/.claude/scripts/claude-hooks/*.sh; do
    if bash -n "$script" 2>/dev/null; then
        echo "✅ $(basename $script)"
    else
        echo "❌ $(basename $script) — syntax error"
    fi
done
echo ""

# Notification config
echo "## Notification Config"
if [ -f ~/.claude/scripts/claude-hooks/notify.conf ]; then
    echo "✅ notify.conf exists"
    grep -E '^[A-Z_]+=' ~/.claude/scripts/claude-hooks/notify.conf | head -3
else
    echo "❌ notify.conf not found"
fi
echo ""

# Audit logs (last 3 errors)
echo "## Recent Errors"
if [ -f ~/.cchooks/logs/hooks-audit.jsonl ]; then
    grep '"status":"error"' ~/.cchooks/logs/hooks-audit.jsonl | tail -3 | python3 -m json.tool 2>/dev/null || tail -3
else
    echo "No audit logs found"
fi
echo ""

echo "End of diagnostics"
EOF

chmod +x ~/diagnose-hooks.sh
~/diagnose-hooks.sh
```

### GitHub Issue Template

**When creating an issue, include this information:**

```markdown
## Issue Summary
[One sentence describing the problem]

## System Info
- OS: [macOS / Linux / Windows Git Bash / WSL2]
- Bash version: [output of `bash --version`]
- Node version: [output of `node --version`]
- Shell: [bash / zsh / other]

## Steps to Reproduce
1. [Step 1]
2. [Step 2]
3. [etc.]

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Error Output
```
[Paste error message here]
```

## Diagnostic Info
[Output of the diagnostic script above]

## Additional Context
[Any other relevant info: recent changes, custom configs, etc.]
```

### Where to Report

- **GitHub Issues:** [Gopherlinzy/claude-code-hooks](https://github.com/Gopherlinzy/claude-code-hooks/issues)
- **Include:** OS, Bash version, exact error message, diagnostic output
- **Logs:** Share last 10 lines of `~/.cchooks/logs/hooks-audit.jsonl` if relevant

---

## FAQ

### Q: My hooks are slow. How can I speed them up?

**A:** Common performance issues:

1. **Large file guard is slow on Windows:** See [Bug #3](#bug-3-large-file-guard-slowness-known-limitation)
2. **Notification backend timeout:** Increase in settings.json
3. **Script is genuinely slow:** Check hook audit logs for execution time
   ```bash
   grep '"script":"cc-stop-hook"' ~/.cchooks/logs/hooks-audit.jsonl | tail -1
   ```

### Q: Where do notification credentials go?

**A:** Two options:

1. **Secrets file (recommended for v1.0.1+):**
   ```bash
   mkdir -p ~/.cchooks
   echo 'NOTIFY_FEISHU_URL=...' > ~/.cchooks/secrets.env
   chmod 600 ~/.cchooks/secrets.env
   ```

2. **notify.conf (less secure):**
   ```bash
   echo 'NOTIFY_FEISHU_URL=...' >> ~/.claude/scripts/claude-hooks/notify.conf
   ```

### Q: How do I disable a specific hook?

**A:** Edit `~/.claude/settings.json` and remove the hook entry:

```json
{
  "hooks": {
    "Stop": [
      // Remove this if you don't want stop notifications
    ]
  }
}
```

### Q: Can I use claude-code-hooks with WSL2?

**A:** Yes! WSL2 is fully supported and recommended for Windows users.

- Install hooks inside WSL2
- All scripts work optimally
- No Git Bash quirks

### Q: What's the difference between v1.0.0 and v1.0.1?

**A:** v1.0.1 (2026-04-12) fixed 4 P0 bugs:
- Windows path escaping in statusline (Bug #1)
- StatusLine command quote escaping (Bug #2)
- Feishu signature generation
- macOS find compatibility

See [CHANGELOG.md](../CHANGELOG.md) for details.

---

## Advanced Debugging

### Enable Verbose Logging

Some scripts support debug mode:

```bash
# Run a hook with debug output
DEBUG=1 bash ~/.claude/scripts/claude-hooks/cc-safety-gate.sh

# Or set globally
export DEBUG=1
```

### Check Environment at Hook Runtime

Hooks run in a subprocess with a clean environment. To debug:

```bash
# Create a test hook that dumps environment
cat > /tmp/debug-hook.sh << 'EOF'
#!/bin/bash
{
  echo "USER: $USER"
  echo "HOME: $HOME"
  echo "PATH: $PATH"
  echo "PWD: $PWD"
  env | sort
} >> /tmp/hook-env.txt
exit 0
EOF
chmod +x /tmp/debug-hook.sh

# Add to settings.json temporarily
# Then run Claude Code and check /tmp/hook-env.txt
```

### Trace Bash Script Execution

```bash
# Run a script with full trace
bash -x ~/.claude/scripts/claude-hooks/wait-notify.sh

# Output goes to stderr, capture with:
bash -x ~/.claude/scripts/claude-hooks/wait-notify.sh 2>&1 | head -50
```

### Monitor Hooks in Real-Time

```bash
# Watch audit log as hooks fire
tail -f ~/.cchooks/logs/hooks-audit.jsonl | python3 -m json.tool

# Or filter by event
watch 'grep "Stop" ~/.cchooks/logs/hooks-audit.jsonl | tail -5'
```

---

## Common Error Messages

| Error | Meaning | Fix |
|-------|---------|-----|
| `ENOENT: no such file` | File/dir not found | Check path exists, permissions |
| `Command not found: node` | Node.js not in PATH | Install Node.js 18+ or add to PATH |
| `SyntaxError in JSON` | Invalid settings.json | Validate with `python3 -m json.tool` |
| `timeout` | Hook took too long | Increase timeout in settings.json |
| `401 Unauthorized` | API key invalid | Check OPENROUTER_API_KEY set correctly |
| `Too many open quotes` | Quote escaping broken | Run `./install.sh --update` |
| `Cannot access /tmp` | Temp dir not writable | Create or fix permissions: `mkdir -p /tmp` |

---

**Last Updated:** 2026-04-13 | **Maintainer:** [@Gopherlinzy](https://github.com/Gopherlinzy)
