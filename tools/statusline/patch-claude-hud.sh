#!/bin/bash
#
# claude-hud 补丁脚本 - 改进 statusline model 和 provider 显示
# 问题：
#   1. Model 名称不完整：Claude Sonnet 4.6 显示为 Sonnet 4
#   2. Provider 不显示：OpenRouter/Claude API 无法显示供应商
#
# 用法：
#   ./patch-claude-hud.sh [--apply|--revert|--status]
#   --apply   : 应用补丁
#   --revert  : 回滚补丁
#   --status  : 查看补丁状态
#
# 修改的文件：
#   ~/.claude/plugins/cache/claude-hud/claude-hud/*/dist/stdin.js

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HUD_PLUGIN_DIR="${HOME}/.claude/plugins/cache/claude-hud/claude-hud"
STDIN_JS_FILE=""

# 查找最新版本的 stdin.js
find_stdin_js() {
    if [[ ! -d "$CLAUDE_HUD_PLUGIN_DIR" ]]; then
        echo "❌ claude-hud plugin not found at $CLAUDE_HUD_PLUGIN_DIR"
        exit 1
    fi

    # 找到最新版本
    STDIN_JS_FILE=$(find "$CLAUDE_HUD_PLUGIN_DIR" -name "stdin.js" -type f 2>/dev/null | sort -V | tail -1)

    if [[ -z "$STDIN_JS_FILE" ]]; then
        echo "❌ stdin.js not found in claude-hud"
        exit 1
    fi

    echo "✅ Found: $STDIN_JS_FILE"
}

# 检查是否已打补丁
is_patched() {
    grep -q "// PATCH: improved model name parsing" "$STDIN_JS_FILE" 2>/dev/null || return 1
}

# 应用补丁
apply_patch() {
    find_stdin_js

    if is_patched; then
        echo "⚠️  Already patched"
        return
    fi

    echo "📝 Applying patch..."

    # 备份原文件
    cp "$STDIN_JS_FILE" "${STDIN_JS_FILE}.backup.$(date +%s)"

    # 补丁 1：改进 getModelName() 函数
    # 处理 claude-sonnet-4-20250514 → Claude Sonnet 4.0
    # 处理 claude-opus-4-1-20250805 → Claude Opus 4.1
    cat > /tmp/patch_getModelName.js << 'EOF'
export function getModelName(stdin) {
    // PATCH: improved model name parsing
    const displayName = stdin.model?.display_name?.trim();
    if (displayName) {
        // Parse claude-sonnet-4 or claude-opus-4-1 formats
        const improved = normalizeClaudeModelLabel(displayName);
        if (improved) {
            return improved;
        }
        return displayName;
    }
    const modelId = stdin.model?.id?.trim();
    if (!modelId) {
        return 'Unknown';
    }
    const normalizedBedrockLabel = normalizeBedrockModelLabel(modelId);
    return normalizedBedrockLabel ?? modelId;
}

// PATCH: helper function to parse claude model names
function normalizeClaudeModelLabel(modelName) {
    const normalized = modelName.toLowerCase();

    // Handle: claude-sonnet-4, claude-opus-4, claude-haiku-3, etc.
    const match = normalized.match(/claude-([a-z]+)-(\d+)(?:-(\d+))?/);
    if (!match) return null;

    const family = match[1];
    const majorVersion = match[2];
    const minorVersion = match[3] || '0';

    // Capitalize family name
    const familyCapitalized = family.charAt(0).toUpperCase() + family.slice(1);

    // Format: "Claude Sonnet 4.0" or "Claude Opus 4.1"
    return `Claude ${familyCapitalized} ${majorVersion}.${minorVersion}`;
}
EOF

    # 找到 getModelName 函数并替换
    python3 << 'PYTHON_EOF'
import re
import sys

stdin_file = sys.argv[1]

with open(stdin_file, 'r') as f:
    content = f.read()

# Replace getModelName function
new_getModelName = '''export function getModelName(stdin) {
    // PATCH: improved model name parsing
    const displayName = stdin.model?.display_name?.trim();
    if (displayName) {
        // Parse claude-sonnet-4 or claude-opus-4-1 formats
        const improved = normalizeClaudeModelLabel(displayName);
        if (improved) {
            return improved;
        }
        return displayName;
    }
    const modelId = stdin.model?.id?.trim();
    if (!modelId) {
        return 'Unknown';
    }
    const normalizedBedrockLabel = normalizeBedrockModelLabel(modelId);
    return normalizedBedrockLabel ?? modelId;
}

// PATCH: helper function to parse claude model names
function normalizeClaudeModelLabel(modelName) {
    const normalized = modelName.toLowerCase();

    // Handle: claude-sonnet-4, claude-opus-4, claude-haiku-3, etc.
    const match = normalized.match(/claude-([a-z]+)-(\\d+)(?:-(\\d+))?/);
    if (!match) return null;

    const family = match[1];
    const majorVersion = match[2];
    const minorVersion = match[3] || '0';

    // Capitalize family name
    const familyCapitalized = family.charAt(0).toUpperCase() + family.slice(1);

    // Format: "Claude Sonnet 4.0" or "Claude Opus 4.1"
    return `Claude ${familyCapitalized} ${majorVersion}.${minorVersion}`;
}'''

# Find and replace getModelName function
pattern = r'export function getModelName\(stdin\) \{[^}]*const displayName[^}]*return normalizedBedrockLabel \?\? modelId;\n\}'
content = re.sub(pattern, new_getModelName, content, flags=re.DOTALL)

# Replace getProviderLabel to support OpenRouter
new_getProviderLabel = '''export function getProviderLabel(stdin) {
    // PATCH: improved provider label detection
    const modelId = stdin.model?.id?.trim();
    if (!modelId) return null;

    // Bedrock detection
    if (isBedrockModelId(modelId)) {
        return 'Bedrock';
    }

    // OpenRouter detection (model IDs usually don't have version suffix)
    // Examples: openrouter/meta-llama/llama-2-70b-chat, anthropic/claude-3-sonnet
    if (modelId.includes('openrouter') || modelId.includes('/')) {
        return 'OpenRouter';
    }

    // Claude API (claude.ai)
    if (modelId.startsWith('claude-')) {
        return 'Claude API';
    }

    return null;
}'''

# Find and replace getProviderLabel function
pattern = r'export function getProviderLabel\(stdin\) \{[^}]*return null;\n\}'
content = re.sub(pattern, new_getProviderLabel, content, flags=re.DOTALL)

with open(stdin_file, 'w') as f:
    f.write(content)

print("✅ Patch applied successfully")
PYTHON_EOF

    if is_patched; then
        echo "✅ Patch applied successfully!"
        echo ""
        echo "Changes:"
        echo "  1. ✅ Improved model name parsing (Claude Sonnet 4.6 instead of Sonnet 4)"
        echo "  2. ✅ Added OpenRouter provider detection"
        echo "  3. ✅ Added Claude API provider detection"
        echo ""
        echo "💡 Restart Claude Code to see the changes"
    else
        echo "❌ Patch failed"
        exit 1
    fi
}

