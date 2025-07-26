#!/bin/bash
# =============================================================================
# Unit Tests for error-handling.sh
# Tests for error logging, handling modes, and cleanup functions
# =============================================================================

set -euo pipefail

# Get script directory for sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the test framework
source "$SCRIPT_DIR/shell-test-framework.sh"

# Source the library under test (disable strict mode temporarily)
set +e
source "$PROJECT_ROOT/lib/error-handling.sh"
set -e

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    # Create temporary error log file
    TEST_ERROR_LOG=$(mktemp)
    export ERROR_LOG_FILE="$TEST_ERROR_LOG"
    
    # Reset error counters
    ERROR_COUNT=0
    WARNING_COUNT=0
    LAST_ERROR=""
    ERROR_CONTEXT=""
    ERROR_STACK=()
    
    # Set safe defaults
    export ERROR_HANDLING_MODE="$ERROR_MODE_RESILIENT"
    export ERROR_NOTIFICATION_ENABLED="false"
    export ERROR_CLEANUP_ENABLED="true"
}

teardown_test_environment() {
    # Clean up temporary files
    [[ -f "$TEST_ERROR_LOG" ]] && rm -f "$TEST_ERROR_LOG"
    
    # Reset error handling to default
    export ERROR_HANDLING_MODE="$ERROR_MODE_STRICT"
    export ERROR_LOG_FILE="/tmp/GeuseMaker-errors.log"
}

# =============================================================================
# ERROR MODE CONSTANTS TESTS
# =============================================================================

test_error_mode_constants_defined() {
    test_start "error mode constants are properly defined"
    
    assert_equals "strict" "$ERROR_MODE_STRICT" "ERROR_MODE_STRICT should be 'strict'"
    assert_equals "resilient" "$ERROR_MODE_RESILIENT" "ERROR_MODE_RESILIENT should be 'resilient'"
    assert_equals "interactive" "$ERROR_MODE_INTERACTIVE" "ERROR_MODE_INTERACTIVE should be 'interactive'"
}

test_default_configuration_values() {
    test_start "default configuration values are set correctly"
    
    # Reset to defaults by unsetting variables
    unset ERROR_HANDLING_MODE ERROR_LOG_FILE ERROR_NOTIFICATION_ENABLED ERROR_CLEANUP_ENABLED
    source "$PROJECT_ROOT/lib/error-handling.sh"
    
    assert_equals "$ERROR_MODE_STRICT" "$ERROR_HANDLING_MODE" "Default mode should be strict"
    assert_equals "/tmp/GeuseMaker-errors.log" "$ERROR_LOG_FILE" "Default log file should be set"
    assert_equals "false" "$ERROR_NOTIFICATION_ENABLED" "Notifications should be disabled by default"
    assert_equals "true" "$ERROR_CLEANUP_ENABLED" "Cleanup should be enabled by default"
}

# =============================================================================
# ERROR INITIALIZATION TESTS
# =============================================================================

test_init_error_handling_strict_mode() {
    test_start "init_error_handling sets up strict mode correctly"
    
    init_error_handling "$ERROR_MODE_STRICT" "$TEST_ERROR_LOG"
    
    assert_equals "$ERROR_MODE_STRICT" "$ERROR_HANDLING_MODE" "Mode should be set to strict"
    assert_equals "$TEST_ERROR_LOG" "$ERROR_LOG_FILE" "Log file should be set correctly"
    assert_file_exists "$TEST_ERROR_LOG" "Error log file should be created"
}

test_init_error_handling_resilient_mode() {
    test_start "init_error_handling sets up resilient mode correctly"
    
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    assert_equals "$ERROR_MODE_RESILIENT" "$ERROR_HANDLING_MODE" "Mode should be set to resilient"
    assert_file_exists "$TEST_ERROR_LOG" "Error log file should be created"
}

test_init_error_handling_creates_log_file() {
    test_start "init_error_handling creates and initializes log file"
    
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    assert_file_exists "$TEST_ERROR_LOG" "Log file should exist"
    
    local log_content
    log_content=$(cat "$TEST_ERROR_LOG")
    
    assert_contains "$log_content" "Error Log Initialized" "Log should contain initialization message"
    assert_contains "$log_content" "PID: $$" "Log should contain process ID"
    assert_contains "$log_content" "Mode: $ERROR_MODE_RESILIENT" "Log should contain mode information"
}

# =============================================================================
# ERROR LOGGING FUNCTION TESTS
# =============================================================================

test_log_error_basic_functionality() {
    test_start "log_error function logs errors correctly"
    
    setup_test_environment
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    local test_message="Test error message"
    local output
    output=$(log_error "$test_message" 2>&1)
    
    assert_contains "$output" "[ERROR]" "Output should contain [ERROR] tag"
    assert_contains "$output" "$test_message" "Output should contain the error message"
    
    # Check that error was logged to file
    local log_content
    log_content=$(cat "$TEST_ERROR_LOG")
    assert_contains "$log_content" "ERROR: $test_message" "Log file should contain the error"
    
    # Check error counters
    assert_equals "1" "$ERROR_COUNT" "Error count should be incremented"
    assert_equals "$test_message" "$LAST_ERROR" "Last error should be set"
}

test_log_error_with_context() {
    test_start "log_error function handles context correctly"
    
    setup_test_environment
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    local test_message="Test error with context"
    local test_context="deployment phase"
    local output
    output=$(log_error "$test_message" "$test_context" 2>&1)
    
    assert_contains "$output" "$test_message" "Output should contain error message"
    assert_contains "$output" "Context: $test_context" "Output should contain context"
    
    assert_equals "$test_context" "$ERROR_CONTEXT" "Error context should be set"
}

test_log_warning_functionality() {
    test_start "log_warning function works correctly"
    
    setup_test_environment
    
    # Check if log_warning function exists
    if declare -f log_warning >/dev/null 2>&1; then
        local test_message="Test warning message"
        local output
        output=$(log_warning "$test_message" 2>&1)
        
        assert_contains "$output" "$test_message" "Output should contain warning message"
    else
        test_skip "log_warning function not found in error-handling.sh"
    fi
}

# =============================================================================
# ERROR STACK TESTS
# =============================================================================

test_error_stack_functionality() {
    test_start "error stack tracks multiple errors"
    
    setup_test_environment
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    # Log multiple errors
    log_error "First error" >/dev/null 2>&1
    log_error "Second error" >/dev/null 2>&1
    log_error "Third error" >/dev/null 2>&1
    
    # Check error count
    assert_equals "3" "$ERROR_COUNT" "Error count should be 3"
    
    # Check that error stack has entries (basic check)
    if [[ "${#ERROR_STACK[@]}" -eq 3 ]]; then
        test_pass
    else
        test_fail "Error stack should have 3 entries, has ${#ERROR_STACK[@]}"
    fi
}

# =============================================================================
# COLOR CODE FALLBACK TESTS
# =============================================================================

test_color_codes_fallback() {
    test_start "color codes have fallback definitions"
    
    # Temporarily unset color variables to test fallback
    local original_red="$RED"
    unset RED GREEN YELLOW BLUE PURPLE CYAN NC
    
    # Re-source the error handling library
    source "$PROJECT_ROOT/lib/error-handling.sh"
    
    assert_not_empty "$RED" "RED color should be defined as fallback"
    assert_not_empty "$GREEN" "GREEN color should be defined as fallback"
    assert_not_empty "$NC" "NC color should be defined as fallback"
    
    # Restore original value
    RED="$original_red"
}

test_color_codes_not_redefined() {
    test_start "color codes are not redefined if already set"
    
    # Set a custom RED value
    local custom_red='\033[1;91m'
    RED="$custom_red"
    
    # Re-source the error handling library
    source "$PROJECT_ROOT/lib/error-handling.sh"
    
    assert_equals "$custom_red" "$RED" "RED color should not be overridden"
}

# =============================================================================
# CONFIGURATION TESTS
# =============================================================================

test_error_notification_disabled_by_default() {
    test_start "error notifications are disabled by default"
    
    setup_test_environment
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    assert_equals "false" "$ERROR_NOTIFICATION_ENABLED" "Notifications should be disabled"
}

test_error_cleanup_enabled_by_default() {
    test_start "error cleanup is enabled by default"
    
    setup_test_environment
    
    assert_equals "true" "$ERROR_CLEANUP_ENABLED" "Cleanup should be enabled by default"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_log_error_empty_message() {
    test_start "log_error handles empty message gracefully"
    
    setup_test_environment
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    local output
    output=$(log_error "" 2>&1)
    
    assert_contains "$output" "[ERROR]" "Should still show error tag with empty message"
}

test_log_error_special_characters() {
    test_start "log_error handles special characters in message"
    
    setup_test_environment
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    local special_message="Error with $pecial ch@rs & symbols!"
    local output
    output=$(log_error "$special_message" 2>&1)
    
    assert_contains "$output" "$special_message" "Should handle special characters in error message"
}

test_multiple_init_calls() {
    test_start "multiple init_error_handling calls work correctly"
    
    setup_test_environment
    
    # Call init multiple times
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    init_error_handling "$ERROR_MODE_STRICT" "$TEST_ERROR_LOG"
    
    assert_equals "$ERROR_MODE_STRICT" "$ERROR_HANDLING_MODE" "Mode should be updated to strict"
    assert_file_exists "$TEST_ERROR_LOG" "Log file should still exist"
}

# =============================================================================
# FILE HANDLING TESTS
# =============================================================================

test_error_log_file_permissions() {
    test_start "error log file has correct permissions"
    
    setup_test_environment
    init_error_handling "$ERROR_MODE_RESILIENT" "$TEST_ERROR_LOG"
    
    if [[ -f "$TEST_ERROR_LOG" ]]; then
        # Check if file is readable and writable
        if [[ -r "$TEST_ERROR_LOG" && -w "$TEST_ERROR_LOG" ]]; then
            test_pass
        else
            test_fail "Error log file should be readable and writable"
        fi
    else
        test_fail "Error log file should exist"
    fi
}

test_error_log_file_invalid_path() {
    test_start "error handling gracefully handles invalid log file path"
    
    local invalid_path="/nonexistent/directory/error.log"
    
    # This should not crash the script
    if init_error_handling "$ERROR_MODE_RESILIENT" "$invalid_path" 2>/dev/null; then
        test_skip "System allows creation of files in nonexistent directories"
    else
        # Check that it fails gracefully without crashing
        test_pass
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    test_init "test-error-handling.sh"
    
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