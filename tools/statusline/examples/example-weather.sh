#!/bin/bash

# 天气显示 - claude-hud statusline 工具
# 显示：当前城市的天气和温度
#
# 使用：
#   1. 复制到 ~/.claude/scripts/claude-hooks/statusline/
#   2. chmod +x weather.sh
#   3. 设置 export WEATHER_CITY="Beijing" 或 export WEATHER_LAT="39.9" WEATHER_LON="116.4"
#   4. 在 settings.json 中添加：--extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/weather.sh"
#
# 注意：使用免费的 wttr.in API，无需认证，但有速率限制
#      建议将 CACHE_TTL 设置为 1800（30 分钟）以减少 API 调用

set -e

CACHE_FILE="${HOME}/.claude/weather-cache.json"
CACHE_TTL=1800  # 30 分钟缓存

# 配置选项
WEATHER_CITY="${WEATHER_CITY:-Beijing}"  # 城市名称或拼音
WEATHER_LAT="${WEATHER_LAT:-}"           # 纬度（可选）
WEATHER_LON="${WEATHER_LON:-}"           # 经度（可选）
WEATHER_FORMAT="${WEATHER_FORMAT:-%-+}"  # wttr.in 格式代码

check_cache() {
  if [[ ! -f "$CACHE_FILE" ]]; then
    return 1
  fi

  local mtime=$(stat -c%Y "$CACHE_FILE" 2>/dev/null || stat -f%m "$CACHE_FILE" 2>/dev/null || echo 0)
  local now=$(date +%s)
  local age=$((now - mtime))

  if [[ $age -lt $CACHE_TTL ]]; then
    return 0
  fi
  return 1
}

get_from_cache() {
  cat "$CACHE_FILE" 2>/dev/null || echo '{"label":"☐"}'
}

fetch_from_api() {
  local location="$WEATHER_CITY"

  # 如果提供了经纬度，使用经纬度查询（更小的响应体）
  if [[ -n "$WEATHER_LAT" ]] && [[ -n "$WEATHER_LON" ]]; then
    location="$WEATHER_LAT,$WEATHER_LON"
  fi

  # 调用 wttr.in API
  # 格式参数说明：
  # % - 温度（°C）
  # c - 天气描述
  # W - 风速
  # p - 降水概率
  local response
  response=$(curl -s --max-time 3 \
    "https://wttr.in/${location}?format=%c+%t" 2>/dev/null || echo "")

  if [[ -z "$response" ]]; then
    echo '{"label":"Weather Offline"}'
    return
  fi

  # 处理可能的错误响应
  if echo "$response" | grep -qi "unknown location"; then
    echo '{"label":"Unknown Location"}'
    return
  fi

  # 解析温度和条件
  local condition=$(echo "$response" | awk '{print $1}')
  local temp=$(echo "$response" | awk '{print $2}' | grep -o "[0-9-]*")

  if [[ -z "$condition" ]] || [[ -z "$temp" ]]; then
    echo '{"label":"Weather Error"}'
    return
  fi

  # 转换天气条件为 emoji
  local emoji="🍃"
  case "$condition" in
    "Sunny"|"☀️"|"Clear")
      emoji="☀️"
      ;;
    "PartlyCloudy"|"⛅"|"Partly")
      emoji="⛅"
      ;;
    "Cloudy"|"☁️"|"Overcast")
      emoji="☁️"
      ;;
    "Rainy"|"🌧️"|"Rain")
      emoji="🌧️"
      ;;
    "Snowy"|"❄️"|"Snow")
      emoji="❄️"
      ;;
    "Stormy"|"⛈️"|"Thunder")
      emoji="⛈️"
      ;;
    "Fog"|"🌫️")
      emoji="🌫️"
      ;;
    "Wind"|"💨")
      emoji="💨"
      ;;
  esac

  # 基于温度调整 emoji
  if [[ $temp -lt 0 ]]; then
    emoji="❄️"
  elif [[ $temp -gt 30 ]]; then
    emoji="🔥"
  fi

  local label="$emoji ${temp}°C"
  echo "{\"label\":\"$label\"}" > "$CACHE_FILE" 2>/dev/null || true
  echo "{\"label\":\"$label\"}"
}

main() {
  if check_cache; then
    get_from_cache
  else
    fetch_from_api
  fi
}

main
