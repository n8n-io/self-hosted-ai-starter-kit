#!/bin/bash
# =============================================================================
# Docker Environment Validation Script
# Ensures Docker Compose environment variables are properly configured
# =============================================================================
# This script validates that all required environment variables are properly
# set and available to Docker Compose, with comprehensive diagnostics and
# automatic fixes for common issues.
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Docker Compose files to validate
readonly COMPOSE_FILES="docker-compose.gpu-optimized.yml docker-compose.yml docker-compose.test.yml"

# Environment files
readonly ENV_FILES=".env config/environment.env"

# Required environment variables
readonly CRITICAL_VARS="POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET"
readonly OPTIONAL_VARS="OPENAI_API_KEY WEBHOOK_URL N8N_CORS_ENABLE N8N_CORS_ALLOWED_ORIGINS"
readonly DB_VARS="POSTGRES_DB POSTGRES_USER"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] SUCCESS: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Check if Docker and Docker Compose are available
check_docker_availability() {
    log "Checking Docker availability..."
    
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed or not in PATH"
        return 1
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        error "Docker Compose is not installed or not in PATH"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running"
        return 1
    fi
    
    success "Docker and Docker Compose are available"
    return 0
}

# Validate environment variable values
validate_variable_content() {
    local var_name="$1"
    local var_value="$2"
    local var_type="${3:-optional}"
    
    case "$var_type" in
        "critical")
            if [ -z "$var_value" ]; then
                error "Critical variable $var_name is empty"
                return 1
            elif [ ${#var_value} -lt 8 ]; then
                error "Critical variable $var_name is too short (${#var_value} chars, minimum 8)"
                return 1
            else
                case "$var_value" in
                    password|test|admin|default|example)
                        error "Critical variable $var_name uses an insecure default value: $var_value"
                        return 1
                        ;;
                esac
            fi
            ;;
        "api_key")
            if [ -n "$var_value" ]; then
                case "$var_name" in
                    "OPENAI_API_KEY")
                        case "$var_value" in
                            sk-*)
                                # Valid OpenAI API key format
                                ;;
                            *)
                                warning "$var_name does not match expected OpenAI API key format"
                                ;;
                        esac
                        ;;
                esac
            fi
            ;;
        "url")
            if [ -n "$var_value" ]; then
                case "$var_value" in
                    http://*|https://*)
                        # Valid URL format
                        ;;
                    *)
                        warning "$var_name does not appear to be a valid URL: $var_value"
                        ;;
                esac
            fi
            ;;
    esac
    
    return 0
}

# Check environment variables in current shell
validate_current_environment() {
    log "Validating current environment variables..."
    
    local validation_errors=0
    
    # Check critical variables
    log "Checking critical variables..."
    for var in $CRITICAL_VARS; do
        local value
        eval "value=\$$var"
        
        if validate_variable_content "$var" "$value" "critical"; then
            success "✓ $var is properly set (${#value} chars)"
        else
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    # Check database variables
    log "Checking database variables..."
    for var in $DB_VARS; do
        local value
        eval "value=\$$var"
        
        if [ -z "$value" ]; then
            warning "Database variable $var is not set"
            validation_errors=$((validation_errors + 1))
        else
            success "✓ $var: $value"
        fi
    done
    
    # Check optional variables
    log "Checking optional variables..."
    for var in $OPTIONAL_VARS; do
        local value
        eval "value=\$$var"
        
        if [ -n "$value" ]; then
            case "$var" in
                *API_KEY*)
                    if validate_variable_content "$var" "$value" "api_key"; then
                        success "✓ $var is set (${#value} chars)"
                    fi
                    ;;
                *URL*)
                    if validate_variable_content "$var" "$value" "url"; then
                        success "✓ $var: $value"
                    fi
                    ;;
                *)
                    success "✓ $var: $value"
                    ;;
            esac
        else
            log "- $var: not set (optional)"
        fi
    done
    
    if [ $validation_errors -eq 0 ]; then
        success "All environment variable validation passed"
        return 0
    else
        error "Environment variable validation failed ($validation_errors errors)"
        return 1
    fi
}

