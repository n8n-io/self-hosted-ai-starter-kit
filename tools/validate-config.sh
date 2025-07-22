#!/bin/bash
# =============================================================================
# Configuration Validation Tool
# Validates all configuration files and settings
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
# VALIDATION FUNCTIONS
# =============================================================================

validate_docker_compose_files() {
    log "Validating Docker Compose files..."
    
    local compose_files=(
        "$PROJECT_ROOT/docker-compose.gpu-optimized.yml"
        "$PROJECT_ROOT/docker-compose.yml"
    )
    
    for file in "${compose_files[@]}"; do
        if [ -f "$file" ]; then
            info "Validating $(basename "$file")..."
            
            # Check YAML syntax
            if command -v yq >/dev/null 2>&1; then
                if ! yq eval '.' "$file" >/dev/null 2>&1; then
                    log_error "Invalid YAML syntax in $file"
                    return 1
                fi
            fi
            
            # Validate with docker-compose
            if command -v docker-compose >/dev/null 2>&1; then
                if ! docker-compose -f "$file" config >/dev/null 2>&1; then
                    log_error "Invalid Docker Compose configuration in $file"
                    return 1
                fi
            fi
            
            # Check for common issues
            if grep -q "latest" "$file"; then
                log_warning "Found 'latest' tag in $file - consider pinning versions"
            fi
            
            # Check resource limits
            if ! grep -q "cpus:" "$file"; then
                log_warning "No CPU limits found in $file"
            fi
            
            if ! grep -q "memory:" "$file"; then
                log_warning "No memory limits found in $file"
            fi
            
            success "$(basename "$file") validation passed"
        else
            log_warning "Docker Compose file not found: $file"
        fi
    done
}

validate_terraform_files() {
    log "Validating Terraform files..."
    
    local terraform_dir="$PROJECT_ROOT/terraform"
    
    if [ ! -d "$terraform_dir" ]; then
        log_warning "Terraform directory not found: $terraform_dir"
        return 0
    fi
    
    cd "$terraform_dir"
    
    # Check if terraform is available
    if ! command -v terraform >/dev/null 2>&1; then
        log_warning "Terraform not installed - skipping validation"
        return 0
    fi
    
    # Initialize terraform
    if [ ! -d ".terraform" ]; then
        info "Initializing Terraform..."
        if ! terraform init >/dev/null 2>&1; then
            log_error "Terraform initialization failed"
            return 1
        fi
    fi
    
    # Validate syntax
    info "Validating Terraform syntax..."
    if ! terraform validate; then
        log_error "Terraform validation failed"
        return 1
    fi
    
    # Format check
    if ! terraform fmt -check; then
        log_warning "Terraform files need formatting. Run: terraform fmt"
    fi
    
    success "Terraform validation passed"
    cd "$PROJECT_ROOT"
}

validate_shell_scripts() {
    log "Validating shell scripts..."
    
    local script_dirs=("$PROJECT_ROOT/scripts" "$PROJECT_ROOT/tools" "$PROJECT_ROOT/lib")
    
    for dir in "${script_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            continue
        fi
        
        find "$dir" -name "*.sh" -type f | while read -r script; do
            info "Validating $(basename "$script")..."
            
            # Check shebang
            if ! head -n1 "$script" | grep -q "#!/bin/bash"; then
                log_warning "Missing or incorrect shebang in $script"
            fi
            
            # Check syntax
            if ! bash -n "$script"; then
                log_error "Syntax error in $script"
                return 1
            fi
            
            # ShellCheck if available
            if command -v shellcheck >/dev/null 2>&1; then
                if ! shellcheck "$script"; then
                    log_warning "ShellCheck issues found in $script"
                fi
            fi
            
            # Check for common security issues
            if grep -q "eval" "$script"; then
                log_warning "Found 'eval' in $script - potential security risk"
            fi
            
            if grep -q "curl.*|.*sh" "$script"; then
                log_warning "Found 'curl | sh' pattern in $script - security risk"
            fi
        done
    done
    
    success "Shell script validation completed"
}

validate_python_files() {
    log "Validating Python files..."
    
    find "$PROJECT_ROOT" -name "*.py" -type f | while read -r py_file; do
        info "Validating $(basename "$py_file")..."
        
        # Check syntax
        if ! python3 -m py_compile "$py_file"; then
            log_error "Python syntax error in $py_file"
            return 1
        fi
        
        # Flake8 if available
        if command -v flake8 >/dev/null 2>&1; then
            if ! flake8 "$py_file" --max-line-length=88; then
                log_warning "Code style issues found in $py_file"
            fi
        fi
    done
    
    success "Python file validation completed"
}

