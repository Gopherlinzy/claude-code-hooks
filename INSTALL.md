# Claude Code Hooks — 完整安装说明

> 人类可读版安装指南。Claude Code Agent 的安装指令见 [CLAUDE.md](CLAUDE.md)。

## 目录

- [前置条件](#前置条件)
- [快速安装](#快速安装)
- [手动安装（分步骤）](#手动安装分步骤)
  - [第 1 步：克隆仓库](#第-1-步克隆仓库)
  - [第 2 步：复制脚本](#第-2-步复制脚本)
  - [第 3 步：配置通知](#第-3-步配置通知)
  - [第 4 步：写入 Hooks](#第-4-步写入-hooks)
  - [第 5 步：OpenRouter 状态栏（可选）](#第-5-步openrouter-状态栏可选)
  - [第 6 步：验证安装](#第-6-步验证安装)
- [OpenRouter 状态栏详细配置](#openrouter-状态栏详细配置)
  - [安装 claude-hud 插件](#安装-claude-hud-插件)
  - [部署 openrouter-statusline 脚本](#部署-openrouter-statusline-脚本)
  - [修改 claude-hud 源代码](#修改-claude-hud-源代码)
  - [配置 settings.json statusLine](#配置-settingsjson-statusline)
  - [隐藏默认模型标签](#隐藏默认模型标签)
- [Generation 成本追踪原理](#generation-成本追踪原理)
- [更新](#更新)
- [模块说明](#模块说明)

---

## 前置条件

- macOS / Linux / Windows (Git Bash)
- Node.js v18+
- `bash`, `curl`
- Claude Code CLI 已安装

---

## 快速安装

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
bash /tmp/claude-code-hooks/install.sh
```

> 🇨🇳 **GitHub 慢？** 用镜像：
> ```bash
> git clone https://ghfast.top/https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
> ```

安装脚本会引导你选择模块，完成后自动更新 `~/.claude/settings.json`。

---

## 手动安装（分步骤）

### 第 1 步：克隆仓库

```bash
git clone https://github.com/Gopherlinzy/claude-code-hooks.git /tmp/claude-code-hooks
```

已有本地克隆？跳过此步，用你的本地路径替换后续命令里的 `/tmp/claude-code-hooks`。

### 第 2 步：复制脚本

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
mkdir -p "${INSTALL_DIR}"

# 主脚本
cp /tmp/claude-code-hooks/scripts/*.sh "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}"/*.sh

# 状态栏工具（OpenRouter 监控）
mkdir -p "${INSTALL_DIR}/statusline"
cp /tmp/claude-code-hooks/tools/statusline/openrouter-statusline.js "${INSTALL_DIR}/statusline/"

# 工具脚本
cp /tmp/claude-code-hooks/tools/merge-hooks.js "${INSTALL_DIR}/"
cp /tmp/claude-code-hooks/tools/select-modules.js "${INSTALL_DIR}/"
```

### 第 3 步：配置通知

创建通知配置文件：

```bash
cat > "${INSTALL_DIR}/notify.conf" << 'EOF'
CC_NOTIFY_BACKEND=auto
CC_NOTIFY_TARGET=""
CC_WAIT_NOTIFY_SECONDS=30
CC_NOTIFY_CHANNEL="feishu"
# 在下方填写 Webhook URL：
EOF
chmod 600 "${INSTALL_DIR}/notify.conf"
```

如果有 Webhook 密钥/Token，放在独立的 secrets 文件里（不提交 Git）：

```bash
mkdir -p "${HOME}/.cchooks"
cat > "${HOME}/.cchooks/secrets.env" << 'EOF'
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
# NOTIFY_WECOM_URL=...
# CC_SLACK_WEBHOOK_URL=...
EOF
chmod 600 "${HOME}/.cchooks/secrets.env"
```

支持的通知后端：飞书、Slack、Telegram、Bark (iOS)、WeCom (企业微信)

### 第 4 步：写入 Hooks

将 hooks 合并进 `~/.claude/settings.json`（不会覆盖已有配置）：

```bash
SETTINGS="${HOME}/.claude/settings.json"
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
PATCH_FILE="/tmp/hooks-patch.json"

# 检测平台（Windows Git Bash 需要 bash 前缀）
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) CMD_PREFIX="bash " ;;
    *)                     CMD_PREFIX="" ;;
esac

INSTALL_DIR_ENV="${INSTALL_DIR}" PREFIX_ENV="${CMD_PREFIX}" PATCH_FILE_ENV="${PATCH_FILE}" \
node -e "
const fs = require('fs'), path = require('path');
const dir = process.env.INSTALL_DIR_ENV;
const prefix = process.env.PREFIX_ENV || '';
const patchFile = process.env.PATCH_FILE_ENV;
const cmd = (s) => prefix + path.join(dir, s).replace(/\\\\/g, '/');
const hooks = {
  hooks: {
    Stop: [{matcher:'*',hooks:[{type:'command',command:cmd('cc-stop-hook.sh'),timeout:15}]}],
    PreToolUse: [
      {matcher:'Bash',hooks:[{type:'command',command:cmd('cc-safety-gate.sh'),timeout:5}]},
      {matcher:'Read|Edit|Write',hooks:[{type:'command',command:cmd('guard-large-files.sh'),timeout:5}]}
    ],
    PermissionRequest: [{matcher:'*',hooks:[{type:'command',command:cmd('wait-notify.sh'),timeout:5}]}],
    Notification:      [{matcher:'*',hooks:[{type:'command',command:cmd('wait-notify.sh'),timeout:5}]}],
    PostToolUse:       [{matcher:'*',hooks:[{type:'command',command:cmd('cancel-wait.sh'),timeout:3}]}],
    UserPromptSubmit:  [{matcher:'*',hooks:[{type:'command',command:cmd('cancel-wait.sh'),timeout:3}]}]
  }
};
fs.writeFileSync(patchFile, JSON.stringify(hooks, null, 2));
console.log('OK — platform: ' + (prefix ? 'Windows' : 'Unix'));
"

node "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" "${PATCH_FILE}" "${SETTINGS}"
rm -f "${PATCH_FILE}"
echo "✅ Hooks 写入完成"
```

### 第 5 步：OpenRouter 状态栏（可选）

详见下方「[OpenRouter 状态栏详细配置](#openrouter-状态栏详细配置)」章节。

### 第 6 步：验证安装

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"

# 检查脚本语法
for f in "${INSTALL_DIR}"/*.sh; do
  bash -n "$f" && echo "✅ $(basename $f)" || echo "❌ $(basename $f)"
done

# 检查 settings.json 合法性
python3 -c "import json; json.load(open('${SETTINGS}')); print('✅ settings.json 合法')"

# 测试通知（如已配置）
"${INSTALL_DIR}/send-notification.sh" "Claude Code Hooks 安装成功！🦞"
```

---

## OpenRouter 状态栏详细配置

最终效果：

```
claude-sonnet-4-5 - $4.78 | 💰 334.83/500 ▓▓▓▓▓▓▓░░░ 67%
```

- **`claude-sonnet-4-5 - $4.78`** — 当前模型 + 本次会话累计成本（实时更新）
- **`💰 334.83/500`** — 账户余额 / 总限额
- **`▓▓▓▓▓▓▓░░░ 67%`** — 余额进度条

### 安装 claude-hud 插件

claude-hud 是状态栏的宿主程序，openrouter 信息通过 `--extra-cmd` 注入进去。

```bash
# 1. 添加到插件市场
# (在 Claude Code 里执行)
/plugin marketplace add jarrodwatts/claude-hud

# 2. 安装
/plugin install claude-hud

# 3. 初始化配置
/claude-hud:setup
```

验证安装：
```bash
ls ~/.claude/plugins/cache/claude-hud/claude-hud/ && echo "✅ claude-hud 已安装"
```

### 部署 openrouter-statusline 脚本

```bash
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
mkdir -p "${INSTALL_DIR}/statusline"

# 从本地仓库复制
cp ~/projects/claude-code-hooks/tools/statusline/openrouter-statusline.js \
   "${INSTALL_DIR}/statusline/"

# 或从 GitHub 直接下载
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/tools/statusline/openrouter-statusline.js \
  -o "${INSTALL_DIR}/statusline/openrouter-statusline.js"
```

确保 API Key 已配置：
```bash
# 添加到 ~/.zshrc 或 ~/.bashrc
export OPENROUTER_API_KEY="sk-or-v1-..."
```

### 修改 claude-hud 源代码

> **这一步是必须的**，原版 claude-hud 有两个限制需要手动修复。

#### 修改 1：移除输出长度限制

原版 `--extra-cmd` 输出限制为 50 字符，会截断 OpenRouter 信息。

```bash
# 找到 claude-hud 安装的版本目录
PLUGIN_DIR=$(ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1)
echo "Found: ${PLUGIN_DIR}"

# 备份原文件
cp "${PLUGIN_DIR}dist/extra-cmd.js" "${PLUGIN_DIR}dist/extra-cmd.js.bak"

# 查看当前值（应该是 50）
grep "MAX_LABEL_LENGTH" "${PLUGIN_DIR}dist/extra-cmd.js"

# 修改：50 → 999
sed -i '' 's/const MAX_LABEL_LENGTH = 50/const MAX_LABEL_LENGTH = 999/' \
  "${PLUGIN_DIR}dist/extra-cmd.js"

# 验证
grep "MAX_LABEL_LENGTH" "${PLUGIN_DIR}dist/extra-cmd.js"
# 期望输出: const MAX_LABEL_LENGTH = 999;
```

> **Linux** 用 `sed -i` 而不是 `sed -i ''`

#### 修改 2：写入当前模型到临时文件（动态更新支持）

claude-hud 主进程有 stdin 数据（含当前模型），但 `--extra-cmd` 拿不到。
通过让 claude-hud 在每次渲染时把当前模型写入临时文件，extra-cmd 脚本读取该文件实现实时同步。

```bash
PLUGIN_DIR=$(ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1)

# 备份
cp "${PLUGIN_DIR}dist/index.js" "${PLUGIN_DIR}dist/index.js.bak"

# 在 runExtraCmd 调用前，插入模型写入逻辑
# 找到插入点：const extraCmd = deps.parseExtraCmdArg();
node - << 'PATCH_EOF'
const fs = require('fs');
const file = require('os').homedir() + '/.claude/plugins/cache/claude-hud/claude-hud/' +
  require('fs').readdirSync(require('os').homedir() + '/.claude/plugins/cache/claude-hud/claude-hud/')
    .sort().pop() + '/dist/index.js';

let content = fs.readFileSync(file, 'utf-8');
const MARKER = '        const extraCmd = deps.parseExtraCmdArg();';
const PATCH = `        // 把当前模型信息写入临时文件，供 --extra-cmd 脚本读取（实时感知 /model 切换）
        try {
            const { writeFileSync } = await import('node:fs');
            const { join } = await import('node:path');
            const { tmpdir } = await import('node:os');
            const modelState = {
                model_id: stdin.model?.id ?? '',
                display_name: stdin.model?.display_name ?? '',
                updated_at: Date.now(),
            };
            writeFileSync(join(tmpdir(), 'claude-hud-current-model.json'), JSON.stringify(modelState));
        } catch (_) {}
`;

if (content.includes(PATCH.trim())) {
  console.log('✅ 已经打过补丁，跳过');
} else if (content.includes(MARKER)) {
  fs.writeFileSync(file, content.replace(MARKER, PATCH + MARKER));
  console.log('✅ 补丁写入成功');
} else {
  console.error('❌ 找不到插入点，请手动修改');
  process.exit(1);
}
PATCH_EOF
```

验证补丁：
```bash
PLUGIN_DIR=$(ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1)
grep -c "claude-hud-current-model" "${PLUGIN_DIR}dist/index.js" \
  && echo "✅ 补丁已生效" || echo "❌ 补丁未找到"
```

### 配置 settings.json statusLine

将以下配置写入 `~/.claude/settings.json` 的 `statusLine` 字段：

```bash
SETTINGS="${HOME}/.claude/settings.json"
STATUSLINE_SCRIPT="${HOME}/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js"

# 生成 statusLine command（自动找到已安装的 claude-hud 版本）
STATUSLINE_CMD="bash -c 'plugin_dir=\$(ls -d \"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1) && exec node \"\${plugin_dir}dist/index.js\" --extra-cmd \"node ${STATUSLINE_SCRIPT}\"'"

# 写入 settings.json（使用 python3，避免 jq 依赖）
python3 - << PYEOF
import json, os
settings_path = os.path.expanduser('${SETTINGS}')
with open(settings_path) as f:
    settings = json.load(f)
settings['statusLine'] = {
    'type': 'command',
    'command': '''${STATUSLINE_CMD}'''
}
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('✅ statusLine 写入完成')
PYEOF
```

**或者手动编辑 `~/.claude/settings.json`，加入：**

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1) && exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"node ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js\"'"
  }
}
```

### 隐藏默认模型标签

claude-hud 默认在左侧显示 `[Claude Haiku 4.5 | OpenRouter]`。由于 extra-cmd 已经显示了模型名，可以关掉避免重复：

```bash
CONFIG="${HOME}/.claude/plugins/claude-hud/config.json"

python3 - << PYEOF
import json, os
path = os.path.expanduser('${CONFIG}')
with open(path) as f:
    cfg = json.load(f)
cfg.setdefault('display', {})['showModel'] = False
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('✅ showModel 已设为 false')
PYEOF
```

重启 Claude Code 生效。

---

## Generation 成本追踪原理

### 数据来源

成本数据来自 OpenRouter 的 Generation API：

```bash
# 查询单次 generation 的费用
curl "https://openrouter.ai/api/v1/generation?id=gen-xxxxx" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

响应字段：
- `data.total_cost` — 本次请求费用（美元）
- `data.cache_discount` — 缓存折扣
- `data.provider_name` — 实际提供商（如 `Amazon Bedrock`）
- `data.model` — 模型 ID（如 `anthropic/claude-haiku-4-5`）

### 缓存文件

脚本在 `$TMPDIR` 里维护每个会话的累计成本文件：

```
$TMPDIR/claude-openrouter-cost-{session_id}.json
```

文件结构：
```json
{
  "seen_ids": ["gen-abc123", "gen-def456"],
  "total_cost": 4.78,
  "total_cache_discount": 0.15,
  "last_provider": "Amazon Bedrock",
  "last_model": "anthropic/claude-haiku-4-5-20251001"
}
```

**字段说明：**
- `seen_ids` — 已处理的 generation ID，避免重复查询
- `total_cost` — 本次会话累计成本
- `last_provider` / `last_model` — 最后一次 generation 的模型信息（降级用）

### 当前模型文件

claude-hud 补丁会在每次渲染时写入：

```
$TMPDIR/claude-hud-current-model.json
```

文件结构：
```json
{
  "model_id": "anthropic/claude-sonnet-4-5",
  "display_name": "Claude Sonnet 4 (1M context)",
  "updated_at": 1749123456789
}
```

**60 秒有效期**。`openrouter-statusline.js` 优先读取此文件，实现 `/model` 切换后立即更新模型名。

### 成本显示逻辑

```
优先：claude-hud-current-model.json（实时当前模型，60s有效）
  → 显示：claude-sonnet-4-5 - $4.78
降级：cost 缓存 last_model + last_provider
  → 显示：Amazon Bedrock: claude-haiku-4-5 - $4.78
再降级：只有成本无模型
  → 显示：$4.78
```

### 查询余额

余额来自：

```bash
curl https://openrouter.ai/api/v1/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

响应字段：
- `data.limit_remaining` — 剩余额度
- `data.limit` — 总额度

---

## 更新

```bash
cd ~/projects/claude-code-hooks  # 或你的本地路径
git pull

# 同步脚本
cp scripts/*.sh ~/.claude/scripts/claude-hooks/
chmod +x ~/.claude/scripts/claude-hooks/*.sh

# 同步 statusline
cp tools/statusline/openrouter-statusline.js \
   ~/.claude/scripts/claude-hooks/statusline/

echo "✅ 更新完成"
```

> 注意：`notify.conf`、`secrets.env`、claude-hud 源码修改**不会被更新命令覆盖**，需要手动处理。
> claude-hud 插件升级到新版本后，需要重新执行「修改 claude-hud 源代码」两个步骤。

---

## 模块说明

| 模块 | 类型 | 默认 | 说明 |
|------|------|------|------|
| Stop 通知 | Hook | ON | 任务完成后发送通知 |
| Safety gate | Hook | ON | 拦截高危 Bash 命令 |
| Large file guard | Hook | ON | 阻止读/写超大文件 |
| Wait 通知 | Hook | ON | 等待许可时发通知 |
| Cancel wait | Hook | ON | 用户操作后取消等待 |
| OpenRouter 状态栏 | StatusLine | OFF | 需手动按本文配置 |

禁用某模块：在第 4 步生成 hooks-patch.json 时删掉对应的 event，或用 `/claude-hud:setup` 界面操作。
