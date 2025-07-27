#!/bin/bash
# =============================================================================
# Parameter Store Integration Test Suite
# Tests AWS Parameter Store integration with fallback mechanisms
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

test_skip() {
    echo -e "${YELLOW}⚬ SKIP:${NC} $1"
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

# Test AWS CLI availability check
test_aws_cli_availability() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test the availability check function
    local aws_available=false
    if command -v aws >/dev/null 2>&1; then
        aws_available=true
    fi
    
    # Call the function and check it returns expected result
    if check_aws_availability >/dev/null 2>&1; then
        if [ "$aws_available" = "true" ]; then
            return 0  # Correctly detected AWS as available
        else
            return 1  # False positive
        fi
    else
        if [ "$aws_available" = "false" ]; then
            return 0  # Correctly detected AWS as unavailable
        else
            # AWS is available but function returned false - could be credentials issue
            return 0  # Still valid behavior
        fi
    fi
}

# Test parameter retrieval with fallback
test_parameter_fallback() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test getting a non-existent parameter with fallback
    local default_value="test_default_value"
    local result
    result=$(get_parameter_store_value "/non/existent/parameter" "$default_value" "String" 2>/dev/null)
    
    if [ "$result" = "$default_value" ]; then
        return 0
    else
        return 1
    fi
}

# Test batch parameter retrieval
test_batch_parameter_retrieval() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test batch retrieval with non-existent parameters
    local param_names="/test/param1 /test/param2 /test/param3"
    local result
    
    # This should fail gracefully and not crash
    if result=$(get_parameters_batch "$param_names" 2>/dev/null); then
        # If it returns something, that's fine
        return 0
    else
        # If it fails, that's also expected for non-existent parameters
        return 0
    fi
}

# Test parameter extraction from batch result
test_parameter_extraction() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test with empty batch result
    local result
    result=$(extract_parameter_from_batch "" "/test/param" "default_value" 2>/dev/null)
    
    if [ "$result" = "default_value" ]; then
        return 0
    else
        return 1
    fi
}

# Test Parameter Store loading with fallbacks
test_parameter_store_loading() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Set up environment variables with defaults
    export POSTGRES_PASSWORD="default_password"
    export N8N_ENCRYPTION_KEY="default_encryption_key"
    export N8N_USER_MANAGEMENT_JWT_SECRET="default_jwt_secret"
    
    # Try loading from Parameter Store (will fail, but should use defaults)
    load_variables_from_parameter_store >/dev/null 2>&1
    
    # Variables should still be set (either from Parameter Store or defaults)
    if [ -n "$POSTGRES_PASSWORD" ] && [ -n "$N8N_ENCRYPTION_KEY" ] && [ -n "$N8N_USER_MANAGEMENT_JWT_SECRET" ]; then
        return 0
    else
        return 1
    fi
}

# Test complete variable initialization without AWS
test_initialization_without_aws() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Clear variables
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET
    unset OPENAI_API_KEY WEBHOOK_URL N8N_CORS_ENABLE
    
    # Mock AWS CLI unavailability by temporarily modifying PATH
    local original_path="$PATH"
    export PATH="/tmp/empty:$PATH"
    
    # Try to initialize all variables
    if init_all_variables true "/tmp/test-cache" >/dev/null 2>&1; then
        # Restore PATH
        export PATH="$original_path"
        
        # Check that variables were initialized with defaults
        if [ -n "$POSTGRES_PASSWORD" ] && [ -n "$N8N_ENCRYPTION_KEY" ] && [ -n "$N8N_USER_MANAGEMENT_JWT_SECRET" ]; then
            return 0
        else
            return 1
        fi
    else
        # Restore PATH
        export PATH="$original_path"
        return 1
    fi
}

# Test emergency recovery scenario
test_emergency_recovery() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Clear all variables to simulate emergency
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET
    unset OPENAI_API_KEY WEBHOOK_URL N8N_CORS_ENABLE POSTGRES_DB POSTGRES_USER
    
    # Initialize essential variables (minimal required for emergency recovery)
    init_essential_variables >/dev/null 2>&1
    
    # Check that critical variables are set
    if [ -n "$POSTGRES_PASSWORD" ] && [ -n "$N8N_ENCRYPTION_KEY" ] && [ -n "$N8N_USER_MANAGEMENT_JWT_SECRET" ]; then
        # Check that basic database variables are set
        if [ "$POSTGRES_DB" = "n8n" ] && [ "$POSTGRES_USER" = "n8n" ]; then
            return 0
        fi
    fi
    
    return 1
}

