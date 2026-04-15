#!/bin/bash

# OpenRouter StatusLine - 余额进度条 (仅用于 claude-hud --extra-cmd)
# claude-hud 的 --extra-cmd 不支持 stdin，所以这里只显示余额

set +e

OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$ANTHROPIC_AUTH_TOKEN}"
[[ -z "$OPENROUTER_API_KEY" ]] && echo "No Key" && exit 0

# === 余额进度条 ===
get_balance() {
  local resp=$(curl -s --max-time 2 \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    "https://openrouter.ai/api/v1/key" 2>/dev/null || echo "")

  [[ -z "$resp" ]] && echo "Offline" && return 1

  # 检查是否有错误
  if echo "$resp" | grep -q '"error"'; then
    echo "Auth Failed"
    return 1
  fi

  # 用 python3 解析 JSON（更稳定的兼容性）
  local remaining limit
  remaining=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('limit_remaining',0))" <<<"$resp" 2>/dev/null || echo "0")
  limit=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('limit',0))" <<<"$resp" 2>/dev/null || echo "0")

  # 验证解析结果
  [[ "$remaining" =~ ^[0-9.]+$ ]] || remaining="0"
  [[ "$limit" =~ ^[0-9.]+$ ]] || limit="0"

  if awk "BEGIN { exit ($limit > 0) ? 0 : 1 }"; then
    local percent=$(awk "BEGIN {printf \"%.0f\", $remaining / $limit * 100}")
    local filled=$((percent / 10))
    local empty=$((10 - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar="${bar}▓"; done
    for ((i = 0; i < empty; i++)); do bar="${bar}░"; done
    printf "💰 %.2f/%.0f %s %d%%" "$remaining" "$limit" "$bar" "$percent"
  else
    echo "💰 0/0"
  fi
}

# === 主逻辑 ===
# 仅输出余额信息（给 claude-hud 的 --extra-cmd 拼接）
BALANCE=$(get_balance 2>/dev/null || echo "")
[[ -n "$BALANCE" ]] && echo "$BALANCE"
exit 0
