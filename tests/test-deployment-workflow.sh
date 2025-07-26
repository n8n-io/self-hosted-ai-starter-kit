#!/bin/bash
# Shell-based tests for deployment workflow
# Converts Python integration tests to shell script format
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

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

skip_test() {
    echo "⚠️  Skip: $1"
}

# Test config manager can execute help command
test_config_manager_help() {
    log_test "config_manager_help"
    
    config_manager="$SCRIPTS_DIR/config-manager.sh"
    if [ ! -f "$config_manager" ]; then
        skip_test "Config manager script not found"
        return
    fi
    
    if output=$(bash "$config_manager" help 2>&1) && echo "$output" | grep -q "Configuration Manager"; then
        pass_test "Config manager help should work"
    else
        fail_test "Config manager help should work"
    fi
}

# Test security check script can execute
test_security_check_execution() {
    log_test "security_check_execution"
    
    security_check="$SCRIPTS_DIR/security-check.sh"
    if [ ! -f "$security_check" ]; then
        skip_test "Security check script not found"
        return
    fi
    
    # Run with timeout to prevent hanging
    if timeout 60 bash "$security_check" 2>&1 | grep -q "Security"; then
        pass_test "Security check script should execute"
    else
        fail_test "Security check script should execute"
    fi
}

# Test deployment validation script syntax
test_validate_deployment_syntax() {
    log_test "validate_deployment_syntax"
    
    validate_script="$SCRIPTS_DIR/validate-deployment.sh"
    if [ ! -f "$validate_script" ]; then
        skip_test "Validation script not found"
        return
    fi
    
    if bash -n "$validate_script" 2>/dev/null; then
        pass_test "Validation script should have valid syntax"
    else
        fail_test "Validation script should have valid syntax"
    fi
}

# Test Docker Compose file validity
test_docker_compose_validity() {
    log_test "docker_compose_validity"
    
    compose_file="$PROJECT_ROOT/docker-compose.gpu-optimized.yml"
    if [ ! -f "$compose_file" ]; then
        skip_test "Docker Compose file not found"
        return
    fi
    
    # Test basic YAML syntax with python if available
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml; yaml.safe_load(open('$compose_file'))" 2>/dev/null; then
            pass_test "Docker Compose file should have valid YAML"
        else
            fail_test "Docker Compose file should have valid YAML"
        fi
    else
        # Fallback: check for obvious syntax issues
        if grep -q "version:" "$compose_file" && grep -q "services:" "$compose_file"; then
            pass_test "Docker Compose file appears to have basic structure"
        else
            fail_test "Docker Compose file should have basic structure"
        fi
    fi
}

# Test container versions are pinned (no :latest)
test_container_versions_pinned() {
    log_test "container_versions_pinned"
    
    compose_file="$PROJECT_ROOT/docker-compose.gpu-optimized.yml"
    if [ ! -f "$compose_file" ]; then
        skip_test "Docker Compose file not found"
        return
    fi
    
    if ! grep -q ":latest" "$compose_file"; then
        pass_test "Docker Compose should not use :latest tags"
    else
        fail_test "Docker Compose should not use :latest tags"
    fi
    
    # Check for specific version patterns
    version_patterns=(
        "postgres:16.1-alpine3.19"
        "n8nio/n8n:1.19.4"
        "qdrant/qdrant:v1.7.3"
        "ollama/ollama:0.1.17"
    )
    
    for pattern in "${version_patterns[@]}"; do
        if grep -q "$pattern" "$compose_file"; then
            pass_test "Should contain pinned version: $pattern"
        else
            fail_test "Should contain pinned version: $pattern"
        fi
    done
}

# Test environment configuration files exist
test_environment_config_files() {
    log_test "environment_config_files"
    
    config_dir="$PROJECT_ROOT/config/environments"
    required_files=("development.yml" "production.yml")
    
    for filename in "${required_files[@]}"; do
        filepath="$config_dir/$filename"
        if [ -f "$filepath" ]; then
            pass_test "Configuration file should exist: $filename"
            
            # Test basic YAML validity with python if available
            if command -v python3 >/dev/null 2>&1; then
                if python3 -c "
import yaml
with open('$filepath') as f:
    config = yaml.safe_load(f)
    assert isinstance(config, dict)
    required_sections = ['global', 'infrastructure', 'applications', 'security']
    for section in required_sections:
        assert section in config, f'Missing section: {section}'
" 2>/dev/null; then
                    pass_test "Configuration file should be valid YAML: $filename"
                else
                    fail_test "Configuration file should be valid YAML: $filename"
                fi
            else
                # Fallback: basic structure check
                if grep -q "global:" "$filepath" && grep -q "infrastructure:" "$filepath"; then
                    pass_test "Configuration file appears valid: $filename"
                else
                    fail_test "Configuration file should have required sections: $filename"
                fi
            fi
        else
            fail_test "Configuration file should exist: $filename"
        fi
    done
}

