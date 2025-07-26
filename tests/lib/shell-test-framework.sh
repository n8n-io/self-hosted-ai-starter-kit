#!/bin/bash
# =============================================================================
# Shell Unit Testing Framework
# Lightweight testing framework compatible with bash 3.x (macOS) and 4.x+ (Linux)
# =============================================================================

set -euo pipefail

# =============================================================================
# FRAMEWORK GLOBALS AND CONFIGURATION
# =============================================================================

# Color codes for output
readonly TEST_RED='\033[0;31m'
readonly TEST_GREEN='\033[0;32m'
readonly TEST_YELLOW='\033[0;33m'
readonly TEST_BLUE='\033[0;34m'
readonly TEST_CYAN='\033[0;36m'
readonly TEST_BOLD='\033[1m'
readonly TEST_NC='\033[0m'

# Test counters (using globals since bash 3.x doesn't support associative arrays)
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

# Test state
CURRENT_TEST_NAME=""
CURRENT_TEST_FILE=""
TEST_OUTPUT_FILE=""
TEST_START_TIME=""

# Framework configuration
TEST_VERBOSE="${TEST_VERBOSE:-false}"
TEST_STOP_ON_FAILURE="${TEST_STOP_ON_FAILURE:-false}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"

# =============================================================================
# CORE TESTING FUNCTIONS
# =============================================================================

# Initialize test framework
test_init() {
    local test_file="${1:-unknown}"
    CURRENT_TEST_FILE="$test_file"
    TEST_OUTPUT_FILE="/tmp/shell-test-$$-$(date +%s).log"
    TEST_START_TIME=$(date +%s)
    
    # Create test output directory
    mkdir -p "$(dirname "$TEST_OUTPUT_FILE")"
    
    echo -e "${TEST_BLUE}${TEST_BOLD}=== Shell Unit Test Framework ===${TEST_NC}"
    echo -e "${TEST_CYAN}Test file: $test_file${TEST_NC}"
    echo -e "${TEST_CYAN}Started at: $(date)${TEST_NC}"
    echo ""
}

# Clean up test framework
test_cleanup() {
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    
    echo ""
    echo -e "${TEST_BLUE}${TEST_BOLD}=== Test Results Summary ===${TEST_NC}"
    echo -e "${TEST_CYAN}Test file: $CURRENT_TEST_FILE${TEST_NC}"
    echo -e "${TEST_CYAN}Duration: ${duration}s${TEST_NC}"
    echo -e "${TEST_GREEN}Passed: $TEST_PASSED${TEST_NC}"
    echo -e "${TEST_RED}Failed: $TEST_FAILED${TEST_NC}"
    echo -e "${TEST_YELLOW}Skipped: $TEST_SKIPPED${TEST_NC}"
    echo -e "${TEST_CYAN}Total: $TEST_TOTAL${TEST_NC}"
    
    # Clean up temporary files
    if [[ -f "$TEST_OUTPUT_FILE" ]]; then
        rm -f "$TEST_OUTPUT_FILE"
    fi
    
    # Exit with error code if any tests failed
    if [[ $TEST_FAILED -gt 0 ]]; then
        exit 1
    fi
}

# Start a test case
test_start() {
    local test_name="$1"
    CURRENT_TEST_NAME="$test_name"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    
    if [[ "$TEST_VERBOSE" == "true" ]]; then
        echo -e "${TEST_CYAN}Running: $test_name${TEST_NC}"
    fi
}

# Mark test as passed
test_pass() {
    TEST_PASSED=$((TEST_PASSED + 1))
    echo -e "${TEST_GREEN}✓${TEST_NC} $CURRENT_TEST_NAME"
}

# Mark test as failed
test_fail() {
    local message="${1:-No message provided}"
    TEST_FAILED=$((TEST_FAILED + 1))
    echo -e "${TEST_RED}✗${TEST_NC} $CURRENT_TEST_NAME"
    echo -e "${TEST_RED}  Error: $message${TEST_NC}"
    
    if [[ "$TEST_STOP_ON_FAILURE" == "true" ]]; then
        test_cleanup
        exit 1
    fi
}

# Skip a test
test_skip() {
    local reason="${1:-No reason provided}"
    TEST_SKIPPED=$((TEST_SKIPPED + 1))
    echo -e "${TEST_YELLOW}○${TEST_NC} $CURRENT_TEST_NAME ${TEST_YELLOW}(skipped: $reason)${TEST_NC}"
}

# =============================================================================
# ASSERTION FUNCTIONS
# =============================================================================

# Assert that two values are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"
    
    if [[ "$expected" == "$actual" ]]; then
        test_pass
    else
        test_fail "$message. Expected: '$expected', Actual: '$actual'"
    fi
}

# Assert that two values are not equal
assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"
    
    if [[ "$expected" != "$actual" ]]; then
        test_pass
    else
        test_fail "$message. Both values are: '$expected'"
    fi
}

# Assert that a string contains a substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        test_pass
    else
        test_fail "$message. '$haystack' does not contain '$needle'"
    fi
}

# Assert that a string does not contain a substring
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        test_pass
    else
        test_fail "$message. '$haystack' contains '$needle'"
    fi
}

# Assert that a string matches a pattern
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should match pattern}"
    
    if [[ "$string" =~ $pattern ]]; then
        test_pass
    else
        test_fail "$message. '$string' does not match pattern '$pattern'"
    fi
}

# Assert that a value is empty
assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"
    
    if [[ -z "$value" ]]; then
        test_pass
    else
        test_fail "$message. Value is: '$value'"
    fi
}

# Assert that a value is not empty
assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"
    
    if [[ -n "$value" ]]; then
        test_pass
    else
        test_fail "$message. Value is empty"
    fi
}

# Assert that a file exists
assert_file_exists() {
    local file_path="$1"
    local message="${2:-File should exist}"
    
    if [[ -f "$file_path" ]]; then
        test_pass
    else
        test_fail "$message. File does not exist: '$file_path'"
    fi
}

# Assert that a directory exists
assert_dir_exists() {
    local dir_path="$1"
    local message="${2:-Directory should exist}"
    
    if [[ -d "$dir_path" ]]; then
        test_pass
    else
        test_fail "$message. Directory does not exist: '$dir_path'"
    fi
}

# Assert that a command succeeds (exit code 0)
assert_command_succeeds() {
    local command="$1"
    local message="${2:-Command should succeed}"
    
    if eval "$command" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "$message. Command failed: '$command'"
    fi
}

# Assert that a command fails (exit code != 0)
assert_command_fails() {
    local command="$1"
    local message="${2:-Command should fail}"
    
    if ! eval "$command" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "$message. Command succeeded: '$command'"
    fi
}

# Assert that command output contains expected text
assert_output_contains() {
    local command="$1"
    local expected="$2"
    local message="${3:-Command output should contain expected text}"
    
    local output
    output=$(eval "$command" 2>&1)
    
    if [[ "$output" == *"$expected"* ]]; then
        test_pass
    else
        test_fail "$message. Output: '$output', Expected to contain: '$expected'"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Capture command output (both stdout and stderr)
capture_output() {
    local command="$1"
    eval "$command" 2>&1
}

# Run command with timeout
run_with_timeout() {
    local timeout="$1"
    local command="$2"
    
    # Use timeout command if available, otherwise basic timeout
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout" bash -c "$command"
    else
        # Fallback for systems without timeout command
        eval "$command"
    fi
}

# Create temporary test file
create_temp_file() {
    local prefix="${1:-test}"
    mktemp "/tmp/${prefix}-XXXXXX"
}

# Create temporary test directory
create_temp_dir() {
    local prefix="${1:-test}"
    mktemp -d "/tmp/${prefix}-XXXXXX"
}

# =============================================================================
# MOCK FUNCTIONS
# =============================================================================

# Simple function override mechanism for mocking
mock_function() {
    local original_function="$1"
    local mock_implementation="$2"
    
    # Create backup of original function
    if declare -f "$original_function" >/dev/null 2>&1; then
        # Use a simpler backup method
        declare -f "$original_function" > /tmp/${original_function}_backup.sh
        sed -i.bak "1s/.*/${original_function}_original()/" /tmp/${original_function}_backup.sh
        source /tmp/${original_function}_backup.sh
        rm -f /tmp/${original_function}_backup.sh /tmp/${original_function}_backup.sh.bak
    fi
    
    # Replace with mock using temporary file for complex implementations
    local temp_mock=$(mktemp)
    echo "$original_function() {" > "$temp_mock"
    echo "$mock_implementation" >> "$temp_mock"
    echo "}" >> "$temp_mock"
    
    source "$temp_mock"
    rm -f "$temp_mock"
}

# Restore mocked function
restore_function() {
    local function_name="$1"
    
    if declare -f "${function_name}_original" >/dev/null 2>&1; then
        # Unset the mock
        unset -f "$function_name"
        
        # Restore using temporary file
        local temp_restore=$(mktemp)
        declare -f "${function_name}_original" | sed "s/${function_name}_original/${function_name}/" > "$temp_restore"
        source "$temp_restore"
        rm -f "$temp_restore"
        
        # Clean up the backup
        unset -f "${function_name}_original"
    fi
}

# =============================================================================
# TEST DISCOVERY AND EXECUTION
# =============================================================================

# Run all test functions in current script
run_all_tests() {
    local test_functions
    test_functions=$(declare -F | grep '^declare -f test_' | awk '{print $3}' | grep -v '^test_init$' | grep -v '^test_cleanup$' | grep -v '^test_start$' | grep -v '^test_pass$' | grep -v '^test_fail$' | grep -v '^test_skip$')
    
    for test_func in $test_functions; do
        test_start "$test_func"
        if declare -f "$test_func" >/dev/null 2>&1; then
            if ! "$test_func"; then
                test_fail "Test function threw an error"
            fi
        else
            test_fail "Test function not found: $test_func"
        fi
    done
}

# Run tests from external test file
run_test_file() {
    local test_file="$1"
    
    if [[ ! -f "$test_file" ]]; then
        echo -e "${TEST_RED}Error: Test file not found: $test_file${TEST_NC}"
        return 1
    fi
    
    # Source the test file and run tests
    source "$test_file"
    run_all_tests
}

# =============================================================================
# TRAP HANDLERS
# =============================================================================

# Set up trap for cleanup on exit
trap test_cleanup EXIT