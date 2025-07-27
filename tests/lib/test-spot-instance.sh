#!/bin/bash
# =============================================================================
# Unit Tests for spot-instance.sh
# Tests for spot pricing analysis and optimal configuration functions
# =============================================================================

set -euo pipefail

# Get script directory for sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the test framework
source "$SCRIPT_DIR/shell-test-framework.sh"

# Source required dependencies
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

# Source the library under test
source "$PROJECT_ROOT/lib/spot-instance.sh"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    # Store original AWS region
    ORIGINAL_AWS_REGION="${AWS_REGION:-}"
    
    # Set test defaults
    export AWS_REGION="us-east-1"
    
    # Mock external AWS commands for testing
    mock_aws_commands
}

teardown_test_environment() {
    # Restore original environment
    export AWS_REGION="${ORIGINAL_AWS_REGION}"
    
    # Restore mocked functions
    restore_function "aws"
    restore_function "bc"
}

# Mock AWS CLI commands for testing
mock_aws_commands() {
    # Mock aws command to return predictable data
    mock_function "aws" '
        if [[ "$*" == *"describe-availability-zones"* ]]; then
            echo -e "us-east-1a\tus-east-1b\tus-east-1c"
        elif [[ "$*" == *"describe-spot-price-history"* ]]; then
            if [[ "$*" == *"us-east-1a"* ]]; then
                echo -e "us-east-1a\t0.1234\t2023-01-01T12:00:00.000Z"
            elif [[ "$*" == *"us-east-1b"* ]]; then
                echo -e "us-east-1b\t0.0987\t2023-01-01T12:00:00.000Z"
            elif [[ "$*" == *"us-east-1c"* ]]; then
                echo -e "us-east-1c\t0.1456\t2023-01-01T12:00:00.000Z"
            else
                echo -e "us-east-1a\t0.1234\t2023-01-01T12:00:00.000Z"
            fi
        else
            return 0
        fi
    '
    
    # Mock bc command for floating point comparisons
    mock_function "bc" '
        # Read from stdin when called with pipe
        local expression
        if [ -p /dev/stdin ]; then
            read expression
        else
            expression="$1"
        fi
        
        # Handle specific price comparisons for our test data
        if [[ "$expression" == "0.0987 < 0.1234" ]]; then
            echo "1"  # 0.0987 is less than 0.1234 (true)
        elif [[ "$expression" == "0.1456 < 0.0987" ]]; then
            echo "0"  # 0.1456 is not less than 0.0987 (false)
        elif [[ "$expression" == "0.1456 < 0.1234" ]]; then
            echo "0"  # 0.1456 is not less than 0.1234 (false)
        elif [[ "$expression" == *"< 0.1"* ]]; then
            echo "1"  # true
        elif [[ "$expression" == *"< 0.2"* ]]; then
            echo "1"  # true
        else
            echo "0"  # false
        fi
    '
}

# =============================================================================
# SPOT PRICING ANALYSIS TESTS
# =============================================================================

test_analyze_spot_pricing_basic_functionality() {
    test_start "analyze_spot_pricing returns pricing information"
    
    setup_test_environment
    
    local result
    result=$(analyze_spot_pricing "g4dn.xlarge" "us-east-1" 2>/dev/null)
    
    assert_not_empty "$result" "Should return pricing information"
    assert_contains "$result" ":" "Result should contain AZ:price format"
}

test_analyze_spot_pricing_missing_instance_type() {
    test_start "analyze_spot_pricing fails when instance type is missing"
    
    setup_test_environment
    
    if analyze_spot_pricing "" "us-east-1" >/dev/null 2>&1; then
        test_fail "Should fail when instance type is missing"
    else
        test_pass
    fi
}

test_analyze_spot_pricing_uses_default_region() {
    test_start "analyze_spot_pricing uses AWS_REGION when region not specified"
    
    setup_test_environment
    export AWS_REGION="us-west-2"
    
    # Mock AWS call for us-west-2
    mock_function "aws" '
        if [[ "$*" == *"describe-availability-zones"* && "$*" == *"us-west-2"* ]]; then
            echo -e "us-west-2a\tus-west-2b"
        elif [[ "$*" == *"describe-spot-price-history"* && "$*" == *"us-west-2"* ]]; then
            echo -e "us-west-2a\t0.2000\t2023-01-01T12:00:00.000Z"
        else
            return 0
        fi
    '
    
    local result
    result=$(analyze_spot_pricing "g4dn.xlarge" 2>/dev/null)
    
    assert_not_empty "$result" "Should work with default region"
}

