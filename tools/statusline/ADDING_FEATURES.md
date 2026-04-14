# 🚀 为 claude-hud 增加 StatusLine 新功能

这份指南展示如何为 claude-hud statusline 开发和集成新的实时监控工具。

## 核心原理

### claude-hud 的 StatusLine 机制

```bash
node ~/.claude/plugins/cache/claude-hud/claude-hud/*/dist/index.js \
  --extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh"
```

**工作流程：**

1. claude-hud 主程序启动，显示基础信息（Model、Provider）
2. 通过 `--extra-cmd` 参数调用外部脚本
3. 脚本输出 JSON 格式：`{ "label": "你的内容" }`
4. claude-hud 将结果拼接到状态栏末尾

**约束条件：**
- 输出必须是有效的 JSON（至少包含 `"label"` 字段）
- 脚本应快速响应（< 500ms 为佳，否则影响启动速度）
- 使用缓存减少 API 调用
- 优雅降级处理错误（网络离线、无认证等）

---

## 快速入门：创建新工具

### 范例 1：GitHub 状态监控（获取用户信息）

创建 `~/.claude/scripts/claude-hooks/statusline/github-status.sh`：

```bash
#!/bin/bash
# GitHub 用户信息状态栏工具

set -e

CACHE_FILE="${HOME}/.claude/github-cache.json"
CACHE_TTL=300  # 5 分钟缓存

# GitHub API Key（从环境或 .env 读取）
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo '{"label":"No GitHub Token"}'
    exit 0
fi

check_cache() {
  if [[ ! -f "$CACHE_FILE" ]]; then
    return 1
  fi
  
  local mtime=$(stat -c%Y "$CACHE_FILE" 2>/dev/null || stat -f%m "$CACHE_FILE" 2>/dev/null || echo 0)
  local now=$(date +%s)
  local age=$((now - mtime))
  
  [[ $age -lt $CACHE_TTL ]]
}

get_from_cache() {
  cat "$CACHE_FILE" 2>/dev/null || echo '{"label":"☐"}'
}

fetch_from_api() {
  local response
  response=$(curl -s --max-time 2 \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user" 2>/dev/null || echo "")
  
  if [[ -z "$response" ]]; then
    echo '{"label":"GitHub Offline"}'
    return
  fi
  
  if echo "$response" | grep -q '"message"'; then
    echo '{"label":"Auth Failed"}'
    return
  fi
  
  # 提取用户名和仓库数量
  local login=$(echo "$response" | grep -o '"login":"[^"]*' | cut -d'"' -f4)
  local repos=$(echo "$response" | grep -o '"public_repos":[0-9]*' | cut -d':' -f2)
  
  local label="👨‍💻 $login ($repos repos)"
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
```

**使用方法：**

```bash
# 1. 设置权限
chmod +x ~/.claude/scripts/claude-hooks/statusline/github-status.sh

# 2. 确保 GITHUB_TOKEN 在环境中
export GITHUB_TOKEN="ghp_xxxx..."

# 3. 测试输出
bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh
# 输出：{"label":"👨‍💻 username (42 repos)"}

# 4. 添加到 settings.json （见下文）
```

---

### 范例 2：系统资源监控（CPU/内存）

创建 `~/.claude/scripts/claude-hooks/statusline/system-status.sh`：

```bash
#!/bin/bash
# 系统资源监控

get_cpu_usage() {
  case "$(uname -s)" in
    Darwin)  # macOS
      ps aux | awk 'NR>1 {sum+=$3} END {printf "%.0f", sum}'
      ;;
    Linux)
      grep -oP '(?<=cpu  )\d+' /proc/stat | awk '{s+=$1} END {printf "%.0f", s/NR}'
      ;;
    *)
      echo "0"
      ;;
  esac
}

get_memory_usage() {
  case "$(uname -s)" in
    Darwin)
      vm_stat | grep "Pages active" | awk '{print $3}' | tr -d '.' | awk '{printf "%.0f", $1 * 4096 / 1024 / 1024}'
      ;;
    Linux)
      free -m | grep Mem | awk '{printf "%.0f", ($3/$2)*100}'
      ;;
    *)
      echo "0"
      ;;
  esac
}

main() {
  local cpu=$(get_cpu_usage)
  local mem=$(get_memory_usage)
  
  # 简单的视觉指示
  if (( $(echo "$cpu > 70" | bc -l 2>/dev/null) )); then
    cpu_indicator="🔴"
  elif (( $(echo "$cpu > 50" | bc -l 2>/dev/null) )); then
    cpu_indicator="🟡"
  else
    cpu_indicator="🟢"
  fi
  
  if (( $(echo "$mem > 70" | bc -l 2>/dev/null) )); then
    mem_indicator="🔴"
  elif (( $(echo "$mem > 50" | bc -l 2>/dev/null) )); then
    mem_indicator="🟡"
  else
    mem_indicator="🟢"
  fi
  
  local label="${cpu_indicator} CPU ${mem_indicator} MEM"
  echo "{\"label\":\"$label\"}"
}

main
```

---

### 范例 3：多个数据源聚合

