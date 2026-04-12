#!/usr/bin/env bats
# Test for cc-safety-gate.sh - P0 Bug-2: Missing blacklist patterns

# Source the safety gate
SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts"

# Helper to create Hook JSON
make_hook_json() {
    local cmd="$1"
    python3 << EOF
import json
print(json.dumps({'tool_input': {'command': '''$cmd'''}}))
EOF
}

# Test dangerous patterns that should be blocked
@test "should block node -e code execution" {
    # Bug-2: cc-safety-gate.sh missing node -e detection
    local json=$(make_hook_json "node -e \"console.log('evil')\"")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]  # Exit 0 = deny
    [[ "$output" == *"deny"* ]]
}

@test "should block node --eval code execution" {
    local json=$(make_hook_json "node --eval \"process.exit(1)\"")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "should block perl -e code execution" {
    local json=$(make_hook_json "perl -e system(id)")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "should block python -c code execution" {
    local json=$(make_hook_json "python3 -c \"import subprocess; subprocess.run(['ls'])\"")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "should block nc -e reverse shell" {
    local json=$(make_hook_json "nc -e /bin/bash 127.0.0.1 9999")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "should block chmod +s SUID escalation" {
    local json=$(make_hook_json "chmod +s /tmp/binary")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "should block find -exec bash" {
    local json=$(make_hook_json "find . -exec bash -c 'whoami' \\;")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "should allow safe commands like echo" {
    local json=$(make_hook_json "echo hello")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" != *"deny"* ]]
}

@test "should allow safe commands like ls" {
    local json=$(make_hook_json "ls -la")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" != *"deny"* ]]
}

@test "should allow safe npm commands" {
    local json=$(make_hook_json "npm install")
    run bash -c "echo '$json' | bash '$SCRIPT_DIR/cc-safety-gate.sh'"
    [ $status -eq 0 ]
    [[ "$output" != *"deny"* ]]
}
