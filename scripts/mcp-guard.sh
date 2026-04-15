#!/usr/bin/env bash
# mcp-guard.sh — Fail-CLOSED: MCP 工具写操作拦截
# PreToolUse hook，matcher: mcp__*
# mysql MCP 写操作 → deny；feishu-docs 写操作 → systemMessage 警告；其余放行

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

_deny() {
    local reason="$1"
    local tool="${TOOL_NAME:-}"
    local session="${CLAUDE_SESSION_ID:-}"
    _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"mcp-guard\",\"decision\":\"deny\",\"tool\":\"${tool}\",\"detail\":\"${reason}\",\"session\":\"${session}\"}"
    echo "{\"decision\":\"deny\",\"reason\":\"[mcp-guard] ${reason}\"}"
    exit 0
}

# fail-closed: hook 内部错误时保守拒绝
trap '_deny "hook 内部错误，保守拒绝"' ERR

INPUT=$(cat)

TOOL_NAME=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name') or '')
except:
    print('')
" 2>/dev/null)

TOOL_INPUT=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') or {}
    print(json.dumps(ti))
except:
    print('{}')
" 2>/dev/null)

# ===== mysql MCP 写操作检测（fail-closed）=====
if [[ "${TOOL_NAME}" == mcp__mysql* ]]; then
    SQL=$(echo "${TOOL_INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # mysql_mcp_server 常见字段名
    print(d.get('query') or d.get('sql') or d.get('statement') or '')
except:
    print('')
" 2>/dev/null | tr '[:lower:]' '[:upper:]')

    for keyword in INSERT UPDATE DELETE DROP TRUNCATE ALTER CREATE REPLACE MERGE; do
        if echo "${SQL}" | grep -qw "${keyword}"; then
            _deny "mysql MCP 写操作被阻断: ${keyword} 语句需要指挥官授权"
        fi
    done

    # 只读操作放行（无日志，减少量）
    exit 0
fi

# ===== feishu-docs MCP 写操作：systemMessage 告警，不阻断 =====
if [[ "${TOOL_NAME}" == mcp__feishu-docs* ]]; then
    # 根据工具名称后缀检测写操作动词
    TOOL_LOWER=$(echo "${TOOL_NAME}" | tr '[:upper:]' '[:lower:]')
    for verb in create update delete write edit patch post put move archive; do
        if echo "${TOOL_LOWER}" | grep -q "${verb}"; then
            _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"mcp-guard\",\"decision\":\"warn\",\"tool\":\"${TOOL_NAME}\",\"detail\":\"feishu-docs 写操作（已放行，需授权）\",\"session\":\"${CLAUDE_SESSION_ID:-}\"}"
            echo "{\"systemMessage\":\"[mcp-guard] ⚠️ 飞书文档写操作：${TOOL_NAME}。已记录审计日志，请确认操作已获得指挥官授权。\"}"
            exit 0
        fi
    done
    # 只读操作放行
    exit 0
fi

# 其余 MCP 工具放行
exit 0
