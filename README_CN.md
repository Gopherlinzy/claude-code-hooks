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

## 🎨 状态栏工具（可选）

### OpenRouter 实时额度监控

为你的 Claude Code 状态栏增强实时 OpenRouter API 额度监控。此功能需要 `claude-hud`（Claude 官方状态栏插件）。

```
Claude Haiku 4.5 │ .openclaw │ 💰 394.34/500 ▓▓▓▓▓▓▓░░░ 79% │ context: 42%
```

**你会得到：**
- ✅ 实时显示信用额度余额
- ✅ 可视化 10 字符进度条
- ✅ 60 秒智能缓存（最小化 API 调用）
- ✅ 离线友好（网络差不显示）
- ✅ 跨平台支持（macOS/Linux/Windows）

### 快速设置（3 步）

**第 1 步：claude-hud 插件会自动安装**

Claude Code 会自动下载并更新 `claude-hud`。你可以验证：
```bash
ls "${HOME}/.claude/plugins/cache/claude-hud/"
# 如果为空，重启 Claude Code 时会自动安装
```

**第 2 步：运行配置工具**

```bash
~/.claude/scripts/claude-hooks/setup-statusline.sh
```

这个工具会：
- ✅ 检查 claude-hud 是否已安装
- ✅ 根据你的系统生成正确的 `statusLine` 配置
- ✅ 提示你添加 `OPENROUTER_API_KEY` 环境变量
- ✅ 展示配置片段供你复制

**第 3 步：粘贴配置到 settings.json**

工具会输出一个 JSON 代码段，你可以直接复制到 `~/.claude/settings.json`。

### 手动配置（如果你更喜欢）

如果你想手动配置，详见 [tools/statusline/README_CN.md](tools/statusline/README_CN.md)。

**前置条件：**
- 设置环境变量 `OPENROUTER_API_KEY`
- `claude-hud` 插件（Claude Code 自动安装）
- Node.js 18+（Claude Code 已需要）

## 极速上手

### 🤖 方案 0：让 Claude Code 自动安装（零 CLI 知识要求）

**适合：** 谁都行，特别是不想碰命令行的人  
**耗时：** ~3 分钟  
**难度：** ⭐（就是在 Claude Code 里打字）

Clone 仓库，在 Claude Code 中打开，让它读安装指南。Claude 会搞定所有步骤，还会问你需要什么。

```bash
# 第 1 步 — Clone（二选一）
git clone https://github.com/Gopherlinzy/claude-code-hooks.git ~/projects/claude-code-hooks

# 🇨🇳 GitHub 太慢？
git clone https://ghfast.top/https://github.com/Gopherlinzy/claude-code-hooks.git ~/projects/claude-code-hooks

# 第 2 步 — 在 Claude Code 中打开项目
cd ~/projects/claude-code-hooks
claude
```

然后就这样告诉 Claude，比如：

```
Please read CLAUDE.md and install claude-code-hooks for me.
I use Feishu for notifications. My webhook URL is https://...
```

Claude 会：
1. 读 `CLAUDE.md`（这个仓库里的人工智能可读安装指南）
2. 把脚本复制到正确的位置
3. 问你想用哪个通知后端
4. 把 hook 合并到 `~/.claude/settings.json`
5. 验证一切正常

> **Note：** `CLAUDE.md` 是机器可读的安装指南 — 它描述每一步，这样 Claude Code 可以代表你执行完整安装。

---

### 选择你的安装路线

不同的安装方式，适合不同的人：

#### 🚀 方案 A：一行命令，无后顾之忧（推荐）

**适合：** 大多数用户，包括 Windows Git Bash  
**耗时：** ~2 分钟  
**难度：** ⭐  

一行命令搞定一切。安装器负责环境检查、脚本安装、模块选择、Hook 注册和通知配置。

**优点：**
- ✅ 完全自动化，带交互式 TUI
- ✅ 出错自动回滚
- ✅ 内置模块选择
- ✅ 原生支持 Windows Git Bash
- ✅ 一行命令，完全自动

**缺点：**
- ❌ 对安装内容的控制较少
- ❌ 需要用 pipe to bash（但完全可审计）

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

