#!/usr/bin/env bats
# Tests for common.sh — shared functions used by all hooks

setup() {
    source /Users/admin/projects/claude-code-hooks/scripts/common.sh 2>/dev/null || true
}

# Test 1: _log_jsonl function exists
@test "common.sh exports _log_jsonl" {
    declare -f _log_jsonl >/dev/null
}

# Test 2: _cchooks_error function exists
@test "common.sh exports _cchooks_error" {
    declare -f _cchooks_error >/dev/null
}

# Test 3: _safe_source_conf function exists
@test "common.sh exports _safe_source_conf" {
    declare -f _safe_source_conf >/dev/null
}

# Test 4: _json_get_value function exists
@test "common.sh exports _json_get_value" {
    declare -f _json_get_value >/dev/null
}

# Test 5: common.sh loads platform-shim
@test "common.sh loads platform-shim" {
    declare -f _date_iso >/dev/null
}

# Test 6: common.sh sets CCHOOKS_TMPDIR
@test "common.sh sets CCHOOKS_TMPDIR" {
    [ -n "$CCHOOKS_TMPDIR" ]
}