创建 `~/.claude/scripts/claude-hooks/statusline/aggregate-status.sh`：

```bash
#!/bin/bash
# 聚合多个状态源

fetch_openrouter() {
  bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh 2>/dev/null | \
    grep -o '"label":"[^"]*' | cut -d'"' -f4
}

fetch_github() {
  local token="${GITHUB_TOKEN}"
  if [[ -z "$token" ]]; then
    echo ""
    return
  fi
  
  local response=$(curl -s --max-time 1 \
    -H "Authorization: token $token" \
    "https://api.github.com/user/notifications" 2>/dev/null || echo "")
  
  if [[ -z "$response" ]]; then
    echo ""
    return
  fi
  
  local count=$(echo "$response" | grep -o '"unread":true' | wc -l)
  if [[ $count -gt 0 ]]; then
    echo "📬 $count"
  fi
}

main() {
  local parts=()
  
  # 收集各个源
  local or=$(fetch_openrouter)
  [[ -n "$or" ]] && parts+=("$or")
  
  local gh=$(fetch_github)
  [[ -n "$gh" ]] && parts+=("$gh")
  
  # 用 " | " 分隔
  local label=$(IFS=" | "; echo "${parts[*]}")
  
  if [[ -z "$label" ]]; then
    label="No Data"
  fi
  
  echo "{\"label\":\"$label\"}"
}

main
```

---

## 集成到 settings.json

### 单个工具集成

编辑 `~/.claude/settings.json`，找到 `statusLine` 部分，添加 `--extra-cmd`：

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh\"'",
    "type": "command"
  }
}
```

### 多工具链式调用

如果想同时集成多个工具，创建聚合脚本 `~/.claude/scripts/claude-hooks/statusline/all-status.sh`：

```bash
#!/bin/bash
# 主聚合脚本

STATUSLINE_DIR="${HOME}/.claude/scripts/claude-hooks/statusline"

call_tool() {
  bash "$STATUSLINE_DIR/$1" 2>/dev/null | \
    grep -o '"label":"[^"]*' | cut -d'"' -f4
}

main() {
  local parts=()
  
  # 按优先级调用各工具
  local or=$(call_tool "openrouter-status.sh")
  [[ -n "$or" ]] && parts+=("$or")
  
  local gh=$(call_tool "github-status.sh")
  [[ -n "$gh" ]] && parts+=("$gh")
  
  local sys=$(call_tool "system-status.sh")
  [[ -n "$sys" ]] && parts+=("$sys")
  
  local label=$(IFS=" | "; echo "${parts[*]}")
  [[ -z "$label" ]] && label="Ready"
  
  echo "{\"label\":\"$label\"}"
}

main
```

然后在 `settings.json` 中引用：

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/all-status.sh\"'",
    "type": "command"
  }
}
```

---

## 最佳实践

### 1. 缓存策略

**为什么需要缓存？**
- claude-hud 每次启动都调用 statusline 命令
- API 通常有速率限制
- 频繁网络请求拖累启动速度

**缓存实现：**

```bash
CACHE_FILE="${HOME}/.cache/my-status.json"
CACHE_TTL=60  # 秒

check_cache() {
  [[ -f "$CACHE_FILE" ]] || return 1
  
  local age=$(( $(date +%s) - $(stat -c%Y "$CACHE_FILE" 2>/dev/null || stat -f%m "$CACHE_FILE" 2>/dev/null) ))
  [[ $age -lt $CACHE_TTL ]]
}

# 使用缓存降低 API 调用
if check_cache; then
  cat "$CACHE_FILE"
else
  fetch_and_cache
fi
```

### 2. 跨平台兼容性

bash 脚本需要在 macOS、Linux、Windows (Git Bash) 上都工作：

```bash
# ✅ 使用 grep 而不是依赖特定的工具
command -v jq >/dev/null || JQ="gojq"

# ✅ 处理不同的 stat 命令
mtime=$(stat -c%Y file 2>/dev/null || stat -f%m file)

# ✅ 避免 macOS 特有的函数
# ❌ printf "%(%s)T" -1  # 仅 bash 4+
# ✅ date +%s  # 兼容所有平台

# ✅ 使用绝对路径
JQ="${HOME}/.claude/scripts/jq"

# ✅ 处理 Windows 路径
CACHE_FILE="${HOME}/.claude/cache.json"  # 兼容所有平台
```

### 3. 错误处理

**优雅降级的 JSON 响应：**

| 场景 | 输出 |
|------|------|
| 网络离线 | `{"label":"Offline"}` |
| 无认证密钥 | `{"label":"No Auth"}` |
| API 限流 | `{"label":"Rate Limited"}` |
| 缓存损坏 | `{"label":"Cache Error"}` |
| 正常工作 | `{"label":"✅ Data"}` |

```bash
fetch_data() {
  local response=$(curl -s --max-time 2 "$API" 2>/dev/null || echo "")
  
  if [[ -z "$response" ]]; then
    echo '{"label":"Offline"}'
    return 1
  fi
  
  if echo "$response" | grep -q '"error"'; then
    echo '{"label":"API Error"}'
    return 1
  fi
  
  # 处理成功响应
  local data=$(echo "$response" | jq -r '.data')
  echo "{\"label\":\"✅ $data\"}"
}
```

