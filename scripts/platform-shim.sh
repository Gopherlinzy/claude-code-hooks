#!/usr/bin/env bash
# platform-shim.sh — Platform detection & compatibility layer for Git Bash (MSYS2/MINGW)
# Source this file at the top of any hook script that needs cross-platform support.
#
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/platform-shim.sh"
#
# Provides:
#   CCHOOKS_PLATFORM   — "macos" | "linux" | "wsl2" | "gitbash" | "unknown"
#   _ps_command_of()   — portable "get command of PID" (replaces ps -p $PID -o command=)
#   _kill_check()      — portable kill -0 check
#   _env_clean()       — portable env -i replacement
#   _find_mtime()      — portable find -mtime wrapper
#   _stat_mtime()      — portable stat mtime-in-epoch
#   _nohup_bg()        — portable nohup + disown wrapper
#   _atomic_mkdir()    — portable atomic lock via mkdir
#   _sleep_frac()      — portable fractional sleep (Git Bash lacks sleep 0.05)

# === Platform Detection ===
CCHOOKS_PLATFORM="unknown"
case "$(uname -s)" in
    Darwin)  CCHOOKS_PLATFORM="macos" ;;
    Linux)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            CCHOOKS_PLATFORM="wsl2"
        else
            CCHOOKS_PLATFORM="linux"
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*)
        CCHOOKS_PLATFORM="gitbash"
        ;;
esac
export CCHOOKS_PLATFORM

# === Portable PID command lookup ===
# macOS/Linux: ps -p PID -o command=
# Git Bash: wmic or tasklist fallback
_ps_command_of() {
    local pid="$1"
    if [ "${CCHOOKS_PLATFORM}" = "gitbash" ]; then
        # Git Bash: use wmic if available, else tasklist
        if command -v wmic &>/dev/null; then
            wmic process where "ProcessId=${pid}" get CommandLine 2>/dev/null | sed -n '2p' | tr -d '\r'
        elif command -v tasklist &>/dev/null; then
            tasklist /FI "PID eq ${pid}" /FO CSV /NH 2>/dev/null | head -1 | cut -d',' -f1 | tr -d '"'
        else
            echo ""
        fi
    else
        ps -p "${pid}" -o command= 2>/dev/null || echo ""
    fi
}

# === Portable kill -0 (process existence check) ===
_kill_check() {
    local pid="$1"
    if [ "${CCHOOKS_PLATFORM}" = "gitbash" ]; then
        tasklist /FI "PID eq ${pid}" /NH 2>/dev/null | grep -q "${pid}" 2>/dev/null
    else
        kill -0 "${pid}" 2>/dev/null
    fi
}

# === Portable env -i (clean environment execution) ===
_env_clean() {
    if [ "${CCHOOKS_PLATFORM}" = "gitbash" ]; then
        # Git Bash: env -i not available, manually unset common vars
        (
            unset ANTHROPIC_API_KEY OPENAI_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY 2>/dev/null
            "$@"
        )
    else
        env -i PATH="${PATH}" "$@"
    fi
}

# === Portable find -mtime ===
_find_mtime() {
    local dir="$1" name="$2" days="$3"
    if [ "${CCHOOKS_PLATFORM}" = "gitbash" ]; then
        # Git Bash: find -mtime may not work, use python3 fallback
        # 变量走 env 传入，消除注入面
        _FM_DIR="${dir}" _FM_NAME="${name}" _FM_DAYS="${days}" python3 -c "
import os, time, glob
cutoff = time.time() - (int(os.environ['_FM_DAYS']) * 86400)
for f in glob.glob(os.path.join(os.environ['_FM_DIR'], os.environ['_FM_NAME'])):
    if os.path.getmtime(f) < cutoff:
        print(f)
" 2>/dev/null
    else
        find "${dir}" -name "${name}" -mtime "+${days}" 2>/dev/null
    fi
}

# === Portable stat mtime (epoch seconds) ===
_stat_mtime() {
    local file="$1"
    if [ "${CCHOOKS_PLATFORM}" = "macos" ]; then
        stat -f %m "${file}" 2>/dev/null || echo "0"
    elif [ "${CCHOOKS_PLATFORM}" = "gitbash" ]; then
        _SM_FILE="${file}" python3 -c "import os; print(int(os.path.getmtime(os.environ['_SM_FILE'])))" 2>/dev/null || echo "0"
    else
        stat -c %Y "${file}" 2>/dev/null || echo "0"
    fi
}

# === Portable nohup + disown ===
_nohup_bg() {
    # $@ = the command to run in background
    if [ "${CCHOOKS_PLATFORM}" = "gitbash" ]; then
        # Git Bash: nohup may not work, use start /B or simple &
        "$@" </dev/null &>/dev/null &
        echo $!
    else
        nohup "$@" </dev/null &>/dev/null &
        local pid=$!
        disown ${pid} 2>/dev/null || true
        echo ${pid}
    fi
}

# === Portable atomic mkdir lock ===
_atomic_mkdir() {
    local lock_dir="$1"
    if [ "${CCHOOKS_PLATFORM}" = "gitbash" ]; then
        # Git Bash: mkdir may not be atomic on NTFS, add retry
        local i
        for i in 1 2 3 4 5; do
            mkdir "${lock_dir}" 2>/dev/null && return 0
            sleep 0.1 2>/dev/null || sleep 1
        done
        return 1
    else
        mkdir "${lock_dir}" 2>/dev/null
    fi
}

# === Portable fractional sleep ===
_sleep_frac() {
    local secs="$1"
    sleep "${secs}" 2>/dev/null || sleep 1
}

# === Portable ISO-8601 timestamp (date -Iseconds replacement) ===
_date_iso() {
    date -Iseconds 2>/dev/null || \
    python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).astimezone().isoformat(timespec='seconds'))" 2>/dev/null || \
    date -u +"%Y-%m-%dT%H:%M:%S+00:00"
}

# === Portable /tmp path ===
if [ "${CCHOOKS_PLATFORM}" = "gitbash" ] && [ -z "${CCHOOKS_TMPDIR:-}" ]; then
    # Git Bash: /tmp maps to MSYS temp, use USERPROFILE fallback
    CCHOOKS_TMPDIR="${USERPROFILE:-${TEMP:-/tmp}}/.cchooks-tmp"
    # 归一化路径分隔符（Windows 环境变量用反斜杠）
    CCHOOKS_TMPDIR="${CCHOOKS_TMPDIR//\\//}"
    export CCHOOKS_TMPDIR
    mkdir -p "${CCHOOKS_TMPDIR}" 2>/dev/null || true
fi
