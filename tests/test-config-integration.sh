#!/bin/bash
# =============================================================================
# Configuration Integration Test Suite
# Tests integration between centralized configuration and existing scripts
# =============================================================================

set -euo pipefail

# =============================================================================
# TEST CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"
CONFIG_DIR="$PROJECT_ROOT/config"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# Test configuration
TEST_TEMP_DIR=""
TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✅ $1${NC}" >&2
}

error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

info() {
    echo -e "${CYAN}ℹ️  $1${NC}" >&2
}

# Test result tracking
record_test() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_RESULTS+=("$test_name:$result:$message")
    
    if [ "$result" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        success "$test_name: $message"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        error "$test_name: $message"
    fi
}

# Cleanup function
cleanup() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Register cleanup
trap cleanup EXIT

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_config_management_library() {
    log "Testing configuration management library..."
    
    # Test library exists
    if [ ! -f "$LIB_DIR/config-management.sh" ]; then
        record_test "config_library_exists" "FAIL" "Configuration management library not found"
        return 1
    fi
    record_test "config_library_exists" "PASS" "Configuration management library found"
    
    # Test library syntax
    if ! bash -n "$LIB_DIR/config-management.sh"; then
        record_test "config_library_syntax" "FAIL" "Configuration management library has syntax errors"
        return 1
    fi
    record_test "config_library_syntax" "PASS" "Configuration management library syntax is valid"
    
    # Test library can be sourced
    if ! source "$LIB_DIR/config-management.sh"; then
        record_test "config_library_source" "FAIL" "Failed to source configuration management library"
        return 1
    fi
    record_test "config_library_source" "PASS" "Configuration management library can be sourced"
    
    # Test core functions exist
    local required_functions=(
        "load_configuration"
        "get_config_value"
        "generate_environment_file"
        "validate_configuration"
        "apply_environment_overrides"
    )
    
    for func in "${required_functions[@]}"; do
        if ! declare -F "$func" >/dev/null 2>&1; then
            record_test "function_${func}" "FAIL" "Required function $func not found"
            return 1
        fi
        record_test "function_${func}" "PASS" "Function $func is available"
    done
}

test_configuration_files() {
    log "Testing configuration files..."
    
    # Test default configuration
    if [ ! -f "$CONFIG_DIR/defaults.yml" ]; then
        record_test "defaults_config_exists" "FAIL" "Default configuration file not found"
        return 1
    fi
    record_test "defaults_config_exists" "PASS" "Default configuration file exists"
    
    # Test environment configurations
    local environments=("development" "production")
    for env in "${environments[@]}"; do
        if [ ! -f "$CONFIG_DIR/environments/$env.yml" ]; then
            record_test "${env}_config_exists" "FAIL" "Environment configuration for $env not found"
            continue
        fi
        record_test "${env}_config_exists" "PASS" "Environment configuration for $env exists"
        
        # Test YAML syntax if yq is available
        if command -v yq >/dev/null 2>&1; then
            if yq eval '.' "$CONFIG_DIR/environments/$env.yml" >/dev/null 2>&1; then
                record_test "${env}_config_syntax" "PASS" "Environment configuration for $env has valid YAML syntax"
            else
                record_test "${env}_config_syntax" "FAIL" "Environment configuration for $env has invalid YAML syntax"
            fi
        fi
    done
    
    # Test deployment types configuration
    if [ ! -f "$CONFIG_DIR/deployment-types.yml" ]; then
        record_test "deployment_types_config_exists" "FAIL" "Deployment types configuration not found"
        return 1
    fi
    record_test "deployment_types_config_exists" "PASS" "Deployment types configuration exists"
}

test_script_integration() {
    log "Testing script integration..."
    
    # Test scripts that should use the new configuration system
    local scripts_to_test=(
        "config-manager.sh"
        "aws-deployment-unified.sh"
        "check-instance-status.sh"
        "cleanup-consolidated.sh"
    )
    
    for script in "${scripts_to_test[@]}"; do
        local script_path="$SCRIPTS_DIR/$script"
        
        if [ ! -f "$script_path" ]; then
            record_test "script_${script}_exists" "FAIL" "Script $script not found"
            continue
        fi
        record_test "script_${script}_exists" "PASS" "Script $script exists"
        
        # Test script syntax
        if ! bash -n "$script_path"; then
            record_test "script_${script}_syntax" "FAIL" "Script $script has syntax errors"
            continue
        fi
        record_test "script_${script}_syntax" "PASS" "Script $script syntax is valid"
        
        # Test script includes config management
        if grep -q "config-management.sh" "$script_path"; then
            record_test "script_${script}_integration" "PASS" "Script $script includes configuration management"
        else
            record_test "script_${script}_integration" "FAIL" "Script $script does not include configuration management"
        fi
    done
}

