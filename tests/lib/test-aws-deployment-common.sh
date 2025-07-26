#!/bin/bash
# =============================================================================
# Unit Tests for aws-deployment-common.sh
# Tests for logging functions, context detection, and utility functions
# =============================================================================

set -euo pipefail

# Get script directory for sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the test framework
source "$SCRIPT_DIR/shell-test-framework.sh"

# Source the library under test
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    # Create temporary files for capturing output
    TEST_LOG_FILE=$(mktemp)
    TEST_ERR_FILE=$(mktemp)
    
    # Mock external dependencies for testing
    mock_function "curl" "echo 'mocked-instance-id'"
    mock_function "whoami" "echo 'testuser'"
    mock_function "hostname" "echo 'testhost'"  
}

teardown_test_environment() {
    # Clean up temporary files
    [[ -f "$TEST_LOG_FILE" ]] && rm -f "$TEST_LOG_FILE"
    [[ -f "$TEST_ERR_FILE" ]] && rm -f "$TEST_ERR_FILE"
    
    # Restore mocked functions
    restore_function "curl"
    restore_function "whoami"
    restore_function "hostname"
}

# =============================================================================
# TIMESTAMP FUNCTION TESTS
# =============================================================================

test_get_timestamp_format() {
    test_start "get_timestamp returns proper format"
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Check format: YYYY-MM-DD HH:MM:SS
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        test_pass
    else
        test_fail "Timestamp format incorrect. Got: '$timestamp'"
    fi
}

test_get_timestamp_not_empty() {
    test_start "get_timestamp returns non-empty value"
    
    local timestamp
    timestamp=$(get_timestamp)
    
    assert_not_empty "$timestamp" "Timestamp should not be empty"
}

# =============================================================================
# CONTEXT DETECTION TESTS
# =============================================================================

test_get_log_context_local() {
    test_start "get_log_context returns local context when not on AWS"
    
    # Mock curl to fail (simulating no AWS metadata service)
    mock_function "curl" "return 1"
    
    local context
    context=$(get_log_context)
    
    assert_contains "$context" "[LOCAL:" "Context should contain LOCAL"
    assert_contains "$context" "testuser" "Context should contain username"
    assert_contains "$context" "testhost" "Context should contain hostname"
    
    restore_function "curl"
}

test_get_log_context_aws() {
    test_start "get_log_context returns AWS context when on instance"
    
    # Mock curl to succeed with instance metadata
    mock_function "curl" 'if [[ "$*" == *"instance-id"* ]]; then echo "i-1234567890abcdef0"; elif [[ "$*" == *"instance-type"* ]]; then echo "g4dn.xlarge"; else return 0; fi'
    
    local context
    context=$(get_log_context)
    
    assert_contains "$context" "[INSTANCE:" "Context should contain INSTANCE"
    assert_contains "$context" "i-123456" "Context should contain truncated instance ID"
    assert_contains "$context" "g4dn.xlarge" "Context should contain instance type"
    
    restore_function "curl"
}

# =============================================================================
# LOGGING FUNCTION TESTS
# =============================================================================

test_log_function_output() {
    test_start "log function produces correct output format"
    
    local test_message="Test log message"
    local output
    output=$(log "$test_message" 2>&1)
    
    assert_contains "$output" "[LOG]" "Output should contain [LOG] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "📋" "Output should contain log emoji"
}

test_error_function_output() {
    test_start "error function produces correct output format"
    
    local test_message="Test error message"
    local output
    output=$(error "$test_message" 2>&1)
    
    assert_contains "$output" "[ERROR]" "Output should contain [ERROR] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "❌" "Output should contain error emoji"
}

test_success_function_output() {
    test_start "success function produces correct output format"
    
    local test_message="Test success message"
    local output
    output=$(success "$test_message" 2>&1)
    
    assert_contains "$output" "[SUCCESS]" "Output should contain [SUCCESS] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "✅" "Output should contain success emoji"
}

test_warning_function_output() {
    test_start "warning function produces correct output format"
    
    local test_message="Test warning message"
    local output
    output=$(warning "$test_message" 2>&1)
    
    assert_contains "$output" "[WARNING]" "Output should contain [WARNING] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "⚠️" "Output should contain warning emoji"
}

