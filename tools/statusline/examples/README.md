# 📊 StatusLine 工具示例库

本目录包含为 claude-hud statusline 准备的各种实用工具示例。

## 快速开始

### 1. 选择你需要的工具

根据你的需求从下表选择：

| 工具 | 功能 | 依赖 | 缓存 |
|------|------|------|------|
| `example-github-status.sh` | GitHub 用户/仓库信息 | GITHUB_TOKEN | 5 分钟 |
| `example-system-status.sh` | CPU/内存/磁盘监控 | 无 | 实时 |
| `example-git-status.sh` | Git 分支/改动状态 | 无 | 10 秒 |
| `example-weather.sh` | 天气和温度（wttr.in） | 无 | 30 分钟 |
| `example-aggregate.sh` | 聚合多个工具 | 其他工具 | 可配置 |

### 2. 安装工具

```bash
# 复制工具到 statusline 目录
cp example-github-status.sh ~/.claude/scripts/claude-hooks/statusline/github-status.sh
chmod +x ~/.claude/scripts/claude-hooks/statusline/github-status.sh
```

### 3. 配置 settings.json

编辑 `~/.claude/settings.json`，找到 `statusLine` 块，添加 `--extra-cmd` 参数：

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh\"'",
    "type": "command"
  }
}
```

### 4. 测试工具

```bash
# 直接运行脚本，检查 JSON 输出
bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh

# 验证 JSON 格式
bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh | jq .

# 检查响应时间
time bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh
```

---

## 工具详细说明

### 🔐 GitHub 状态 (`example-github-status.sh`)

显示 GitHub 用户信息和公开仓库数量。

**功能：**
- 用户名显示
- 公开仓库数
- 未读通知数（可选）
- 错误处理（无密钥、离线、认证失败）

**配置：**

```bash
# 1. 设置 Token
export GITHUB_TOKEN="ghp_your_token_here"

# 或在 ~/.cchooks/secrets.env 中设置
echo "GITHUB_TOKEN=ghp_..." >> ~/.cchooks/secrets.env
chmod 600 ~/.cchooks/secrets.env

# 2. 测试
bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh
# 输出：{"label":"👨‍💻 username (42 repos)"}
```

**自定义：**

```bash
# 修改缓存时间（秒）
CACHE_TTL=600  # 改为 10 分钟

# 添加未读通知数
# 在脚本中取消注释 "获取未读通知数" 部分
```

**故障排除：**

| 输出 | 原因 | 解决方案 |
|------|------|--------|
| `No GitHub Token` | GITHUB_TOKEN 未设置 | 设置 `export GITHUB_TOKEN=...` |
| `GitHub Auth Failed` | Token 无效或已过期 | 检查 Token 权限和有效期 |
| `GitHub Offline` | 网络不可达 | 检查网络连接，curl 是否正常 |

---

### 🖥️ 系统状态 (`example-system-status.sh`)

实时监控 CPU、内存、磁盘使用率。

**功能：**
- CPU 使用率（%）
- 内存使用率（GB）
- 磁盘使用率（%）
- 颜色指示（🟢 正常 / 🟡 中等 / 🔴 严重）

**跨平台支持：**
- ✅ macOS
- ✅ Linux
- ✅ Windows (Git Bash)

**输出示例：**

```
🟢 CPU 35% 🟢 MEM 12GB 🟡 DSK 72%
```

**配置：**

```bash
# 1. 复制脚本
cp example-system-status.sh ~/.claude/scripts/claude-hooks/statusline/system-status.sh
chmod +x ~/.claude/scripts/claude-hooks/statusline/system-status.sh

# 2. 设置到 settings.json
# 在 --extra-cmd 中使用
--extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/system-status.sh"
```

**性能提示：**

- CPU 检查需要采样，首次调用会有短暂延迟
- 建议缓存时间 30 秒左右
- 如果响应慢，检查系统负载

---

### 🗂️ Git 状态 (`example-git-status.sh`)

显示当前 Git 仓库的分支、改动状态和推送进度。

**功能：**
- 当前分支名
- 未提交的改动类型和数量
- 待推送提交数
- 待拉取提交数

**输出示例：**

```
✅ main         （没有改动）
⚠️ feature      （5 changes: +2~1-1?1）
🔄 main ↑3↓1   （3 个待推送，1 个待拉取）
```

**配置：**

```bash
# 1. 复制脚本
cp example-git-status.sh ~/.claude/scripts/claude-hooks/statusline/git-status.sh
chmod +x ~/.claude/scripts/claude-hooks/statusline/git-status.sh

# 2. 在项目目录启动 Claude Code
# statusline 会自动检测当前仓库状态

# 3. 设置到 settings.json
--extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/git-status.sh"
```

**适用场景：**

- 快速检查当前分支
- 避免在错误的分支上工作
- 监控未提交的改动
- 提醒有未推送的提交

---

### 🌤️ 天气状态 (`example-weather.sh`)

显示当前地点的天气和温度（使用免费的 wttr.in API）。

**功能：**
- 实时天气条件
- 当前温度
- Emoji 表示天气类型
- 自动地理位置或手动设置

**配置：**

```bash
# 方案 1：按城市名称
export WEATHER_CITY="Beijing"