#### 🛠️ 方案 B：一步一步手工安装（我想要完全控制）

**适合：** 高级用户、CI/CD 集成、自定义部署  
**耗时：** ~10 分钟  
**难度：** ⭐⭐  

Clone 仓库，然后手工运行每一步。完全控制文件放在哪、怎么配置，以及启用哪些模块。

**优点：**
- ✅ 完全控制 — 自己决定什么放在哪里
- ✅ 易于集成到 CI/CD 流程
- ✅ 每一步都可以先审计再执行
- ✅ 完美适配气隙环境（提前下载）
- ✅ Windows Git Bash 完美支持

**缺点：**
- ❌ 要手工执行 6 个步骤而不是 1 条命令
- ❌ 出错需要手工修复
- ❌ 需要一些 bash 知识

**[→ 详见下方「手工安装」章节](#手工安装-我想要完全控制)**

#### 📦 方案 C：完全离线（气隙系统）

**适合：** 离线开发、气隙 CI/CD、隔离网络  
**耗时：** ~15 分钟（主要是下载等待）  
**难度：** ⭐⭐  

在有网的机器上提前下载，然后转移到没网的系统。除了下载步骤，其他和方案 B 完全一样。

**优点：**
- ✅ 完全离线（初始下载后）
- ✅ 和方案 B 的控制力一样
- ✅ 目标机器上无网络调用
- ✅ 便于审计

**缺点：**
- ❌ 需要两台机器（一台有网）
- ❌ 需要手工转移文件
- ❌ 和方案 B 一样要 6 个步骤

**关键差异：** 在有网的机器上下载，然后通过 U 盘、scp 等方式转移到离线机器。

**[→ 详见下方「完全离线」章节](#完全离线气隙系统)**

### 方案对比

| 方面 | 方案 0 | 方案 A | 方案 B | 方案 C |
|------|--------|--------|--------|--------|
| **耗时** | ~3 分钟 | ~2 分钟 | ~10 分钟 | ~15 分钟 |
| **难度** | ⭐ | ⭐ | ⭐⭐ | ⭐⭐ |
| **怎么做** | 和 Claude 聊天 | 一行 curl 命令 | 手工多个步骤 | 提前下载然后手工 |
| **可控性** | Claude 选择 | 低 | 高 | 高 |
| **出错恢复** | Claude 处理 | 自动回滚 | 手工修复 | 手工修复 |
| **需要网络** | 安装时 | 安装时 | 安装时 | 不需要（预下载） |
| **最适合** | 非 CLI 用户 | 普通用户 | 高级用户、CI/CD | 气隙环境 |
| **Windows Git Bash** | ✅ | ✅ | ✅ 推荐 | ✅ |
| **依赖检查** | Claude 检查 | 自动 | 手工 | 手工 |
| **模块选择** | 和 Claude 聊 | TUI | 手工编辑 | 手工编辑 |

---

### 一行命令，零售后

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

### 手工安装（我想要完全控制）

这是**方案 B** 的详细版本。按照下面 6 个步骤完全掌控安装。

#### 步骤 1：Clone 仓库

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
cd /tmp/claude-code-hooks
```

> 🇨🇳 **国内或 GitHub 太慢？**
> ```bash
> git clone https://ghfast.top/https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
> cd /tmp/claude-code-hooks
> ```

#### 步骤 2：复制脚本

创建安装目录并复制所有脚本：

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
mkdir -p "${INSTALL_DIR}"

# 复制主 Hook 脚本
cp scripts/*.sh "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}"/*.sh

# 复制状态栏工具（可选，OpenRouter 信用额度监控）
mkdir -p "${INSTALL_DIR}/statusline"
cp tools/statusline/*.sh "${INSTALL_DIR}/statusline/"
chmod +x "${INSTALL_DIR}/statusline"/*.sh

# 复制工具脚本（为了未来更新）
cp tools/merge-hooks.js "${INSTALL_DIR}/"
cp tools/select-modules.js "${INSTALL_DIR}/"
```

**Windows (Git Bash) 注意：** 上面的路径在 Git Bash 中本身就可用，无需特殊处理。

#### 步骤 3：创建 notify.conf

选择你的通知后端并配置：

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
cat > "${INSTALL_DIR}/notify.conf" << 'EOF'
CC_NOTIFY_BACKEND=auto
CC_WAIT_NOTIFY_SECONDS=30

# 取消注释并配置你要用的后端：
# NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
# CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../xxx
# CC_BARK_URL=https://api.day.app/YOUR_KEY
# CC_TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
# CC_TELEGRAM_CHAT_ID=987654321
# CC_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
EOF
```

**对于敏感凭证**（含 Token 的 Webhook URL），把它们放在 `~/.cchooks/secrets.env` 里，而不是 `notify.conf`：

```bash
mkdir -p "${HOME}/.cchooks"
cat > "${HOME}/.cchooks/secrets.env" << 'EOF'
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN
CC_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../xxx
EOF
chmod 600 "${HOME}/.cchooks/secrets.env"
```

#### 步骤 4：合并 Hook 到 settings.json

这一步把所有 Hook 注册到 Claude Code 设置文件（保留已有的 Hook）

**macOS / Linux / WSL2：**

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"

node "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" \
  <(node -e "
const fs = require('fs');
const dir = '${INSTALL_DIR}'.replace(/'/g, '');
const cmd = (script) => dir + '/' + script;
const hooks = {
  hooks: {
    Stop: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cc-stop-hook.sh'), timeout: 15 }] }],
    PreToolUse: [
      { matcher: 'Bash', hooks: [{ type: 'command', command: cmd('cc-safety-gate.sh'), timeout: 5 }] },
      { matcher: 'Read|Edit|Write', hooks: [{ type: 'command', command: cmd('guard-large-files.sh'), timeout: 5 }] }
    ],
    PermissionRequest: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('wait-notify.sh'), timeout: 5 }] }],
    Notification: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('wait-notify.sh'), timeout: 5 }] }],
    PostToolUse: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cancel-wait.sh'), timeout: 3 }] }],
    UserPromptSubmit: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cancel-wait.sh'), timeout: 3 }] }]
  }
};
fs.writeFileSync('/dev/stdout', JSON.stringify(hooks, null, 2));
") \
  "${SETTINGS}"
```

**Windows (Git Bash)：**

Windows 需要给所有 Hook 命令加 `bash ` 前缀：

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"

node -e "
const fs = require('fs');
const dir = '${INSTALL_DIR}'.replace(/'/g, '');
const prefix = 'bash ';
const cmd = (script) => prefix + dir + '/' + script;
const hooks = {
  hooks: {
    Stop: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cc-stop-hook.sh'), timeout: 15 }] }],
    PreToolUse: [
      { matcher: 'Bash', hooks: [{ type: 'command', command: cmd('cc-safety-gate.sh'), timeout: 5 }] },
      { matcher: 'Read|Edit|Write', hooks: [{ type: 'command', command: cmd('guard-large-files.sh'), timeout: 5 }] }
    ],
    PermissionRequest: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('wait-notify.sh'), timeout: 5 }] }],
    Notification: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('wait-notify.sh'), timeout: 5 }] }],
    PostToolUse: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cancel-wait.sh'), timeout: 3 }] }],
    UserPromptSubmit: [{ matcher: '*', hooks: [{ type: 'command', command: cmd('cancel-wait.sh'), timeout: 3 }] }]
  }
};
fs.writeFileSync('/tmp/hooks-patch.json', JSON.stringify(hooks, null, 2));
" && node "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" /tmp/hooks-patch.json "${SETTINGS}"
rm -f /tmp/hooks-patch.json
```

#### 步骤 5：（可选）配置状态栏 OpenRouter 信用监控

如果你想在 claude-hud 状态栏显示实时 OpenRouter 信用额度：

**macOS / Linux / WSL2：**

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"
PLUGIN_DIR=$(ls -d "${HOME}/.claude/plugins/cache/claude-hud/claude-hud/"*/ 2>/dev/null | \
    awk -F/ '{ print $(NF-1) "\t" $(0) }' | \
    sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | \
    tail -1 | cut -f2-)

if [ -z "$PLUGIN_DIR" ]; then
    echo "⚠️  claude-hud 插件未找到 — 状态栏配置跳过"
else
    node -e "
const fs = require('fs');
const settings = JSON.parse(fs.readFileSync('${SETTINGS}', 'utf8'));
settings.statusLine = {
    command: 'bash -c \"plugin_dir=${PLUGIN_DIR}; exec node \\\${plugin_dir}dist/index.js --extra-cmd \\\"bash ${INSTALL_DIR}/statusline/openrouter-status.sh\\\"\"',
    type: 'command'
};
fs.writeFileSync('${SETTINGS}', JSON.stringify(settings, null, 2) + '\\n');
" && echo "✅ 状态栏已配置"
fi
```

