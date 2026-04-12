#!/usr/bin/env bats
# Tests for send-notification.sh — notification broadcast mode (auto-discovery)

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts"
TEST_TEMP_DIR=""

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
    export CCHOOKS_TMPDIR="${TEST_TEMP_DIR}"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# Test 1: send_notify with auto backend discovers no backends gracefully
@test "send_notify gracefully handles auto mode with no backends" {
    run bash << 'SCRIPT'
export CC_NOTIFY_BACKEND="auto"
source /Users/admin/projects/claude-code-hooks/scripts/send-notification.sh
send_notify "test message"
SCRIPT
    [ $status -eq 0 ]
}

# Test 2: send_notify with empty message returns 0
@test "send_notify returns 0 for empty message" {
    run bash << 'SCRIPT'
source /Users/admin/projects/claude-code-hooks/scripts/send-notification.sh
send_notify ""
SCRIPT
    [ $status -eq 0 ]
}

# Test 3: send_notify with no backends configured returns 0
@test "send_notify returns success with no backends" {
    run bash << 'SCRIPT'
export CC_NOTIFY_BACKEND="none"
source /Users/admin/projects/claude-code-hooks/scripts/send-notification.sh
send_notify "test notification"
SCRIPT
    [ $status -eq 0 ]
}

# Test 4: send-notification.sh script exists and is readable
@test "send-notification.sh script exists and is readable" {
    [ -f "$SCRIPT_DIR/send-notification.sh" ]
    [ -r "$SCRIPT_DIR/send-notification.sh" ]
}

# Test 5: send-notification.sh has proper shebang
@test "send-notification.sh has proper shebang" {
    head -n 1 "$SCRIPT_DIR/send-notification.sh" | grep -q "#!/usr/bin/env bash"
}

# Test 6: send-notification.sh sources common.sh
@test "send-notification.sh sources common.sh" {
    grep -q "source.*common.sh" "$SCRIPT_DIR/send-notification.sh"
}
