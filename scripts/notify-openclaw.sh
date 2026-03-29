#!/usr/bin/env bash
# notify-openclaw.sh — Claude Code Stop Hook
# 触发时机：Claude Code 任务结束（Stop Hook）
# 从 stdin 读取 JSON 获取 session_id、stop_reason 等信息
# 安全约束：Security best practices

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

# === 常量 ===
HOOK_DIR="~/.openclaw/scripts/claude-hooks"
DONE_DIR="/tmp/openclaw-hooks"
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

# === 审计日志 (P3 安全加固) ===
echo "[$(date -Iseconds)] COMPLETE session_id=${TASK_ID_SHORT} name=${TASK_NAME} stop_reason=${STOP_REASON} event=stop" >> ~/.openclaw/logs/audit.log 2>/dev/null || true

# === 清理锁文件 ===
rm -f "${LOCK_FILE}"

# === 信号通道 1：唤醒 OpenClaw 本地网关（仅限 localhost）===
# 使用 env -i 确保最小化环境，防止意外变量泄漏
env -i PATH="${PATH}" \
    curl -s -X POST "http://127.0.0.1:YOUR_GATEWAY_PORT/api/cron/wake" \
    -H "Content-Type: application/json" \
    -d "{\"text\": \"Claude Code session done: ${TASK_ID_SHORT} (${TASK_NAME})\", \"mode\": \"now\"}" \
    --max-time 5 \
    --connect-timeout 3 \
    || true

# === 信号通道 2：飞书推送给指挥官 ===
FEISHU_TARGET="YOUR_FEISHU_TARGET_ID"
NOTIFY_MSG="🤖 Claude Code 任务完成！
📋 任务: ${TASK_NAME}
🆔 Session: ${TASK_ID_SHORT}
🛑 停止原因: ${STOP_REASON}
⏰ 时间: ${TIMESTAMP}
📦 结果文件: ${DONE_FILE}"

openclaw message send \
    --channel feishu \
    --target "${FEISHU_TARGET}" \
    -m "${NOTIFY_MSG}" \
    2>/dev/null || true

# 始终以 0 退出，不影响 Claude Code 主进程
exit 0
