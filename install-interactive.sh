#!/usr/bin/env bash
# install-interactive.sh — Interactive module selector for claude-code-hooks
# Allows users to choose which scripts to install (core + optional + tools)

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === Helper Functions ===
print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  Claude Code Hooks — Interactive Installer               ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo -e "${YELLOW}$1${NC}"
    echo "───────────────────────────────────────────────────────────────"
}

print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-yes}"

    if [[ "$default" == "yes" ]]; then
        read -p "$prompt [Y/n]: " -n 1 -r
    else
        read -p "$prompt [y/N]: " -n 1 -r
    fi
    echo

    if [[ $REPLY =~ ^[Yy]$ ]] || ([[ -z "$REPLY" ]] && [[ "$default" == "yes" ]]); then
        return 0
    else
        return 1
    fi
}

# === Main Flow ===
print_header

# Step 1: Detect environment
print_section "Step 1: Detecting Environment"

REPO_PATH="${1:-.}"
if [ ! -d "$REPO_PATH/scripts" ]; then
    echo -e "${RED}Error: Not in claude-code-hooks directory${NC}"
    echo "Usage: $0 [path/to/claude-code-hooks]"
    exit 1
fi

OS_TYPE=$(uname -s)
case "$OS_TYPE" in
    Darwin) OS="macOS" ;;
    Linux) OS="Linux" ;;
    MINGW*|MSYS*|CYGWIN*) OS="Windows Git Bash" ;;
    *) OS="Unknown" ;;
esac

print_info "Detected OS: $OS"
print_info "Repository path: $REPO_PATH"

# Step 2: Present module selection
print_section "Step 2: Choose Modules to Install"

echo ""
echo "Select which modules you want to install:"
echo ""

# Core modules (always selected)
echo -e "${GREEN}[REQUIRED]${NC} Core Hooks (5 scripts) — Essential security & notifications"
echo "  • cc-stop-hook.sh          → Task completion notifications"
echo "  • cc-safety-gate.sh        → Bash command security gate (23+ patterns)"
echo "  • wait-notify.sh           → Permission request reminders"
echo "  • cancel-wait.sh           → Cancel notification when you respond"
echo "  • guard-large-files.sh     → Prevent reading large/auto-gen files"
INSTALL_CORE=true
print_info "Will install core hooks"

echo ""
echo -e "${YELLOW}[OPTIONAL]${NC} Extended Hooks (5 scripts) — Advanced security"
if prompt_yes_no "Install extended security hooks?"; then
    echo "  ✓ Configuration protection (config-change-guard.sh)"
    echo "  ✓ MCP tool safety (mcp-guard.sh)"
    echo "  ✓ Prompt injection detection (injection-scan.sh)"
    echo "  ✓ Project file protection (project-context-guard.sh)"
    echo "  ✓ Cost summary display (openrouter-cost-summary.sh)"
    INSTALL_EXTENDED=true
else
    print_warning "Skipping extended hooks"
    INSTALL_EXTENDED=false
fi

echo ""
echo -e "${YELLOW}[OPTIONAL]${NC} Standalone Tools (5 scripts) — Manual/periodic tasks"
if prompt_yes_no "Install standalone tools?"; then
    echo "  ✓ Process cleanup (reap-orphans.sh)"
    echo "  ✓ Task dispatch (dispatch-claude.sh)"
    echo "  ✓ Status check (check-claude-status.sh)"
    echo "  ✓ Skill indexing (generate-skill-index.sh)"
    echo "  ✓ Notification library (send-notification.sh)"
    INSTALL_TOOLS=true
else
    print_warning "Skipping standalone tools"
    INSTALL_TOOLS=false
fi

echo ""
echo -e "${YELLOW}[OPTIONAL]${NC} OpenRouter Statusline Integration"
if prompt_yes_no "Setup OpenRouter credit monitoring in statusline?"; then
    INSTALL_STATUSLINE=true
    echo "  ✓ Will configure claude-hud plugin with OpenRouter display"
else
    print_warning "Skipping statusline setup"
    INSTALL_STATUSLINE=false
fi

# Step 3: Summary
print_section "Step 3: Installation Summary"

