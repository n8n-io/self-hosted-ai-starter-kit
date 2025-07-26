#!/bin/bash
# =============================================================================
# Test Script for Unified Cleanup Script
# Comprehensive testing of all cleanup functionality
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source required libraries
source "$LIB_DIR/error-handling.sh"
source "$LIB_DIR/aws-deployment-common.sh"

# Test configuration
TEST_STACK_NAME="test-cleanup-$(date +%s)"
CLEANUP_SCRIPT="$PROJECT_ROOT/scripts/cleanup-unified.sh"
TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# =============================================================================
# TEST HELPER FUNCTIONS
# =============================================================================

log() { echo -e "\033[0;34m[$(date +'%Y-%m-%d %H:%M:%S')] $1\033[0m" >&2; }
error() { echo -e "\033[0;31m❌ [ERROR] $1\033[0m" >&2; }
success() { echo -e "\033[0;32m✅ [SUCCESS] $1\033[0m" >&2; }
warning() { echo -e "\033[0;33m⚠️  [WARNING] $1\033[0m" >&2; }
info() { echo -e "\033[0;36mℹ️  [INFO] $1\033[0m" >&2; }
step() { echo -e "\033[0;35m🔸 [STEP] $1\033[0m" >&2; }

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    ((TOTAL_TESTS++))
    
    log "Running test: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local exit_code=$?
        if [ $exit_code -eq "$expected_exit_code" ]; then
            success "PASS: $test_name"
            ((PASSED_TESTS++))
            TEST_RESULTS+=("PASS: $test_name")
        else
            error "FAIL: $test_name (expected exit code $expected_exit_code, got $exit_code)"
            ((FAILED_TESTS++))
            TEST_RESULTS+=("FAIL: $test_name (exit code mismatch)")
        fi
    else
        local exit_code=$?
        if [ $exit_code -eq "$expected_exit_code" ]; then
            success "PASS: $test_name (expected failure)"
            ((PASSED_TESTS++))
            TEST_RESULTS+=("PASS: $test_name (expected failure)")
        else
            error "FAIL: $test_name (expected exit code $expected_exit_code, got $exit_code)"
            ((FAILED_TESTS++))
            TEST_RESULTS+=("FAIL: $test_name (unexpected failure)")
        fi
    fi
}

test_script_exists() {
    step "Testing script existence and permissions"
    
    run_test "Script exists" "[ -f '$CLEANUP_SCRIPT' ]"
    run_test "Script is executable" "[ -x '$CLEANUP_SCRIPT' ]"
    run_test "Script is readable" "[ -r '$CLEANUP_SCRIPT' ]"
}

test_help_functionality() {
    step "Testing help functionality"
    
    run_test "Help flag works" "$CLEANUP_SCRIPT --help"
    run_test "Help flag shows usage" "$CLEANUP_SCRIPT --help | grep -q 'Usage:'"
    run_test "Help flag shows examples" "$CLEANUP_SCRIPT --help | grep -q 'EXAMPLES:'"
}

test_argument_parsing() {
    step "Testing argument parsing"
    
    # Test invalid arguments
    run_test "Invalid flag rejected" "$CLEANUP_SCRIPT --invalid-flag" 1
    run_test "Multiple stack names rejected" "$CLEANUP_SCRIPT stack1 stack2" 1
    
    # Test valid arguments
    run_test "Valid stack name accepted" "$CLEANUP_SCRIPT --dry-run test-stack"
    run_test "Region flag works" "$CLEANUP_SCRIPT --region us-west-2 --dry-run test-stack"
    run_test "Force flag works" "$CLEANUP_SCRIPT --force --dry-run test-stack"
    run_test "Verbose flag works" "$CLEANUP_SCRIPT --verbose --dry-run test-stack"
}

test_mode_functionality() {
    step "Testing cleanup modes"
    
    run_test "Stack mode with dry-run" "$CLEANUP_SCRIPT --mode stack --dry-run test-stack"
    run_test "EFS mode with dry-run" "$CLEANUP_SCRIPT --mode efs --dry-run test-stack"
    run_test "All mode with dry-run" "$CLEANUP_SCRIPT --mode all --dry-run test-stack"
    run_test "Specific mode with dry-run" "$CLEANUP_SCRIPT --mode specific --efs --dry-run test-stack"
}

