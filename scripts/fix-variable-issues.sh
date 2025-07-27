#!/bin/bash
# =============================================================================
# Variable Issues Fix Script
# Diagnoses and fixes environment variable setting issues on EC2 instances
# =============================================================================
# This script is designed to be run on EC2 instances that are experiencing
# variable setting issues. It provides comprehensive diagnosis and automated
# fixes for common variable-related problems.
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

# File paths
readonly VARIABLE_CACHE_FILE="/tmp/geuse-variable-cache"
readonly DOCKER_ENV_FILE="/home/ubuntu/GeuseMaker/.env"
readonly CONFIG_ENV_FILE="/home/ubuntu/GeuseMaker/config/environment.env"
readonly VARIABLE_MANAGEMENT_LIB="/home/ubuntu/GeuseMaker/lib/variable-management.sh"
readonly LOG_FILE="/var/log/variable-fix.log"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}] INFO: ${message}${NC}" | tee -a "$LOG_FILE"
}

error() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ERROR: ${message}${NC}" | tee -a "$LOG_FILE" >&2
}

success() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] SUCCESS: ${message}${NC}" | tee -a "$LOG_FILE"
}

warning() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] WARNING: ${message}${NC}" | tee -a "$LOG_FILE"
}

# =============================================================================
# DIAGNOSTIC FUNCTIONS
# =============================================================================

# Check if essential commands are available
check_system_prerequisites() {
    log "Checking system prerequisites..."
    
    local missing_commands=()
    local required_commands="docker aws openssl"
    
    for cmd in $required_commands; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        warning "Missing commands: ${missing_commands[*]}"
        return 1
    fi
    
    success "All required commands are available"
    return 0
}

# Check AWS credentials and connectivity
check_aws_connectivity() {
    log "Checking AWS connectivity and credentials..."
    
    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI not installed"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        warning "AWS credentials not configured or expired"
        return 1
    fi
    
    # Check Parameter Store access
    local region="${AWS_REGION:-us-east-1}"
    if ! aws ssm describe-parameters --region "$region" >/dev/null 2>&1; then
        warning "Cannot access Parameter Store in region $region"
        return 1
    fi
    
    success "AWS connectivity and credentials are working"
    return 0
}

# Diagnose current variable state
diagnose_variable_state() {
    log "Diagnosing current variable state..."
    
    echo ""
    echo "=== CURRENT ENVIRONMENT VARIABLES ==="
    
    # Check critical variables
    local critical_vars="POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET"
    echo ""
    echo "Critical Variables:"
    for var in $critical_vars; do
        local value
        eval "value=\$$var"
        if [ -n "$value" ]; then
            echo "  ✓ $var: [SET - ${#value} chars]"
        else
            echo "  ✗ $var: [NOT SET]"
        fi
    done
    
    # Check optional variables
    local optional_vars="OPENAI_API_KEY WEBHOOK_URL N8N_CORS_ENABLE"
    echo ""
    echo "Optional Variables:"
    for var in $optional_vars; do
        local value
        eval "value=\$$var"
        if [ -n "$value" ]; then
            case "$var" in
                *API_KEY*|*PASSWORD*|*SECRET*)
                    echo "  ✓ $var: [SET - ${#value} chars]"
                    ;;
                *)
                    echo "  ✓ $var: $value"
                    ;;
            esac
        else
            echo "  - $var: [NOT SET]"
        fi
    done
    
    # Check environment files
    echo ""
    echo "=== ENVIRONMENT FILES ==="
    
    local env_files="$DOCKER_ENV_FILE $CONFIG_ENV_FILE $VARIABLE_CACHE_FILE"
    for file in $env_files; do
        if [ -f "$file" ]; then
            local file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
            echo "  ✓ $file: exists (${file_size} bytes)"
        else
            echo "  ✗ $file: missing"
        fi
    done
    
    echo ""
}