### 4. 性能优化

**响应时间目标：**
- 缓存命中：< 10ms
- 缓存未命中：< 500ms

**优化技巧：**

```bash
# ❌ 串行调用多个 API（太慢）
api1=$(curl "$URL1" -s)
api2=$(curl "$URL2" -s)
api3=$(curl "$URL3" -s)

# ✅ 并行调用
(curl "$URL1" -s > /tmp/api1 &)
(curl "$URL2" -s > /tmp/api2 &)
(curl "$URL3" -s > /tmp/api3 &)
wait
api1=$(cat /tmp/api1)
api2=$(cat /tmp/api2)
api3=$(cat /tmp/api3)

# ✅ 使用 curl 超时避免挂死
curl -s --max-time 2 "$URL"  # 2 秒超时

# ✅ 本地计算而不是网络调用
local cpu_percent=$((cpu_used * 100 / cpu_total))  # 快速
# vs
# curl "$MONITORING_API/cpu"  # 慢
```

### 5. 调试技巧

```bash
# 直接测试输出
bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh

# 验证 JSON 格式
bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh | jq .

# 查看响应时间
time bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh

# 监控缓存
watch -n 1 'cat ~/.claude/my-cache.json | jq .'

# 查看 claude-hud 日志
tail -f ~/.claude/logs/  # 如果存在

# 测试完整 statusline 命令
bash -c 'plugin_dir=$(ls -d "${HOME}/.claude"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node "${plugin_dir}dist/index.js" --extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh"'
```

---

## 常见需求示例

### 监控 AWS 账户信息

```bash
#!/bin/bash
CACHE_FILE="${HOME}/.claude/aws-cache.json"
CACHE_TTL=600

fetch_aws() {
  # 需要 AWS CLI 和正确的 ~/.aws/credentials
  local account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
  local user=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2 2>/dev/null)
  
  if [[ -z "$account" ]]; then
    echo '{"label":"AWS Unavailable"}'
    return
  fi
  
  local label="☁️ $user@$account"
  echo "{\"label\":\"$label\"}" | tee "$CACHE_FILE"
}

check_cache() {
  [[ -f "$CACHE_FILE" ]] && [[ $(( $(date +%s) - $(stat -c%Y "$CACHE_FILE" 2>/dev/null || stat -f%m "$CACHE_FILE") )) -lt $CACHE_TTL ]]
}

if check_cache; then
  cat "$CACHE_FILE"
else
  fetch_aws
fi
```

### 监控 Docker 容器

```bash
#!/bin/bash
# 显示运行中的容器数

running=$(docker ps --format "table {{.Names}}" 2>/dev/null | tail -n +2 | wc -l)
total=$(docker ps -a --format "table {{.Names}}" 2>/dev/null | tail -n +2 | wc -l)

if [[ $running -eq 0 ]]; then
  label="🐳 ${total} images"
else
  label="🐳 ${running}/${total} running"
fi

echo "{\"label\":\"$label\"}"
```

### 监控 Git 状态

```bash
#!/bin/bash
# 当前项目的 Git 状态

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo '{"label":"No Git"}'
  exit 0
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
status=$(git status --porcelain 2>/dev/null | wc -l)

if [[ $status -eq 0 ]]; then
  icon="✅"
else
  icon="⚠️"
fi

label="$icon $branch (+$status)"
echo "{\"label\":\"$label\"}"
```

---

## 测试清单

在发布新工具前检查：

- [ ] JSON 格式有效（`jq .` 无错误）
- [ ] 响应时间 < 500ms
- [ ] 缓存策略已实现
- [ ] 错误处理完善（无密钥、网络离线等）
- [ ] 在 macOS、Linux、Windows 上测试过
- [ ] 避免依赖不常见的外部工具
- [ ] 包含使用文档和配置示例
- [ ] 敏感信息（API 密钥）处理安全

---

## 提交新工具

如果你创建了一个有用的工具，考虑提交到 claude-code-hooks 项目：

1. Fork https://github.com/Gopherlinzy/claude-code-hooks
2. 在 `tools/statusline/` 目录下创建 `my-tool-status.sh`
3. 添加 README 说明
4. 确保所有平台兼容
5. 提交 Pull Request

---

## 故障排除

| 问题 | 原因 | 解决方案 |
|------|------|--------|
| 状态栏不显示自定义内容 | `--extra-cmd` 未正确配置 | 检查 `settings.json` 中的完整命令 |
| 输出为空 | 脚本没有返回有效 JSON | 手动运行脚本，检查输出 |
| Claude Code 启动变慢 | 脚本响应超时 | 增加缓存 TTL，减少 API 调用 |
| 系统崩溃 | 脚本占用大量资源 | 使用 `--max-time`、避免死循环 |
| 跨平台不兼容 | 使用了平台特定的命令 | 使用 `$(uname -s)` 检测平台 |

---

## 下一步

- 创建你的第一个 statusline 工具
- 分享到 GitHub Discussions
- 贡献到 claude-code-hooks 项目
- 集成更多实时数据源
