#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# wait-notify.sh — PermissionRequest / Notification Hook
# 触发时机：Claude Code 等待用户操作（权限审批、通知等）
# 机制：写入等待标记 + 启动后台定时器，超时后发送飞书通知
# 安全约束：遵循 Iris 风控报告规范

set -uo pipefail

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
# === 死循环防护（学习 CC 源码 query/stopHooks.ts 熔断机制）===
MAX_CONCURRENT_TIMERS=3       # 同一 session 最大并发定时器数
GLOBAL_COOLDOWN_SECONDS=10    # 全局冷却：10 秒内不重复启动新定时器

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
    # 尝试提取命令（Bash）、文件路径（Write/Edit）、或问题内容（AskUserQuestion 等）
    TOOL_INPUT_CMD="$(echo "${STDIN_JSON}" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.path // .tool_input.question // .tool_input.text // .tool_input.content // (.tool_input | tostring | if length > 200 then .[:200] + "..." else . end) // empty' 2>/dev/null || true)"
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
if [ -z "${TOOL_NAME:-}" ] && [ -n "${STDIN_JSON:-}" ]; then
    TOOL_NAME="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name') or '')
except: pass
" 2>/dev/null || true)"
fi
if [ -z "${HOOK_EVENT:-}" ] && [ -n "${STDIN_JSON:-}" ]; then
    HOOK_EVENT="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('hook_event_name') or '')
except: pass
" 2>/dev/null || true)"
fi
if [ -z "${TOOL_INPUT_CMD:-}" ] && [ -n "${STDIN_JSON:-}" ]; then
    TOOL_INPUT_CMD="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') or {}
    if isinstance(ti, str):
        print(ti[:200])
    else:
        v = ti.get('command') or ti.get('file_path') or ti.get('path') or ti.get('question') or ti.get('text') or ti.get('content') or str(ti)[:200]
        print(v or '')
except: pass
" 2>/dev/null || true)"
fi

SESSION_ID="${SESSION_ID:-${CLAUDE_TASK_ID:-unknown}}"
SESSION_SHORT="${SESSION_ID:0:8}"
HOOK_EVENT="${HOOK_EVENT:-PermissionRequest}"

# === Notification 事件：正常处理（2026-03-31 修复，原 P1 硬杀已移除）===
# Notification 事件现在通过 matcher:"*" 正常触发，由脚本内部逻辑处理

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
# === 并发计数文件 ===
COUNTER_FILE="${MARKER_DIR}/${SESSION_SHORT}.counter"

# === 死循环防护：检查当前活跃定时器数 ===
_active_count=0
if [ -f "${COUNTER_FILE}" ]; then
    _active_count=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "0")
fi
if [ "${_active_count}" -ge "${MAX_CONCURRENT_TIMERS}" ]; then
    _log_jsonl "{\"ts\":\"$(date -Iseconds)\",\"hook\":\"wait-notify\",\"event\":\"circuit_breaker\",\"session\":\"${SESSION_SHORT}\",\"reason\":\"max_concurrent_timers_${MAX_CONCURRENT_TIMERS}\"}"
    exit 0
fi

# === 全局冷却防护 ===
COOLDOWN_FILE="${MARKER_DIR}/${SESSION_SHORT}.cooldown"
if [ -f "${COOLDOWN_FILE}" ]; then
    _cd_ts=$(cat "${COOLDOWN_FILE}" 2>/dev/null || echo "0")
    _now_ts=$(date +%s)
    if [ $(( _now_ts - _cd_ts )) -lt "${GLOBAL_COOLDOWN_SECONDS}" ]; then
        exit 0
    fi
fi
date +%s > "${COOLDOWN_FILE}" 2>/dev/null || true

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

# === 检查任务是否已完成（.done 文件存在则跳过）===
DONE_DIR="/tmp/cchooks"
if [ -f "${DONE_DIR}/${SESSION_SHORT}.done" ]; then
    # 任务已完成，不需要等待通知
    rm -f "${MARKER_FILE}" "${DETAIL_FILE}" 2>/dev/null || true
    exit 0
fi

# === 启动后台定时器（非阻塞）===
(
    sleep "${WAIT_SECONDS}"

    # 检查标记是否仍存在（如果用户已操作，cancel-wait.sh 会删除标记）
    if [ ! -f "${MARKER_FILE}" ]; then
        # 标记已被取消，用户已操作，不发通知
        rm -f "${DETAIL_FILE}" 2>/dev/null || true
        exit 0
    fi

    # 再次检查任务是否已在等待期间完成
    if [ -f "${DONE_DIR}/${SESSION_SHORT}.done" ]; then
        rm -f "${MARKER_FILE}" "${DETAIL_FILE}" 2>/dev/null || true
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
    # python3 fallback when jq unavailable
    if [ -z "${D_TOOL:-}" ] && [ -f "${DETAIL_FILE:-}" ]; then
        D_TOOL="$(python3 -c "
import json
try:
    d = json.load(open('${DETAIL_FILE}'))
    print(d.get('tool_name') or '')
except: pass
" 2>/dev/null || true)"
    fi
    if [ -z "${D_INPUT:-}" ] && [ -f "${DETAIL_FILE:-}" ]; then
        D_INPUT="$(python3 -c "
import json
try:
    d = json.load(open('${DETAIL_FILE}'))
    print(d.get('tool_input') or '')
except: pass
" 2>/dev/null || true)"
    fi
    if [ -z "${D_EVENT:-}" ] && [ -f "${DETAIL_FILE:-}" ]; then
        D_EVENT="$(python3 -c "
import json
try:
    d = json.load(open('${DETAIL_FILE}'))
    print(d.get('hook_event') or '')
except: pass
" 2>/dev/null || true)"
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
    # 递减并发计数
    if [ -f "${COUNTER_FILE}" ]; then
        _cnt=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "1")
        _cnt=$(( _cnt - 1 ))
        [ "${_cnt}" -le 0 ] && rm -f "${COUNTER_FILE}" || echo "${_cnt}" > "${COUNTER_FILE}"
    fi

) &>/dev/null &
TIMER_PID=$!
echo "${TIMER_PID}" > "${PID_FILE}" 2>/dev/null || true
# 递增并发计数
echo $(( _active_count + 1 )) > "${COUNTER_FILE}" 2>/dev/null || true
disown

# hook 本身立即返回，不阻塞 CC 主流程
exit 0
