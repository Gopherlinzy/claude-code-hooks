#!/bin/bash

# OpenRouter StatusLine - 三合一：余额 + 模型 + 成本
# 直接作为 statusLine 命令，接收 stdin，输出 JSON

set +e

OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-$ANTHROPIC_AUTH_TOKEN}"
[[ -z "$OPENROUTER_API_KEY" ]] && echo '{"label":"⚙️ No API Key"}' && exit 0

# ===== 1. 获取余额（通过 /api/v1/key）=====
get_balance() {
  local resp=$(curl -s --max-time 2 \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    "https://openrouter.ai/api/v1/key" 2>/dev/null || echo "")

  [[ -z "$resp" ]] && return 1

  if echo "$resp" | grep -q '"error"'; then
    return 1
  fi

  # 用 python3 解析 JSON
  python3 << 'PYEOF'
import json, sys
try:
  d = json.loads(sys.stdin.read())
  remaining = d.get('data', {}).get('limit_remaining', 0)
  limit = d.get('data', {}).get('limit', 0)
  if limit > 0:
    pct = int(remaining / limit * 100)
    print(f"{remaining:.0f}/{limit:.0f}")
  else:
    print("0/0")
except:
  print("0/0")
PYEOF
}

# ===== 2. 获取会话成本和模型信息（通过 stdin + generation API）=====
get_session_cost() {
  local input="$1"
  [[ -z "$input" ]] && return 1

  # 用 Python 处理整个逻辑
  python3 << 'PYEOF'
import json, sys, os, subprocess
from pathlib import Path

try:
  stdin_data = json.loads(sys.argv[1])
except:
  exit(1)

sid = stdin_data.get('session_id', '')
tpath = stdin_data.get('transcript_path', '')

if not sid or not tpath:
  exit(1)

api_key = os.environ.get('OPENROUTER_API_KEY') or os.environ.get('ANTHROPIC_AUTH_TOKEN')
if not api_key:
  exit(1)

# 状态文件
tmpdir = os.environ.get('TMPDIR', '/tmp')
sf = f"{tmpdir}/claude-openrouter-cost-{sid}.json"

# 加载已保存的状态
state = {'seen_ids': [], 'total_cost': 0, 'total_cache_discount': 0, 'last_provider': '', 'last_model': ''}
if os.path.exists(sf):
  try:
    with open(sf) as f:
      state = json.load(f)
  except:
    pass

# 从 transcript 提取新的 gen-id
if os.path.exists(tpath):
  try:
    with open(tpath) as f:
      content = f.read()

    import re
    gen_ids = sorted(set(re.findall(r'"id":"(gen-[^"]*)"', content)))

    for gid in gen_ids:
      if gid in state['seen_ids']:
        continue

      # 调用 generation API
      try:
        result = subprocess.run(
          ['curl', '-s', '--max-time', '3',
           '-H', f'Authorization: Bearer {api_key}',
           f'https://openrouter.ai/api/v1/generation?id={gid}'],
          capture_output=True, text=True, timeout=4
        )

        if result.returncode != 0:
          continue

        r = json.loads(result.stdout)
        data = r.get('data', {})

        gc = data.get('total_cost', 0)
        gch = data.get('cache_discount', 0)
        gp = data.get('provider_name', '')
        gm = data.get('model', '')

        state['total_cost'] += gc
        state['total_cache_discount'] += gch
        if gp:
          state['last_provider'] = gp
        if gm:
          state['last_model'] = gm

        state['seen_ids'].append(gid)
      except:
        pass
  except:
    pass

# 保存状态
try:
  with open(sf, 'w') as f:
    json.dump(state, f)
except:
  pass

# 输出
if state['last_provider'] and state['last_model']:
  model = state['last_model'].split('/')[-1]  # 去掉前缀
  model = re.sub(r'-\d+$', '', model)  # 去掉版本号
  print(f"{state['last_provider']}: {model} - ${state['total_cost']:.4f} - cache: ${state['total_cache_discount']:.2f}")
PYEOF
}

# ===== 主逻辑 =====
# 从 stdin 读取数据
INPUT=$(cat 2>/dev/null || true)

# 获取余额
BALANCE=$(get_balance <<<"$(python3 << 'PYEOF'
import json, sys
try:
  d = json.loads(sys.argv[1])
  import subprocess, os
  resp = subprocess.run(
    ['curl', '-s', '--max-time', '2',
     '-H', f'Authorization: Bearer {os.environ.get("OPENROUTER_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN")}',
     'https://openrouter.ai/api/v1/key'],
    capture_output=True, text=True
  )
  print(resp.stdout)
except:
  pass
PYEOF
)")

# 获取会话成本
SESSION=$(get_session_cost "$INPUT" 2>/dev/null || echo "")

# 组建输出
OUTPUT=""
if [[ -n "$SESSION" ]]; then
  OUTPUT="$SESSION"
  [[ -n "$BALANCE" ]] && OUTPUT="$OUTPUT | 💰 $BALANCE"
elif [[ -n "$BALANCE" ]]; then
  OUTPUT="💰 $BALANCE"
fi

# 输出为 JSON
if [[ -n "$OUTPUT" ]]; then
  printf '{"label":"%s"}' "$OUTPUT"
else
  printf '{"label":"⚙️ Loading..."}'
fi

exit 0
