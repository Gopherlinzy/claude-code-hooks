#!/usr/bin/env bash
# project-context-guard.sh — Fail-CLOSED
# PreToolUse(Write|Edit) 拦截 Project Context 根级 5 文件写入
# 使用 python3 os.path.realpath（不依赖 realpath 命令，macOS 兼容）
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

trap 'echo "{\"decision\":\"deny\",\"reason\":\"[project-context-guard] hook 内部错误，保守拒绝\"}" ; exit 0' ERR

INPUT=$(cat)

# 提取文件路径（兼容 file_path / path / filePath 字段）
FILE_PATH=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or ti.get('filePath') or '')
except:
    print('')
" 2>/dev/null)

[ -z "${FILE_PATH}" ] && exit 0

# macOS 兼容的绝对路径解析（不依赖 realpath 命令）
REAL_PATH=$(python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "${FILE_PATH}" 2>/dev/null || echo "${FILE_PATH}")

WORKSPACE_ROOT="/Users/admin/.openclaw/workspace-main"
PROTECTED=("SOUL.md" "IDENTITY.md" "USER.md" "AGENTS.md" "TOOLS.md")

for f in "${PROTECTED[@]}"; do
    if [ "${REAL_PATH}" = "${WORKSPACE_ROOT}/${f}" ]; then
        TOOL_NAME=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name') or '')
except:
    print('')
" 2>/dev/null || true)
        _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"project-context-guard\",\"decision\":\"deny\",\"tool\":\"${TOOL_NAME}\",\"detail\":\"禁止写入 ${f}\",\"session\":\"${CLAUDE_SESSION_ID:-}\"}"
        echo "{\"decision\":\"deny\",\"reason\":\"[project-context-guard] 禁止写入 Project Context 根级文件: ${f}\"}"
        exit 0
    fi
done

# === 保护 Hook 配置目录和系统配置文件（防 Write 工具绕过）===
PROTECTED_HOOK_DIRS=(
    "/Users/admin/.claude/scripts/claude-hooks/"
    "/Users/admin/.cchooks/"
)
PROTECTED_CONFIG_FILES=(
    "/Users/admin/.claude/settings.json"
    "/Users/admin/.openclaw/openclaw.json"
)

for hook_dir in "${PROTECTED_HOOK_DIRS[@]}"; do
    if [[ "${REAL_PATH}" == "${hook_dir}"* ]]; then
        TOOL_NAME=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name') or '')
except:
    print('')
" 2>/dev/null || true)
        _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"project-context-guard\",\"decision\":\"deny\",\"tool\":\"${TOOL_NAME}\",\"detail\":\"禁止写入受保护 Hook 目录: ${hook_dir}\",\"session\":\"${CLAUDE_SESSION_ID:-}\"}"
        echo "{\"decision\":\"deny\",\"reason\":\"[project-context-guard] 禁止写入受保护 Hook 配置目录\"}"
        exit 0
    fi
done

for cfg_file in "${PROTECTED_CONFIG_FILES[@]}"; do
    if [ "${REAL_PATH}" = "${cfg_file}" ]; then
        TOOL_NAME=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name') or '')
except:
    print('')
" 2>/dev/null || true)
        _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"project-context-guard\",\"decision\":\"deny\",\"tool\":\"${TOOL_NAME}\",\"detail\":\"禁止写入受保护配置文件: ${cfg_file}\",\"session\":\"${CLAUDE_SESSION_ID:-}\"}"
        echo "{\"decision\":\"deny\",\"reason\":\"[project-context-guard] 禁止写入受保护配置文件: ${cfg_file}\"}"
        exit 0
    fi
done

exit 0
