#!/usr/bin/env bash
# FAIL_MODE=open — hook 自身故障时静默放行，不阻塞 Claude Code
# wait-notify.sh — PermissionRequest / Notification Hook
# 触发时机：Claude Code 等待用户操作（权限审批、通知等）
# 机制：写入等待标记 + 启动后台定时器，超时后发送飞书通知
# 安全约束：遵循 Iris 风控报告规范

set -uo pipefail

# === Load common functions ===
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# === 安全隔离 ===
unset ANTHROPIC_API_KEY OPENAI_API_KEY ANTHROPIC_AUTH_TOKEN
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# === 加载配置文件（CC Hook 子进程不继承 ~/.zshrc 环境变量）===
_CONF_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/notify.conf"

_safe_source_conf "${_CONF_FILE}"

# 加载凭证隔离文件
_SECRETS_FILE="${HOME}/.cchooks/secrets.env"
_safe_source_conf "${_SECRETS_FILE}"

# === 配置变量（配置文件 > 环境变量 > 默认值）===
WAIT_SECONDS="${CC_WAIT_NOTIFY_SECONDS:-30}"
NOTIFY_CHANNEL="${CC_NOTIFY_CHANNEL:-feishu}"
NOTIFY_TARGET="${CC_NOTIFY_TARGET:-}"
MARKER_DIR="${CCHOOKS_TMPDIR:-/tmp/cchooks}/wait"
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
NOTIFY_MESSAGE=""
NOTIFY_TYPE=""

if command -v jq &>/dev/null && [ -n "${STDIN_JSON}" ]; then
    SESSION_ID="$(echo "${STDIN_JSON}" | jq -r '.session_id // empty' 2>/dev/null || true)"
    TOOL_NAME="$(echo "${STDIN_JSON}" | jq -r '.tool_name // empty' 2>/dev/null || true)"
    HOOK_EVENT="$(echo "${STDIN_JSON}" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
    # 尝试提取命令（Bash）、文件路径（Write/Edit）、或问题内容（AskUserQuestion 等）
    TOOL_INPUT_CMD="$(echo "${STDIN_JSON}" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.path // .tool_input.question // .tool_input.text // .tool_input.content // (.tool_input | tostring | if length > 200 then .[:200] + "..." else . end) // empty' 2>/dev/null || true)"
    NOTIFY_MESSAGE="$(echo "${STDIN_JSON}" | jq -r '.message // empty' 2>/dev/null || true)"
    NOTIFY_TYPE="$(echo "${STDIN_JSON}" | jq -r '.notification_type // empty' 2>/dev/null || true)"
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
# python3 fallback for NOTIFY_MESSAGE
if [ -z "${NOTIFY_MESSAGE:-}" ] && [ -n "${STDIN_JSON:-}" ]; then
    NOTIFY_MESSAGE="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('message') or '')
except: pass
" 2>/dev/null || true)"
fi
# python3 fallback for NOTIFY_TYPE
if [ -z "${NOTIFY_TYPE:-}" ] && [ -n "${STDIN_JSON:-}" ]; then
    NOTIFY_TYPE="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('notification_type') or '')
except: pass
" 2>/dev/null || true)"
fi

SESSION_ID="${SESSION_ID:-${CLAUDE_TASK_ID:-unknown}}"
SESSION_SHORT="${SESSION_ID:0:8}"
HOOK_EVENT="${HOOK_EVENT:-PermissionRequest}"

# === 提取原始 tool_input JSON（供后台定时器格式化用）===
TOOL_INPUT_RAW=""
if [ -n "${STDIN_JSON}" ]; then
    if command -v jq &>/dev/null; then
        TOOL_INPUT_RAW="$(echo "${STDIN_JSON}" | jq -c '.tool_input // empty' 2>/dev/null || true)"
    fi
    if [ -z "${TOOL_INPUT_RAW:-}" ]; then
        TOOL_INPUT_RAW="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input')
    if ti is not None:
        print(json.dumps(ti, ensure_ascii=False))
except: pass
" 2>/dev/null || true)"
    fi
fi

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

# === 原子计数器锁函数（mkdir + stale 检测 + 3 次重试）===
_counter_lock() {
    local lock_dir="${MARKER_DIR}/${SESSION_SHORT}.counter.lock"
    local i
    for i in 1 2 3; do
        if mkdir "${lock_dir}" 2>/dev/null; then
            echo $$ > "${lock_dir}/owner" 2>/dev/null
            return 0
        fi
        # Stale lock detection: owner process gone?
        local owner_pid
        owner_pid=$(cat "${lock_dir}/owner" 2>/dev/null || echo "")
        if [ -n "${owner_pid}" ] && ! _kill_check "${owner_pid}"; then
            rm -rf "${lock_dir}" 2>/dev/null || true
            continue
        fi
        _sleep_frac 0.05
    done
    return 1
}
_counter_unlock() {
    rm -rf "${MARKER_DIR}/${SESSION_SHORT}.counter.lock" 2>/dev/null || true
}

