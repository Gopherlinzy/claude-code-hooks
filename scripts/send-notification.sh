#!/usr/bin/env bash
# send-notification.sh — Universal notification dispatcher
# Supports multiple backends without any OpenClaw dependency.
# Called by other hooks: source this file and call send_notify "message"
#
# Backends: openclaw | slack | telegram | discord | bark | webhook | command
# Configure via notify.conf (CC_NOTIFY_BACKEND + backend-specific vars)

set -uo pipefail

# === Load config ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/notify.conf"
if [ -f "${CONF_FILE}" ]; then
    # shellcheck disable=SC1090
    source "${CONF_FILE}"
fi

CC_NOTIFY_BACKEND="${CC_NOTIFY_BACKEND:-auto}"

# Auto-detect: if openclaw is available, use it; otherwise fall back to webhook/command
if [ "${CC_NOTIFY_BACKEND}" = "auto" ]; then
    if command -v openclaw &>/dev/null; then
        CC_NOTIFY_BACKEND="openclaw"
    elif [ -n "${NOTIFY_FEISHU_URL:-}" ]; then
        CC_NOTIFY_BACKEND="feishu"
    elif [ -n "${NOTIFY_WECOM_URL:-}" ]; then
        CC_NOTIFY_BACKEND="wecom"
    elif [ -n "${CC_SLACK_WEBHOOK_URL:-}" ]; then
        CC_NOTIFY_BACKEND="slack"
    elif [ -n "${CC_TELEGRAM_BOT_TOKEN:-}" ]; then
        CC_NOTIFY_BACKEND="telegram"
    elif [ -n "${CC_DISCORD_WEBHOOK_URL:-}" ]; then
        CC_NOTIFY_BACKEND="discord"
    elif [ -n "${CC_BARK_URL:-}" ]; then
        CC_NOTIFY_BACKEND="bark"
    elif [ -n "${CC_WEBHOOK_URL:-}" ]; then
        CC_NOTIFY_BACKEND="webhook"
    elif [ -n "${CC_NOTIFY_COMMAND:-}" ]; then
        CC_NOTIFY_BACKEND="command"
    else
        # No backend configured — silent exit
        CC_NOTIFY_BACKEND="none"
    fi
fi

# === Backend implementations ===

_notify_openclaw() {
    local msg="$1"
    local channel="${CC_NOTIFY_CHANNEL:-feishu}"
    local target="${CC_NOTIFY_TARGET:-}"
    if [ -z "${target}" ]; then
        echo "[send-notification] ERROR: CC_NOTIFY_TARGET not set" >&2
        return 1
    fi
    openclaw message send \
        --channel "${channel}" \
        --target "${target}" \
        -m "${msg}" \
        2>/dev/null || true
}

_notify_slack() {
    local msg="$1"
    local url="${CC_SLACK_WEBHOOK_URL:-}"
    if [ -z "${url}" ]; then
        echo "[send-notification] ERROR: CC_SLACK_WEBHOOK_URL not set" >&2
        return 1
    fi
    curl -s -X POST "${url}" \
        -H 'Content-Type: application/json' \
        -d "{\"text\": $(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" \
        >/dev/null 2>&1 || true
}

_notify_telegram() {
    local msg="$1"
    local token="${CC_TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${CC_TELEGRAM_CHAT_ID:-}"
    if [ -z "${token}" ] || [ -z "${chat_id}" ]; then
        echo "[send-notification] ERROR: CC_TELEGRAM_BOT_TOKEN or CC_TELEGRAM_CHAT_ID not set" >&2
        return 1
    fi
    curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -H 'Content-Type: application/json' \
        -d "{\"chat_id\": \"${chat_id}\", \"text\": $(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'), \"parse_mode\": \"Markdown\"}" \
        >/dev/null 2>&1 || true
}

_notify_discord() {
    local msg="$1"
    local url="${CC_DISCORD_WEBHOOK_URL:-}"
    if [ -z "${url}" ]; then
        echo "[send-notification] ERROR: CC_DISCORD_WEBHOOK_URL not set" >&2
        return 1
    fi
    curl -s -X POST "${url}" \
        -H 'Content-Type: application/json' \
        -d "{\"content\": $(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" \
        >/dev/null 2>&1 || true
}

