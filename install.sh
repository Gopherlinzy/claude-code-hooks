#!/usr/bin/env bash
# install.sh — Claude Code Hooks installer (v2)
# Usage:
#   Interactive:     ./install.sh
#   Non-interactive: ./install.sh --non-interactive | -y
#   Update scripts:  ./install.sh --update
#   Uninstall:       ./install.sh --uninstall [--purge]
#   Status:          ./install.sh --status
#   From curl:       curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash
set -euo pipefail

# ─── 颜色 & 日志 ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✅${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠️${NC}  $*"; }
err()   { echo -e "${RED}❌${NC} $*" >&2; }
step()  { echo -e "\n${CYAN}${BOLD}[$1/$TOTAL_STEPS]${NC} ${BOLD}$2${NC}"; }

# ─── 全局常量 ───
TOTAL_STEPS=6
REPO_URL="https://github.com/Gopherlinzy/claude-code-hooks.git"
INSTALL_DIR="${HOME}/.claude/scripts/claude-hooks"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CONF_FILE="${INSTALL_DIR}/notify.conf"
LOCKDIR="${CLAUDE_DIR}/.settings-lock"

# ─── 运行时状态 ───
SUBCMD=""
PURGE=false
NON_INTERACTIVE=false
BACKUP_FILE=""

# ─── 自动检测 stdin 是否为终端（curl|bash 模式下 stdin 是管道）───
# fd3 作为统一的用户输入源：正常模式 → stdin，curl|bash 模式 → /dev/tty
if [ -t 0 ]; then
  # 正常终端模式：stdin 就是终端
  exec 3<&0
elif [ -c /dev/tty ]; then
  # curl|bash 模式：stdin 被管道占用，用 /dev/tty 恢复交互
  exec 3</dev/tty
else
  # 无终端可用（CI/Docker 等），强制非交互
  NON_INTERACTIVE=true
  exec 3</dev/null
fi
# 模块开关（默认全开）
MODULE_STOP=true
MODULE_SAFETY=true
MODULE_GUARD=true
MODULE_NOTIFY=true
MODULE_CANCEL=true
MODULE_STATUSLINE=false  # 默认关闭，用户可选

# 检测脚本目录（curl|bash 模式时可能为空/无效）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""

# ─── 解析参数 ───
for arg in "$@"; do
  case "$arg" in
    --non-interactive|-y) NON_INTERACTIVE=true ;;
    --update)             SUBCMD="update" ;;
    --uninstall)          SUBCMD="uninstall" ;;
    --purge)              PURGE=true ;;
    --status)             SUBCMD="status" ;;
    --help|-h)            SUBCMD="help" ;;
  esac
done

# 验证 --purge 只与 --uninstall 配合使用
if [ "$PURGE" = true ] && [ "$SUBCMD" != "uninstall" ]; then
  err "--purge can only be used with --uninstall"
  exit 1
fi

# ═══════════════════════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════════════════════

# 跨平台文件大小
file_size() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || wc -c < "$1" | tr -d ' '
}

# mkdir 原子锁（跨平台，替代 flock）
acquire_lock() {
  mkdir -p "$CLAUDE_DIR"
  local attempts=0
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ $attempts -gt 10 ]; then
      err "Could not acquire settings lock after 10 attempts."
      err "If no other install is running, remove: $LOCKDIR"
      exit 1
    fi
    sleep 1
  done
}

release_lock() {
  rm -rf "$LOCKDIR" 2>/dev/null || true
}

# 备份 settings.json（时间戳后缀，幂等）
backup_settings() {
  if [ -f "$SETTINGS_FILE" ]; then
    BACKUP_FILE="${SETTINGS_FILE}.bak.$(date +%s)"
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    ok "Backed up settings.json → $(basename "$BACKUP_FILE")"
  fi
}

# 保留最近 5 份备份，清理旧的
cleanup_old_backups() {
  local backups
  # shellcheck disable=SC2207
  backups=($(ls -t "${SETTINGS_FILE}.bak."* 2>/dev/null)) || return 0
  if [ "${#backups[@]}" -gt 5 ]; then
    for old in "${backups[@]:5}"; do
      rm -f "$old"
    done
  fi
}

# 回滚到最近备份
rollback_settings() {
  if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SETTINGS_FILE"
    ok "Rolled back settings.json to $(basename "$BACKUP_FILE")"
  else
    warn "No backup file available for rollback."
    return 1
  fi
}

# ─── 全局清理资源追踪 & 统一 trap 管理 ───
_CLEANUP_DIRS=()
_HAD_ERROR=false
_ERROR_HANDLED=false

