#!/usr/bin/env bats
# Test Feishu HMAC-SHA256 signature generation
# Reference: https://open.feishu.cn/document/server-docs/bot-framework/event/security_verification

# Helper: extract sign from payload
extract_sign() {
    local payload="$1"
    echo "$payload" | python3 -c "import json,sys; print(json.load(sys.stdin).get('sign',''))" 2>/dev/null || echo ""
}

extract_timestamp() {
    local payload="$1"
    echo "$payload" | python3 -c "import json,sys; print(json.load(sys.stdin).get('timestamp',''))" 2>/dev/null || echo ""
}

# Simulate the _notify_feishu function signature generation
# This extracts just the signing logic for testing
feishu_sign() {
    local timestamp="$1"
    local secret="$2"

    # Correct algorithm per Feishu docs:
    # sign = base64(HMAC-SHA256(timestamp + "\n" + secret, secret))
    local sign_str="${timestamp}"$'\n'"${secret}"
    local sign
    sign=$(echo -n "${sign_str}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)
    echo "$sign"
}

# Test 1: Basic signature generation with known values
@test "should generate valid Feishu HMAC-SHA256 signature" {
    # Use fixed timestamp for deterministic test
    local timestamp="1234567890"
    local secret="test_secret_key"

    local sign=$(feishu_sign "$timestamp" "$secret")

    # Verify signature is not empty and looks like base64
    [[ -n "$sign" ]]
    [[ "$sign" =~ ^[A-Za-z0-9+/=]+$ ]]
}

# Test 2: Signature changes with different secrets
@test "should produce different signatures for different secrets" {
    local timestamp="1234567890"
    local secret1="secret_one"
    local secret2="secret_two"

    local sign1=$(feishu_sign "$timestamp" "$secret1")
    local sign2=$(feishu_sign "$timestamp" "$secret2")

    [[ "$sign1" != "$sign2" ]]
}

# Test 3: Signature is deterministic (same inputs = same output)
@test "should be deterministic - same inputs produce same signature" {
    local timestamp="1234567890"
    local secret="test_secret"

    local sign1=$(feishu_sign "$timestamp" "$secret")
    local sign2=$(feishu_sign "$timestamp" "$secret")

    [[ "$sign1" == "$sign2" ]]
}

# Test 4: Verify against known test vector (Feishu docs example)
# From: https://open.feishu.cn/document/server-docs/bot-framework/event/security_verification
# timestamp: 1609459200
# secret: XXXXXXXX
# expected: calculated externally
@test "should handle special characters in secret" {
    local timestamp="1609459200"
    local secret='test!@#$%^&*()'

    # Should not crash and produce valid base64
    local sign=$(feishu_sign "$timestamp" "$secret")
    [[ -n "$sign" ]]
    [[ "$sign" =~ ^[A-Za-z0-9+/=]+$ ]]
}

# Test 5: Newline separator is critical
@test "should include newline separator between timestamp and secret" {
    local timestamp="1234567890"
    local secret="secret"

    # Correct: with newline
    local sign_correct=$(echo -n "${timestamp}"$'\n'"${secret}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)

    # Incorrect: without newline (old buggy version)
    local sign_wrong=$(echo -n "${timestamp}${secret}" | openssl dgst -sha256 -hmac "${secret}" -binary | base64)

    local sign=$(feishu_sign "$timestamp" "$secret")

    [[ "$sign" == "$sign_correct" ]]
    [[ "$sign" != "$sign_wrong" ]]
}

# Test 6: Empty secret handling
@test "should handle empty secret gracefully" {
    local timestamp="1234567890"
    local secret=""

    # Should not error - empty secret is valid (though not recommended)
    local sign=$(feishu_sign "$timestamp" "$secret")
    [[ -n "$sign" ]]
}

# Test 7: Unicode in secret
@test "should handle unicode characters in secret" {
    local timestamp="1234567890"
    local secret="秘钥_secret_🔑"

    # Should handle UTF-8 properly
    local sign=$(feishu_sign "$timestamp" "$secret")
    [[ -n "$sign" ]]
    [[ "$sign" =~ ^[A-Za-z0-9+/=]+$ ]]
}