validate_environment_files() {
    log "Validating environment configuration..."
    
    local env_dirs=(
        "$PROJECT_ROOT/config/environments"
        "$PROJECT_ROOT/config/logging"
    )
    
    for dir in "${env_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_warning "Environment directory not found: $dir"
            continue
        fi
        
        find "$dir" -name "*.yml" -o -name "*.yaml" | while read -r config_file; do
            info "Validating $(basename "$config_file")..."
            
            # Check YAML syntax
            if command -v yq >/dev/null 2>&1; then
                if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
                    log_error "Invalid YAML syntax in $config_file"
                    return 1
                fi
            fi
        done
    done
    
    success "Environment configuration validation completed"
}

validate_security_configuration() {
    log "Validating security configuration..."
    
    # Check .gitignore
    if [ -f "$PROJECT_ROOT/.gitignore" ]; then
        local security_patterns=(
            "*.pem"
            "*.key"
            ".env"
            "*password*"
            "*secret*"
            "*token*"
        )
        
        for pattern in "${security_patterns[@]}"; do
            if ! grep -q "$pattern" "$PROJECT_ROOT/.gitignore"; then
                log_warning ".gitignore missing security pattern: $pattern"
            fi
        done
    else
        log_error ".gitignore file missing"
        return 1
    fi
    
    # Check for sensitive files
    local sensitive_patterns=("*.pem" "*.key" ".env.production" "*secret*" "*password*")
    
    for pattern in "${sensitive_patterns[@]}"; do
        if find "$PROJECT_ROOT" -name "$pattern" -type f | grep -q .; then
            log_warning "Found potentially sensitive files matching: $pattern"
        fi
    done
    
    success "Security configuration validation completed"
}

validate_aws_configuration() {
    log "Validating AWS configuration..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_warning "AWS CLI not installed"
        return 0
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_warning "AWS credentials not configured or invalid"
        return 0
    fi
    
    # Check default region
    local aws_region
    aws_region=$(aws configure get region)
    
    if [ -z "$aws_region" ]; then
        log_warning "AWS default region not configured"
    else
        info "AWS region configured: $aws_region"
    fi
    
    success "AWS configuration validation completed"
}

validate_docker_configuration() {
    log "Validating Docker configuration..."
    
    # Check Docker installation
    if ! command -v docker >/dev/null 2>&1; then
        log_warning "Docker not installed"
        return 0
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_warning "Docker daemon not running"
        return 0
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_warning "Docker Compose not installed"
        return 0
    fi
    
    # Check for Dockerfiles
    find "$PROJECT_ROOT" -name "Dockerfile*" -type f | while read -r dockerfile; do
        info "Validating $(basename "$dockerfile")..."
        
        # Check for best practices
        if ! grep -q "USER" "$dockerfile"; then
            log_warning "Dockerfile $dockerfile doesn't specify USER (potential security risk)"
        fi
        
        if grep -q "latest" "$dockerfile"; then
            log_warning "Dockerfile $dockerfile uses 'latest' tag - consider pinning versions"
        fi
    done
    
    success "Docker configuration validation completed"
}

# =============================================================================
# MAIN VALIDATION PROCESS
# =============================================================================

main() {
    local exit_code=0
    local validation_functions=(
        "validate_docker_compose_files"
        "validate_terraform_files"
        "validate_shell_scripts"
        "validate_python_files"
        "validate_environment_files"
        "validate_security_configuration"
        "validate_aws_configuration"
        "validate_docker_configuration"
    )
    
    log "Starting comprehensive configuration validation..."
    
    for validation_func in "${validation_functions[@]}"; do
        if ! $validation_func; then
            exit_code=1
        fi
        echo
    done
    
    if [ $exit_code -eq 0 ]; then
        success "🎉 All validations passed successfully!"
        
        # Summary
        info "Validation Summary:"
        info "✅ Docker Compose files validated"
        info "✅ Terraform configuration validated"
        info "✅ Shell scripts validated"
        info "✅ Python files validated"
        info "✅ Environment configuration validated"
        info "✅ Security configuration validated"
        info "✅ AWS configuration validated"
        info "✅ Docker configuration validated"
        
    else
        warning "⚠️  Some validations failed or had warnings"
        warning "Please review the output above and fix any issues"
    fi
    
    return $exit_code
}

# Show help
show_help() {
    cat << EOF
Configuration Validation Tool

Usage: $0 [options]

Options:
    --help, -h          Show this help message
    --quiet, -q         Suppress info messages
    --strict            Exit on warnings (not just errors)

Examples:
    $0                  Run all validations
    $0 --quiet          Run validations with minimal output
    $0 --strict         Fail on warnings

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --quiet|-q)
            # Redirect info messages to /dev/null if quiet mode
            exec 3>&1 1>/dev/null
            shift
            ;;
        --strict)
            # In strict mode, warnings become errors
            export STRICT_MODE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main validation
main