#!/usr/bin/env bash
# reap-orphans.sh — 清理超时的 Claude Code 孤儿进程
# 扫描 /tmp/cchooks/*.meta，超过 TIMEOUT_SEC 且 PID 仍存活的任务将被终止

set -uo pipefail
_had_error=false
trap '_had_error=true' ERR

# === Load common functions ===
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TIMEOUT_SEC=${REAP_TIMEOUT:-1800}  # 默认 30 分钟
META_DIR="${CCHOOKS_TMPDIR:-/tmp/cchooks}"
NOW=$(date +%s 2>/dev/null || echo "0")
REAPED=0

for meta in "${META_DIR}"/*.meta; do
    [ -f "$meta" ] || continue
    TASK_ID=$(basename "$meta" .meta)

    # [F4 补丁] 若对应 .done 存在，直接清理 .meta 不进入 kill 判断
    if [ -f "${META_DIR}/${TASK_ID}.done" ]; then
        rm -f "$meta"
        continue
    fi

    PID=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('pid', 0))" < "$meta" 2>/dev/null || echo 0)
    START=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('start_epoch', 0))" < "$meta" 2>/dev/null || echo 0)
    [ "$PID" -eq 0 ] && continue
    [ "$START" -eq 0 ] && continue
    ELAPSED=$((NOW - START))
    if [ "$ELAPSED" -gt "$TIMEOUT_SEC" ] && (_kill_check "$PID" 2>/dev/null || true); then
        # [F3 补丁] kill 前验证进程命令行包含 "claude"，防止 PID 重用误杀
        PROC_CMD=$(_ps_command_of "$PID" 2>/dev/null || echo "")
        [[ "$PROC_CMD" != *"claude"* ]] && continue
        echo "[reaper] Killing orphan PID $PID (task: ${TASK_ID}, elapsed: ${ELAPSED}s)"
        kill -TERM "$PID" 2>/dev/null || true
        sleep 2
        (_kill_check "$PID" 2>/dev/null || false) && kill -9 "$PID" 2>/dev/null || true
        REAPED=$((REAPED + 1))
    fi
    # 清理已完成任务的 .meta 文件（PID 不存在且已超时）
    if [ "$ELAPSED" -gt "$TIMEOUT_SEC" ] && ! (_kill_check "$PID" 2>/dev/null || false); then
        rm -f "$meta"
    fi
done

# === 清理过期的 .done 文件（7天以上）===
# 修复：macOS BSD find 不支持 -delete + -print，改用 while loop
_DONE_CLEANED=0
while IFS= read -r -d '' _f; do
    rm -f "${_f}" && _DONE_CLEANED=$(( _DONE_CLEANED + 1 ))
done < <(find "${META_DIR}" -name "*.done" -mtime +7 -print0 2>/dev/null)
[ "${_DONE_CLEANED:-0}" -gt 0 ] && echo "[reaper] Cleaned ${_DONE_CLEANED} expired .done file(s)"

# === 清理过期的 .meta 文件（无进程存活且超过7天）===
find "${META_DIR}" -name "*.meta" -mtime +7 -print0 2>/dev/null | while IFS= read -r -d '' _old_meta; do
    [ -f "${_old_meta}" ] || continue
    _old_pid=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('pid',0))" < "${_old_meta}" 2>/dev/null || echo 0)
    if [ "${_old_pid}" -eq 0 ] || ! (_kill_check "${_old_pid}" 2>/dev/null || false); then
        rm -f "${_old_meta}"
    fi
done

# === 清理孤儿 worktrees（best-effort，覆盖常用路径）===
for wt_dir in ~/.openclaw/workspace-main/.worktrees ~/projects/*/.worktrees; do
    [ -d "${wt_dir}" ] || continue
    _repo_dir="$(dirname "${wt_dir}")"
    # 先清理已失效的 worktree 引用
    git -C "${_repo_dir}" worktree prune 2>/dev/null || true
    # 用 git worktree remove 正确清理（含引用），失败再 fallback rm
    find "${wt_dir}" -maxdepth 1 -type d -name "wt-*" -mtime +7 -print0 2>/dev/null | while IFS= read -r -d '' _wt; do
        [ -d "${_wt}" ] || continue
        (git -C "${_repo_dir}" worktree remove --force "${_wt}" 2>/dev/null || rm -rf "${_wt}" 2>/dev/null || true)
    done
done

[ "$REAPED" -gt 0 ] && echo "[reaper] Reaped $REAPED orphan(s)" || echo "[reaper] No orphans found"
