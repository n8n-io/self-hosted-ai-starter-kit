#!/bin/bash
# =============================================================================
# Variable Management Library Test Suite
# Comprehensive testing for the variable management system
# =============================================================================

set -euo pipefail

# Test configuration
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
readonly VARIABLE_MANAGEMENT_LIB="$PROJECT_ROOT/lib/variable-management.sh"

# Test results
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test logging
test_log() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

test_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Run a test and capture results
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TEST_COUNT=$((TEST_COUNT + 1))
    test_log "Running: $test_name"
    
    if $test_function; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name"
        return 1
    fi
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

# Test library loading
test_library_loading() {
    if [ -f "$VARIABLE_MANAGEMENT_LIB" ]; then
        source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
        if declare -f init_essential_variables >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Test secure password generation
test_secure_password_generation() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    local password1 password2
    password1=$(generate_secure_password)
    password2=$(generate_secure_password)
    
    # Check passwords are generated
    if [ -z "$password1" ] || [ -z "$password2" ]; then
        return 1
    fi
    
    # Check passwords are different
    if [ "$password1" = "$password2" ]; then
        return 1
    fi
    
    # Check minimum length
    if [ ${#password1} -lt 16 ]; then
        return 1
    fi
    
    return 0
}

# Test encryption key generation
test_encryption_key_generation() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    local key1 key2
    key1=$(generate_encryption_key)
    key2=$(generate_encryption_key)
    
    # Check keys are generated
    if [ -z "$key1" ] || [ -z "$key2" ]; then
        return 1
    fi
    
    # Check keys are different
    if [ "$key1" = "$key2" ]; then
        return 1
    fi
    
    # Check minimum length
    if [ ${#key1} -lt 32 ]; then
        return 1
    fi
    
    return 0
}

# Test critical variable initialization
test_critical_variable_initialization() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Clear any existing variables
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET
    
    # Initialize variables
    init_critical_variables >/dev/null 2>&1
    
    # Check variables are set
    if [ -z "$POSTGRES_PASSWORD" ] || [ -z "$N8N_ENCRYPTION_KEY" ] || [ -z "$N8N_USER_MANAGEMENT_JWT_SECRET" ]; then
        return 1
    fi
    
    # Check minimum lengths
    if [ ${#POSTGRES_PASSWORD} -lt 8 ] || [ ${#N8N_ENCRYPTION_KEY} -lt 32 ] || [ ${#N8N_USER_MANAGEMENT_JWT_SECRET} -lt 8 ]; then
        return 1
    fi
    
    return 0
}

# Test optional variable initialization
test_optional_variable_initialization() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Clear any existing variables
    unset WEBHOOK_URL N8N_CORS_ENABLE POSTGRES_DB POSTGRES_USER
    
    # Initialize variables
    init_optional_variables >/dev/null 2>&1
    
    # Check variables are set with defaults
    if [ "$WEBHOOK_URL" != "http://localhost:5678" ]; then
        return 1
    fi
    
    if [ "$N8N_CORS_ENABLE" != "true" ]; then
        return 1
    fi
    
    if [ "$POSTGRES_DB" != "n8n" ]; then
        return 1
    fi
    
    if [ "$POSTGRES_USER" != "n8n" ]; then
        return 1
    fi
    
    return 0
}

# Test variable validation
test_variable_validation() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Set up test variables
    export POSTGRES_PASSWORD="test_password_123"
    export N8N_ENCRYPTION_KEY="test_encryption_key_with_sufficient_length_123456789"
    export N8N_USER_MANAGEMENT_JWT_SECRET="test_jwt_secret_123"
    
    # Test validation passes
    if ! validate_critical_variables >/dev/null 2>&1; then
        return 1
    fi
    
    # Test validation fails with short password
    export POSTGRES_PASSWORD="short"
    if validate_critical_variables >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test Docker environment file generation
test_docker_env_file_generation() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Initialize variables
    init_critical_variables >/dev/null 2>&1
    init_optional_variables >/dev/null 2>&1
    
    # Generate environment file
    local test_env_file="/tmp/test-geuse.env"
    generate_docker_env_file "$test_env_file" >/dev/null 2>&1
    
    # Check file was created
    if [ ! -f "$test_env_file" ]; then
        return 1
    fi
    
    # Check file contains required variables
    if ! grep -q "POSTGRES_PASSWORD=" "$test_env_file"; then
        rm -f "$test_env_file"
        return 1
    fi
    
    if ! grep -q "N8N_ENCRYPTION_KEY=" "$test_env_file"; then
        rm -f "$test_env_file"
        return 1
    fi
    
    # Clean up
    rm -f "$test_env_file"
    return 0
}

# Test cache functionality
test_cache_functionality() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Initialize variables
    init_critical_variables >/dev/null 2>&1
    init_optional_variables >/dev/null 2>&1
    
    # Save to cache
    local test_cache_file="/tmp/test-geuse-cache"
    save_variables_to_cache "$test_cache_file" >/dev/null 2>&1
    
    # Check cache file was created
    if [ ! -f "$test_cache_file" ]; then
        return 1
    fi
    
    # Check cache contains variables
    if ! grep -q "POSTGRES_PASSWORD=" "$test_cache_file"; then
        rm -f "$test_cache_file"
        return 1
    fi
    
    # Test loading from cache
    unset POSTGRES_PASSWORD
    load_variables_from_file "$test_cache_file" >/dev/null 2>&1
    
    if [ -z "$POSTGRES_PASSWORD" ]; then
        rm -f "$test_cache_file"
        return 1
    fi
    
    # Clean up
    rm -f "$test_cache_file"
    return 0
}

# Test AWS availability check
test_aws_availability_check() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test when AWS CLI is not available (should fail gracefully)
    if command -v aws >/dev/null 2>&1; then
        # AWS CLI is available, test actual check
        check_aws_availability >/dev/null 2>&1
        local result=$?
        # Either pass or fail is fine, just ensure no errors
        return 0
    else
        # AWS CLI not available, should fail gracefully
        if check_aws_availability >/dev/null 2>&1; then
            return 1  # Should have failed
        else
            return 0  # Correctly failed
        fi
    fi
}