_on_error_handler() {
  [ "$_ERROR_HANDLED" = true ] && return
  _ERROR_HANDLED=true
  echo ""
  err "An error occurred. Installation may be incomplete."
  if [ -n "${BACKUP_FILE:-}" ] && [ -f "$BACKUP_FILE" ]; then
    warn "Your settings.json backup: $BACKUP_FILE"
    if [ "$NON_INTERACTIVE" = false ] && { true <&3; } 2>/dev/null; then
      echo -n "  Rollback settings.json to backup? [Y/n] "
      read -r _ROLLBACK_CHOICE <&3 || true
      if [[ ! "${_ROLLBACK_CHOICE:-}" =~ ^[Nn]$ ]]; then
        rollback_settings
      fi
    else
      warn "No interactive terminal — auto-rolling back."
      rollback_settings
    fi
  fi
}

cleanup_all() {
  for d in "${_CLEANUP_DIRS[@]}"; do
    rm -rf "$d" 2>/dev/null || true
  done
  release_lock
  if [ "$_HAD_ERROR" = true ]; then
    _on_error_handler
  fi
}

trap '_HAD_ERROR=true' ERR
trap 'cleanup_all' EXIT
trap 'echo ""; warn "Interrupted."; _HAD_ERROR=true; exit 130' INT TERM

# ─── 生成 hooks-patch.json（基于当前模块开关状态）───
generate_hooks_patch() {
  local output="$1"

  # Platform detection: Windows (Git Bash/MSYS/Cygwin) needs "bash " prefix for .sh files
  local cmd_prefix=""
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) cmd_prefix="bash " ;;
  esac

  MOD_STOP="${MODULE_STOP}" \
  MOD_SAFETY="${MODULE_SAFETY}" \
  MOD_GUARD="${MODULE_GUARD}" \
  MOD_NOTIFY="${MODULE_NOTIFY}" \
  MOD_CANCEL="${MODULE_CANCEL}" \
  MOD_STATUSLINE="${MODULE_STATUSLINE}" \
  INSTALL_DIR_ENV="${INSTALL_DIR}" \
  CMD_PREFIX="${cmd_prefix}" \
  PATCH_OUTPUT="${output}" \
  node -e "
    const fs = require('fs');
    const patch = { hooks: {} };
    const dir = process.env.INSTALL_DIR_ENV;
    const prefix = process.env.CMD_PREFIX || '';
    const cmd = (script) => prefix + dir + '/statusline/' + script;
    const cmdHook = (script) => prefix + dir + '/' + script;  // hooks 不在 statusline 子目录
    const add = (event, entry) => {
      if (!patch.hooks[event]) patch.hooks[event] = [];
      patch.hooks[event].push(entry);
    };
    if (process.env.MOD_STOP === 'true')
      add('Stop', { matcher: '*', hooks: [{ type: 'command', command: cmdHook('cc-stop-hook.sh'), timeout: 15 }] });
    if (process.env.MOD_SAFETY === 'true')
      add('PreToolUse', { matcher: 'Bash', hooks: [{ type: 'command', command: cmdHook('cc-safety-gate.sh'), timeout: 5 }] });
    if (process.env.MOD_GUARD === 'true')
      add('PreToolUse', { matcher: 'Read|Edit|Write', hooks: [{ type: 'command', command: cmdHook('guard-large-files.sh'), timeout: 5 }] });
    if (process.env.MOD_NOTIFY === 'true') {
      add('Notification', { matcher: '*', hooks: [{ type: 'command', command: cmdHook('wait-notify.sh'), timeout: 5 }] });
      add('PermissionRequest', { matcher: '*', hooks: [{ type: 'command', command: cmdHook('wait-notify.sh'), timeout: 5 }] });
    }
    if (process.env.MOD_CANCEL === 'true') {
      add('PostToolUse', { matcher: '*', hooks: [{ type: 'command', command: cmdHook('cancel-wait.sh'), timeout: 3 }] });
      add('UserPromptSubmit', { matcher: '*', hooks: [{ type: 'command', command: cmdHook('cancel-wait.sh'), timeout: 3 }] });
    }
    fs.writeFileSync(process.env.PATCH_OUTPUT, JSON.stringify(patch, null, 2) + '\n', 'utf8');
  "
}

