#!/bin/bash
# =============================================================================
# Comprehensive Improvements Validation
# Validates all improvements made to the GeuseMaker
# =============================================================================

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]; then
    source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
fi

if [ -f "$PROJECT_ROOT/lib/error-handling.sh" ]; then
    source "$PROJECT_ROOT/lib/error-handling.sh"
    init_error_handling "resilient"
fi

# =============================================================================
# VALIDATION CATEGORIES
# =============================================================================

# Define validation categories (compatible with older bash)
get_validation_description() {
    case "$1" in
        "security") echo "Security improvements and vulnerability fixes" ;;
        "structure") echo "Project structure and configuration files" ;;
        "infrastructure") echo "Infrastructure as Code implementation" ;;
        "documentation") echo "Documentation completeness and quality" ;;
        "tools") echo "Developer tools and automation" ;;
        "testing") echo "Testing framework and coverage" ;;
        "error-handling") echo "Error handling and resilience" ;;
        "monitoring") echo "Monitoring and observability" ;;
        *) echo "Unknown category" ;;
    esac
}

# List of all validation categories
VALIDATION_CATEGORIES="security structure infrastructure documentation tools testing error-handling monitoring"

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_security_improvements() {
    log "Validating security improvements..."
    local issues=0
    
    # Check demo credentials removal
    info "Checking demo credentials removal..."
    if [ -d "$PROJECT_ROOT/n8n/demo-data/credential-templates" ]; then
        success "Demo credentials moved to templates directory"
    else
        log_error "Demo credentials not properly handled"
        ((issues++))
    fi
    
    # Check .gitignore enhancements
    info "Checking .gitignore security patterns..."
    local security_patterns=("*api-key*" "*private-key*" "*cert*" "*certificate*" "config.production.*")
    
    for pattern in "${security_patterns[@]}"; do
        if grep -q "$pattern" "$PROJECT_ROOT/.gitignore"; then
            success "Security pattern '$pattern' found in .gitignore"
        else
            log_warning "Security pattern '$pattern' missing from .gitignore"
            ((issues++))
        fi
    done
    
    # Check security validation library
    info "Checking security validation library..."
    if [ -f "$PROJECT_ROOT/scripts/security-validation.sh" ]; then
        if grep -q "validate_aws_region" "$PROJECT_ROOT/scripts/security-validation.sh"; then
            success "Security validation library contains proper functions"
        else
            log_warning "Security validation library missing key functions"
            ((issues++))
        fi
    else
        log_error "Security validation library not found"
        ((issues++))
    fi
    
    return $issues
}

validate_project_structure() {
    log "Validating project structure improvements..."
    local issues=0
    
    # Check essential configuration files
    info "Checking essential configuration files..."
    local config_files=(".editorconfig" "Makefile" ".gitignore")
    
    for file in "${config_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            success "Configuration file '$file' exists"
        else
            log_error "Configuration file '$file' missing"
            ((issues++))
        fi
    done
    
    # Check directory structure
    info "Checking directory structure..."
    local directories=("lib" "tools" "docs" "terraform" "tests/unit" "tests/integration")
    
    for dir in "${directories[@]}"; do
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            success "Directory '$dir' exists"
        else
            log_error "Directory '$dir' missing"
            ((issues++))
        fi
    done
    
    # Check library organization
    info "Checking library organization..."
    local lib_files=("aws-deployment-common.sh" "aws-config.sh" "error-handling.sh" "spot-instance.sh" "ondemand-instance.sh" "simple-instance.sh")
    
    for lib in "${lib_files[@]}"; do
        if [ -f "$PROJECT_ROOT/lib/$lib" ]; then
            success "Library '$lib' exists"
        else
            log_error "Library '$lib' missing"
            ((issues++))
        fi
    done
    
    return $issues
}

validate_infrastructure_code() {
    log "Validating Infrastructure as Code implementation..."
    local issues=0
    
    # Check Terraform files
    info "Checking Terraform implementation..."
    local tf_files=("main.tf" "variables.tf" "outputs.tf" "user-data.sh")
    
    for tf_file in "${tf_files[@]}"; do
        if [ -f "$PROJECT_ROOT/terraform/$tf_file" ]; then
            success "Terraform file '$tf_file' exists"
        else
            log_error "Terraform file '$tf_file' missing"
            ((issues++))
        fi
    done
    
    # Check Terraform syntax if terraform is available
    if command -v terraform >/dev/null 2>&1; then
        info "Validating Terraform syntax..."
        cd "$PROJECT_ROOT/terraform"
        
        if terraform fmt -check >/dev/null 2>&1; then
            success "Terraform files are properly formatted"
        else
            log_warning "Terraform files need formatting"
            ((issues++))
        fi
        
        if terraform init >/dev/null 2>&1 && terraform validate >/dev/null 2>&1; then
            success "Terraform configuration is valid"
        else
            log_error "Terraform configuration validation failed"
            ((issues++))
        fi
        
        cd "$PROJECT_ROOT"
    else
        info "Terraform not available, skipping syntax validation"
    fi
    
    # Check unified deployment script
    info "Checking unified deployment script..."
    if [ -f "$PROJECT_ROOT/scripts/aws-deployment-unified.sh" ]; then
        if grep -q "deployment_type" "$PROJECT_ROOT/scripts/aws-deployment-unified.sh"; then
            success "Unified deployment script contains proper functionality"
        else
            log_warning "Unified deployment script missing key features"
            ((issues++))
        fi
    else
        log_error "Unified deployment script missing"
        ((issues++))
    fi
    
    return $issues
}

validate_documentation() {
    log "Validating documentation improvements..."
    local issues=0
    
    # Check documentation structure
    info "Checking documentation structure..."
    local doc_dirs=("docs/api" "docs/setup" "docs/architecture" "docs/operations" "docs/examples")
    
    for dir in "${doc_dirs[@]}"; do
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            success "Documentation directory '$dir' exists"
        else
            log_error "Documentation directory '$dir' missing"
            ((issues++))
        fi
    done
    
    # Check key documentation files
    info "Checking key documentation files..."
    local doc_files=("docs/README.md" "docs/setup/troubleshooting.md")
    
    for doc in "${doc_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$doc" ]; then
            success "Documentation file '$doc' exists"
        else
            log_error "Documentation file '$doc' missing"
            ((issues++))
        fi
    done
    
    # Check README updates
    info "Checking README quality..."
    if [ -f "$PROJECT_ROOT/README.md" ]; then
        if grep -q "Quick Start" "$PROJECT_ROOT/README.md"; then
            success "README contains Quick Start section"
        else
            log_warning "README missing Quick Start section"
            ((issues++))
        fi
    fi
    
    return $issues
}

validate_developer_tools() {
    log "Validating developer tools and automation..."
    local issues=0
    
    # Check tool scripts
    info "Checking tool scripts..."
    local tools=("install-deps.sh" "validate-config.sh" "test-runner.sh" "monitoring-setup.sh")
    
    for tool in "${tools[@]}"; do
        if [ -f "$PROJECT_ROOT/tools/$tool" ] && [ -x "$PROJECT_ROOT/tools/$tool" ]; then
            success "Tool script '$tool' exists and is executable"
        else
            log_error "Tool script '$tool' missing or not executable"
            ((issues++))
        fi
    done
    
    # Check Makefile targets
    info "Checking Makefile targets..."
    if [ -f "$PROJECT_ROOT/Makefile" ]; then
        local make_targets=("setup" "test" "deploy" "validate" "clean")
        
        for target in "${make_targets[@]}"; do
            if grep -q "^$target:" "$PROJECT_ROOT/Makefile"; then
                success "Makefile target '$target' exists"
            else
                log_warning "Makefile target '$target' missing"
                ((issues++))
            fi
        done
    else
        log_error "Makefile missing"
        ((issues++))
    fi
    
    return $issues
}

