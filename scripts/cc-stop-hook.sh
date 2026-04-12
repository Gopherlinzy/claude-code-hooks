#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# cc-stop-hook.sh — Claude Code Stop Hook
# 触发时机：Claude Code 任务结束（Stop Hook）
# 从 stdin 读取 JSON 获取 session_id、stop_reason 等信息
# 安全约束：Security best practices

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

# === 安全隔离：卸除敏感环境变量，防止 curl 请求意外携带认证信息 ===
unset ANTHROPIC_API_KEY
unset OPENAI_API_KEY
unset ANTHROPIC_AUTH_TOKEN
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

# === 从 stdin 读取 Hook JSON（和 cc-safety-gate.sh 一致的方式）===
STDIN_JSON="$(cat 2>/dev/null || true)"

# === 解析 session_id 和 stop_reason ===
# 优先从 stdin JSON 提取，环境变量作为 fallback（向后兼容）
if command -v jq &>/dev/null && [ -n "${STDIN_JSON}" ]; then
    SESSION_ID="$(echo "${STDIN_JSON}" | jq -r '.session_id // empty' 2>/dev/null || true)"
    STOP_REASON="$(echo "${STDIN_JSON}" | jq -r '.stop_reason // empty' 2>/dev/null || true)"
fi
# python3 fallback when jq unavailable
if [ -z "${SESSION_ID:-}" ] && [ -n "${STDIN_JSON:-}" ]; then
    SESSION_ID="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id') or '')
except: pass
" 2>/dev/null || true)"
fi
if [ -z "${STOP_REASON:-}" ] && [ -n "${STDIN_JSON:-}" ]; then
    STOP_REASON="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('stop_reason') or '')
except: pass
" 2>/dev/null || true)"
fi

# fallback：环境变量 > 默认值
TASK_ID="${SESSION_ID:-${CLAUDE_TASK_ID:-unknown}}"
STOP_REASON="${STOP_REASON:-completed}"

# 截取 session_id 前 8 位作为短 ID（便于阅读）
TASK_ID_SHORT="${TASK_ID:0:8}"

# === 尝试获取 session name（--name 参数设置的会话名）===
TASK_NAME=""
if command -v jq &>/dev/null; then
    _matched_file="$(grep -rl "\"${TASK_ID}\"" ~/.claude/projects/*/sessions/ 2>/dev/null | head -1 || true)"
    if [ -n "${_matched_file}" ] && [ -f "${_matched_file}" ]; then
        TASK_NAME="$(jq -r '.name // .session_name // empty' "${_matched_file}" 2>/dev/null || true)"
    fi
fi
# python3 fallback when jq unavailable
if [ -z "${TASK_NAME:-}" ]; then
    _matched_file="$(grep -rl "${TASK_ID}" ~/.claude/projects/*/sessions/ 2>/dev/null | head -1 || true)"
    if [ -n "${_matched_file}" ] && [ -f "${_matched_file}" ]; then
        TASK_NAME="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('name') or d.get('session_name') or '')
except: pass
" < "${_matched_file}" 2>/dev/null || true)"
    fi
fi

# fallback：环境变量 > CWD 目录名 > unnamed
TASK_NAME="${TASK_NAME:-${CLAUDE_TASK_NAME:-$(basename "${PWD}" 2>/dev/null || echo "unnamed")}}"

# === 加载配置文件（CC Hook 子进程不继承 ~/.zshrc 环境变量）===
_CONF_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/notify.conf"
# 完整性校验函数
_safe_source_conf() {
    local _file="$1"
    [ -f "${_file}" ] || return 0

    # P0-Bug-3 修复：只检查非注释行中的危险字符
    local _tainted_lines
    _tainted_lines=$(grep -v '^\s*#' "${_file}" | grep -E '\$\(|`|\\|&&|;.*eval|source\s+<' 2>/dev/null || true)

    if [ -n "$_tainted_lines" ]; then
        echo "[cc-stop-hook] WARN: ${_file##*/} integrity check failed" >&2
        return 1
    fi

    source "${_file}"
}

_safe_source_conf "${_CONF_FILE}"

# 加载凭证隔离文件
_SECRETS_FILE="${HOME}/.cchooks/secrets.env"
_safe_source_conf "${_SECRETS_FILE}"

# === 常量 ===
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DONE_DIR="${CCHOOKS_TMPDIR:-/tmp/cchooks}"
# 锁文件按 session_id 隔离，避免并发冲突
# P1-2: 锁文件迁移至 /tmp/cchooks/
LOCK_FILE="${DONE_DIR}/.hook-lock-${TASK_ID_SHORT}"
LOCK_TTL=300   # 秒；超过此时间的锁视为过期（防 /resume 重复通知）

# === 确保输出目录存在 ===
mkdir -p "${DONE_DIR}"

# === 基于时间戳的去重锁（60 秒 TTL 自动过期）===
if [ -f "${LOCK_FILE}" ]; then
    lock_ts=$(cat "${LOCK_FILE}" 2>/dev/null || echo "0")
    now_ts=$(date +%s)
    age=$(( now_ts - lock_ts ))
    if [ "${age}" -lt "${LOCK_TTL}" ]; then
        # 锁仍有效，跳过本次触发（去重）
        exit 0
    fi
    # 锁已过期，强制清除
    rm -f "${LOCK_FILE}"
fi

# 写入新锁（记录当前时间戳）
date +%s > "${LOCK_FILE}"

# === 写入 JSON 完成文件（文件数据通道）===
# 使用 session_id 命名确保唯一
DONE_FILE="${DONE_DIR}/${TASK_ID_SHORT}.done"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# 通知用本地时间（人类友好），JSON 保留 UTC（机器友好）
TIMESTAMP_DISPLAY=$(date +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || echo "${TIMESTAMP}")

# DONE_FILE 用 python3 生成合法 JSON
TASK_ID="${TASK_ID}" \
TASK_NAME="${TASK_NAME}" \
STOP_REASON="${STOP_REASON}" \
TIMESTAMP="${TIMESTAMP}" \
python3 -c "
import json, os, sys
d = {
    'session_id': os.environ['TASK_ID'],
    'task_name': os.environ['TASK_NAME'],
    'stop_reason': os.environ['STOP_REASON'],
    'timestamp': os.environ['TIMESTAMP'],
    'event': 'stop',
    'status': 'done'
}
json.dump(d, sys.stdout, indent=2, ensure_ascii=False)
print()
" > "${DONE_FILE}" 2>/dev/null || cat > "${DONE_FILE}" <<EOF
{
  "session_id": "${TASK_ID}",
  "task_name": "unknown",
  "stop_reason": "${STOP_REASON}",
  "timestamp": "${TIMESTAMP}",
  "event": "stop",
  "status": "done"
}
EOF

# === 审计日志 (JSONL) ===
if command -v jq &>/dev/null; then
    _log_jsonl "$(jq -nc --arg ts "$(_date_iso)" --arg sid "${TASK_ID_SHORT}" --arg name "${TASK_NAME}" --arg reason "${STOP_REASON}" --arg event "stop" --arg hook "cc-stop-hook" '{ts:$ts,hook:$hook,session_id:$sid,name:$name,stop_reason:$reason,event:$event}')"
else
    _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"notify-openclaw\",\"session_id\":\"${TASK_ID_SHORT}\",\"name\":\"${TASK_NAME}\",\"stop_reason\":\"${STOP_REASON}\",\"event\":\"stop\"}"
fi

# === 锁文件保留至自然过期（TTL=300s），不主动删除，防止 /resume 重复触发 ===

# === 信号通道 1：唤醒 OpenClaw 本地网关（仅限 localhost）===
# CC_GATEWAY_PORT 从 notify.conf 读取，未配置则跳过
if [ -n "${CC_GATEWAY_PORT:-}" ]; then
    # 使用 _env_clean 确保最小化环境
    _SAFE_NAME="$(printf '%s' "${TASK_NAME}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || echo "${TASK_NAME}")"
    _env_clean \
        curl -s -X POST "http://127.0.0.1:${CC_GATEWAY_PORT}/api/cron/wake" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"Claude Code session done: ${TASK_ID_SHORT} (${_SAFE_NAME})\", \"mode\": \"now\"}" \
        --max-time 5 \
        --connect-timeout 3 \
        || true
fi

# === 清理 wait-notify 标记 + kill 定时器（防止任务完成后仍发"等待操作"通知）===
_WAIT_MARKER_DIR="${CCHOOKS_TMPDIR:-/tmp/cchooks}/wait"
_WAIT_PID_FILE="${_WAIT_MARKER_DIR}/${TASK_ID_SHORT}.pid"
if [ -f "${_WAIT_PID_FILE}" ]; then
    _WAIT_PID=$(cat "${_WAIT_PID_FILE}" 2>/dev/null || echo "")
    if [ -n "${_WAIT_PID}" ] && _kill_check "${_WAIT_PID}"; then
        _WAIT_CMD=$(_ps_command_of "${_WAIT_PID}")
        if echo "${_WAIT_CMD}" | grep -q "sleep"; then
            kill "${_WAIT_PID}" 2>/dev/null || true
        fi
    fi
    rm -f "${_WAIT_PID_FILE}"
fi
rm -f "${_WAIT_MARKER_DIR}/${TASK_ID_SHORT}.waiting" "${_WAIT_MARKER_DIR}/${TASK_ID_SHORT}.detail" 2>/dev/null || true
rm -f "${_WAIT_MARKER_DIR}/${TASK_ID_SHORT}.counter" "${_WAIT_MARKER_DIR}/${TASK_ID_SHORT}.cooldown" 2>/dev/null || true

# === 信号通道 2：推送通知（通过通用通知层）===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/send-notification.sh"
NOTIFY_MSG="🤖 Claude Code 任务完成！
📋 任务: ${TASK_NAME}
🆔 Session: ${TASK_ID_SHORT}
🛑 停止原因: ${STOP_REASON}
⏰ 时间: ${TIMESTAMP_DISPLAY}
📦 结果文件: ${DONE_FILE//\\//}"

send_notify "${NOTIFY_MSG}"

# === 异步触发孤儿清理（fire-and-forget）===
_REAPER="${SCRIPT_DIR}/reap-orphans.sh"
if [ -x "${_REAPER}" ]; then
    (bash "${_REAPER}" &>/dev/null &)
fi

# 始终以 0 退出，不影响 Claude Code 主进程
exit 0
