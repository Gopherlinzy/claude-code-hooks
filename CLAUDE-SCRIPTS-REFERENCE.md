# 📚 Claude Code Hooks - 脚本快速参考

> 此文档为 AI 代理（Claude）快速查阅脚本功能时使用。用户安装时可参考此文档的内容。

## 脚本总览

**总脚本数**: 18 个 shell 脚本 + 2 个库 + 1 个助手  
**总代码行数**: 2,812L  
**跨平台**: macOS ✅ | Linux ✅ | Windows Git Bash ✅

---

## 🔴 核心脚本（5个 - 必须安装）

这些脚本通过 Claude Code 的 Hook API 自动触发，无需手动配置（只需合并到 settings.json）。

### 1. `cc-stop-hook.sh` (219L)
**触发**: Stop hook（任务完成时）  
**功能**: 任务完成通知 + 审计日志  

**特性**:
- 🔔 多渠道通知：Feishu、Slack、Telegram、Discord、Bark、WeCom、通用 Webhook
- 📊 JSONL 审计日志（~/.cchooks/logs/hooks-audit.jsonl）
- 🧹 异步触发 reap-orphans 清理
- 🔐 会话去重（TTL 300秒，防重复通知）

**配置**: notify.conf （通知后端和 URL）

**依赖**: send-notification.sh

---

### 2. `cc-safety-gate.sh` (138L)
**触发**: PreToolUse hook（Bash 命令前）  
**功能**: Bash 命令安全门  

**拦截规则** (23+ 种):
- ✋ `rm -rf /` / `rm -rf /*` / `rm -rf .`
- ✋ `sudo` / pipe-to-shell (`| sh` / `| bash`)
- ✋ `eval` / `exec` / `` `backtick` ``
- ✋ `$(...)` 命令替换
- ✋ `dd if=/` / `truncate` / `dd of=/`
- 等等...

**模式**: Fail-safe（故障不阻塞 Claude Code）  
**自定义**: safety-rules.conf

**依赖**: common.sh

---

### 3. `wait-notify.sh` (539L)
**触发**: PermissionRequest + Notification hooks  
**功能**: Claude 等待权限时定时催促  

**特性**:
- ⏰ 定期提醒（默认 30 秒间隔）
- 🧊 冷却期防止轰炸（dedup）
- 🔄 多事件支持（权限请求、一般通知）
- 📊 智能去重

**配置**: CC_WAIT_NOTIFY_SECONDS （环境变量）

**依赖**: send-notification.sh, common.sh

---

### 4. `cancel-wait.sh`
**触发**: PostToolUse + UserPromptSubmit hooks  
**功能**: 用户回应时取消催促  

**特性**:
- 🛑 立即停止定时器
- 📉 递减活动计数器
- 🗑️ 清理临时状态文件

**依赖**: common.sh

---

### 5. `guard-large-files.sh`
**触发**: PreToolUse hook（Read|Edit|Write）  
**功能**: 防读大文件 + 自动生成垃圾代码  