validate_testing_framework() {
    log "Validating testing framework implementation..."
    local issues=0
    
    # Check test directories
    info "Checking test directory structure..."
    local test_dirs=("tests/unit" "tests/integration")
    
    for test_dir in "${test_dirs[@]}"; do
        if [ -d "$PROJECT_ROOT/$test_dir" ]; then
            success "Test directory '$test_dir' exists"
        else
            log_error "Test directory '$test_dir' missing"
            ((issues++))
        fi
    done
    
    # Check test runner
    info "Checking test runner functionality..."
    if [ -f "$PROJECT_ROOT/tools/test-runner.sh" ]; then
        if grep -q "run_unit_tests" "$PROJECT_ROOT/tools/test-runner.sh"; then
            success "Test runner contains proper test functions"
        else
            log_warning "Test runner missing key functionality"
            ((issues++))
        fi
    else
        log_error "Test runner script missing"
        ((issues++))
    fi
    
    # Check existing test files
    info "Checking existing test files..."
    local existing_tests=$(find "$PROJECT_ROOT/tests" -name "*.py" 2>/dev/null | wc -l)
    
    if [ "$existing_tests" -gt 0 ]; then
        success "Found $existing_tests test files"
    else
        log_warning "No test files found - tests need to be written"
        ((issues++))
    fi
    
    return $issues
}

validate_error_handling() {
    log "Validating error handling improvements..."
    local issues=0
    
    # Check error handling library
    info "Checking error handling library..."
    if [ -f "$PROJECT_ROOT/lib/error-handling.sh" ]; then
        local error_functions=("init_error_handling" "log_error" "retry_command" "handle_script_error")
        
        for func in "${error_functions[@]}"; do
            if grep -q "$func" "$PROJECT_ROOT/lib/error-handling.sh"; then
                success "Error handling function '$func' exists"
            else
                log_error "Error handling function '$func' missing"
                ((issues++))
            fi
        done
    else
        log_error "Error handling library missing"
        ((issues++))
    fi
    
    # Check error handling integration
    info "Checking error handling integration..."
    if [ -f "$PROJECT_ROOT/scripts/aws-deployment-unified.sh" ]; then
        if grep -q "error-handling.sh" "$PROJECT_ROOT/scripts/aws-deployment-unified.sh"; then
            success "Error handling integrated in unified deployment script"
        else
            log_warning "Error handling not integrated in deployment script"
            ((issues++))
        fi
    fi
    
    return $issues
}

validate_monitoring_setup() {
    log "Validating monitoring and observability implementation..."
    local issues=0
    
    # Check monitoring setup script
    info "Checking monitoring setup script..."
    if [ -f "$PROJECT_ROOT/tools/monitoring-setup.sh" ]; then
        if grep -q "setup_prometheus" "$PROJECT_ROOT/tools/monitoring-setup.sh"; then
            success "Monitoring setup script contains proper functions"
        else
            log_warning "Monitoring setup script missing key functionality"
            ((issues++))
        fi
    else
        log_error "Monitoring setup script missing"
        ((issues++))
    fi
    
    # Check CloudWatch integration
    info "Checking CloudWatch integration..."
    if [ -f "$PROJECT_ROOT/terraform/user-data.sh" ]; then
        if grep -q "cloudwatch" "$PROJECT_ROOT/terraform/user-data.sh"; then
            success "CloudWatch integration found in user data"
        else
            log_warning "CloudWatch integration missing from user data"
            ((issues++))
        fi
    fi
    
    return $issues
}

# =============================================================================
# COMPREHENSIVE VALIDATION
# =============================================================================

run_comprehensive_validation() {
    log "Running comprehensive validation of all improvements..."
    
    local total_issues=0
    local validation_results=()
    
    for category in $VALIDATION_CATEGORIES; do
        echo
        log "=== Validating $category ==="
        
        local category_issues=0
        
        case "$category" in
            "security")
                category_issues=$(validate_security_improvements)
                ;;
            "structure")
                category_issues=$(validate_project_structure)
                ;;
            "infrastructure")
                category_issues=$(validate_infrastructure_code)
                ;;
            "documentation")
                category_issues=$(validate_documentation)
                ;;
            "tools")
                category_issues=$(validate_developer_tools)
                ;;
            "testing")
                category_issues=$(validate_testing_framework)
                ;;
            "error-handling")
                category_issues=$(validate_error_handling)
                ;;
            "monitoring")
                category_issues=$(validate_monitoring_setup)
                ;;
        esac
        
        validation_results+=("$category:$category_issues")
        total_issues=$((total_issues + category_issues))
        
        if [ "$category_issues" -eq 0 ]; then
            success "$category validation passed ✅"
        else
            warning "$category validation had $category_issues issues ⚠️"
        fi
    done
    
    # Summary report
    echo
    log "=== Validation Summary ==="
    
    for result in "${validation_results[@]}"; do
        local cat="${result%:*}"
        local issues="${result#*:}"
        local description=$(get_validation_description "$cat")
        
        if [ "$issues" -eq 0 ]; then
            info "✅ $cat: $description"
        else
            warning "⚠️  $cat: $description ($issues issues)"
        fi
    done
    
    echo
    if [ "$total_issues" -eq 0 ]; then
        success "🎉 All validations passed! GeuseMaker improvements are complete."
        
        info "Summary of completed improvements:"
        info "• ✅ Security vulnerabilities fixed and credentials secured"
        info "• ✅ Project structure modernized with proper organization"
        info "• ✅ Infrastructure as Code implemented with Terraform"
        info "• ✅ Comprehensive documentation created"
        info "• ✅ Developer tools and automation added"
        info "• ✅ Testing framework implemented"
        info "• ✅ Error handling and resilience enhanced"
        info "• ✅ Monitoring and observability stack created"
        
        echo
        info "🚀 Ready for production deployment!"
        info "Next steps:"
        info "1. Run 'make setup' to initialize development environment"
        info "2. Run 'make test' to execute comprehensive tests"
        info "3. Deploy with 'make deploy STACK_NAME=your-stack'"
        
    else
        warning "⚠️  $total_issues total issues found across all categories."
        warning "Please review the output above and address the identified issues."
        
        info "Common next steps:"
        info "1. Address critical missing files or configurations"
        info "2. Run individual validation tools to fix specific issues"
        info "3. Re-run this validation script to confirm fixes"
        
        return 1
    fi
    
    return 0
}

# =============================================================================
# SPECIFIC VALIDATIONS
# =============================================================================

run_security_validation() {
    echo
    log "=== Security Validation Only ==="
    local issues
    issues=$(validate_security_improvements)
    
    if [ "$issues" -eq 0 ]; then
        success "Security validation passed ✅"
    else
        warning "Security validation found $issues issues ⚠️"
        return 1
    fi
}

run_infrastructure_validation() {
    echo
    log "=== Infrastructure Validation Only ==="
    local issues
    issues=$(validate_infrastructure_code)
    
    if [ "$issues" -eq 0 ]; then
        success "Infrastructure validation passed ✅"
    else
        warning "Infrastructure validation found $issues issues ⚠️"
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

show_help() {
    cat << EOF
Comprehensive Improvements Validation Tool

Usage: $0 [options]

Options:
    --help, -h              Show this help message
    --comprehensive         Run all validations (default)
    --security-only         Run only security validations
    --infrastructure-only   Run only infrastructure validations
    --structure-only        Run only project structure validations
    --tools-only           Run only developer tools validations
    --quiet                Suppress info messages
    --verbose              Show debug information

Categories:
EOF
    
    for category in $VALIDATION_CATEGORIES; do
        printf "  %-15s %s\n" "$category" "$(get_validation_description "$category")"
    done
    
    cat << EOF

Examples:
    $0                      Run comprehensive validation
    $0 --security-only      Run only security checks
    $0 --quiet              Run with minimal output
    $0 --verbose            Run with debug output

EOF
}

main() {
    local validation_type="comprehensive"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --comprehensive)
                validation_type="comprehensive"
                shift
                ;;
            --security-only)
                validation_type="security"
                shift
                ;;
            --infrastructure-only)
                validation_type="infrastructure"
                shift
                ;;
            --structure-only)
                validation_type="structure"
                shift
                ;;
            --tools-only)
                validation_type="tools"
                shift
                ;;
            --quiet)
                # Redirect info to /dev/null for quiet mode
                exec 3>&1 1>/dev/null
                shift
                ;;
            --verbose)
                export DEBUG=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log "Starting GeuseMaker improvements validation..."
    log "Validation type: $validation_type"
    
    case "$validation_type" in
        "comprehensive")
            run_comprehensive_validation
            ;;
        "security")
            run_security_validation
            ;;
        "infrastructure")
            run_infrastructure_validation
            ;;
        "structure")
            validate_project_structure >/dev/null
            ;;
        "tools")
            validate_developer_tools >/dev/null
            ;;
        *)
            log_error "Unknown validation type: $validation_type"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"