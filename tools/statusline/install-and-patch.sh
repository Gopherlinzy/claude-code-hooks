#!/bin/bash
#
# claude-hud 补丁安装脚本
# 一键安装补丁文件并应用修复
#
# 用法：
#   ./install-and-patch.sh            # 安装到 ~/.claude/scripts/claude-hooks/statusline/
#   ./install-and-patch.sh /custom/dir # 安装到自定义目录

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${1:-${HOME}/.claude/scripts/claude-hooks/statusline}"

echo "🔧 Claude HUD StatusLine Patch Installer"
echo ""

# 检查依赖
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Please install Node.js 18+ first:"
    echo "   https://nodejs.org/"
    exit 1
fi

echo "✅ Node.js found: $(node --version)"

# 检查 claude-hud 是否安装
CLAUDE_HUD_PLUGIN_DIR="${HOME}/.claude/plugins/cache/claude-hud/claude-hud"
if [[ ! -d "$CLAUDE_HUD_PLUGIN_DIR" ]]; then
    echo "❌ claude-hud plugin not found"
    echo ""
    echo "Please install claude-hud first:"
    echo "  1. /plugin marketplace add jarrodwatts/claude-hud"
    echo "  2. /plugin install claude-hud"
    echo "  3. /claude-hud:setup"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo "✅ claude-hud found at: $CLAUDE_HUD_PLUGIN_DIR"
echo ""

# 创建安装目录
mkdir -p "$INSTALL_DIR"
echo "📁 Creating directory: $INSTALL_DIR"

# 复制补丁脚本
echo "📝 Installing patch scripts..."

files=(
    "patch-stdin-inline.js"
    "patch-claude-hud.sh"
    "PATCH_GUIDE.md"
)

for file in "${files[@]}"; do
    src="$SCRIPT_DIR/$file"
    dst="$INSTALL_DIR/$file"

    if [[ ! -f "$src" ]]; then
        echo "⚠️  $file not found in $SCRIPT_DIR"
        continue
    fi

    cp "$src" "$dst"
    chmod +x "$dst" 2>/dev/null || true
    echo "   ✅ $file"
done

echo ""
echo "✅ Installation complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Next: Apply the patch"
echo ""
echo "   node $INSTALL_DIR/patch-stdin-inline.js --apply"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📖 Documentation: $INSTALL_DIR/PATCH_GUIDE.md"
echo ""
echo "💡 Steps:"
echo "   1. Apply patch:    node $INSTALL_DIR/patch-stdin-inline.js --apply"
echo "   2. Restart Claude Code"
echo "   3. StatusLine should now show: [Claude Sonnet 4.0 | OpenRouter]"
echo ""
echo "💾 Commands:"
echo "   Apply:      node $INSTALL_DIR/patch-stdin-inline.js --apply"
echo "   Status:     node $INSTALL_DIR/patch-stdin-inline.js --status"
echo "   Revert:     node $INSTALL_DIR/patch-stdin-inline.js --revert"
echo ""
