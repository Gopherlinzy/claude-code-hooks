#!/bin/bash

# StatusLine 示例工具快速安装脚本
# 用法：bash setup-examples.sh [工具1] [工具2] ...
# 例如：bash setup-examples.sh github system git all

set -e

STATUSLINE_DIR="${HOME}/.claude/scripts/claude-hooks/statusline"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 创建 statusline 目录
mkdir -p "${STATUSLINE_DIR}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

print_header() {
  echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️ $1${NC}"
}

print_info() {
  echo -e "ℹ️ $1"
}

# 安装单个工具
install_tool() {
  local tool_name="$1"
  local tool_file="$2"
  local description="$3"

  if [[ ! -f "${SCRIPT_DIR}/examples/${tool_file}" ]]; then
    print_error "Tool not found: $tool_file"
    return 1
  fi

  cp "${SCRIPT_DIR}/examples/${tool_file}" "${STATUSLINE_DIR}/${tool_name}.sh"
  chmod +x "${STATUSLINE_DIR}/${tool_name}.sh"
  print_success "Installed: ${tool_name}.sh ($description)"
}

# 显示用法
show_usage() {
  cat <<EOF
${BLUE}🚀 StatusLine 示例工具安装脚本${NC}

${YELLOW}用法：${NC}
  bash setup-examples.sh [选项] [工具...]

${YELLOW}工具列表：${NC}
  github      - GitHub 用户信息和仓库数
  system      - CPU、内存、磁盘监控
  git         - Git 分支和改动状态
  weather     - 天气和温度显示
  aggregate   - 多工具聚合
  all         - 安装所有工具

${YELLOW}选项：${NC}
  --help      - 显示此帮助信息
  --list      - 仅列出可用工具
  --customize - 交互式选择工具

${YELLOW}示例：${NC}
  # 安装 GitHub 和系统监控
  bash setup-examples.sh github system

  # 安装所有工具
  bash setup-examples.sh all

  # 交互式选择
  bash setup-examples.sh --customize

EOF
}

# 列出所有工具
list_tools() {
  print_header "可用的 StatusLine 工具"
  echo ""
  echo "1. github    - GitHub 用户信息"
  echo "2. system    - 系统资源监控 (CPU/内存/磁盘)"
  echo "3. git       - Git 状态显示"
  echo "4. weather   - 天气显示"
  echo "5. aggregate - 多工具聚合"
  echo ""
}

# 交互式选择
interactive_select() {
  print_header "请选择要安装的工具"
  echo ""
  list_tools

  local selected_tools=()

  read -p "$(echo -e ${YELLOW})选择工具 (用空格分隔数字，如 "1 3 5")：$(echo -e ${NC}) " choice

  for num in $choice; do
    case $num in
      1) selected_tools+=("github") ;;
      2) selected_tools+=("system") ;;
      3) selected_tools+=("git") ;;
      4) selected_tools+=("weather") ;;
      5) selected_tools+=("aggregate") ;;
      *) print_warning "Unknown option: $num" ;;
    esac
  done

  echo "${selected_tools[@]}"
}