**Windows (Git Bash)：**

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"
PLUGIN_DIR=$(ls -d "${HOME}/.claude/plugins/cache/claude-hud/claude-hud/"*/ 2>/dev/null | \
    awk -F/ '{ print $(NF-1) "\t" $(0) }' | \
    sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | \
    tail -1 | cut -f2-)

if [ -z "$PLUGIN_DIR" ]; then
    echo "⚠️  claude-hud 插件未找到 — 状态栏配置跳过"
else
    node -e "
const fs = require('fs');
const settings = JSON.parse(fs.readFileSync('${SETTINGS}', 'utf8'));
settings.statusLine = {
    command: 'bash -c \"plugin_dir=${PLUGIN_DIR}; exec node \\\${plugin_dir}dist/index.js --extra-cmd \\\"bash ${INSTALL_DIR}/statusline/openrouter-status.sh\\\"\"',
    type: 'command'
};
fs.writeFileSync('${SETTINGS}', JSON.stringify(settings, null, 2) + '\\n');
" && echo "✅ 状态栏已配置"
fi
```

#### 步骤 6：验证安装

运行这些检查确保一切配置正确：

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"

# 检查所有脚本都可执行
echo "=== 检查 Hook 脚本 ==="
for f in "${INSTALL_DIR}"/*.sh; do
    if bash -n "$f" 2>/dev/null; then
        echo "✅ $(basename "$f")"
    else
        echo "❌ $(basename "$f") — 语法错误"
    fi
done

# 检查 settings.json 是有效的 JSON
echo "=== 检查 settings.json ==="
if python3 -c "import json; json.load(open('${SETTINGS}'))" 2>/dev/null; then
    echo "✅ settings.json 是有效的 JSON"
else
    echo "❌ settings.json 无效"
fi

# 测试通知（如果已配置）
echo "=== 测试通知 ==="
if "${INSTALL_DIR}/send-notification.sh" "Claude Code Hooks 测试消息 🦞"; then
    echo "✅ 通知已发送"
else
    echo "⚠️  通知后端尚未配置"
fi
```

