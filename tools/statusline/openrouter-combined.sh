#!/bin/bash

# OpenRouter StatusLine - 三合一：余额 + 模型 + 成本
# 直接作为 statusLine 命令，接收 stdin，输出 JSON
# 配置：~/.claude/settings.json 的 statusLine.command 指向此脚本

set +e

OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$ANTHROPIC_AUTH_TOKEN}"
[[ -z "$OPENROUTER_API_KEY" ]] && echo '{"label":"⚙️ No API Key"}' && exit 0

# ===== 1. 获取余额（通过 /api/v1/key）=====
get_balance() {
  local resp=$(curl -s --max-time 2 \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    "https://openrouter.ai/api/v1/key" 2>/dev/null || echo "")

  [[ -z "$resp" ]] && return 1

  # 检查错误
  if echo "$resp" | grep -q '"error"'; then
    return 1
  fi

  # 用 python3 解析 JSON
  local remaining limit
  remaining=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('limit_remaining',0))" <<<"$resp" 2>/dev/null || echo "0")
  limit=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('limit',0))" <<<"$resp" 2>/dev/null || echo "0")

  [[ "$remaining" =~ ^[0-9.]+$ ]] || remaining="0"
  [[ "$limit" =~ ^[0-9.]+$ ]] || limit="0"

  if awk "BEGIN { exit ($limit > 0) ? 0 : 1 }"; then
    local percent=$(awk "BEGIN {printf \"%.0f\", $remaining / $limit * 100}")
    printf "%.2f/%.0f" "$remaining" "$limit"
  else
    printf "0/0"
  fi
}

# ===== 2. 获取会话成本和模型信息（通过 stdin + generation API）=====
get_session_cost() {
  local input="$1"
  [[ -z "$input" ]] && return 1

  # 从 stdin JSON 提取 session_id 和 transcript_path
  local sid=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" <<<"$input" 2>/dev/null || echo "")
  local tpath=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('transcript_path',''))" <<<"$input" 2>/dev/null || echo "")

  [[ -z "$sid" || -z "$tpath" ]] && return 1

  local sf="${TMPDIR:-/tmp}/claude-openrouter-cost-${sid}.json"
  local tcost="0"
  local tcache="0"
  local prov=""
  local model=""
  local sids=""

  # 加载已保存的状态
  if [[ -f "$sf" ]]; then
    tcost=$(python3 -c "import json; d=json.load(open('$sf')); print(d.get('total_cost','0'))" 2>/dev/null || echo "0")
    tcache=$(python3 -c "import json; d=json.load(open('$sf')); print(d.get('total_cache_discount','0'))" 2>/dev/null || echo "0")
    prov=$(python3 -c "import json; d=json.load(open('$sf')); print(d.get('last_provider',''))" 2>/dev/null || echo "")
    model=$(python3 -c "import json; d=json.load(open('$sf')); print(d.get('last_model',''))" 2>/dev/null || echo "")
    sids=$(python3 -c "import json; d=json.load(open('$sf')); print('\\n'.join(d.get('seen_ids',[])))" 2>/dev/null || echo "")
  fi

  # 从 transcript 提取新的 gen-id
  if [[ -f "$tpath" ]]; then
    local new_ids=$(grep -o '"id":"gen-[^"]*"' "$tpath" 2>/dev/null | sed 's/"id":"//;s/"/' | sort -u)

    while IFS= read -r gid; do
      [[ -z "$gid" ]] && continue
      # 检查是否已见过
      echo "$sids" | grep -qx "$gid" && continue

      # 调用 generation API
      local r=$(curl -s --max-time 3 \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        "https://openrouter.ai/api/v1/generation?id=$gid" 2>/dev/null || echo "")

      [[ -z "$r" ]] && continue

      # 解析成本和信息
      local gc=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('total_cost',0))" <<<"$r" 2>/dev/null || echo "0")
      local gch=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('cache_discount',0))" <<<"$r" 2>/dev/null || echo "0")
      local gp=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('provider_name',''))" <<<"$r" 2>/dev/null || echo "")
      local gm=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('model',''))" <<<"$r" 2>/dev/null || echo "")

      # 累计成本
      tcost=$(python3 -c "print(float('$tcost') + float('$gc'))")
      tcache=$(python3 -c "print(float('$tcache') + float('$gch'))")
      [[ -n "$gp" ]] && prov="$gp"
      [[ -n "$gm" ]] && model="$gm"

      sids="${sids:+$sids}${sids:+$'\n'}$gid"
    done <<<"$new_ids"
  fi

  # 保存状态到文件
  {
    python3 -c "
import json
seen_ids = [s.strip() for s in '$sids'.split('\\n') if s.strip()]
data = {
  'seen_ids': seen_ids,
  'total_cost': float('$tcost'),
  'total_cache_discount': float('$tcache'),
  'last_provider': '$prov',
  'last_model': '$model'
}
print(json.dumps(data))
" > "$sf"
  } 2>/dev/null

  # 输出：只有有有效 provider 和 model 时才输出
  if [[ -n "$prov" && -n "$model" ]]; then
    # 简化模型名（去掉前缀和版本号）
    local sm=$(echo "$model" | sed 's|^[^/]*/||;s/-[0-9]*$//')
    printf "%s: %s - \$%.4f - cache: \$%.2f" "$prov" "$sm" "$tcost" "$tcache"
  fi
}

# ===== 主逻辑 =====
INPUT=$(cat 2>/dev/null || true)
BALANCE=$(get_balance)
SESSION=$(get_session_cost "$INPUT" 2>/dev/null || echo "")

# 组建输出
OUTPUT=""
if [[ -n "$SESSION" ]]; then
  # 有会话成本信息：显示 [Provider: Model - Cost] | 余额
  OUTPUT="$SESSION | 💰 $BALANCE"
elif [[ -n "$BALANCE" ]]; then
  # 只有余额：显示 余额
  OUTPUT="💰 $BALANCE"
fi

# 输出为 JSON（claude-hud 格式）
if [[ -n "$OUTPUT" ]]; then
  printf '{"label":"%s"}' "$OUTPUT"
else
  printf '{"label":"⚙️ Loading..."}'
fi

exit 0