_notify_bark() {
    local msg="$1"
    local url="${CC_BARK_URL:-}"
    local title="${CC_BARK_TITLE:-Claude Code}"
    if [ -z "${url}" ]; then
        echo "[send-notification] ERROR: CC_BARK_URL not set" >&2
        return 1
    fi
    # Bark URL format: https://api.day.app/YOUR_KEY/title/body
    local encoded_title encoded_msg
    encoded_title=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${title}'))" 2>/dev/null || echo "${title}")
    encoded_msg=$(printf '%s' "${msg}" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || echo "${msg}")
    curl -s "${url}/${encoded_title}/${encoded_msg}" >/dev/null 2>&1 || true
}

_notify_feishu() {
    local msg="$1"
    local url="${NOTIFY_FEISHU_URL:-}"
    if [ -z "${url}" ]; then
        echo "[send-notification] ERROR: NOTIFY_FEISHU_URL not set" >&2
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
    curl -sS -X POST -H "Content-Type: application/json" -d "${payload}" "${url}" >/dev/null 2>&1 || true
}

_notify_wecom() {
    local msg="$1"
    local url="${NOTIFY_WECOM_URL:-}"
    if [ -z "${url}" ]; then
        echo "[send-notification] ERROR: NOTIFY_WECOM_URL not set" >&2
        return 1
    fi
    local escaped_msg
    escaped_msg=$(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf '%s' "${msg}" | sed 's/"/\\"/g')
    curl -sS -X POST -H "Content-Type: application/json" \
        -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"${escaped_msg}\"}}" \
        "${url}" >/dev/null 2>&1 || true
}

_notify_webhook() {
    local msg="$1"
    local url="${CC_WEBHOOK_URL:-}"
    local method="${CC_WEBHOOK_METHOD:-POST}"
    local content_type="${CC_WEBHOOK_CONTENT_TYPE:-application/json}"
    local body_template="${CC_WEBHOOK_BODY_TEMPLATE:-{\"text\": \"__MESSAGE__\"}}"
    if [ -z "${url}" ]; then
        echo "[send-notification] ERROR: CC_WEBHOOK_URL not set" >&2
        return 1
    fi
    # Escape message for JSON and substitute into template
    local escaped_msg
    escaped_msg=$(printf '%s' "${msg}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf '%s' "${msg}" | sed 's/"/\\"/g; s/\n/\\n/g')
    local body="${body_template//__MESSAGE__/${escaped_msg}}"
    curl -s -X "${method}" "${url}" \
        -H "Content-Type: ${content_type}" \
        -d "${body}" \
        >/dev/null 2>&1 || true
}

_notify_command() {
    local msg="$1"
    local cmd="${CC_NOTIFY_COMMAND:-}"
    if [ -z "${cmd}" ]; then
        echo "[send-notification] ERROR: CC_NOTIFY_COMMAND not set" >&2
        return 1
    fi
    # Pass message as $1 and also via stdin
    printf '%s' "${msg}" | eval "${cmd}" >/dev/null 2>&1 || true
}

# === Public API ===

send_notify() {
    local msg="${1:-}"
    if [ -z "${msg}" ]; then
        return 0
    fi

    case "${CC_NOTIFY_BACKEND}" in
        openclaw)  _notify_openclaw "${msg}" ;;
        slack)     _notify_slack "${msg}" ;;
        telegram)  _notify_telegram "${msg}" ;;
        discord)   _notify_discord "${msg}" ;;
        feishu)    _notify_feishu "${msg}" ;;
        wecom)     _notify_wecom "${msg}" ;;
        bark)      _notify_bark "${msg}" ;;
        webhook)   _notify_webhook "${msg}" ;;
        command)   _notify_command "${msg}" ;;
        none)      return 0 ;;
        *)
            echo "[send-notification] ERROR: unknown backend '${CC_NOTIFY_BACKEND}'" >&2
            return 1
            ;;
    esac
}

# If called directly (not sourced), send the first argument as message
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    send_notify "$@"
fi
