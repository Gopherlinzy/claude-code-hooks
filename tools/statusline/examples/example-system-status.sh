#!/bin/bash

# 系统资源监控 - claude-hud statusline 工具
# 显示：CPU 使用率、内存使用率、磁盘使用率
#
# 使用：
#   1. 复制到 ~/.claude/scripts/claude-hooks/statusline/
#   2. chmod +x system-status.sh
#   3. 在 settings.json 中添加：--extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/system-status.sh"

get_cpu_usage() {
  case "$(uname -s)" in
    Darwin)  # macOS
      # 使用 top -l 1 获取平均 CPU 使用率
      top -l 1 | grep "CPU usage:" | awk '{print $3}' | sed 's/%//' | awk -F. '{print $1}'
      ;;
    Linux)
      # 读取 /proc/stat 来计算 CPU 使用率
      local idle1 idle2 total1 total2
      all1=$(cat /proc/stat | head -n1 | awk '{print $2+$3+$4+$5+$6+$7+$8}')
      idle1=$(cat /proc/stat | head -n1 | awk '{print $5}')
      sleep 0.1
      all2=$(cat /proc/stat | head -n1 | awk '{print $2+$3+$4+$5+$6+$7+$8}')
      idle2=$(cat /proc/stat | head -n1 | awk '{print $5}')
      echo "scale=0; (100 * (($all2-$all1) - ($idle2-$idle1)) / ($all2-$all1))" | bc 2>/dev/null || echo "0"
      ;;
    *)
      echo "0"
      ;;
  esac
}

get_memory_usage() {
  case "$(uname -s)" in
    Darwin)
      # macOS 内存使用率
      vm_stat | awk '/Pages active:/ {active=$3} /Pages inactive:/ {inactive=$3} /Pages wired down:/ {wired=$3} END {total=(active+inactive+wired)*4096; printf "%.0f", total/1024/1024/1024}'
      ;;
    Linux)
      # Linux 内存使用率
      free -b | awk 'NR==2 {printf "%.0f", $3/1024/1024/1024}'
      ;;
    *)
      echo "0"
      ;;
  esac
}

get_disk_usage() {
  # 获取根目录磁盘使用率
  df / | awk 'NR==2 {print $5}' | sed 's/%//'
}

get_indicator() {
  local value=$1
  local emoji="🟢"

  if (( $(echo "$value > 80 " | bc -l 2>/dev/null) )); then
    emoji="🔴"  # 红色 - 严重
  elif (( $(echo "$value > 60" | bc -l 2>/dev/null) )); then
    emoji="🟡"  # 黄色 - 警告
  elif (( $(echo "$value > 40" | bc -l 2>/dev/null) )); then
    emoji="🟠"  # 橙色 - 中等
  fi

  echo "$emoji"
}

main() {
  # 获取各项数据
  local cpu=$(get_cpu_usage)
  local mem=$(get_memory_usage)
  local disk=$(get_disk_usage)

  # 处理空值
  cpu=${cpu:-0}
  mem=${mem:-0}
  disk=${disk:-0}

  # 获取对应的表情符号
  local cpu_indicator=$(get_indicator "$cpu")
  local mem_indicator=$(get_indicator "$mem")
  local disk_indicator=$(get_indicator "$disk")

  # 构建标签
  local label="${cpu_indicator} CPU${cpu}% ${mem_indicator} MEM${mem}GB ${disk_indicator} DSK${disk}%"

  echo "{\"label\":\"$label\"}"
}

main