# === 死循环防护：检查当前活跃定时器数 ===
_active_count=0
if [ -f "${COUNTER_FILE}" ]; then
    _active_count=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "0")
fi
if [ "${_active_count}" -ge "${MAX_CONCURRENT_TIMERS}" ]; then
    _log_jsonl "{\"ts\":\"$(_date_iso)\",\"hook\":\"wait-notify\",\"event\":\"circuit_breaker\",\"session\":\"${SESSION_SHORT}\",\"reason\":\"max_concurrent_timers_${MAX_CONCURRENT_TIMERS}\"}"
    exit 0
fi

# === 全局冷却防护 ===
COOLDOWN_FILE="${MARKER_DIR}/${SESSION_SHORT}.cooldown"
if [ -f "${COOLDOWN_FILE}" ]; then
    _cd_ts=$(cat "${COOLDOWN_FILE}" 2>/dev/null || echo "0")
    _now_ts=$(date +%s)
    if [ $(( _now_ts - _cd_ts )) -lt "${GLOBAL_COOLDOWN_SECONDS}" ]; then
        # 冷却期内 PermissionRequest 升级 detail（修复乱序问题）
        if [ "${HOOK_EVENT}" = "PermissionRequest" ] && [ -n "${TOOL_NAME:-}" ]; then
            _UPGRADE_DETAIL="${MARKER_DIR}/${SESSION_SHORT}.detail"
            if [ -f "${_UPGRADE_DETAIL}" ]; then
                SESSION_ID="${SESSION_ID}" \
                SESSION_SHORT="${SESSION_SHORT}" \
                TOOL_NAME="${TOOL_NAME}" \
                TOOL_INPUT_CMD="${TOOL_INPUT_CMD}" \
                HOOK_EVENT="${HOOK_EVENT}" \
                NOTIFY_MESSAGE="${NOTIFY_MESSAGE}" \
                NOTIFY_TYPE="${NOTIFY_TYPE}" \
                _TOOL_INPUT_RAW="${TOOL_INPUT_RAW:-}" \
                python3 -c "
import json, os
d = {
    'session_id': os.environ.get('SESSION_ID', ''),
    'session_short': os.environ.get('SESSION_SHORT', ''),
    'tool_name': os.environ.get('TOOL_NAME', ''),
    'tool_input': os.environ.get('TOOL_INPUT_CMD', ''),
    'tool_input_raw': None,
    'hook_event': os.environ.get('HOOK_EVENT', ''),
    'notify_message': os.environ.get('NOTIFY_MESSAGE', ''),
    'notify_type': os.environ.get('NOTIFY_TYPE', ''),
}
raw = os.environ.get('_TOOL_INPUT_RAW', '')
if raw:
    try: d['tool_input_raw'] = json.loads(raw)
    except: pass
json.dump(d, open('${_UPGRADE_DETAIL}', 'w'), indent=2, ensure_ascii=False)
" 2>/dev/null || true
            fi
        fi
        exit 0
    fi
fi
date +%s > "${COOLDOWN_FILE}" 2>/dev/null || true

# === 杀旧定时器（kill-old-before-new）===
if [ -f "${PID_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}" 2>/dev/null || echo "")
    if [ -n "${OLD_PID}" ] && _kill_check "${OLD_PID}"; then
        # 身份校验：确认是 sleep 进程，防止 PID reuse 误杀
        OLD_CMD=$(_ps_command_of "${OLD_PID}")
        if echo "${OLD_CMD}" | grep -q "sleep"; then
            kill "${OLD_PID}" 2>/dev/null || true
        fi
    fi
    rm -f "${PID_FILE}"
    # 递减计数器（旧 timer 被杀，其 subshell 不会自行递减）
    if [ -f "${COUNTER_FILE}" ]; then
        if _counter_lock; then
            _cnt=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "1")
            _cnt=$(( _cnt - 1 ))
            if [ "${_cnt}" -le 0 ]; then
                rm -f "${COUNTER_FILE}"
                _active_count=0
            else
                echo "${_cnt}" > "${COUNTER_FILE}"
                _active_count="${_cnt}"
            fi
            _counter_unlock
        else
            # Fallback: 无锁操作（宁可 TOCTOU 也不能漏计）
            _cnt=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "1")
            _cnt=$(( _cnt - 1 ))
            if [ "${_cnt}" -le 0 ]; then
                rm -f "${COUNTER_FILE}"
                _active_count=0
            else
                echo "${_cnt}" > "${COUNTER_FILE}"
                _active_count="${_cnt}"
            fi
        fi
    fi
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

