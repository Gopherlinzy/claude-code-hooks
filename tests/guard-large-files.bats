#!/usr/bin/env bats
# Tests for guard-large-files.sh — large file detection and auto-generated file blocking

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/../scripts"
TEST_TEMP_DIR=""

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# Test 1: guard-large-files script exists and is readable
@test "guard-large-files.sh script exists and is readable" {
    [ -f "$SCRIPT_DIR/guard-large-files.sh" ]
    [ -r "$SCRIPT_DIR/guard-large-files.sh" ]
}

# Test 2: guard-large-files should pass through normal file paths
@test "guard-large-files allows normal file paths" {
    TEST_FILE="${TEST_TEMP_DIR}/normal_file.txt"
    echo "This is a small test file" > "$TEST_FILE"

    JSON_INPUT="{\"tool_input\":{\"file_path\":\"${TEST_FILE}\"}}"
    run bash << SCRIPT
source '$SCRIPT_DIR/guard-large-files.sh' << 'JSON'
$JSON_INPUT
JSON
SCRIPT
    [ $status -eq 0 ]
}

# Test 3: guard-large-files blocks auto-generated Go files
@test "guard-large-files blocks auto-generated Go files (_gen.go)" {
    TEST_FILE="${TEST_TEMP_DIR}/generated_gen.go"
    echo "// This is auto-generated" > "$TEST_FILE"

    JSON_INPUT="{\"tool_input\":{\"file_path\":\"${TEST_FILE}\"}}"
    run bash << SCRIPT
source '$SCRIPT_DIR/guard-large-files.sh' << 'JSON'
$JSON_INPUT
JSON
SCRIPT
    [ $status -eq 0 ]
    [[ $output == *"decision"*"deny"* ]]
}

# Test 4: guard-large-files blocks minified files
@test "guard-large-files blocks minified JS files" {
    TEST_FILE="${TEST_TEMP_DIR}/script.min.js"
    echo "console.log('minified');" > "$TEST_FILE"

    JSON_INPUT="{\"tool_input\":{\"file_path\":\"${TEST_FILE}\"}}"
    run bash << SCRIPT
source '$SCRIPT_DIR/guard-large-files.sh' << 'JSON'
$JSON_INPUT
JSON
SCRIPT
    [ $status -eq 0 ]
    [[ $output == *"decision"*"deny"* ]]
}

# Test 5: guard-large-files blocks node_modules paths
@test "guard-large-files blocks node_modules directory files" {
    TEST_FILE="${TEST_TEMP_DIR}/node_modules/package/index.js"
    mkdir -p "$(dirname "$TEST_FILE")"
    echo "module.exports = {};" > "$TEST_FILE"

    JSON_INPUT="{\"tool_input\":{\"file_path\":\"${TEST_FILE}\"}}"
    run bash << SCRIPT
source '$SCRIPT_DIR/guard-large-files.sh' << 'JSON'
$JSON_INPUT
JSON
SCRIPT
    [ $status -eq 0 ]
    [[ $output == *"decision"*"deny"* ]]
}

# Test 6: guard-large-files has proper shebang
@test "guard-large-files.sh has proper shebang" {
    head -n 1 "$SCRIPT_DIR/guard-large-files.sh" | grep -q "#!/usr/bin/env bash"
}

# Test 7: guard-large-files handles missing file paths gracefully
@test "guard-large-files handles missing file paths gracefully" {
    JSON_INPUT="{\"tool_input\":{}}"
    run bash << SCRIPT
source '$SCRIPT_DIR/guard-large-files.sh' << 'JSON'
$JSON_INPUT
JSON
SCRIPT
    [ $status -eq 0 ]
}