echo ""
echo "Modules to install:"
echo "  ✓ Core hooks (required)                   5 scripts"
[ "$INSTALL_EXTENDED" = true ] && echo "  ✓ Extended hooks (optional)                5 scripts" || echo "  • Extended hooks (skipped)"
[ "$INSTALL_TOOLS" = true ] && echo "  ✓ Standalone tools (optional)              5 scripts" || echo "  • Standalone tools (skipped)"
[ "$INSTALL_STATUSLINE" = true ] && echo "  ✓ OpenRouter statusline (optional)" || echo "  • OpenRouter statusline (skipped)"

echo ""
echo "Installation destination:"
echo "  ~/.claude/scripts/claude-hooks/"
echo "  ~/.cchooks/                    (config & logs)"

echo ""
if ! prompt_yes_no "Proceed with installation?"; then
    echo -e "${YELLOW}Installation cancelled.${NC}"
    exit 0
fi

# Step 4: Run actual installation
print_section "Step 4: Installing"

INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
mkdir -p "${INSTALL_DIR}"

# Copy core scripts
print_info "Installing core hooks..."
for script in cc-stop-hook.sh cc-safety-gate.sh wait-notify.sh cancel-wait.sh guard-large-files.sh; do
    cp "$REPO_PATH/scripts/$script" "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/$script"
done

# Copy libraries (always needed)
print_info "Installing libraries..."
for lib in common.sh platform-shim.sh send-notification.sh; do
    cp "$REPO_PATH/scripts/$lib" "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/$lib"
done

# Copy extended hooks if selected
if [ "$INSTALL_EXTENDED" = true ]; then
    print_info "Installing extended hooks..."
    for script in config-change-guard.sh mcp-guard.sh injection-scan.sh project-context-guard.sh openrouter-cost-summary.sh; do
        cp "$REPO_PATH/scripts/$script" "${INSTALL_DIR}/"
        chmod +x "${INSTALL_DIR}/$script"
    done
fi

# Copy tools if selected
if [ "$INSTALL_TOOLS" = true ]; then
    print_info "Installing standalone tools..."
    for script in reap-orphans.sh dispatch-claude.sh check-claude-status.sh generate-skill-index.sh setup-statusline.sh; do
        cp "$REPO_PATH/scripts/$script" "${INSTALL_DIR}/"
        chmod +x "${INSTALL_DIR}/$script"
    done
fi

# Copy tools
print_info "Installing utilities..."
cp "$REPO_PATH/tools/merge-hooks.js" "${INSTALL_DIR}/"
cp "$REPO_PATH/tools/select-modules.js" "${INSTALL_DIR}/"

