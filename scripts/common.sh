#!/usr/bin/env bash
# common.sh — Shared functions for all claude-code-hooks scripts
# Contains: platform detection, logging, JSON parsing, configuration loading
# Source this file at the beginning of all hook scripts

# === Platform shim (cross-platform compatibility) ===
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platform-shim.sh"

# === Python 兼容性适配（Windows Git Bash：python3 不在 PATH） ===
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

# === 错误处理函数 ===
# 记录错误日志并输出到 stderr
_cchooks_error() {
    local _msg="$1"
    local _caller="${2:-unknown}"
    local _timestamp
    _timestamp="$(_date_iso 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # 输出到 stderr
    echo "[cchooks] ERROR [${_caller}] ${_msg}" >&2

    # 记录到 JSONL 日志
    _log_jsonl "{\"timestamp\":\"${_timestamp}\",\"level\":\"ERROR\",\"caller\":\"${_caller}\",\"message\":\"${_msg}\"}" 2>/dev/null || true
}

# === 安全配置文件加载函数（P0-Bug-3 修复：只检查非注释行） ===
_safe_source_conf() {
    local _file="$1"
    [ -f "${_file}" ] || return 0

    # 只检查非注释行中的危险字符，避免误伤注释中的示例代码
    # 只检查真正危险的模式：$( 代码替换、` 反引号执行、eval 执行
    # 移除过于宽泛的 \\ 和 && 检查（Windows 路径和管道都合法）
    local _tainted_lines
    _tainted_lines=$(grep -v '^\s*#' "${_file}" | grep -E '\$\(|`|;[[:space:]]*eval' 2>/dev/null || true)

    if [ -n "$_tainted_lines" ]; then
        echo "[cchooks] WARN: ${_file##*/} contains suspicious code ($(echo "$_tainted_lines" | wc -l) lines) — skipping" >&2
        return 1
    fi

    source "${_file}"
}

# === JSON 值提取函数（jq/python3 双路径） ===
# 从 JSON 字符串中提取指定键的值
# 用法: _json_get_value <json_string> <key_path>
# 例如: _json_get_value "$json" "session_id"
#      _json_get_value "$json" "tool_input.command"
_json_get_value() {
    local _json="$1"
    local _key="$2"

    # 首先尝试使用 jq（更快更可靠）
    if command -v jq &>/dev/null && [ -n "${_json}" ]; then
        echo "${_json}" | jq -r ".${_key} // empty" 2>/dev/null || true
    # 如果 jq 不可用，使用 python3 fallback
    elif command -v python3 &>/dev/null && [ -n "${_json}" ]; then
        echo "${_json}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # 处理点号路径（例如 'tool_input.command'）
    keys = '$_key'.split('.')
    result = d
    for key in keys:
        if isinstance(result, dict):
            result = result.get(key)
        else:
            result = None
            break
    print(result if result is not None else '')
except:
    pass
" 2>/dev/null || true
    else
        # 都不可用，返回空
        return 1
    fi
}

# === 导出所有函数供子 shell 使用 ===
export -f _log_jsonl
export -f _cchooks_error
export -f _safe_source_conf
export -f _json_get_value
export -f _ps_command_of
export -f _kill_check
export -f _env_clean
export -f _find_mtime
export -f _stat_mtime
export -f _nohup_bg
export -f _atomic_mkdir
export -f _sleep_frac
export -f _date_iso

# === 导出 platform-shim 的全局变量 ===
export CCHOOKS_PLATFORM

# === 确保 CCHOOKS_TMPDIR 总是被设置（对于非 Git Bash 平台） ===
if [ -z "${CCHOOKS_TMPDIR:-}" ]; then
    CCHOOKS_TMPDIR="${HOME}/.cchooks-tmp"
    mkdir -p "${CCHOOKS_TMPDIR}" 2>/dev/null || true
fi
export CCHOOKS_TMPDIR
