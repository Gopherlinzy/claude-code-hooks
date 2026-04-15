# 🪄 Claude HUD 状态栏工具

为 Claude Code 状态栏增强实时 OpenRouter API 信用额度监控和会话成本追踪。

## ⚡ 快速开始

**在 claude-hud 状态栏显示 OpenRouter 信用额度：**

```
Amazon Bedrock: claude-4.5-haiku - $4.78 | 💰 334.83/500 ▓▓▓▓▓▓▓░░░ 67%
```

显示内容：
- **会话成本**：`Amazon Bedrock: claude-4.5-haiku - $4.78`（提供商、模型、成本）
- **账户余额**：`334.83/500`（剩余 / 总限额）
- **进度条**：`▓▓▓▓▓▓▓░░░`（10 字符，每个代表 10%）
- **百分比**：`67%`

## 🏗️ 架构设计

### 工作原理

```
┌─────────────────┐
│  Claude Code    │
│   (claude-hud)  │
└────────┬────────┘
         │
         │ 调用 --extra-cmd
         │
┌────────▼────────────────────────────────┐
│ openrouter-statusline.js (Node.js)      │
├─────────────────────────────────────────┤
│ • 获取余额: /api/v1/key                   │
│ • 读取缓存成本: /tmp/claude-..json        │
│ • 格式化输出: { label: "..." }           │
└────────┬────────────────────────────────┘
         │
         │ 返回 JSON
         │
┌────────▼─────────────────┐
│ claude-hud 在状态栏      │
│ 中显示                    │
└──────────────────────────┘
```

### 数据流

1. **余额** — 从 `https://openrouter.ai/api/v1/key` API 获取
2. **会话成本** — 从 `$TMPDIR/claude-openrouter-cost-*.json` 缓存文件读取
3. **进度条** — 由 `剩余 / 限额` 计算

## 🔧 安装

### 前置条件

- 已设置 `OPENROUTER_API_KEY` 环境变量
- 已安装 claude-hud 插件（`/plugin install claude-hud`）
- 已安装 Node.js

### 第 1 步：复制脚本

```bash
mkdir -p ~/.claude/scripts/claude-hooks/statusline
cp tools/statusline/openrouter-statusline.js ~/.claude/scripts/claude-hooks/statusline/
chmod +x ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js
```

或使用安装器：
```bash
./install.sh
# 在提示时选择 "Statusline tools"
```

### 第 2 步：配置 claude-hud

编辑 `~/.claude/settings.json`，更新（或创建）`statusLine` 部分：

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"node ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js\"'",
    "type": "command"
  }
}
```

**Windows (Git Bash)：** 在 `node` 前加 `bash -c 'node …'`：
```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec bash -c \"node \\\"${plugin_dir}dist/index.js\\\" --extra-cmd \\\"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js\\\"\"'",
    "type": "command"
  }
}
```

### 第 3 步：重启 Claude Code

重启后配置生效。

## ⚙️ 修改源代码

### 为什么要修改 claude-hud

默认情况下，claude-hud 的 `--extra-cmd` 会将输出截断到 50 个字符，这样无法显示完整的会话成本 + 余额信息。解决方案是增加这个限制。

### 如何修改

**找到 claude-hud 安装位置：**

```bash
# 定位 dist 目录
ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/dist/
```

**编辑 extra-cmd.js 文件：**

```bash
# 用编辑器打开
nano ~/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/extra-cmd.js
```

**找到第 5 行并修改：**

```javascript
// 修改前:
const MAX_LABEL_LENGTH = 50;

// 修改后:
const MAX_LABEL_LENGTH = 999;
```

这样就能显示完整的 OpenRouter 信息而不会被截断。

**验证修改：**

```bash
grep "MAX_LABEL_LENGTH" ~/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/extra-cmd.js
# 应该显示: const MAX_LABEL_LENGTH = 999;
```

### 替代方案：补丁脚本

如果你有 patch-stdin-v2-final.js 脚本：

```bash
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js --apply
```

## 📝 配置详情

### 环境变量

```bash
# 必需
export OPENROUTER_API_KEY="sk-or-v1-..."

