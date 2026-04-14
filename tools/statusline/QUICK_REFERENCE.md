# 🚀 StatusLine 工具快速参考

## 输出格式

所有 statusline 工具必须返回：

```json
{"label":"显示在状态栏中的文字"}
```

## 基础模板

```bash
#!/bin/bash
CACHE_FILE="${HOME}/.claude/cache.json"
CACHE_TTL=60

check_cache() {
  [[ -f "$CACHE_FILE" ]] && [[ $(( $(date +%s) - $(stat -c%Y "$CACHE_FILE" 2>/dev/null || stat -f%m "$CACHE_FILE") )) -lt $CACHE_TTL ]]
}

main() {
  if check_cache; then
    cat "$CACHE_FILE"
  else
    local label="✨ Your Data"
    echo "{\"label\":\"$label\"}" | tee "$CACHE_FILE"
  fi
}

main
```

## 安装工具

```bash
# 复制获取执权限
cp my-status.sh ~/.claude/scripts/claude-hooks/statusline/
chmod +x ~/.claude/scripts/claude-hooks/statusline/my-status.sh

# 测试
bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh | jq .
```

## 配置 settings.json

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh\"'",
    "type": "command"
  }
}
```

## 常见 Emoji

```
💻 系统      ☁️ 云服务    🔐 安全      📊 数据
🌐 网络      🔧 工具      ⚙️ 配置      📝 文本
📱 手机      🐳 容器      🗂️ 文件      🔗 链接
✅ 成功      ❌ 失败      ⚠️ 警告      🔄 同步
🟢 正常      🟡 中等      🔴 严重      🚀 启动
💰 信用      📬 消息      🌤️ 天气      🔋 电量
🎯 目标      📈 上升      📉 下降      💡 建议
```

## Emoji 温度指示

```bash
if (( $(echo "$temp < 0" | bc -l) )); then
  emoji="❄️"
elif (( $(echo "$temp > 30" | bc -l) )); then
  emoji="🔥"
else
  emoji="🌡️"
fi
```

## Emoji 百分比进度条

```bash
# 10 字符进度条
filled=$((percent / 10))
empty=$((10 - filled))
bar=""
for ((i = 0; i < filled; i++)); do bar="${bar}▓"; done
for ((i = 0; i < empty; i++)); do bar="${bar}░"; done
# 结果：▓▓▓▓░░░░░░
```

## 快速 API 调用（带缓存和超时）

```bash
# 获取 API 数据
response=$(curl -s --max-time 2 \
  -H "Authorization: Bearer $TOKEN" \
  "https://api.example.com/data" 2>/dev/null || echo "")

# 检查是否为空
[[ -z "$response" ]] && echo '{"label":"Offline"}' && exit

# 检查是否有错误
echo "$response" | grep -q '"error"' && echo '{"label":"Error"}' && exit

# 提取字段
field=$(echo "$response" | grep -o '"field":"[^"]*' | cut -d'"' -f4)
```

## 跨平台路径处理

```bash
# ✅ 同时适用 macOS、Linux、Windows
HOME_DIR="${HOME}"  # 兼容所有平台

# ✅ 临时文件
TEMP_FILE="/tmp/myfile.tmp"

# ✅ 使用 stat 兼容两个版本
mtime=$(stat -c%Y file 2>/dev/null || stat -f%m file 2>/dev/null)

# ✅ 使用 date 代替 printf "%(%s)T"
now=$(date +%s)
```

## 处理命令不存在

```bash
# 检查 jq 是否存在，否则用 grep 替代
if command -v jq &>/dev/null; then
  value=$(echo "$json" | jq -r '.field')
else
  value=$(echo "$json" | grep -o '"field":"[^"]*' | cut -d'"' -f4)
fi
```

## 并行调用多个工具（聚合）

```bash
# 创建临时文件
temp1="/tmp/api1_$$.json"
temp2="/tmp/api2_$$.json"

# 并行调用
(curl -s "$URL1" > "$temp1" &)
(curl -s "$URL2" > "$temp2" &)
wait

# 合并结果
api1=$(cat "$temp1")
api2=$(cat "$temp2")
rm -f "$temp1" "$temp2"
```

## JSON 转义

```bash
# ✅ 正确：避免特殊字符
label="User: John (50%)"
echo "{\"label\":\"$label\"}"  # ✅ 工作

# ✅ 正确：转义引号和反斜杠
label='He said "Hello"'
label="${label//\"/\\\"}"  # 转义引号
echo "{\"label\":\"$label\"}"

# ✅ 正确：避免单引号问题
label='It'\''s working'  # 转义单引号
echo "{\"label\":\"$label\"}"
```

## 缓存策略

| 场景 | TTL (秒) |
|------|---------|
| API 信用度 | 60-180 |
| Git 状态 | 10-30 |
| GitHub 信息 | 300-600 |
| 系统资源 | 5-10 |
| 天气 | 1800+ |
| 时间 | 1-5 |

## 故障排除速查表

```bash
# 验证 JSON 格式
bash my-status.sh | jq . 2>&1

# 测试响应时间
time bash my-status.sh

# 查看完整的 stderr 输出
bash my-status.sh 2>&1

# 监控缓存内容
watch 'cat ~/.claude/cache.json' 2>/dev/null

# 测试 API 连接
curl -I -v https://api.example.com/endpoint

# 检查环境变量
env | grep -i token

# 验证脚本权限
ls -la ~/.claude/scripts/claude-hooks/statusline/my-status.sh
```

## 一行命令测试 StatusLine

```bash
bash -c 'plugin_dir=$(ls -d "${HOME}/.claude"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node "${plugin_dir}dist/index.js" --extra-cmd "bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh"'
```

## 性能目标

- **缓存命中**：< 10ms
- **缓存未命中**：< 500ms
- **总启动时间**：不增加 > 200ms

## Windows (Git Bash) 注意事项

```bash
# ✅ 使用正斜杠
HOME_DIR="${HOME}"  # 正确

# ✅ 路径转换
path_unix="${path//\\/\/}"  # 转换反斜杠为正斜杠

# ✅ grep 替代品
# 尽量用 grep 而不是其他工具

# ✅ 在 settings.json 中添加 bash 前缀
"--extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/my-status.sh\""
```

## 调试技巧

```bash
# 在脚本中添加调试输出
set -x  # 打印每个命令

# 只在 DEBUG 环境变量设置时打印
[[ -n "$DEBUG" ]] && echo "Debug: $var" >&2

# 查看脚本执行
bash -x my-status.sh 2>&1 | head -50

# 查看环境变量
declare -p | grep -i my_var
```

---

**更多信息**：参考 [ADDING_FEATURES.md](./ADDING_FEATURES.md) 和 [examples/README.md](./examples/README.md)
