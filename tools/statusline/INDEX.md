# 📚 Claude HUD StatusLine 功能指南全索引

为 claude-hud statusline 增加实时监控和自定义指标的完整文档。

## 📖 文档体系

### 1. **快速参考** ([QUICK_REFERENCE.md](./QUICK_REFERENCE.md)) ⭐ 从这里开始
快速查找表和代码片段，包括：
- 输出格式
- 基础模板
- Emoji 速查
- 故障排除
- **最适合**：快速查询、复制代码

### 2. **功能开发指南** ([ADDING_FEATURES.md](./ADDING_FEATURES.md)) 🚀 详细教程
完整的开发指南，包括：
- 核心原理和工作流程
- 范例 1-3：从简单到复杂
- 集成到 settings.json
- 最佳实践（缓存、跨平台、性能）
- 常见需求代码示例
- 提交贡献的流程
- **最适合**：学习原理、创建新工具

### 3. **示例工具库** ([examples/README.md](./examples/README.md)) 🎛️ 现成工具
五个即插即用的工具：

| 工具 | 文件 | 功能 | TTL |
|------|------|------|-----|
| GitHub 用户 | `example-github-status.sh` | 用户名、仓库数、通知 | 5min |
| 系统监控 | `example-system-status.sh` | CPU、内存、磁盘 | 实时 |
| Git 状态 | `example-git-status.sh` | 分支、改动、推送 | 10s |
| 天气显示 | `example-weather.sh` | 温度、条件、Emoji | 30min |
| 多工具聚合 | `example-aggregate.sh` | 合并多个输出 | 可配 |

- **最适合**：复制-粘贴使用、快速集成

### 4. **原有文档**
- [README.md](./README.md) — OpenRouter 信用监控（英文）
- [README_CN.md](./README_CN.md) — OpenRouter 信用监控（中文）

---

## 🎯 按场景快速导航

### 我想...

#### 📌 快速查看 StatusLine 工具能做什么？
→ 阅读本文档下面的"[工具功能概览](#工具功能概览)"部分

#### 🔧 创建我的第一个 StatusLine 工具
→ **推荐路径**：
1. 阅读 [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) 了解格式
2. 参考 [examples/](./examples/) 中的某个工具
3. 复制模板，修改 API 端点和解析逻辑
4. 测试：`bash my-status.sh | jq .`

#### 📚 深入理解原理
→ 阅读 [ADDING_FEATURES.md](./ADDING_FEATURES.md)：
- 工作流程机制
- 缓存策略
- 跨平台兼容性
- 性能优化

#### 🚀 快速安装现成工具
→ 按照 [examples/README.md](./examples/README.md) 的步骤：
1. 选择工具
2. 复制到 `~/.claude/scripts/claude-hooks/statusline/`
3. 设置必要的环境变量（如 `GITHUB_TOKEN`）
4. 更新 `settings.json`

#### 💰 监控 OpenRouter 信用度
→ 阅读 [README.md](./README.md) 或 [README_CN.md](./README_CN.md)

#### 🌍 在 Windows (Git Bash) 上使用
→ 查看 [ADDING_FEATURES.md](./ADDING_FEATURES.md) 的"跨平台兼容性"部分和 [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) 的"Windows 注意事项"

---

## 工具功能概览

### 🔐 认证和开发工具

| 工具 | 显示内容 | 示例输出 |
|------|--------|--------|
| **GitHub** | 用户名、仓库数、通知 | 👨‍💻 username (42 repos) |
| **OpenRouter** | API 信用额度 | 💰 394.34/500 ▓▓░░░░░░░░ 79% |

### 📊 监控工具

| 工具 | 显示内容 | 示例输出 |
|------|--------|--------|
| **系统资源** | CPU / 内存 / 磁盘 | 🟢 CPU35% 🟢 MEM12GB 🟡 DSK72% |
| **Git 状态** | 分支 / 改动 / 同步 | ✅ main \| ⚠️ feature (+5) |
| **天气** | 温度、条件 | ☀️ 28°C |

### 🔄 集成工具

| 工具 | 功能 |
|------|------|
| **聚合工具** | 并行调用多个 statusline 工具，拼接到一行 |

---

## 📝 快速示例

### 最简单的工具

```bash
#!/bin/bash
echo '{"label":"✨ Hello"}'
```

### 带缓存的工具

```bash
#!/bin/bash
CACHE=~/.claude/cache.json

if [[ -f "$CACHE" ]]; then
  cat "$CACHE"
else
  echo '{"label":"✨ Fresh"}' | tee "$CACHE"
fi
```

### 调用 API 的工具

```bash
#!/bin/bash
response=$(curl -s --max-time 2 "https://api.example.com/data")
label=$(echo "$response" | grep -o '"value":"[^"]*' | cut -d'"' -f4)
echo "{\"label\":\"$label\"}"
```

---

## 🛠️ 安装流程

### 方案 A：使用现成工具（推荐新手）

```bash
# 1. 复制工具
cp examples/example-github-status.sh ~/.claude/scripts/claude-hooks/statusline/github-status.sh
chmod +x ~/.claude/scripts/claude-hooks/statusline/github-status.sh

# 2. 设置环境变量
export GITHUB_TOKEN="ghp_..."

# 3. 编辑 ~/.claude/settings.json (statusLine 块)
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/github-status.sh\"'",
    "type": "command"
  }
}

# 4. 重启 Claude Code
```

