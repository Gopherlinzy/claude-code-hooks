#!/bin/bash

# 多数据源聚合 - claude-hud statusline 工具
# 并行调用多个 statusline 工具，将结果汇总到一行
#
# 使用：
#   1. 复制到 ~/.claude/scripts/claude-hooks/statusline/
#   2. chmod +x aggregate.sh
#   3. 先确保其他工具已安装（openrouter-status.sh 等）
#   4. 在 settings.json 中添加：--extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/aggregate.sh"

set -e

STATUSLINE_DIR="${HOME}/.claude/scripts/claude-hooks/statusline"
TIMEOUT=5  # 单个工具最多等待 5 秒

# 检查文件是否存在并可执行
check_tool() {
  local tool="$1"
  if [[ -f "$STATUSLINE_DIR/$tool" ]] && [[ -x "$STATUSLINE_DIR/$tool" ]]; then
    return 0
  fi
  return 1
}

# 安全地调用工具（带超时保护）
call_tool() {
  local tool="$1"
  local temp_file="/tmp/statusline_$$.tmp"

  if ! check_tool "$tool"; then
    return 1
  fi

  # 使用后台进程和超时保护
  (
    bash "$STATUSLINE_DIR/$tool" > "$temp_file" 2>/dev/null || echo '{"label":"Error"}'
  ) &

  local pid=$!
  sleep "$TIMEOUT" && kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true

  # 提取 label 字段
  if [[ -f "$temp_file" ]]; then
    cat "$temp_file" | grep -o '"label":"[^"]*' | cut -d'"' -f4
    rm -f "$temp_file"
  fi
}

main() {
  local parts=()

  # 优先级顺序：按重要性和性能排列
  # 1. OpenRouter 信用度（最常用）
  if [[ -n "$(call_tool "openrouter-status.sh")" ]]; then
    parts+=("$(call_tool "openrouter-status.sh")")
  fi

  # 2. GitHub 状态（如果配置了 GITHUB_TOKEN）
  if [[ -n "$GITHUB_TOKEN" ]] && check_tool "github-status.sh"; then
    if [[ -n "$(call_tool "github-status.sh")" ]]; then
      parts+=("$(call_tool "github-status.sh")")
    fi
  fi

  # 3. 系统资源（轻量级本地调用）
  if check_tool "system-status.sh"; then
    if [[ -n "$(call_tool "system-status.sh")" ]]; then
      parts+=("$(call_tool "system-status.sh")")
    fi
  fi

  # 4. 自定义工具（如果存在）
  # if [[ -n "$(call_tool "custom-status.sh")" ]]; then
  #   parts+=("$(call_tool "custom-status.sh")")
  # fi

  # 拼接结果
  local label
  if [[ ${#parts[@]} -gt 0 ]]; then
    label=$(IFS=" | "; echo "${parts[*]}")
  else
    label="Ready"
  fi

  # 清理临时文件
  rm -f /tmp/statusline_$$.tmp

  echo "{\"label\":\"$label\"}"
}

main
