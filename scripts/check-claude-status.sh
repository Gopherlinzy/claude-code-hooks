#!/usr/bin/env bash
# check-claude-status.sh — Claude Code 任务状态快照
# 用法: check-claude-status.sh <workdir>
# 输出: JSON 格式状态摘要（供 Luna exec 调用）
#
# 状态值:
#   not-dispatched     — .claude-dispatched 不存在，进程未拉起
#   running            — PID 存活，.claude-progress.md 存在
#   running-no-progress — PID 存活，但 .claude-progress.md 不存在
#   completed          — .done 文件存在（Stop Hook 已触发）
#   dead               — PID 不存活，非正常结束
#   unknown            — 无法判定

set -uo pipefail

# === Platform shim (cross-platform compatibility) ===
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platform-shim.sh"

# === Python 兼容（Windows Git Bash：python3 不在 PATH） ===
if ! command -v python3 &>/dev/null && command -v python &>/dev/null; then
    python3() { PYTHONUTF8=1 python "$@"; }
fi

WORKDIR="${1:-.}"
STATUS="unknown"
DETAILS=""
PID="0"
MTIME_AGE=""
STEPS_DONE="0"
STEPS_TOTAL="?"

# 检查 .claude-dispatched（L0 启动信号）
if [[ ! -f "${WORKDIR}/.claude-dispatched" ]]; then
    echo "{\"status\":\"not-dispatched\",\"details\":\"no .claude-dispatched file found\",\"workdir\":\"${WORKDIR}\"}"
    exit 0
fi

# 读取 PID
PID=$(WORKDIR="${WORKDIR}" python3 -c "
import json, os
p = os.path.join(os.environ['WORKDIR'], '.claude-dispatched')
print(json.load(open(p))['pid'])
" 2>/dev/null || echo "0")
TASK_ID=$(WORKDIR="${WORKDIR}" python3 -c "
import json, os
p = os.path.join(os.environ['WORKDIR'], '.claude-dispatched')
print(json.load(open(p))['task_id'])
" 2>/dev/null || echo "unknown")

# 检查 .done 文件（Stop Hook 完成信号）
DONE_FILE="${CCHOOKS_TMPDIR:-/tmp/cchooks}/${TASK_ID}.done"
if [[ -f "${DONE_FILE}" ]]; then
    STATUS="completed"
    DETAILS="task finished (stop hook fired)"
    # 尝试读取进度文件的最终步骤统计
    if [[ -f "${WORKDIR}/.claude-progress.md" ]]; then
        STEPS_DONE=$(grep -c '\[x\]' "${WORKDIR}/.claude-progress.md" 2>/dev/null || echo "0")
        STEPS_TOTAL=$(grep -c '\[ \]\|\[x\]' "${WORKDIR}/.claude-progress.md" 2>/dev/null || echo "?")
        DETAILS="completed ${STEPS_DONE}/${STEPS_TOTAL} steps"
    fi
    echo "{\"status\":\"${STATUS}\",\"details\":\"${DETAILS}\",\"pid\":${PID},\"task_id\":\"${TASK_ID}\",\"workdir\":\"${WORKDIR}\"}"
    exit 0
fi

# 检查 PID 存活
if _kill_check "${PID}"; then
    # PID 存活
    if [[ -f "${WORKDIR}/.claude-progress.md" ]]; then
        # 计算 mtime 年龄
        MTIME=$(_stat_mtime "${WORKDIR}/.claude-progress.md")
        NOW=$(date +%s)
        MTIME_AGE=$(( NOW - MTIME ))
        STEPS_DONE=$(grep -c '\[x\]' "${WORKDIR}/.claude-progress.md" 2>/dev/null || echo "0")
        STEPS_TOTAL=$(grep -c '\[ \]\|\[x\]' "${WORKDIR}/.claude-progress.md" 2>/dev/null || echo "?")
        STATUS="running"
        DETAILS="step ${STEPS_DONE}/${STEPS_TOTAL}, last update ${MTIME_AGE}s ago"
    else
        STATUS="running-no-progress"
        DETAILS="process alive but .claude-progress.md not yet created"
    fi
else
    # PID 不存活
    STATUS="dead"
    DETAILS="PID ${PID} not alive"
    # 检查是否有日志可读
    LOG_FILE="${CCHOOKS_TMPDIR:-/tmp/cchooks}/${TASK_ID}.log"
    if [[ -f "${LOG_FILE}" ]]; then
        LOG_SIZE=$(wc -c < "${LOG_FILE}" 2>/dev/null || echo "0")
        DETAILS="${DETAILS}, log ${LOG_SIZE} bytes"
    fi
fi

STATUS="${STATUS}" \
PID="${PID}" \
TASK_ID="${TASK_ID}" \
MTIME_AGE="${MTIME_AGE:-0}" \
STEPS_DONE="${STEPS_DONE}" \
STEPS_TOTAL="${STEPS_TOTAL}" \
WORKDIR="${WORKDIR}" \
python3 -c "
import json, sys, os
print(json.dumps({
    'status': os.environ.get('STATUS', 'unknown'),
    'details': sys.stdin.read().strip(),
    'pid': int(os.environ.get('PID', '0')),
    'task_id': os.environ.get('TASK_ID', 'unknown'),
    'mtime_age_s': int(os.environ.get('MTIME_AGE', '0')),
    'steps': os.environ.get('STEPS_DONE', '0') + '/' + os.environ.get('STEPS_TOTAL', '?'),
    'workdir': os.environ.get('WORKDIR', '.')
}, ensure_ascii=False))
" <<< "${DETAILS}" 2>/dev/null \
|| echo '{"status":"unknown","details":"output-error"}'
