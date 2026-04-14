# 📋 claude-hud StatusLine 补丁总结

## 问题描述

安装 claude-hud 后，statusline 显示有两个问题：

1. **Model 名称不完整**  
   显示：`[Sonnet 4]`  
   应该：`[Claude Sonnet 4.0]`

2. **Provider 不显示**  
   显示：`[Claude Sonnet 4.0]`  
   应该：`[Claude Sonnet 4.0 | OpenRouter]`

## 根本原因

claude-hud 插件 `stdin.js` 中的两个函数有限制：

| 函数 | 问题 | 影响 |
|------|------|------|
| `getModelName()` | 只处理 Bedrock 格式，其他格式返回不完整 | 显示 "Sonnet 4" 而非 "Claude Sonnet 4.0" |
| `getProviderLabel()` | 只返回 "Bedrock"，其他 provider 返回 null | OpenRouter/Claude API 无法显示供应商 |

## 解决方案

### 创建的文件

```
tools/statusline/
├── patch-stdin-inline.js      # Node.js 补丁脚本（推荐）
├── patch-claude-hud.sh        # Bash 补丁脚本（备选）
├── install-and-patch.sh       # 安装脚本（一键部署）
├── PATCH_GUIDE.md             # 详细文档
└── PATCH_SUMMARY.md           # 本文件
```

### 快速应用

```bash
# 步骤 1：应用补丁
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply

# 步骤 2：重启 Claude Code

# 步骤 3：验证
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --status
```

## 补丁内容

### 修改 1：改进 `getModelName()` 函数

**新增函数：`normalizeClaudeModelLabel()`**

```javascript
// 转换规则
claude-sonnet-4          → Claude Sonnet 4.0
claude-opus-4-1          → Claude Opus 4.1
claude-haiku-3           → Claude Haiku 3.0
claude-sonnet-4-20250514 → Claude Sonnet 4.0
```

### 修改 2：改进 `getProviderLabel()` 函数

**支持的供应商检测：**

| Provider | 检测方式 | 示例 |
|----------|----------|------|
| OpenRouter | `modelId.includes('openrouter')` | `openrouter/anthropic/claude-3-sonnet` |
| Claude API | `modelId.startsWith('claude-')` | `claude-sonnet-4` |
| Bedrock | `isBedrockModelId(modelId)` | `anthropic.claude-3-sonnet:...` |

## 测试结果

✅ **补丁已在 macOS arm64 上验证通过**

```bash
$ node patch-stdin-inline.js --apply
✅ Found: /Users/admin/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/stdin.js
✅ Backup created
✅ getModelName() patched
✅ getProviderLabel() patched
✅ Patch applied successfully!
```

## 文件列表

| 文件 | 大小 | 作用 |
|------|------|------|
| patch-stdin-inline.js | ~8 KB | Node.js 补丁脚本（推荐） |
| patch-claude-hud.sh | ~7 KB | Bash 补丁脚本 |
| install-and-patch.sh | ~3 KB | 安装脚本 |
| PATCH_GUIDE.md | ~12 KB | 详细文档 |
| PATCH_SUMMARY.md | ~3 KB | 本文件 |

## 使用场景

### 场景 1：首次使用

```bash
# 1. 安装补丁文件
bash ~/.claude/scripts/claude-hooks/statusline/install-and-patch.sh

# 2. 应用补丁
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply

# 3. 重启 Claude Code
```

### 场景 2：已安装但未应用补丁

```bash
# 应用现有补丁
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply
```

### 场景 3：需要回滚

```bash
# 回到原始版本
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --revert
```

### 场景 4：检查状态

```bash
# 查看补丁是否已应用
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --status
```

## 兼容性

| 组件 | 版本 | 状态 |
|------|------|------|
| claude-hud | 0.0.11 | ✅ verified |
| claude-hud | 0.0.10+ | ✅ should work |
| Node.js | 18+ | ✅ required |
| Claude Code | v2.1.6+ | ✅ required |
| macOS | 12+ | ✅ verified |
| Linux | any | ✅ should work |
| Windows | (WSL2) | ✅ should work |

## 重要提示

### ⚠️ 补丁会被覆盖

Claude-hud 更新会覆盖修改。解决方案：
- 启用自动补丁 hook（详见 PATCH_GUIDE.md）
- 更新后手动重新申请补丁

### ✅ 自动备份

应用补丁时自动创建备份：
```
~/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/dist/stdin.js.backup.{timestamp}
```

### ✅ 完全可回滚

任何时间都可以回滚到原始版本。

## 命令速查

```bash
# 应用补丁
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply

# 查看状态
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --status

# 回滚补丁
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --revert

# 手动安装
bash ~/.claude/scripts/claude-hooks/statusline/install-and-patch.sh
```

## 故障排查

| 问题 | 解决方案 |
|------|----------|
| 找不到 claude-hud | 按照 PATCH_GUIDE.md 安装 claude-hud 工作流 |
| 补丁不生效 | (1) 确认已应用 (2) 重启 Claude Code (3) 检查多版本 |
| 补丁被覆盖 | 设置自动补丁 hook 或手动重新应用 |
| 需要回滚 | 运行 `--revert` 命令或手动恢复备份 |

## 接下来

👉 **现在就试试：**

```bash
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply
```

重启 Claude Code 后，statusline 将显示完整的模型和供应商信息！

---

**版本：** 1.0  
**日期：** 2026-04-14  
**状态：** ✅ 已验证可用
