#!/bin/bash
#
# 在主安装流程中可选应用 claude-hud 补丁
# 由 claude-code-hooks 主安装脚本调用
#
# 用法：
#   source ./apply-patch-on-install.sh
#   should_patch_claude_hud  # 询问用户
#   apply_claude_hud_patch   # 应用补丁

# 询问用户是否要应用补丁
should_patch_claude_hud() {
    local install_dir="$1"

    if [[ ! -f "$install_dir/patch-stdin-v2-final.js" ]]; then
        return 1  # 补丁脚本不存在
    fi

    # 检查 claude-hud 是否安装
    if [[ ! -d "${HOME}/.claude/plugins/cache/claude-hud/claude-hud" ]]; then
        # claude-hud 未安装，跳过
        return 1
    fi

    # 询问用户
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🔧 Optional: Fix claude-hud StatusLine Display Issues"
    echo ""
    echo "The patch fixes two common problems:"
    echo "  1. Model name incomplete: 'Sonnet 4' → 'Claude Sonnet 4.0'"
    echo "  2. Provider not shown: add '| OpenRouter' to statusline"
    echo ""
    echo "Before: [Sonnet 4]"
    echo "After:  [Claude Sonnet 4.0 | OpenRouter]"
    echo ""
    read -p "Apply claude-hud patch? (y/n) [y]: " -r
    REPLY="${REPLY:=y}"

    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# 应用补丁
apply_claude_hud_patch() {
    local install_dir="$1"
    local patch_script="$install_dir/patch-stdin-v2-final.js"

    if [[ ! -f "$patch_script" ]]; then
        echo "⚠️  Patch script not found: $patch_script"
        return 1
    fi

    echo ""
    echo "💾 Applying patch..."

    if node "$patch_script" --apply 2>/dev/null; then
        echo ""
        echo "✅ Patch applied successfully!"
        echo ""
        echo "💡 Remember to restart Claude Code to see the changes"
    else
        echo ""
        echo "❌ Patch failed. Check: node $patch_script --status"
    fi
}

# 导出函数（供外部调用）
export -f should_patch_claude_hud
export -f apply_claude_hud_patch
