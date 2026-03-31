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
| `cancel-wait.sh` | PostToolUse / UserPromptSubmit | 取消等待超时计时器 |
| `cc-safety-gate.sh` | PreToolUse (Bash) | 危险命令拦截（黑名单 + 路径保护） |
| `guard-large-files.sh` | PreToolUse (Read/Edit/Write) | 自动生成文件 + 噪音目录 + 超大文件拦截 |
| `dispatch-claude.sh` | — | 任务派发封装（同步/异步 + 进度追踪 + 环境隔离 + 🆕 Worktree 隔离） |
| `check-claude-status.sh` | — | 任务状态查询 |
| `reap-orphans.sh` | — | 孤儿进程清理 |
| `generate-skill-index.sh` | — | Skills 索引生成器 |

## 快速开始

### 方式 A：一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
```

自动完成：① 克隆并复制脚本 ② 交互式配置通知渠道/目标 ③ 输出 settings.json 配置片段

非交互模式（CI/自动化）：
```bash
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash -s -- --non-interactive
```

### 方式 B：手动安装

#### 1. 安装脚本

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks && ./install.sh
```

或手动操作：```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
```

#### 2. 配置通知目标

```bash
# 创建 notify.conf（CC Hook 子进程不会继承 ~/.zshrc 的环境变量！）
cat > ~/.claude/scripts/claude-hooks/notify.conf << 'EOF'
CC_NOTIFY_TARGET="你的飞书_open_id"
CC_WAIT_NOTIFY_SECONDS=30
CC_NOTIFY_CHANNEL="feishu"
EOF
chmod 600 ~/.claude/scripts/claude-hooks/notify.conf
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
| `CC_GATEWAY_PORT` | OpenClaw 网关端口（未设置则跳过唤醒） | _(未设置)_ |
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
  └── Stop ─────────────── cc-stop-hook.sh → .done 文件 + 通知
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

## Phase 1 加固 (v1.1)

所有 Hook 经过以下加固改进：

### 显式 Fail-Open 声明
每个 Hook 顶部声明 `# FAIL_MODE=open` — 如果 Hook 自身崩溃，静默放行而非阻塞 Claude Code。错误不再被 `|| true` 无记录地吞掉。

### JSONL 结构化审计日志
所有 Hook 现在将审计事件写入 `~/.claude/scripts/claude-hooks/logs/hooks-audit.jsonl`：
```json
{"ts":"2026-03-30T01:00:00+08:00","hook":"cc-safety-gate","action":"deny","rule":"rm -rf /","cmd":"rm -rf /tmp"}
```
优先使用 `jq -nc` 构建 JSON，`jq` 不可用时回退到 `printf`。`_log_jsonl()` 函数自身 fail-safe（`2>/dev/null || true`）。

### 安全规则外部化
`cc-safety-gate.sh` 支持从 `safety-rules.conf` 加载自定义规则：
```bash
cp scripts/safety-rules.conf.example scripts/safety-rules.conf
# 按需编辑黑名单和受保护路径
```
内置默认规则**始终保留** — 外部配置只做覆盖，不做替代。配置文件不存在或不可读时，使用内置规则。

### Gateway Port 动态化
`cc-stop-hook.sh` 不再硬编码网关端口。在 `notify.conf` 中设置 `CC_GATEWAY_PORT` — 未设置时跳过 Gateway 唤醒调用。

### 异步派发引号修复
`dispatch-claude.sh` 现在将 prompt 写入 `mktemp` 临时文件，而非嵌入 `nohup bash -c '...'` 字符串，消除引号转义 bug。临时文件通过 `trap EXIT` 清理。

## 依赖

### 必需

| 依赖 | 版本 | 用途 |
|-----|------|------|
| `bash` | 4.0+ | 所有 hook 脚本（macOS 自带 bash 3.2，需 `brew install bash` 升级） |
| `curl` | 任意 | 通知投递（飞书、企微、Slack、Telegram、Discord、Bark、webhook） |
| `python3` | 3.6+ | 通知后端 JSON 编码 + `dispatch-claude.sh` |
| Claude Code CLI | 最新版 | `claude` 命令 — hooks 专为 Claude Code 设计 |

### 推荐

| 依赖 | 用途 |
|-----|------|
| `jq` | JSON 解析（缺失时优雅降级为 `printf` fallback） |
| `openssl` | 飞书 webhook HMAC-SHA256 签名（仅配置 `NOTIFY_FEISHU_SECRET` 时需要） |
| `git` | `dispatch-claude.sh` 的 worktree 隔离（非 git 目录不受影响） |

### 可选

| 依赖 | 用途 |
|-----|------|
| `openclaw` CLI | 仅使用 openclaw 通知后端时需要 |

### 平台说明

- **macOS**：默认 bash 为 3.2（GPLv2），需通过 `brew install bash` 安装 4+。其他依赖（`curl`、`python3`、`git`、`openssl`）已预装。
- **Linux (Ubuntu/Debian)**：所有依赖可通过 `apt` 安装，bash 4+ 为默认。
- **Windows (WSL)**：WSL2 Ubuntu 下完全支持。

