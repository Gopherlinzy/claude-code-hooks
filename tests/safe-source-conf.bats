#!/usr/bin/env bats
# Test for P0-Bug-3: _safe_source_conf false positives
# Bug: 配置文件中的注释如果含有 $( 会被误判为危险，导致合法配置被拒

TEST_TEMP_DIR=""

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# Create a test version of _safe_source_conf
# This is the BUGGY version (current implementation in send-notification.sh L26-38)
_safe_source_conf_buggy() {
    local _file="$1"
    [ -f "${_file}" ] || return 0
    if grep -qF '$(' "${_file}" 2>/dev/null; then
        echo "[send-notification] WARN: ${_file##*/} contains \$( — skipping" >&2
        return 1
    fi
    if grep -qF '`' "${_file}" 2>/dev/null; then
        echo "[send-notification] WARN: ${_file##*/} contains backtick — skipping" >&2
        return 1
    fi
    source "${_file}"
}

# Fixed version: only check non-comment lines
_safe_source_conf_fixed() {
    local _file="$1"
    [ -f "${_file}" ] || return 0

    # 只检查非注释行中的危险字符
    local _tainted_lines
    _tainted_lines=$(grep -v '^\s*#' "${_file}" | grep -E '[$`]|\\(|&&|;.*eval|source\s+<' 2>/dev/null || true)

    if [ -n "$_tainted_lines" ]; then
        echo "[send-notification] WARN: Config file contains suspicious code" >&2
        return 1
    fi

    source "${_file}" || return 1
}

# Test 1: Buggy version rejects comments with $( (false positive)
@test "buggy _safe_source_conf: falsely rejects config with \$( in comment" {
    cat > "$TEST_TEMP_DIR/config.conf" << 'EOF'
# Example webhook URL (this is safe, it's a comment):
# CC_BARK_URL=https://api.day.app/$(whoami)
# Never will execute this

# Real config:
CC_BARK_URL=https://api.day.app/legitimate_key
EOF

    # Buggy version should fail
    run bash << SCRIPT
_safe_source_conf_buggy() {
    local _file="\$1"
    [ -f "\${_file}" ] || return 0
    if grep -qF '$(' "\${_file}" 2>/dev/null; then
        echo "[send-notification] WARN: \${_file##*/} contains \$( — skipping" >&2
        return 1
    fi
    source "\${_file}"
}

_safe_source_conf_buggy "$TEST_TEMP_DIR/config.conf"
SCRIPT

    [ $status -ne 0 ]  # Should fail (false positive)
}

# Test 2: Fixed version accepts comments with $( (no false positive)
@test "fixed _safe_source_conf: accepts config with \$( in comment" {
    cat > "$TEST_TEMP_DIR/config.conf" << 'EOF'
# Example webhook URL (this is safe, it's a comment):
# CC_BARK_URL=https://api.day.app/$(whoami)
# Never will execute this

# Real config:
CC_BARK_URL=https://api.day.app/legitimate_key
EOF

    # Fixed version should succeed
    run bash -c "source '$SCRIPT_DIR/platform-shim.sh' 2>/dev/null; _safe_source_conf_fixed '$TEST_TEMP_DIR/config.conf' && echo 'OK'"
    [ $status -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# Test 3: Fixed version still rejects actual code injection
@test "fixed _safe_source_conf: rejects real code injection in active code" {
    cat > "$TEST_TEMP_DIR/config.conf" << 'EOF'
# Safe comment with $( syntax
# Example: $(whoami)

# Dangerous line:
CC_SECRET=$(whoami)
EOF

    # Should fail (real injection)
    run bash -c "source '$SCRIPT_DIR/platform-shim.sh' 2>/dev/null; _safe_source_conf_fixed '$TEST_TEMP_DIR/config.conf'"
    [ $status -ne 0 ]  # Should fail
    [[ "$output" == *"suspicious"* ]] || [[ "$output" == *"code"* ]]
}

# Test 4: Fixed version accepts backtick in comment
@test "fixed _safe_source_conf: accepts backtick in comment" {
    cat > "$TEST_TEMP_DIR/config.conf" << 'EOF'
# This is a comment with backtick example: `whoami`
# Should not be rejected

CC_MY_TOKEN=valid_token_here
EOF

    run bash -c "source '$SCRIPT_DIR/platform-shim.sh' 2>/dev/null; _safe_source_conf_fixed '$TEST_TEMP_DIR/config.conf' && echo 'OK'"
    [ $status -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# Test 5: Fixed version rejects backtick in active code
@test "fixed _safe_source_conf: rejects backtick code injection in active code" {
    cat > "$TEST_TEMP_DIR/config.conf" << 'EOF'
# Safe comment
CC_USER=`whoami`
EOF

    run bash -c "source '$SCRIPT_DIR/platform-shim.sh' 2>/dev/null; _safe_source_conf_fixed '$TEST_TEMP_DIR/config.conf'"
    [ $status -ne 0 ]  # Should fail
    [[ "$output" == *"suspicious"* ]]
}

# Test 6: Valid config with special URLs passes
@test "fixed _safe_source_conf: accepts valid URLs with special characters" {
    cat > "$TEST_TEMP_DIR/config.conf" << 'EOF'
NOTIFY_FEISHU_URL=https://open.feishu.cn/open-apis/bot/v2/hook/token
CC_BARK_URL=https://api.day.app/key123
CC_TELEGRAM_BOT_TOKEN=123456:ABC-DEF-GHI
EOF

    run bash -c "source '$SCRIPT_DIR/platform-shim.sh' 2>/dev/null; _safe_source_conf_fixed '$TEST_TEMP_DIR/config.conf' && echo 'OK'"
    [ $status -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# Test 7: Empty or missing file handled gracefully
@test "fixed _safe_source_conf: handles missing file gracefully" {
    run bash -c "source '$SCRIPT_DIR/platform-shim.sh' 2>/dev/null; _safe_source_conf_fixed '/nonexistent/file.conf'"
    [ $status -eq 0 ]  # Should succeed (no-op)
}
