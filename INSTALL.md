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

> **Windows 用户注意**：`--extra-cmd` 在 Windows 上由 `cmd.exe` 执行，不认识 Git Bash 的 MSYS 路径（`/c/Users/...`）。
> 必须使用 Windows 原生格式（`C:/Users/...`）。  
> 推荐使用 `run-hud.sh` 自动处理路径转换，**macOS/Linux/Windows 通用**。

#### 推荐方式（跨平台，使用 run-hud.sh）

**Step 1 — 复制 run-hud.sh**

```bash
mkdir -p ~/.claude/scripts/claude-hooks/statusline
cp ~/projects/claude-code-hooks/tools/statusline/run-hud.sh \
   ~/.claude/scripts/claude-hooks/statusline/
chmod +x ~/.claude/scripts/claude-hooks/statusline/run-hud.sh
```

**Step 2 — 写入 settings.json**

```bash
python3 - << 'PYEOF'
import json, os
settings_path = os.path.expanduser('~/.claude/settings.json')
run_hud = os.path.expanduser('~/.claude/scripts/claude-hooks/statusline/run-hud.sh')
with open(settings_path) as f:
    settings = json.load(f)
settings['statusLine'] = {
    'type': 'command',
    'command': f'bash "{run_hud}"'
}
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('✅ statusLine 写入完成')
PYEOF
```

