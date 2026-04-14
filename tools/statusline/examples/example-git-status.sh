#!/bin/bash

# Git 仓库状态监控 - claude-hud statusline 工具
# 显示：当前分支、未提交的改动数、待推送的提交数
#
# 使用：
#   1. 复制到 ~/.claude/scripts/claude-hooks/statusline/
#   2. chmod +x git-status.sh
#   3. 在 settings.json 中添加：--extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/git-status.sh"
#   4. 在项目目录启动 Claude Code，会显示当前项目的 Git 状态

CACHE_FILE="${HOME}/.claude/git-status-cache.json"
CACHE_TTL=10  # 10 秒缓存（Git 操作很快）

# 获取当前 Git 仓库的状态
get_git_info() {
  # 检查是否在 Git 仓库中
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    return 1
  fi

  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  local status_output=$(git status --porcelain 2>/dev/null)
  local modified=$(echo "$status_output" | grep -c "^.M" || echo 0)
  local added=$(echo "$status_output" | grep -c "^A" || echo 0)
  local deleted=$(echo "$status_output" | grep -c "^.D" || echo 0)
  local untracked=$(echo "$status_output" | grep -c "^??" || echo 0)

  local total_changes=$((modified + added + deleted + untracked))

  # 获取待推送的提交数
  local ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  local behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)

  echo "branch:$branch|changes:$total_changes|ahead:$ahead|behind:$behind|modified:$modified|added:$added|deleted:$deleted|untracked:$untracked"
}

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

format_output() {
  local git_info="$1"

  # 解析信息
  local branch=$(echo "$git_info" | grep -o "branch:[^|]*" | cut -d':' -f2)
  local changes=$(echo "$git_info" | grep -o "changes:[^|]*" | cut -d':' -f2)
  local ahead=$(echo "$git_info" | grep -o "ahead:[^|]*" | cut -d':' -f2)
  local behind=$(echo "$git_info" | grep -o "behind:[^|]*" | cut -d':' -f2)
  local modified=$(echo "$git_info" | grep -o "modified:[^|]*" | cut -d':' -f2)
  local added=$(echo "$git_info" | grep -o "added:[^|]*" | cut -d':' -f2)
  local deleted=$(echo "$git_info" | grep -o "deleted:[^|]*" | cut -d':' -f2)
  local untracked=$(echo "$git_info" | grep -o "untracked:[^|]*" | cut -d':' -f2)

  local label=""

  # 分支信息
  if [[ "$branch" == "HEAD" ]]; then
    # 分离的 HEAD 状态
    label="🗂️ (detached)"
  else
    label="🗂️ $branch"
  fi

  # 改动信息
  if [[ $changes -gt 0 ]]; then
    local details=""
    [[ $added -gt 0 ]] && details="${details}+$added"
    [[ $modified -gt 0 ]] && details="${details}~$modified"
    [[ $deleted -gt 0 ]] && details="${details}-$deleted"
    [[ $untracked -gt 0 ]] && details="${details}?$untracked"

    label="$label ⚠️ $changes changes($details)"
  else
    label="$label ✅"
  fi

  # 推送/拉取状态
  if [[ $ahead -gt 0 ]] || [[ $behind -gt 0 ]]; then
    local sync=""
    [[ $ahead -gt 0 ]] && sync="${sync}↑$ahead"
    [[ $behind -gt 0 ]] && sync="${sync}↓$behind"
    label="$label 🔄 $sync"
  fi

  echo "{\"label\":\"$label\"}"
}

main() {
  # 尝试从缓存读取
  if check_cache; then
    get_from_cache
    return 0
  fi

  # 获取 Git 信息
  local git_info=$(get_git_info)

  if [[ -z "$git_info" ]]; then
    # 不在 Git 仓库中，返回空标签
    echo '{"label":""}'
    return 0
  fi

  # 格式化并缓存
  local output=$(format_output "$git_info")
  echo "$output" > "$CACHE_FILE" 2>/dev/null || true
  echo "$output"
}

main
