# 🪄 Claude HUD 状态栏工具

为 claude-hud 状态栏增强实时 API 信用额度监控和自定义指标。

## 🔧 claude-hud 显示补丁

修复 claude-hud 默认显示中的两个 Bug：

| 修复前 | 修复后 |
|--------|--------|
| `[sonnet 4]` | `[Claude Sonnet 4.6 \| Claude API]` |
| `[Claude Haiku 4.0]` | `[Claude Haiku 4.5 \| OpenRouter]` |
| `[Unknown]` | `[glm-5.1 \| z-ai]` |

**修复内容：**
- Model 版本被截断（4.6 显示成 4 或 4.0）
- Provider 不显示（OpenRouter、Claude API、自定义 base URL）
- 非 Claude 模型（glm、gpt、llama…）无法识别
- OpenRouter `vendor/model` 格式（`anthropic/claude-sonnet-4-5`）无法解析

### 安装补丁

**第 1 步 — 下载补丁脚本**

```bash
mkdir -p ~/.claude/scripts/claude-hooks/statusline
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/tools/statusline/patch-stdin-v2-final.js \
  -o ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js
chmod +x ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js
```

> 🇨🇳 **GitHub 太慢？** 用镜像：
> ```bash
> curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/tools/statusline/patch-stdin-v2-final.js \
>   -o ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js
> ```

**第 2 步 — 应用补丁**

```bash
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js --apply
```

预期输出：
```
✅ getModelName() patched
✅ getProviderLabel() patched
✅ Patch v2 applied!
```

**第 3 步 — 重启 Claude Code**

补丁在重启时生效。

### 其他补丁命令

```bash
# 检查补丁是否已应用
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js --status

# 回滚到原始版本
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js --revert
```

### Provider 识别原理

补丁读取 `ANTHROPIC_BASE_URL` 环境变量来识别真实 Provider：

| `ANTHROPIC_BASE_URL` | 显示的 Provider |
|---|---|
| `api.anthropic.com`（或未设置） | `Claude API` |
| `openrouter.ai/…` | `OpenRouter` |
| `api.z-ai.com/…` | `z-ai` |
| `api.aihubmix.com/…` | `aihubmix` |
| AWS Bedrock 模型 ID | `Bedrock` |

对于 OpenRouter，`vendor/model` 格式被正确识别：

| `ANTHROPIC_MODEL` | 显示为 |
|---|---|
| `anthropic/claude-sonnet-4-5` | `Claude Sonnet 4.5 \| OpenRouter` |
| `z-ai/glm-5.1` | `glm-5.1 \| OpenRouter` |
| `meta-llama/llama-3.3-70b-instruct` | `llama-3.3-70b-instruct \| OpenRouter` |

### settings.json — statusLine 命令

安装 claude-hud（`/plugin install claude-hud`）和运行配置（`/claude-hud:setup`）后，你的 `~/.claude/settings.json` 中应该有 `statusLine` 块。如果没有，或你想手工配置：

```bash
# 自动生成你的系统对应的正确命令
~/.claude/scripts/claude-hooks/setup-statusline.sh
```

或者把这个模板复制粘贴到 `~/.claude/settings.json`（替换 `NODE_PATH` 和 `PLUGIN_DIR`）：

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
```

> **Windows (Git Bash)：** 在 `node` 前加 `bash -c 'node …'` 并用正斜杠。`setup-statusline.sh` 脚本会自动处理。

#### 已应用补丁、不需要 OpenRouter 密钥

如果你只想要 Model + Provider 标签，不需要 OpenRouter 信用额度，可以完全省去 `--extra-cmd`：

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\"'",
    "type": "command"
  }
}
```

补丁已经修复了 claude-hud 内部的显示 — 不需要额外脚本。

## 可用工具

### OpenRouter 信用额度监控

在 claude-hud 状态栏中显示 OpenRouter API 余额，并附带可视化进度条。

**功能特性：**
- 实时显示信用额度和限额
- 可视化进度条（10 字符，每个字符代表 10%）
- 60 秒智能缓存（最小化 API 调用）
- 友好的错误处理（无密钥、网络离线、认证失败）
- 轻量级且快速（~100ms，含缓存）

**输出格式：**
```
💰 394.34/500 ▓▓▓▓▓▓▓░░░ 79%
```

