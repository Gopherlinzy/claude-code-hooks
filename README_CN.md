# 🦞 Claude Code Hooks

> "我给 Claude Code 开了 sudo 权限。就一次。就那一次。"

给你的 AI 编程助手拴上安全绳 — 任务通知、安全门禁、跨平台兼容，一套搞定。

## 你一定遇到过

你启动 Claude Code，甩给它一个大活儿，去倒了杯咖啡。回来一看：

- ☕ 任务 20 分钟前就跑完了。没人告诉你。
- 🔐 Claude 乖乖等你审批权限。等了 20 分钟。一声不吭。
- 💀 更惨的 — 它跑了个 `rm -rf`，删了不该删的东西。
- 📖 它把整个 `bundle.min.js`（15000 行）读进了上下文窗口。
- 👻 昨天的异步任务还有三个孤儿进程在后台苟活。

**这个仓库，专治以上疑难杂症。**

## 全家桶一览

| Hook | 触发时机 | 用人话说 |
|------|---------|---------|
| 🔔 **cc-stop-hook.sh** | 任务结束 | 飞书/Slack/Telegram 推一下 —— 别再傻等了 |
| ⏰ **wait-notify.sh** | 等你审批 | "老板，Claude 等你 30 秒了，快回来……" |
| 🛑 **cancel-wait.sh** | 你回来了 | 取消催命闹钟，它知道你在 |
| 🛡️ **cc-safety-gate.sh** | 跑 Bash | 拦住 `rm -rf /`、`sudo`、`eval` 和 [22 种危险操作](#安全门拦截规则) |
| 📏 **guard-large-files.sh** | 读文件 | "放下那个 `node_modules/`，慢慢退后。" |
| 🚀 **dispatch-claude.sh** | 你手动调 | 隔离子任务：git worktree + 进度追踪 + 环境清洗 |
| 📊 **check-claude-status.sh** | 你手动调 | "那玩意儿还活着吗？" 快速回答。 |
| 🧹 **reap-orphans.sh** | 定时/手动 | 找到僵尸进程，人道主义清理 |
| 📚 **generate-skill-index.sh** | 懒加载 | 构建 Skills 索引，让 Claude 知道自己有什么装备 |
| 💰 **[statusline/](tools/statusline/)** | claude-hud 显示 | 实时 OpenRouter 信用额度监控，附带可视化进度条 |

## 🎨 状态栏工具

### OpenRouter 信用额度监控

为 `claude-hud` 状态栏增强实时 OpenRouter API 余额监控功能。

```
Claude Haiku 4.5 │ .openclaw │ 💰 394.34/500 ▓▓▓▓▓▓▓░░░ 79%
Context ███░░░░░░░ 30% │ Usage █████░░░░░ 45%
```

**功能特性：**
- 实时显示信用额度和使用统计
- 可视化 10 字符进度条（1 格 = 10%）
- 60 秒智能缓存，最小化 API 调用
- 友好的错误处理（离线、认证失败等）
- 快速配置：在 statusLine 中加 `--extra-cmd` 参数

**开始使用：** 详见 [tools/statusline/README_CN.md](tools/statusline/README_CN.md)。

## 极速上手

### 一行命令，零售后

```bash
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
```

> 🇨🇳 **国内用户 / GitHub 慢？** 用镜像：
> ```bash
> curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
> ```

安装器替你搞定一切：

```
[1/6] 环境检查     ← bash、node、python3、curl，齐了没？
[2/6] 安装脚本     ← 拉仓库 → 复制 → 加权限。完事。
[3/6] 模块选择     ← 带复选框的 TUI！很酷对吧。
[4/6] 注入配置     ← 深度合并到 settings.json，你原来的 hooks 不会被覆盖。
[5/6] 通知设置     ← 飞书、Slack、Telegram、Bark、Discord……选你喜欢的。
[6/6] 安装验证     ← 全绿通过，否则自动回滚。
```

```
  ↑↓ 移动  ␣ 选择  a 全选/全不选  Enter 确认

  ❯ [✔] 任务完成通知      因为沉默不是金
    [✔] 安全门（Bash）     因为 rm -rf / 永远不是正确答案
    [✔] 大文件拦截         因为 bundle.min.js 不是轻松读物
    [✔] 等待超时提醒       因为 Claude 太有礼貌了不会冲你喊
    [✔] 取消等待           因为你回来了，好人类
```

### 安装器花式用法

```bash
./install.sh                    # 交互式安装
./install.sh --non-interactive  # CI 模式 — 全部模块，不问问题
./install.sh --status           # "我装对了没？"
./install.sh --update           # 只更新脚本，配置不动
./install.sh --uninstall        # 体面退出
./install.sh --uninstall --purge  # 核弹选项
```

### 手动安装（"我不信 curl | bash"）

敬你是条好汉。

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks && ./install.sh
```

纯手工，不用安装器：
```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
# 然后手动编辑 ~/.claude/settings.json — 参考下方「Hook 注册」
```

## 平台支持

| 平台 | 状态 | 备注 |
|------|------|------|
| 🍎 **macOS** | ✅ 完美 | 需要 bash 4.0+（`brew install bash`，macOS 自带 3.2 太老了） |
| 🐧 **Linux** | ✅ 完美 | `apt install bash curl python3 jq` 然后一键安装 |
| 🪟 **WSL2** | ✅ 完美 | 本质上就是 Linux，只是多了几步安装 |
| 🪟 **Git Bash** | ⚠️ 能用 | 通知和安全门没问题，后台定时器不太靠谱 |
| 🪟 **PowerShell** | ❌ 不行 | 用 WSL2。认真的。 |

### v3.0.0 新增：跨平台兼容层

`platform-shim.sh` 提供了 8 个跨平台函数替换，所有 hook 自动加载 —— 你不需要配任何东西：

```bash
_date_iso          # date -Iseconds（MSYS2 上炸了）→ 自动降级 python3
_kill_check $PID   # kill -0（Git Bash 没有）→ tasklist 兼容
_ps_command_of $PID  # ps -p ... -o command=（同上）→ wmic 兼容
_stat_mtime $FILE  # stat -f/-c（macOS vs Linux）→ 自动检测
_env_clean cmd     # env -i（Windows 没有）→ 手动清理环境
_sleep_frac 0.05   # sleep 0.05（MSYS2 不支持小数）→ 降级 sleep 1
```

## 装完之后：配置通知

编辑 `notify.conf`（hook 子进程**不继承你的 shell 环境变量**，所以必须写在配置文件里）：

```bash
vim ~/.claude/scripts/claude-hooks/notify.conf
```

```bash
CC_NOTIFY_BACKEND=auto          # 自动发现所有已配置后端，同时广播
CC_WAIT_NOTIFY_SECONDS=30       # 等多久开始催你

# 取消注释你要用的：
# NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/你的TOKEN
# NOTIFY_WECOM_URL=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=你的KEY
# CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxx
# CC_BARK_URL=https://api.day.app/你的KEY
# CC_TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
# CC_TELEGRAM_CHAT_ID=987654321
```

> 🔒 **凭证管理（v3.0.0 新增）：** 敏感 URL/Token 建议放 `~/.cchooks/secrets.env`（权限 600），别放 `notify.conf`。脚本会自动加载两个文件，还会做完整性检查 —— 有人塞了 `$(whoami)` 进去？直接拒绝加载。

测试一下：
```bash
~/.claude/scripts/claude-hooks/send-notification.sh "你好，来自 Claude Code Hooks！🦞"
```

## 9 大通知后端

**广播模式**（默认）：同时推到所有已配置的后端。一个挂了？其他不受影响。

| 后端 | 配置变量 | 说明 |
|------|---------|------|
| 飞书 | `NOTIFY_FEISHU_URL` | 自定义机器人 webhook（支持签名验证） |
| 企业微信 | `NOTIFY_WECOM_URL` | 群机器人 webhook |
| Slack | `CC_SLACK_WEBHOOK_URL` | Incoming Webhook |
| Telegram | `CC_TELEGRAM_BOT_TOKEN` + `CHAT_ID` | Bot API |
| Discord | `CC_DISCORD_WEBHOOK_URL` | Webhook |
| Bark | `CC_BARK_URL` | iOS 推送 — [Bark](https://github.com/Finb/Bark) |
| Webhook | `CC_WEBHOOK_URL` | 任意 HTTP 端点 |
| Command | `CC_NOTIFY_COMMAND` | 管道到任意命令行工具 |
| OpenClaw | `CC_NOTIFY_TARGET` | 通过 OpenClaw 路由到飞书/Telegram 等 |

```bash
# 举例：飞书 + Bark 同时推送
CC_NOTIFY_BACKEND=auto
NOTIFY_FEISHU_URL=https://open.feishu.cn/...
CC_BARK_URL=https://api.day.app/...
# → 每条通知，两边都收到。冗余即是爱。
```

## 安全门拦截规则

`cc-safety-gate.sh` 见到这些直接拦：

| 类别 | 举例 |
|------|------|
| **删库跑路** | `rm -rf /`、`rm -rf ~/`、`mkfs`、`dd if=` |
| **提权** | `sudo`、`/usr/bin/sudo`、`\sudo`、`chmod 777` |
| **代码注入** | `eval`、`source <(...)`、`. <(...)`、`base64 ... \| bash` |
| **远程执行** | `curl \| sh`、`wget \| bash`、下载并执行链 |
| **套壳绕过** | `bash -c "rm ..."`、`sh -c "sudo ..."`、`python3 -c "os.system(...)"` |
| **路径保护** | `.ssh/`、`SOUL.md`、`IDENTITY.md`、`/etc/`、`/System/` |

还支持外部自定义规则（`safety-rules.conf`）。

> ⚠️ **诚实声明：** 黑名单天生存在绕过可能。一个有决心的攻击者（或者一个有创意的 LLM）总能找到办法。这是减速带，不是城墙。真正的安全边界请用 Claude Code 的 `--permission-mode`。

## 架构图

```
Claude Code 会话
  │
  ├── PreToolUse ─────┬── cc-safety-gate.sh ── "不行，这条命令我不让跑。"
  │                   └── guard-large-files.sh ── "放下 bundle.min.js，慢慢退后。"
  │
  ├── PermissionRequest ── wait-notify.sh ──→ ⏱️ 30秒 ──→ 📱 "快回来！"
  │
  ├── Notification ─────── wait-notify.sh ──→ ⏱️ 30秒 ──→ 📱 "还在等你……"
  │
  ├── PostToolUse ──────── cancel-wait.sh ──→ ⏱️❌ "没事了，人回来了。"
  │
  ├── UserPromptSubmit ─── cancel-wait.sh ──→ ⏱️❌ "他打字了！"
  │
  └── Stop ─────────────── cc-stop-hook.sh ──→ 📱 "完事了！结果在这。"
```

## Hook 注册（settings.json）

安装器会帮你搞定，手动安装的话照着抄：

```json
{
  "hooks": {
    "Stop": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cc-stop-hook.sh", "timeout": 15 }] }
    ],
    "PreToolUse": [
      { "matcher": "Read|Edit|Write", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/guard-large-files.sh", "timeout": 5 }] },
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cc-safety-gate.sh", "timeout": 5 }] }
    ],
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/wait-notify.sh", "timeout": 5 }] }
    ],
    "Notification": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/wait-notify.sh", "timeout": 5 }] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cancel-wait.sh", "timeout": 3 }] }
    ],
    "UserPromptSubmit": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/claude-hooks/cancel-wait.sh", "timeout": 3 }] }
    ]
  }
}
```

## 安全加固

我们引以为傲的设计：

- 🛟 **全链路 Fail-Open** — hook 自身崩溃绝不阻塞 Claude Code。绝不。
- 📝 **JSONL 审计日志** — 一切操作记录在 `~/.cchooks/logs/hooks-audit.jsonl`
- 🔒 **凭证隔离** — 敏感信息存 `~/.cchooks/secrets.env`（600 权限），不放脚本目录
- 🧬 **完整性校验** — `source` 前检查文件，含 `$(` 或反引号的一律拒绝
- ⚛️ **原子写入** — tmp → 验证 → mv（崩溃安全）
- 🔑 **API Key 隔离** — hook 启动时立即 unset `ANTHROPIC_API_KEY`
- 🌍 **跨平台兼容** — `platform-shim.sh` 让 macOS/Linux/WSL2/Git Bash 统统能跑

## Claude Code Hook 事件一览

| 事件 | 触发时机 | matcher 匹配的是 |
|------|---------|-----------------|
| **PreToolUse** | 工具执行前 | 工具名（`Bash`、`Read` 等） |
| **PostToolUse** | 工具执行后（成功） | 工具名 |
| **Stop** | 会话结束 | 停止原因 |
| **Notification** | CC 发通知 | `permission_prompt` / `idle_prompt` 等 |
| **PermissionRequest** | CC 请求权限 | 工具名 |
| **UserPromptSubmit** | 你输入了东西 | `*` |

**matcher 语法：** `"*"`（全匹配）· `"Bash"`（精确）· `"Read|Edit|Write"`（OR）· `""`（别用 — 行为未定义）

## 依赖

| 依赖 | 必需？ | 干嘛的 |
|------|--------|--------|
| `bash` 4.0+ | ✅ | 一切都是 bash 写的。macOS 自带 3.2 太老了 → `brew install bash` |
| `node` 14+ | ✅ | 安装器 TUI + hooks 合并 |
| `curl` | ✅ | 发通知 |
| `python3` | ✅ | JSON 转义（Windows 上自动检测 `python`） |
| `jq` | 推荐 | JSON 解析（没有的话优雅降级到 Python） |
| `git` | 可选 | Worktree 隔离 |
| `openssl` | 可选 | 飞书签名验证 |

## 更新日志

### v3.0.0 (2026-04-02)

**🛡️ 安全加固 + 跨平台兼容层 + 34 项修复**

> 请了个安全审计，然后他有很多意见。

- **安全：** 凭证迁移到 secrets.env (600) · source 完整性检查 · eval → bash -c · 全部 shell→python 注入面消除 · JSON 生成改用 json.dump · 安全门 +8 条规则
- **跨平台：** 新增 platform-shim.sh（8 个 portable 函数）· 30 处平台特定调用全部替换 · CCHOOKS_TMPDIR 全局可配置
- **健壮性：** 移除致命 set -e · 修复锁释放 · 空数组保护 · session 搜索加速 · find -print0 防空格

### v2.0.0 (2026-04-02) · 交互式安装器
### v1.3.1 (2026-04-01) · Git Bash 兼容
### v1.3.0 (2026-03-31) · 广播模式
### v1.2.0 (2026-03-31) · 飞书 & 企微
### v1.1.0 (2026-03-30) · Worktree 隔离
### v1.0.0 (2026-03-29) · 首发

## 许可证

MIT — 你想干嘛干嘛。但别 `rm -rf /`。
