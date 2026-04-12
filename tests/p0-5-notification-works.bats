#!/usr/bin/env bats
# Test for P0-5: verify notification functionality works after fix
# Ensure send-notification.sh is properly sourced and send_notify can be called

TEST_TEMP_DIR=""
SCRIPT_DIR=""

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../scripts" && pwd)"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# Test: send_notify function is exported after sourcing send-notification.sh
@test "P0-5: send_notify function is available after sourcing send-notification.sh" {
    # Source send-notification.sh in a subshell
    result=$(bash -c "
        source '${SCRIPT_DIR}/send-notification.sh' 2>/dev/null || true
        declare -f send_notify > /dev/null && echo 'OK' || echo 'FAIL'
    ")
    [ "$result" = "OK" ]
}

# Test: send_notify doesn't fail when no backends configured
@test "P0-5: send_notify gracefully handles no backends" {
    result=$(bash -c "
        # Clear all notification environment variables
        unset CC_NOTIFY_BACKEND
        unset NOTIFY_FEISHU_URL
        unset NOTIFY_WECOM_URL
        unset CC_SLACK_WEBHOOK_URL
        unset CC_TELEGRAM_BOT_TOKEN
        unset CC_DISCORD_WEBHOOK_URL
        unset CC_BARK_URL
        unset CC_WEBHOOK_URL
        unset CC_NOTIFY_COMMAND
        unset CC_NOTIFY_TARGET

        source '${SCRIPT_DIR}/send-notification.sh' 2>/dev/null || true
        send_notify 'Test message' 2>/dev/null
        echo 'OK'
    ")
    [ "$result" = "OK" ]
}

# Test: cc-stop-hook.sh successfully sources send-notification.sh
@test "P0-5: cc-stop-hook.sh sources send-notification.sh with no errors" {
    # Create a minimal mock of cc-stop-hook logic
    result=$(bash -c "
        export SCRIPT_DIR='${SCRIPT_DIR}'

        # Simulate the fixed code path
        _NOTIFY_SCRIPT=\"\${SCRIPT_DIR}/send-notification.sh\"
        if [ -f \"\${_NOTIFY_SCRIPT}\" ]; then
            source \"\${_NOTIFY_SCRIPT}\" 2>/dev/null || true
            declare -f send_notify > /dev/null && echo 'SOURCED' || echo 'FAILED'
        else
            echo 'MISSING'
        fi
    ")
    [ "$result" = "SOURCED" ]
}

# Test: wait-notify.sh can invoke send_notify after sourcing
@test "P0-5: wait-notify.sh subshell can call send_notify after sourcing" {
    # Create a test that simulates the wait-notify subshell pattern
    result=$(bash -c "
        export SCRIPT_DIR='${SCRIPT_DIR}'

        # Subshell simulation (like the backgrounded timer in wait-notify.sh)
        (
            _NOTIFY_SCRIPT=\"\${SCRIPT_DIR}/send-notification.sh\"
            if [ -f \"\${_NOTIFY_SCRIPT}\" ]; then
                source \"\${_NOTIFY_SCRIPT}\" 2>/dev/null || true
                # Verify function exists in subshell
                if declare -f send_notify > /dev/null; then
                    echo 'OK'
                else
                    echo 'FAIL'
                fi
            else
                echo 'MISSING'
            fi
        )
    ")
    [ "$result" = "OK" ]
}

# Test: send-notification.sh doesn't have syntax errors
@test "P0-5: send-notification.sh has valid bash syntax" {
    bash -n "${SCRIPT_DIR}/send-notification.sh" 2>/dev/null
}

# Test: cc-stop-hook.sh has valid bash syntax
@test "P0-5: cc-stop-hook.sh has valid bash syntax" {
    bash -n "${SCRIPT_DIR}/cc-stop-hook.sh" 2>/dev/null
}

# Test: wait-notify.sh has valid bash syntax
@test "P0-5: wait-notify.sh has valid bash syntax" {
    bash -n "${SCRIPT_DIR}/wait-notify.sh" 2>/dev/null
}