**保护规则**:
- 📏 大文件阈值（默认 >10MB）
- 🗑️ 自动生成代码（bundle.min.js、dist/*、node_modules、etc）
- 📝 生成文件（.map、.min.js、minified CSS）

**配置**: guard-large-files.conf

**依赖**: common.sh

---

## 🟡 扩展脚本（5个 - 可选，需手动启用）

这些脚本需要用户明确选择安装，然后手动注册到 settings.json hooks 中。

### 6. `config-change-guard.sh`
**触发**: ConfigChange hook  
**功能**: 防止 settings.json 被意外修改  

**特性**:
- 🔐 Fail-CLOSED（保守态度）
- 📋 阻止非管理员编辑配置

**启用方式**: 将以下添加到 settings.json:
```json
{
  "hooks": {
    "ConfigChange": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "bash ~/.claude/scripts/claude-hooks/config-change-guard.sh"}]}
    ]
  }
}
```

---

### 7. `mcp-guard.sh` (90L)
**触发**: PreToolUse hook（mcp__* 工具）  
**功能**: 拦截危险 MCP 工具调用  

**特性**:
- 🛡️ 拦截 MCP 写操作
- ✅ 白名单安全操作

**启用方式**: 手动注册到 PreToolUse hooks

---

### 8. `injection-scan.sh`
**触发**: UserPromptSubmit hook  
**功能**: Prompt Injection 模式检测  

**特性**:
- 🔍 基于模式的注入检测
- ⚠️ 可疑语法告警
- 📤 Fail-OPEN（通知但不阻塞）

---

### 9. `project-context-guard.sh` (99L)
**触发**: PreToolUse hook（Write|Edit）  
**功能**: 保护项目根目录关键文件  

**保护的文件**:
- .env, .envlocal, .env.local
- .git, .gitignore
- package.json, requirements.txt
- 其他关键配置

**特性**:
- 🔐 Fail-CLOSED（保守）
- ✅ 白名单异常

---

### 10. `openrouter-cost-summary.sh` (91L)
**触发**: 由 cc-stop-hook 调用  
**功能**: 显示本次 session 的 OpenRouter API 费用  

**特性**:
- 💰 每次任务完成显示成本
- 📊 实时 API 额度追踪
- 📈 成本趋势分析

**依赖**: OpenRouter API（需配置 OPENROUTER_API_KEY）

---

## 🟢 独立工具脚本（5个 - 可选）

手动调用或通过定时任务运行。与 Hook 系统无直接关系。

### 11. `reap-orphans.sh` (78L)
**用途**: 清理孤儿 Claude 进程  
**调用方式**: 
- 定时: `0 2 * * * ~/.claude/scripts/claude-hooks/reap-orphans.sh` (cron)
- 手动: `~/.claude/scripts/claude-hooks/reap-orphans.sh`
- 自动: cc-stop-hook.sh 会异步触发

**功能**:
- 🧟 清理超时进程（>30 分钟）
- 🗑️ 清理过期 worktree（>7 天）
- 🧹 清理过期 .done / .meta 文件

**跨平台**: macOS ✅ | Linux ✅ | Windows Git Bash ✅

**配置**: REAP_TIMEOUT (环境变量，默认 1800s)

**⚠️ 注意**: 需要定时任务配置（见 INSTALL.md）

---

### 12. `dispatch-claude.sh` (323L)
**用途**: 派发隔离的子任务  
**调用方式**: `dispatch-claude.sh [--workdir=...] <command>`

**功能**:
- 📦 创建独立 git worktree
- 🧹 清洁环境（避免变量污染）
- 📊 进度追踪
- 📝 为 reap-orphans 生成 .meta 文件

**示例**:
```bash
dispatch-claude.sh "npm run build"
dispatch-claude.sh --workdir=/tmp/test "python script.py"
```

---

### 13. `check-claude-status.sh` (112L)
**用途**: 查看当前任务状态  
**调用方式**: `check-claude-status.sh [workdir]`

**功能**:
- 🔍 快速检查 PID 和运行时间
- ⏱️ 显示已耗时
- 📋 进程命令检查

---

### 14. `send-notification.sh` (257L)
**用途**: 通用多渠道通知分发器  
**调用方式**: `send-notification.sh <message>`

**支持的后端** (7 种):
- 📱 Feishu (飞书) - NOTIFY_FEISHU_URL
- 💬 Slack - CC_SLACK_WEBHOOK_URL
- 🤖 Telegram - CC_TELEGRAM_BOT_TOKEN + CC_TELEGRAM_CHAT_ID
- 🎮 Discord - CC_DISCORD_WEBHOOK_URL
- 📲 Bark (iOS) - CC_BARK_URL
- 🏢 WeCom (企业微信) - NOTIFY_WECOM_URL
- 🔗 Webhook (通用) - CC_WEBHOOK_URL

**特性**:
- 🔄 自动重试 (3次)
- ⏱️ 超时控制 (8秒)
- 📤 广播模式（发送到所有配置的）
- 🎨 富文本格式支持

**配置**: notify.conf

---

### 15. `generate-skill-index.sh` (103L)
**用途**: 生成 Skill 目录索引  
**调用方式**: `generate-skill-index.sh`

**功能**:
- 🔍 扫描 ~/.cchooks/skills/ 中的 SKILL.md
- 📋 生成 JSON 索引供 Claude 使用
- 🔄 自动重建

**输出**: ~/.cchooks/skills/index.json

---

## ⚙️ 库脚本（2个 - 内部依赖）

所有脚本都依赖这些库。用户无需直接使用。

### `common.sh` (149L)
**功能**: 共享实用函数库

**提供**:
- 📄 JSON 解析（jq + python3 fallback）
- 🔐 安全配置加载（防注入）
- 📊 JSONL 审计日志记录
- ⚠️ 错误处理与上报
- 🔧 环保函数导出

**被以下脚本依赖**: 所有 hook 脚本

---

### `platform-shim.sh` (159L)
**功能**: 跨平台兼容层

**平台检测**:
- 🍎 macOS (Darwin)
- 🐧 Linux
- 🪟 WSL2
- 🪟 Windows Git Bash (MSYS2/MINGW)

**提供函数** (23 个):
- `_ps_command_of` - 获取进程命令
- `_kill_check` - 进程存在检查
- `_find_mtime` - 文件修改时间查询
- `_stat_mtime` - stat 兼容层
- `_env_clean` - 清洁环境执行
- `_nohup_bg` - 后台运行
- 等等...

**被依赖**: common.sh 中

---

## 📋 辅助脚本（1个）

### `setup-statusline.sh` (182L)
**功能**: statusline 集成配置助手  
**调用方式**: `~/.claude/scripts/claude-hooks/setup-statusline.sh`

**功能**:
- 🔌 自动安装 claude-hud 插件
- ⚙️ 配置 OpenRouter 实时额度显示
- 🔧 应用必要的代码补丁
- 🌍 跨平台支持

---

## 🎯 快速参考 - 按场景

### "我想要基础保护"
✅ 安装: **核心脚本 (5个)** + settings.json 合并  
⏱️ 时间: 5 分钟  
📊 覆盖:
- 🔔 任务完成通知
- 🛡️ Bash 命令安全门
- ⏰ 权限请求催促
- 📏 大文件保护

### "我想要完整安全"
✅ 安装: **核心脚本 (5个)** + **所有扩展脚本 (5个)**  
⏱️ 时间: 10 分钟  
📊 覆盖: 基础保护 + 配置保护 + MCP 安全 + Prompt 注入检测 + 项目文件保护

### "我想要任务管理"
✅ 安装: **核心脚本** + `dispatch-claude.sh` + `check-claude-status.sh`  
⏱️ 时间: 8 分钟  
📊 覆盖: 隔离子任务 + 进程清理 + 状态查询

### "我想要完整体验"
✅ 安装: **所有脚本** (包括 statusline)  
⏱️ 时间: 15 分钟  
📊 覆盖: 全部功能

---

## 📊 脚本依赖关系

```
common.sh (all hooks depend on this)
├── platform-shim.sh (cross-platform compat)
└── Global exports for all hooks

send-notification.sh (通知库)
├── cc-stop-hook.sh (发送完成通知)
├── wait-notify.sh (发送权限催促)
└── dispatch-claude.sh (进度通知)

Hook 系统自动加载:
├── Stop hook → cc-stop-hook.sh
├── PreToolUse(Bash) → cc-safety-gate.sh
├── PreToolUse(Read|Edit|Write) → guard-large-files.sh
├── PermissionRequest+Notification → wait-notify.sh
└── PostToolUse+UserPromptSubmit → cancel-wait.sh

独立运行:
├── reap-orphans.sh (定时/后台)
├── dispatch-claude.sh (手动)
├── check-claude-status.sh (手动)
└── generate-skill-index.sh (定时/手动)
```

---

## 🛠️ 安装遵循

1. **核心脚本** → 自动注册到 settings.json
2. **扩展脚本** → 用户选择启用
3. **工具脚本** → 自动复制（手动调用或配置定时）
4. **库脚本** → 自动复制（被其他脚本依赖）

---

## 🔍 快速查找

### 按功能查找

| 需求 | 脚本 |
|------|------|
| 任务完成通知 | cc-stop-hook.sh |
| 防止危险命令 | cc-safety-gate.sh |
| 权限请求催促 | wait-notify.sh |
| 大文件防护 | guard-large-files.sh |
| MCP 工具安全 | mcp-guard.sh ⭐ |
| 配置保护 | config-change-guard.sh ⭐ |
| Prompt 注入检测 | injection-scan.sh ⭐ |
| 项目文件保护 | project-context-guard.sh ⭐ |
| 费用追踪 | openrouter-cost-summary.sh ⭐ |
| 进程清理 | reap-orphans.sh |
| 隔离任务 | dispatch-claude.sh |
| 任务状态 | check-claude-status.sh |
| 多渠道通知 | send-notification.sh |
| Skill 索引 | generate-skill-index.sh |

⭐ = 可选扩展

### 按触发方式查找

| 触发方式 | 脚本 |
|---------|------|
| Hook (自动) | cc-stop-hook.sh, cc-safety-gate.sh, wait-notify.sh, cancel-wait.sh, guard-large-files.sh |
| Hook (可选) | config-change-guard.sh, mcp-guard.sh, injection-scan.sh, project-context-guard.sh |
| 被调用 | cc-stop-hook.sh → send-notification.sh + openrouter-cost-summary.sh + reap-orphans.sh |
| 手动 | dispatch-claude.sh, check-claude-status.sh, setup-statusline.sh, generate-skill-index.sh |
| 定时 | reap-orphans.sh, generate-skill-index.sh |

---

## 版本信息

- **项目**: claude-code-hooks
- **版本**: 3.0.0+
- **总脚本**: 18 个 shell + 2 个库 + 1 个助手
- **总代码**: 2,812L
- **跨平台**: macOS | Linux | Windows Git Bash
- **最后更新**: 2026-04-16
