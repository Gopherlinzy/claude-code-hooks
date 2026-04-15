#!/usr/bin/env bash
# injection-scan.sh — Fail-OPEN: Prompt Injection 模式告警
# UserPromptSubmit hook
# 检测已知 prompt injection 模式，返回 systemMessage 警告（不阻断！）
# fail-open：误杀风险高，只告警不拒绝

set -uo pipefail
# 注意：fail-OPEN — 任何内部错误直接静默放行
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/platform-shim.sh" 2>/dev/null || true

# === JSONL 审计日志（自身 fail-safe）===
_log_jsonl() {
    local _dir="${HOME}/.cchooks/logs"
    local _file="${_dir}/hooks-audit.jsonl"
    mkdir -p "${_dir}" 2>/dev/null || true
    printf '%s\n' "$1" >> "${_file}" 2>/dev/null || true
}

# === 读取 stdin ===
INPUT=$(cat)

# 提取用户提交的 prompt 文本
PROMPT=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('prompt') or '')
except:
    print('')
" 2>/dev/null || true)

# prompt 为空直接放行
if [[ -z "${PROMPT}" ]]; then
    exit 0
fi

# === Prompt Injection 模式列表（大小写不敏感）===
# 格式：每行一个模式（ERE）
INJECTION_PATTERNS=(
    'ignore previous instructions'
    'ignore all previous'
    'you are now'
    '^[[:space:]]*system:'
    '^[[:space:]]*ADMIN:'
    'override:[[:space:]]'
    'overwrite:[[:space:]]'
    '<system>'
    '</system>'
    'forget everything'
)

PROMPT_LOWER=$(echo "${PROMPT}" | tr '[:upper:]' '[:lower:]')

MATCHED_PATTERN=""
for pattern in "${INJECTION_PATTERNS[@]}"; do
    # 将大写模式转为小写后匹配
    PATTERN_LOWER=$(echo "${pattern}" | tr '[:upper:]' '[:lower:]')
    if echo "${PROMPT_LOWER}" | grep -qE "${PATTERN_LOWER}"; then
        MATCHED_PATTERN="${pattern}"
        break
    fi
done

if [[ -n "${MATCHED_PATTERN}" ]]; then
    SESSION="${CLAUDE_SESSION_ID:-}"
    _log_jsonl "{\"ts\":\"$(_date_iso 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)\",\"hook\":\"injection-scan\",\"decision\":\"warn\",\"tool\":\"UserPromptSubmit\",\"detail\":\"检测到 injection 模式: ${MATCHED_PATTERN}\",\"session\":\"${SESSION}\"}"

    # 输出 systemMessage 告警（不阻断）
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[injection-scan] ⚠️ 检测到疑似 Prompt Injection 模式：'${MATCHED_PATTERN}'。已记录审计日志。如这是正常请求请继续操作。"}}
EOF
fi

exit 0