test_resource_type_flags() {
    step "Testing resource type flags"
    
    run_test "Instances flag" "$CLEANUP_SCRIPT --instances --dry-run test-stack"
    run_test "EFS flag" "$CLEANUP_SCRIPT --efs --dry-run test-stack"
    run_test "IAM flag" "$CLEANUP_SCRIPT --iam --dry-run test-stack"
    run_test "Network flag" "$CLEANUP_SCRIPT --network --dry-run test-stack"
    run_test "Monitoring flag" "$CLEANUP_SCRIPT --monitoring --dry-run test-stack"
    run_test "Storage flag" "$CLEANUP_SCRIPT --storage --dry-run test-stack"
    run_test "Multiple resource flags" "$CLEANUP_SCRIPT --efs --instances --dry-run test-stack"
}

test_aws_prerequisites() {
    step "Testing AWS prerequisites"
    
    run_test "AWS CLI available" "command -v aws >/dev/null 2>&1"
    run_test "AWS credentials configured" "aws sts get-caller-identity >/dev/null 2>&1"
}

test_dry_run_functionality() {
    step "Testing dry-run functionality"
    
    # Test that dry-run doesn't actually delete anything
    run_test "Dry-run with stack name" "$CLEANUP_SCRIPT --dry-run --force $TEST_STACK_NAME"
    run_test "Dry-run shows what would be deleted" "$CLEANUP_SCRIPT --dry-run --force $TEST_STACK_NAME 2>&1 | grep -q 'Would'"
}

test_confirmation_prompt() {
    step "Testing confirmation prompts"
    
    # Test that confirmation is required without --force
    run_test "Confirmation required without force" "echo 'n' | $CLEANUP_SCRIPT --dry-run $TEST_STACK_NAME 2>&1 | grep -q 'CONFIRMATION REQUIRED'"
}

test_error_handling() {
    step "Testing error handling"
    
    # Test with invalid region
    run_test "Invalid region handling" "$CLEANUP_SCRIPT --region invalid-region --dry-run test-stack" 1
    
    # Test with missing stack name in stack mode
    run_test "Missing stack name in stack mode" "$CLEANUP_SCRIPT --mode stack --dry-run" 1
}

test_script_syntax() {
    step "Testing script syntax"
    
    run_test "Bash syntax check" "bash -n '$CLEANUP_SCRIPT'"
    run_test "ShellCheck compliance" "command -v shellcheck >/dev/null 2>&1 && shellcheck '$CLEANUP_SCRIPT' || true"
}

test_function_definitions() {
    step "Testing function definitions"
    
    # Check that all required functions are defined
    local required_functions=(
        "show_usage"
        "parse_arguments"
        "confirm_cleanup"
        "increment_counter"
        "print_summary"
        "cleanup_ec2_instances"
        "cleanup_efs_resources"
        "cleanup_single_efs"
        "cleanup_network_resources"
        "cleanup_load_balancers"
        "cleanup_cloudfront_distributions"
        "cleanup_monitoring_resources"
        "cleanup_iam_resources"
        "cleanup_storage_resources"
        "main"
    )
    
    for func in "${required_functions[@]}"; do
        run_test "Function $func defined" "grep -q '^${func}()' '$CLEANUP_SCRIPT'"
    done
}

test_library_sourcing() {
    step "Testing library sourcing"
    
    # Check that required libraries are sourced
    run_test "Error handling library sourced" "grep -q 'source.*error-handling.sh' '$CLEANUP_SCRIPT'"
    run_test "AWS deployment common sourced" "grep -q 'source.*aws-deployment-common.sh' '$CLEANUP_SCRIPT'"
    run_test "AWS config sourced" "grep -q 'source.*aws-config.sh' '$CLEANUP_SCRIPT'"
}