# Check Docker Compose environment integration
check_docker_integration() {
    log "Checking Docker Compose environment integration..."
    
    if [ ! -f "$DOCKER_ENV_FILE" ]; then
        error "Docker environment file missing: $DOCKER_ENV_FILE"
        return 1
    fi
    
    # Validate environment file syntax
    if ! grep -q "POSTGRES_PASSWORD=" "$DOCKER_ENV_FILE"; then
        error "Docker environment file missing POSTGRES_PASSWORD"
        return 1
    fi
    
    if ! grep -q "N8N_ENCRYPTION_KEY=" "$DOCKER_ENV_FILE"; then
        error "Docker environment file missing N8N_ENCRYPTION_KEY"
        return 1
    fi
    
    # Check if Docker can read the environment file
    if command -v docker >/dev/null 2>&1; then
        local compose_file="/home/ubuntu/GeuseMaker/docker-compose.gpu-optimized.yml"
        if [ -f "$compose_file" ]; then
            log "Testing Docker Compose configuration..."
            if docker-compose -f "$compose_file" config >/dev/null 2>&1; then
                success "Docker Compose configuration is valid"
            else
                warning "Docker Compose configuration has issues"
                return 1
            fi
        fi
    fi
    
    success "Docker integration looks good"
    return 0
}

# =============================================================================
# REPAIR FUNCTIONS
# =============================================================================

# Install or update variable management library
install_variable_management() {
    log "Installing/updating variable management library..."
    
    mkdir -p "$(dirname "$VARIABLE_MANAGEMENT_LIB")"
    
    # Copy the library from the project
    if [ -f "$PROJECT_ROOT/lib/variable-management.sh" ]; then
        log "Copying variable management library from project"
        cp "$PROJECT_ROOT/lib/variable-management.sh" "$VARIABLE_MANAGEMENT_LIB"
    else
        log "Creating embedded variable management library"
        # Create a simplified version of the library
        cat > "$VARIABLE_MANAGEMENT_LIB" << 'LIB_EOF'
#!/bin/bash
# Embedded Variable Management Library for Emergency Recovery

var_log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $level: $*"
}

generate_secure_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 2>/dev/null | tr -d '\n'
    else
        echo "secure_$(date +%s)_$(echo $$ | tail -c 6)"
    fi
}

generate_encryption_key() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32 2>/dev/null
    else
        echo "$(date +%s | sha256sum | cut -c1-64)"
    fi
}

check_aws_availability() {
    command -v aws >/dev/null 2>&1 && aws sts get-caller-identity >/dev/null 2>&1
}

get_parameter_store_value() {
    local param_name="$1"
    local default_value="$2"
    local region="${AWS_REGION:-us-east-1}"
    
    if check_aws_availability; then
        local value
        value=$(aws ssm get-parameter --name "$param_name" --with-decryption --region "$region" --query 'Parameter.Value' --output text 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$value" ] && [ "$value" != "None" ]; then
            echo "$value"
            return 0
        fi
    fi
    echo "$default_value"
    return 1
}

init_all_variables() {
    var_log INFO "Emergency variable initialization"
    
    # Critical variables with secure defaults
    export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(get_parameter_store_value '/aibuildkit/POSTGRES_PASSWORD' "$(generate_secure_password)")}"
    export N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(get_parameter_store_value '/aibuildkit/n8n/ENCRYPTION_KEY' "$(generate_encryption_key)")}"
    export N8N_USER_MANAGEMENT_JWT_SECRET="${N8N_USER_MANAGEMENT_JWT_SECRET:-$(get_parameter_store_value '/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET' "$(generate_secure_password)")}"
    
    # Optional variables
    export OPENAI_API_KEY="${OPENAI_API_KEY:-$(get_parameter_store_value '/aibuildkit/OPENAI_API_KEY' '')}"
    export WEBHOOK_URL="${WEBHOOK_URL:-$(get_parameter_store_value '/aibuildkit/WEBHOOK_URL' 'http://localhost:5678')}"
    export N8N_CORS_ENABLE="${N8N_CORS_ENABLE:-$(get_parameter_store_value '/aibuildkit/n8n/CORS_ENABLE' 'true')}"
    export N8N_CORS_ALLOWED_ORIGINS="${N8N_CORS_ALLOWED_ORIGINS:-$(get_parameter_store_value '/aibuildkit/n8n/CORS_ALLOWED_ORIGINS' '*')}"
    
    # Additional service variables
    export N8N_BASIC_AUTH_ACTIVE="${N8N_BASIC_AUTH_ACTIVE:-true}"
    export N8N_BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER:-admin}"
    export N8N_BASIC_AUTH_PASSWORD="${N8N_BASIC_AUTH_PASSWORD:-$(generate_secure_password)}"
    export POSTGRES_DB="${POSTGRES_DB:-n8n}"
    export POSTGRES_USER="${POSTGRES_USER:-n8n}"
    export ENABLE_METRICS="${ENABLE_METRICS:-true}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"
    
    # Infrastructure variables
    export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
    
    var_log SUCCESS "Emergency variable initialization completed"
}