# 可选 - 未设置时自动检测
export TMPDIR  # 缓存文件的临时目录
```

### 输出格式

状态栏按以下格式显示：

```
{会话成本} | {带进度条的余额}
```

**输出示例：**

- 包含会话成本：
  ```
  Amazon Bedrock: claude-4.5-haiku - $4.78 | 💰 334.83/500 ▓▓▓▓▓▓▓░░░ 67%
  ```

- 无会话成本（还未生成）：
  ```
  💰 334.83/500 ▓▓▓▓▓▓▓░░░ 67%
  ```

- 无 API 密钥（优雅降级）：
  ```
  （不显示额外信息）
  ```

## 🛠️ 自定义源代码

### 编辑 TypeScript 源代码

如果想自定义输出格式或行为，修改 `openrouter-statusline.ts`：

```bash
# 编辑源代码
nano tools/statusline/openrouter-statusline.ts
```

### 关键函数

**`getBalance()`** — 从 OpenRouter API 获取余额
```typescript
async function getBalance(): Promise<string | null>
```

**`tryGetSessionData()`** — 从磁盘读取缓存的会话成本
```typescript
async function tryGetSessionData(): Promise<{sessionCost?: string} | null>
```

**`main()`** — 合并数据并格式化输出
```typescript
async function main() {
  const balance = await getBalance();
  const sessionData = await tryGetSessionData();
  // 格式化并输出...
}
```

### 修改后编译

```bash
cd tools/statusline/
npx tsc openrouter-statusline.ts --target es2020 --module commonjs
```

这会生成 `openrouter-statusline.js`。

### 复制更新后的脚本

```bash
cp tools/statusline/openrouter-statusline.js ~/.claude/scripts/claude-hooks/statusline/
```

## 🔍 成本追踪机制

### 会话成本缓存

脚本为每个会话维护一个 JSON 缓存文件：

```
$TMPDIR/claude-openrouter-cost-{session_id}.json
```

**缓存结构：**

```json
{
  "seen_ids": ["gen-001", "gen-002"],
  "total_cost": 4.78,
  "total_cache_discount": 0.15,
  "last_provider": "Amazon Bedrock",
  "last_model": "anthropic/claude-4.5-haiku"
}
```

**工作原理：**

1. 脚本读取当前会话的缓存文件
2. 从转录文本中提取生成 ID
3. 对每个未见过的 ID，调用 `/api/v1/generation?id={id}` 获取成本
4. 更新总成本并保存缓存文件
5. 显示最后的提供商、模型和总成本

**缓存优势：**

- 避免对同一生成的重复 API 调用
- 跟踪一个会话中多个 API 调用的成本
- 最小化开销（~100ms，缓存命中）

## 📊 性能指标

- **缓存命中**：~1ms（读取本地 JSON）
- **缓存未命中**：~500-800ms（2 个 API 调用）
- **默认行为**：60+ 秒缓存 → 大多数都是命中
- **新生成时**：~1 秒显示更新的成本

## 🐛 故障排除

| 问题 | 解决方案 |
|------|--------|
| OpenRouter 信息不显示 | 检查 `OPENROUTER_API_KEY` 是否已设置：`echo $OPENROUTER_API_KEY` |
| 输出被截断（显示"…"） | 修改 claude-hud `MAX_LABEL_LENGTH` 为 999（见上文） |
| 无会话成本，仅显示余额 | 首次调用还未完成，或生成 ID 未捕获 |
| 缓存权限错误 | 检查 `/tmp` 或 `$TMPDIR` 是否可写：`ls -la $TMPDIR` |
| 超时错误 | 通常是网络问题或 OpenRouter API 响应慢，通常 60 秒后恢复 |

### 调试模式

启用调试输出：

```bash
DEBUG=claude-hud node ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js
```

## 📚 相关文件

- `openrouter-statusline.ts` — TypeScript 源代码（自定义时编辑）
- `openrouter-statusline.js` — 编译后的 JavaScript（claude-hud 运行的版本）
- `openrouter-statusline.d.ts` — TypeScript 类型定义
- `examples/` — 其他 API 的状态栏实现示例

## 📖 文档

- `INDEX.md` — 功能概览和导航
- `QUICK_REFERENCE.md` — 快速查找输出格式
- `ADDING_FEATURES.md` — 添加新状态栏功能的指南
- `examples/` — 示例实现（GitHub、Git、天气、系统、聚合）

## 🔗 API 参考

### 使用的 OpenRouter 端点

**获取账户余额：**
```bash
curl https://openrouter.ai/api/v1/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

响应字段：
- `data.limit_remaining` — 剩余信用
- `data.limit` — 总限额
- `data.usage` — 已使用（可选）

**获取生成成本：**
```bash
curl "https://openrouter.ai/api/v1/generation?id={id}" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

响应字段：
- `data.total_cost` — 美元成本
- `data.cache_discount` — 应用的折扣
- `data.provider_name` — 提供商名称
- `data.model` — 模型标识符

## 📄 许可证

与 claude-code-hooks 主项目相同。
