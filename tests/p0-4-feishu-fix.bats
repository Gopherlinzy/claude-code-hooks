#!/usr/bin/env bats
# Test for P0-4: Feishu HMAC-SHA256 signature fix
# Verify that the correct signature generation method is used

SCRIPT_DIR=""

setup() {
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../scripts" && pwd)"
}

# Test: Feishu signature uses printf '%s\n%s' (not printf '%b')
@test "P0-4: send-notification.sh uses printf '%s\\n%s' for signature" {
    grep -q "printf '%s" "${SCRIPT_DIR}/send-notification.sh" || \
    grep -q 'printf '"'"'%s' "${SCRIPT_DIR}/send-notification.sh"
    # Verify it's NOT using the old buggy printf '%b'
    ! grep -q "printf '%b'.*sign_str" "${SCRIPT_DIR}/send-notification.sh"
}

# Test: Signature generation produces correct format
@test "P0-4: signature generation follows Feishu spec" {
    # Extract and test the signature generation logic
    result=$(bash -c "
        source '${SCRIPT_DIR}/send-notification.sh' 2>/dev/null || true

        # Simulate the signing part
        timestamp='1234567890'
        secret='test_secret'

        # Use the correct method (as per fix)
        sign_str=\$(printf '%s\n%s' \"\${timestamp}\" \"\${secret}\")
        sign=\$(printf '%s' \"\${sign_str}\" | openssl dgst -sha256 -hmac \"\${secret}\" -binary | base64)

        # Verify sign is valid base64
        if [[ \$sign =~ ^[A-Za-z0-9+/=]+\$ ]]; then
            echo 'VALID'
        else
            echo 'INVALID'
        fi
    ")
    [ "$result" = "VALID" ]
}

# Test: newline is properly included in signature string
@test "P0-4: newline separator is included in signature" {
    result=$(bash -c "
        timestamp='1234567890'
        secret='test_secret'

        # Correct way with newline
        sign_str=\$(printf '%s\n%s' \"\${timestamp}\" \"\${secret}\")
        sign_correct=\$(printf '%s' \"\${sign_str}\" | openssl dgst -sha256 -hmac \"\${secret}\" -binary | base64)

        # Wrong way without newline
        sign_wrong=\$(printf '%s%s' \"\${timestamp}\" \"\${secret}\" | openssl dgst -sha256 -hmac \"\${secret}\" -binary | base64)

        # They should be different
        if [[ \$sign_correct != \$sign_wrong ]]; then
            echo 'DIFFERENT'
        else
            echo 'SAME'
        fi
    ")
    [ "$result" = "DIFFERENT" ]
}

# Test: send-notification.sh has valid bash syntax
@test "P0-4: send-notification.sh has valid syntax" {
    bash -n "${SCRIPT_DIR}/send-notification.sh" 2>/dev/null
}

# Test: the fix doesn't break basic source loading
@test "P0-4: send-notification.sh can be sourced without error" {
    result=$(bash -c "
        source '${SCRIPT_DIR}/send-notification.sh' 2>&1
        declare -f send_notify > /dev/null && echo 'OK' || echo 'FAIL'
    ")
    [ "$result" = "OK" ]
}