generate_docker_env_file() {
    local output_file="${1:-/home/ubuntu/GeuseMaker/.env}"
    
    var_log INFO "Generating Docker environment file: $output_file"
    
    mkdir -p "$(dirname "$output_file")"
    
    cat > "$output_file" << EOF
# =============================================================================
# GeuseMaker Docker Environment File
# Generated by Emergency Recovery Script
# Generated: $(date)
# =============================================================================

# Database Configuration
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# n8n Configuration
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET
N8N_BASIC_AUTH_ACTIVE=$N8N_BASIC_AUTH_ACTIVE
N8N_BASIC_AUTH_USER=$N8N_BASIC_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_BASIC_AUTH_PASSWORD
N8N_CORS_ENABLE=$N8N_CORS_ENABLE
N8N_CORS_ALLOWED_ORIGINS=$N8N_CORS_ALLOWED_ORIGINS

# API Keys
OPENAI_API_KEY=$OPENAI_API_KEY

# Service Configuration
WEBHOOK_URL=$WEBHOOK_URL
ENABLE_METRICS=$ENABLE_METRICS
LOG_LEVEL=$LOG_LEVEL

# Infrastructure
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_DEFAULT_REGION=${AWS_REGION:-us-east-1}
STACK_NAME=${STACK_NAME:-GeuseMaker}
ENVIRONMENT=${ENVIRONMENT:-development}
EOF
    
    chmod 600 "$output_file"
    
    # Set ownership if running as root
    if [ "$(id -u)" -eq 0 ] && id ubuntu >/dev/null 2>&1; then
        chown ubuntu:ubuntu "$output_file"
    fi
    
    var_log SUCCESS "Docker environment file generated: $output_file"
}
LIB_EOF
    fi
    
    chmod +x "$VARIABLE_MANAGEMENT_LIB"
    success "Variable management library installed"
}

# Regenerate all environment variables and files
regenerate_variables() {
    log "Regenerating environment variables and files..."
    
    # Source the variable management library
    if [ -f "$VARIABLE_MANAGEMENT_LIB" ]; then
        source "$VARIABLE_MANAGEMENT_LIB"
    else
        error "Variable management library not found"
        return 1
    fi
    
    # Initialize variables
    if ! init_all_variables; then
        error "Failed to initialize variables"
        return 1
    fi
    
    # Generate Docker environment file
    if ! generate_docker_env_file "$DOCKER_ENV_FILE"; then
        error "Failed to generate Docker environment file"
        return 1
    fi
    
    # Generate config environment file
    mkdir -p "$(dirname "$CONFIG_ENV_FILE")"
    if ! generate_docker_env_file "$CONFIG_ENV_FILE"; then
        error "Failed to generate config environment file"
        return 1
    fi
    
    success "Variables and environment files regenerated"
}

# Fix file permissions
fix_permissions() {
    log "Fixing file permissions..."
    
    local files_to_fix="$DOCKER_ENV_FILE $CONFIG_ENV_FILE $VARIABLE_CACHE_FILE $VARIABLE_MANAGEMENT_LIB"
    
    for file in $files_to_fix; do
        if [ -f "$file" ]; then
            chmod 600 "$file" 2>/dev/null || true
            
            # Set ownership if running as root
            if [ "$(id -u)" -eq 0 ] && id ubuntu >/dev/null 2>&1; then
                chown ubuntu:ubuntu "$file" 2>/dev/null || true
            fi
        fi
    done
    
    success "File permissions fixed"
}