# === 将上下文信息写入 detail 文件（python3 安全 JSON 生成）===
DETAIL_FILE="${MARKER_DIR}/${SESSION_SHORT}.detail"
SESSION_ID="${SESSION_ID}" \
SESSION_SHORT="${SESSION_SHORT}" \
TOOL_NAME="${TOOL_NAME}" \
TOOL_INPUT_CMD="${TOOL_INPUT_CMD}" \
HOOK_EVENT="${HOOK_EVENT}" \
NOTIFY_MESSAGE="${NOTIFY_MESSAGE}" \
NOTIFY_TYPE="${NOTIFY_TYPE}" \
_TOOL_INPUT_RAW="${TOOL_INPUT_RAW:-}" \
python3 -c "
import json, os, sys
d = {
    'session_id': os.environ.get('SESSION_ID', ''),
    'session_short': os.environ.get('SESSION_SHORT', ''),
    'tool_name': os.environ.get('TOOL_NAME', ''),
    'tool_input': os.environ.get('TOOL_INPUT_CMD', ''),
    'tool_input_raw': None,
    'hook_event': os.environ.get('HOOK_EVENT', ''),
    'notify_message': os.environ.get('NOTIFY_MESSAGE', ''),
    'notify_type': os.environ.get('NOTIFY_TYPE', ''),
}
raw = os.environ.get('_TOOL_INPUT_RAW', '')
if raw:
    try: d['tool_input_raw'] = json.loads(raw)
    except: pass
json.dump(d, sys.stdout, indent=2, ensure_ascii=False)
print()
" > "${DETAIL_FILE}" 2>/dev/null || echo '{"session_id":"'"${SESSION_SHORT}"'","hook_event":"'"${HOOK_EVENT}"'"}' > "${DETAIL_FILE}"

# === 检查任务是否已完成（.done 文件存在则跳过）===
DONE_DIR="${CCHOOKS_TMPDIR:-/tmp/cchooks}"
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
    D_INPUT_RAW=""
    D_EVENT=""
    D_NOTIFY_TYPE=""
    if [ -f "${DETAIL_FILE}" ] && command -v jq &>/dev/null; then
        D_TOOL="$(jq -r '.tool_name // empty' "${DETAIL_FILE}" 2>/dev/null || true)"
        D_INPUT="$(jq -r '.tool_input // empty' "${DETAIL_FILE}" 2>/dev/null || true)"
        D_INPUT_RAW="$(jq -c '.tool_input_raw // empty' "${DETAIL_FILE}" 2>/dev/null || true)"
        D_EVENT="$(jq -r '.hook_event // empty' "${DETAIL_FILE}" 2>/dev/null || true)"
        D_NOTIFY_TYPE="$(jq -r '.notify_type // empty' "${DETAIL_FILE}" 2>/dev/null || true)"
    fi
    # python3 fallback when jq unavailable (stdin redirect for Windows compat)
    if [ -z "${D_TOOL:-}" ] && [ -f "${DETAIL_FILE:-}" ]; then
        D_TOOL="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name') or '')
except: pass
" < "${DETAIL_FILE}" 2>/dev/null || true)"
    fi
    if [ -z "${D_INPUT:-}" ] && [ -f "${DETAIL_FILE:-}" ]; then
        D_INPUT="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input') or '')
except: pass
" < "${DETAIL_FILE}" 2>/dev/null || true)"
    fi
    if [ -z "${D_INPUT_RAW:-}" ] && [ -f "${DETAIL_FILE:-}" ]; then
        D_INPUT_RAW="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    raw = d.get('tool_input_raw')
    if raw is not None:
        print(json.dumps(raw, ensure_ascii=False))
except: pass
" < "${DETAIL_FILE}" 2>/dev/null || true)"
    fi
    if [ -z "${D_EVENT:-}" ] && [ -f "${DETAIL_FILE:-}" ]; then
        D_EVENT="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('hook_event') or '')
except: pass
" < "${DETAIL_FILE}" 2>/dev/null || true)"
    fi
    if [ -z "${D_NOTIFY_TYPE:-}" ] && [ -f "${DETAIL_FILE:-}" ]; then
        D_NOTIFY_TYPE="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('notify_type') or '')
except: pass
" < "${DETAIL_FILE}" 2>/dev/null || true)"
    fi

    # 构建消息内容
    EVENT_LABEL="权限审批"
    # permission_prompt 类型的 Notification 也归类为"权限审批"
    if [ "${D_EVENT}" = "Notification" ] && [ "${D_NOTIFY_TYPE}" != "permission_prompt" ]; then
        EVENT_LABEL="通知确认"
    fi
    # Notification 路径无 tool_name 时用 notification_type 填充
    if [ -z "${D_TOOL:-}" ] && [ -n "${D_NOTIFY_TYPE:-}" ]; then D_TOOL="${D_NOTIFY_TYPE}"; fi

    # === 智能格式化 tool_input（将 JSON 结构化为可读文本）===
    # 优先使用 tool_input_raw（原始 JSON 对象），fallback 到 tool_input（字符串摘要）
    _FORMAT_SOURCE="${D_INPUT_RAW:-${D_INPUT:-}}"
    FORMATTED_INPUT="${D_INPUT:-无}"
    if [ -n "${_FORMAT_SOURCE:-}" ]; then
        _MAYBE_FORMATTED="$(printf '%s' "${_FORMAT_SOURCE}" | python3 -c "
import json, sys
try:
    raw = sys.stdin.read()
    d = json.loads(raw) if raw.strip().startswith('{') or raw.strip().startswith('[') else None
    if d is None:
        print(raw[:500])
        sys.exit(0)
    lines = []
    # AskUserQuestion: format question + options
    questions = d.get('questions') or d.get('question')
    if isinstance(questions, list):
        for q in questions:
            header = q.get('header') or ''
            question = q.get('question') or ''
            if header:
                lines.append(f'📋 {header}')
            if question:
                lines.append(f'❓ {question}')
            options = q.get('options') or []
            for i, opt in enumerate(options, 1):
                label = opt.get('label') or str(opt)
                desc = opt.get('description') or ''
                if desc:
                    lines.append(f'  {i}. {label} — {desc}')
                else:
                    lines.append(f'  {i}. {label}')
    elif isinstance(questions, str):
        lines.append(f'❓ {questions}')
    elif d.get('command'):
        lines.append(d['command'][:500])
    elif d.get('question'):
        lines.append(f\"❓ {d['question']}\")
    elif d.get('text'):
        lines.append(d['text'][:500])
    else:
        lines.append(json.dumps(d, ensure_ascii=False, indent=2)[:500])
    print('\n'.join(lines))
except:
    print(raw[:500] if 'raw' in dir() else '')
" 2>/dev/null || true)"
        if [ -n "${_MAYBE_FORMATTED}" ]; then
            FORMATTED_INPUT="${_MAYBE_FORMATTED}"
        fi
    fi

    NOTIFY_MSG="⏰ Claude Code 等待你操作已超 ${WAIT_SECONDS} 秒！
🆔 Session: ${SESSION_SHORT}
📌 类型: ${EVENT_LABEL}
🔧 工具: ${D_TOOL:-未知}
💻 内容:
${FORMATTED_INPUT}

👉 请回到终端完成操作"

    # 发送通知（通过通用通知层）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # P0-Bug-4 修复：在 source 前检查完整性
    _NOTIFY_SCRIPT="${SCRIPT_DIR}/send-notification.sh"
    if ! _safe_source_conf "${_NOTIFY_SCRIPT}" 2>/dev/null; then
        _cchooks_error "send-notification.sh integrity check failed"
    else
        send_notify "${NOTIFY_MSG}"
    fi

    # 清理标记和详情文件
    rm -f "${MARKER_FILE}" "${DETAIL_FILE}" 2>/dev/null || true
    # 递减并发计数（内联原子锁，subshell 不继承函数）
    if [ -f "${COUNTER_FILE}" ]; then
        if mkdir "${MARKER_DIR}/${SESSION_SHORT}.counter.lock" 2>/dev/null; then
            _cnt=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "1")
            _cnt=$(( _cnt - 1 ))
            [ "${_cnt}" -le 0 ] && rm -f "${COUNTER_FILE}" || echo "${_cnt}" > "${COUNTER_FILE}"
            rm -rf "${MARKER_DIR}/${SESSION_SHORT}.counter.lock" 2>/dev/null || true
        else
            # Fallback: 无锁操作
            _cnt=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "1")
            _cnt=$(( _cnt - 1 ))
            [ "${_cnt}" -le 0 ] && rm -f "${COUNTER_FILE}" || echo "${_cnt}" > "${COUNTER_FILE}"
        fi
    fi

) &>/dev/null &
TIMER_PID=$!
echo "${TIMER_PID}" > "${PID_FILE}" 2>/dev/null || true
# 递增并发计数（原子锁，失败 fallback 无锁写入）
if _counter_lock; then
    _active_count=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "0")
    echo $(( _active_count + 1 )) > "${COUNTER_FILE}" 2>/dev/null || true
    _counter_unlock
else
    _active_count=$(cat "${COUNTER_FILE}" 2>/dev/null || echo "0")
    echo $(( _active_count + 1 )) > "${COUNTER_FILE}" 2>/dev/null || true
fi
disown $TIMER_PID

# hook 本身立即返回，不阻塞 CC 主流程
exit 0
