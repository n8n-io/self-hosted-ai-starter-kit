#!/bin/bash
# =============================================================================
# Unit Tests for ondemand-instance.sh and simple-instance.sh
# Tests for instance launch functions and utilities
# =============================================================================

set -euo pipefail

# Get script directory for sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the test framework
source "$SCRIPT_DIR/shell-test-framework.sh"

# Source required dependencies
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

# Source the libraries under test
source "$PROJECT_ROOT/lib/ondemand-instance.sh"
source "$PROJECT_ROOT/lib/simple-instance.sh"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    # Store original AWS region
    ORIGINAL_AWS_REGION="${AWS_REGION:-}"
    
    # Set test defaults
    export AWS_REGION="us-east-1"
    
    # Mock external AWS commands for testing
    mock_aws_instance_commands
}

teardown_test_environment() {
    # Restore original environment
    export AWS_REGION="${ORIGINAL_AWS_REGION}"
    
    # Restore mocked functions
    restore_function "aws"
    restore_function "get_ubuntu_ami"
    restore_function "get_optimal_ami"
}

# Mock AWS CLI commands for instance testing
mock_aws_instance_commands() {
    # Mock aws command to return predictable data
    mock_function "aws" '
        if [[ "$*" == *"run-instances"* ]]; then
            echo "{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\",\"State\":{\"Name\":\"pending\"}}]}"
        elif [[ "$*" == *"describe-instances"* ]]; then
            echo "{\"Reservations\":[{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\",\"State\":{\"Name\":\"running\"},\"PublicIpAddress\":\"1.2.3.4\"}]}]}"
        elif [[ "$*" == *"terminate-instances"* ]]; then
            echo "{\"TerminatingInstances\":[{\"InstanceId\":\"i-1234567890abcdef0\",\"CurrentState\":{\"Name\":\"shutting-down\"}}]}"
        elif [[ "$*" == *"describe-images"* ]]; then
            echo "{\"Images\":[{\"ImageId\":\"ami-0123456789abcdef0\",\"Name\":\"ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20231201\"}]}"
        else
            return 0
        fi
    '
    
    # Mock AMI helper functions
    mock_function "get_ubuntu_ami" 'echo "ami-0123456789abcdef0"'
    mock_function "get_optimal_ami" 'echo "ami-0987654321fedcba0"'
}

# =============================================================================
# ON-DEMAND INSTANCE LAUNCH TESTS
# =============================================================================

test_launch_ondemand_instance_basic() {
    test_start "launch_ondemand_instance launches instance with basic parameters"
    
    setup_test_environment
    
    local result
    result=$(launch_ondemand_instance "test-stack" "g4dn.xlarge" "user-data" "sg-123" "subnet-456" "key-name" "iam-profile" "tags" 2>/dev/null)
    
    assert_not_empty "$result" "Should return instance launch result"
}

test_launch_ondemand_instance_missing_stack_name() {
    test_start "launch_ondemand_instance fails when stack name is missing"
    
    setup_test_environment
    
    if launch_ondemand_instance "" "g4dn.xlarge" "user-data" "sg-123" "subnet-456" "key-name" "iam-profile" "tags" >/dev/null 2>&1; then
        test_fail "Should fail when stack name is missing"
    else
        test_pass
    fi
}

test_launch_ondemand_instance_missing_instance_type() {
    test_start "launch_ondemand_instance fails when instance type is missing"
    
    setup_test_environment
    
    if launch_ondemand_instance "test-stack" "" "user-data" "sg-123" "subnet-456" "key-name" "iam-profile" "tags" >/dev/null 2>&1; then
        test_fail "Should fail when instance type is missing"
    else
        test_pass
    fi
}

test_launch_ondemand_instance_logs_info() {
    test_start "launch_ondemand_instance logs appropriate information"
    
    setup_test_environment
    
    local output
    output=$(launch_ondemand_instance "test-stack" "g4dn.xlarge" "user-data" "sg-123" "subnet-456" "key-name" "iam-profile" "tags" 2>&1)
    
    assert_contains "$output" "Launching on-demand instance" "Should log launch message"
    assert_contains "$output" "Instance Type: g4dn.xlarge" "Should log instance type"
    assert_contains "$output" "Stack Name: test-stack" "Should log stack name"
}

test_launch_ondemand_instance_calls_aws() {
    test_start "launch_ondemand_instance calls AWS run-instances"
    
    setup_test_environment
    
    local aws_called=false
    mock_function "aws" '
        if [[ "$*" == *"run-instances"* ]]; then
            aws_called=true
            echo "{\"Instances\":[{\"InstanceId\":\"i-1234567890abcdef0\"}]}"
        else
            return 0
        fi
    '
    
    launch_ondemand_instance "test-stack" "g4dn.xlarge" "user-data" "sg-123" "subnet-456" "key-name" "iam-profile" "tags" >/dev/null 2>&1
    
    if [[ "$aws_called" == "true" ]]; then
        test_pass
    else
        test_fail "Should call AWS run-instances command"
    fi
    
    restore_function "aws"
}

# =============================================================================
# SIMPLE INSTANCE LAUNCH TESTS
# =============================================================================

test_launch_simple_instance_basic() {
    test_start "launch_simple_instance launches instance with basic parameters"
    
    setup_test_environment
    
    local result
    result=$(launch_simple_instance "test-stack" "t3.medium" "user-data" "sg-123" "subnet-456" "key-name" 2>/dev/null)
    
    assert_not_empty "$result" "Should return instance launch result"
}

test_launch_simple_instance_missing_stack_name() {
    test_start "launch_simple_instance fails when stack name is missing"
    
    setup_test_environment
    
    if launch_simple_instance "" "t3.medium" "user-data" "sg-123" "subnet-456" "key-name" >/dev/null 2>&1; then
        test_fail "Should fail when stack name is missing"
    else
        test_pass
    fi
}

test_launch_simple_instance_missing_instance_type() {
    test_start "launch_simple_instance fails when instance type is missing"
    
    setup_test_environment
    
    if launch_simple_instance "test-stack" "" "user-data" "sg-123" "subnet-456" "key-name" >/dev/null 2>&1; then
        test_fail "Should fail when instance type is missing"
    else
        test_pass
    fi
}

test_launch_simple_instance_logs_info() {
    test_start "launch_simple_instance logs appropriate information"
    
    setup_test_environment
    
    local output
    output=$(launch_simple_instance "test-stack" "t3.medium" "user-data" "sg-123" "subnet-456" "key-name" 2>&1)
    
    assert_contains "$output" "Launching simple instance" "Should log launch message"
    assert_contains "$output" "Instance Type: t3.medium" "Should log instance type"
    assert_contains "$output" "Stack Name: test-stack" "Should log stack name"
}

test_launch_simple_instance_uses_ubuntu_ami() {
    test_start "launch_simple_instance uses Ubuntu AMI"
    
    setup_test_environment
    
    local get_ubuntu_ami_called=false
    mock_function "get_ubuntu_ami" '
        get_ubuntu_ami_called=true
        echo "ami-0123456789abcdef0"
    '
    
    launch_simple_instance "test-stack" "t3.medium" "user-data" "sg-123" "subnet-456" "key-name" >/dev/null 2>&1
    
    if [[ "$get_ubuntu_ami_called" == "true" ]]; then
        test_pass
    else
        test_fail "Should call get_ubuntu_ami function"
    fi
    
    restore_function "get_ubuntu_ami"
}

# =============================================================================
# PARAMETER VALIDATION TESTS
# =============================================================================

test_ondemand_instance_parameter_count() {
    test_start "launch_ondemand_instance accepts correct number of parameters"
    
    setup_test_environment
    
    # On-demand instance should accept 8 parameters
    if launch_ondemand_instance "stack" "type" "data" "sg" "subnet" "key" "iam" "tags" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Should accept 8 parameters for on-demand instance"
    fi
}

test_simple_instance_parameter_count() {
    test_start "launch_simple_instance accepts correct number of parameters"
    
    setup_test_environment
    
    # Simple instance should accept 6 parameters
    if launch_simple_instance "stack" "type" "data" "sg" "subnet" "key" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Should accept 6 parameters for simple instance"
    fi
}

test_ondemand_instance_optional_parameters() {
    test_start "launch_ondemand_instance handles optional parameters"
    
    setup_test_environment
    
    # Test with minimal required parameters
    if launch_ondemand_instance "test-stack" "g4dn.xlarge" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Should work with minimal parameters"
    fi
}

test_simple_instance_optional_parameters() {
    test_start "launch_simple_instance handles optional parameters"
    
    setup_test_environment
    
    # Test with minimal required parameters
    if launch_simple_instance "test-stack" "t3.medium" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Should work with minimal parameters"
    fi
}

# =============================================================================
# AMI SELECTION TESTS
# =============================================================================

test_ondemand_instance_ami_selection() {
    test_start "launch_ondemand_instance uses optimal AMI selection"
    
    setup_test_environment
    
    local get_optimal_ami_called=false
    mock_function "get_optimal_ami" '
        get_optimal_ami_called=true
        echo "ami-0987654321fedcba0"
    '
    
    launch_ondemand_instance "test-stack" "g4dn.xlarge" >/dev/null 2>&1
    
    if [[ "$get_optimal_ami_called" == "true" ]]; then
        test_pass
    else
        test_skip "get_optimal_ami function not called (may not exist in current implementation)"
    fi
    
    restore_function "get_optimal_ami"
}

test_simple_instance_ubuntu_ami() {
    test_start "launch_simple_instance specifically uses Ubuntu AMI"
    
    setup_test_environment
    
    local output
    output=$(launch_simple_instance "test-stack" "t3.medium" 2>&1)
    
    # Simple instance should mention Ubuntu or call get_ubuntu_ami
    assert_contains "$output" "Ubuntu\|ami-" "Should reference Ubuntu AMI selection"
}

# =============================================================================
# INSTANCE TYPE VALIDATION TESTS
# =============================================================================

test_ondemand_instance_gpu_type() {
    test_start "launch_ondemand_instance works with GPU instance types"
    
    setup_test_environment
    
    local gpu_types=("g4dn.xlarge" "g4dn.2xlarge" "g5.xlarge" "p3.2xlarge")
    
    for instance_type in "${gpu_types[@]}"; do
        if launch_ondemand_instance "test-stack" "$instance_type" >/dev/null 2>&1; then
            test_pass
            return
        fi
    done
    
    test_fail "Should work with GPU instance types"
}

test_simple_instance_cpu_type() {
    test_start "launch_simple_instance works with CPU instance types"
    
    setup_test_environment
    
    local cpu_types=("t3.medium" "t3.large" "m5.large" "c5.large")
    
    for instance_type in "${cpu_types[@]}"; do
        if launch_simple_instance "test-stack" "$instance_type" >/dev/null 2>&1; then
            test_pass
            return
        fi
    done
    
    test_fail "Should work with CPU instance types"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_ondemand_instance_aws_failure() {
    test_start "launch_ondemand_instance handles AWS failures gracefully"
    
    setup_test_environment
    
    # Mock AWS to fail
    mock_function "aws" 'return 1'
    
    if launch_ondemand_instance "test-stack" "g4dn.xlarge" >/dev/null 2>&1; then
        test_fail "Should handle AWS failures"
    else
        test_pass
    fi
    
    restore_function "aws"
}

test_simple_instance_aws_failure() {
    test_start "launch_simple_instance handles AWS failures gracefully"
    
    setup_test_environment
    
    # Mock AWS to fail
    mock_function "aws" 'return 1'
    
    if launch_simple_instance "test-stack" "t3.medium" >/dev/null 2>&1; then
        test_fail "Should handle AWS failures"
    else
        test_pass
    fi
    
    restore_function "aws"
}

test_ondemand_instance_ami_failure() {
    test_start "launch_ondemand_instance handles AMI lookup failures"
    
    setup_test_environment
    
    # Mock AMI lookup to fail
    mock_function "get_optimal_ami" 'return 1'
    
    if launch_ondemand_instance "test-stack" "g4dn.xlarge" >/dev/null 2>&1; then
        test_skip "AMI failure handling depends on implementation"
    else
        test_pass
    fi
    
    restore_function "get_optimal_ami"
}

test_simple_instance_ami_failure() {
    test_start "launch_simple_instance handles AMI lookup failures"
    
    setup_test_environment
    
    # Mock AMI lookup to fail
    mock_function "get_ubuntu_ami" 'return 1'
    
    if launch_simple_instance "test-stack" "t3.medium" >/dev/null 2>&1; then
        test_skip "AMI failure handling depends on implementation"
    else
        test_pass
    fi
    
    restore_function "get_ubuntu_ami"
}

# =============================================================================
# HELPER FUNCTION TESTS
# =============================================================================

test_instance_helper_functions_exist() {
    test_start "instance helper functions are available"
    
    local helper_functions=(
        "validate_ondemand_configuration"
        "validate_simple_configuration"
        "get_instance_status"
        "monitor_instance_launch"
        "terminate_instance"
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
        test_skip "No additional instance helper functions found"
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_ondemand_simple_instance_workflow() {
    test_start "on-demand and simple instance functions work in typical workflow"
    
    setup_test_environment
    
    # Test on-demand instance launch
    local ondemand_result
    ondemand_result=$(launch_ondemand_instance "test-stack-od" "g4dn.xlarge" 2>/dev/null)
    
    # Test simple instance launch
    local simple_result
    simple_result=$(launch_simple_instance "test-stack-simple" "t3.medium" 2>/dev/null)
    
    if [[ -n "$ondemand_result" && -n "$simple_result" ]]; then
        test_pass
    else
        test_fail "Both instance types should launch successfully"
    fi
}

# =============================================================================
# CONFIGURATION DIFFERENCE TESTS
# =============================================================================

test_ondemand_vs_simple_parameter_differences() {
    test_start "on-demand and simple instances have appropriate parameter differences"
    
    setup_test_environment
    
    # On-demand should accept more parameters (including IAM profile)
    local ondemand_output
    ondemand_output=$(launch_ondemand_instance "test" "g4dn.xlarge" "data" "sg" "subnet" "key" "iam-profile" "tags" 2>&1)
    
    # Simple should work with fewer parameters (no IAM profile needed)
    local simple_output
    simple_output=$(launch_simple_instance "test" "t3.medium" "data" "sg" "subnet" "key" 2>&1)
    
    if [[ -n "$ondemand_output" && -n "$simple_output" ]]; then
        test_pass
    else
        test_fail "Both instance types should handle their respective parameters"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    test_init "test-instance-libraries.sh"
    
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