### 方案 B：创建自己的工具（高阶用户）

```bash
# 1. 学习基础
cat QUICK_REFERENCE.md

# 2. 学习原理
cat ADDING_FEATURES.md

# 3. 创建脚本
cat > ~/.claude/scripts/claude-hooks/statusline/my-tool.sh << 'EOF'
#!/bin/bash
# 你的代码
EOF
chmod +x ~/.claude/scripts/claude-hooks/statusline/my-tool.sh

# 4. 测试
bash ~/.claude/scripts/claude-hooks/statusline/my-tool.sh | jq .

# 5. 集成到 settings.json
# 同方案 A
```

---

## 📊 对比表

### 按复杂度

| 难度 | 工具 | 文档 |
|------|------|------|
| ⭐ 简单 | GitHub、Git、天气 | examples/README.md |
| ⭐⭐ 中等 | 系统资源、聚合 | examples/README.md + QUICK_REFERENCE.md |
| ⭐⭐⭐ 复杂 | 自定义工具 | ADDING_FEATURES.md |

### 按响应时间

| 工具 | 缓存 TTL | 说明 |
|------|---------|------|
| OpenRouter | 60秒 | API 调用，需缓存 |
| GitHub | 300秒 | API 调用，5 分钟缓存 |
| Git | 10秒 | 本地操作，极快 |
| 系统 | 实时 | 子进程调用，快速 |
| 天气 | 1800秒 | 变化慢，30 分钟缓存 |

---

## 🔗 文件树

```
tools/statusline/
├── INDEX.md                          ← 你在这里
├── QUICK_REFERENCE.md                ← 快速查询
├── ADDING_FEATURES.md                ← 详细教程
├── README.md                          ← OpenRouter (EN)
├── README_CN.md                       ← OpenRouter (CN)
├── openrouter-status.sh               ← OpenRouter 费用追踪（generation API，按会话统计）
├── openrouter-balance.sh              ← OpenRouter 余额查询（/api/v1/key，进度条显示）
├── examples/
│   ├── README.md                      ← 示例工具说明
│   ├── example-github-status.sh       ← GitHub 用户信息
│   ├── example-system-status.sh       ← CPU/内存/磁盘
│   ├── example-git-status.sh          ← Git 分支状态
│   ├── example-weather.sh             ← 天气显示
│   └── example-aggregate.sh           ← 多工具聚合
└── [已安装位置]
    └── ~/.claude/scripts/claude-hooks/statusline/
        ├── openrouter-status.sh
        ├── github-status.sh           ← 复制示例到这里
        ├── system-status.sh
        ├── git-status.sh
        └── ...
```

---

## ❓ 常见问题

### Q: StatusLine 工具的输出在哪里显示？

A: 在 Claude Code IDE 右下角的状态栏（如果使用了 claude-hud 插件）。

### Q: 能在 settings.json 中定义多个 statusLine？

A: 不能，`statusLine` 只有一个。但你可以在 `--extra-cmd` 中调用聚合脚本（见 `example-aggregate.sh`）。

### Q: 工具响应慢会怎样？

A: 会影响 Claude Code 启动速度。使用缓存和超时保护。参考 [ADDING_FEATURES.md](./ADDING_FEATURES.md) 的"性能优化"部分。

### Q: 怎样调试工具输出？

A: 
```bash
bash ~/.claude/scripts/claude-hooks/statusline/my-tool.sh | jq .
```

### Q: 能在 Windows 上使用吗？

A: 能，但要注意路径和命令兼容性。参考 [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) 的"Windows 注意事项"。

---

## 📚 学习路径推荐

### 🟢 初学者

1. 阅读本文档（5 分钟）
2. 阅读 [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) 的"基础模板"部分（5 分钟）
3. 从 [examples/](./examples/) 复制一个工具，修改并测试（10 分钟）
4. 集成到 settings.json （5 分钟）

**总计**：约 25 分钟

### 🟡 中级用户

1. 阅读 [ADDING_FEATURES.md](./ADDING_FEATURES.md) 的"核心原理"部分（10 分钟）
2. 查看 2-3 个示例工具的实现（15 分钟）
3. 创建自己的工具（取决于复杂度）
4. 使用 [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) 进行调试

### 🔴 高级用户

1. 直接阅读 [ADDING_FEATURES.md](./ADDING_FEATURES.md) 全文
2. 参考示例代码和最佳实践
3. 开发复杂的多源聚合工具
4. 考虑提交到项目

---

## 🚀 下一步

- [ ] 选择一个工具从 [examples/](./examples/) 开始
- [ ] 将其复制到 `~/.claude/scripts/claude-hooks/statusline/`
- [ ] 配置环境变量（如需要）
- [ ] 更新 `~/.claude/settings.json`
- [ ] 重启 Claude Code，查看效果
- [ ] 根据需要调整缓存时间和显示格式

---

## 📞 获取帮助

- 🐛 **Bug 报告**：https://github.com/Gopherlinzy/claude-code-hooks/issues
- 💬 **讨论**：https://github.com/Gopherlinzy/claude-code-hooks/discussions
- 📖 **文档**：本目录下的各个 .md 文件
- 🎯 **贡献**：欢迎提交 PR，参考 [ADDING_FEATURES.md](./ADDING_FEATURES.md) 的"提交新工具"部分

---

**最后更新**：2026-04-14  
**版本**：2.0 (增强功能版)