# Setup statusline if requested
if [ "$INSTALL_STATUSLINE" = true ]; then
    print_info "Setting up OpenRouter statusline..."
    mkdir -p "${INSTALL_DIR}/statusline"
    cp "$REPO_PATH/tools/statusline/run-hud.sh" "${INSTALL_DIR}/statusline/"
    cp "$REPO_PATH/tools/statusline/openrouter-statusline.js" "${INSTALL_DIR}/statusline/"
    chmod +x "${INSTALL_DIR}/statusline"/*.sh
fi

# Step 5: Merge hooks into settings.json
print_section "Step 5: Configuring Settings"

SETTINGS="${HOME}/.claude/settings.json"

# Generate hooks patch dynamically
PATCH_FILE="${TMPDIR:-${TEMP:-/tmp}}/hooks-patch.json"
mkdir -p "$(dirname "$PATCH_FILE")"

# Windows detection
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) CMD_PREFIX="bash " ;;
    *)                     CMD_PREFIX="" ;;
esac

# Build hooks JSON
node -e "
const fs = require('fs');
const path = require('path');

const dir = '${INSTALL_DIR}'.replace(/\\\\/g, '/');
const prefix = '${CMD_PREFIX}';
const cmd = (script) => prefix + path.join('${INSTALL_DIR}', script).replace(/\\\\/g, '/');

const hooks = {
  hooks: {
    Stop: [{matcher: '*', hooks: [{type: 'command', command: cmd('cc-stop-hook.sh'), timeout: 15}]}],
    PreToolUse: [
      {matcher: 'Bash', hooks: [{type: 'command', command: cmd('cc-safety-gate.sh'), timeout: 5}]},
      {matcher: 'Read|Edit|Write', hooks: [{type: 'command', command: cmd('guard-large-files.sh'), timeout: 5}]}
    ],
    PermissionRequest: [{matcher: '*', hooks: [{type: 'command', command: cmd('wait-notify.sh'), timeout: 5}]}],
    Notification: [{matcher: '*', hooks: [{type: 'command', command: cmd('wait-notify.sh'), timeout: 5}]}],
    PostToolUse: [{matcher: '*', hooks: [{type: 'command', command: cmd('cancel-wait.sh'), timeout: 3}]}],
    UserPromptSubmit: [{matcher: '*', hooks: [{type: 'command', command: cmd('cancel-wait.sh'), timeout: 3}]}]
  }
};

fs.writeFileSync('${PATCH_FILE}', JSON.stringify(hooks, null, 2));
console.log('OK');
"

# Merge hooks
print_info "Merging hooks into settings.json..."
node "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" "${PATCH_FILE}" "${SETTINGS}"
rm -f "${PATCH_FILE}"

# Step 6: Create config files
print_section "Step 6: Configuration Files"

mkdir -p "${HOME}/.cchooks/logs"

# Create notify.conf if missing
if [ ! -f "${INSTALL_DIR}/notify.conf" ]; then
    print_info "Creating notify.conf template..."
    cat > "${INSTALL_DIR}/notify.conf" << 'CONFEOF'
# Claude Code Hooks Notification Configuration
# Copy appropriate credentials from ~/.cchooks/secrets.env

CC_NOTIFY_BACKEND=auto
CC_NOTIFY_TARGET=""
CC_WAIT_NOTIFY_SECONDS=30
CC_NOTIFY_CHANNEL="feishu"

# Add backend URLs or credentials below (or use ~/.cchooks/secrets.env)
# Example:
# NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx
CONFEOF
    chmod 600 "${INSTALL_DIR}/notify.conf"
fi

# Step 7: Verify installation
print_section "Step 7: Verification"

ERRORS=0
for script in cc-stop-hook.sh cc-safety-gate.sh wait-notify.sh cancel-wait.sh guard-large-files.sh common.sh platform-shim.sh; do
    if [ -x "${INSTALL_DIR}/$script" ]; then
        print_info "$script ✓"
    else
        echo -e "${RED}✗${NC} $script - NOT FOUND"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ -f "${SETTINGS}" ]; then
    if python3 -c "import json; json.load(open('${SETTINGS}'))" 2>/dev/null; then
        print_info "settings.json is valid ✓"
    else
        echo -e "${RED}✗${NC} settings.json has JSON errors"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Step 8: Setup optional components
if [ "$INSTALL_EXTENDED" = true ]; then
    read -p "Would you like to enable extended hooks now? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Extended hooks are installed but DISABLED by default."
        print_info "To enable, add them to settings.json hooks manually."
        print_info "See documentation for examples."
    fi
fi

if [ "$INSTALL_TOOLS" = true ] && grep -q "reap-orphans.sh" "${INSTALL_DIR}/reap-orphans.sh" 2>/dev/null; then
    read -p "Would you like to setup automatic reap-orphans scheduling? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "To setup automatic cleanup scheduling on macOS, run:"
        echo "  launchctl load ~/Library/LaunchAgents/com.cchooks.reaper.plist"
        echo ""
        print_info "For Linux, add to crontab:"
        echo "  0 2 * * * ~/.claude/scripts/claude-hooks/reap-orphans.sh"
    fi
fi

# Final summary
print_section "Installation Complete! 🎉"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All modules installed successfully!${NC}"
else
    echo -e "${YELLOW}⚠ Some issues detected. Please review above.${NC}"
fi

echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to load new settings"
echo "  2. Configure notify.conf with your notification backend"
echo "  3. See README.md or CLAUDE-SCRIPTS-REFERENCE.md for full documentation"
echo ""
echo "Quick commands:"
[ "$INSTALL_TOOLS" = true ] && echo "  • Check task status: check-claude-status.sh"
[ "$INSTALL_TOOLS" = true ] && echo "  • Dispatch task: dispatch-claude.sh 'command'"
[ "$INSTALL_TOOLS" = true ] && echo "  • Clean processes: reap-orphans.sh"
echo ""