显示内容：
- `💰` — 表情符号
- `394.34/500` — 剩余信用额度 / 总限额
- `▓▓▓▓▓▓▓░░░` — 可视化进度条（79% → 7 个满格）
- `79%` — 百分比

## 安装

### 方案 1：通过 claude-code-hooks 安装脚本

```bash
./install.sh
# 在提示时选择 "Statusline tools"
```

安装器会：
1. 复制脚本到 `~/.claude/scripts/claude-hooks/statusline/`
2. 引导你完成配置
3. 自动更新你的 `settings.json`

### 方案 2：手动安装

```bash
# 复制脚本
cp tools/statusline/openrouter-status.sh ~/.claude/scripts/claude-hooks/statusline/

# 授予执行权限
chmod +x ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh

# 确保环境中已设置 OPENROUTER_API_KEY
echo $OPENROUTER_API_KEY  # 应该显示你的密钥
```

## 配置

### 添加到 Claude Code 设置

编辑 `~/.claude/settings.json` 并更新 `statusLine` 部分，加入 `--extra-cmd` 参数：

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print $(NF-1) \"\\t\" $(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"/path/to/node\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
```

或者使用安装器，它会自动完成这一切。

### 环境变量

确保 `OPENROUTER_API_KEY` 在你的 shell 环境中可用：

```bash
# 添加到 ~/.zshrc 或 ~/.bashrc
export OPENROUTER_API_KEY="sk-or-v1-..."
```

## 工作原理

1. **claude-hud** 通过 `--extra-cmd` 参数调用 `openrouter-status.sh`
2. 脚本检查有效的缓存（60 秒 TTL）
3. 缓存未命中时，调用 `https://openrouter.ai/api/v1/key` API
4. 从响应中解析 `limit_remaining` 和 `limit`
5. 计算百分比并生成进度条
6. 返回 JSON：`{ "label": "💰 394.34/500 ▓▓▓▓▓▓▓░░░ 79%" }`
7. claude-hud 在状态栏中显示

## 故障排除

| 问题 | 解决方案 |
|------|--------|
| 显示 `No Key` | 设置 `OPENROUTER_API_KEY` 环境变量 |
| 显示 `Auth Failed` | 检查你的 API 密钥是否有效 |
| 显示 `Offline` | 网络连接问题，检查 curl 是否正常 |
| 显示 `☐` | 缓存文件损坏，尝试：`rm ~/.claude/openrouter-cache.json` |
| 更新缓慢 | 缓存正常工作，等待 60 秒后获取最新数据 |

## 自定义

### 修改缓存 TTL

编辑 `openrouter-status.sh`：
```bash
CACHE_TTL=30  # 从 60 改为 30 秒
```

### 改变显示格式

示例：仅显示百分比
```bash
label=$(printf "💰 %d%%\n" "$percent")
```

示例：添加使用量数据
```bash
usage=$(echo "$response" | jq -r '.data.usage // 0')
label=$(printf "💰 %.2f/%.0f %s %d%% | Used: %.2f\n" "$remaining" "$limit" "$bar" "$percent" "$usage")
```

### 低额度警告

```bash
# 在计算百分比之后：
if (( $(echo "$remaining < 10" | bc -l 2>/dev/null) )); then
  emoji="🪫"  # 低电量表情
else
  emoji="💰"
fi
label=$(printf "%s %.2f/%.0f %s %d%%\n" "$emoji" "$remaining" "$limit" "$bar" "$percent")
```

## API 详情

使用 OpenRouter 的 `GET /api/v1/key` 端点：

```bash
curl https://openrouter.ai/api/v1/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

**所用响应字段：**
- `data.limit_remaining` — 剩余信用额度
- `data.limit` — 总信用限额
- `data.usage` — 已使用的总信用（可选）
- `data.usage_daily` — 每日使用量（可选）

所有调用都缓存 60 秒以保持在速率限制内。

## 性能影响

- **缓存命中**：~1ms（读取本地 JSON 文件）
- **缓存未命中**：~500-800ms（API 调用 + 解析）
- **默认行为**：缓存 60 秒 → 大多数时间 ~1ms
- **网络开销**：最小化，curl 超时设为 2 秒

## 许可证

与 claude-code-hooks 主项目相同。
