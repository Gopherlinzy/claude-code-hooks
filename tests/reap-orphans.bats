#!/usr/bin/env bats
# Tests for reap-orphans.sh — orphan process reaping script

SCRIPT_DIR="/Users/admin/projects/claude-code-hooks/scripts"

setup() {
    # 创建临时目录用于测试
    export TEST_META_DIR="$(mktemp -d)"
    export CCHOOKS_TMPDIR="${TEST_META_DIR}"
}

teardown() {
    # 清理临时目录
    rm -rf "${TEST_META_DIR}" 2>/dev/null || true
}

# Test 1: reap-orphans should not exit on syntax errors (set -e removed)
@test "reap-orphans should have set -uo pipefail (not set -e)" {
    grep -q "set -uo pipefail" "${SCRIPT_DIR}/reap-orphans.sh"
    ! grep -q "set -euo pipefail" "${SCRIPT_DIR}/reap-orphans.sh"
}

# Test 2: reap-orphans should source common.sh
@test "reap-orphans sources common.sh" {
    grep -q "source.*common.sh" "${SCRIPT_DIR}/reap-orphans.sh"
}

# Test 3: reap-orphans should have trap ERR for error handling
@test "reap-orphans has trap ERR for error handling" {
    grep -q "trap.*ERR" "${SCRIPT_DIR}/reap-orphans.sh"
}

# Test 4: reap-orphans bash syntax check
@test "reap-orphans.sh has valid bash syntax" {
    bash -n "${SCRIPT_DIR}/reap-orphans.sh"
}

# Test 5: reap-orphans should continue processing after non-existent PIDs
@test "reap-orphans continues after error without set -e" {
    # Create a simple test meta file with fake PID
    mkdir -p "${TEST_META_DIR}"
    cat > "${TEST_META_DIR}/test123.meta" <<'EOF'
{"pid": 999999, "start_epoch": 1000}
EOF

    # Run reap-orphans in subshell with our test dir
    run bash -c "
        REAP_TIMEOUT=0
        CCHOOKS_TMPDIR='${TEST_META_DIR}'
        source '${SCRIPT_DIR}/reap-orphans.sh'
    " 2>&1

    # Should not fail (exit 0) even with non-existent PID
    [ $status -eq 0 ]
}

# Test 6: reap-orphans should handle errors in kill commands
@test "reap-orphans handles kill errors gracefully" {
    grep -E "(kill.*\|\|.*true|kill.*2>/dev/null)" "${SCRIPT_DIR}/reap-orphans.sh"
}

# Test 7: reap-orphans should handle errors in find commands
@test "reap-orphans handles find errors gracefully" {
    grep -E "(find.*\|\|.*true|find.*2>/dev/null)" "${SCRIPT_DIR}/reap-orphans.sh"
}

# Test 8: reap-orphans should handle errors in git commands
@test "reap-orphans handles git errors gracefully" {
    grep -E "(git.*\|\|.*true|git.*2>/dev/null)" "${SCRIPT_DIR}/reap-orphans.sh"
}
