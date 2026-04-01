#!/usr/bin/env bash
# send-notification.sh — Universal notification dispatcher (v2: broadcast mode)
# Supports multiple backends without any OpenClaw dependency.
# Called by other hooks: source this file and call send_notify "message"
#
# Mode:
#   auto     — Discover ALL configured backends → broadcast to all of them
#   explicit — CC_NOTIFY_BACKEND=feishu,slack,bark → broadcast to listed backends
#   single   — CC_NOTIFY_BACKEND=feishu → single backend (backward-compatible)
#
# Backends: openclaw | feishu | wecom | slack | telegram | discord | bark | webhook | command
# Configure via notify.conf (CC_NOTIFY_BACKEND + backend-specific vars)

set -uo pipefail

# === Python 兼容（Windows Git Bash：python3 不在 PATH） ===
if ! command -v python3 &>/dev/null && command -v python &>/dev/null; then
    python3() { PYTHONUTF8=1 python "$@"; }
fi

# === Load config ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/notify.conf"
if [ -f "${CONF_FILE}" ]; then
    # shellcheck disable=SC1090
    source "${CONF_FILE}"
fi

CC_NOTIFY_BACKEND="${CC_NOTIFY_BACKEND:-auto}"

# === Build backend list ===
# auto: discover ALL configured backends (broadcast to all)
# explicit list: "feishu,slack" → broadcast to both
# single: "feishu" → just that one (backward-compatible)

_CC_BACKENDS=""

if [ "${CC_NOTIFY_BACKEND}" = "auto" ]; then
    # Discover all configured backends — order is cosmetic, all will fire
    command -v openclaw &>/dev/null && [ -n "${CC_NOTIFY_TARGET:-}" ] && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}openclaw"
    [ -n "${NOTIFY_FEISHU_URL:-}" ]       && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}feishu"
    [ -n "${NOTIFY_WECOM_URL:-}" ]        && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}wecom"
    [ -n "${CC_SLACK_WEBHOOK_URL:-}" ]    && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}slack"
    [ -n "${CC_TELEGRAM_BOT_TOKEN:-}" ]   && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}telegram"
    [ -n "${CC_DISCORD_WEBHOOK_URL:-}" ]  && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}discord"
    [ -n "${CC_BARK_URL:-}" ]             && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}bark"
    [ -n "${CC_WEBHOOK_URL:-}" ]          && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}webhook"
    [ -n "${CC_NOTIFY_COMMAND:-}" ]       && _CC_BACKENDS="${_CC_BACKENDS:+${_CC_BACKENDS},}command"

    if [ -z "${_CC_BACKENDS}" ]; then
        _CC_BACKENDS="none"
    fi
else
    # User-specified: single or comma-separated list
    _CC_BACKENDS="${CC_NOTIFY_BACKEND}"
fi

# === Backend implementations ===

_notify_openclaw() {
    local msg="$1"
    local channel="${CC_NOTIFY_CHANNEL:-feishu}"
    local target="${CC_NOTIFY_TARGET:-}"
    if [ -z "${target}" ]; then
        echo "[send-notification] WARN: openclaw backend skipped — CC_NOTIFY_TARGET not set" >&2
        return 1
    fi
    openclaw message send \
        --channel "${channel}" \
        --target "${target}" \
        -m "${msg}" \
        2>/dev/null || return 1
}

_notify_slack() {
    local msg="$1"
    local url="${CC_SLACK_WEBHOOK_URL:-}"
    if [ -z "${url}" ]; then
        echo "[send-notification] WARN: slack backend skipped — CC_SLACK_WEBHOOK_URL not set" >&2
        return 1
    fi
    curl -s -X POST "${url}" \
        -H 'Content-Type: application/json' \
        -d "{\"text\": $(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" \
        >/dev/null 2>&1 || return 1
}

_notify_telegram() {
    local msg="$1"
    local token="${CC_TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${CC_TELEGRAM_CHAT_ID:-}"
    if [ -z "${token}" ] || [ -z "${chat_id}" ]; then
        echo "[send-notification] WARN: telegram backend skipped — CC_TELEGRAM_BOT_TOKEN or CC_TELEGRAM_CHAT_ID not set" >&2
        return 1
    fi
    curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -H 'Content-Type: application/json' \
        -d "{\"chat_id\": \"${chat_id}\", \"text\": $(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'), \"parse_mode\": \"Markdown\"}" \
        >/dev/null 2>&1 || return 1
}

_notify_discord() {
    local msg="$1"
    local url="${CC_DISCORD_WEBHOOK_URL:-}"
    if [ -z "${url}" ]; then
        echo "[send-notification] WARN: discord backend skipped — CC_DISCORD_WEBHOOK_URL not set" >&2
        return 1
    fi
    curl -s -X POST "${url}" \
        -H 'Content-Type: application/json' \
        -d "{\"content\": $(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" \
        >/dev/null 2>&1 || return 1
}

_notify_bark() {
    local msg="$1"
    local url="${CC_BARK_URL:-}"
    local title="${CC_BARK_TITLE:-Claude Code}"
    if [ -z "${url}" ]; then
        echo "[send-notification] WARN: bark backend skipped — CC_BARK_URL not set" >&2
        return 1
    fi
    local encoded_title encoded_msg
    encoded_title=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${title}'))" 2>/dev/null || echo "${title}")
    encoded_msg=$(printf '%s' "${msg}" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo "${msg}")
    curl -s "${url}/${encoded_title}/${encoded_msg}" >/dev/null 2>&1 || return 1
}

