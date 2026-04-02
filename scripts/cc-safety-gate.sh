#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# cc-safety-gate.sh — PreToolUse 安全门：拦截高危 Bash 命令
# 从 stdin 读取 Claude Code Hook JSON，提取 .tool_input.command 进行黑名单匹配

set -uo pipefail

# === Platform shim (cross-platform compatibility) ===
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platform-shim.sh"

# === Python 兼容（Windows Git Bash：python3 不在 PATH） ===
if ! command -v python3 &>/dev/null && command -v python &>/dev/null; then
    python3() { PYTHONUTF8=1 python "$@"; }
fi

# === JSONL 审计日志函数（自身 fail-safe，绝不抛错）===
_log_jsonl() {
    local _jsonl_dir="${HOME}/.cchooks/logs"
    local _jsonl_file="${_jsonl_dir}/hooks-audit.jsonl"
    mkdir -p "${_jsonl_dir}" 2>/dev/null || true
    printf '%s\n' "$1" >> "${_jsonl_file}" 2>/dev/null || true
}

# 读取 stdin JSON，提取命令
INPUT="$(cat)"
CMD="$(echo "${INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
# python3 fallback when jq unavailable
if [ -z "${CMD:-}" ] && [ -n "${INPUT:-}" ]; then
    CMD="$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print((d.get('tool_input') or {}).get('command') or '')
except: pass
" 2>/dev/null || true)"
fi

# 无命令则放行
if [[ -z "${CMD}" ]]; then
    exit 0
fi

# === 黑名单模式 ===
BLACKLIST_PATTERNS=(
    'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)*/($|\s|\*)'
    'rm\s+--recursive\s+--force\s+/'
    'rm\s+-rf\s+~'
    'sudo '
    '\\\\sudo\s'
    '(/usr/(local/)?s?bin/)?sudo\s'
    'chmod 777'
    'curl[[:space:]].*\|[[:space:]]*(ba)?sh'
    'wget[[:space:]].*\|[[:space:]]*(ba)?sh'
    'curl[[:space:]].*>[[:space:]]*/tmp/.*&&.*sh'
    'eval\s+'
    'source\s+<\('
    '\.\s+<\('
    'base64\s+.*\|\s*(ba)?sh'
    '>\s*/tmp/[^\s]+\s*&&\s*(ba)?sh\s'
    '(ba)?sh\s+-c\s+.*rm\s'
    '(ba)?sh\s+-c\s+.*sudo'
    'python[23]?\s+-c\s+.*os\.(system|popen|exec)'
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
    # 完整性校验：分别用 grep -qF 检查 $( 和反引号
    _rules_tainted=false
    grep -qF '$(' "${_RULES_FILE}" 2>/dev/null && _rules_tainted=true
    grep -qF '`' "${_RULES_FILE}" 2>/dev/null && _rules_tainted=true
    if [ "${_rules_tainted}" = true ]; then
        _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"cc-safety-gate\",\"action\":\"integrity_reject\",\"file\":\"safety-rules.conf\"}"
    else
        source "${_RULES_FILE}" || true
    fi
fi

# 检查黑名单
for pattern in "${BLACKLIST_PATTERNS[@]}"; do
    if echo "${CMD}" | grep -qE "${pattern}"; then
        if command -v jq &>/dev/null; then
            _log_jsonl "$(jq -nc --arg ts "$(_date_iso)" --arg hook "cc-safety-gate" --arg action "deny" --arg rule "${pattern}" --arg cmd "${CMD}" '{ts:$ts,hook:$hook,action:$action,rule:$rule,cmd:$cmd}')"
        else
            _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"cc-safety-gate\",\"action\":\"deny\",\"rule\":\"${pattern}\"}"
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
            _log_jsonl "$(jq -nc --arg ts "$(_date_iso)" --arg hook "cc-safety-gate" --arg action "deny" --arg path "${protected}" --arg cmd "${CMD}" '{ts:$ts,hook:$hook,action:$action,protected_path:$path,cmd:$cmd}')"
        else
            _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"cc-safety-gate\",\"action\":\"deny\",\"protected_path\":\"${protected}\"}"
        fi
        cat <<EOF
{"decision":"deny","reason":"[cc-safety-gate] 命令涉及受保护路径: ${protected}"}
EOF
        exit 0
    fi
done

# 未匹配，放行
exit 0
