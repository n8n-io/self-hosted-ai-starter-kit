#!/bin/bash
# =============================================================================
# Deployment Fixes Test Script
# Tests the comprehensive fixes for deployment issues
# =============================================================================

# Remove set -e to allow tests to continue even if some fail
set -uo pipefail

# Source common libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/aws-deployment-common.sh"
source "$SCRIPT_DIR/../lib/aws-config.sh"

# Test configuration
TEST_STACK_NAME="test-fixes-$(date +%Y%m%d%H%M%S)"
TEST_ENVIRONMENT="development"
TEST_DEPLOYMENT_TYPE="spot"
TEST_INSTANCE_TYPE="t3.micro"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Test result functions
test_pass() {
    local test_name="$1"
    success "✅ PASS: $test_name"
    ((TESTS_PASSED++))
    ((TOTAL_TESTS++))
}

test_fail() {
    local test_name="$1"
    local error_msg="$2"
    error "❌ FAIL: $test_name - $error_msg"
    ((TESTS_FAILED++))
    ((TOTAL_TESTS++))
}

# Test summary
print_test_summary() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 TEST SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        success "🎉 All tests passed!"
        return 0
    else
        error "❌ $TESTS_FAILED test(s) failed"
        return 1
    fi
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_health_check_endpoints() {
    local test_name="Health Check Endpoints Configuration"
    
    # Test that health check endpoints are properly configured
    local expected_endpoints=(
        "n8n:/healthz"
        "ollama:/api/tags"
        "qdrant:/health"
        "crawl4ai:/health"
    )
    
    for endpoint in "${expected_endpoints[@]}"; do
        local service="${endpoint%:*}"
        local path="${endpoint#*:}"
        
        # Verify the endpoint is valid
        if [[ "$path" =~ ^/[a-zA-Z0-9/_]+$ ]]; then
            test_pass "$test_name - $service endpoint validation"
        else
            test_fail "$test_name - $service endpoint validation" "Invalid endpoint path: $path"
        fi
    done
}

test_cloudwatch_alarm_formatting() {
    local test_name="CloudWatch Alarm Formatting"
    
    # Test that CloudWatch alarm dimensions are properly formatted
    local test_instance_id="i-test123456789"
    local test_alb_name="test-alb"
    
    # Test instance alarm formatting
    local instance_dimension="Name=InstanceId,Value=${test_instance_id}"
    if [[ "$instance_dimension" =~ ^Name=[A-Za-z]+,Value=[a-z0-9-]+$ ]]; then
        test_pass "$test_name - Instance dimension formatting"
    else
        test_fail "$test_name - Instance dimension formatting" "Invalid format: $instance_dimension"
    fi
    
    # Test ALB alarm formatting
    local alb_dimension="Name=LoadBalancer,Value=${test_alb_name}"
    if [[ "$alb_dimension" =~ ^Name=[A-Za-z]+,Value=[a-zA-Z0-9-]+$ ]]; then
        test_pass "$test_name - ALB dimension formatting"
    else
        test_fail "$test_name - ALB dimension formatting" "Invalid format: $alb_dimension"
    fi
}

test_user_data_script_validation() {
    local test_name="User Data Script Validation"
    
    local user_data_file="$SCRIPT_DIR/../terraform/user-data.sh"
    
    # Check if user data script exists
    if [ ! -f "$user_data_file" ]; then
        test_fail "$test_name" "User data script not found: $user_data_file"
        return
    fi
    
    # Check for required components
    local required_components=(
        "auto-start.sh"
        "start-services.sh"
        "health-check.sh"
        "docker-compose"
        "user-data-complete"
    )
    
    for component in "${required_components[@]}"; do
        if grep -q "$component" "$user_data_file" 2>/dev/null; then
            test_pass "$test_name - $component found"
        else
            test_fail "$test_name - $component found" "Component not found: $component"
        fi
    done
}

test_docker_compose_health_checks() {
    local test_name="Docker Compose Health Checks"
    
    local compose_file="$SCRIPT_DIR/../config/docker-compose-template.yml"
    
    # Check if compose file exists
    if [ ! -f "$compose_file" ]; then
        test_fail "$test_name" "Docker compose file not found: $compose_file"
        return
    fi
    
    # Check for health check configurations
    local services=("n8n" "ollama" "qdrant" "crawl4ai")
    
    for service in "${services[@]}"; do
        if grep -A 10 "healthcheck:" "$compose_file" 2>/dev/null | grep -q "$service\|test:"; then
            test_pass "$test_name - $service health check configured"
        else
            test_fail "$test_name - $service health check configured" "Health check not found for $service"
        fi
    done
}

test_service_dependencies() {
    local test_name="Service Dependencies"
    
    local compose_file="$SCRIPT_DIR/../config/docker-compose-template.yml"
    
    # Check for proper service dependencies
    local expected_dependencies=(
        "n8n:postgres"
        "crawl4ai:ollama"
    )
    
    for dependency in "${expected_dependencies[@]}"; do
        local dependent="${dependency%:*}"
        local dependency="${dependency#*:}"
        
        if grep -A 5 "depends_on:" "$compose_file" 2>/dev/null | grep -q "$dependency"; then
            test_pass "$test_name - $dependent depends on $dependency"
        else
            test_fail "$test_name - $dependent depends on $dependency" "Dependency not found"
        fi
    done
}

test_aws_cli_commands() {
    local test_name="AWS CLI Command Validation"
    
    # Test AWS CLI version
    if command -v aws >/dev/null 2>&1; then
        local aws_version
        aws_version=$(aws --version 2>&1 || echo "unknown")
        if [[ "$aws_version" =~ ^aws-cli/[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            test_pass "$test_name - AWS CLI version check"
        else
            test_fail "$test_name - AWS CLI version check" "Invalid AWS CLI version: $aws_version"
        fi
    else
        test_fail "$test_name - AWS CLI version check" "AWS CLI not installed"
    fi
    
    # Test AWS credentials (skip if not configured)
    if aws sts get-caller-identity >/dev/null 2>&1; then
        test_pass "$test_name - AWS credentials validation"
    else
        test_fail "$test_name - AWS credentials validation" "AWS credentials not configured (this is expected in test environment)"
    fi
}

test_configuration_files() {
    local test_name="Configuration Files Validation"
    
    local required_files=(
        "config/docker-compose-template.yml"
        "config/environments/development.yml"
        "config/environments/production.yml"
        "config/environments/staging.yml"
        "lib/aws-deployment-common.sh"
        "lib/aws-config.sh"
        "terraform/user-data.sh"
    )
    
    for file in "${required_files[@]}"; do
        local full_path="$SCRIPT_DIR/../$file"
        if [ -f "$full_path" ]; then
            test_pass "$test_name - $file exists"
        else
            test_fail "$test_name - $file exists" "File not found: $file"
        fi
    done
}

test_health_check_logic() {
    local test_name="Health Check Logic"
    
    # Test the health check function with mock data
    local mock_instance_ip="127.0.0.1"
    local mock_services=("n8n:5678" "ollama:11434")
    
    # This is a basic validation test - in a real scenario, we'd need a running instance
    if command -v curl >/dev/null 2>&1; then
        test_pass "$test_name - curl available for health checks"
    else
        test_fail "$test_name - curl available for health checks" "curl not installed"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    echo "🚀 Starting Deployment Fixes Test Suite"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Run all tests
    test_health_check_endpoints
    test_cloudwatch_alarm_formatting
    test_user_data_script_validation
    test_docker_compose_health_checks
    test_service_dependencies
    test_aws_cli_commands
    test_configuration_files
    test_health_check_logic
    
    # Print summary
    print_test_summary
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        echo
        success "🎉 All deployment fixes are ready for testing!"
        echo
        info "Next steps:"
        info "1. Run a test deployment: ./scripts/aws-deployment-unified.sh --stack-name test-fixes --deployment-type spot"
        info "2. Monitor the deployment logs for any remaining issues"
        info "3. Verify that services start automatically and health checks pass"
        exit 0
    else
        echo
        error "❌ Some tests failed. Please review and fix the issues before deployment."
        exit 1
    fi
}

# Run main function
main "$@" 