#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# wait-notify.sh — PermissionRequest / Notification Hook
# 触发时机：Claude Code 等待用户操作（权限审批、通知等）
# 机制：写入等待标记 + 启动后台定时器，超时后发送飞书通知
# 安全约束：遵循 Iris 风控报告规范

set -uo pipefail

# === JSONL 审计日志函数（自身 fail-safe，绝不抛错）===
_log_jsonl() {
    local _jsonl_dir="${HOME}/.cchooks/logs"
    local _jsonl_file="${_jsonl_dir}/hooks-audit.jsonl"
    mkdir -p "${_jsonl_dir}" 2>/dev/null || true
    printf '%s\n' "$1" >> "${_jsonl_file}" 2>/dev/null || true
}

# === 安全隔离 ===
unset ANTHROPIC_API_KEY OPENAI_API_KEY ANTHROPIC_AUTH_TOKEN
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# === 加载配置文件（CC Hook 子进程不继承 ~/.zshrc 环境变量）===
_CONF_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/notify.conf"
if [ -f "${_CONF_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${_CONF_FILE}"
fi

# === 配置变量（配置文件 > 环境变量 > 默认值）===
WAIT_SECONDS="${CC_WAIT_NOTIFY_SECONDS:-30}"
NOTIFY_CHANNEL="${CC_NOTIFY_CHANNEL:-feishu}"
NOTIFY_TARGET="${CC_NOTIFY_TARGET:-}"
MARKER_DIR="/tmp/cchooks/wait"

# 若未配置任何通知后端，静默退出
# CC_NOTIFY_TARGET 仅 openclaw 后端需要；feishu/wecom/slack 等通过各自 URL 环境变量驱动
if [ -z "${NOTIFY_TARGET}" ] \
    && [ -z "${NOTIFY_FEISHU_URL:-}" ] \
    && [ -z "${NOTIFY_WECOM_URL:-}" ] \
    && [ -z "${CC_SLACK_WEBHOOK_URL:-}" ] \
    && [ -z "${CC_TELEGRAM_BOT_TOKEN:-}" ] \
    && [ -z "${CC_DISCORD_WEBHOOK_URL:-}" ] \
    && [ -z "${CC_BARK_URL:-}" ] \
    && [ -z "${CC_WEBHOOK_URL:-}" ] \
    && [ -z "${CC_NOTIFY_COMMAND:-}" ] \
    && ! command -v openclaw &>/dev/null; then
    exit 0
fi

# === 从 stdin 读取 Hook JSON ===
STDIN_JSON="$(cat 2>/dev/null || true)"

# === 解析字段 ===
SESSION_ID=""
TOOL_NAME=""
TOOL_INPUT_CMD=""
HOOK_EVENT=""

if command -v jq &>/dev/null && [ -n "${STDIN_JSON}" ]; then
    SESSION_ID="$(echo "${STDIN_JSON}" | jq -r '.session_id // empty' 2>/dev/null || true)"
    TOOL_NAME="$(echo "${STDIN_JSON}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
    HOOK_EVENT="$(echo "${STDIN_JSON}" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
    # 尝试提取命令（Bash 工具）或文件路径（Write/Edit 工具）
    TOOL_INPUT_CMD="$(echo "${STDIN_JSON}" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
fi

SESSION_ID="${SESSION_ID:-${CLAUDE_TASK_ID:-unknown}}"
SESSION_SHORT="${SESSION_ID:0:8}"
HOOK_EVENT="${HOOK_EVENT:-PermissionRequest}"

# === P1 防御纵深：Notification 事件直接退出（即使配置被意外恢复也不会复发）===
if [ "${HOOK_EVENT}" = "Notification" ]; then
    exit 0
fi

# === 截断过长的命令内容（防止消息爆炸）===
MAX_CMD_LEN=200
if [ "${#TOOL_INPUT_CMD}" -gt "${MAX_CMD_LEN}" ]; then
    TOOL_INPUT_CMD="${TOOL_INPUT_CMD:0:${MAX_CMD_LEN}}..."
fi

# === 创建等待标记目录 ===
mkdir -p "${MARKER_DIR}"

# === 等待标记文件（按 session 短 ID 隔离）===
MARKER_FILE="${MARKER_DIR}/${SESSION_SHORT}.waiting"

# === PID 文件（追踪后台定时器进程）===
PID_FILE="${MARKER_DIR}/${SESSION_SHORT}.pid"

# === 杀旧定时器（kill-old-before-new）===
if [ -f "${PID_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}" 2>/dev/null || echo "")
    if [ -n "${OLD_PID}" ] && kill -0 "${OLD_PID}" 2>/dev/null; then
        # 身份校验：确认是 sleep 进程，防止 PID reuse 误杀
        OLD_CMD=$(ps -p "${OLD_PID}" -o command= 2>/dev/null || true)
        if echo "${OLD_CMD}" | grep -q "sleep"; then
            kill "${OLD_PID}" 2>/dev/null || true
        fi
    fi
    rm -f "${PID_FILE}"
fi

# 去重：如果已有同 session 的等待标记且未过期，不重复启动
if [ -f "${MARKER_FILE}" ]; then
    marker_ts=$(cat "${MARKER_FILE}" 2>/dev/null || echo "0")
    now_ts=$(date +%s)
    age=$(( now_ts - marker_ts ))
    # 动态去重窗口：WAIT_SECONDS * 2（保证 > 定时器周期）
    DEDUP_WINDOW=$(( WAIT_SECONDS * 2 ))
    if [ "${age}" -lt "${DEDUP_WINDOW}" ]; then
        exit 0
    fi
    rm -f "${MARKER_FILE}"
fi

# 写入等待标记（记录时间戳）
date +%s > "${MARKER_FILE}"

# === 将上下文信息写入 detail 文件供定时器读取 ===
DETAIL_FILE="${MARKER_DIR}/${SESSION_SHORT}.detail"
cat > "${DETAIL_FILE}" <<EOF
{
  "session_id": "${SESSION_ID}",
  "session_short": "${SESSION_SHORT}",
  "tool_name": "${TOOL_NAME}",
  "tool_input": $(printf '%s' "${TOOL_INPUT_CMD}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'),
  "hook_event": "${HOOK_EVENT}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

# === 启动后台定时器（非阻塞）===
(
    sleep "${WAIT_SECONDS}"

    # 检查标记是否仍存在（如果用户已操作，cancel-wait.sh 会删除标记）
    if [ ! -f "${MARKER_FILE}" ]; then
        # 标记已被取消，用户已操作，不发通知
        rm -f "${DETAIL_FILE}" 2>/dev/null || true
        exit 0
    fi

    # === 超时！用户仍未操作 → 发送飞书通知 ===

    # 读取详情
    D_TOOL=""
    D_INPUT=""
    D_EVENT=""
    if [ -f "${DETAIL_FILE}" ] && command -v jq &>/dev/null; then
        D_TOOL="$(jq -r '.tool_name // empty' "${DETAIL_FILE}" 2>/dev/null || true)"
        D_INPUT="$(jq -r '.tool_input // empty' "${DETAIL_FILE}" 2>/dev/null || true)"
        D_EVENT="$(jq -r '.hook_event // empty' "${DETAIL_FILE}" 2>/dev/null || true)"
    fi

    # 构建消息内容
    EVENT_LABEL="权限审批"
    if [ "${D_EVENT}" = "Notification" ]; then
        EVENT_LABEL="通知确认"
    fi

    NOTIFY_MSG="⏰ Claude Code 等待你操作已超 ${WAIT_SECONDS} 秒！
📌 类型: ${EVENT_LABEL}
🔧 工具: ${D_TOOL:-未知}
💻 内容: ${D_INPUT:-无}
🆔 Session: ${SESSION_SHORT}

👉 请回到终端完成操作（允许/拒绝/输入）"

    # 发送通知（通过通用通知层）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/send-notification.sh"
    send_notify "${NOTIFY_MSG}"

    # 清理标记和详情文件
    rm -f "${MARKER_FILE}" "${DETAIL_FILE}" 2>/dev/null || true

) &>/dev/null &
TIMER_PID=$!
echo "${TIMER_PID}" > "${PID_FILE}" 2>/dev/null || true
disown

# hook 本身立即返回，不阻塞 CC 主流程
exit 0