# Validate environment files exist and are readable
validate_environment_files() {
    log "Validating environment files..."
    
    local files_found=0
    local files_valid=0
    
    for env_file in $ENV_FILES; do
        local full_path="$PROJECT_ROOT/$env_file"
        
        if [ -f "$full_path" ]; then
            files_found=$((files_found + 1))
            
            log "Found environment file: $env_file"
            
            # Check file permissions
            if [ ! -r "$full_path" ]; then
                error "Environment file is not readable: $env_file"
                continue
            fi
            
            # Check file is not empty
            if [ ! -s "$full_path" ]; then
                warning "Environment file is empty: $env_file"
                continue
            fi
            
            # Validate file format
            if ! grep -q "=" "$full_path"; then
                warning "Environment file does not contain any variable assignments: $env_file"
                continue
            fi
            
            # Check for critical variables in file
            local critical_vars_in_file=0
            for var in $CRITICAL_VARS; do
                if grep -q "^$var=" "$full_path" || grep -q "^export $var=" "$full_path"; then
                    critical_vars_in_file=$((critical_vars_in_file + 1))
                fi
            done
            
            if [ $critical_vars_in_file -eq 0 ]; then
                warning "Environment file contains no critical variables: $env_file"
            else
                success "✓ $env_file contains $critical_vars_in_file critical variables"
                files_valid=$((files_valid + 1))
            fi
        else
            log "Environment file not found: $env_file (optional)"
        fi
    done
    
    if [ $files_found -eq 0 ]; then
        warning "No environment files found"
        return 1
    elif [ $files_valid -eq 0 ]; then
        error "No valid environment files found"
        return 1
    else
        success "Found $files_valid valid environment files out of $files_found total"
        return 0
    fi
}

# Validate Docker Compose files can access environment variables
validate_docker_compose_integration() {
    log "Validating Docker Compose integration..."
    
    local compose_files_validated=0
    
    for compose_file in $COMPOSE_FILES; do
        local full_path="$PROJECT_ROOT/$compose_file"
        
        if [ ! -f "$full_path" ]; then
            log "Compose file not found: $compose_file (skipping)"
            continue
        fi
        
        log "Validating Docker Compose file: $compose_file"
        
        # Change to project directory for Docker Compose context
        cd "$PROJECT_ROOT"
        
        # Test configuration parsing
        if ! docker-compose -f "$compose_file" config >/dev/null 2>&1; then
            error "Docker Compose configuration is invalid: $compose_file"
            continue
        fi
        
        # Check if environment variables are properly referenced
        local env_vars_referenced=0
        for var in $CRITICAL_VARS $DB_VARS; do
            if grep -q "\${$var}" "$full_path" || grep -q "$var=" "$full_path"; then
                env_vars_referenced=$((env_vars_referenced + 1))
            fi
        done
        
        if [ $env_vars_referenced -eq 0 ]; then
            warning "Compose file does not reference any environment variables: $compose_file"
        else
            success "✓ $compose_file references $env_vars_referenced environment variables"
        fi
        
        # Test variable substitution
        local config_output
        if config_output=$(docker-compose -f "$compose_file" config 2>/dev/null); then
            # Check if variables were properly substituted (no ${VAR} patterns remain for critical vars)
            local unsubstituted_vars=0
            for var in $CRITICAL_VARS; do
                if echo "$config_output" | grep -q "\${$var}"; then
                    warning "Variable $var was not substituted in $compose_file"
                    unsubstituted_vars=$((unsubstituted_vars + 1))
                fi
            done
            
            if [ $unsubstituted_vars -eq 0 ]; then
                success "✓ All critical variables properly substituted in $compose_file"
            else
                warning "$unsubstituted_vars variables not properly substituted in $compose_file"
            fi
        fi
        
        compose_files_validated=$((compose_files_validated + 1))
    done
    
    if [ $compose_files_validated -eq 0 ]; then
        error "No Docker Compose files could be validated"
        return 1
    else
        success "Validated $compose_files_validated Docker Compose files"
        return 0
    fi
}