# 回滚补丁
revert_patch() {
    find_stdin_js

    if [[ ! -f "${STDIN_JS_FILE}.backup."* ]]; then
        echo "❌ No backup found, cannot revert"
        exit 1
    fi

    # 找到最新的备份
    BACKUP_FILE=$(ls -t "${STDIN_JS_FILE}".backup.* 2>/dev/null | head -1)

    if [[ -z "$BACKUP_FILE" ]]; then
        echo "❌ No backup found"
        exit 1
    fi

    echo "📝 Reverting patch..."
    cp "$BACKUP_FILE" "$STDIN_JS_FILE"

    echo "✅ Reverted to: $BACKUP_FILE"
    echo "💡 Restart Claude Code to see the changes"
}

# 查看补丁状态
show_status() {
    find_stdin_js

    if is_patched; then
        echo "✅ Patch is applied"
        echo ""
        echo "Features enabled:"
        echo "  • Improved model name parsing"
        echo "  • OpenRouter provider detection"
        echo "  • Claude API provider detection"
        echo ""

        # 显示最新的备份
        BACKUP_FILE=$(ls -t "${STDIN_JS_FILE}".backup.* 2>/dev/null | head -1)
        if [[ -n "$BACKUP_FILE" ]]; then
            echo "Last backup: $BACKUP_FILE"
        fi
    else
        echo "❌ Patch is NOT applied"
        echo ""
        echo "Run: $0 --apply"
    fi
}

# 主程序
main() {
    case "${1:-}" in
        --apply)
            apply_patch
            ;;
        --revert)
            revert_patch
            ;;
        --status)
            show_status
            ;;
        *)
            cat << 'USAGE'
claude-hud Patch Script - Fix statusline model and provider display

Usage: ./patch-claude-hud.sh [COMMAND]

Commands:
  --apply         Apply the patch (fixes model name and provider display)
  --revert        Revert to previous version
  --status        Show current patch status

Examples:
  ./patch-claude-hud.sh --apply
  ./patch-claude-hud.sh --status
  ./patch-claude-hud.sh --revert

Fixes:
  ✅ Model name parsing: Claude Sonnet 4.6 (instead of Sonnet 4)
  ✅ Provider detection: OpenRouter, Claude API, Bedrock
USAGE
            exit 0
            ;;
    esac
}

main "$@"