# ─── 配置 statusLine（如果启用）───
inject_statusline() {
  if [ "${MODULE_STATUSLINE}" != "true" ]; then
    return 0
  fi

  local tmp_output="${SETTINGS_FILE}.tmp.$$"
  local node_exe="${NODE_EXE:-$(which node 2>/dev/null)}"

  if [ -z "$node_exe" ]; then
    warn "Node.js not found — skipping statusline configuration"
    return 1
  fi

  # 构建脚本路径（支持 macOS 和 Windows）
  local cmd_prefix=""
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) cmd_prefix="bash " ;;
  esac
  local statusline_script="${cmd_prefix}${INSTALL_DIR}/statusline/openrouter-status.sh"

  # 生成 statusLine patch
  STATUSLINE_CMD="${statusline_script}" \
  NODE_EXE="${node_exe}" \
  INSTALL_DIR_ENV="${INSTALL_DIR}" \
  PATCH_OUTPUT="${SETTINGS_FILE}.statusline-patch.$$" \
  "$node_exe" -e "
    const fs = require('fs');
    const path = require('path');

    // 读取当前 settings.json
    const settingsPath = '${SETTINGS_FILE}';
    let current = {};
    if (fs.existsSync(settingsPath)) {
      try {
        current = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
      } catch (e) {
        console.error('Error reading settings.json:', e.message);
        process.exit(1);
      }
    }

    // 构建现有 statusLine 的备份并更新
    if (current.statusLine) {
      // 备份现有 statusLine 配置
      current._statusLine_backup = current.statusLine;
    }

    // 获取 node 路径和脚本路径
    const nodeExe = '${NODE_EXE}';
    const installDir = '${INSTALL_DIR_ENV}';
    const statuslineScript = '${statusline_script}';

    // 构建完整的 statusLine 命令（支持 macOS 和 Windows）
    const pluginFinder = \`bash -c 'plugin_dir=\$(ls -d \"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print \$(NF-1) \"\\\\t\" \$(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"\${nodeExe}\" \"\${plugin_dir}dist/index.js\" --extra-cmd \"${statusline_script}\"'\`;

    current.statusLine = {
      command: pluginFinder,
      type: 'command'
    };

    fs.writeFileSync(process.env.PATCH_OUTPUT, JSON.stringify(current, null, 2) + '\\n', 'utf8');
  " 2>/dev/null || {
    warn "Failed to configure statusline — skipping"
    return 1
  }

  # 验证生成的文件
  if [ ! -f "${SETTINGS_FILE}.statusline-patch.$$" ]; then
    warn "Statusline patch generation failed"
    return 1
  fi

  # 备份原文件
  if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak.statusline.$$"
  fi

  # 用新的替换
  mv "${SETTINGS_FILE}.statusline-patch.$$" "$SETTINGS_FILE" || {
    warn "Failed to apply statusline configuration"
    [ -f "$SETTINGS_FILE.bak.statusline.$$" ] && mv "$SETTINGS_FILE.bak.statusline.$$" "$SETTINGS_FILE"
    return 1
  }

  rm -f "$SETTINGS_FILE.bak.statusline.$$"
  ok "Statusline configured with OpenRouter monitor"
}

# ─── 将 patch 深度合并进 settings.json（原子写入）───
inject_hooks() {
  local tmp_output="${SETTINGS_FILE}.tmp.$$"
  local patch_file="${INSTALL_DIR}/hooks-patch.json"

  # 确保 settings.json 存在
  if [ ! -f "$SETTINGS_FILE" ]; then
    mkdir -p "$CLAUDE_DIR"
    echo '{}' > "$SETTINGS_FILE"
    info "Created empty settings.json"
  fi

  # 生成 patch
  generate_hooks_patch "$patch_file"

  # 深度合并 → tmp
  if ! node "${INSTALL_DIR}/merge-hooks.js" "$SETTINGS_FILE" "$patch_file" "$tmp_output" 2>/dev/null; then
    err "Merge script failed — settings.json unchanged."
    rm -f "$tmp_output" "$patch_file"
    return 1
  fi

  # 二次验证 JSON 合法性
  if ! TMP_PATH="${tmp_output}" node -e "
      JSON.parse(require('fs').readFileSync(process.env.TMP_PATH,'utf8'))
    " 2>/dev/null; then
    err "Merged JSON validation failed — aborting."
    rm -f "$tmp_output" "$patch_file"
    return 1
  fi

  # 交互模式：展示 diff，等待确认
  if [ "$NON_INTERACTIVE" = false ]; then
    echo ""
    echo -e "  ${BOLD}Pending changes to ~/.claude/settings.json:${NC}"
    if command -v diff &>/dev/null && [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
      diff -u "$BACKUP_FILE" "$tmp_output" 2>/dev/null | tail -n +3 | head -60 || true
    fi
    echo ""
    echo -n "  Apply these changes? [Y/n] "
    read -r _CONFIRM_INJ <&3 || true
    if [[ "${_CONFIRM_INJ:-}" =~ ^[Nn]$ ]]; then
      rm -f "$tmp_output" "$patch_file"
      warn "Hooks injection skipped."
      return 0
    fi
  fi

  # 原子移入
  mv "$tmp_output" "$SETTINGS_FILE"
  rm -f "$patch_file"
  ok "settings.json updated successfully."
}

# ─── Webhook 连通性测试 ───
validate_webhook() {
  local url="$1"
  [ -z "$url" ] && return 0
  info "Testing webhook connectivity..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 --max-time 10 \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    -d '{"msg_type":"text","content":{"text":"🦞 claude-code-hooks connectivity test"}}' \
    2>/dev/null) || true
  case "$http_code" in
    200|204) ok "Webhook test passed (HTTP ${http_code})" ;;
    000)     warn "Could not reach webhook URL — check network or URL" ;;
    *)       warn "Webhook returned HTTP ${http_code} — may need verification" ;;
  esac
}

# ═══════════════════════════════════════════════════════════
# 子命令
# ═══════════════════════════════════════════════════════════

cmd_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  (none)                Run interactive 6-step installer"
  echo "  --non-interactive|-y  Skip prompts, use defaults"
  echo "  --status              Show current installation status"
  echo "  --update              Update scripts only, keep config"
  echo "  --uninstall           Remove hook scripts and hooks from settings.json"
  echo "  --uninstall --purge   Also delete notify.conf and install directory"
  echo "  --help|-h             Show this help"
  echo ""
  echo "curl | bash install:"
  echo "  curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/install.sh | bash"
}

cmd_status() {
  echo -e "\n${BOLD}🦞 Claude Code Hooks — Status${NC}\n"

  if [ -d "$INSTALL_DIR" ]; then
    ok "Installed at ${INSTALL_DIR}"
    local sh_count
    sh_count=$(find "${INSTALL_DIR}" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
    info "${sh_count} hook script(s) found"
  else
    err "Not installed (${INSTALL_DIR} does not exist)"
    return 1
  fi

  if [ -f "$SETTINGS_FILE" ]; then
    SETTINGS_FILE_ENV="${SETTINGS_FILE}" INSTALL_DIR_ENV="${INSTALL_DIR}" \
    node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync(process.env.SETTINGS_FILE_ENV, 'utf8'));
      const hooks = s.hooks || {};
      const dir = process.env.INSTALL_DIR_ENV;
      let ours = 0, total = 0;
      for (const entries of Object.values(hooks)) {
        for (const entry of entries) {
          for (const h of (entry.hooks || [])) {
            total++;
            if (h.command && h.command.startsWith(dir)) ours++;
          }
        }
      }
      console.log('  \u2139\ufe0f  Hooks in settings.json: ' + total + ' total, ' + ours + ' from claude-code-hooks');
    " 2>/dev/null || warn "Could not parse settings.json"
  else
    warn "settings.json not found"
  fi

  if [ -f "$CONF_FILE" ]; then
    local _conf_channel
    _conf_channel=$(grep -m1 '^CC_NOTIFY_CHANNEL=' "$CONF_FILE" 2>/dev/null | sed 's/^[^=]*=//; s/^"//; s/"$//' || echo "unknown")
    ok "notify.conf: channel=${_conf_channel:-unknown}"
  else
    warn "notify.conf not found"
  fi

  local backup_count
  backup_count=$(find "$(dirname "${SETTINGS_FILE}")" -maxdepth 1 -name 'settings.json.bak.*' 2>/dev/null | wc -l | tr -d ' ')
  info "${backup_count} backup(s) of settings.json found"
}

cmd_update() {
  echo -e "\n${BOLD}🦞 Claude Code Hooks — Update${NC}\n"

  if [ ! -d "$INSTALL_DIR" ]; then
    err "No existing installation found at ${INSTALL_DIR}. Run install first."
    exit 1
  fi

  # 备份 settings.json
  acquire_lock
  backup_settings

  # 克隆最新代码
  local _update_tmp
  _update_tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  _CLEANUP_DIRS+=("${_update_tmp}")

  info "Fetching latest from GitHub..."
  git clone --depth 1 --quiet "$REPO_URL" "${_update_tmp}/repo"

  # 覆盖脚本（保留 notify.conf）
  local updated=0
  for f in "${_update_tmp}/repo/scripts"/*.sh; do
    [ -f "$f" ] || continue
    cp "$f" "${INSTALL_DIR}/$(basename "$f")"
    updated=$((updated + 1))
  done
  chmod +x "${INSTALL_DIR}"/*.sh
  ok "Updated ${updated} hook scripts"

  # 更新工具文件
  if [ -f "${_update_tmp}/repo/tools/merge-hooks.js" ]; then
    cp "${_update_tmp}/repo/tools/merge-hooks.js" "${INSTALL_DIR}/merge-hooks.js"
    ok "Updated merge-hooks.js"
  fi

  if [ -f "${_update_tmp}/repo/tools/select-modules.js" ]; then
    cp "${_update_tmp}/repo/tools/select-modules.js" "${INSTALL_DIR}/select-modules.js"
    ok "Updated select-modules.js (TUI)"
  fi

  rm -rf "${_update_tmp}"

  # 重新注入 hooks（使用默认 MODULE_* 值）
  if [ "$NON_INTERACTIVE" = false ]; then
    echo -n "  Re-inject hooks into settings.json with default config? [Y/n] "
    read -r _REINJECT <&3 || true
    if [[ ! "${_REINJECT:-}" =~ ^[Nn]$ ]]; then
      inject_hooks
    fi
  else
    # 非交互模式：自动重注入（使用默认 MODULE_* 值）
    info "Re-injecting hooks with default config (non-interactive mode)..."
    inject_hooks
  fi

  cleanup_old_backups
  release_lock

  echo -e "\n${GREEN}${BOLD}✅ Update complete!${NC}"
  echo "  Restart Claude Code to activate changes."
}

cmd_uninstall() {
  echo -e "\n${BOLD}🦞 Claude Code Hooks — Uninstall${NC}\n"

  if [ ! -d "$INSTALL_DIR" ]; then
    warn "No installation found at ${INSTALL_DIR}"
    return 0
  fi

  if [ "$NON_INTERACTIVE" = false ] && [ "$PURGE" = false ]; then
    echo -n "  Remove claude-code-hooks? [y/N] "
    read -r _CONFIRM_UNINSTALL <&3 || true
    if [[ ! "${_CONFIRM_UNINSTALL:-}" =~ ^[Yy]$ ]]; then
      info "Uninstall cancelled."
      return 0
    fi
  fi

  # 备份 settings.json
  acquire_lock
  backup_settings

  # 精准移除 settings.json 中属于本工具的 hooks 条目
  if [ -f "$SETTINGS_FILE" ]; then
    info "Removing claude-code-hooks entries from settings.json..."
    local _rm_tmp="${SETTINGS_FILE}.tmp.$$"
    SETTINGS_PATH="${SETTINGS_FILE}" \
    INSTALL_DIR_ENV="${INSTALL_DIR}" \
    TMP_OUTPUT="${_rm_tmp}" \
    node -e "
      const fs = require('fs');
      const s = JSON.parse(fs.readFileSync(process.env.SETTINGS_PATH, 'utf8'));
      const dir = process.env.INSTALL_DIR_ENV;
      if (s.hooks) {
        for (const event of Object.keys(s.hooks)) {
          s.hooks[event] = s.hooks[event].map(entry => {
            entry.hooks = (entry.hooks || []).filter(
              h => !h.command || !h.command.startsWith(dir)
            );
            return entry;
          }).filter(entry => entry.hooks.length > 0);
          if (s.hooks[event].length === 0) delete s.hooks[event];
        }
        if (Object.keys(s.hooks).length === 0) delete s.hooks;
      }
      fs.writeFileSync(process.env.TMP_OUTPUT, JSON.stringify(s, null, 2) + '\n', 'utf8');
    " 2>/dev/null

    if [ -f "$_rm_tmp" ]; then
      if TMP_PATH="${_rm_tmp}" node -e "
          JSON.parse(require('fs').readFileSync(process.env.TMP_PATH,'utf8'))
        " 2>/dev/null; then
        mv "$_rm_tmp" "$SETTINGS_FILE"
        ok "Removed claude-code-hooks entries from settings.json"
      else
        err "Validation failed — settings.json unchanged."
        rm -f "$_rm_tmp"
      fi
    fi
  fi

  # 删除脚本文件
  rm -f "${INSTALL_DIR}"/*.sh "${INSTALL_DIR}/merge-hooks.js" 2>/dev/null || true
  ok "Removed hook scripts"

  # --purge：删除整个目录（含 notify.conf）
  if [ "$PURGE" = true ]; then
    rm -rf "${INSTALL_DIR}"
    ok "Purged ${INSTALL_DIR} (including notify.conf)"
  else
    info "Kept ${INSTALL_DIR}/notify.conf (use --purge to delete it)"
  fi

  cleanup_old_backups
  release_lock

  echo -e "\n${GREEN}${BOLD}✅ Uninstall complete!${NC}"
  [ -n "$BACKUP_FILE" ] && info "Backup: $BACKUP_FILE"
}

# ═══════════════════════════════════════════════════════════
# 主安装流程（6 步）
# ═══════════════════════════════════════════════════════════

run_install() {
  echo -e "\n${BOLD}🦞 Claude Code Hooks Installer${NC}\n"

  # ── Step 1: 环境检查 ─────────────────────────────────────
  step 1 "Checking environment..."

  if ! command -v node &>/dev/null; then
    err "Node.js is required but not found."
    err "Claude Code depends on Node.js — please install it first."
    exit 1
  fi
  ok "Node.js $(node -v)"

  if ! command -v git &>/dev/null; then
    err "git is required but not found. Please install git first."
    exit 1
  fi
  ok "git $(git --version | awk '{print $3}')"

  if command -v claude &>/dev/null; then
    ok "Claude Code CLI found"
  else
    warn "claude CLI not found — hooks won't work until Claude Code is installed"
  fi

  if [ -d "$CLAUDE_DIR" ]; then
    ok "Found ~/.claude"
  else
    info "~/.claude not found — creating it"
    mkdir -p "$CLAUDE_DIR"
  fi

  if [ -d "$INSTALL_DIR" ] && ls "${INSTALL_DIR}"/*.sh &>/dev/null 2>&1; then
    info "Existing installation detected at ${INSTALL_DIR}"
  fi

  # ── Step 2: 安装脚本 ─────────────────────────────────────
  step 2 "Installing hook scripts to ${INSTALL_DIR}..."

  mkdir -p "${INSTALL_DIR}"

  local SRC_DIR=""
  local _install_tmp=""
  # 检测运行方式：本地 repo 还是 curl|bash
  if [ -n "$SCRIPT_DIR" ] && [ -d "${SCRIPT_DIR}/scripts" ] && [ -f "${SCRIPT_DIR}/scripts/cc-stop-hook.sh" ]; then
    SRC_DIR="${SCRIPT_DIR}/scripts"
    info "Source: local repo at ${SCRIPT_DIR}"
  else
    _install_tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    _CLEANUP_DIRS+=("${_install_tmp}")
    info "Cloning from GitHub..."
    git clone --depth 1 --quiet "$REPO_URL" "${_install_tmp}/repo"
    SRC_DIR="${_install_tmp}/repo/scripts"
  fi

  local COPIED=0
  for f in "${SRC_DIR}"/*.sh; do
    [ -f "$f" ] || continue
    cp "$f" "${INSTALL_DIR}/$(basename "$f")"
    COPIED=$((COPIED + 1))
  done
  chmod +x "${INSTALL_DIR}"/*.sh

  # 复制示例配置（不覆盖已有文件）
  for conf in "${SRC_DIR}"/*.example; do
    [ -f "$conf" ] || continue
    local dest="${INSTALL_DIR}/$(basename "$conf")"
    [ -f "$dest" ] || cp "$conf" "$dest"
  done

  # 安装 merge 工具
  local _tools_src=""
  if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/tools/merge-hooks.js" ]; then
    _tools_src="${SCRIPT_DIR}/tools/merge-hooks.js"
  elif [ -n "$_install_tmp" ] && [ -f "${_install_tmp}/repo/tools/merge-hooks.js" ]; then
    _tools_src="${_install_tmp}/repo/tools/merge-hooks.js"
  fi

  if [ -n "$_tools_src" ]; then
    cp "$_tools_src" "${INSTALL_DIR}/merge-hooks.js"
  fi

  # 安装 select-modules.js
  local _select_src=""
  if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/tools/select-modules.js" ]; then
    _select_src="${SCRIPT_DIR}/tools/select-modules.js"
  elif [ -n "$_install_tmp" ] && [ -f "${_install_tmp}/repo/tools/select-modules.js" ]; then
    _select_src="${_install_tmp}/repo/tools/select-modules.js"
  fi
  if [ -n "$_select_src" ]; then
    cp "$_select_src" "${INSTALL_DIR}/select-modules.js"
  fi

  ok "Installed ${COPIED} hook scripts + tools"

  # ── Step 3: Hooks 模块选择 ────────────────────────────────
  step 3 "Select hook modules to enable..."

  if [ "$NON_INTERACTIVE" = false ] && [ -f "${INSTALL_DIR}/select-modules.js" ]; then
    echo ""
    # 用 Node.js TUI 选择器（↑↓ 导航，空格切换，Enter 确认）
    # 不用 $() 捕获（会吞掉 TUI），改用 tmpfile 通信
    local _select_tmp="${INSTALL_DIR}/.select-result.$$"
    local _select_rc=0
    node "${INSTALL_DIR}/select-modules.js" --output "$_select_tmp" 2>/dev/null || _select_rc=$?
    
    local _selected=""
    if [ "$_select_rc" -eq 130 ]; then
      # 用户按了 Ctrl+C
      rm -f "$_select_tmp"
      warn "Module selection cancelled."
      echo -n "  Continue with all modules enabled? [Y/n] "
      read -r _CONT <&3 || true
      if [[ "${_CONT:-}" =~ ^[Nn]$ ]]; then
        info "Installation cancelled."
        exit 0
      fi
    elif [ -f "$_select_tmp" ]; then
      _selected=$(cat "$_select_tmp")
      rm -f "$_select_tmp"
    fi

    if [ -n "$_selected" ]; then
      # 解析 JSON 数组，未选中的模块设为 false
      [[ "$_selected" != *'"stop"'* ]]   && MODULE_STOP=false   && info "Disabled: Stop notification"
      [[ "$_selected" != *'"safety"'* ]] && MODULE_SAFETY=false && info "Disabled: Safety gate"
      [[ "$_selected" != *'"guard"'* ]]  && MODULE_GUARD=false  && info "Disabled: Large file guard"
      [[ "$_selected" != *'"notify"'* ]] && MODULE_NOTIFY=false && info "Disabled: Wait notification"
      [[ "$_selected" != *'"cancel"'* ]] && MODULE_CANCEL=false && info "Disabled: Cancel wait"
    fi
  elif [ "$NON_INTERACTIVE" = false ]; then
    # Fallback：无 select-modules.js 时用简单数字输入
    echo ""
    echo -e "  ${BOLD}Available modules (all hooks enabled, statusline optional):${NC}"
    echo ""
    echo -e "    1) [${GREEN}ON${NC}] Stop notification       → cc-stop-hook.sh"
    echo -e "    2) [${GREEN}ON${NC}] Safety gate (Bash)      → cc-safety-gate.sh"
    echo -e "    3) [${GREEN}ON${NC}] Large file guard        → guard-large-files.sh"
    echo -e "    4) [${GREEN}ON${NC}] Wait notification       → wait-notify.sh"
    echo -e "    5) [${GREEN}ON${NC}] Cancel wait             → cancel-wait.sh"
    echo -e "    6) [${RED}OFF${NC}] OpenRouter Credits       → statusline/openrouter-status.sh (optional)"
    echo ""
    echo -e "  Enter numbers to toggle (comma-separated), or press Enter to keep defaults:"
    echo -n "  Toggle: "
    read -r _DISABLE_INPUT <&3 || true

    if [ -n "${_DISABLE_INPUT:-}" ]; then
      IFS=',' read -ra _DISABLED_NUMS <<< "$_DISABLE_INPUT"
      for _num in "${_DISABLED_NUMS[@]}"; do
        _num="$(echo "$_num" | tr -d ' ')"
        case "$_num" in
          1) MODULE_STOP=false;   info "Disabled: Stop notification" ;;
          2) MODULE_SAFETY=false; info "Disabled: Safety gate" ;;
          3) MODULE_GUARD=false;  info "Disabled: Large file guard" ;;
          4) MODULE_NOTIFY=false; info "Disabled: Wait notification" ;;
          5) MODULE_CANCEL=false; info "Disabled: Cancel wait" ;;
          6) MODULE_STATUSLINE=true; info "Enabled: OpenRouter Credits statusline" ;;
        esac
      done
    fi
  else
    info "Non-interactive mode: all modules enabled"
  fi

  # ── Step 4: 自动注入 settings.json ───────────────────────
  step 4 "Injecting hooks into ~/.claude/settings.json..."

  if [ ! -f "${INSTALL_DIR}/merge-hooks.js" ]; then
    warn "merge-hooks.js missing — skipping auto-injection."
    warn "Add hooks manually (see README for the JSON snippet)."
  else
    acquire_lock
    backup_settings
    inject_hooks
    inject_statusline  # Configure statusline if enabled
    cleanup_old_backups
    release_lock
  fi

  # ── Step 5: 通知后端配置 ──────────────────────────────────
  step 5 "Configure notification backend..."

  local SKIP_CONF=false
  if [ -f "$CONF_FILE" ] && [ "$NON_INTERACTIVE" = false ]; then
    echo -e "  Existing notify.conf found."
    echo -n "  Overwrite? [y/N] "
    read -r _OVERWRITE <&3 || true
    if [[ ! "${_OVERWRITE:-}" =~ ^[Yy]$ ]]; then
      ok "Keeping existing notify.conf"
      SKIP_CONF=true
    fi
  fi

  if [ "$SKIP_CONF" = false ]; then
    local CC_CHANNEL CC_TARGET CC_TIMEOUT WEBHOOK_URL
    CC_TARGET="" WEBHOOK_URL="" CC_TIMEOUT=30

    if [ "$NON_INTERACTIVE" = true ]; then
      CC_CHANNEL="feishu"
    else
      echo ""
      echo -e "  ${BOLD}Notification channel:${NC}"
      echo "    1) feishu  (飞书)"
      echo "    2) wecom   (企业微信)"
      echo "    3) telegram"
      echo "    4) slack"
      echo "    5) discord"
      echo "    6) none    (skip notifications)"
      echo -n "  Choose [1-6, default=1]: "
      read -r _CH_CHOICE <&3 || true
      case "${_CH_CHOICE:-1}" in
        1) CC_CHANNEL="feishu" ;;
        2) CC_CHANNEL="wecom" ;;
        3) CC_CHANNEL="telegram" ;;
        4) CC_CHANNEL="slack" ;;
        5) CC_CHANNEL="discord" ;;
        6) CC_CHANNEL="none" ;;
        *) CC_CHANNEL="feishu" ;;
      esac

      if [ "$CC_CHANNEL" != "none" ]; then
        # 询问 Webhook URL
        case "$CC_CHANNEL" in
          feishu)   echo -n "  Feishu bot webhook URL (https://open.feishu.cn/...): " ;;
          wecom)    echo -n "  WeCom bot webhook URL (https://qyapi.weixin.qq.com/...): " ;;
          telegram) echo -n "  Telegram webhook URL: " ;;
          slack)    echo -n "  Slack webhook URL (https://hooks.slack.com/...): " ;;
          discord)  echo -n "  Discord webhook URL (https://discord.com/api/webhooks/...): " ;;
        esac
        read -r WEBHOOK_URL <&3 || true

        # 询问通知目标 ID（可选，用于某些渠道）
        case "$CC_CHANNEL" in
          feishu)   echo -n "  Feishu open_id (ou_xxx, optional): " ;;
          telegram) echo -n "  Telegram chat_id: " ;;
          slack)    echo -n "  Slack channel ID (optional): " ;;
          discord)  echo -n "  Discord channel ID (optional): " ;;
          wecom)    CC_TARGET=""; echo "" ;;
        esac
        if [ "$CC_CHANNEL" != "wecom" ]; then
          read -r CC_TARGET <&3 || true
        fi

        echo -n "  Wait timeout before notification (seconds) [30]: "
        read -r CC_TIMEOUT <&3 || true
        CC_TIMEOUT="${CC_TIMEOUT:-30}"

        # 可选连通性测试
        if [ -n "${WEBHOOK_URL:-}" ]; then
          echo -n "  Test webhook now? [Y/n] "
          read -r _TEST_WH <&3 || true
          if [[ ! "${_TEST_WH:-}" =~ ^[Nn]$ ]]; then
            validate_webhook "${WEBHOOK_URL:-}"
          fi
        fi
      fi
    fi

    # 写入 conf 文件（chmod 600，避免 history 暴露）
    local CHANNEL_UPPER
    CHANNEL_UPPER="$(echo "$CC_CHANNEL" | tr '[:lower:]' '[:upper:]')"
    cat > "$CONF_FILE" << CONF
# Claude Code Hook Notification Config
# Generated by install.sh on $(date +%Y-%m-%d)
CC_NOTIFY_CHANNEL="${CC_CHANNEL}"
CC_NOTIFY_TARGET="${CC_TARGET:-}"
CC_WAIT_NOTIFY_SECONDS=${CC_TIMEOUT:-30}
CONF

    # Webhook URL 写入（非 none 且有值时）
    if [ "$CC_CHANNEL" != "none" ] && [ -n "${WEBHOOK_URL:-}" ]; then
      echo "NOTIFY_${CHANNEL_UPPER}_URL=\"${WEBHOOK_URL}\"" >> "$CONF_FILE"
    fi

    chmod 600 "$CONF_FILE"
    ok "Created notify.conf (channel: ${CC_CHANNEL})"
  fi

  # ── Step 6: 验证 ─────────────────────────────────────────
  step 6 "Verifying installation..."

  local ERRORS=0
  for script in cc-stop-hook.sh cc-safety-gate.sh \
                guard-large-files.sh wait-notify.sh cancel-wait.sh; do
    if [ -x "${INSTALL_DIR}/${script}" ]; then
      ok "${script}"
    else
      err "${script} — missing or not executable"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # 可选脚本（不计入 ERRORS）
  for script in dispatch-claude.sh check-claude-status.sh reap-orphans.sh send-notification.sh generate-skill-index.sh; do
    if [ -x "${INSTALL_DIR}/${script}" ]; then
      ok "${script} (optional)"
    fi
  done

  # merge-hooks.js 是工具，非必须脚本
  if [ -f "${INSTALL_DIR}/merge-hooks.js" ]; then
    ok "merge-hooks.js"
  else
    warn "merge-hooks.js missing — future hook injection won't work"
  fi

  # settings.json hooks 验证
  if [ -f "$SETTINGS_FILE" ]; then
    local HOOKS_COUNT
    HOOKS_COUNT=$(SETTINGS_PATH="${SETTINGS_FILE}" node -e "
      const s = JSON.parse(require('fs').readFileSync(process.env.SETTINGS_PATH,'utf8'));
      console.log(Object.keys(s.hooks || {}).length);
    " 2>/dev/null || echo "0")
    if [ "${HOOKS_COUNT:-0}" -gt 0 ]; then
      ok "settings.json: ${HOOKS_COUNT} hook event type(s) registered"
    else
      warn "settings.json: no hooks found — injection may have been skipped"
    fi
  else
    warn "settings.json not found"
  fi

  # notify.conf 检查
  if [ -f "$CONF_FILE" ]; then
    ok "notify.conf ($(file_size "$CONF_FILE") bytes)"
  else
    warn "notify.conf not found — notifications won't work"
  fi

  # ── 结果汇总 ──────────────────────────────────────────────
  echo ""
  if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}🎉 Installation complete!${NC}"
    echo ""
    echo "  Scripts:  ${INSTALL_DIR}"
    echo "  Config:   ${CONF_FILE}"
    echo "  Settings: ${SETTINGS_FILE}"
    [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ] && \
      echo "  Backup:   ${BACKUP_FILE}"
    echo ""
    echo -e "  ${BOLD}Quick commands:${NC}"
    echo "    ./install.sh --status     Show installation status"
    echo "    ./install.sh --update     Update scripts (keep config)"
    echo "    ./install.sh --uninstall  Remove hooks (keep config)"
    echo ""
    echo "  Restart Claude Code to activate hooks."
  else
    err "Installation completed with ${ERRORS} error(s)."
    exit 1
  fi
}

# ═══════════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════════

case "$SUBCMD" in
  help)      cmd_help ;;
  status)    cmd_status ;;
  update)    cmd_update ;;
  uninstall) cmd_uninstall ;;
  *)         run_install ;;
esac