# Test deployment scripts have security validation
test_deployment_scripts_security() {
    log_test "deployment_scripts_security"
    
    deployment_scripts=(
        "aws-deployment-unified.sh"
        "aws-deployment-simple.sh"
        "aws-deployment-ondemand.sh"
    )
    
    for script_name in "${deployment_scripts[@]}"; do
        script_path="$SCRIPTS_DIR/$script_name"
        if [ -f "$script_path" ]; then
            if grep -q "security-validation.sh" "$script_path"; then
                pass_test "Deployment script should load security validation: $script_name"
            else
                fail_test "Deployment script should load security validation: $script_name"
            fi
        fi
    done
}

# Test .gitignore protects sensitive files
test_gitignore_protection() {
    log_test "gitignore_protection"
    
    gitignore_path="$PROJECT_ROOT/.gitignore"
    if [ ! -f "$gitignore_path" ]; then
        skip_test ".gitignore file not found"
        return
    fi
    
    sensitive_patterns=(
        "*.pem"
        "*.key"
        "**/credentials/*.json"
        "*secret*"
        "*password*"
        ".env"
        ".aws/"
    )
    
    for pattern in "${sensitive_patterns[@]}"; do
        if grep -Fq "$pattern" "$gitignore_path"; then
            pass_test ".gitignore should protect sensitive files: $pattern"
        else
            fail_test ".gitignore should protect sensitive files: $pattern"
        fi
    done
}

# Test demo credentials have warnings
test_demo_credentials_warnings() {
    log_test "demo_credentials_warnings"
    
    credentials_dir="$PROJECT_ROOT/n8n/demo-data/credentials"
    if [ ! -d "$credentials_dir" ]; then
        skip_test "Demo credentials directory not found"
        return
    fi
    
    for filepath in "$credentials_dir"/*.json; do
        [ -f "$filepath" ] || continue
        filename=$(basename "$filepath")
        
        if command -v python3 >/dev/null 2>&1; then
            if python3 -c "
import json
with open('$filepath') as f:
    data = json.load(f)
    warning_fields = ['_WARNING', '_SECURITY_NOTICE', '_USAGE']
    has_warning = any(field in data for field in warning_fields)
    assert has_warning, 'No security warning found'
" 2>/dev/null; then
                pass_test "Demo credential file should have security warning: $filename"
            else
                fail_test "Demo credential file should have security warning: $filename"
            fi
        else
            # Fallback: grep for warning patterns
            if grep -q "_WARNING\|_SECURITY\|_USAGE" "$filepath"; then
                pass_test "Demo credential file appears to have warning: $filename"
            else
                fail_test "Demo credential file should have warning: $filename"
            fi
        fi
    done
}

# Test container security configuration
test_container_security_config() {
    log_test "container_security_config"
    
    compose_file="$PROJECT_ROOT/docker-compose.gpu-optimized.yml"
    if [ ! -f "$compose_file" ]; then
        skip_test "Docker Compose file not found"
        return
    fi
    
    security_configs=(
        "no-new-privileges:true"
        "user:"
        "security_opt:"
        "read_only:"
    )
    
    for config in "${security_configs[@]}"; do
        if grep -q "$config" "$compose_file"; then
            pass_test "Docker Compose should have security config: $config"
        else
            fail_test "Docker Compose should have security config: $config"
        fi
    done
}

# Test all shell scripts have valid syntax
test_all_scripts_syntax() {
    log_test "all_scripts_syntax"
    
    for script_path in "$SCRIPTS_DIR"/*.sh; do
        [ -f "$script_path" ] || continue
        filename=$(basename "$script_path")
        
        if bash -n "$script_path" 2>/dev/null; then
            pass_test "Script should have valid syntax: $filename"
        else
            fail_test "Script should have valid syntax: $filename"
        fi
    done
}

# Test Python scripts have valid syntax (if python available)
test_python_scripts_syntax() {
    log_test "python_scripts_syntax"
    
    if ! command -v python3 >/dev/null 2>&1; then
        skip_test "Python3 not available for syntax checking"
        return
    fi
    
    for script_path in "$SCRIPTS_DIR"/*.py; do
        [ -f "$script_path" ] || continue
        filename=$(basename "$script_path")
        
        if python3 -m py_compile "$script_path" 2>/dev/null; then
            pass_test "Python script should have valid syntax: $filename"
        else
            fail_test "Python script should have valid syntax: $filename"
        fi
    done
}

# Test scripts are executable
test_scripts_executable() {
    log_test "scripts_executable"
    
    executable_scripts=(
        "security-validation.sh"
        "security-check.sh"
        "validate-deployment.sh"
        "config-manager.sh"
    )
    
    for script_name in "${executable_scripts[@]}"; do
        script_path="$SCRIPTS_DIR/$script_name"
        if [ -f "$script_path" ]; then
            if [ -x "$script_path" ]; then
                pass_test "Script should be executable: $script_name"
            else
                fail_test "Script should be executable: $script_name"
            fi
        fi
    done
}

# Main test runner
main() {
    echo "🧪 Running Deployment Workflow Tests"
    echo "====================================="
    
    # Run all tests
    test_config_manager_help
    test_security_check_execution
    test_validate_deployment_syntax
    test_docker_compose_validity
    test_container_versions_pinned
    test_environment_config_files
    test_deployment_scripts_security
    test_gitignore_protection
    test_demo_credentials_warnings
    test_container_security_config
    test_all_scripts_syntax
    test_python_scripts_syntax
    test_scripts_executable
    
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