test_analyze_spot_pricing_finds_best_price() {
    test_start "analyze_spot_pricing finds the lowest price availability zone"
    
    setup_test_environment
    
    # Mock returns us-east-1b as cheapest (0.0987)
    local result
    result=$(analyze_spot_pricing "g4dn.xlarge" "us-east-1" 2>/dev/null)
    
    assert_contains "$result" "us-east-1b" "Should select the cheapest AZ"
    assert_contains "$result" "0.0987" "Should return the lowest price"
}

test_analyze_spot_pricing_specific_azs() {
    test_start "analyze_spot_pricing works with specific availability zones"
    
    setup_test_environment
    
    local result
    result=$(analyze_spot_pricing "g4dn.xlarge" "us-east-1" "us-east-1a" "us-east-1c" 2>/dev/null)
    
    assert_not_empty "$result" "Should work with specific AZs"
    # Should return us-east-1a (0.1234) as it's cheaper than us-east-1c (0.1456)
    assert_contains "$result" "us-east-1a" "Should select cheapest from specified AZs"
}

test_analyze_spot_pricing_no_data() {
    test_start "analyze_spot_pricing handles case when no pricing data is available"
    
    setup_test_environment
    
    # Mock AWS to return empty results
    mock_function "aws" 'return 0'  # Return success but no output
    
    if analyze_spot_pricing "invalid-instance" "us-east-1" >/dev/null 2>&1; then
        test_fail "Should fail when no pricing data is available"
    else
        test_pass
    fi
}

# =============================================================================
# OPTIMAL SPOT CONFIGURATION TESTS
# =============================================================================

test_get_optimal_spot_configuration_basic() {
    test_start "get_optimal_spot_configuration returns optimal configuration"
    
    setup_test_environment
    
    # Mock analyze_spot_pricing to return a known result
    mock_function "analyze_spot_pricing" 'echo "us-east-1b:0.0987"'
    
    local result
    result=$(get_optimal_spot_configuration "g4dn.xlarge" "0.50" "us-east-1" 2>/dev/null)
    
    assert_not_empty "$result" "Should return configuration"
    
    restore_function "analyze_spot_pricing"
}

test_get_optimal_spot_configuration_missing_params() {
    test_start "get_optimal_spot_configuration fails when parameters are missing"
    
    setup_test_environment
    
    # Test missing instance type
    if get_optimal_spot_configuration "" "0.50" "us-east-1" >/dev/null 2>&1; then
        test_fail "Should fail when instance type is missing"
    else
        test_pass
    fi
}

test_get_optimal_spot_configuration_missing_max_price() {
    test_start "get_optimal_spot_configuration fails when max price is missing"
    
    setup_test_environment
    
    if get_optimal_spot_configuration "g4dn.xlarge" "" "us-east-1" >/dev/null 2>&1; then
        test_fail "Should fail when max price is missing"
    else
        test_pass
    fi
}

test_get_optimal_spot_configuration_uses_default_region() {
    test_start "get_optimal_spot_configuration uses AWS_REGION when region not specified"
    
    setup_test_environment
    export AWS_REGION="us-west-2"
    
    # Mock analyze_spot_pricing to return a result
    mock_function "analyze_spot_pricing" 'echo "us-west-2a:0.1500"'
    
    local result
    result=$(get_optimal_spot_configuration "g4dn.xlarge" "0.50" 2>/dev/null)
    
    assert_not_empty "$result" "Should work with default region"
    
    restore_function "analyze_spot_pricing"
}

test_get_optimal_spot_configuration_pricing_failure() {
    test_start "get_optimal_spot_configuration handles pricing analysis failure"
    
    setup_test_environment
    
    # Mock analyze_spot_pricing to fail
    mock_function "analyze_spot_pricing" 'return 1'
    
    if get_optimal_spot_configuration "g4dn.xlarge" "0.50" "us-east-1" >/dev/null 2>&1; then
        test_fail "Should fail when pricing analysis fails"
    else
        test_pass
    fi
    
    restore_function "analyze_spot_pricing"
}

# =============================================================================
# SPOT CONFIGURATION VALIDATION TESTS
# =============================================================================

test_validate_spot_configuration_exists() {
    test_start "validate_spot_configuration function exists"
    
    if declare -f validate_spot_configuration >/dev/null 2>&1; then
        test_pass
    else
        test_skip "validate_spot_configuration function not found in spot-instance.sh"
    fi
}

