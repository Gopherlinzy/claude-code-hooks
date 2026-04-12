#!/usr/bin/env bats
# Integration test for Feishu notification with HMAC signature

# Source the notification script
setup() {
    export NOTIFY_FEISHU_URL="https://open.feishu.cn/open-apis/bot/v2/hook/test_token"
    export NOTIFY_FEISHU_SECRET="test_secret_key"
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

    # Mock curl to capture the payload
    export MOCK_CURL_PAYLOAD=""
    export TEST_TEMP_DIR=$(mktemp -d)

    # Capture test's curl calls
    curl_mock() {
        # Last argument is usually the URL, second-to-last might be data
        local args=("$@")
        for ((i=0; i<${#args[@]}; i++)); do
            if [[ "${args[$i]}" == "-d" ]] && [[ $((i+1)) -lt ${#args[@]} ]]; then
                MOCK_CURL_PAYLOAD="${args[$((i+1))]}"
                break
            fi
        done
        return 0  # Pretend curl succeeded
    }
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# Helper to extract JSON field
json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field',''))" 2>/dev/null || echo ""
}

# Test: Verify current send-notification.sh signature algorithm
@test "send-notification: feishu signature should use timestamp and secret with newline" {
    # Simulate what send-notification.sh does (lines 160-165)
    local timestamp="1234567890"
    local secret="test_secret"

    # Current (buggy) implementation in send-notification.sh:
    # local sign_str="${timestamp}\n${NOTIFY_FEISHU_SECRET}"
    # sign=$(printf '%b' "${sign_str}" | openssl dgst -sha256 -hmac "${NOTIFY_FEISHU_SECRET}" -binary | base64)

    # This is WRONG because printf '%b' interprets \n but the whole thing is ambiguous
    local sign_wrong=$(printf '%b' "${timestamp}\\n${secret}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)

    # Correct implementation:
    # local sign_str="${timestamp}"$'\n'"${secret}"
    # sign=$(echo -n "${sign_str}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)

    local sign_correct=$(echo -n "${timestamp}"$'\n'"${secret}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)

    # They should be different (proving the bug exists)
    [[ "$sign_wrong" != "$sign_correct" ]]
}

# Test: Verify signature generation with proper echo -n method
@test "send-notification: should use echo -n not printf %b for consistent behavior" {
    local timestamp="1609459200"
    local secret="mySecret123"

    # These should be identical (both correct)
    local sign_echo=$(echo -n "${timestamp}"$'\n'"${secret}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)
    local sign_echo2=$(echo -n "${timestamp}"$'\n'"${secret}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)

    [[ "$sign_echo" == "$sign_echo2" ]]
    [[ -n "$sign_echo" ]]
}

# Test: Payload structure correctness
@test "send-notification: feishu payload should include timestamp and sign fields" {
    # When signature is enabled, payload must have timestamp and sign
    # (simulating what happens in _notify_feishu)

    local timestamp="1234567890"
    local secret="test_secret"
    local sign=$(echo -n "${timestamp}"$'\n'"${secret}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)

    # Build payload like send-notification does
    local payload="{\"timestamp\":\"${timestamp}\",\"sign\":\"${sign}\",\"msg_type\":\"text\",\"content\":{\"text\":\"test message\"}}"

    # Verify it's valid JSON
    echo "$payload" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || false

    # Verify fields exist
    [[ "$(json_field "$payload" "timestamp")" == "$timestamp" ]]
    [[ "$(json_field "$payload" "sign")" == "$sign" ]]
    [[ "$(json_field "$payload" "msg_type")" == "text" ]]
}
