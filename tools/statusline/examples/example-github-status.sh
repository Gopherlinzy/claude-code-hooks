#!/bin/bash

# GitHub 用户状态监控 - claude-hud statusline 工具
# 显示：GitHub 用户名、公开仓库数、未读通知数
#
# 使用：
#   1. 复制到 ~/.claude/scripts/claude-hooks/statusline/
#   2. chmod +x github-status.sh
#   3. 设置 export GITHUB_TOKEN="ghp_..."
#   4. 在 settings.json 中添加：--extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh"

set -e

CACHE_FILE="${HOME}/.claude/github-cache.json"
CACHE_TTL=300  # 5 分钟缓存

# GitHub Token（从环境读取，或从 ~/.cchooks/secrets.env）
if [[ -z "$GITHUB_TOKEN" ]]; then
    [[ -f "${HOME}/.cchooks/secrets.env" ]] && source "${HOME}/.cchooks/secrets.env"
fi

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
  if [[ -z "$GITHUB_TOKEN" ]]; then
    echo '{"label":"No GitHub Token"}'
    return
  fi

  local response
  response=$(curl -s --max-time 2 \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/user" 2>/dev/null || echo "")

  if [[ -z "$response" ]]; then
    echo '{"label":"GitHub Offline"}'
    return
  fi

  if echo "$response" | grep -q '"message"'; then
    local msg=$(echo "$response" | grep -o '"message":"[^"]*' | cut -d'"' -f4 | head -1)
    if [[ "$msg" == *"401"* ]] || [[ "$msg" == *"Unauthorized"* ]]; then
      echo '{"label":"GitHub Auth Failed"}'
    else
      echo '{"label":"GitHub Error: '"$msg"'"}'
    fi
    return
  fi

  # 提取用户名和仓库数量
  local login=$(echo "$response" | grep -o '"login":"[^"]*' | cut -d'"' -f4)
  local repos=$(echo "$response" | grep -o '"public_repos":[0-9]*' | cut -d':' -f2)

  if [[ -z "$login" ]] || [[ -z "$repos" ]]; then
    echo '{"label":"GitHub Parse Error"}'
    return
  fi

  # 获取未读通知数（可选，可能影响性能）
  local notifications=""
  # 注释掉以加快响应：
  # local notif=$(curl -s --max-time 1 \
  #   -H "Authorization: token $GITHUB_TOKEN" \
  #   "https://api.github.com/notifications?all=false" 2>/dev/null | grep -c '"unread":true' || echo 0)
  # [[ $notif -gt 0 ]] && notifications=" · 📬 $notif"

  local label="👨‍💻 $login ($repos repos)${notifications}"
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
