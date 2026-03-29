#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# cc-safety-gate.sh — PreToolUse 安全门：拦截高危 Bash 命令
# 从 stdin 读取 Claude Code Hook JSON，提取 .tool_input.command 进行黑名单匹配

set -euo pipefail

# === JSONL 审计日志函数（自身 fail-safe，绝不抛错）===
_log_jsonl() {
    local _jsonl_dir="${HOME}/.openclaw/logs"
    local _jsonl_file="${_jsonl_dir}/hooks-audit.jsonl"
    mkdir -p "${_jsonl_dir}" 2>/dev/null || true
    printf '%s\n' "$1" >> "${_jsonl_file}" 2>/dev/null || true
}

# 读取 stdin JSON，提取命令
INPUT="$(cat)"
CMD="$(echo "${INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

# 无命令则放行
if [[ -z "${CMD}" ]]; then
    exit 0
fi

# === 黑名单模式 ===
BLACKLIST_PATTERNS=(
    'rm -rf /'
    'rm -rf ~'
    'sudo '
    'chmod 777'
    'curl.*|.*sh'
    'wget.*|.*sh'
    'mkfs'
    'dd if='
    '> /etc/'
)

# === 路径保护 ===
PROTECTED_PATHS=(
    '.ssh'
    'SOUL.md'
    'IDENTITY.md'
    'USER.md'
    '/etc/'
    '/System/'
)

# === 外部配置覆盖（仅存在时加载，失败不致命）===
_RULES_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/safety-rules.conf"
if [ -f "${_RULES_FILE}" ]; then
    source "${_RULES_FILE}" || true
fi

# 检查黑名单
for pattern in "${BLACKLIST_PATTERNS[@]}"; do
    if echo "${CMD}" | grep -qE "${pattern}"; then
        if command -v jq &>/dev/null; then
            _log_jsonl "$(jq -nc --arg ts "$(date -Iseconds)" --arg hook "cc-safety-gate" --arg action "deny" --arg rule "${pattern}" --arg cmd "${CMD}" '{ts:$ts,hook:$hook,action:$action,rule:$rule,cmd:$cmd}')"
        else
            _log_jsonl "{\"ts\":\"$(date -Iseconds)\",\"hook\":\"cc-safety-gate\",\"action\":\"deny\",\"rule\":\"${pattern}\"}"
        fi
        cat <<EOF
{"decision":"deny","reason":"[cc-safety-gate] 命令匹配黑名单规则: ${pattern}"}
EOF
        exit 0
    fi
done

# 检查路径保护
for protected in "${PROTECTED_PATHS[@]}"; do
    if echo "${CMD}" | grep -qF "${protected}"; then
        if command -v jq &>/dev/null; then
            _log_jsonl "$(jq -nc --arg ts "$(date -Iseconds)" --arg hook "cc-safety-gate" --arg action "deny" --arg path "${protected}" --arg cmd "${CMD}" '{ts:$ts,hook:$hook,action:$action,protected_path:$path,cmd:$cmd}')"
        else
            _log_jsonl "{\"ts\":\"$(date -Iseconds)\",\"hook\":\"cc-safety-gate\",\"action\":\"deny\",\"protected_path\":\"${protected}\"}"
        fi
        cat <<EOF
{"decision":"deny","reason":"[cc-safety-gate] 命令涉及受保护路径: ${protected}"}
EOF
        exit 0
    fi
done

# 未匹配，放行
exit 0
