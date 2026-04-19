# 🦞 Claude Code Hooks — 项目架构与开发指南

> 本文档面向开发者和 Claude Code Agent。项目概述、安装指引请见 [README.md](README.md)。

## 项目概述

**Claude Code Hooks** 是一套 Claude Code [Hook API](https://docs.anthropic.com/en/docs/claude-code/hooks) 安全防护和通知脚本集合，提供：

- 🔔 **跨渠道任务通知**（飞书、Slack、Telegram 等）
- 🛡️ **Bash 安全门**（拦截 `rm -rf /`、`sudo` 等危险命令）
- ⏰ **权限等待催促**（Claude 等待权限时定时提醒）
- 📏 **大文件保护**（防止意外读取 node_modules、bundle.min.js）
- 💡 **扩展防护**（prompt injection 检测、配置文件保护、MCP 防护）
- 📊 **OpenRouter 金额监控**（集成 claude-hud 状态栏实时显示 API 余额）

**语言**: Bash (POSIX + GNU 兼容)  
**跨平台**: macOS ✅ | Linux ✅ | Windows Git Bash ✅  
**版本**: 1.0.1

---

## 目录结构

```
claude-code-hooks/
├── CLAUDE.md                          # 本文件 — 项目架构和开发指南
├── CLAUDE-SCRIPTS-REFERENCE.md        # 脚本功能快速参考
├── README.md                          # 用户文档（英文）
├── INSTALL.md                         # 详细安装指引
├── CHANGELOG.md                       # 变更记录
│
├── scripts/                           # 核心脚本（18 个）
│   ├── 【核心脚本 - 自动触发】
│   ├── cc-stop-hook.sh               # Stop hook — 任务完成通知 + 审计日志
│   ├── cc-safety-gate.sh             # PreToolUse hook (Bash) — 安全门（拦截危险命令）
│   ├── wait-notify.sh                # PermissionRequest/Notification — 权限等待催促
│   ├── cancel-wait.sh                # PostToolUse/UserPromptSubmit — 取消催促
│   ├── guard-large-files.sh          # PreToolUse hook (Read/Edit/Write) — 大文件保护
│   │
│   ├── 【扩展脚本 - 可选启用】
│   ├── config-change-guard.sh        # ConfigChange hook — 防 settings.json 修改
│   ├── mcp-guard.sh                  # PreToolUse hook (MCP) — MCP 工具防护
│   ├── injection-scan.sh             # UserPromptSubmit hook — Prompt Injection 检测
│   ├── project-context-guard.sh      # PreToolUse hook (Write/Edit) — 关键文件保护
│   │
│   ├── 【工具脚本 - 手动触发】
│   ├── send-notification.sh          # 底层：跨渠道通知发送
│   ├── common.sh                     # 底层：通用函数库
│   ├── platform-shim.sh              # 工具：平台兼容性垫片
│   ├── dispatch-claude.sh            # 工具：spawn 隔离子任务（git worktree）
│   ├── check-claude-status.sh        # 工具：查看任务状态
│   ├── reap-orphans.sh               # 工具：清理孤立进程（需 cron 配置）
│   ├── generate-skill-index.sh       # 工具：生成 Skill 索引
│   ├── openrouter-cost-summary.sh    # 工具：显示 API 成本统计
│   ├── setup-statusline.sh           # 工具：配置 OpenRouter 状态栏监控
│   │
│   ├── 【示例配置】
│   ├── notify.conf.example           # 通知后端配置示例
│   └── safety-rules.conf.example     # 安全规则自定义示例
│
├── tools/                             # 辅助工具
│   ├── merge-hooks.js                # 工具：深度合并 JSON hooks 到 settings.json
│   ├── select-modules.js             # 工具：交互式模块选择
│   ├── diagnose-windows.sh           # 工具：Windows 诊断助手
│   └── statusline/                   # OpenRouter 状态栏集成
│       ├── openrouter-statusline.js  # 实时余额查询逻辑
│       └── run-hud.sh                # 跨平台包装脚本
│
├── tests/                             # BATS 单元测试
│   ├── common-functions.bats         # common.sh 函数测试
│   ├── safety-gate.bats              # cc-safety-gate.sh 规则测试
│   ├── guard-large-files.bats        # guard-large-files.sh 测试
│   ├── send-notification-feishu.bats # Feishu 通知测试
│   ├── notifications-broadcast.bats  # 多渠道通知测试
│   ├── feishu-signature.bats         # Feishu 签名验证测试
│   ├── reap-orphans.bats             # 进程清理测试
│   ├── source-integrity.bats         # 脚本加载完整性测试
│   ├── safe-source-conf.bats         # 配置文件安全加载测试
│   ├── p0-4-feishu-fix.bats          # P0 Bug 兼容性测试
│   ├── p0-5-notification-works.bats  # P0 通知完整性测试
│   └── integration.bats              # 集成测试
│
├── docs/                              # 文档
│   ├── TROUBLESHOOTING.md            # 常见问题和排查指南
│   └── http-hooks.md                 # HTTP Webhook 配置说明
│
├── install-interactive.sh            # 交互式安装程序
├── install.sh                        # 传统一键安装脚本
├── .gitignore                        # Git 忽略规则
├── LICENSE                           # MIT License
└── README_CN.md                      # 已废弃（迁移到 README.md 英文版本）
```

---

## 脚本分层架构

### 第 1 层：基础库

```bash
common.sh              # 通用函数 — 日志、路径、事件 ID、通知队列等
platform-shim.sh       # 平台兼容性 — macOS/Linux 命令差异处理
```

### 第 2 层：通知系统

```bash
send-notification.sh   # 核心通知发送器 — Feishu / Slack / Telegram / Discord / Bark / WeCom
└─ 支持渠道：
   ├── Feishu (飞书) + 签名验证
   ├── Slack
   ├── Telegram
   ├── Discord
   ├── Bark (iOS)
   ├── WeCom (企业微信)
   └── 通用 Webhook (curl)
```

### 第 3 层：Hook 脚本（自动触发）

| Hook | 触发条件 | 脚本 | 作用 |
|------|----------|------|------|
| **Stop** | 任务完成 | `cc-stop-hook.sh` | 通知 + 审计日志 + 清理孤立进程 |
| **PreToolUse (Bash)** | 运行 Bash 前 | `cc-safety-gate.sh` | 拦截危险命令模式 |
| **PreToolUse (Read/Edit/Write)** | 文件操作前 | `guard-large-files.sh` | 防读大文件 + 自动排除垃圾代码目录 |
| **PreToolUse (MCP)** | MCP 调用前 | `mcp-guard.sh` | MCP 工具防护（可选） |
| **PreToolUse (Write/Edit)** | 写文件前 | `project-context-guard.sh` | 保护 .env/.git 等关键文件（可选） |
| **PermissionRequest** | 权限请求时 | `wait-notify.sh` | 定时催促 Claude 用户批准 |
| **Notification** | 系统通知时 | `wait-notify.sh` | 定时催促 Claude 用户响应 |
| **PostToolUse** | 工具执行后 | `cancel-wait.sh` | 取消进行中的催促 |
| **UserPromptSubmit** | 用户输入时 | `cancel-wait.sh` | 取消进行中的催促 |
|  |  | `injection-scan.sh` | Prompt Injection 检测（可选） |
| **ConfigChange** | 配置变更时 | `config-change-guard.sh` | 防 settings.json 被修改（可选） |

### 第 4 层：工具脚本（手动触发）

```bash
dispatch-claude.sh          # spawn 隔离 Claude 子任务（git worktree）
check-claude-status.sh      # 查询当前任务状态
reap-orphans.sh             # 清理孤立进程（需 cron）
generate-skill-index.sh     # 生成 Skill 索引
openrouter-cost-summary.sh  # API 成本统计
setup-statusline.sh         # 配置 OpenRouter 状态栏
```

### 第 5 层：状态栏集成

```bash
tools/statusline/
├── openrouter-statusline.js  # 实时 API 余额查询
└── run-hud.sh               # 跨平台包装脚本
```

---

## 关键特性详解

### 1. 多渠道通知系统

**send-notification.sh** 是核心的通知分发器，支持：

| 渠道 | 环境变量 | 配置文件 | 说明 |
|------|----------|----------|------|
| Feishu | `NOTIFY_FEISHU_URL` | `notify.conf` | 支持消息加密签名 |
| Slack | `CC_SLACK_WEBHOOK_URL` | `notify.conf` | Block 格式富文本 |
| Telegram | `CC_TELEGRAM_BOT_TOKEN` + `CC_TELEGRAM_CHAT_ID` | `notify.conf` | Markdown 支持 |
| Discord | `CC_DISCORD_WEBHOOK_URL` | `notify.conf` | Embeds 格式 |
| Bark | `CC_BARK_URL` | `notify.conf` | iOS 推送 |
| WeCom | `NOTIFY_WECOM_URL` | `notify.conf` | 企业微信 Markdown |
| 通用 Webhook | 任意 URL + Bearer token | `notify.conf` | 自定义 JSON payload |

**配置位置**:
```bash
~/.claude/scripts/claude-hooks/notify.conf       # 公开配置
~/.cchooks/secrets.env                          # 敏感信息（chmod 600）
```

### 2. Bash 安全门（23+ 规则）

**cc-safety-gate.sh** 在 Bash 执行前进行模式匹配，拦截：

```bash
rm -rf /        # 根目录删除
sudo ...        # 权限提升
eval / exec     # 代码注入
$(...)          # 命令替换
| sh / | bash   # 管道到 shell
dd if=/ / dd of=/   # 磁盘操作
truncate        # 文件截断
```

**自定义规则**:
```bash
~/.claude/scripts/claude-hooks/safety-rules.conf
```

**Fail-safe 模式**: 规则加载失败时不阻塞 Claude Code（日志记录）。

### 3. 权限等待催促

**wait-notify.sh** 实现：
- 定期提醒（默认 30 秒）
- 智能去重（防止轰炸）
- 多事件支持（权限请求、系统通知）
- 活跃计数跟踪

**取消机制**:
- **cancel-wait.sh** 在 PostToolUse 或 UserPromptSubmit 时立即停止催促

### 4. 大文件保护

**guard-large-files.sh** 防护两个维度：

1. **文件大小**: 超过阈值（默认 10MB）自动拒绝
2. **路径模式**: 自动排除垃圾代码目录
   ```bash
   node_modules/*, dist/*, build/*, .bundle, *.min.js, *.map
   ```

### 5. 审计日志

**cc-stop-hook.sh** 在 `~/.cchooks/logs/hooks-audit.jsonl` 记录：

```json
{
  "timestamp": "2026-04-19T13:26:00+08:00",
  "event": "task_complete",
  "session_id": "abc123",
  "duration": 127,
  "command": "[REDACTED - 200 chars max]",
  "exit_code": 0
}
```

**敏感信息脱敏**: Bearer token、API key、密码自动隐藏（基于模式）。

---

## 开发指南

### 环境配置

```bash
NODE_VERSION=v24.14.0          # 脚本测试环境
SHELL=$(which bash)             # POSIX Bash（非 sh）
OS=darwin|linux|mingw          # 平台检测
```

### 代码约定

#### 文件头

```bash
#!/bin/bash

# 脚本名称和简要功能说明（一行）
# 触发条件、依赖关系

set -euo pipefail  # 严格模式
```

#### 通用函数从 common.sh 导入

```bash
# 不要重复 load，脚本接收方已 source
source "$(dirname "$0")/common.sh"

# 使用：
log_info "Message"
log_error "Error"
get_event_id "event_name"
```

#### 配置文件安全加载

```bash
# ✅ 正确：在 common.sh 中通过 safer_source 加载
safer_source "${CONF_FILE}" "safe-rules"

# ❌ 错误：直接 source（存在注入风险）
source "${CONF_FILE}"
```

#### 命令及参数传递

```bash
# ✅ 使用临时脚本文件
cat > "$_TMP_SCRIPT" << EOF
$(escape_quoted_arg "$_ASYNC_SKILL_ARG")
EOF
bash "$_TMP_SCRIPT"

# ❌ 避免：命令行字符串拼接
bash -c "${CMD} ${ARG}"  # ARG 可能包含特殊字符
```

### 测试框架

使用 **BATS** (Bash Automated Testing System)。

#### 运行全部测试

```bash
cd tests
bats *.bats
```

#### 运行单个测试文件

```bash
bats tests/safety-gate.bats
```

#### 编写新测试

```bash
@test "describe what this tests" {
  # Arrange
  expected="value"
  
  # Act
  result=$(bash scripts/foo.sh --arg "$expected")
  
  # Assert
  [ "$result" = "$expected" ]
}
```

### 脚本间依赖关系

```
common.sh
  ↓
send-notification.sh
  ↓
cc-stop-hook.sh ← 同时调用 reap-orphans.sh
wait-notify.sh → cancel-wait.sh

cc-safety-gate.sh (standalone)
guard-large-files.sh (standalone)
config-change-guard.sh (standalone)
mcp-guard.sh (standalone)
injection-scan.sh (standalone)
project-context-guard.sh (standalone)

tools/*sh (工具脚本，相对独立)
```

### 常见问题排查

详见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

常见问题：
- Windows Git Bash 路径转换
- Feishu 加密签名验证失败
- 孤立进程清理不生效
- 权限催促轰炸用户
- 大文件阈值误报

---

## 发版流程

### 语义版本

遵循 [Semantic Versioning](https://semver.org)：
- **Major**: Hook API 变更 / 序列化格式变更
- **Minor**: 新脚本 / 新功能（向后兼容）
- **Patch**: Bug 修复 / 文档改进

### 变更记录

在 [CHANGELOG.md](CHANGELOG.md) 中记录所有 PR：

```markdown
## [1.0.2] - 2026-04-20

### Fixed
- P0: reap-orphans orphan detection accuracy
- Command sanitization for sensitive patterns

### Added
- New dispatch-claude.sh --safe mode
- OpenRouter statusline caching

### Deprecated
- README_CN.md → Use README.md English version
```

### 安全发布清单

- [ ] 所有测试通过 (`bats tests/*.bats`)
- [ ] CHANGELOG.md 已更新
- [ ] 敏感信息脱敏测试通过
- [ ] 跨平台测试（macOS / Linux / Windows Git Bash）
- [ ] 文档 README.md 同步

---

## 安装与配置

### 快速开始

**推荐方案**：交互式安装
```bash
bash install-interactive.sh
```

**传统方案**：详见 [INSTALL.md](INSTALL.md)

### 配置路径

| 配置 | 位置 | 权限 | 用途 |
|------|------|------|------|
| 公开配置 | `~/.claude/scripts/claude-hooks/notify.conf` | 644 | 通知渠道、超时 |
| 敏感信息 | `~/.cchooks/secrets.env` | 600 | Webhook URL、Token |
| 安全规则 | `~/.claude/scripts/claude-hooks/safety-rules.conf` | 644 | 自定义命令规则 |
| 审计日志 | `~/.cchooks/logs/hooks-audit.jsonl` | 600 | 读写事件日志 |
| 临时状态 | `$TMPDIR/cc-wait-*.tmp` | 600 | 催促计数器（自清理） |

---

## Known Issues & TODOs

### P0（严重 / 安全）

- [ ] dispatch-claude.sh 异步模式参数注入（需改进）
- [ ] dispatch-claude.sh ANTHROPIC_API_KEY 环境泄露（需 unset）

### P1（中等）

- [ ] reap-orphans 需要 cron 配置（文档标注）
- [ ] Windows Git Bash 路径转换边界情况

### P2（低优先级 / 增强）

- [ ] MCP 工具白名单可配置化
- [ ] Injection 检测规则库可扩展

---

## 参考资源

- **Claude Code Hook 文档**: https://docs.anthropic.com/en/docs/claude-code/hooks
- **Feishu Bot 开发**: https://open.feishu.cn/document/common-capabilities/bot-ability
- **BATS 测试框架**: https://github.com/bats-core/bats-core
- **脚本快速参考**: [CLAUDE-SCRIPTS-REFERENCE.md](CLAUDE-SCRIPTS-REFERENCE.md)
- **故障排查**: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- **Webhook 配置**: [docs/http-hooks.md](docs/http-hooks.md)

---

最后更新：2026-04-19 | 版本：1.0.1