或手动编辑 `~/.claude/settings.json`：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"C:/Users/你的用户名/.claude/scripts/claude-hooks/statusline/run-hud.sh\""
  }
}
```

> **为什么用 run-hud.sh？**  
> `run-hud.sh` 自动检测平台，在 Windows 上将 `/c/Users/你的用户名/...` 转换为 `C:/Users/你的用户名/...`，
> 使 `cmd.exe` 可以识别 `--extra-cmd` 的路径。macOS/Linux 上直接运行，无额外开销。

#### Windows 路径问题说明

| 格式 | 示例 | cmd.exe 能识别 |
|------|------|:---:|
| MSYS 路径 | `/c/Users/sunluyi/.claude/...` | ❌ |
| Windows 原生路径 | `C:/Users/sunluyi/.claude/...` | ✅ |
| 反斜杠路径 | `C:\Users\sunluyi\.claude\...` | ✅（但 bash 中需转义）|

`run-hud.sh` 内部使用 `sed 's|^/\([a-zA-Z]\)/|\U\1:/|'` 自动完成转换，无需手动修改。

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

---

## Windows Git Bash 完整指南

### 特殊注意事项

Windows 上使用 Git Bash 需要额外的配置。本指南针对 **Windows 10/11 + Git for Windows + Node.js**。

#### 前置条件

```bash
# 验证必要的工具
which git bash node curl
# 都应该返回路径，如: /usr/bin/bash, /c/Program Files/nodejs/node.exe
```

#### Windows 特定问题

| 问题 | 原因 | 解决 |
|------|------|------|
| `bash: scripts/*.sh: command not found` | 脚本执行权限 | Git Bash 自动处理，无需 chmod |
| 路径包含反斜杠导致错误 | Windows 路径格式 | 脚本已使用正斜杠处理 |
| `OPENROUTER_API_KEY` 未生效 | 环境变量配置位置 | 编辑 `~/.bashrc` 或 `~/.zshrc` |
| statusline 显示乱码 | 编码问题 | 确保 `.bashrc` 含 `export LANG=en_US.UTF-8` |

#### Windows 快速安装

**Step 1: 在 Git Bash 中运行安装脚本**

```bash
cd /tmp  # 或任意临时目录
git clone https://github.com/Gopherlinzy/claude-code-hooks.git
cd claude-code-hooks
bash install.sh
```

安装脚本会自动检测 Windows 平台并添加 `bash` 前缀。

**Step 2: 配置 API Key**

编辑 `~/.bashrc`（通常在 `C:\Users\你的用户名\.bashrc`）：

```bash
# 在末尾添加
export OPENROUTER_API_KEY="sk-or-v1-..."
export LANG=en_US.UTF-8
```

然后重启 Git Bash 使配置生效：

```bash
source ~/.bashrc
echo $OPENROUTER_API_KEY  # 验证
```

**Step 3: 验证安装**

运行诊断脚本：

```bash
bash ~/projects/claude-code-hooks/tools/diagnose-windows.sh
```

这会检查：
- Node.js、bash、curl 可用性
- settings.json 和 hooks 配置
- OpenRouter API Key 环境变量
- statusline 脚本运行状态

### Windows 常见错误

#### 错误 1: `Settings file not found`

**症状**: 安装完成但 hooks 没有生效

**诊断**:
```bash
cat ~/.claude/settings.json | grep -c "hooks"
# 返回 0 表示 hooks 未写入
```

**解决**:
```bash
# 重新生成和写入 hooks
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
SETTINGS="${HOME}/.claude/settings.json"

# 检查目录是否存在
ls -la "$INSTALL_DIR"/*.sh

# 手动合并（使用 Python）
python3 "${INSTALL_DIR}/merge-hooks.js" "${SETTINGS}" patch.json "${SETTINGS}"
```

#### 错误 2: `OpenRouter statusline not showing`

**症状**: 状态栏不显示余额信息

**诊断**:
```bash
# 测试脚本单独运行
node ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js

# 应该输出: {"label":"💰 ..."}
```

**常见原因**:

1. **API Key 未设置**
   ```bash
   echo $OPENROUTER_API_KEY
   # 空结果表示未配置
   ```

2. **claude-hud 未安装或未配置**
   ```bash
   ls ~/.claude/plugins/cache/claude-hud/
   # 如果无输出，运行 /plugin install claude-hud
   ```

3. **statusline command 配置错误**
   ```bash
   grep statusLine ~/.claude/settings.json
   # 检查 command 字段是否包含正确的路径
   ```

**解决**:

```bash
# 完整的 statusline 配置命令
python3 << 'PYEOF'
import json, os, subprocess

settings_file = os.path.expanduser('~/.claude/settings.json')
plugin_dir_cmd = "ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1"
plugin_dir = subprocess.check_output(plugin_dir_cmd, shell=True, text=True).strip()

if not plugin_dir:
    print("❌ claude-hud 未安装")
    exit(1)

statusline_script = os.path.expanduser('~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js')
command = f"bash -c 'exec node \"{plugin_dir}dist/index.js\" --extra-cmd \"node {statusline_script}\"'"

with open(settings_file) as f:
    settings = json.load(f)

settings['statusLine'] = {'type': 'command', 'command': command}

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print("✅ statusLine 配置已更新")
PYEOF
```

然后重启 Claude Code。

#### 错误 3: `Network timeout`

**症状**: 状态栏多次出现 "timeout" 或无响应

**诊断**:
```bash
# 测试到 OpenRouter 的网络连接
curl -I https://openrouter.ai/api/v1/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

**解决**:

1. **检查防火墙/代理**
   ```bash
   # 如果使用代理，添加到 ~/.bashrc
   export http_proxy=http://proxy.company.com:8080
   export https_proxy=http://proxy.company.com:8080
   ```

2. **增加超时时间**
   编辑 `~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js`，找到：
   ```javascript
   fetchWithTimeout(..., 2000)  // 2秒
   ```
   改为：
   ```javascript
   fetchWithTimeout(..., 5000)  // 5秒
   ```

### Windows 诊断流程

如果安装后仍有问题，按以下顺序诊断：

**1. 环境检查**
```bash
bash tools/diagnose-windows.sh
```

**2. 手动路径检查**
```bash
# 检查安装目录
echo "INSTALL_DIR: $HOME/.claude/scripts/claude-hooks"
ls ~/.claude/scripts/claude-hooks/*.sh | wc -l

# 检查 settings.json
echo "SETTINGS: $HOME/.claude/settings.json"
python3 -c "import json; json.load(open('~/.claude/settings.json')); print('✅ Valid')" || echo "❌ Invalid JSON"
```

**3. 手动测试各个组件**
```bash
# 测试 notification
~/.claude/scripts/claude-hooks/send-notification.sh "Test message"

# 测试 safety gate
bash ~/.claude/scripts/claude-hooks/cc-safety-gate.sh "rm -rf /"

# 测试 statusline
node ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js
```

**4. 查看 Claude Code 日志**
```bash
# Claude Code 日志位置（Windows）
cat ~/.claude/logs/claude-code.log | tail -50
```

### Windows 卸载

要完全卸载：

```bash
# 移除脚本
rm -rf ~/.claude/scripts/claude-hooks

# 移除 hooks 配置（手动编辑 settings.json 删除 "hooks" 字段）
python3 << 'PYEOF'
import json, os
settings_file = os.path.expanduser('~/.claude/settings.json')
with open(settings_file) as f:
    settings = json.load(f)
if 'hooks' in settings:
    del settings['hooks']
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')
print("✅ Hooks 已移除")
PYEOF

# 重启 Claude Code
```

---

## 故障排除总览

### 快速检查清单

- [ ] Node.js 已安装: `node --version`
- [ ] 脚本存在: `ls ~/.claude/scripts/claude-hooks/*.sh | wc -l` → 应 ≥ 13
- [ ] settings.json 有效: `python3 -c "import json; json.load(open('~/.claude/settings.json'))"`
- [ ] hooks 已注册: `grep -c "hooks" ~/.claude/settings.json` → ≥ 1
- [ ] API Key 已配置: `echo $OPENROUTER_API_KEY | wc -c` → > 10
- [ ] Claude Code 已重启（让新配置生效）

### 获取帮助

- **GitHub Issues**: https://github.com/Gopherlinzy/claude-code-hooks/issues
- **项目 Wiki**: https://github.com/Gopherlinzy/claude-code-hooks/wiki
- **诊断脚本**: `bash tools/diagnose-windows.sh`（包含详细输出）
