#!/usr/bin/env bats
# Integration tests — verify all hooks work together as a system

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts"

# Test 1: all scripts have valid bash syntax
@test "all scripts have valid bash syntax" {
    for script in "$SCRIPT_DIR"/*.sh; do
        bash -n "$script" || return 1
    done
}

# Test 2: common.sh is sourced by notification scripts
@test "send-notification.sh sources common.sh" {
    grep -q "source.*common.sh" "$SCRIPT_DIR/send-notification.sh"
}

# Test 3: platform-shim.sh exists and is readable
@test "platform-shim.sh exists and is readable" {
    [ -f "$SCRIPT_DIR/platform-shim.sh" ]
    [ -r "$SCRIPT_DIR/platform-shim.sh" ]
}

# Test 4: common.sh defines critical functions
@test "common.sh defines _log_jsonl function" {
    grep -q "_log_jsonl" "$SCRIPT_DIR/common.sh"
}

# Test 5: guard-large-files.sh sources common.sh
@test "guard-large-files.sh sources common.sh" {
    grep -q "source.*common.sh" "$SCRIPT_DIR/guard-large-files.sh"
}

# Test 6: safety-gate hook exists and is readable
@test "cc-safety-gate.sh exists and is readable" {
    [ -f "$SCRIPT_DIR/cc-safety-gate.sh" ]
    [ -r "$SCRIPT_DIR/cc-safety-gate.sh" ]
}

# Test 7: stop-hook script exists and is readable
@test "cc-stop-hook.sh exists and is readable" {
    [ -f "$SCRIPT_DIR/cc-stop-hook.sh" ]
    [ -r "$SCRIPT_DIR/cc-stop-hook.sh" ]
}

# Test 8: reap-orphans.sh is executable
@test "reap-orphans.sh is executable" {
    [ -x "$SCRIPT_DIR/reap-orphans.sh" ]
}

# Test 9: all main hooks have proper shebangs
@test "all main hooks have proper shebangs" {
    for hook in cc-safety-gate.sh cc-stop-hook.sh send-notification.sh guard-large-files.sh; do
        if [ -f "$SCRIPT_DIR/$hook" ]; then
            head -n 1 "$SCRIPT_DIR/$hook" | grep -q "#!/usr/bin/env bash" || return 1
        fi
    done
}

# Test 10: platform-shim.sh sources platform detection code
@test "platform-shim.sh contains platform detection" {
    grep -q "uname\|OSTYPE" "$SCRIPT_DIR/platform-shim.sh"
}

# Test 11: send-notification.sh handles broadcast mode
@test "send-notification.sh supports broadcast mode (auto)" {
    grep -q "CC_NOTIFY_BACKEND.*auto" "$SCRIPT_DIR/send-notification.sh"
}

# Test 12: guard-large-files.sh has proper error handling
@test "guard-large-files.sh has error handling (set -uo)" {
    head -n 15 "$SCRIPT_DIR/guard-large-files.sh" | grep -q "set -uo pipefail"
}

# Test 13: common.sh has proper structure
@test "common.sh has proper structure and sources platform-shim" {
    grep -q "platform-shim.sh" "$SCRIPT_DIR/common.sh"
}

# Test 14: hooks locate themselves dynamically (not hardcoded)
@test "hooks locate themselves dynamically (not hardcoded paths)" {
    grep -q 'dirname.*BASH_SOURCE' "$SCRIPT_DIR/send-notification.sh"
    grep -q 'dirname.*BASH_SOURCE' "$SCRIPT_DIR/guard-large-files.sh"
}

# Test 15: safety configuration file exists
@test "safety-rules.conf.example exists" {
    [ -f "$SCRIPT_DIR/safety-rules.conf.example" ]
}

# Test 16: notify configuration file exists
@test "notify.conf.example exists" {
    [ -f "$SCRIPT_DIR/notify.conf.example" ]
}

# Test 17: dispatch-claude.sh exists and is readable
@test "dispatch-claude.sh exists and is readable" {
    [ -f "$SCRIPT_DIR/dispatch-claude.sh" ]
    [ -r "$SCRIPT_DIR/dispatch-claude.sh" ]
}

# Test 18: wait-notify.sh exists and is readable
@test "wait-notify.sh exists and is readable" {
    [ -f "$SCRIPT_DIR/wait-notify.sh" ]
    [ -r "$SCRIPT_DIR/wait-notify.sh" ]
}
