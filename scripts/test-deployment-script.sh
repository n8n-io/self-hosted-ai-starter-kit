#!/bin/bash

# =============================================================================
# Deployment Script Test
# =============================================================================
# This script tests the deployment script generation to ensure no infinite loops
# =============================================================================

set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Test deployment script generation
test_deployment_script_generation() {
    log "Testing deployment script generation..."
    
    # Create a minimal test environment
    local test_public_ip="192.168.1.100"
    local test_efs_dns="fs-12345678.efs.us-east-1.amazonaws.com"
    local test_instance_id="i-1234567890abcdef0"
    
    # Source the deployment script to get the function
    if [ -f "scripts/aws-deployment-unified.sh" ]; then
        # Extract the deploy_application function
        local deploy_function=$(grep -A 10 "deploy_application()" scripts/aws-deployment-unified.sh | head -20 || grep -A 10 "deploy_application" scripts/aws-deployment-unified.sh | head -20)
        
        if [ -n "$deploy_function" ]; then
            success "Deployment function found"
            
            # Test if the function generates the deploy-app.sh script correctly
            # We'll create a minimal test by extracting the script generation part
            local script_generation=$(grep -A 50 "cat > deploy-app.sh" scripts/aws-deployment-unified.sh | head -100)
            
            if [ -n "$script_generation" ]; then
                success "Script generation logic found"
                
                # Check for potential infinite loops in the generated script
                local loop_indicators=(
                    "install_docker_compose.*install_docker_compose"
                    "shared_install_docker_compose.*shared_install_docker_compose"
                    "install_docker_compose.*shared_install_docker_compose"
                )
                
                local found_loops=0
                for pattern in "${loop_indicators[@]}"; do
                    if echo "$script_generation" | grep -q "$pattern"; then
                        error "Potential infinite loop detected: $pattern"
                        found_loops=$((found_loops + 1))
                    fi
                done
                
                if [ $found_loops -eq 0 ]; then
                    success "No infinite loops detected in script generation"
                else
                    error "Found $found_loops potential infinite loops"
                    return 1
                fi
                
                # Check for proper function calls
                if echo "$script_generation" | grep -q "command -v install_docker_compose"; then
                    success "Proper function availability check found"
                else
                    warning "Function availability check not found"
                fi
                
                return 0
            else
                error "Script generation logic not found"
                return 1
            fi
        else
            error "Deployment function not found"
            return 1
        fi
    else
        error "Deployment script not found"
        return 1
    fi
}

# Test shared library integration
test_shared_library_integration() {
    log "Testing shared library integration..."
    
    # Check if shared library exists
    if [ -f "lib/aws-deployment-common.sh" ]; then
        success "Shared library found"
        
        # Check if install_docker_compose function exists
        if grep -q "install_docker_compose()" lib/aws-deployment-common.sh; then
            success "install_docker_compose function found in shared library"
        else
            error "install_docker_compose function not found in shared library"
            return 1
        fi
        
        # Check for function name conflicts
        local function_count=$(grep -c "install_docker_compose()" lib/aws-deployment-common.sh)
        if [ "$function_count" -eq 1 ]; then
            success "No function name conflicts detected"
        else
            error "Multiple install_docker_compose functions found ($function_count)"
            return 1
        fi
        
        return 0
    else
        error "Shared library not found"
        return 1
    fi
}

# Test for breaking changes
test_breaking_changes() {
    log "Testing for breaking changes..."
    
    # Check if existing functions are still available
    local required_functions=(
        "deploy_application"
        "install_docker_compose"
        "wait_for_apt_lock"
    )
    
    local missing_functions=0
    for func in "${required_functions[@]}"; do
        if grep -q "${func}()" scripts/aws-deployment-unified.sh || grep -q "${func}()" lib/aws-deployment-common.sh; then
            success "Function $func found"
        else
            error "Required function $func not found"
            missing_functions=$((missing_functions + 1))
        fi
    done
    
    if [ $missing_functions -eq 0 ]; then
        success "No breaking changes detected"
        return 0
    else
        error "Found $missing_functions missing functions (potential breaking changes)"
        return 1
    fi
}

# Test script syntax
test_script_syntax() {
    log "Testing script syntax..."
    
    local scripts_to_test=(
        "scripts/aws-deployment-unified.sh"
        "lib/aws-deployment-common.sh"
        "scripts/test-docker-compose-fix.sh"
    )
    
    local syntax_errors=0
    for script in "${scripts_to_test[@]}"; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>/dev/null; then
                success "Syntax check passed for $script"
            else
                error "Syntax error in $script"
                syntax_errors=$((syntax_errors + 1))
            fi
        else
            warning "Script $script not found, skipping syntax check"
        fi
    done
    
    if [ $syntax_errors -eq 0 ]; then
        success "All scripts have valid syntax"
        return 0
    else
        error "Found $syntax_errors syntax errors"
        return 1
    fi
}

# Main test execution
main() {
    log "Starting deployment script tests..."
    
    local tests_passed=0
    local tests_failed=0
    
    # Test 1: Script syntax
    if test_script_syntax; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    # Test 2: Shared library integration
    if test_shared_library_integration; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    # Test 3: Breaking changes
    if test_breaking_changes; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    # Test 4: Deployment script generation
    if test_deployment_script_generation; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    # Summary
    log "Test summary: $tests_passed passed, $tests_failed failed"
    
    if [ $tests_failed -eq 0 ]; then
        success "All tests passed! Deployment script is working correctly."
        return 0
    else
        error "Some tests failed. Please review the output above."
        return 1
    fi
}

# Run tests
main "$@" 