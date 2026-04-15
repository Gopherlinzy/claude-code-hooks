#!/usr/bin/env bash
# openrouter-cost-summary.sh — 在 Stop hook 里输出本次 session 的 OpenRouter 费用汇总
# 从 /tmp/claude-openrouter-cost-<session_id>.json 读取 statusline 缓存的累计数据
# 若缓存不存在（statusline 未运行过），则实时从 transcript 查询
# FAIL_MODE=open — 自身故障不影响 Claude Code 主进程

set -euo pipefail

# === 从 stdin 读取 Hook JSON ===
STDIN_JSON="$(cat 2>/dev/null || true)"

# === 解析 session_id 和 transcript_path ===
SESSION_ID=""
TRANSCRIPT_PATH=""
if command -v jq &>/dev/null && [ -n "${STDIN_JSON}" ]; then
    SESSION_ID="$(echo "${STDIN_JSON}" | jq -r '.session_id // empty' 2>/dev/null || true)"
    TRANSCRIPT_PATH="$(echo "${STDIN_JSON}" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
fi
if [ -z "${SESSION_ID}" ] && [ -n "${STDIN_JSON}" ]; then
    SESSION_ID="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id') or '')
except: pass
" 2>/dev/null || true)"
    TRANSCRIPT_PATH="$(echo "${STDIN_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path') or '')
except: pass
" 2>/dev/null || true)"
fi

[ -n "${SESSION_ID}" ] || exit 0

STATE_FILE="/tmp/claude-openrouter-cost-${SESSION_ID}.json"

# === 方案 A：statusline 缓存存在，直接读取 ===
if [ -f "${STATE_FILE}" ]; then
    python3 - "${STATE_FILE}" <<'PYEOF'
import sys, json

path = sys.argv[1]
try:
    with open(path) as f:
        s = json.load(f)
except Exception:
    sys.exit(0)

cost   = s.get("total_cost", 0)
cache  = s.get("total_cache_discount", 0)
prov   = s.get("last_provider", "")
model  = s.get("last_model", "")
seen   = len(s.get("seen_ids", []))

# 缩短模型名
import re
short = re.sub(r'^[^/]+/', '', model)
short = re.sub(r'-\d{8}$', '', short)

label = f"{prov}: {short}" if prov else "OpenRouter"
print(f"\n💰 本次费用汇总 ({label})")
print(f"   总费用:   ${cost:.4f}")
if cache > 0:
    print(f"   缓存节省: ${cache:.4f}")
if seen > 0:
    print(f"   共 {seen} 次调用")
PYEOF
    exit 0
fi

# === 方案 B：缓存不存在，用 tsx 调 statusline.ts 查一次 ===
TSX_BIN="$(command -v tsx 2>/dev/null || echo "")"
STATUSLINE_TS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/openrouter-statusline.ts"
API_KEY="${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_API_KEY:-}}"

if [ -z "${TSX_BIN}" ] || [ ! -f "${STATUSLINE_TS}" ] || [ -z "${API_KEY}" ] || [ -z "${TRANSCRIPT_PATH}" ]; then
    exit 0
fi

RESULT="$(echo "${STDIN_JSON}" | \
    ANTHROPIC_AUTH_TOKEN="${API_KEY}" \
    "${TSX_BIN}" "${STATUSLINE_TS}" 2>/dev/null || true)"

[ -n "${RESULT}" ] || exit 0

echo ""
echo "💰 本次费用汇总"
echo "   ${RESULT}"
