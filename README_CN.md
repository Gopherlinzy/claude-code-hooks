# Claude Code Hooks — 任务生命周期与安全管理工具集

一套生产级 Claude Code 钩子（Hooks），将 Claude Code 从裸 CLI 升级为可管理、可观测、安全的开发环境。

## 解决什么问题

使用 Claude Code 执行长时间任务时，你会遇到这些痛点：
1. **静默完成** — 任务结束了但你不知道，除非一直盯着终端
2. **权限卡死** — Claude 请求权限，你离开了，它就一直等
3. **危险命令** — 没有防护栏阻止 `rm -rf /` 或写入受保护文件
4. **大文件浪费** — Claude 读取上万行自动生成文件，浪费上下文窗口
5. **孤儿进程** — 异步任务挂死无人清理
6. **进度黑盒** — 无法在执行中途查看任务状态

## 包含的 Hooks

| 脚本 | 触发事件 | 功能 |
|------|---------|------|
| `notify-openclaw.sh` | Stop | 任务完成通知 + 审计日志 + .done 文件 |
| `wait-notify.sh` | PermissionRequest / Notification | 等待超时提醒（默认 30 秒） |
| `cancel-wait.sh` | PostToolUse / UserPromptSubmit | 取消等待超时计时器 |
| `cc-safety-gate.sh` | PreToolUse (Bash) | 危险命令拦截（黑名单 + 路径保护） |
| `guard-large-files.sh` | PreToolUse (Read/Edit/Write) | 自动生成文件 + 噪音目录 + 超大文件拦截 |
| `dispatch-claude.sh` | — | 任务派发封装（同步/异步 + 进度追踪 + 环境隔离） |
| `check-claude-status.sh` | — | 任务状态查询 |
| `reap-orphans.sh` | — | 孤儿进程清理 |
| `generate-skill-index.sh` | — | Skills 索引生成器 |

## 快速开始

### 1. 安装脚本

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.openclaw/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.openclaw/scripts/claude-hooks/
chmod +x ~/.openclaw/scripts/claude-hooks/*.sh
```

### 2. 配置通知目标

```bash
# 创建 notify.conf（CC Hook 子进程不会继承 ~/.zshrc 的环境变量！）
cat > ~/.openclaw/scripts/claude-hooks/notify.conf << 'EOF'
CC_NOTIFY_TARGET="你的飞书_open_id"
CC_WAIT_NOTIFY_SECONDS=30
CC_NOTIFY_CHANNEL="feishu"
EOF
chmod 600 ~/.openclaw/scripts/claude-hooks/notify.conf
```

### 3. 注册到 `~/.claude/settings.json`

完整配置见 [README.md](README.md#3-register-hooks-in-claudesettingsjson)。

### 4. 重启 Claude Code

新钩子在启动新的 `claude` 会话时生效，已有会话不受影响。

## 配置项

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CC_NOTIFY_TARGET` | 通知目标（飞书 open_id / chat_id 等） | _(必填)_ |
| `CC_WAIT_NOTIFY_SECONDS` | 等待超时秒数 | `30` |
| `CC_NOTIFY_CHANNEL` | 通知渠道（feishu / telegram / slack 等） | `feishu` |
| `REAP_TIMEOUT` | 孤儿进程超时秒数 | `1800` |

## 架构图

```
Claude Code 会话
  │
  ├── PreToolUse ─────┬── cc-safety-gate.sh（拦截危险 Bash 命令）
  │                   └── guard-large-files.sh（拦截大文件/噪音）
  │
  ├── PermissionRequest ── wait-notify.sh → [30s 定时器] → 飞书通知
  │
  ├── PostToolUse ──────── cancel-wait.sh → [取消定时器]
  │
  ├── UserPromptSubmit ─── cancel-wait.sh → [取消定时器]
  │
  └── Stop ─────────────── notify-openclaw.sh → .done 文件 + 通知
```

## 通知后端

所有 Hook 使用**通用通知分发器**（`send-notification.sh`），内置支持 7 种后端，**无需安装 OpenClaw**：

| 后端 | 配置变量 | 说明 |
|------|---------|------|
| Auto | `CC_NOTIFY_BACKEND=auto` | 自动检测第一个可用后端 |
| OpenClaw | `CC_NOTIFY_TARGET` | 飞书 / Telegram / 任意 OpenClaw 渠道 |
| Slack | `CC_SLACK_WEBHOOK_URL` | Slack Incoming Webhook |
| Telegram | `CC_TELEGRAM_BOT_TOKEN` | Telegram Bot API |
| Discord | `CC_DISCORD_WEBHOOK_URL` | Discord Webhook |
| Bark | `CC_BARK_URL` | iOS 推送 ([Bark](https://github.com/Finb/Bark)) |
| Webhook | `CC_WEBHOOK_URL` | 任意 HTTP 端点（可自定义方法/请求体） |
| Command | `CC_NOTIFY_COMMAND` | 任意命令行工具 |

默认 `auto` 模式自动检测。详见 `scripts/notify.conf.example`。

## 依赖

- `bash` 4+
- `jq`（JSON 解析，缺失时优雅降级）
- `python3`（JSON 编码 + 通知后端）
- `curl`（Slack/Telegram/Discord/Bark/Webhook 通知）
- Claude Code CLI (`claude`)
- `openclaw` CLI（可选 — 仅使用 openclaw 通知后端时需要）

## 许可证

MIT