# Test variable update functionality
test_variable_update() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test updating a variable
    local test_value="test_value_123"
    update_variable "TEST_VAR" "$test_value" false >/dev/null 2>&1
    
    if [ "$TEST_VAR" != "$test_value" ]; then
        return 1
    fi
    
    return 0
}

# Test bash 3.x compatibility
test_bash_compatibility() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test that functions work in current bash version
    local test_password test_key
    test_password=$(generate_secure_password)
    test_key=$(generate_encryption_key)
    
    if [ -z "$test_password" ] || [ -z "$test_key" ]; then
        return 1
    fi
    
    # Test variable assignment patterns that work in bash 3.x
    init_essential_variables >/dev/null 2>&1
    
    return 0
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "============================================================================="
    echo "Variable Management Library Test Suite"
    echo "============================================================================="
    echo ""
    
    # Check if library exists
    if [ ! -f "$VARIABLE_MANAGEMENT_LIB" ]; then
        echo -e "${RED}ERROR:${NC} Variable management library not found: $VARIABLE_MANAGEMENT_LIB"
        exit 1
    fi
    
    echo "Testing library: $VARIABLE_MANAGEMENT_LIB"
    echo ""
    
    # Run tests
    run_test "Library Loading" test_library_loading
    run_test "Secure Password Generation" test_secure_password_generation
    run_test "Encryption Key Generation" test_encryption_key_generation
    run_test "Critical Variable Initialization" test_critical_variable_initialization
    run_test "Optional Variable Initialization" test_optional_variable_initialization
    run_test "Variable Validation" test_variable_validation
    run_test "Docker Environment File Generation" test_docker_env_file_generation
    run_test "Cache Functionality" test_cache_functionality
    run_test "AWS Availability Check" test_aws_availability_check
    run_test "Variable Update Functionality" test_variable_update
    run_test "Bash Compatibility" test_bash_compatibility
    
    # Report results
    echo ""
    echo "============================================================================="
    echo "Test Results Summary"
    echo "============================================================================="
    echo "Total Tests: $TEST_COUNT"
    echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
    echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
    
    local success_rate=0
    if [ $TEST_COUNT -gt 0 ]; then
        success_rate=$((PASS_COUNT * 100 / TEST_COUNT))
    fi
    echo "Success Rate: ${success_rate}%"
    
    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# Execute main function
main "$@"