# 验证工具安装
verify_installation() {
  print_header "验证安装"

  for tool in $(ls "${STATUSLINE_DIR}"/*.sh 2>/dev/null | xargs -n1 basename); do
    if bash -n "${STATUSLINE_DIR}/${tool}" 2>/dev/null; then
      print_success "$tool (语法正确)"
    else
      print_error "$tool (语法错误)"
    fi
  done
}

# 显示 settings.json 配置模板
show_config_template() {
  print_header "settings.json 配置模板"

  echo ""
  echo "编辑 ~/.claude/settings.json，添加或修改 statusLine 配置："
  echo ""
  echo '# 单工具示例：'
  echo '{'
  echo '  "statusLine": {'
  echo '    "command": "bash -c '"'"'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh\"'"'"'",'
  echo '    "type": "command"'
  echo '  }'
  echo '}'
  echo ""
  echo "# 聚合工具示例（多个数据源）："
  echo '{'
  echo '  "statusLine": {'
  echo '    "command": "bash -c '"'"'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/aggregate.sh\"'"'"'",'
  echo '    "type": "command"'
  echo '  }'
  echo '}'
  echo ""
}

# 显示环境变量配置
show_env_setup() {
  print_header "环境变量配置"

  echo ""
  echo "某些工具需要环境变量。将以下行添加到 ~/.zshrc 或 ~/.bashrc："
  echo ""
  echo "# GitHub 工具"
  echo 'export GITHUB_TOKEN="ghp_your_token_here"'
  echo ""
  echo "# OpenRouter 工具"
  echo 'export OPENROUTER_API_KEY="sk-or-v1-..."'
  echo ""
  echo "# 天气工具"
  echo 'export WEATHER_CITY="Beijing"'
  echo "# 或使用经纬度："
  echo 'export WEATHER_LAT="39.9"'
  echo 'export WEATHER_LON="116.4"'
  echo ""
}

# 主函数
main() {
  local tools_to_install=()

  # 解析命令行参数
  if [[ $# -eq 0 ]]; then
    show_usage
    return 0
  fi

  case "$1" in
    --help)
      show_usage
      return 0
      ;;
    --list)
      list_tools
      return 0
      ;;
    --customize)
      tools_to_install=($(interactive_select))
      ;;
    *)
      # 直接指定工具
      for arg in "$@"; do
        case "$arg" in
          all)
            tools_to_install=("github" "system" "git" "weather" "aggregate")
            ;;
          github|system|git|weather|aggregate)
            tools_to_install+=("$arg")
            ;;
          --verify)
            # 验证安装后再处理
            ;;
          *)
            print_error "Unknown tool: $arg"
            ;;
        esac
      done
      ;;
  esac

  # 检查是否有要安装的工具
  if [[ ${#tools_to_install[@]} -eq 0 ]]; then
    print_warning "No tools specified"
    return 1
  fi

  # 安装工具
  print_header "开始安装"
  echo ""

  local installed_count=0
  for tool in "${tools_to_install[@]}"; do
    case "$tool" in
      github)
        install_tool "github-status" "example-github-status.sh" "GitHub" && ((installed_count++))
        ;;
      system)
        install_tool "system-status" "example-system-status.sh" "System Resources" && ((installed_count++))
        ;;
      git)
        install_tool "git-status" "example-git-status.sh" "Git Status" && ((installed_count++))
        ;;
      weather)
        install_tool "weather-status" "example-weather.sh" "Weather" && ((installed_count++))
        ;;
      aggregate)
        install_tool "aggregate" "example-aggregate.sh" "Aggregate" && ((installed_count++))
        ;;
    esac
  done

  echo ""
  print_header "安装完成"
  print_info "已安装 $installed_count 个工具到 ${STATUSLINE_DIR}"
  echo ""

  # 显示配置步骤
  show_config_template
  echo ""
  show_env_setup

  # 验证安装
  echo ""
  verify_installation

  # 测试工具
  print_header "测试工具"
  echo ""
  print_info "运行以下命令测试工具："
  echo ""
  for tool in "${tools_to_install[@]}"; do
    case "$tool" in
      github)
        echo "  bash ${STATUSLINE_DIR}/github-status.sh | jq ."
        ;;
      system)
        echo "  bash ${STATUSLINE_DIR}/system-status.sh | jq ."
        ;;
      git)
        echo "  bash ${STATUSLINE_DIR}/git-status.sh | jq ."
        ;;
      weather)
        echo "  bash ${STATUSLINE_DIR}/weather-status.sh | jq ."
        ;;
      aggregate)
        echo "  bash ${STATUSLINE_DIR}/aggregate.sh | jq ."
        ;;
    esac
  done

  echo ""
  print_success "Setup complete!"
  print_info "Next: 1) 设置环境变量  2) 编辑 settings.json  3) 重启 Claude Code"
}

# 运行
main "$@"
