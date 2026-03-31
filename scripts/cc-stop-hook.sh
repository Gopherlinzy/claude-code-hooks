#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# cc-stop-hook.sh — Claude Code Stop Hook
# 触发时机：Claude Code 任务结束（Stop Hook）
# 从 stdin 读取 JSON 获取 session_id、stop_reason 等信息
# 安全约束：Security best practices

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

# fallback：环境变量 > 默认值
TASK_ID="${SESSION_ID:-${CLAUDE_TASK_ID:-unknown}}"
STOP_REASON="${STOP_REASON:-completed}"

# 截取 session_id 前 8 位作为短 ID（便于阅读）
TASK_ID_SHORT="${TASK_ID:0:8}"

# === 尝试获取 session name（--name 参数设置的会话名）===
TASK_NAME=""
if command -v jq &>/dev/null; then
    # Claude Code 的 session 数据存储在 ~/.claude/projects/ 下
    # 遍历查找匹配 session_id 的 session 文件
    for session_file in ~/.claude/projects/*/sessions/*.json; do
        [ -f "${session_file}" ] || continue
        file_session_id="$(jq -r '.session_id // .id // empty' "${session_file}" 2>/dev/null || true)"
        if [ "${file_session_id}" = "${TASK_ID}" ]; then
            TASK_NAME="$(jq -r '.name // .session_name // empty' "${session_file}" 2>/dev/null || true)"
            break
        fi
    done
fi

# fallback：环境变量 > CWD 目录名 > unnamed
TASK_NAME="${TASK_NAME:-${CLAUDE_TASK_NAME:-$(basename "${PWD}" 2>/dev/null || echo "unnamed")}}"

# === 加载配置文件（CC Hook 子进程不继承 ~/.zshrc 环境变量）===
_CONF_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/notify.conf"
if [ -f "${_CONF_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${_CONF_FILE}"
fi

# === 常量 ===
HOOK_DIR="${HOME}/.cchooks"
DONE_DIR="/tmp/cchooks"
# 锁文件按 session_id 隔离，避免并发冲突
LOCK_FILE="${HOOK_DIR}/.hook-lock-${TASK_ID_SHORT}"
LOCK_TTL=60   # 秒；超过此时间的锁视为过期

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

cat > "${DONE_FILE}" <<EOF
{
  "session_id": "${TASK_ID}",
  "task_name": "${TASK_NAME}",
  "stop_reason": "${STOP_REASON}",
  "timestamp": "${TIMESTAMP}",
  "event": "stop",
  "status": "done"
}
EOF

# === 审计日志 (JSONL) ===
if command -v jq &>/dev/null; then
    _log_jsonl "$(jq -nc --arg ts "$(date -Iseconds)" --arg sid "${TASK_ID_SHORT}" --arg name "${TASK_NAME}" --arg reason "${STOP_REASON}" --arg event "stop" --arg hook "cc-stop-hook" '{ts:$ts,hook:$hook,session_id:$sid,name:$name,stop_reason:$reason,event:$event}')"
else
    _log_jsonl "{\"ts\":\"$(date -Iseconds)\",\"hook\":\"notify-openclaw\",\"session_id\":\"${TASK_ID_SHORT}\",\"name\":\"${TASK_NAME}\",\"stop_reason\":\"${STOP_REASON}\",\"event\":\"stop\"}"
fi

# === 清理锁文件 ===
rm -f "${LOCK_FILE}"

# === 信号通道 1：唤醒 OpenClaw 本地网关（仅限 localhost）===
# CC_GATEWAY_PORT 从 notify.conf 读取，未配置则跳过
if [ -n "${CC_GATEWAY_PORT:-}" ]; then
    # 使用 env -i 确保最小化环境，防止意外变量泄漏
    env -i PATH="${PATH}" \
        curl -s -X POST "http://127.0.0.1:${CC_GATEWAY_PORT}/api/cron/wake" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"Claude Code session done: ${TASK_ID_SHORT} (${TASK_NAME})\", \"mode\": \"now\"}" \
        --max-time 5 \
        --connect-timeout 3 \
        || true
fi

# === 清理 wait-notify 标记 + kill 定时器（防止任务完成后仍发"等待操作"通知）===
_WAIT_MARKER_DIR="/tmp/cchooks/wait"
_WAIT_PID_FILE="${_WAIT_MARKER_DIR}/${TASK_ID_SHORT}.pid"
if [ -f "${_WAIT_PID_FILE}" ]; then
    _WAIT_PID=$(cat "${_WAIT_PID_FILE}" 2>/dev/null || echo "")
    if [ -n "${_WAIT_PID}" ] && kill -0 "${_WAIT_PID}" 2>/dev/null; then
        _WAIT_CMD=$(ps -p "${_WAIT_PID}" -o command= 2>/dev/null || true)
        if echo "${_WAIT_CMD}" | grep -q "sleep"; then
            kill "${_WAIT_PID}" 2>/dev/null || true
        fi
    fi
    rm -f "${_WAIT_PID_FILE}"
fi
rm -f "${_WAIT_MARKER_DIR}/${TASK_ID_SHORT}.waiting" "${_WAIT_MARKER_DIR}/${TASK_ID_SHORT}.detail" 2>/dev/null || true

# === 信号通道 2：推送通知（通过通用通知层）===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/send-notification.sh"
NOTIFY_MSG="🤖 Claude Code 任务完成！
📋 任务: ${TASK_NAME}
🆔 Session: ${TASK_ID_SHORT}
🛑 停止原因: ${STOP_REASON}
⏰ 时间: ${TIMESTAMP}
📦 结果文件: ${DONE_FILE}"

send_notify "${NOTIFY_MSG}"

# 始终以 0 退出，不影响 Claude Code 主进程
exit 0