# Restart relevant services
restart_services() {
    local restart_docker="${1:-false}"
    
    log "Restarting services (restart_docker=$restart_docker)..."
    
    if [ "$restart_docker" = "true" ] && command -v docker >/dev/null 2>&1; then
        log "Restarting Docker services..."
        
        local compose_file="/home/ubuntu/GeuseMaker/docker-compose.gpu-optimized.yml"
        if [ -f "$compose_file" ]; then
            cd "$(dirname "$compose_file")"
            
            # Stop services
            if docker-compose -f "$compose_file" ps -q | grep -q .; then
                log "Stopping existing Docker services..."
                docker-compose -f "$compose_file" down || warning "Failed to stop some services"
            fi
            
            # Start services with new environment
            log "Starting Docker services with updated environment..."
            if docker-compose -f "$compose_file" up -d; then
                success "Docker services restarted successfully"
            else
                warning "Failed to restart Docker services"
                return 1
            fi
        else
            warning "Docker Compose file not found: $compose_file"
        fi
    fi
    
    success "Service restart completed"
}

# =============================================================================
# MAIN EXECUTION FUNCTIONS
# =============================================================================

# Run comprehensive diagnosis
run_diagnosis() {
    log "Running comprehensive variable diagnosis..."
    echo ""
    
    local diagnosis_results=()
    
    # Check system prerequisites
    if ! check_system_prerequisites; then
        diagnosis_results+=("FAILED: System prerequisites")
    else
        diagnosis_results+=("PASSED: System prerequisites")
    fi
    
    # Check AWS connectivity
    if ! check_aws_connectivity; then
        diagnosis_results+=("FAILED: AWS connectivity")
    else
        diagnosis_results+=("PASSED: AWS connectivity")
    fi
    
    # Diagnose variable state
    diagnose_variable_state
    
    # Check Docker integration
    if ! check_docker_integration; then
        diagnosis_results+=("FAILED: Docker integration")
    else
        diagnosis_results+=("PASSED: Docker integration")
    fi
    
    # Report results
    echo ""
    echo "=== DIAGNOSIS SUMMARY ==="
    for result in "${diagnosis_results[@]}"; do
        if [[ "$result" == PASSED* ]]; then
            echo -e "  ${GREEN}$result${NC}"
        else
            echo -e "  ${RED}$result${NC}"
        fi
    done
    echo ""
}

# Run automatic fixes
run_fixes() {
    local restart_services_flag="${1:-false}"
    
    log "Running automatic fixes for variable issues..."
    
    # Install/update variable management library
    if ! install_variable_management; then
        error "Failed to install variable management library"
        return 1
    fi
    
    # Regenerate variables and environment files
    if ! regenerate_variables; then
        error "Failed to regenerate variables"
        return 1
    fi
    
    # Fix file permissions
    if ! fix_permissions; then
        error "Failed to fix file permissions"
        return 1
    fi
    
    # Restart services if requested
    if [ "$restart_services_flag" = "true" ]; then
        if ! restart_services true; then
            warning "Service restart had issues"
        fi
    fi
    
    success "All fixes completed successfully"
}

# Show usage information
show_usage() {
    echo "GeuseMaker Variable Issues Fix Script v$SCRIPT_VERSION"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  diagnose    Run comprehensive diagnosis of variable issues (default)"
    echo "  fix         Run automatic fixes for variable issues"
    echo "  regenerate  Regenerate all environment variables and files"
    echo "  status      Show current variable status"
    echo ""
    echo "Options:"
    echo "  --restart-services    Restart Docker services after fixes"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 diagnose"
    echo "  $0 fix --restart-services"
    echo "  $0 regenerate"
}

# Main execution
main() {
    local command="diagnose"
    local restart_services_flag="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            diagnose|fix|regenerate|status)
                command="$1"
                shift
                ;;
            --restart-services)
                restart_services_flag="true"
                shift
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
    
    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log "Starting Variable Issues Fix Script v$SCRIPT_VERSION"
    log "Command: $command"
    log "Restart services: $restart_services_flag"
    
    case "$command" in
        "diagnose")
            run_diagnosis
            ;;
        "fix")
            run_diagnosis
            echo ""
            run_fixes "$restart_services_flag"
            echo ""
            log "Running post-fix diagnosis..."
            run_diagnosis
            ;;
        "regenerate")
            run_fixes "false"
            ;;
        "status")
            diagnose_variable_state
            ;;
    esac
    
    log "Script execution completed"
}

# Execute main function with all arguments
main "$@"