test_validate_spot_instance_type_exists() {
    test_start "validate_spot_instance_type function exists"
    
    if declare -f validate_spot_instance_type >/dev/null 2>&1; then
        test_pass
    else
        test_skip "validate_spot_instance_type function not found in spot-instance.sh"
    fi
}

# =============================================================================
# HELPER FUNCTION TESTS
# =============================================================================

test_spot_instance_helpers_exist() {
    test_start "spot instance helper functions are available"
    
    local helper_functions=(
        "get_spot_fleet_config"
        "create_spot_fleet_request"
        "monitor_spot_fleet"
        "terminate_spot_fleet"
    )
    
    local found_functions=0
    for func in "${helper_functions[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            ((found_functions++))
        fi
    done
    
    if [[ $found_functions -gt 0 ]]; then
        test_pass
    else
        test_skip "No additional spot instance helper functions found"
    fi
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_analyze_spot_pricing_single_az() {
    test_start "analyze_spot_pricing works with single availability zone"
    
    setup_test_environment
    
    local result
    result=$(analyze_spot_pricing "g4dn.xlarge" "us-east-1" "us-east-1a" 2>/dev/null)
    
    assert_not_empty "$result" "Should work with single AZ"
    assert_contains "$result" "us-east-1a" "Should return the specified AZ"
}

test_analyze_spot_pricing_floating_point_comparison() {
    test_start "analyze_spot_pricing handles floating point price comparisons"
    
    setup_test_environment
    
    # Mock bc to handle floating point correctly
    mock_function "bc" '
        # Read from stdin when called with pipe
        local expr
        if [ -p /dev/stdin ]; then
            read expr
        else
            expr="$1"
        fi
        
        if [[ "$expr" == "0.0987 < 0.1234" ]]; then
            echo "1"
        elif [[ "$expr" == "0.1456 < 0.0987" ]]; then
            echo "0"
        else
            echo "0"
        fi
    '
    
    local result
    result=$(analyze_spot_pricing "g4dn.xlarge" "us-east-1" 2>/dev/null)
    
    assert_contains "$result" "0.0987" "Should correctly identify lowest price"
    
    restore_function "bc"
}

test_analyze_spot_pricing_aws_cli_error() {
    test_start "analyze_spot_pricing handles AWS CLI errors gracefully"
    
    setup_test_environment
    
    # Mock AWS CLI to return error
    mock_function "aws" 'return 1'
    
    if analyze_spot_pricing "g4dn.xlarge" "us-east-1" >/dev/null 2>&1; then
        test_fail "Should handle AWS CLI errors gracefully"
    else
        test_pass
    fi
}

test_get_optimal_spot_configuration_price_parsing() {
    test_start "get_optimal_spot_configuration correctly parses pricing result"
    
    setup_test_environment
    
    # Mock analyze_spot_pricing to return formatted result
    mock_function "analyze_spot_pricing" 'echo "us-east-1b:0.0987"'
    
    local result
    result=$(get_optimal_spot_configuration "g4dn.xlarge" "0.50" "us-east-1" 2>/dev/null)
    
    assert_not_empty "$result" "Should parse pricing result correctly"
    
    restore_function "analyze_spot_pricing"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_spot_pricing_workflow() {
    test_start "spot pricing functions work together in typical workflow"
    
    setup_test_environment
    
    # Step 1: Analyze pricing
    local pricing_result
    pricing_result=$(analyze_spot_pricing "g4dn.xlarge" "us-east-1" 2>/dev/null)
    
    if [[ -n "$pricing_result" ]]; then
        # Step 2: Get optimal configuration using pricing result
        mock_function "analyze_spot_pricing" "echo '$pricing_result'"
        
        local config_result
        config_result=$(get_optimal_spot_configuration "g4dn.xlarge" "0.50" "us-east-1" 2>/dev/null)
        
        if [[ -n "$config_result" ]]; then
            test_pass
        else
            test_fail "Configuration step should succeed with valid pricing"
        fi
        
        restore_function "analyze_spot_pricing"
    else
        test_fail "Pricing analysis should return results"
    fi
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_analyze_spot_pricing_performance() {
    test_start "analyze_spot_pricing completes within reasonable time"
    
    setup_test_environment
    
    local start_time=$(date +%s)
    analyze_spot_pricing "g4dn.xlarge" "us-east-1" >/dev/null 2>&1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $duration -lt 10 ]]; then
        test_pass
    else
        test_fail "Function took too long: ${duration}s (should be < 10s)"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    test_init "test-spot-instance.sh"
    
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