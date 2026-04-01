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
| `cc-stop-hook.sh` | Stop | 任务完成通知 + 审计日志 + .done 文件 |
| `wait-notify.sh` | PermissionRequest / Notification | 等待超时提醒（默认 30 秒） |
| `cancel-wait.sh` | PostToolUse / UserPromptSubmit | 取消等待超时计时器（含 5 秒防误杀） |
| `cc-safety-gate.sh` | PreToolUse (Bash) | 危险命令拦截（黑名单 + 路径保护） |
| `guard-large-files.sh` | PreToolUse (Read/Edit/Write) | 自动生成文件 + 噪音目录 + 超大文件拦截 |
| `dispatch-claude.sh` | — | 任务派发封装（同步/异步 + 进度追踪 + Worktree 隔离） |
| `check-claude-status.sh` | — | 任务状态查询 |
| `reap-orphans.sh` | — | 孤儿进程清理 |
| `generate-skill-index.sh` | — | Skills 索引生成器 |

## 快速开始

### 方式 A：一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
```

自动完成：① 克隆并复制脚本 ② 交互式配置通知渠道/目标 ③ 输出 settings.json 配置片段

### 方式 B：手动安装

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
```

配置通知后端：
```bash
cat > ~/.claude/scripts/claude-hooks/notify.conf << 'EOF'
# auto = 发现所有已配置后端，同时广播
CC_NOTIFY_BACKEND=auto
CC_WAIT_NOTIFY_SECONDS=30

# 飞书：
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN

# Slack：
# CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
EOF
chmod 600 ~/.claude/scripts/claude-hooks/notify.conf
```