# Test actual Docker Compose startup (dry run)
test_docker_compose_startup() {
    local compose_file="${1:-docker-compose.gpu-optimized.yml}"
    local full_path="$PROJECT_ROOT/$compose_file"
    
    if [ ! -f "$full_path" ]; then
        error "Compose file not found for testing: $compose_file"
        return 1
    fi
    
    log "Testing Docker Compose startup (dry run): $compose_file"
    
    cd "$PROJECT_ROOT"
    
    # Test configuration is valid
    if ! docker-compose -f "$compose_file" config >/dev/null 2>&1; then
        error "Docker Compose configuration test failed"
        return 1
    fi
    
    # Test image pulling (without actually pulling)
    log "Testing image availability..."
    if docker-compose -f "$compose_file" config | grep -E "image:" | while read -r line; do
        local image_name=$(echo "$line" | sed 's/.*image: *//g' | tr -d '"')
        if [ -n "$image_name" ] && [[ ! "$image_name" =~ \$ ]]; then
            log "Checking image: $image_name"
            # Don't actually pull, just check if image exists locally or can be resolved
            if ! docker image inspect "$image_name" >/dev/null 2>&1; then
                log "Image $image_name not available locally (will be pulled on startup)"
            fi
        fi
    done; then
        success "Image availability check completed"
    fi
    
    # Test that we can create containers (without starting them)
    log "Testing container creation..."
    if docker-compose -f "$compose_file" create >/dev/null 2>&1; then
        success "✓ Container creation test passed"
        
        # Clean up test containers
        docker-compose -f "$compose_file" rm -f >/dev/null 2>&1 || true
        
        return 0
    else
        error "Container creation test failed"
        return 1
    fi
}

# =============================================================================
# REPAIR FUNCTIONS
# =============================================================================

# Generate missing environment file
generate_missing_env_file() {
    local env_file="${1:-$PROJECT_ROOT/.env}"
    
    log "Generating missing environment file: $env_file"
    
    # Source variable management library if available
    if [ -f "$PROJECT_ROOT/lib/variable-management.sh" ]; then
        source "$PROJECT_ROOT/lib/variable-management.sh"
        
        if command -v generate_docker_env_file >/dev/null 2>&1; then
            generate_docker_env_file "$env_file"
            success "Environment file generated using variable management library"
            return 0
        fi
    fi
    
    # Fallback: generate basic environment file
    cat > "$env_file" << EOF
# =============================================================================
# GeuseMaker Environment File
# Generated by validation script
# Generated: $(date)
# =============================================================================

# Database Configuration
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "fallback_$(date +%s)")

# n8n Configuration
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32 2>/dev/null || echo "fallback_$(date +%s)")
N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -base64 32 2>/dev/null || echo "fallback_$(date +%s)")
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "fallback_$(date +%s)")
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=*

# API Keys (add your actual keys)
OPENAI_API_KEY=

# Service Configuration
WEBHOOK_URL=http://localhost:5678
ENABLE_METRICS=true
LOG_LEVEL=info

# Infrastructure
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1
STACK_NAME=GeuseMaker
ENVIRONMENT=development
EOF
    
    chmod 600 "$env_file"
    success "Basic environment file generated: $env_file"
}

# Fix environment file permissions
fix_env_file_permissions() {
    log "Fixing environment file permissions..."
    
    for env_file in $ENV_FILES; do
        local full_path="$PROJECT_ROOT/$env_file"
        
        if [ -f "$full_path" ]; then
            chmod 600 "$full_path" 2>/dev/null || true
            log "Fixed permissions for: $env_file"
        fi
    done
    
    success "Environment file permissions fixed"
}

# =============================================================================
# MAIN EXECUTION FUNCTIONS
# =============================================================================

