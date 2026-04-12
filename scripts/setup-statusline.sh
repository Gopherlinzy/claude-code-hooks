#!/usr/bin/env bash
# setup-statusline.sh — Claude Code Hooks statusline configuration helper
# 协助用户安装 claude-hud 并配置 OpenRouter 实时额度监控

set -uo pipefail

# ─── 颜色和日志 ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✅${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠️${NC}  $*"; }
err()   { echo -e "${RED}❌${NC} $*" >&2; }
step()  { echo -e "\n${CYAN}${BOLD}→${NC} ${BOLD}$*${NC}"; }

# ─── 常量 ───
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"

echo -e "${BOLD}🎨 Claude Code Hooks — Statusline Setup${NC}\n"

# ─── 步骤 1：检查 claude-hud 是否安装 ───
step "检查 claude-hud 插件..."

CLAUDE_HUD_DIR="${CLAUDE_DIR}/plugins/cache/claude-hud"
if [ -d "$CLAUDE_HUD_DIR" ] && [ -n "$(ls -d "$CLAUDE_HUD_DIR"/*/ 2>/dev/null | head -1)" ]; then
    ok "claude-hud 已安装"
    CLAUDE_HUD_LATEST=$(ls -d "${CLAUDE_HUD_DIR}"/*/ 2>/dev/null | sort -V | tail -1)
    info "版本目录: $CLAUDE_HUD_LATEST"
else
    warn "claude-hud 插件未找到"
    echo ""
    echo "  📝 claude-hud 是 Claude Code 的官方状态栏插件。"
    echo "  📝 它会在你下次启动 Claude Code 时自动安装。"
    echo ""
    read -p "  是否已安装 claude-hud？(y/N) " -r HAS_HUD
    if [[ ! "$HAS_HUD" =~ ^[Yy]$ ]]; then
        info "安装 claude-hud："
        echo "  1. 重启 Claude Code 桌面应用"
        echo "  2. claude-hud 会自动下载到 ${CLAUDE_HUD_DIR}"
        echo "  3. 之后再运行此脚本"
        exit 0
    fi
fi

# ─── 步骤 2：检查 openrouter-status.sh ───
step "检查 openrouter-status.sh..."

OPENROUTER_SCRIPT="${INSTALL_DIR}/statusline/openrouter-status.sh"
if [ -f "$OPENROUTER_SCRIPT" ]; then
    ok "openrouter-status.sh 已安装"
else
    err "未找到 $OPENROUTER_SCRIPT"
    echo "  请先运行: ./install.sh"
    exit 1
fi

# ─── 步骤 3：检查环境变量 ───
step "检查 OPENROUTER_API_KEY..."

if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    ok "OPENROUTER_API_KEY 已设置"
else
    warn "OPENROUTER_API_KEY 环境变量未设置"
    echo ""
    echo "  📝 获取 API Key："
    echo "  1. 访问 https://openrouter.ai/keys"
    echo "  2. 创建或复制你的 API Key"
    echo "  3. 添加到 shell 配置（~/.zshrc 或 ~/.bashrc）："
    echo ""
    echo "     export OPENROUTER_API_KEY='sk-or-v1-xxxxx...'"
    echo ""
    echo "  4. 重新加载 shell："
    echo ""
    echo "     source ~/.zshrc  # 或 source ~/.bashrc"
    echo ""
    read -p "  已添加到 shell 配置吗？(y/N) " -r HAS_KEY
    if [[ ! "$HAS_KEY" =~ ^[Yy]$ ]]; then
        info "配置后再运行此脚本"
        exit 0
    fi
fi

# ─── 步骤 4：检查 settings.json ───
step "检查 settings.json..."

if [ ! -f "$SETTINGS_FILE" ]; then
    warn "settings.json 不存在，将为您创建"
    mkdir -p "$CLAUDE_DIR"
    echo '{}' > "$SETTINGS_FILE"
fi

# ─── 步骤 5：生成 statusLine 配置 ───
step "生成 statusLine 配置..."

# 检查系统类型
case "$(uname -s)" in
    Darwin|Linux)
        NODE_CMD="/usr/local/bin/node"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        NODE_CMD="node"
        ;;
    *)
        NODE_CMD="node"
        ;;
esac

# 生成 statusLine JSON 配置
read -r -d '' STATUSLINE_CONFIG <<'EOF' || true
    "statusLine": {
      "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\\''{ print $(NF-1) \"\\\\t\" $(0) }'\\'' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); [ -z \"$plugin_dir\" ] && plugin_dir=\"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/claude-hud/claude-hud\"; exec \"${NODE_CMD}\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
      "type": "command"
    }
EOF

ok "配置已生成"

# ─── 步骤 6：提示用户如何在 settings.json 中添加配置 ───
echo ""
step "将配置添加到 ~/.claude/settings.json..."

echo ""
echo "  📋 请按以下步骤操作："
echo ""
echo "  1. 打开文本编辑器："
echo "     vim ~/.claude/settings.json"
echo ""
echo "  2. 在顶层 JSON 对象中添加以下配置（用逗号分隔）："
echo ""

# 输出配置片段，带格式化
cat << 'EOF'
{
  "hooks": { ... },
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print $(NF-1) \"\\t\" $(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"node\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
EOF

echo ""
echo "  💡 提示："
echo "  • 确保 OPENROUTER_API_KEY 已在你的 shell 环境变量中设置"
echo "  • JSON 格式正确（最后一个属性后不要有逗号）"
echo "  • 保存文件后，重启 Claude Code 生效"
echo ""

# ─── 步骤 7：快速验证 ───
step "快速验证..."

echo ""
if bash -n "$OPENROUTER_SCRIPT" 2>/dev/null; then
    ok "openrouter-status.sh 语法正确"
else
    err "openrouter-status.sh 有语法错误"
    exit 1
fi

if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version)
    ok "Node.js 已安装：$NODE_VERSION"
else
    warn "Node.js 未在 PATH 中找到（Claude Code 需要它）"
fi

# ─── 完成 ───
echo ""
echo -e "${GREEN}${BOLD}✅ 配置助手完成！${NC}"
echo ""
echo "  📝 后续步骤："
echo "  1. 编辑 ~/.claude/settings.json，添加 statusLine 配置"
echo "  2. 重启 Claude Code 桌面应用"
echo "  3. 状态栏右侧应该显示 OpenRouter 余额"
echo ""
echo "  🐛 如遇问题："
echo "  • 检查 OPENROUTER_API_KEY 是否设置：echo \$OPENROUTER_API_KEY"
echo "  • 检查 claude-hud 是否安装：ls ${CLAUDE_HUD_DIR}"
echo "  • 检查 settings.json 格式：此工具不会自动修改，请手动添加"
echo ""
