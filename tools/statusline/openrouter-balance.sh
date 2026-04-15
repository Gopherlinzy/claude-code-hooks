#!/bin/bash

# OpenRouter 余额查询脚本 - 为 claude-hud statusline 提供实时余额信息
# 调用 /api/v1/key 获取信用额度，显示进度条
#
# 配置示例：在 ~/.claude/settings.json 的 statusLine 中添加：
#   --extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/openrouter-balance.sh"

set -e

CACHE_FILE="${HOME}/.claude/openrouter-balance-cache.json"
CACHE_TTL=60  # 秒

# Windows/macOS/Linux 兼容性：jq 路径兜底
JQ=$(command -v jq 2>/dev/null || echo "${HOME}/.claude/scripts/jq.exe")

# OpenRouter API Key 兼容性：支持 ANTHROPIC_AUTH_TOKEN fallback
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$ANTHROPIC_AUTH_TOKEN}"

# 检查缓存是否仍然有效
check_cache() {
  if [[ ! -f "$CACHE_FILE" ]]; then
    return 1
  fi

  # stat 语法兼容性：GNU stat (-c%Y) vs BSD stat (-f%m)
  local mtime=$(stat -c%Y "$CACHE_FILE" 2>/dev/null || stat -f%m "$CACHE_FILE" 2>/dev/null || echo 0)
  local now=$(date +%s)
  local age=$((now - mtime))

  if [[ $age -lt $CACHE_TTL ]]; then
    return 0
  fi
  return 1
}

# 从缓存读取
get_from_cache() {
  cat "$CACHE_FILE" 2>/dev/null || echo '{"label":"☐"}'
}

# 从 OpenRouter API 获取数据
fetch_from_api() {
  if [[ -z "$OPENROUTER_API_KEY" ]]; then
    echo '{"label":"No Key"}'
    return
  fi

  local response
  response=$(curl -s --max-time 2 \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    "https://openrouter.ai/api/v1/key" 2>/dev/null || echo "")

  if [[ -z "$response" ]]; then
    echo '{"label":"Offline"}'
    return
  fi

  # 检查是否是错误响应
  if echo "$response" | grep -q '"error"'; then
    echo '{"label":"Auth Failed"}'
    return
  fi

  # 从响应中提取 limit_remaining 和 limit（字段在 .data 下）
  local remaining limit percent label
  remaining=$(echo "$response" | "$JQ" -r '.data.limit_remaining // 0' 2>/dev/null || echo "0")
  limit=$(echo "$response" | "$JQ" -r '.data.limit // 0' 2>/dev/null || echo "0")

  # 计算百分比和进度条（使用 awk，兼容 macOS/Linux/Windows，避免 bc 依赖）
  if awk "BEGIN { exit ($limit > 0) ? 0 : 1 }"; then
    percent=$(awk "BEGIN {printf \"%.0f\", $remaining / $limit * 100}" 2>/dev/null || echo "0")
    # 进度条：10 个字符，每个字符代表 10%
    local filled=$((percent / 10))
    local empty=$((10 - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar="${bar}▓"; done
    for ((i = 0; i < empty; i++)); do bar="${bar}░"; done

    # 格式化输出：💰 1999/2000 ▓▓░░░░░░░░ 99%
    label=$(printf "💰 %.2f/%.0f %s %d%%\n" "$remaining" "$limit" "$bar" "$percent")
  else
    label="💰 0/0"
  fi

  # 缓存结果
  echo "{\"label\":\"$label\"}" > "$CACHE_FILE" 2>/dev/null || true

  echo "{\"label\":\"$label\"}"
}

# 主逻辑
main() {
  if check_cache; then
    get_from_cache
  else
    fetch_from_api
  fi
}

main
