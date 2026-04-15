#!/bin/bash

# OpenRouter StatusLine - 余额 + 费用两行显示

set +e

OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$ANTHROPIC_AUTH_TOKEN}"
[[ -z "$OPENROUTER_API_KEY" ]] && echo '{"label":"No Key"}' && exit 0

JQ=$(command -v jq 2>/dev/null || echo "")

# === 第一行：余额进度条 ===
get_balance() {
  local resp=$(curl -s --max-time 2 \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    "https://openrouter.ai/api/v1/key" 2>/dev/null || echo "")

  [[ -z "$resp" ]] && echo "Offline" && return 1
  echo "$resp" | grep -q '"error"' && echo "Auth Failed" && return 1

  local remaining limit
  remaining=$(echo "$resp" | $JQ -r '.data.limit_remaining // 0' 2>/dev/null || echo "0")
  limit=$(echo "$resp" | $JQ -r '.data.limit // 0' 2>/dev/null || echo "0")

  if awk "BEGIN { exit ($limit > 0) ? 0 : 1 }"; then
    local percent=$(awk "BEGIN {printf \"%.0f\", $remaining / $limit * 100}")
    local filled=$((percent / 10))
    local bar=$(printf '▓%.0s' $(seq 1 $filled))$(printf '░%.0s' $(seq 1 $((10 - filled))))
    printf "💰 %.1f/%.0f %s %d%%" "$remaining" "$limit" "$bar" "$percent"
  else
    echo "💰 0/0"
  fi
}

# === 第二行：会话费用（可选）===
get_session() {
  local input="$1"
  [[ -z "$input" ]] && return 1

  local sid=$(echo "$input" | $JQ -r '.session_id // empty' 2>/dev/null || true)
  local tpath=$(echo "$input" | $JQ -r '.transcript_path // empty' 2>/dev/null || true)
  [[ -z "$sid" || -z "$tpath" ]] && return 1

  local sf="${TMPDIR:-/tmp}/claude-openrouter-cost-${sid}.json"
  local tcost=0 tcache=0 prov="" model=""
  local sids=""

  [[ -f "$sf" ]] && {
    tcost=$($JQ -r '.total_cost // 0' "$sf" 2>/dev/null || echo "0")
    tcache=$($JQ -r '.total_cache_discount // 0' "$sf" 2>/dev/null || echo "0")
    prov=$($JQ -r '.last_provider // ""' "$sf" 2>/dev/null || echo "")
    model=$($JQ -r '.last_model // ""' "$sf" 2>/dev/null || echo "")
    sids=$($JQ -r '.seen_ids[]' "$sf" 2>/dev/null || true)
  }

  # 提取新的 gen-id
  [[ -f "$tpath" ]] && {
    grep -o '"id":"gen-[^"]*"' "$tpath" 2>/dev/null | sed 's/"id":"//;s/"/' | sort -u | while read gid; do
      echo "$sids" | grep -qx "$gid" && continue

      local r=$(curl -sf --max-time 5 -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        "https://openrouter.ai/api/v1/generation?id=$gid" 2>/dev/null || echo "")
      [[ -z "$r" ]] && continue

      local gc=$($JQ -r '.data.total_cost // 0' <<<"$r" 2>/dev/null || echo "0")
      local gch=$($JQ -r '.data.cache_discount // 0' <<<"$r" 2>/dev/null || echo "0")
      local gp=$($JQ -r '.data.provider_name // ""' <<<"$r" 2>/dev/null || echo "")
      local gm=$($JQ -r '.data.model // ""' <<<"$r" 2>/dev/null || echo "")

      tcost=$(awk "BEGIN {printf \"%.6f\", $tcost + $gc}")
      tcache=$(awk "BEGIN {printf \"%.6f\", $tcache + $gch}")
      [[ -n "$gp" ]] && prov="$gp"
      [[ -n "$gm" ]] && model="$gm"

      sids="$sids"$'\n'"$gid"
    done
  }

  # 保存
  {
    local sjson="[]"
    [[ -n "$sids" ]] && sjson=$(echo "$sids" | grep -v '^$' | awk 'BEGIN{printf "["}{if(NR>1)printf ",";printf "\"%s\"",$0}END{printf "]"}')
    printf '{"seen_ids":%s,"total_cost":%s,"total_cache_discount":%s,"last_provider":"%s","last_model":"%s"}\n' \
      "$sjson" "$tcost" "$tcache" "$prov" "$model" > "$sf"
  } 2>/dev/null

  # 输出
  [[ -n "$prov" ]] && {
    local sm=$(echo "$model" | sed 's|^[^/]*/||;s/-[0-9]*$//')
    printf "%s: %s - \$%.4f - cache: \$%.2f" "$prov" "$sm" "$tcost" "$tcache"
  }
}

# === 主逻辑 ===
BALANCE=$(get_balance 2>/dev/null || echo "")
INPUT=$(cat 2>/dev/null || true)
SESSION=$(get_session "$INPUT" 2>/dev/null || echo "")

# 第一行：会话费用（如有）或余额
if [[ -n "$SESSION" ]]; then
  echo "$SESSION"
else
  echo "$BALANCE"
fi

# 第二行：余额（如果会话有内容）
if [[ -n "$SESSION" && -n "$BALANCE" ]]; then
  echo "$BALANCE"
fi

exit 0