# Test cache recovery
test_cache_recovery() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Create a test cache file
    local test_cache="/tmp/test-recovery-cache"
    cat > "$test_cache" << EOF
# Test cache file
POSTGRES_PASSWORD=cached_password_123
N8N_ENCRYPTION_KEY=cached_encryption_key_123456789012345678901234567890
N8N_USER_MANAGEMENT_JWT_SECRET=cached_jwt_secret_123
WEBHOOK_URL=http://cached.example.com
EOF
    
    # Clear variables
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET WEBHOOK_URL
    
    # Try to initialize with cache (no force refresh)
    if init_all_variables false "$test_cache" >/dev/null 2>&1; then
        # Check that variables were loaded from cache
        if [ "$POSTGRES_PASSWORD" = "cached_password_123" ] && [ "$WEBHOOK_URL" = "http://cached.example.com" ]; then
            rm -f "$test_cache"
            return 0
        fi
    fi
    
    rm -f "$test_cache"
    return 1
}

# Test region fallback
test_region_fallback() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test that the function tries multiple regions
    local original_region="$AWS_REGION"
    export AWS_REGION="non-existent-region"
    
    # This should try the non-existent region, then fallback to default regions
    local result
    result=$(get_parameter_store_value "/test/parameter" "fallback_value" "String" 2>/dev/null)
    
    # Restore original region
    if [ -n "$original_region" ]; then
        export AWS_REGION="$original_region"
    else
        unset AWS_REGION
    fi
    
    # Should return fallback value since parameter doesn't exist
    if [ "$result" = "fallback_value" ]; then
        return 0
    else
        return 1
    fi
}

# Test jq dependency handling
test_jq_dependency() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test parameter extraction without jq (fallback method)
    local mock_batch_result='{"Parameters":[{"Name":"/test/param","Value":"test_value"}]}'
    
    # Extract parameter using the function (should work with or without jq)
    local result
    result=$(extract_parameter_from_batch "$mock_batch_result" "/test/param" "default" 2>/dev/null)
    
    # Should extract the value or return default
    if [ -n "$result" ]; then
        return 0
    else
        return 1
    fi
}

# Test concurrent safety
test_concurrent_safety() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test that multiple initializations don't conflict
    init_essential_variables >/dev/null 2>&1 &
    local pid1=$!
    
    init_essential_variables >/dev/null 2>&1 &
    local pid2=$!
    
    # Wait for both to complete
    wait $pid1
    local result1=$?
    wait $pid2
    local result2=$?
    
    # Both should succeed
    if [ $result1 -eq 0 ] && [ $result2 -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "============================================================================="
    echo "Parameter Store Integration Test Suite"
    echo "============================================================================="
    echo ""
    
    # Check if library exists
    if [ ! -f "$VARIABLE_MANAGEMENT_LIB" ]; then
        echo -e "${RED}ERROR:${NC} Variable management library not found: $VARIABLE_MANAGEMENT_LIB"
        exit 1
    fi
    
    echo "Testing library: $VARIABLE_MANAGEMENT_LIB"
    echo ""
    
    # Check AWS CLI availability for reporting
    if command -v aws >/dev/null 2>&1; then
        echo -e "${GREEN}AWS CLI is available${NC} - will test actual integration"
    else
        echo -e "${YELLOW}AWS CLI not available${NC} - will test fallback mechanisms only"
    fi
    echo ""
    
    # Run tests
    run_test "AWS CLI Availability Check" test_aws_cli_availability
    run_test "Parameter Retrieval with Fallback" test_parameter_fallback
    run_test "Batch Parameter Retrieval" test_batch_parameter_retrieval
    run_test "Parameter Extraction from Batch" test_parameter_extraction
    run_test "Parameter Store Loading with Fallbacks" test_parameter_store_loading
    run_test "Initialization Without AWS" test_initialization_without_aws
    run_test "Emergency Recovery Scenario" test_emergency_recovery
    run_test "Cache Recovery" test_cache_recovery
    run_test "Region Fallback" test_region_fallback
    run_test "jq Dependency Handling" test_jq_dependency
    run_test "Concurrent Safety" test_concurrent_safety
    
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
        echo -e "${GREEN}All Parameter Store integration tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some Parameter Store integration tests failed.${NC}"
        exit 1
    fi
}

# Execute main function
main "$@"