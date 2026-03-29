#!/usr/bin/env bash
# cc-safety-gate.sh — PreToolUse 安全门：拦截高危 Bash 命令
# 从 stdin 读取 Claude Code Hook JSON，提取 .tool_input.command 进行黑名单匹配

set -euo pipefail

# 读取 stdin JSON，提取命令
INPUT="$(cat)"
CMD="$(echo "${INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

# 无命令则放行
if [[ -z "${CMD}" ]]; then
    exit 0
fi

# === 黑名单模式 ===
BLACKLIST_PATTERNS=(
    'rm -rf /'
    'rm -rf ~'
    'sudo '
    'chmod 777'
    'curl.*|.*sh'
    'wget.*|.*sh'
    'mkfs'
    'dd if='
    '> /etc/'
)

# === 路径保护 ===
PROTECTED_PATHS=(
    '.ssh'
    'SOUL.md'
    'IDENTITY.md'
    'USER.md'
    '/etc/'
    '/System/'
)

# 检查黑名单
for pattern in "${BLACKLIST_PATTERNS[@]}"; do
    if echo "${CMD}" | grep -qE "${pattern}"; then
        cat <<EOF
{"decision":"deny","reason":"[cc-safety-gate] 命令匹配黑名单规则: ${pattern}"}
EOF
        exit 0
    fi
done

# 检查路径保护
for protected in "${PROTECTED_PATHS[@]}"; do
    if echo "${CMD}" | grep -qF "${protected}"; then
        cat <<EOF
{"decision":"deny","reason":"[cc-safety-gate] 命令涉及受保护路径: ${protected}"}
EOF
        exit 0
    fi
done

# 未匹配，放行
exit 0
