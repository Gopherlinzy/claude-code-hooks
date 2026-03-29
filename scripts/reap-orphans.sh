#!/usr/bin/env bash
# reap-orphans.sh — 清理超时的 Claude Code 孤儿进程
# 扫描 /tmp/openclaw-hooks/*.meta，超过 TIMEOUT_SEC 且 PID 仍存活的任务将被终止

set -euo pipefail

TIMEOUT_SEC=${REAP_TIMEOUT:-1800}  # 默认 30 分钟
META_DIR="/tmp/openclaw-hooks"
NOW=$(date +%s)
REAPED=0

for meta in "${META_DIR}"/*.meta; do
    [ -f "$meta" ] || continue
    TASK_ID=$(basename "$meta" .meta)

    # [F4 补丁] 若对应 .done 存在，直接清理 .meta 不进入 kill 判断
    if [ -f "${META_DIR}/${TASK_ID}.done" ]; then
        rm -f "$meta"
        continue
    fi

    PID=$(python3 -c "import json; print(json.load(open('$meta')).get('pid', 0))" 2>/dev/null || echo 0)
    START=$(python3 -c "import json; print(json.load(open('$meta')).get('start_epoch', 0))" 2>/dev/null || echo 0)
    [ "$PID" -eq 0 ] && continue
    [ "$START" -eq 0 ] && continue
    ELAPSED=$((NOW - START))
    if [ "$ELAPSED" -gt "$TIMEOUT_SEC" ] && kill -0 "$PID" 2>/dev/null; then
        # [F3 补丁] kill 前验证进程命令行包含 "claude"，防止 PID 重用误杀
        PROC_CMD=$(ps -p "$PID" -o command= 2>/dev/null || echo "")
        [[ "$PROC_CMD" != *"claude"* ]] && continue
        echo "[reaper] Killing orphan PID $PID (task: ${TASK_ID}, elapsed: ${ELAPSED}s)"
        kill -TERM "$PID" 2>/dev/null || true
        sleep 2
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
        REAPED=$((REAPED + 1))
    fi
    # 清理已完成任务的 .meta 文件（PID 不存在且已超时）
    if [ "$ELAPSED" -gt "$TIMEOUT_SEC" ] && ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$meta"
    fi
done

[ "$REAPED" -gt 0 ] && echo "[reaper] Reaped $REAPED orphan(s)" || echo "[reaper] No orphans found"
