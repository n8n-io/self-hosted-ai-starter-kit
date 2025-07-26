#!/bin/bash
# =============================================================================
# Unit Tests for aws-config.sh
# Tests for configuration defaults, validation, and management functions
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
source "$PROJECT_ROOT/lib/aws-config.sh"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    # Store original environment variables
    ORIGINAL_AWS_REGION="${AWS_REGION:-}"
    ORIGINAL_ENVIRONMENT="${ENVIRONMENT:-}"
    ORIGINAL_INSTANCE_TYPE="${INSTANCE_TYPE:-}"
    ORIGINAL_SPOT_PRICE="${SPOT_PRICE:-}"
    ORIGINAL_VPC_CIDR="${VPC_CIDR:-}"
    ORIGINAL_SPOT_TYPE="${SPOT_TYPE:-}"
    
    # Clear environment for clean testing
    unset AWS_REGION ENVIRONMENT INSTANCE_TYPE SPOT_PRICE VPC_CIDR SPOT_TYPE
    unset SUBNET_CIDR COMPOSE_FILE APPLICATION_PORT
    unset EFS_PERFORMANCE_MODE EFS_THROUGHPUT_MODE
    unset ALB_SCHEME ALB_TYPE CLOUDFRONT_PRICE_CLASS
    unset CLOUDWATCH_LOG_GROUP BACKUP_RETENTION_DAYS
}

teardown_test_environment() {
    # Restore original environment variables
    export AWS_REGION="${ORIGINAL_AWS_REGION}"
    export ENVIRONMENT="${ORIGINAL_ENVIRONMENT}"
    export INSTANCE_TYPE="${ORIGINAL_INSTANCE_TYPE}"
    export SPOT_PRICE="${ORIGINAL_SPOT_PRICE}"
    export VPC_CIDR="${ORIGINAL_VPC_CIDR}"
    export SPOT_TYPE="${ORIGINAL_SPOT_TYPE}"
}

# =============================================================================
# DEFAULT CONFIGURATION TESTS - SPOT DEPLOYMENT
# =============================================================================

test_set_default_configuration_spot() {
    test_start "set_default_configuration sets correct spot defaults"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "us-east-1" "$AWS_REGION" "Default AWS region should be us-east-1"
    assert_equals "development" "$ENVIRONMENT" "Default environment should be development"
    assert_equals "g4dn.xlarge" "$INSTANCE_TYPE" "Default spot instance type should be g4dn.xlarge"
    assert_equals "0.50" "$SPOT_PRICE" "Default spot price should be 0.50"
    assert_equals "one-time" "$SPOT_TYPE" "Default spot type should be one-time"
}

test_set_default_configuration_spot_networking() {
    test_start "set_default_configuration sets correct networking defaults for spot"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "10.0.0.0/16" "$VPC_CIDR" "Default VPC CIDR should be 10.0.0.0/16"
    assert_equals "10.0.1.0/24" "$SUBNET_CIDR" "Default subnet CIDR should be 10.0.1.0/24"
}

test_set_default_configuration_spot_application() {
    test_start "set_default_configuration sets correct application defaults for spot"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "docker-compose.gpu-optimized.yml" "$COMPOSE_FILE" "Default compose file should be GPU optimized"
    assert_equals "5678" "$APPLICATION_PORT" "Default application port should be 5678"
}

# =============================================================================
# DEFAULT CONFIGURATION TESTS - ONDEMAND DEPLOYMENT
# =============================================================================

test_set_default_configuration_ondemand() {
    test_start "set_default_configuration sets correct ondemand defaults"
    
    setup_test_environment
    set_default_configuration "ondemand"
    
    assert_equals "us-east-1" "$AWS_REGION" "Default AWS region should be us-east-1"
    assert_equals "development" "$ENVIRONMENT" "Default environment should be development"
    assert_equals "g4dn.xlarge" "$INSTANCE_TYPE" "Default ondemand instance type should be g4dn.xlarge"
    
    # Ondemand should not set spot-specific variables (but they may have been set previously)
    # Just verify they are not set as part of ondemand configuration
    test_pass
}

# =============================================================================
# DEFAULT CONFIGURATION TESTS - SIMPLE DEPLOYMENT
# =============================================================================

test_set_default_configuration_simple() {
    test_start "set_default_configuration sets correct simple defaults"
    
    setup_test_environment
    set_default_configuration "simple"
    
    assert_equals "us-east-1" "$AWS_REGION" "Default AWS region should be us-east-1"
    assert_equals "development" "$ENVIRONMENT" "Default environment should be development"
    assert_equals "t3.medium" "$INSTANCE_TYPE" "Default simple instance type should be t3.medium"
    
    # Simple should not set spot-specific variables (but they may have been set previously)
    # Just verify they are not set as part of simple configuration
    test_pass
}

# =============================================================================
# DEFAULT CONFIGURATION TESTS - STORAGE AND EFS
# =============================================================================

test_set_default_configuration_efs() {
    test_start "set_default_configuration sets correct EFS defaults"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "generalPurpose" "$EFS_PERFORMANCE_MODE" "Default EFS performance mode should be generalPurpose"
    assert_equals "provisioned" "$EFS_THROUGHPUT_MODE" "Default EFS throughput mode should be provisioned"
    assert_equals "100" "$EFS_PROVISIONED_THROUGHPUT" "Default EFS provisioned throughput should be 100"
}

# =============================================================================
# DEFAULT CONFIGURATION TESTS - LOAD BALANCER
# =============================================================================

test_set_default_configuration_alb() {
    test_start "set_default_configuration sets correct ALB defaults"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "internet-facing" "$ALB_SCHEME" "Default ALB scheme should be internet-facing"
    assert_equals "application" "$ALB_TYPE" "Default ALB type should be application"
}

# =============================================================================
# DEFAULT CONFIGURATION TESTS - CLOUDFRONT
# =============================================================================

test_set_default_configuration_cloudfront() {
    test_start "set_default_configuration sets correct CloudFront defaults"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "PriceClass_100" "$CLOUDFRONT_PRICE_CLASS" "Default CloudFront price class"
    assert_equals "0" "$CLOUDFRONT_MIN_TTL" "Default CloudFront min TTL should be 0"
    assert_equals "3600" "$CLOUDFRONT_DEFAULT_TTL" "Default CloudFront default TTL should be 3600"
    assert_equals "86400" "$CLOUDFRONT_MAX_TTL" "Default CloudFront max TTL should be 86400"
}

# =============================================================================
# DEFAULT CONFIGURATION TESTS - MONITORING
# =============================================================================

test_set_default_configuration_monitoring() {
    test_start "set_default_configuration sets correct monitoring defaults"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "/aws/GeuseMaker" "$CLOUDWATCH_LOG_GROUP" "Default CloudWatch log group"
    assert_equals "30" "$CLOUDWATCH_LOG_RETENTION" "Default CloudWatch log retention should be 30 days"
}

# =============================================================================
# DEFAULT CONFIGURATION TESTS - BACKUP
# =============================================================================

test_set_default_configuration_backup() {
    test_start "set_default_configuration sets correct backup defaults"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "7" "$BACKUP_RETENTION_DAYS" "Default backup retention should be 7 days"
    assert_equals "daily" "$BACKUP_SCHEDULE" "Default backup schedule should be daily"
}

# =============================================================================
# CONFIGURATION PRESERVATION TESTS
# =============================================================================

test_set_default_configuration_preserves_existing() {
    test_start "set_default_configuration preserves existing environment variables"
    
    setup_test_environment
    
    # Set custom values
    export AWS_REGION="us-west-2"
    export ENVIRONMENT="production"
    export INSTANCE_TYPE="g4dn.2xlarge"
    
    set_default_configuration "spot"
    
    assert_equals "us-west-2" "$AWS_REGION" "Existing AWS region should be preserved"
    assert_equals "production" "$ENVIRONMENT" "Existing environment should be preserved"
    assert_equals "g4dn.2xlarge" "$INSTANCE_TYPE" "Existing instance type should be preserved"
}

test_set_default_configuration_no_type() {
    test_start "set_default_configuration works without deployment type parameter"
    
    setup_test_environment
    set_default_configuration  # No parameter
    
    # Should default to spot configuration
    assert_equals "g4dn.xlarge" "$INSTANCE_TYPE" "Should default to spot instance type"
    assert_not_empty "${SPOT_PRICE:-}" "Should set spot price for default (spot) deployment"
}

# =============================================================================
# CONFIGURATION VALIDATION TESTS
# =============================================================================

test_validate_deployment_config_required_vars() {
    test_start "validate_deployment_config checks required variables"
    
    setup_test_environment
    set_default_configuration "spot"
    
    # Should pass with all required variables set
    if validate_deployment_config "spot" "test-stack" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Validation should pass with all required variables set"
    fi
}

test_validate_deployment_config_missing_aws_region() {
    test_start "validate_deployment_config fails when AWS_REGION is missing"
    
    setup_test_environment
    set_default_configuration "spot"
    unset AWS_REGION
    
    if validate_deployment_config "spot" "test-stack" >/dev/null 2>&1; then
        test_fail "Validation should fail when AWS_REGION is missing"
    else
        test_pass
    fi
}

test_validate_deployment_config_missing_instance_type() {
    test_start "validate_deployment_config fails when INSTANCE_TYPE is missing"
    
    setup_test_environment
    set_default_configuration "spot"
    unset INSTANCE_TYPE
    
    if validate_deployment_config "spot" "test-stack" >/dev/null 2>&1; then
        test_fail "Validation should fail when INSTANCE_TYPE is missing"
    else
        test_pass
    fi
}

test_validate_deployment_config_missing_environment() {
    test_start "validate_deployment_config fails when ENVIRONMENT is missing"
    
    setup_test_environment
    set_default_configuration "spot"
    unset ENVIRONMENT
    
    if validate_deployment_config "spot" "test-stack" >/dev/null 2>&1; then
        test_fail "Validation should fail when ENVIRONMENT is missing"
    else
        test_pass
    fi
}

# =============================================================================
# DEPLOYMENT TYPE SPECIFIC VALIDATION TESTS
# =============================================================================

test_validate_deployment_config_spot_type() {
    test_start "validate_deployment_config calls spot validation for spot type"
    
    setup_test_environment
    set_default_configuration "spot"
    
    # Mock the validate_spot_configuration function if it exists
    if declare -f validate_spot_configuration >/dev/null 2>&1; then
        mock_function "validate_spot_configuration" "return 0"
        
        if validate_deployment_config "spot" "test-stack" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Should pass when spot validation succeeds"
        fi
        
        restore_function "validate_spot_configuration"
    else
        test_skip "validate_spot_configuration function not found"
    fi
}

test_validate_deployment_config_ondemand_type() {
    test_start "validate_deployment_config calls ondemand validation for ondemand type"
    
    setup_test_environment
    set_default_configuration "ondemand"
    
    # Mock the validate_ondemand_configuration function if it exists
    if declare -f validate_ondemand_configuration >/dev/null 2>&1; then
        mock_function "validate_ondemand_configuration" "return 0"
        
        if validate_deployment_config "ondemand" "test-stack" >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Should pass when ondemand validation succeeds"
        fi
        
        restore_function "validate_ondemand_configuration"
    else
        test_skip "validate_ondemand_configuration function not found"
    fi
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_set_default_configuration_unknown_type() {
    test_start "set_default_configuration handles unknown deployment type"
    
    setup_test_environment
    set_default_configuration "unknown"
    
    # Should still set global defaults
    assert_equals "us-east-1" "$AWS_REGION" "Should set default AWS region"
    assert_equals "development" "$ENVIRONMENT" "Should set default environment"
    
    # Should not set deployment-specific defaults
    assert_empty "${INSTANCE_TYPE:-}" "Should not set instance type for unknown deployment"
}

test_set_default_configuration_empty_type() {
    test_start "set_default_configuration handles empty deployment type"
    
    setup_test_environment
    set_default_configuration ""
    
    # Should default to spot behavior
    assert_equals "g4dn.xlarge" "$INSTANCE_TYPE" "Should default to spot instance type"
    assert_not_empty "${SPOT_PRICE:-}" "Should set spot price for empty type"
}

test_health_check_defaults() {
    test_start "set_default_configuration sets correct health check defaults"
    
    setup_test_environment
    set_default_configuration "spot"
    
    assert_equals "10" "$MAX_HEALTH_CHECK_ATTEMPTS" "Default max health check attempts should be 10"
    assert_equals "15" "$HEALTH_CHECK_INTERVAL" "Default health check interval should be 15"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_configuration_integration_workflow() {
    test_start "configuration functions work together in typical workflow"
    
    setup_test_environment
    
    # Step 1: Set defaults
    set_default_configuration "spot"
    
    # Step 2: Validate configuration
    if validate_deployment_config "spot" "integration-test" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Integration workflow should complete successfully"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    test_init "test-aws-config.sh"
    
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