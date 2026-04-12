#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# cancel-wait.sh — PostToolUse / UserPromptSubmit Hook
# 触发时机：用户完成操作后（工具成功执行 / 用户提交新 prompt）
# 机制：删除等待标记文件，使 wait-notify.sh 的后台定时器不再发送通知
# 安全约束：纯文件删除操作，无外部网络调用

set -uo pipefail

# === Load common functions ===
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# === 从 stdin 读取 Hook JSON ===
STDIN_JSON="$(cat 2>/dev/null || true)"

# === 解析 session_id ===
SESSION_ID=""
if command -v jq &>/dev/null && [ -n "${STDIN_JSON}" ]; then
    SESSION_ID="$(echo "${STDIN_JSON}" | jq -r '.session_id // empty' 2>/dev/null || true)"
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

SESSION_ID="${SESSION_ID:-${CLAUDE_TASK_ID:-unknown}}"
SESSION_SHORT="${SESSION_ID:0:8}"

# === 等待标记目录 ===
MARKER_DIR="${CCHOOKS_TMPDIR:-/tmp/cchooks}/wait"

# === 删除等待标记（如果存在）===
MARKER_FILE="${MARKER_DIR}/${SESSION_SHORT}.waiting"
DETAIL_FILE="${MARKER_DIR}/${SESSION_SHORT}.detail"
PID_FILE="${MARKER_DIR}/${SESSION_SHORT}.pid"

# === 防误杀：标记刚写入不到 GRACE_SECONDS 秒则跳过清除 ===
# PermissionRequest 和 PostToolUse 可能几乎同时触发
# 如果标记太新，说明用户还没来得及操作，不应该取消
GRACE_SECONDS=5

if [ -f "${MARKER_FILE}" ]; then
    marker_ts=$(cat "${MARKER_FILE}" 2>/dev/null || echo "0")
    now_ts=$(date +%s)
    age=$(( now_ts - marker_ts ))
    if [ "${age}" -lt "${GRACE_SECONDS}" ]; then
        # 标记太新，跳过清除（保护定时器继续倒计时）
        exit 0
    fi
fi

# === 主动 kill 后台定时器进程（P1 加固）===
if [ -f "${PID_FILE}" ]; then
    TIMER_PID=$(cat "${PID_FILE}" 2>/dev/null || echo "")
    if [ -n "${TIMER_PID}" ] && _kill_check "${TIMER_PID}"; then
        # 身份校验：确认是 sleep 进程，防止 PID reuse 误杀
        TIMER_CMD="$(_ps_command_of "${TIMER_PID}")"
        if echo "${TIMER_CMD}" | grep -q "sleep"; then
            kill "${TIMER_PID}" 2>/dev/null || true
        fi
    fi
    rm -f "${PID_FILE}"
fi

rm -f "${MARKER_FILE}" "${DETAIL_FILE}" 2>/dev/null || true
# 清理计数器和冷却文件（防止 circuit breaker 因 cancel 累积误触发）
rm -f "${MARKER_DIR}/${SESSION_SHORT}.counter" "${MARKER_DIR}/${SESSION_SHORT}.cooldown" 2>/dev/null || true

# 静默退出，不影响 CC 主流程
exit 0
