#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# cancel-wait.sh — PostToolUse / UserPromptSubmit Hook
# 触发时机：用户完成操作后（工具成功执行 / 用户提交新 prompt）
# 机制：删除等待标记文件，使 wait-notify.sh 的后台定时器不再发送通知
# 安全约束：纯文件删除操作，无外部网络调用

set -uo pipefail

# === JSONL 审计日志函数（自身 fail-safe，绝不抛错）===
_log_jsonl() {
    local _jsonl_dir="${HOME}/.openclaw/logs"
    local _jsonl_file="${_jsonl_dir}/hooks-audit.jsonl"
    mkdir -p "${_jsonl_dir}" 2>/dev/null || true
    printf '%s\n' "$1" >> "${_jsonl_file}" 2>/dev/null || true
}

# === 从 stdin 读取 Hook JSON ===
STDIN_JSON="$(cat 2>/dev/null || true)"

# === 解析 session_id ===
SESSION_ID=""
if command -v jq &>/dev/null && [ -n "${STDIN_JSON}" ]; then
    SESSION_ID="$(echo "${STDIN_JSON}" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi

SESSION_ID="${SESSION_ID:-${CLAUDE_TASK_ID:-unknown}}"
SESSION_SHORT="${SESSION_ID:0:8}"

# === 等待标记目录 ===
MARKER_DIR="/tmp/openclaw-hooks/wait"

# === 删除等待标记（如果存在）===
MARKER_FILE="${MARKER_DIR}/${SESSION_SHORT}.waiting"
DETAIL_FILE="${MARKER_DIR}/${SESSION_SHORT}.detail"
PID_FILE="${MARKER_DIR}/${SESSION_SHORT}.pid"

# === 主动 kill 后台定时器进程（P1 加固）===
if [ -f "${PID_FILE}" ]; then
    TIMER_PID=$(cat "${PID_FILE}" 2>/dev/null || echo "")
    if [ -n "${TIMER_PID}" ] && kill -0 "${TIMER_PID}" 2>/dev/null; then
        # 身份校验：确认是 sleep 进程，防止 PID reuse 误杀
        TIMER_CMD=$(ps -p "${TIMER_PID}" -o command= 2>/dev/null || true)
        if echo "${TIMER_CMD}" | grep -q "sleep"; then
            kill "${TIMER_PID}" 2>/dev/null || true
        fi
    fi
    rm -f "${PID_FILE}"
fi

rm -f "${MARKER_FILE}" "${DETAIL_FILE}" 2>/dev/null || true

# 静默退出，不影响 CC 主流程
exit 0