**如果有检查失败，** 参考 [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) 获得解决方案。

---

### 完全离线（气隙系统）

这是**方案 C** 的详细版本。在目标系统无网络访问的情况下使用此方法。

#### 步骤 0：在有网的机器上准备

在有网络的机器上：

```bash
# Clone 仓库
git clone https://github.com/Gopherlinzy/claude-code-hooks.git

# 可选：压缩便于转移（如果空间有限）
tar czf claude-code-hooks.tar.gz claude-code-hooks/
```

通过 U 盘、scp 或其他方式把 `claude-code-hooks/` 目录（或压缩文件）转移到离线机器。

#### 步骤 1-6：和方案 B 完全一样

一旦你在离线机器上有了 `claude-code-hooks/` 目录，按照**方案 B 的步骤 1-6** 完全相同地做：

1. ✅ Clone → 跳过（已经有目录了）
2. ✅ 复制脚本
3. ✅ 创建 notify.conf
4. ✅ 合并 Hook 到 settings.json
5. ✅ （可选）配置状态栏
6. ✅ 验证安装

**唯一的差异：** 在步骤 1 不需要 Clone，因为你已经有文件了。只需导航到 `claude-code-hooks/` 目录，然后从步骤 2 开始：

```bash
# 而不是：git clone https://github.com/.../claude-code-hooks.git /tmp/claude-code-hooks
# 你已经有了，所以只需：
cd /path/to/claude-code-hooks
# 然后继续步骤 2（复制脚本）及之后的步骤
```

---