注册到 `~/.claude/settings.json`：完整配置见 [README.md](README.md#2-register-hooks-in-claudesettingsjson)。

> **注意**：所有 matcher 使用 `"*"`（匹配所有）。避免使用空字符串 `""`，其行为未定义，可能导致 hook 不触发。

### 🪟 Windows 用户

Windows 用户有两个选择：**WSL2**（完整功能）或 **Git Bash**（仅 hooks，有限制）。

#### 方案 A：WSL2（推荐 — 完整功能）

```powershell
# PowerShell（管理员）— 安装 WSL2
wsl --install -d Ubuntu
```

```bash
# 在 WSL2 Ubuntu 内：
sudo apt-get install -y nodejs jq python3 curl openssl
npm install -g @anthropic-ai/claude-code
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
echo 'NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN' >> ~/.claude/scripts/claude-hooks/notify.conf
~/.claude/scripts/claude-hooks/send-notification.sh "Hello from WSL2!"
```

#### 方案 B：Git Bash（仅 Hooks — 无需 jq）

> **v1.3.1 起**，所有 hook 脚本内置了 `jq` 和 `python3` 的 Python 兼容层。如果你已经在 Git Bash 下运行 Claude Code，hooks 无需额外安装依赖即可工作。

**前置条件：**
- [Git for Windows](https://gitforwindows.org/)（含 Git Bash）
- [Python 3.6+](https://www.python.org/downloads/)（安装时勾选"Add to PATH"）
- Claude Code CLI 已在 Git Bash 下可用

**安装：**
```bash
# 在 Git Bash 中：
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
```

**配置通知：**
```bash
cat > ~/.claude/scripts/claude-hooks/notify.conf << 'EOF'
CC_NOTIFY_BACKEND=auto
CC_WAIT_NOTIFY_SECONDS=30
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
EOF
```

**注册 hooks（`~/.claude/settings.json`）：**

> ⚠️ **Windows 路径格式**：使用 `bash /c/Users/用户名/...` 正斜杠格式（Git Bash 风格），将 `用户名` 替换为你的 Windows 用户名。

完整 settings.json 配置见 [README.md（英文版 Git Bash 段落）](README.md#option-b-git-bash-hooks-only--no-jq-required)。

**测试：**
```bash
~/.claude/scripts/claude-hooks/send-notification.sh "Hello from Git Bash!"
```

**Git Bash 已知限制：**
- `jq` 不包含在 Git Bash 中 — 所有脚本自动回退到 Python 解析 JSON
- `python3` 命令可能不存在 — 脚本自动检测并使用 `python`
- `/tmp/` 路径映射与原生 Windows 进程不同 — 多会话场景下后台定时器可能不稳定
- 任务派发（`dispatch-claude.sh`）和孤儿清理（`reap-orphans.sh`）建议在 WSL2 下使用

> **总结**：Git Bash 适合**通知**（任务完成、飞书/Slack/Telegram 提醒）和**安全门**（危险命令拦截）。完整任务生命周期管理请用 WSL2。

## 架构图

```
Claude Code 会话
  │
  ├── PreToolUse ─────┬── cc-safety-gate.sh（拦截危险 Bash 命令）
  │                   └── guard-large-files.sh（拦截大文件/噪音）
  │
  ├── PermissionRequest ── wait-notify.sh → [30s 定时器] → 通知
  │
  ├── Notification ─────── wait-notify.sh → [30s 定时器] → 通知
  │
  ├── PostToolUse ──────── cancel-wait.sh → [取消定时器]
  │
  ├── UserPromptSubmit ─── cancel-wait.sh → [取消定时器]
  │
  └── Stop ─────────────── cc-stop-hook.sh → .done 文件 + 通知
```

## 通知后端

所有 Hook 使用**通用通知分发器**（`send-notification.sh`），内置支持 **9 种后端**，**同时广播到所有已配置渠道**：

| 后端 | 配置变量 | 说明 |
|------|---------|------|
| Auto | `CC_NOTIFY_BACKEND=auto` | 发现所有已配置后端，同时广播 |
| OpenClaw | `CC_NOTIFY_TARGET` | 飞书 / Telegram / 任意 OpenClaw 渠道 |
| 飞书 | `NOTIFY_FEISHU_URL` | 飞书自定义机器人 webhook（支持签名） |
| 企业微信 | `NOTIFY_WECOM_URL` | 企微群机器人 webhook |
| Slack | `CC_SLACK_WEBHOOK_URL` | Slack Incoming Webhook |
| Telegram | `CC_TELEGRAM_BOT_TOKEN` | Telegram Bot API |
| Discord | `CC_DISCORD_WEBHOOK_URL` | Discord Webhook |
| Bark | `CC_BARK_URL` | iOS 推送 ([Bark](https://github.com/Finb/Bark)) |
| Webhook | `CC_WEBHOOK_URL` | 任意 HTTP 端点 |
| Command | `CC_NOTIFY_COMMAND` | 任意命令行工具 |

### 广播模式 (v1.3.0+)

默认 `auto` 模式会**发现所有已配置后端**，然后**同时广播到每一个**。各后端独立执行 — 一个失败不影响其他。

```bash
# 示例：同时推送到飞书和 Bark
CC_NOTIFY_BACKEND=auto
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
CC_BARK_URL=https://api.day.app/YOUR_KEY
# → 飞书和 Bark 同时收到每条通知
```

也支持显式指定：
```bash
# 显式列表
CC_NOTIFY_BACKEND=feishu,bark

# 单后端（向后兼容）
CC_NOTIFY_BACKEND=feishu
```

## 配置项

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CC_NOTIFY_BACKEND` | 后端选择（auto / 逗号列表 / 单个） | `auto` |
| `CC_WAIT_NOTIFY_SECONDS` | 等待超时秒数 | `30` |
| `CC_GATEWAY_PORT` | OpenClaw 网关端口（未设置则跳过） | _(未设置)_ |
| `REAP_TIMEOUT` | 孤儿进程超时秒数 | `1800` |

## 依赖

| 依赖 | 版本 | 用途 |
|-----|------|------|
| `bash` | 4.0+ | 所有 hook 脚本（macOS 需 `brew install bash`） |
| `curl` | 任意 | 通知投递 |
| `python3` | 3.6+ | JSON 编码 |
| `jq` | 推荐 | JSON 解析（缺失时优雅降级） |

## 更新日志

### v1.3.1 (2026-04-01)

**🪟 Windows Git Bash 兼容性**

- **Python3 兼容层**：9 个 hook 脚本自动检测 `python`（当 `python3` 不存在时）
- **jq 兼容层**：5 个依赖 jq 的脚本现在在 jq 不可用时自动回退到 Python 解析 JSON
- **install.sh 修复**：matcher `""` → `"*"`（空字符串导致 hooks 静默不触发）
- **安全门正则修复**：`curl.*|.*sh` 误杀合法命令 → 使用 POSIX `[[:space:]]` 兼容 macOS
- **.gitattributes**：强制 `*.sh` 使用 LF 换行（防止 Windows 下 CRLF 报错）
- **README**：新增 Windows Git Bash 安装指南

### v1.3.0 (2026-03-31)

**📡 广播模式 — 多渠道同时通知**

- **`send-notification.sh` v2**：重写后端选择逻辑
  - `auto` 模式发现**所有**已配置后端并同时广播
  - 各后端独立执行，一个失败不阻塞其他
  - 支持逗号分隔显式列表：`CC_NOTIFY_BACKEND=feishu,slack,bark`
  - 所有后端函数现在返回正确的退出码
- **`cancel-wait.sh`**：新增 5 秒防误杀保护
- **`wait-notify.sh`**：移除硬编码 `exit 0`，Notification hook 现在正常工作
- **`settings.json` 修复**：
  - Stop hook 正确注册 `cc-stop-hook.sh`
  - Notification matcher `""` → `"*"`
  - 移除所有无效 SUPERSET 命令（5 处）
  - 移除 `/tmp` 调试脚本引用（安全风险）

### v1.2.0 (2026-03-31)

**🌍 飞书 & 企微 Webhook + 完全脱离 OpenClaw 依赖**

### v1.1.0 (2026-03-30)

**🛡️ Git Worktree 隔离（P0 安全加固）**

### v1.0.0 (2026-03-29)

初始发布。

## 许可证

MIT
