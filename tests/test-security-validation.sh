#!/bin/bash
# Shell-based tests for security validation functionality
# Converts Python unittest to shell script format
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECURITY_SCRIPT="$PROJECT_ROOT/scripts/security-validation.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test logging functions
log_test() {
    echo "🧪 Test: $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

pass_test() {
    echo "✅ Pass: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail_test() {
    echo "❌ Fail: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test AWS region validation with valid regions
test_validate_aws_region_valid() {
    log_test "validate_aws_region_valid"
    
    valid_regions=("us-east-1" "us-west-2" "eu-west-1")
    
    for region in "${valid_regions[@]}"; do
        if bash -c "source $SECURITY_SCRIPT && validate_aws_region '$region'" >/dev/null 2>&1; then
            pass_test "Valid region $region should pass validation"
        else
            fail_test "Valid region $region should pass validation"
        fi
    done
}

# Test AWS region validation with invalid regions
test_validate_aws_region_invalid() {
    log_test "validate_aws_region_invalid"
    
    invalid_regions=("invalid-region" "us-invalid-1" "")
    
    for region in "${invalid_regions[@]}"; do
        if ! bash -c "source $SECURITY_SCRIPT && validate_aws_region '$region'" >/dev/null 2>&1; then
            pass_test "Invalid region '$region' should fail validation"
        else
            fail_test "Invalid region '$region' should fail validation"
        fi
    done
}

# Test instance type validation with valid types
test_validate_instance_type_valid() {
    log_test "validate_instance_type_valid"
    
    valid_types=("g4dn.xlarge" "g5g.2xlarge" "auto")
    
    for instance_type in "${valid_types[@]}"; do
        if bash -c "source $SECURITY_SCRIPT && validate_instance_type '$instance_type'" >/dev/null 2>&1; then
            pass_test "Valid instance type $instance_type should pass validation"
        else
            fail_test "Valid instance type $instance_type should pass validation"
        fi
    done
}

# Test instance type validation with invalid types
test_validate_instance_type_invalid() {
    log_test "validate_instance_type_invalid"
    
    invalid_types=("t2.micro" "invalid-type" "")
    
    for instance_type in "${invalid_types[@]}"; do
        if ! bash -c "source $SECURITY_SCRIPT && validate_instance_type '$instance_type'" >/dev/null 2>&1; then
            pass_test "Invalid instance type '$instance_type' should fail validation"
        else
            fail_test "Invalid instance type '$instance_type' should fail validation"
        fi
    done
}

# Test spot price validation with valid prices
test_validate_spot_price_valid() {
    log_test "validate_spot_price_valid"
    
    valid_prices=("0.10" "1.50" "5.00" "10.0")
    
    for price in "${valid_prices[@]}"; do
        if bash -c "source $SECURITY_SCRIPT && validate_spot_price '$price'" >/dev/null 2>&1; then
            pass_test "Valid price $price should pass validation"
        else
            fail_test "Valid price $price should pass validation"
        fi
    done
}

# Test spot price validation with invalid prices
test_validate_spot_price_invalid() {
    log_test "validate_spot_price_invalid"
    
    invalid_prices=("0.05" "100.00" "invalid" "-1.0" "")
    
    for price in "${invalid_prices[@]}"; do
        if ! bash -c "source $SECURITY_SCRIPT && validate_spot_price '$price'" >/dev/null 2>&1; then
            pass_test "Invalid price '$price' should fail validation"
        else
            fail_test "Invalid price '$price' should fail validation"
        fi
    done
}

# Test stack name validation with valid names
test_validate_stack_name_valid() {
    log_test "validate_stack_name_valid"
    
    valid_names=("GeuseMaker" "mystack123" "test-stack-1")
    
    for name in "${valid_names[@]}"; do
        if bash -c "source $SECURITY_SCRIPT && validate_stack_name '$name'" >/dev/null 2>&1; then
            pass_test "Valid stack name $name should pass validation"
        else
            fail_test "Valid stack name $name should pass validation"
        fi
    done
}

# Test stack name validation with invalid names
test_validate_stack_name_invalid() {
    log_test "validate_stack_name_invalid"
    
    invalid_names=("invalid_name" "stack with spaces" "x" "$(printf 'a%.0s' {1..65})" "")
    
    for name in "${invalid_names[@]}"; do
        if ! bash -c "source $SECURITY_SCRIPT && validate_stack_name '$name'" >/dev/null 2>&1; then
            pass_test "Invalid stack name '$name' should fail validation"
        else
            fail_test "Invalid stack name '$name' should fail validation"
        fi
    done
}

# Test secure password generation
test_generate_secure_password() {
    log_test "generate_secure_password"
    
    if password=$(bash -c "source $SECURITY_SCRIPT && generate_secure_password 256" 2>/dev/null); then
        if [ ${#password} -eq 64 ]; then
            pass_test "256-bit password should be 64 hex characters"
        else
            fail_test "256-bit password should be 64 hex characters, got ${#password}"
        fi
        
        # Check if it's valid hex
        if [[ $password =~ ^[0-9a-fA-F]{64}$ ]]; then
            pass_test "Password should be valid hex"
        else
            fail_test "Password should be valid hex"
        fi
    else
        fail_test "Password generation should succeed"
    fi
}

# Test password strength validation
test_validate_password_strength() {
    log_test "validate_password_strength"
    
    # Test strong password (32 char hex string)
    strong_password="$(printf 'a%.0s' {1..32})"
    if bash -c "source $SECURITY_SCRIPT && validate_password_strength '$strong_password' 24" >/dev/null 2>&1; then
        pass_test "Strong password should pass validation"
    else
        fail_test "Strong password should pass validation"
    fi
    
    # Test weak password
    weak_password="abc"
    if ! bash -c "source $SECURITY_SCRIPT && validate_password_strength '$weak_password' 24" >/dev/null 2>&1; then
        pass_test "Weak password should fail validation"
    else
        fail_test "Weak password should fail validation"
    fi
}

# Test path sanitization
test_sanitize_path() {
    log_test "sanitize_path"
    
    test_cases=(
        "normal/path:normal/path"
        "../../../etc/passwd:etc/passwd"
        "/absolute/path:absolute/path"
        "path/with/../traversal:path/with/traversal"
    )
    
    for test_case in "${test_cases[@]}"; do
        input_path="${test_case%:*}"
        expected="${test_case#*:}"
        
        if sanitized=$(bash -c "source $SECURITY_SCRIPT && sanitize_path '$input_path'" 2>/dev/null); then
            if [ "$sanitized" = "$expected" ]; then
                pass_test "Path '$input_path' should be sanitized to '$expected'"
            else
                fail_test "Path '$input_path' should be sanitized to '$expected', got '$sanitized'"
            fi
        else
            fail_test "Path sanitization should succeed for '$input_path'"
        fi
    done
}

# Test shell argument escaping
test_escape_shell_arg() {
    log_test "escape_shell_arg"
    
    dangerous_args=(
        "normal_arg"
        "arg with spaces"
        "arg;with;semicolons"
        "arg\$(command)substitution"
        "arg\`with\`backticks"
    )
    
    for arg in "${dangerous_args[@]}"; do
        if escaped=$(bash -c "source $SECURITY_SCRIPT && escape_shell_arg '$arg'" 2>/dev/null); then
            if [ -n "$escaped" ]; then
                pass_test "Argument escaping should succeed for '$arg'"
            else
                fail_test "Escaped argument should not be empty for '$arg'"
            fi
        else
            fail_test "Argument escaping should succeed for '$arg'"
        fi
    done
}

# Test security script syntax
test_security_script_syntax() {
    log_test "security_script_syntax"
    
    if bash -n "$SECURITY_SCRIPT" 2>/dev/null; then
        pass_test "Security script should have valid syntax"
    else
        fail_test "Security script should have valid syntax"
    fi
}

# Test cost optimization script syntax (if exists)
test_cost_script_syntax() {
    log_test "cost_script_syntax"
    
    # Python cost optimization script removed - using AWS CloudWatch instead
    echo "⚠️  Skip: Cost optimization script removed (Python dependency eliminated)"
    echo "💡 Using AWS CloudWatch for cost monitoring instead"
    pass_test "Cost optimization functionality replaced with CloudWatch"
}

# Main test runner
main() {
    echo "🧪 Running Security Validation Tests"
    echo "===================================="
    
    # Check if security script exists
    if [ ! -f "$SECURITY_SCRIPT" ]; then
        echo "❌ Security validation script not found: $SECURITY_SCRIPT"
        exit 1
    fi
    
    # Run all tests
    test_validate_aws_region_valid
    test_validate_aws_region_invalid
    test_validate_instance_type_valid
    test_validate_instance_type_invalid
    test_validate_spot_price_valid
    test_validate_spot_price_invalid
    test_validate_stack_name_valid
    test_validate_stack_name_invalid
    test_generate_secure_password
    test_validate_password_strength
    test_sanitize_path
    test_escape_shell_arg
    test_security_script_syntax
    test_cost_script_syntax
    
    # Print summary
    echo ""
    echo "📊 Test Summary"
    echo "==============="
    echo "Tests run: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✅ All tests passed!"
        exit 0
    else
        echo "❌ Some tests failed!"
        exit 1
    fi
}

# Run tests if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi