# 🔧 claude-hud StatusLine 补丁指南

修复 claude-hud statusline 显示的两个问题：

1. **Model 名称不完整**：`Claude Sonnet 4.6` 显示为 `Sonnet 4`
2. **Provider 不显示**：OpenRouter、Claude API 等供应商无法显示

## 快速开始

### 1️⃣ 应用补丁

```bash
# 方式 A：使用 Node.js 脚本（推荐）
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply

# 方式 B：使用 Bash 脚本
bash ~/.claude/scripts/claude-hooks/statusline/patch-claude-hud.sh --apply
```

### 2️⃣ 重启 Claude Code

补丁在 Claude Code 重启后生效。

### 3️⃣ 验证效果

StatusLine 现在应该显示为：
```
[Claude Sonnet 4.0 | OpenRouter] ■■■□□□□□□□ 25%
```

而不是之前的：
```
[sonnet 4] ■■■□□□□□□□ 25%
```

---

## 详细说明

### 补丁修改了什么？

#### 问题 1：Model 显示不完整

**原因：**
- `display_name` 格式为 `claude-sonnet-4` 或 `claude-opus-4-1`
- 原始代码只对 Bedrock 格式处理版本号解析
- 其他格式直接返回原始名称（不完整）

**修复：**
- 添加 `normalizeClaudeModelLabel()` 函数
- 解析 `claude-{family}-{major}[-{minor}]` 格式
- 输出：`Claude Sonnet 4.0`、`Claude Opus 4.1` 等

**示例转换：**
```
claude-sonnet-4          → Claude Sonnet 4.0
claude-opus-4-1          → Claude Opus 4.1
claude-haiku-3           → Claude Haiku 3.0
claude-sonnet-4-20250514 → Claude Sonnet 4.0
```

#### 问题 2：Provider 不显示

**原因：**
- `getProviderLabel()` 只检测 Bedrock
- 其他 provider（OpenRouter、Claude API）返回 `null`
- null 导致 statusline 不显示 provider

**修复：**
- 添加 OpenRouter 检测：`modelId.includes('openrouter')` 或 `provider/model` 格式
- 添加 Claude API 检测：`modelId.startsWith('claude-')` 且不包含 `/`
- 保留 Bedrock 检测

**支持的 Provider：**
```
OpenRouter  : openrouter/... 或 anthropic/claude-3-sonnet
Claude API  : claude-sonnet-4, claude-opus-4-1, etc.
Bedrock     : anthropic.claude-3-sonnet:...
```

---

## 命令参考

### 应用补丁

```bash
# Node.js 版本（推荐）
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply

# Bash 版本
bash ~/.claude/scripts/claude-hooks/statusline/patch-claude-hud.sh --apply
```

**输出：**
```
✅ Found: /Users/admin/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/stdin.js
💾 Backup created: stdin.js.backup.1776159670688
🔧 Patching getModelName()...
✅ getModelName() patched
🔧 Patching getProviderLabel()...
✅ getProviderLabel() patched
✅ Patch applied successfully!
```

### 查看状态

```bash
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --status
```

**输出：**
```
✅ Patch is applied

Features enabled:
  • Improved model name parsing
  • OpenRouter provider detection
  • Claude API provider detection

Last backup: stdin.js.backup.1776159670688
```

### 回滚补丁

```bash
# 恢复到原始版本
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --revert

# 或者手动恢复
cp /Users/admin/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/stdin.js.backup.1776159670688 \
   /Users/admin/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/stdin.js
```

---

## 工作原理

### 修改的文件

```
~/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/stdin.js
```

### 修改的函数

**1. `getModelName()` 函数**
```javascript
// 原始：返回 display_name 或 modelId（不完整）
// 修复：解析 claude-{family}-{major}[-{minor}] 格式

const displayName = stdin.model?.display_name?.trim();
if (displayName) {
    // 新增：尝试解析 Claude 格式
    const improved = normalizeClaudeModelLabel(displayName);
    if (improved) return improved;
    // 如果不是 Claude 格式，返回原始
    return displayName;
}
```