---

## 平台安装指南

### 🍎 macOS

macOS 自带大部分依赖，唯一需要注意的是 bash 版本（系统自带 3.2）。

```bash
# 1. 检查 bash 版本
bash --version  # 如果 < 4.0，升级：
brew install bash

# 2. 确认 Claude Code 已安装
claude --version  # 如果未安装：
npm install -g @anthropic-ai/claude-code

# 3. 一键安装 hooks
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash

# 4. 配置通知后端（示例：飞书）
echo 'NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/你的TOKEN' >> ~/.claude/scripts/claude-hooks/notify.conf

# 5. 将打印的 hooks 配置复制到 ~/.claude/settings.json
# 然后重启 Claude Code

# 6. 测试
~/.claude/scripts/claude-hooks/send-notification.sh "Hello from macOS!"
```

### 🪟 Windows (WSL2)

Claude Code 在 Windows 上需要 WSL2 环境。所有 hooks 在 WSL2 Linux 环境内运行。

#### 前置条件

```powershell
# 在 PowerShell（管理员）中 — 安装 WSL2
wsl --install -d Ubuntu

# 如提示，重启后打开 Ubuntu 终端
```

#### 在 WSL2 (Ubuntu) 中

```bash
# 1. 安装 Node.js（Claude Code 需要）
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# 2. 安装 Claude Code
npm install -g @anthropic-ai/claude-code

# 3. 安装依赖
sudo apt-get install -y jq python3 curl openssl

# 4. 安装 hooks
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash

# 5. 配置通知后端（示例：飞书）
echo 'NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/你的TOKEN' >> ~/.claude/scripts/claude-hooks/notify.conf

# 6. 将打印的 hooks 配置复制到 ~/.claude/settings.json
# 然后重启 Claude Code

# 7. 测试
~/.claude/scripts/claude-hooks/send-notification.sh "Hello from Windows WSL2!"
```

#### Windows 特别注意

- **路径格式**：WSL2 内使用 Linux 路径（如 `~/.claude/scripts/`），不是 Windows 路径
- **VS Code 集成**：如果通过 VS Code 使用 Claude Code，确保 VS Code 连接到 WSL2（`Remote - WSL` 扩展）
- **文件权限**：WSL2 Ubuntu 原生支持 `chmod +x`，无需额外操作
- **通知投递**：`curl` 在 WSL2 内运行，可正常访问外部 webhook（飞书、企微、Slack 等）
- **推荐终端**：使用 Windows Terminal 获得更好的 bash 体验

## 许可证

MIT

## 更新日志

### v1.2.0 (2026-03-31)

**🌍 飞书 & 企微 Webhook + 完全脱离 OpenClaw 依赖**

Phase 1 — 新增通知后端：
- 新增 `_notify_feishu()` — 飞书自定义机器人 webhook，支持可选 HMAC-SHA256 签名
- 新增 `_notify_wecom()` — 企业微信群机器人 webhook（零鉴权）
- 自动检测优先级：`openclaw → feishu → wecom → slack → telegram → discord → bark → webhook → command`
- 总计支持 **9** 种通知后端（原 7 种）

Phase 2 — OpenClaw 解耦：
- 重命名 `notify-openclaw.sh` → `cc-stop-hook.sh`（git 历史保留）
- 所有路径中性化：`/tmp/openclaw-hooks/` → `/tmp/cchooks/`、`~/.openclaw/` → `~/.claude/scripts/claude-hooks/`
- 修复预存 Bug：`HOOK_DIR` 在双引号内使用 `~`（波浪号不展开，改为 `${HOME}`）
- `generate-skill-index.sh` 支持 `CC_SKILLS_DIR` 环境变量覆盖
- `install.sh` 更新为 `~/.claude/scripts/claude-hooks/` 路径
- 项目现在完全独立运行，无需安装 OpenClaw

Phase 3 — 用户体验：
- 首次运行提示：未配置通知后端时，一次性 stderr 提示引导配置
- `install.sh` 安装完成后打印飞书/企微/Slack 配置一键命令

### v1.1.0 (2026-03-30)

**🛡️ Git Worktree 隔离（P0 安全加固）**

针对 [Claude Code issue #40710](https://github.com/anthropics/claude-code/issues/40710) — Claude Code CLI 可能每 ~10 分钟通过内部 `libgit2` 静默执行 `git reset --hard origin/main`，销毁所有未提交变更。

- `dispatch-claude.sh`：自动检测 git 仓库并创建隔离 worktree（`git worktree add .worktrees/wt-{task_id} HEAD`）
- 优雅降级：worktree 创建失败时回退到原始工作目录
- 自动将 `.worktrees/` 追加到 `.gitignore`
- Git 安全断言注入：在 Claude prompt 中追踪每步 HEAD，检测到非预期 reset 时标注 `⚠️ GIT_RESET_DETECTED`
- 非 git 目录完全不受影响
