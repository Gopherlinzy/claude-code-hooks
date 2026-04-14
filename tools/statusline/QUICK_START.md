# ⚡ 快速开始 - claude-hud 补丁

## 问题

你的 statusline 显示有问题，比如：
- Model 显示不完整：`[sonnet 4]` 而不是 `[Claude Sonnet 4.0]`
- Provider 不显示：没有 `| OpenRouter` 这样的供应商标识

## 解决方案（3 步）

### 1️⃣ 应用补丁

```bash
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply
```

**输出应该是：**
```
✅ getModelName() patched
✅ getProviderLabel() patched
✅ Patch applied successfully!
```

### 2️⃣ 重启 Claude Code

关闭 Claude Code，完全退出，再重新打开。

### 3️⃣ 验证效果

StatusLine 现在应该显示：
```
[Claude Sonnet 4.0 | OpenRouter] ███████░░░ 70%
```

---

## 出问题了？

### 补丁不生效

```bash
# 检查补丁状态
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --status

# 应该显示：✅ Patch is applied
```

如果显示 `❌ Patch is NOT applied`，重新运行：
```bash
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --apply
```

### 想要回滚

```bash
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-inline.js --revert
```

---

## 更多信息

👉 详细文档：`~/.claude/scripts/claude-hooks/statusline/PATCH_GUIDE.md`

---

**就这么简单！** 🎉
