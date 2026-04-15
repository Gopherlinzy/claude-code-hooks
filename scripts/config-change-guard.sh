#!/usr/bin/env bash
# config-change-guard.sh — Fail-CLOSED
# ConfigChange hook 阻断非管理员配置修改
# ⚠️ 正确字段名是 .source（不是 .config_source！）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/platform-shim.sh"

# === JSONL 审计日志（自身 fail-safe）===
_log_jsonl() {
    local _dir="${HOME}/.cchooks/logs"
    local _file="${_dir}/hooks-audit.jsonl"
    mkdir -p "${_dir}" 2>/dev/null || true
    printf '%s\n' "$1" >> "${_file}" 2>/dev/null || true
}

trap 'echo "{\"decision\":\"deny\",\"reason\":\"[config-guard] hook 内部错误，保守拒绝\"}" ; exit 0' ERR

INPUT=$(cat)

# 正确字段：.source，不是 .config_source
SOURCE=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('source') or '')
except:
    print('')
" 2>/dev/null)

FILE_PATH=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('file_path') or '')
except:
    print('')
" 2>/dev/null)

# policy_settings 是管理员级别，允许通过（实际上 CC 不会把此类事件发给 hook，保留判断更清晰）
if [ "${SOURCE}" = "policy_settings" ]; then
    exit 0
fi

_log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"config-change-guard\",\"decision\":\"deny\",\"tool\":\"ConfigChange\",\"detail\":\"source=${SOURCE} file=${FILE_PATH}\",\"session\":\"${CLAUDE_SESSION_ID:-}\"}"
echo "{\"decision\":\"deny\",\"reason\":\"[config-guard] 运行时配置修改被阻断（source: ${SOURCE}, file: ${FILE_PATH}）。需要指挥官通过管理界面授权。\"}"
exit 0