# Run complete validation
run_complete_validation() {
    log "Running complete Docker environment validation..."
    echo ""
    
    local validation_results=()
    local total_checks=0
    local passed_checks=0
    
    # Check Docker availability
    total_checks=$((total_checks + 1))
    if check_docker_availability; then
        validation_results+=("PASSED: Docker availability")
        passed_checks=$((passed_checks + 1))
    else
        validation_results+=("FAILED: Docker availability")
    fi
    
    # Validate current environment
    total_checks=$((total_checks + 1))
    if validate_current_environment; then
        validation_results+=("PASSED: Current environment variables")
        passed_checks=$((passed_checks + 1))
    else
        validation_results+=("FAILED: Current environment variables")
    fi
    
    # Validate environment files
    total_checks=$((total_checks + 1))
    if validate_environment_files; then
        validation_results+=("PASSED: Environment files")
        passed_checks=$((passed_checks + 1))
    else
        validation_results+=("FAILED: Environment files")
    fi
    
    # Validate Docker Compose integration
    total_checks=$((total_checks + 1))
    if validate_docker_compose_integration; then
        validation_results+=("PASSED: Docker Compose integration")
        passed_checks=$((passed_checks + 1))
    else
        validation_results+=("FAILED: Docker Compose integration")
    fi
    
    # Test Docker Compose startup
    total_checks=$((total_checks + 1))
    if test_docker_compose_startup; then
        validation_results+=("PASSED: Docker Compose startup test")
        passed_checks=$((passed_checks + 1))
    else
        validation_results+=("FAILED: Docker Compose startup test")
    fi
    
    # Report results
    echo ""
    echo "=== VALIDATION SUMMARY ==="
    for result in "${validation_results[@]}"; do
        if [[ "$result" == PASSED* ]]; then
            echo -e "  ${GREEN}$result${NC}"
        else
            echo -e "  ${RED}$result${NC}"
        fi
    done
    
    echo ""
    log "Validation completed: $passed_checks/$total_checks checks passed"
    
    if [ $passed_checks -eq $total_checks ]; then
        success "All validation checks passed!"
        return 0
    else
        error "Some validation checks failed"
        return 1
    fi
}

# Run fixes for common issues
run_fixes() {
    log "Running fixes for common Docker environment issues..."
    
    # Fix environment file permissions
    fix_env_file_permissions
    
    # Generate missing .env file if needed
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        generate_missing_env_file "$PROJECT_ROOT/.env"
    fi
    
    # Generate missing config environment file if needed
    if [ ! -f "$PROJECT_ROOT/config/environment.env" ]; then
        mkdir -p "$PROJECT_ROOT/config"
        generate_missing_env_file "$PROJECT_ROOT/config/environment.env"
    fi
    
    success "Fixes completed"
}

# Show usage information
show_usage() {
    echo "Docker Environment Validation Script v$SCRIPT_VERSION"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  validate    Run complete validation (default)"
    echo "  fix         Run automatic fixes for common issues"
    echo "  test        Test Docker Compose startup"
    echo "  check-env   Check current environment variables only"
    echo ""
    echo "Options:"
    echo "  --compose-file FILE    Specify Docker Compose file to test"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 validate"
    echo "  $0 fix"
    echo "  $0 test --compose-file docker-compose.gpu-optimized.yml"
}

# Main execution
main() {
    local command="validate"
    local compose_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            validate|fix|test|check-env)
                command="$1"
                shift
                ;;
            --compose-file)
                compose_file="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "Starting Docker Environment Validation v$SCRIPT_VERSION"
    log "Command: $command"
    log "Project root: $PROJECT_ROOT"
    
    case "$command" in
        "validate")
            run_complete_validation
            ;;
        "fix")
            run_fixes
            echo ""
            log "Running validation after fixes..."
            run_complete_validation
            ;;
        "test")
            if [ -n "$compose_file" ]; then
                test_docker_compose_startup "$compose_file"
            else
                test_docker_compose_startup
            fi
            ;;
        "check-env")
            validate_current_environment
            ;;
    esac
}

# Execute main function with all arguments
main "$@"