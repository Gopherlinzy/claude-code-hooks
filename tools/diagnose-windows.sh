#!/bin/bash
# Windows Claude Code Hooks 诊断脚本
# 在 Git Bash 上运行此脚本来诊断常见问题

set -e

echo "🔍 Claude Code Hooks - Windows 诊断工具"
echo "=========================================="
echo ""

# 1. 检查基础工具
echo "📋 [1/5] 检查基础工具..."
{
    which bash && echo "  ✅ bash: $(bash --version | head -1)" || echo "  ❌ bash 未找到"
    which node && echo "  ✅ node: $(node --version)" || echo "  ❌ node 未找到"
    which curl && echo "  ✅ curl: $(curl --version | head -1)" || echo "  ❌ curl 未找到"
    which jq 2>/dev/null && echo "  ✅ jq: $(jq --version)" || echo "  ⚠️  jq 未找到（可选）"
} || true
echo ""

# 2. 检查 settings.json
echo "📋 [2/5] 检查 settings.json..."
SETTINGS="${HOME}/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    echo "  ✅ 文件存在: $SETTINGS"
    echo ""
    echo "  内容预览（hooks 部分）:"
    python3 << 'PYEOF' 2>/dev/null || echo "  ⚠️  无法解析 settings.json"
import json
import os
settings_file = os.path.expanduser('~/.claude/settings.json')
try:
    with open(settings_file) as f:
        settings = json.load(f)
    if 'hooks' in settings:
        print("  ✅ 找到 'hooks' 字段")
        hooks = settings['hooks']
        for event_name, matchers in hooks.items():
            print(f"    - {event_name}: {len(matchers) if isinstance(matchers, list) else 1} 个匹配器")
            if isinstance(matchers, list):
                for i, m in enumerate(matchers):
                    print(f"      [{i}] matcher='{m.get('matcher')}', hooks 数={len(m.get('hooks', []))}")
    else:
        print("  ❌ 未找到 'hooks' 字段")
except Exception as e:
    print(f"  ❌ 错误: {e}")
PYEOF
else
    echo "  ❌ 文件不存在: $SETTINGS"
fi
echo ""

# 3. 检查 hooks 脚本安装
echo "📋 [3/5] 检查 hooks 脚本安装..."
HOOKS_DIR="${HOME}/.claude/scripts/claude-hooks"
if [ -d "$HOOKS_DIR" ]; then
    echo "  ✅ 目录存在: $HOOKS_DIR"
    echo ""
    echo "  已安装的脚本:"
    ls -1 "$HOOKS_DIR"/*.sh 2>/dev/null | wc -l | xargs echo "    共"
    echo "个脚本"

    # 检查关键脚本
    for script in cc-stop-hook.sh cc-safety-gate.sh guard-large-files.sh wait-notify.sh; do
        if [ -f "$HOOKS_DIR/$script" ]; then
            echo "    ✅ $script"
        else
            echo "    ❌ $script 缺失"
        fi
    done
else
    echo "  ❌ 目录不存在: $HOOKS_DIR"
fi
echo ""

# 4. 检查 OpenRouter statusline 配置
echo "📋 [4/5] 检查 OpenRouter statusline..."
STATUSLINE_SCRIPT="${HOOKS_DIR}/statusline/openrouter-statusline.js"
if [ -f "$STATUSLINE_SCRIPT" ]; then
    echo "  ✅ statusline 脚本存在"

    # 检查 API Key
    if [ -z "$OPENROUTER_API_KEY" ]; then
        echo "  ⚠️  OPENROUTER_API_KEY 未设置"
        echo "     在 ~/.bashrc 或 ~/.zshrc 中添加: export OPENROUTER_API_KEY='your-key'"
    else
        echo "  ✅ OPENROUTER_API_KEY 已设置（长度: ${#OPENROUTER_API_KEY}）"
    fi

    # 测试脚本运行
    echo ""
    echo "  测试脚本运行（5秒超时）..."
    timeout 5 node "$STATUSLINE_SCRIPT" 2>&1 | head -5 || {
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo "  ⚠️  脚本超时（网络慢）"
        else
            echo "  ⚠️  脚本返回错误码: $EXIT_CODE"
        fi
    }
else
    echo "  ❌ statusline 脚本不存在"
fi
echo ""

# 5. 检查 Claude HUD 状态栏配置
echo "📋 [5/5] 检查 Claude HUD statusLine..."
python3 << 'PYEOF' 2>/dev/null || echo "  ⚠️  无法读取配置"
import json
import os
settings_file = os.path.expanduser('~/.claude/settings.json')
try:
    with open(settings_file) as f:
        settings = json.load(f)
    if 'statusLine' in settings:
        sl = settings['statusLine']
        print(f"  ✅ 找到 statusLine 配置")
        print(f"     type: {sl.get('type')}")
        if 'command' in sl:
            cmd = sl['command'][:100] + ('...' if len(sl['command']) > 100 else '')
            print(f"     command: {cmd}")
    else:
        print(f"  ❌ 未找到 statusLine 配置")
        print(f"     运行 /claude-hud:setup 来配置")
except Exception as e:
    print(f"  ❌ 错误: {e}")
PYEOF
echo ""

# 总结
echo "=========================================="
echo "✅ 诊断完成！"
echo ""
echo "💡 故障排除建议："
echo "   1. 如果 hooks 缺失: 重新运行 install.sh"
echo "   2. 如果 OPENROUTER_API_KEY 未设置: 编辑 ~/.bashrc 或 ~/.zshrc"
echo "   3. 如果 statusline 超时: 检查网络连接或 OpenRouter API 状态"
echo "   4. 如果找不到脚本: 检查 INSTALL_DIR 路径是否正确"
echo ""