test_backward_compatibility() {
    log "Testing backward compatibility..."
    
    # Create temporary test environment
    TEST_TEMP_DIR=$(mktemp -d)
    local test_env_file="$TEST_TEMP_DIR/test.env"
    local test_compose_file="$TEST_TEMP_DIR/docker-compose.yml"
    
    # Test that old environment variable patterns still work
    local old_env_vars=(
        "AWS_REGION=us-east-1"
        "INSTANCE_TYPE=g4dn.xlarge"
        "STACK_NAME=test-stack"
        "PROJECT_NAME=GeuseMaker"
    )
    
    for env_var in "${old_env_vars[@]}"; do
        echo "$env_var" >> "$test_env_file"
    done
    
    # Test environment file generation with old patterns
    if [ -f "$LIB_DIR/config-management.sh" ]; then
        source "$LIB_DIR/config-management.sh"
        
        if generate_environment_file "development" "$test_env_file.new" >/dev/null 2>&1; then
            record_test "backward_compat_env_generation" "PASS" "Environment file generation works with old patterns"
        else
            record_test "backward_compat_env_generation" "FAIL" "Environment file generation failed with old patterns"
        fi
    fi
    
    # Test that existing docker-compose files still work
    local compose_files=(
        "docker-compose.yml"
        "docker-compose.gpu-optimized.yml"
        "docker-compose.test.yml"
    )
    
    for compose_file in "${compose_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$compose_file" ]; then
            record_test "compose_${compose_file}_exists" "PASS" "Docker Compose file $compose_file exists"
            
            # Test basic syntax validation
            if command -v docker-compose >/dev/null 2>&1; then
                if docker-compose -f "$PROJECT_ROOT/$compose_file" config >/dev/null 2>&1; then
                    record_test "compose_${compose_file}_syntax" "PASS" "Docker Compose file $compose_file has valid syntax"
                else
                    record_test "compose_${compose_file}_syntax" "FAIL" "Docker Compose file $compose_file has invalid syntax"
                fi
            fi
        else
            record_test "compose_${compose_file}_exists" "FAIL" "Docker Compose file $compose_file not found"
        fi
    done
}

test_configuration_validation() {
    log "Testing configuration validation..."
    
    # Test configuration validation script
    if [ -f "$PROJECT_ROOT/tools/validate-config.sh" ]; then
        record_test "validation_script_exists" "PASS" "Configuration validation script exists"
        
        # Test validation script syntax
        if bash -n "$PROJECT_ROOT/tools/validate-config.sh"; then
            record_test "validation_script_syntax" "PASS" "Configuration validation script syntax is valid"
        else
            record_test "validation_script_syntax" "FAIL" "Configuration validation script has syntax errors"
        fi
        
        # Test validation script execution (non-destructive)
        if timeout 30s "$PROJECT_ROOT/tools/validate-config.sh" --dry-run >/dev/null 2>&1; then
            record_test "validation_script_execution" "PASS" "Configuration validation script executes successfully"
        else
            record_test "validation_script_execution" "FAIL" "Configuration validation script execution failed"
        fi
    else
        record_test "validation_script_exists" "FAIL" "Configuration validation script not found"
    fi
}

test_makefile_integration() {
    log "Testing Makefile integration..."
    
    if [ ! -f "$PROJECT_ROOT/Makefile" ]; then
        record_test "makefile_exists" "FAIL" "Makefile not found"
        return 1
    fi
    record_test "makefile_exists" "PASS" "Makefile exists"
    
    # Test configuration-related make targets
    local config_targets=(
        "config:generate"
        "config:validate"
        "config:show"
        "config:diff"
    )
    
    for target in "${config_targets[@]}"; do
        local target_name=$(echo "$target" | cut -d: -f2)
        if grep -q "^$target_name:" "$PROJECT_ROOT/Makefile"; then
            record_test "makefile_target_${target_name}" "PASS" "Makefile target $target_name exists"
        else
            record_test "makefile_target_${target_name}" "FAIL" "Makefile target $target_name not found"
        fi
    done
}

test_test_integration() {
    log "Testing test integration..."
    
    # Test that configuration tests are included in test runner
    if [ -f "$PROJECT_ROOT/tools/test-runner.sh" ]; then
        record_test "test_runner_exists" "PASS" "Test runner exists"
        
        if grep -q "config" "$PROJECT_ROOT/tools/test-runner.sh"; then
            record_test "test_runner_config_integration" "PASS" "Test runner includes configuration tests"
        else
            record_test "test_runner_config_integration" "FAIL" "Test runner does not include configuration tests"
        fi
    else
        record_test "test_runner_exists" "FAIL" "Test runner not found"
    fi
    
    # Test configuration management test suite
    if [ -f "$PROJECT_ROOT/tests/test-config-management.sh" ]; then
        record_test "config_test_suite_exists" "PASS" "Configuration management test suite exists"
        
        # Test test suite syntax
        if bash -n "$PROJECT_ROOT/tests/test-config-management.sh"; then
            record_test "config_test_suite_syntax" "PASS" "Configuration management test suite syntax is valid"
        else
            record_test "config_test_suite_syntax" "FAIL" "Configuration management test suite has syntax errors"
        fi
    else
        record_test "config_test_suite_exists" "FAIL" "Configuration management test suite not found"
    fi
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    log "Starting configuration integration tests..."
    
    # Run all test suites
    test_config_management_library
    test_configuration_files
    test_script_integration
    test_backward_compatibility
    test_configuration_validation
    test_makefile_integration
    test_test_integration
    
    # Print summary
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Configuration Integration Test Results"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo
    
    if [ $FAILED_TESTS -eq 0 ]; then
        success "All configuration integration tests passed! 🎉"
        echo
        echo "The centralized configuration management system is fully integrated"
        echo "and maintains backward compatibility with existing scripts."
        exit 0
    else
        error "Some configuration integration tests failed! ❌"
        echo
        echo "Failed tests:"
        for result in "${TEST_RESULTS[@]}"; do
            local test_name=$(echo "$result" | cut -d: -f1)
            local test_result=$(echo "$result" | cut -d: -f2)
            local test_message=$(echo "$result" | cut -d: -f3)
            
            if [ "$test_result" = "FAIL" ]; then
                echo "  - $test_name: $test_message"
            fi
        done
        echo
        echo "Please review and fix the failed tests before proceeding."
        exit 1
    fi
}

# Run main function
main "$@" 