test_info_function_output() {
    test_start "info function produces correct output format"
    
    local test_message="Test info message"
    local output
    output=$(info "$test_message" 2>&1)
    
    assert_contains "$output" "[INFO]" "Output should contain [INFO] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "ℹ️" "Output should contain info emoji"
}

test_step_function_output() {
    test_start "step function produces correct output format"
    
    local test_message="Test step message"
    local output
    output=$(step "$test_message" 2>&1)
    
    assert_contains "$output" "[STEP]" "Output should contain [STEP] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "🔸" "Output should contain step emoji"
}

test_progress_function_output() {
    test_start "progress function produces correct output format"
    
    local test_message="Test progress message"
    local output
    output=$(progress "$test_message" 2>&1)
    
    assert_contains "$output" "[PROGRESS]" "Output should contain [PROGRESS] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "⏳" "Output should contain progress emoji"
}

# =============================================================================
# DEPLOYMENT STATUS FUNCTION TESTS
# =============================================================================

test_deploy_start_function() {
    test_start "deploy_start function produces correct output format"
    
    local test_message="Starting deployment"
    local output
    output=$(deploy_start "$test_message" 2>&1)
    
    assert_contains "$output" "[DEPLOY-START]" "Output should contain [DEPLOY-START] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "🚀" "Output should contain rocket emoji"
    assert_contains "$output" "╔═" "Output should contain box drawing characters"
}

test_deploy_complete_function() {
    test_start "deploy_complete function produces correct output format"
    
    local test_message="Deployment completed"
    local output
    output=$(deploy_complete "$test_message" 2>&1)
    
    assert_contains "$output" "[DEPLOY-COMPLETE]" "Output should contain [DEPLOY-COMPLETE] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "🎉" "Output should contain celebration emoji"
    assert_contains "$output" "╔═" "Output should contain box drawing characters"
}

test_deploy_failed_function() {
    test_start "deploy_failed function produces correct output format"
    
    local test_message="Deployment failed"
    local output
    output=$(deploy_failed "$test_message" 2>&1)
    
    assert_contains "$output" "[DEPLOY-FAILED]" "Output should contain [DEPLOY-FAILED] tag"
    assert_contains "$output" "$test_message" "Output should contain the message"
    assert_contains "$output" "💥" "Output should contain explosion emoji"
    assert_contains "$output" "╔═" "Output should contain box drawing characters"
}

# =============================================================================
# COLOR CODE TESTS
# =============================================================================

test_color_constants_defined() {
    test_start "color constants are properly defined"
    
    assert_not_empty "$RED" "RED color constant should be defined"
    assert_not_empty "$GREEN" "GREEN color constant should be defined"
    assert_not_empty "$YELLOW" "YELLOW color constant should be defined"
    assert_not_empty "$BLUE" "BLUE color constant should be defined"
    assert_not_empty "$CYAN" "CYAN color constant should be defined"
    assert_not_empty "$NC" "NC (no color) constant should be defined"
}

test_color_codes_format() {
    test_start "color codes have correct ANSI format"
    
    assert_matches "$RED" "033.*31m" "RED should have correct ANSI code"
    assert_matches "$GREEN" "033.*32m" "GREEN should have correct ANSI code"  
    assert_matches "$NC" "033.*0m" "NC should have correct ANSI reset code"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_logging_with_empty_message() {
    test_start "logging functions handle empty messages gracefully"
    
    local output
    output=$(log "" 2>&1)
    
    assert_contains "$output" "[LOG]" "Should still show log tag with empty message"
}

test_logging_with_special_characters() {
    test_start "logging functions handle special characters"
    
    local special_message="Test with special ch@rs & symbols!"
    local output
    output=$(log "$special_message" 2>&1)
    
    assert_contains "$output" "special ch@rs" "Should handle special characters in message"
}

test_context_with_network_timeout() {
    test_start "context detection handles network timeouts gracefully"
    
    # Mock curl to timeout/fail
    mock_function "curl" "return 1"
    
    local context
    context=$(get_log_context)
    
    assert_contains "$context" "[LOCAL:" "Should fall back to local context on timeout"
    
    restore_function "curl"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    test_init "test-aws-deployment-common.sh"
    
    # Set up clean test environment
    setup_test_environment
    
    # Run all tests
    run_all_tests
    
    # Clean up
    teardown_test_environment
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi