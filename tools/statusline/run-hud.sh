#!/usr/bin/env bash
# run-hud.sh — 启动 claude-hud 并传入 --extra-cmd 调用 openrouter-statusline.js
#
# 核心问题：--extra-cmd 在 Windows 上由 cmd.exe 执行，不认识 MSYS 路径（/c/Users/...）
# 解决方案：检测到 Windows 时，将路径转换为原生格式（C:/Users/...）
#
# 用法：
#   settings.json → "command": "bash ~/.claude/scripts/claude-hooks/statusline/run-hud.sh"

set -e

# ── 1. 找到 claude-hud 插件目录（取最新版本）──────────────────────────────────
PLUGIN_BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/claude-hud/claude-hud"
plugin_dir=$(
  ls -d "${PLUGIN_BASE}/"*/ 2>/dev/null \
  | awk -F/ '{ print $(NF-1) "\t" $0 }' \
  | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
  | tail -1 | cut -f2-
)

if [ -z "$plugin_dir" ]; then
  echo '{"label":"claude-hud not found"}' >&2
  exit 1
fi

# ── 2. 定位 openrouter-statusline.js ─────────────────────────────────────────
STATUSLINE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/claude-hooks/statusline/openrouter-statusline.js"

# ── 3. Windows 路径转换 ───────────────────────────────────────────────────────
# 检测 Windows（Git Bash / MSYS2 / Cygwin）
is_windows() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac
}

# 将 MSYS 路径 /c/Users/... 转为 Windows 原生路径 C:/Users/...
# 这是 --extra-cmd 能被 cmd.exe 识别的关键
to_win_path() {
  echo "$1" | sed 's|^/\([a-zA-Z]\)/|\U\1:/|'
}

if is_windows; then
  # Windows：主进程用 node.exe 绝对路径（避免 PATH 问题）
  NODE_BIN=$(which node 2>/dev/null || echo "node")

  win_plugin_dir=$(to_win_path "$plugin_dir")
  win_statusline=$(to_win_path "$STATUSLINE")

  exec "$NODE_BIN" "${win_plugin_dir}dist/index.js" \
    --extra-cmd "node \"${win_statusline}\""
else
  # macOS / Linux：直接用 node
  exec node "${plugin_dir}dist/index.js" \
    --extra-cmd "node \"${STATUSLINE}\""
fi