# 方案 2：按经纬度（更加精确）
export WEATHER_LAT="39.9"
export WEATHER_LON="116.4"

# 方案 3：自动检测（使用 IP 地理位置）
# 默认使用 wttr.in 自动检测

# 测试
bash ~/.claude/scripts/claude-hooks/statusline/weather.sh
# 输出：{"label":"☀️ 28°C"}
```

**输出示例：**

```
☀️ 28°C      （晴天）
⛅ 18°C      （多云）
🌧️ 15°C      （下雨）
❄️ -5°C      （下雪）
🔥 35°C      （炎热）
```

**自定义：**

```bash
# 修改缓存时间
CACHE_TTL=1800  # 30 分钟（天气不常变化）

# 修改 API 端点（如果国内访问 wttr.in 慢）
# 可改用其他天气 API 如 api.weatherapi.com
```

**故障排除：**

| 输出 | 原因 | 解决方案 |
|------|------|--------|
| `Unknown Location` | 城市名拼写错误 | 确认城市名称或使用经纬度 |
| `Weather Offline` | 网络不可达 | 检查网络，考虑使用代理 |
| `Weather Error` | API 解析错误 | 检查脚本，更新 API 格式代码 |

---

### 🔄 聚合工具 (`example-aggregate.sh`)

将多个 statusline 工具的输出聚合到一行中。

**功能：**
- 并行调用多个工具
- 智能过滤空结果
- 超时保护（避免单个工具拖累启动速度）
- 优先级排序

**配置优先级：**

```bash
# 默认优先级（可在脚本中修改）
# 1. OpenRouter 信用度
# 2. GitHub 状态
# 3. 系统资源
# 4. 自定义工具
```

**示例：**

```bash
# 输出示例（多个工具）
💰 394.34/500 | 👨‍💻 username | 🟢 CPU35% 🟢 MEM12GB
```

**使用方法：**

```bash
# 1. 先安装所有需要的工具
cp example-*.sh ~/.claude/scripts/claude-hooks/statusline/
chmod +x ~/.claude/scripts/claude-hooks/statusline/*.sh

# 2. 复制聚合脚本
cp example-aggregate.sh ~/.claude/scripts/claude-hooks/statusline/aggregate.sh
chmod +x ~/.claude/scripts/claude-hooks/statusline/aggregate.sh

# 3. 在 settings.json 中使用
--extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/aggregate.sh"

# 4. 测试
bash ~/.claude/scripts/claude-hooks/statusline/aggregate.sh
```

**性能：**

- 默认为单个工具 5 秒超时
- 通过并行调用减少总时间
- 自动跳过错误或超时的工具

---

## 创建自己的工具

如果你想开发新的 statusline 工具，参考 [ADDING_FEATURES.md](../ADDING_FEATURES.md)。

### 模板

```bash
#!/bin/bash
# 我的自定义工具

set -e

CACHE_FILE="${HOME}/.claude/my-tool-cache.json"
CACHE_TTL=60

check_cache() {
  [[ -f "$CACHE_FILE" ]] && [[ $(( $(date +%s) - $(stat -c%Y "$CACHE_FILE" 2>/dev/null || stat -f%m "$CACHE_FILE") )) -lt $CACHE_TTL ]]
}

get_data() {
  # 从 API 或本地数据源获取数据
  local data=$(curl -s "https://api.example.com/data")
  echo "$data"
}

format_output() {
  local data="$1"
  # 解析和格式化数据
  local label="✨ $data"
  echo "{\"label\":\"$label\"}"
}

main() {
  if check_cache; then
    cat "$CACHE_FILE"
  else
    local data=$(get_data)
    local output=$(format_output "$data")
    echo "$output" > "$CACHE_FILE"
    echo "$output"
  fi
}

main
```

---

## 常见问题

### Q: 多个工具会拖累启动速度吗？

A: 不会。因为 `--extra-cmd` 是异步调用的，不会阻塞 claude-hud 启动。但如果单个工具响应慢，会影响显示更新频率。

### Q: 能否组合多个工具？

A: 推荐使用 `example-aggregate.sh` 或自己创建聚合脚本，参考上面的示例。

### Q: API 密钥的安全性？

A: 建议将敏感信息存放在 `~/.cchooks/secrets.env` 中，文件权限设为 `600`，然后在脚本中引入。

### Q: 如何排查问题？

A: 直接运行脚本，查看 JSON 输出，确认格式正确。使用 `time` 命令检查响应时间。

### Q: 在 Windows (Git Bash) 上没反应？

A: 确保脚本中所有路径使用正斜杠 `/`，命令前加上 `bash` 前缀，参考 [ADDING_FEATURES.md](../ADDING_FEATURES.md) 的跨平台部分。

---

## 贡献

如果你创建了有用的 statusline 工具，欢迎提交 PR 到 claude-code-hooks 项目！

要求：
- 跨平台兼容（macOS、Linux、Windows）
- 包含完整的使用文档
- 实现缓存机制
- 优雅的错误处理
- 性能优化（响应 < 500ms）

---

## 许可证

与 claude-code-hooks 主项目相同。