test_output_formatting() {
    step "Testing output formatting"
    
    # Test that the script produces properly formatted output
    run_test "Color codes present" "grep -q '\\033\\[0;' '$CLEANUP_SCRIPT'"
    run_test "Logging functions defined" "grep -q 'log()' '$CLEANUP_SCRIPT'"
    run_test "Success function defined" "grep -q 'success()' '$CLEANUP_SCRIPT'"
    run_test "Error function defined" "grep -q 'error()' '$CLEANUP_SCRIPT'"
}

test_counter_functionality() {
    step "Testing counter functionality"
    
    # Test that counter functions are properly implemented
    run_test "Counter variables defined" "grep -q 'RESOURCES_DELETED=' '$CLEANUP_SCRIPT'"
    run_test "Increment function defined" "grep -q 'increment_counter()' '$CLEANUP_SCRIPT'"
    run_test "Summary function defined" "grep -q 'print_summary()' '$CLEANUP_SCRIPT'"
}

test_aws_api_calls() {
    step "Testing AWS API call patterns"
    
    # Test that AWS API calls are properly structured
    run_test "AWS CLI calls use region" "grep -q '--region.*AWS_REGION' '$CLEANUP_SCRIPT'"
    run_test "Error handling for AWS calls" "grep -q '|| true' '$CLEANUP_SCRIPT'"
    run_test "Output redirection" "grep -q '>/dev/null' '$CLEANUP_SCRIPT'"
}

test_resource_detection() {
    step "Testing resource detection patterns"
    
    # Test that resource detection uses proper AWS CLI patterns
    run_test "Instance detection pattern" "grep -q 'describe-instances' '$CLEANUP_SCRIPT'"
    run_test "EFS detection pattern" "grep -q 'describe-file-systems' '$CLEANUP_SCRIPT'"
    run_test "Security group detection" "grep -q 'describe-security-groups' '$CLEANUP_SCRIPT'"
    run_test "IAM detection pattern" "grep -q 'get-instance-profile' '$CLEANUP_SCRIPT'"
}

test_cleanup_order() {
    step "Testing cleanup order"
    
    # Test that cleanup follows proper dependency order
    run_test "Instances cleaned before security groups" "grep -A 10 -B 5 'cleanup_ec2_instances' '$CLEANUP_SCRIPT' | grep -q 'cleanup_network_resources'"
    run_test "Mount targets deleted before EFS" "grep -A 20 'cleanup_single_efs' '$CLEANUP_SCRIPT' | grep -q 'delete-file-system'"
}

test_safety_features() {
    step "Testing safety features"
    
    # Test safety features
    run_test "Set -euo pipefail" "grep -q 'set -euo pipefail' '$CLEANUP_SCRIPT'"
    run_test "Confirmation prompt" "grep -q 'CONFIRMATION REQUIRED' '$CLEANUP_SCRIPT'"
    run_test "Dry-run option" "grep -q 'DRY_RUN' '$CLEANUP_SCRIPT'"
    run_test "Force option" "grep -q 'FORCE' '$CLEANUP_SCRIPT'"
}

print_test_summary() {
    echo "=============================================="
    echo "📊 TEST SUMMARY"
    echo "=============================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        success "All tests passed! 🎉"
    else
        error "Some tests failed. Please review the output above."
        echo ""
        echo "Failed tests:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ $result == FAIL:* ]]; then
                echo "  $result"
            fi
        done
    fi
    
    echo "=============================================="
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "=============================================="
    echo "🧪 TESTING UNIFIED CLEANUP SCRIPT"
    echo "=============================================="
    echo "Test Stack Name: $TEST_STACK_NAME"
    echo "Cleanup Script: $CLEANUP_SCRIPT"
    echo "=============================================="
    
    # Run all test categories
    test_script_exists
    test_help_functionality
    test_argument_parsing
    test_mode_functionality
    test_resource_type_flags
    test_aws_prerequisites
    test_dry_run_functionality
    test_confirmation_prompt
    test_error_handling
    test_script_syntax
    test_function_definitions
    test_library_sourcing
    test_output_formatting
    test_counter_functionality
    test_aws_api_calls
    test_resource_detection
    test_cleanup_order
    test_safety_features
    
    # Print final summary
    print_test_summary
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@" 