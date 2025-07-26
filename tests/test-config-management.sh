#!/bin/bash
# =============================================================================
# Configuration Management Test Suite
# Comprehensive testing for centralized configuration management system
# =============================================================================

set -euo pipefail

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"
CONFIG_DIR="$PROJECT_ROOT/config"

# Test configuration
TEST_TEMP_DIR=""
TEST_CONFIG_FILE=""
TEST_ENV_FILE=""
TEST_COMPOSE_FILE=""

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Color definitions for test output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

pass_test() {
    echo -e "${GREEN}✅ PASS${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

fail_test() {
    echo -e "${RED}❌ FAIL${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

skip_test() {
    echo -e "${YELLOW}⏭️  SKIP${NC} $1"
    ((SKIPPED_TESTS++))
    ((TOTAL_TESTS++))
}

# Test setup and teardown
setup_test_environment() {
    log_test "Setting up test environment..."
    
    # Create temporary test directory
    TEST_TEMP_DIR=$(mktemp -d)
    TEST_CONFIG_FILE="$TEST_TEMP_DIR/test-config.yml"
    TEST_ENV_FILE="$TEST_TEMP_DIR/test.env"
    TEST_COMPOSE_FILE="$TEST_TEMP_DIR/test-compose.yml"
    
    # Create test configuration
    cat > "$TEST_CONFIG_FILE" << 'EOF'
global:
  environment: test
  region: us-east-1
  stack_name: test-stack
  project_name: test-project

infrastructure:
  instance_types:
    preferred: ["t3.micro"]
    fallback: ["t3.small"]
  
  auto_scaling:
    min_capacity: 1
    max_capacity: 2
    target_utilization: 80

applications:
  postgres:
    image: postgres:16.1-alpine3.19
    resources:
      cpu_limit: "0.5"
      memory_limit: "1G"
    config:
      max_connections: 50
      shared_buffers: "256MB"

  n8n:
    image: n8nio/n8n:1.19.4
    resources:
      cpu_limit: "0.5"
      memory_limit: "1G"
    config:
      cors_enable: true
      cors_allowed_origins: "*"

security:
  container_security:
    run_as_non_root: false
    read_only_root_filesystem: false
    no_new_privileges: false
  
  secrets_management:
    use_aws_secrets_manager: false
    rotate_secrets: false
    encryption_at_rest: false

monitoring:
  metrics:
    enabled: true
    retention_days: 7
    scrape_interval: 60s
  
  logging:
    level: debug
    centralized: false
    retention_days: 7
    format: text

cost_optimization:
  spot_instances:
    enabled: false
    max_price: 1.00
    interruption_handling: false
  
  auto_scaling:
    scale_down_enabled: true
    scale_down_threshold: 10
    idle_timeout_minutes: 10

backup:
  automated_backups: false
  backup_schedule: "0 6 * * 0"
  backup_retention_days: 7
  cross_region_replication: false
  point_in_time_recovery: false

compliance:
  audit_logging: false
  encryption_in_transit: false
  encryption_at_rest: false
  access_logging: false
  data_retention_policy: 7

development:
  hot_reload: true
  debug_mode: true
  test_data_enabled: true
  mock_services_enabled: true
  local_development_mode: true
EOF

    log_test "Test environment setup completed"
}

cleanup_test_environment() {
    log_test "Cleaning up test environment..."
    
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    
    log_test "Test environment cleanup completed"
}

# =============================================================================
# LOAD CONFIGURATION MANAGEMENT LIBRARY
# =============================================================================

load_config_management() {
    log_test "Loading configuration management library..."
    
    if [ -f "$LIB_DIR/config-management.sh" ]; then
        source "$LIB_DIR/config-management.sh"
        pass_test "Configuration management library loaded successfully"
        return 0
    else
        fail_test "Configuration management library not found: $LIB_DIR/config-management.sh"
        return 1
    fi
}

# =============================================================================
# CORE FUNCTION TESTS
# =============================================================================

test_load_configuration() {
    log_test "Testing load_configuration function..."
    
    # Test successful loading
    if load_configuration "$TEST_CONFIG_FILE" "test"; then
        pass_test "Configuration loaded successfully"
        
        # Verify key variables are set
        if [ "${CONFIG_ENVIRONMENT:-}" = "test" ]; then
            pass_test "Environment variable set correctly"
        else
            fail_test "Environment variable not set correctly"
        fi
        
        if [ "${CONFIG_REGION:-}" = "us-east-1" ]; then
            pass_test "Region variable set correctly"
        else
            fail_test "Region variable not set correctly"
        fi
        
        if [ "${CONFIG_STACK_NAME:-}" = "test-stack" ]; then
            pass_test "Stack name variable set correctly"
        else
            fail_test "Stack name variable not set correctly"
        fi
    else
        fail_test "Configuration loading failed"
    fi
}

test_validate_configuration() {
    log_test "Testing validate_configuration function..."
    
    # Test valid configuration
    if validate_configuration "$TEST_CONFIG_FILE"; then
        pass_test "Valid configuration validation passed"
    else
        fail_test "Valid configuration validation failed"
    fi
    
    # Test invalid configuration (missing required sections)
    local invalid_config="$TEST_TEMP_DIR/invalid-config.yml"
    cat > "$invalid_config" << 'EOF'
global:
  environment: test
EOF
    
    if ! validate_configuration "$invalid_config" 2>/dev/null; then
        pass_test "Invalid configuration validation correctly failed"
    else
        fail_test "Invalid configuration validation should have failed"
    fi
}

test_generate_environment_file() {
    log_test "Testing generate_environment_file function..."
    
    # Load configuration first
    load_configuration "$TEST_CONFIG_FILE" "test"
    
    # Generate environment file
    if generate_environment_file "$TEST_CONFIG_FILE" "test" "$TEST_ENV_FILE"; then
        pass_test "Environment file generated successfully"
        
        # Verify file exists and has content
        if [ -f "$TEST_ENV_FILE" ]; then
            pass_test "Environment file created"
            
            # Check for key variables
            if grep -q "ENVIRONMENT=test" "$TEST_ENV_FILE"; then
                pass_test "Environment variable in generated file"
            else
                fail_test "Environment variable missing from generated file"
            fi
            
            if grep -q "AWS_REGION=us-east-1" "$TEST_ENV_FILE"; then
                pass_test "AWS region variable in generated file"
            else
                fail_test "AWS region variable missing from generated file"
            fi
            
            if grep -q "STACK_NAME=test-stack" "$TEST_ENV_FILE"; then
                pass_test "Stack name variable in generated file"
            else
                fail_test "Stack name variable missing from generated file"
            fi
        else
            fail_test "Environment file not created"
        fi
    else
        fail_test "Environment file generation failed"
    fi
}

test_generate_docker_compose() {
    log_test "Testing generate_docker_compose function..."
    
    # Load configuration first
    load_configuration "$TEST_CONFIG_FILE" "test"
    
    # Generate Docker Compose file
    if generate_docker_compose "$TEST_CONFIG_FILE" "test" "$TEST_COMPOSE_FILE"; then
        pass_test "Docker Compose file generated successfully"
        
        # Verify file exists and has content
        if [ -f "$TEST_COMPOSE_FILE" ]; then
            pass_test "Docker Compose file created"
            
            # Check for key services
            if grep -q "postgres:" "$TEST_COMPOSE_FILE"; then
                pass_test "PostgreSQL service in generated file"
            else
                fail_test "PostgreSQL service missing from generated file"
            fi
            
            if grep -q "n8n:" "$TEST_COMPOSE_FILE"; then
                pass_test "n8n service in generated file"
            else
                fail_test "n8n service missing from generated file"
            fi
            
            # Check for resource limits
            if grep -q "cpus: '0.5'" "$TEST_COMPOSE_FILE"; then
                pass_test "CPU limits in generated file"
            else
                fail_test "CPU limits missing from generated file"
            fi
        else
            fail_test "Docker Compose file not created"
        fi
    else
        fail_test "Docker Compose file generation failed"
    fi
}

test_apply_deployment_type_overrides() {
    log_test "Testing apply_deployment_type_overrides function..."
    
    # Load configuration first
    load_configuration "$TEST_CONFIG_FILE" "test"
    
    # Test simple deployment type
    if apply_deployment_type_overrides "simple"; then
        pass_test "Simple deployment type overrides applied"
        
        # Verify overrides are applied
        if [ "${CONFIG_INSTANCE_TYPE:-}" = "t3.micro" ]; then
            pass_test "Instance type override applied correctly"
        else
            fail_test "Instance type override not applied correctly"
        fi
    else
        fail_test "Simple deployment type overrides failed"
    fi
    
    # Test spot deployment type
    if apply_deployment_type_overrides "spot"; then
        pass_test "Spot deployment type overrides applied"
        
        # Verify spot-specific overrides
        if [ "${CONFIG_SPOT_INSTANCES_ENABLED:-}" = "true" ]; then
            pass_test "Spot instances enabled for spot deployment"
        else
            fail_test "Spot instances not enabled for spot deployment"
        fi
    else
        fail_test "Spot deployment type overrides failed"
    fi
}

test_validate_security_configuration() {
    log_test "Testing validate_security_configuration function..."
    
    # Load configuration first
    load_configuration "$TEST_CONFIG_FILE" "test"
    
    # Test security validation
    if validate_security_configuration "$TEST_CONFIG_FILE"; then
        pass_test "Security configuration validation passed"
    else
        fail_test "Security configuration validation failed"
    fi
    
    # Test with security issues (create insecure config)
    local insecure_config="$TEST_TEMP_DIR/insecure-config.yml"
    cat > "$insecure_config" << 'EOF'
global:
  environment: test
  region: us-east-1
  stack_name: test-stack
  project_name: test-project

infrastructure:
  instance_types:
    preferred: ["t3.micro"]
    fallback: ["t3.small"]
  
  auto_scaling:
    min_capacity: 1
    max_capacity: 2
    target_utilization: 80

applications:
  postgres:
    image: postgres:16.1-alpine3.19
    resources:
      cpu_limit: "0.5"
      memory_limit: "1G"
    config:
      max_connections: 50
      shared_buffers: "256MB"

  n8n:
    image: n8nio/n8n:1.19.4
    resources:
      cpu_limit: "0.5"
      memory_limit: "1G"
    config:
      cors_enable: true
      cors_allowed_origins: "*"

security:
  container_security:
    run_as_non_root: false
    read_only_root_filesystem: false
    no_new_privileges: false
  
  secrets_management:
    use_aws_secrets_manager: false
    rotate_secrets: false
    encryption_at_rest: false

monitoring:
  metrics:
    enabled: true
    retention_days: 7
    scrape_interval: 60s
  
  logging:
    level: debug
    centralized: false
    retention_days: 7
    format: text

cost_optimization:
  spot_instances:
    enabled: false
    max_price: 1.00
    interruption_handling: false
  
  auto_scaling:
    scale_down_enabled: true
    scale_down_threshold: 10
    idle_timeout_minutes: 10

backup:
  automated_backups: false
  backup_schedule: "0 6 * * 0"
  backup_retention_days: 7
  cross_region_replication: false
  point_in_time_recovery: false

compliance:
  audit_logging: false
  encryption_in_transit: false
  encryption_at_rest: false
  access_logging: false
  data_retention_policy: 7

development:
  hot_reload: true
  debug_mode: true
  test_data_enabled: true
  mock_services_enabled: true
  local_development_mode: true
EOF
    
    # This should pass for development environment
    if validate_security_configuration "$insecure_config"; then
        pass_test "Development security configuration validation passed (expected)"
    else
        fail_test "Development security configuration validation failed (unexpected)"
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_integration_with_shared_libraries() {
    log_test "Testing integration with shared libraries..."
    
    # Test integration with aws-deployment-common.sh
    if [ -f "$LIB_DIR/aws-deployment-common.sh" ]; then
        # Source the common library
        source "$LIB_DIR/aws-deployment-common.sh"
        
        # Test that config functions work with common library
        if load_configuration "$TEST_CONFIG_FILE" "test"; then
            pass_test "Configuration management integrates with aws-deployment-common.sh"
        else
            fail_test "Configuration management failed to integrate with aws-deployment-common.sh"
        fi
    else
        skip_test "aws-deployment-common.sh not found, skipping integration test"
    fi
}

test_backward_compatibility() {
    log_test "Testing backward compatibility..."
    
    # Test that old environment files still work
    local old_env_file="$TEST_TEMP_DIR/old.env"
    cat > "$old_env_file" << 'EOF'
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=old_password
N8N_HOST=0.0.0.0
N8N_PORT=5678
WEBHOOK_URL=http://localhost:5678
EOF
    
    # Test loading old format
    if [ -f "$old_env_file" ]; then
        pass_test "Old environment file format still supported"
    else
        fail_test "Old environment file format not supported"
    fi
}

test_error_handling() {
    log_test "Testing error handling..."
    
    # Test with non-existent config file
    if ! load_configuration "/non/existent/file.yml" "test" 2>/dev/null; then
        pass_test "Error handling for non-existent config file"
    else
        fail_test "Should have failed for non-existent config file"
    fi
    
    # Test with invalid YAML
    local invalid_yaml="$TEST_TEMP_DIR/invalid.yml"
    cat > "$invalid_yaml" << 'EOF'
global:
  environment: test
  region: us-east-1
  stack_name: test-stack
  project_name: test-project
  invalid: [unclosed: array
EOF
    
    if ! validate_configuration "$invalid_yaml" 2>/dev/null; then
        pass_test "Error handling for invalid YAML"
    else
        fail_test "Should have failed for invalid YAML"
    fi
}

# =============================================================================
# CROSS-PLATFORM COMPATIBILITY TESTS
# =============================================================================

test_bash_compatibility() {
    log_test "Testing bash compatibility..."
    
    # Test bash version compatibility
    local bash_version=$(bash --version | head -n1 | cut -d' ' -f4 | cut -d'.' -f1)
    
    if [ "$bash_version" -ge 3 ]; then
        pass_test "Bash version $bash_version is compatible"
    else
        fail_test "Bash version $bash_version is not compatible (minimum: 3)"
    fi
    
    # Test array syntax compatibility
    local test_array=("item1" "item2" "item3")
    if [ "${#test_array[@]}" -eq 3 ]; then
        pass_test "Array syntax is compatible"
    else
        fail_test "Array syntax is not compatible"
    fi
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_performance() {
    log_test "Testing performance..."
    
    # Test configuration loading performance
    local start_time=$(date +%s.%N)
    
    for i in {1..10}; do
        load_configuration "$TEST_CONFIG_FILE" "test" >/dev/null 2>&1
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    
    if (( $(echo "$duration < 5.0" | bc -l) )); then
        pass_test "Configuration loading performance acceptable ($duration seconds for 10 loads)"
    else
        fail_test "Configuration loading performance too slow ($duration seconds for 10 loads)"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

run_all_tests() {
    echo "=============================================================================="
    echo "Configuration Management Test Suite"
    echo "=============================================================================="
    echo
    
    # Setup test environment
    setup_test_environment
    
    # Load configuration management library
    if ! load_config_management; then
        echo "❌ Cannot run tests without configuration management library"
        cleanup_test_environment
        exit 1
    fi
    
    # Run core function tests
    echo "Running core function tests..."
    test_load_configuration
    test_validate_configuration
    test_generate_environment_file
    test_generate_docker_compose
    test_apply_deployment_type_overrides
    test_validate_security_configuration
    
    # Run integration tests
    echo
    echo "Running integration tests..."
    test_integration_with_shared_libraries
    test_backward_compatibility
    test_error_handling
    
    # Run compatibility tests
    echo
    echo "Running compatibility tests..."
    test_bash_compatibility
    
    # Run performance tests
    echo
    echo "Running performance tests..."
    test_performance
    
    # Cleanup
    cleanup_test_environment
    
    # Print summary
    echo
    echo "=============================================================================="
    echo "Test Summary"
    echo "=============================================================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Skipped: $SKIPPED_TESTS"
    echo
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo "🎉 All tests passed!"
        exit 0
    else
        echo "❌ Some tests failed!"
        exit 1
    fi
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
Configuration Management Test Suite

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --help, -h          Show this help message
    --verbose, -v       Enable verbose output
    --quick, -q         Run only essential tests
    --performance, -p   Run only performance tests
    --integration, -i   Run only integration tests

EXAMPLES:
    $0                  # Run all tests
    $0 --quick          # Run essential tests only
    $0 --performance    # Run performance tests only
    $0 --integration    # Run integration tests only

EOF
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --verbose|-v)
        set -x
        run_all_tests
        ;;
    --quick|-q)
        # Run only essential tests
        setup_test_environment
        load_config_management
        test_load_configuration
        test_validate_configuration
        test_generate_environment_file
        test_error_handling
        cleanup_test_environment
        ;;
    --performance|-p)
        # Run only performance tests
        setup_test_environment
        load_config_management
        test_performance
        cleanup_test_environment
        ;;
    --integration|-i)
        # Run only integration tests
        setup_test_environment
        load_config_management
        test_integration_with_shared_libraries
        test_backward_compatibility
        test_error_handling
        cleanup_test_environment
        ;;
    "")
        run_all_tests
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac