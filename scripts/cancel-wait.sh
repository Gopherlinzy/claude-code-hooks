#!/usr/bin/env bash
# cancel-wait.sh — PostToolUse / UserPromptSubmit Hook
# 触发时机：用户完成操作后（工具成功执行 / 用户提交新 prompt）
# 机制：删除等待标记文件，使 wait-notify.sh 的后台定时器不再发送通知
# 安全约束：纯文件删除操作，无外部网络调用

set -uo pipefail

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

rm -f "${MARKER_FILE}" "${DETAIL_FILE}" 2>/dev/null || true

# 静默退出，不影响 CC 主流程
exit 0
