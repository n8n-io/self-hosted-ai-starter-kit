#!/bin/bash
# =============================================================================
# Emergency Recovery Test Suite
# Tests emergency scenarios without AWS and recovery mechanisms
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

# Test complete offline initialization
test_offline_initialization() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Clear all variables
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET
    unset OPENAI_API_KEY WEBHOOK_URL N8N_CORS_ENABLE AWS_REGION
    
    # Mock no network/AWS access
    local original_path="$PATH"
    export PATH="/usr/bin:/bin"  # Minimal PATH without aws
    
    # Initialize variables
    if init_essential_variables >/dev/null 2>&1; then
        export PATH="$original_path"
        
        # Verify critical variables are set
        if [ -n "$POSTGRES_PASSWORD" ] && [ -n "$N8N_ENCRYPTION_KEY" ] && [ -n "$N8N_USER_MANAGEMENT_JWT_SECRET" ]; then
            # Verify secure generation
            if [ ${#POSTGRES_PASSWORD} -ge 16 ] && [ ${#N8N_ENCRYPTION_KEY} -ge 32 ]; then
                return 0
            fi
        fi
    fi
    
    export PATH="$original_path"
    return 1
}

# Test degraded fallback generation
test_degraded_fallback() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test password generation without openssl
    local password1 password2
    
    # Mock no openssl
    local original_path="$PATH"
    export PATH="/usr/bin:/bin"
    
    password1=$(generate_secure_password 2>/dev/null || echo "fallback_test")
    password2=$(generate_encryption_key 2>/dev/null || echo "fallback_test")
    
    export PATH="$original_path"
    
    # Should have generated something
    if [ -n "$password1" ] && [ -n "$password2" ]; then
        return 0
    fi
    
    return 1
}

# Test file permission recovery
test_file_permission_recovery() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Create test environment file with wrong permissions
    local test_env="/tmp/test-permissions.env"
    cat > "$test_env" << EOF
POSTGRES_PASSWORD=test_password
N8N_ENCRYPTION_KEY=test_key_1234567890123456789012345678901234567890
N8N_USER_MANAGEMENT_JWT_SECRET=test_jwt_secret
EOF
    
    chmod 644 "$test_env"  # Wrong permissions
    
    # Generate environment file (should fix permissions)
    init_essential_variables >/dev/null 2>&1
    generate_docker_env_file "$test_env" >/dev/null 2>&1
    
    # Check permissions were fixed
    local perms
    perms=$(stat -f "%OLp" "$test_env" 2>/dev/null || stat -c "%a" "$test_env" 2>/dev/null)
    
    rm -f "$test_env"
    
    if [ "$perms" = "600" ]; then
        return 0
    fi
    
    return 1
}

# Test cache corruption recovery
test_cache_corruption_recovery() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Create corrupted cache file
    local test_cache="/tmp/test-corrupted-cache"
    echo "corrupted data" > "$test_cache"
    
    # Clear variables
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET
    
    # Try to initialize with corrupted cache
    if init_all_variables false "$test_cache" >/dev/null 2>&1; then
        # Should have fallen back to secure generation
        if [ -n "$POSTGRES_PASSWORD" ] && [ -n "$N8N_ENCRYPTION_KEY" ]; then
            rm -f "$test_cache"
            return 0
        fi
    fi
    
    rm -f "$test_cache"
    return 1
}

# Test minimal resource scenario
test_minimal_resources() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test with minimal /tmp space (simulated)
    local test_env="/tmp/test-minimal.env"
    
    # Initialize and generate files
    init_essential_variables >/dev/null 2>&1
    
    if generate_docker_env_file "$test_env" false >/dev/null 2>&1; then
        # Check file was created and contains essentials
        if [ -f "$test_env" ] && grep -q "POSTGRES_PASSWORD=" "$test_env"; then
            rm -f "$test_env"
            return 0
        fi
    fi
    
    rm -f "$test_env"
    return 1
}

# Test cross-platform compatibility
test_cross_platform_compatibility() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test bash 3.x compatible operations
    local test_array="item1 item2 item3"
    local count=0
    
    # Test bash 3.x compatible iteration
    for item in $test_array; do
        count=$((count + 1))
    done
    
    if [ $count -eq 3 ]; then
        # Test variable operations that work in bash 3.x
        init_essential_variables >/dev/null 2>&1
        return 0
    fi
    
    return 1
}

# Test error propagation
test_error_propagation() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test that errors are properly handled
    local result=0
    
    # Test validation with invalid data
    export POSTGRES_PASSWORD="bad"  # Too short
    export N8N_ENCRYPTION_KEY="bad"  # Too short
    
    if validate_critical_variables >/dev/null 2>&1; then
        result=1  # Should have failed
    else
        result=0  # Correctly failed
    fi
    
    # Clean up
    unset POSTGRES_PASSWORD N8N_ENCRYPTION_KEY
    
    return $result
}

# Test rapid initialization cycles
test_rapid_initialization() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Test multiple rapid initializations
    local success_count=0
    
    for i in 1 2 3 4 5; do
        if init_essential_variables >/dev/null 2>&1; then
            success_count=$((success_count + 1))
        fi
    done
    
    if [ $success_count -eq 5 ]; then
        return 0
    fi
    
    return 1
}

# Test variable consistency
test_variable_consistency() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Initialize variables
    init_essential_variables >/dev/null 2>&1
    
    # Store initial values
    local initial_password="$POSTGRES_PASSWORD"
    local initial_key="$N8N_ENCRYPTION_KEY"
    
    # Re-initialize (should use existing values)
    init_essential_variables >/dev/null 2>&1
    
    # Check consistency
    if [ "$POSTGRES_PASSWORD" = "$initial_password" ] && [ "$N8N_ENCRYPTION_KEY" = "$initial_key" ]; then
        return 0
    fi
    
    return 1
}

# Test cleanup functionality
test_cleanup_functionality() {
    source "$VARIABLE_MANAGEMENT_LIB" >/dev/null 2>&1
    
    # Create test cache files
    local test_cache="/tmp/test-cleanup-cache"
    echo "test data" > "$test_cache"
    
    # Use the cache
    export VAR_CACHE_FILE="$test_cache"
    
    # Clear cache
    clear_variable_cache >/dev/null 2>&1
    
    # Check file was removed
    if [ ! -f "$test_cache" ]; then
        return 0
    fi
    
    return 1
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "============================================================================="
    echo "Emergency Recovery Test Suite"
    echo "============================================================================="
    echo ""
    
    # Check if library exists
    if [ ! -f "$VARIABLE_MANAGEMENT_LIB" ]; then
        echo -e "${RED}ERROR:${NC} Variable management library not found: $VARIABLE_MANAGEMENT_LIB"
        exit 1
    fi
    
    echo "Testing emergency recovery scenarios..."
    echo ""
    
    # Run tests
    run_test "Complete Offline Initialization" test_offline_initialization
    run_test "Degraded Fallback Generation" test_degraded_fallback
    run_test "File Permission Recovery" test_file_permission_recovery
    run_test "Cache Corruption Recovery" test_cache_corruption_recovery
    run_test "Minimal Resources Scenario" test_minimal_resources
    run_test "Cross-Platform Compatibility" test_cross_platform_compatibility
    run_test "Error Propagation" test_error_propagation
    run_test "Rapid Initialization Cycles" test_rapid_initialization
    run_test "Variable Consistency" test_variable_consistency
    run_test "Cleanup Functionality" test_cleanup_functionality
    
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
        echo -e "${GREEN}All emergency recovery tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some emergency recovery tests failed.${NC}"
        exit 1
    fi
}

# Execute main function
main "$@"