### DIY 安装（我不信 curl | bash）

敬你是条好汉。

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks && ./install.sh
```

或者完全手工，不用安装器：

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
mkdir -p ~/.claude/scripts/claude-hooks
cp claude-code-hooks/scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh
# 然后手动编辑 ~/.claude/settings.json — 参考下方「Hook 注册」
```

---

## 平台支持

| 平台 | 状态 | 安装方式 | 备注 | 已知问题 |
|------|------|--------|------|--------|
| 🍎 **macOS** | ✅ 完美 | `./install.sh` | 需要 bash 4.0+（`brew install bash`，macOS 自带 3.2 太老了） | 无 |
| 🐧 **Linux** | ✅ 完美 | `./install.sh` | `apt install bash curl python3 jq` | 无 |
| 🪟 **WSL2** | ✅ 完美 | `./install.sh`（Linux 模式） | 插件缓存在 WSL Linux 主目录，不在 Windows | 无 |
| 🪟 **Git Bash** | ✅ Hook + ⚠️ 状态栏 | `./install.sh` 或手工 | Hook ✅ 可用；状态栏有[已知问题](docs/TROUBLESHOOTING.md#windows-git-bash-specific) | [见 Git Bash 问题](docs/TROUBLESHOOTING.md#windows-git-bash-specific) |
| 🪟 **PowerShell / cmd** | ❌ 不行 | 用 WSL2 | 不支持 — Hook 脚本只能用 bash | 使用 [Windows 子系统](https://learn.microsoft.com/zh-cn/windows/wsl/) |

**关键差异：**

- **macOS/Linux：** 完整支持，开箱即用
- **WSL2：** 完整支持，用 Linux 命令（插件缓存要在 WSL 文件系统）
- **Git Bash：** Hook ✅ 可用，状态栏配置有已知路径转义问题（v1.0.1）。[见解决方案](docs/TROUBLESHOOTING.md#windows-git-bash-specific)
- **PowerShell：** 不支持。Windows 开发用 WSL2。

> **Windows 用户：** 大多数问题都和路径有关，[已在 TROUBLESHOOTING 中记录](docs/TROUBLESHOOTING.md#windows-git-bash-specific)。安装失败? [查看 Windows 故障排查章节](docs/TROUBLESHOOTING.md#installation-failures)。

### v1.0.1 新增：跨平台兼容层与安全加固

`platform-shim.sh` 提供了 8 个跨平台函数替换。所有 Hook 脚本自动使用这些函数 —— 你无需配置任何东西。

```bash
# 这些函数在所有平台都可用：
_date_iso          # date -Iseconds（MSYS2 上炸了）→ 自动降级 python3
_kill_check $PID   # kill -0（Git Bash 没有）→ tasklist 兼容
_ps_command_of $PID  # ps -p PID -o command=（同上）→ wmic 兼容
_stat_mtime $FILE  # stat -f %m / stat -c %Y（macOS vs Linux）
_env_clean cmd     # env -i（Windows 没有）→ 手动清理环境
_sleep_frac 0.05   # Fractional sleep（MSYS2 不支持小数）
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

### 状态栏配置（可选）

要在 claude-hud 状态栏添加实时 OpenRouter 信用额度监控：

**macOS / Linux：**
```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print $(NF-1) \"\\t\" $(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"/usr/local/bin/node\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
```

**Windows (Git Bash / MSYS2)：**
```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print $(NF-1) \"\\t\" $(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"node\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
```

**前置条件：**
- 设置环境变量 `OPENROUTER_API_KEY`
- 已安装 `claude-hud` 插件
- PATH 中可用 Node.js 18+

详细配置见 [tools/statusline/README_CN.md](tools/statusline/)。

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

详细的版本发布日志、bug 修复和历史记录见 [CHANGELOG.md](CHANGELOG.md)。

**最新版本（v1.0.0 - 2026-04-12）：**
- 4 个 P0 Bug 修复（质量评分 7.5 → 8.5）
- 多账户 Git 支持（GitHub + GitLab）
- SSH 密钥路由配置
- 跨平台兼容性改进

## 许可证

MIT — 你想干嘛干嘛。但别 `rm -rf /`。