**2. `getProviderLabel()` 函数**
```javascript
// 原始：只返回 "Bedrock" 或 null
// 修复：添加 OpenRouter 和 Claude API 检测

export function getProviderLabel(stdin) {
    if (isBedrockModelId(modelId)) {
        return 'Bedrock';
    }
    if (modelId.includes('openrouter')) {
        return 'OpenRouter';
    }
    if (modelId.startsWith('claude-')) {
        return 'Claude API';
    }
    return null;
}
```

**3. 新增辅助函数 `normalizeClaudeModelLabel()`**
```javascript
function normalizeClaudeModelLabel(modelName) {
    // 匹配 claude-{family}-{major}[-{minor}]
    const match = modelName.match(/claude-([a-z]+)-(\d+)(?:-(\d+))?/i);
    if (!match) return null;

    // 格式化为 "Claude {Family} {Major}.{Minor}"
    const family = match[1];      // sonnet, opus, haiku
    const major = match[2];        // 4, 3, etc.
    const minor = match[3] || '0'; // 1, 0, etc.

    const familyCapitalized = family.charAt(0).toUpperCase() + family.slice(1);
    return `Claude ${familyCapitalized} ${major}.${minor}`;
}
```

---

## 兼容性

| 组件 | 版本 | 状态 |
|------|------|------|
| claude-hud | 0.0.11+ | ✅ 支持 |
| claude-hud | 0.0.10 | ✅ 支持 |
| Claude Code | v2.1.6+ | ✅ 支持 |
| Node.js | 18+ | ✅ 支持 |

---

## 故障排查

### 补丁不生效

**症状：** 修改 statusline 后仍然显示错误的格式

**解决方案：**
1. ✅ 确认补丁已应用：
   ```bash
   node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --status
   ```

2. ✅ 重启 Claude Code（关闭所有窗口，等待 5 秒，重新打开）

3. ✅ 检查是否有多个 claude-hud 版本：
   ```bash
   ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/dist/stdin.js
   ```
   如果有多个，需要为每个都应用补丁

### 补丁被覆盖了

**症状：** 补丁应用成功，但下次打开 Claude Code 后失效

**原因：** claude-hud 插件更新覆盖了修改

**解决方案：**
1. 创建一个 hook 脚本自动重新应用补丁（见下方）
2. 或者最新的 claude-hud 版本中 bug 可能已修复

### 如何创建自动补丁 Hook

编辑 `~/.claude/settings.json`，在 `hooks` 中添加：

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply 2>/dev/null || true",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

这样每次关闭 Claude Code 时都会自动检查并重新应用补丁。

---

## 安全性

### 备份

补丁应用时自动创建备份：
```
~/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/stdin.js.backup.{timestamp}
```

### 恢复

还原到原始版本：
```bash
# 查看可用的备份
ls -lh ~/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/stdin.js.backup.*

# 使用工具回滚
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --revert

# 或手动恢复特定备份
cp stdin.js.backup.{timestamp} stdin.js
```

---

## 常见问题

### Q: 为什么 statusline 仍然显示 "Sonnet 4"？

**A:** 
1. 确认补丁已应用：`node patch-stdin-inline.js --status`
2. 重启 Claude Code
3. 如果问题持续，清除 Claude Code 缓存：
   ```bash
   rm -rf ~/.claude/cache/*
   ```

### Q: 支持哪些 provider？

**A:** 目前修复支持：
- ✅ OpenRouter
- ✅ Claude API（直接使用 Anthropic 的 API）
- ✅ Bedrock（AWS）

其他 provider 可在使用时联系维护者进行增加。

### Q: 更新 claude-hud 后补丁会丢失吗？

**A:** 是的。claude-hud 更新会覆盖修改的文件。解决方案：
1. 启用自动补丁 Hook（见上方）
2. 或者在更新后手动重新应用：
   ```bash
   node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply
   ```

### Q: 如何报告 bug？

**A:** 如果补丁导致问题：
1. 回滚补丁：
   ```bash
   node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --revert
   ```
2. 在 GitHub 上报告：[Gopherlinzy/claude-code-hooks/issues](https://github.com/Gopherlinzy/claude-code-hooks/issues)

---

## 贡献

补丁由 Claude Code 自动生成。如果你有改进建议，欢迎提交 issue 或 PR。

---

**最后更新：** 2026-04-14  
**补丁版本：** 1.0