_notify_feishu() {
    local msg="$1"
    local url="${NOTIFY_FEISHU_URL:-}"
    if [ -z "${url}" ]; then
        echo "[send-notification] WARN: feishu backend skipped — NOTIFY_FEISHU_URL not set" >&2
        return 1
    fi
    local escaped_msg
    escaped_msg=$(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf '%s' "${msg}" | sed 's/"/\\"/g')
    local payload
    if [ -n "${NOTIFY_FEISHU_SECRET:-}" ]; then
        local timestamp
        timestamp=$(date +%s)
        local sign_str="${timestamp}\n${NOTIFY_FEISHU_SECRET}"
        local sign
        sign=$(printf '%b' "${sign_str}" | openssl dgst -sha256 -hmac "${NOTIFY_FEISHU_SECRET}" -binary | base64)
        payload="{\"timestamp\":\"${timestamp}\",\"sign\":\"${sign}\",\"msg_type\":\"text\",\"content\":{\"text\":\"${escaped_msg}\"}}"
    else
        payload="{\"msg_type\":\"text\",\"content\":{\"text\":\"${escaped_msg}\"}}"
    fi
    curl -sS -X POST -H "Content-Type: application/json" -d "${payload}" "${url}" >/dev/null 2>&1 || return 1
}

_notify_wecom() {
    local msg="$1"
    local url="${NOTIFY_WECOM_URL:-}"
    if [ -z "${url}" ]; then
        echo "[send-notification] WARN: wecom backend skipped — NOTIFY_WECOM_URL not set" >&2
        return 1
    fi
    local escaped_msg
    escaped_msg=$(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf '%s' "${msg}" | sed 's/"/\\"/g')
    curl -sS -X POST -H "Content-Type: application/json" \
        -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"${escaped_msg}\"}}" \
        "${url}" >/dev/null 2>&1 || return 1
}

_notify_webhook() {
    local msg="$1"
    local url="${CC_WEBHOOK_URL:-}"
    local method="${CC_WEBHOOK_METHOD:-POST}"
    local content_type="${CC_WEBHOOK_CONTENT_TYPE:-application/json}"
    local body_template="${CC_WEBHOOK_BODY_TEMPLATE:-{\"text\": \"__MESSAGE__\"}}"
    if [ -z "${url}" ]; then
        echo "[send-notification] WARN: webhook backend skipped — CC_WEBHOOK_URL not set" >&2
        return 1
    fi
    local escaped_msg
    escaped_msg=$(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf '%s' "${msg}" | sed 's/"/\\"/g; s/\n/\\n/g')
    local body="${body_template//__MESSAGE__/${escaped_msg}}"
    curl -s -X "${method}" "${url}" \
        -H "Content-Type: ${content_type}" \
        -d "${body}" \
        >/dev/null 2>&1 || return 1
}

_notify_command() {
    local msg="$1"
    local cmd="${CC_NOTIFY_COMMAND:-}"
    if [ -z "${cmd}" ]; then
        echo "[send-notification] WARN: command backend skipped — CC_NOTIFY_COMMAND not set" >&2
        return 1
    fi
    printf '%s' "${msg}" | eval "${cmd}" >/dev/null 2>&1 || return 1
}

# === Public API ===

send_notify() {
    local msg="${1:-}"
    if [ -z "${msg}" ]; then
        return 0
    fi

    local _any_success=0

    # Broadcast: iterate ALL backends in the list
    IFS=',' read -ra _backend_list <<< "${_CC_BACKENDS}"
    for _backend in "${_backend_list[@]}"; do
        # Trim whitespace
        _backend="$(echo "${_backend}" | tr -d ' ')"
        case "${_backend}" in
            openclaw)  _notify_openclaw "${msg}"  && _any_success=1 ;;
            slack)     _notify_slack "${msg}"     && _any_success=1 ;;
            telegram)  _notify_telegram "${msg}"  && _any_success=1 ;;
            discord)   _notify_discord "${msg}"   && _any_success=1 ;;
            feishu)    _notify_feishu "${msg}"    && _any_success=1 ;;
            wecom)     _notify_wecom "${msg}"     && _any_success=1 ;;
            bark)      _notify_bark "${msg}"      && _any_success=1 ;;
            webhook)   _notify_webhook "${msg}"   && _any_success=1 ;;
            command)   _notify_command "${msg}"   && _any_success=1 ;;
            none)
                # First-run hint: tell user no backend is configured (one-shot)
                local _hint_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                local _hint_file="${_hint_dir}/.first-run-hint-shown"
                if [ ! -f "${_hint_file}" ]; then
                    echo "[cchooks] No notification backend configured. Edit notify.conf in ${_hint_dir}/ to set up Feishu, Slack, or other backends." >&2
                    touch "${_hint_file}" 2>/dev/null || true
                fi
                ;;
            *)
                echo "[send-notification] WARN: unknown backend '${_backend}', skipping" >&2
                ;;
        esac
    done

    if [ "${_any_success}" -eq 0 ] && [ "${_CC_BACKENDS}" != "none" ]; then
        echo "[send-notification] WARN: all backends failed for this message" >&2
    fi

    return 0
}

# If called directly (not sourced), send the first argument as message
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    send_notify "$@"
fi
