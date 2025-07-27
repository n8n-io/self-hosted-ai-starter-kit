#!/bin/bash
# =============================================================================
# Environment Variable Validation and Default Setup
# Validates and sets default values for all required environment variables
# =============================================================================

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]; then
    source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
fi

# =============================================================================
# ENVIRONMENT VARIABLE DEFINITIONS AND DEFAULTS
# =============================================================================

# =============================================================================
# VARIABLE LOOKUP FUNCTIONS (bash 3.x compatible)
# =============================================================================

get_required_default() {
    local var_name="$1"
    case "$var_name" in
        "AWS_REGION") echo "us-east-1" ;;
        "STACK_NAME") echo "GeuseMaker-development" ;;
        "PROJECT_NAME") echo "GeuseMaker" ;;
        "ENVIRONMENT") echo "development" ;;
        "DEPLOYMENT_TYPE") echo "simple" ;;
        *) return 1 ;;
    esac
}

get_optional_default() {
    local var_name="$1"
    case "$var_name" in
        "VPC_CIDR") echo "10.0.0.0/16" ;;
        "EFS_PERFORMANCE_MODE") echo "generalPurpose" ;;
        "EFS_ENCRYPTION") echo "true" ;;
        "BACKUP_RETENTION_DAYS") echo "30" ;;
        "ASG_MIN_CAPACITY") echo "1" ;;
        "ASG_MAX_CAPACITY") echo "3" ;;
        "ASG_TARGET_UTILIZATION") echo "70" ;;
        "CONTAINER_SECURITY_ENABLED") echo "true" ;;
        "NETWORK_SECURITY_STRICT") echo "true" ;;
        "SECRETS_MANAGER_ENABLED") echo "true" ;;
        "MONITORING_ENABLED") echo "true" ;;
        "LOG_LEVEL") echo "info" ;;
        "LOG_FORMAT") echo "json" ;;
        "METRICS_RETENTION_DAYS") echo "30" ;;
        "SPOT_INSTANCES_ENABLED") echo "false" ;;
        "SPOT_MAX_PRICE") echo "2.00" ;;
        "AUTO_SCALING_ENABLED") echo "true" ;;
        "IDLE_TIMEOUT_MINUTES") echo "30" ;;
        *) return 1 ;;
    esac
}

is_sensitive_var() {
    local var_name="$1"
    case "$var_name" in
        "POSTGRES_PASSWORD"|"N8N_ENCRYPTION_KEY"|"N8N_USER_MANAGEMENT_JWT_SECRET"|\
        "OPENAI_API_KEY"|"ANTHROPIC_API_KEY"|"DEEPSEEK_API_KEY"|"GROQ_API_KEY"|\
        "TOGETHER_API_KEY"|"MISTRAL_API_KEY"|"GEMINI_API_TOKEN")
            return 0 ;;
        *) return 1 ;;
    esac
}

is_dynamic_var() {
    local var_name="$1"
    case "$var_name" in
        "EFS_DNS"|"INSTANCE_ID"|"INSTANCE_TYPE"|"WEBHOOK_URL"|"NOTIFICATION_WEBHOOK"|"AWS_DEFAULT_REGION")
            return 0 ;;
        *) return 1 ;;
    esac
}

# Get list of required variables
get_required_vars() {
    echo "AWS_REGION STACK_NAME PROJECT_NAME ENVIRONMENT DEPLOYMENT_TYPE"
}

# Get list of optional variables  
get_optional_vars() {
    echo "VPC_CIDR EFS_PERFORMANCE_MODE EFS_ENCRYPTION BACKUP_RETENTION_DAYS ASG_MIN_CAPACITY ASG_MAX_CAPACITY ASG_TARGET_UTILIZATION CONTAINER_SECURITY_ENABLED NETWORK_SECURITY_STRICT SECRETS_MANAGER_ENABLED MONITORING_ENABLED LOG_LEVEL LOG_FORMAT METRICS_RETENTION_DAYS SPOT_INSTANCES_ENABLED SPOT_MAX_PRICE AUTO_SCALING_ENABLED IDLE_TIMEOUT_MINUTES"
}

# Get list of sensitive variables
get_sensitive_vars() {
    echo "POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY GROQ_API_KEY TOGETHER_API_KEY MISTRAL_API_KEY GEMINI_API_TOKEN"
}

# Get list of dynamic variables
get_dynamic_vars() {
    echo "EFS_DNS INSTANCE_ID INSTANCE_TYPE WEBHOOK_URL NOTIFICATION_WEBHOOK AWS_DEFAULT_REGION"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate AWS region format
validate_aws_region() {
    local region="$1"
    
    if [[ ! "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
        warning "AWS region format may be invalid: $region"
        return 1
    fi
    
    return 0
}

# Validate stack name format
validate_stack_name() {
    local stack_name="$1"
    
    if [[ ! "$stack_name" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,127}$ ]]; then
        error "Invalid stack name format. Must start with letter, contain only alphanumeric and hyphens, max 128 chars: $stack_name"
        return 1
    fi
    
    return 0
}

# Validate environment name
validate_environment() {
    local env="$1"
    local valid_environments="development staging production"
    
    for valid_env in $valid_environments; do
        if [[ "$env" == "$valid_env" ]]; then
            return 0
        fi
    done
    
    error "Invalid environment: $env. Valid options: $valid_environments"
    return 1
}

# Validate deployment type
validate_deployment_type() {
    local type="$1"
    local valid_types="simple spot ondemand"
    
    for valid_type in $valid_types; do
        if [[ "$type" == "$valid_type" ]]; then
            return 0
        fi
    done
    
    error "Invalid deployment type: $type. Valid options: $valid_types"
    return 1
}

# Validate numeric values
validate_numeric() {
    local var_name="$1"
    local value="$2"
    local min="${3:-0}"
    local max="${4:-999999}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        error "$var_name must be a numeric value: $value"
        return 1
    fi
    
    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        error "$var_name value out of range ($min-$max): $value"
        return 1
    fi
    
    return 0
}

# Validate boolean values
validate_boolean() {
    local var_name="$1"
    local value="$2"
    
    # Convert to lowercase using bash 3.x compatible method
    local lowercase_value
    lowercase_value=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    
    case "$lowercase_value" in
        "true"|"false"|"yes"|"no"|"1"|"0")
            return 0
            ;;
        *)
            error "$var_name must be a boolean value (true/false): $value"
            return 1
            ;;
    esac
}

# =============================================================================
# DEFAULT VALUE FUNCTIONS
# =============================================================================

# Generate secure default for sensitive variables
generate_secure_default() {
    local var_name="$1"
    
    case "$var_name" in
        *"PASSWORD"*|*"SECRET"*|*"KEY"*)
            # Generate 32-character random string
            openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -d '=+/' | head -c 32
            ;;
        *)
            echo ""
            ;;
    esac
}

# Set default values for required variables
set_required_defaults() {
    log "Setting defaults for required environment variables..."
    
    # Use bash 3.x compatible iteration
    for var_name in AWS_REGION STACK_NAME PROJECT_NAME ENVIRONMENT DEPLOYMENT_TYPE; do
        case "$var_name" in
            "AWS_REGION") default_value="us-east-1" ;;
            "STACK_NAME") default_value="GeuseMaker-development" ;;
            "PROJECT_NAME") default_value="GeuseMaker" ;;
            "ENVIRONMENT") default_value="development" ;;
            "DEPLOYMENT_TYPE") default_value="simple" ;;
        esac
        
        if [[ -z "${!var_name:-}" ]]; then
            export "$var_name=$default_value"
            info "Set default $var_name=$default_value"
        fi
    done
}

# Set default values for optional variables
set_optional_defaults() {
    log "Setting defaults for optional environment variables..."
    
    # Bash 3.x compatible approach
    local vars="VPC_CIDR EFS_PERFORMANCE_MODE EFS_ENCRYPTION BACKUP_RETENTION_DAYS ASG_MIN_CAPACITY ASG_MAX_CAPACITY ASG_TARGET_UTILIZATION CONTAINER_SECURITY_ENABLED NETWORK_SECURITY_STRICT SECRETS_MANAGER_ENABLED MONITORING_ENABLED LOG_LEVEL LOG_FORMAT METRICS_RETENTION_DAYS SPOT_INSTANCES_ENABLED SPOT_MAX_PRICE AUTO_SCALING_ENABLED IDLE_TIMEOUT_MINUTES"
    
    for var_name in $vars; do
        case "$var_name" in
            "VPC_CIDR") default_value="10.0.0.0/16" ;;
            "EFS_PERFORMANCE_MODE") default_value="generalPurpose" ;;
            "EFS_ENCRYPTION") default_value="true" ;;
            "BACKUP_RETENTION_DAYS") default_value="30" ;;
            "ASG_MIN_CAPACITY") default_value="1" ;;
            "ASG_MAX_CAPACITY") default_value="3" ;;
            "ASG_TARGET_UTILIZATION") default_value="70" ;;
            "CONTAINER_SECURITY_ENABLED") default_value="true" ;;
            "NETWORK_SECURITY_STRICT") default_value="true" ;;
            "SECRETS_MANAGER_ENABLED") default_value="true" ;;
            "MONITORING_ENABLED") default_value="true" ;;
            "LOG_LEVEL") default_value="info" ;;
            "LOG_FORMAT") default_value="json" ;;
            "METRICS_RETENTION_DAYS") default_value="30" ;;
            "SPOT_INSTANCES_ENABLED") default_value="false" ;;
            "SPOT_MAX_PRICE") default_value="2.00" ;;
            "AUTO_SCALING_ENABLED") default_value="true" ;;
            "IDLE_TIMEOUT_MINUTES") default_value="30" ;;
        esac
        
        if [[ -z "${!var_name:-}" ]]; then
            export "$var_name=$default_value"
            debug "Set default $var_name=$default_value"
        fi
    done
}

# Set safe defaults for sensitive variables (but warn about missing values)
set_sensitive_defaults() {
    log "Checking sensitive environment variables..."
    
    local sensitive_vars="POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY GROQ_API_KEY TOGETHER_API_KEY MISTRAL_API_KEY GEMINI_API_TOKEN"
    local missing_sensitive=""
    
    for var_name in $sensitive_vars; do
        if [[ -z "${!var_name:-}" ]]; then
            # Generate secure default for passwords and keys
            case "$var_name" in
                *"PASSWORD"*|*"SECRET"*|*"ENCRYPTION_KEY"*)
                    local secure_default
                    secure_default=$(generate_secure_default "$var_name")
                    export "$var_name=$secure_default"
                    info "Generated secure default for $var_name"
                    ;;
                *"API_KEY"*|*"TOKEN"*)
                    # Set empty default for API keys but warn
                    export "$var_name="
                    if [ -z "$missing_sensitive" ]; then
                        missing_sensitive="$var_name"
                    else
                        missing_sensitive="$missing_sensitive $var_name"
                    fi
                    ;;
            esac
        fi
    done
    
    if [ -n "$missing_sensitive" ]; then
        warning "Missing optional API keys (features may be limited): $missing_sensitive"
        warning "Set these via AWS Parameter Store or environment variables for full functionality"
    fi
}

# Set dynamic variables to safe defaults
set_dynamic_defaults() {
    log "Setting defaults for dynamic variables..."
    
    # Set AWS_DEFAULT_REGION to match AWS_REGION
    if [[ -z "${AWS_DEFAULT_REGION:-}" ]]; then
        export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
    fi
    
    # Set empty defaults for other dynamic variables
    local dynamic_vars="EFS_DNS INSTANCE_ID INSTANCE_TYPE WEBHOOK_URL NOTIFICATION_WEBHOOK"
    for var_name in $dynamic_vars; do
        if [[ -z "${!var_name:-}" ]]; then
            export "$var_name="
        fi
    done
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate all environment variables
validate_all_variables() {
    log "Validating all environment variables..."
    
    local validation_errors=0
    
    # Validate required variables
    if ! validate_aws_region "${AWS_REGION:-}"; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if ! validate_stack_name "${STACK_NAME:-}"; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if ! validate_environment "${ENVIRONMENT:-}"; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if ! validate_deployment_type "${DEPLOYMENT_TYPE:-}"; then
        validation_errors=$((validation_errors + 1))
    fi
    
    # Validate numeric variables
    if ! validate_numeric "BACKUP_RETENTION_DAYS" "${BACKUP_RETENTION_DAYS:-}" 1 365; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if ! validate_numeric "ASG_MIN_CAPACITY" "${ASG_MIN_CAPACITY:-}" 0 100; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if ! validate_numeric "ASG_MAX_CAPACITY" "${ASG_MAX_CAPACITY:-}" 1 100; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if ! validate_numeric "ASG_TARGET_UTILIZATION" "${ASG_TARGET_UTILIZATION:-}" 10 95; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if ! validate_numeric "METRICS_RETENTION_DAYS" "${METRICS_RETENTION_DAYS:-}" 1 365; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if ! validate_numeric "IDLE_TIMEOUT_MINUTES" "${IDLE_TIMEOUT_MINUTES:-}" 1 1440; then
        validation_errors=$((validation_errors + 1))
    fi
    
    # Validate boolean variables
    local boolean_vars="EFS_ENCRYPTION CONTAINER_SECURITY_ENABLED NETWORK_SECURITY_STRICT SECRETS_MANAGER_ENABLED MONITORING_ENABLED SPOT_INSTANCES_ENABLED AUTO_SCALING_ENABLED"
    for var_name in $boolean_vars; do
        if ! validate_boolean "$var_name" "${!var_name}"; then
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    if [ $validation_errors -gt 0 ]; then
        error "Environment validation failed with $validation_errors errors"
        return 1
    fi
    
    success "Environment validation passed"
    return 0
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Complete environment setup and validation
setup_environment() {
    section "Environment Variable Setup and Validation"
    
    # Set all defaults
    set_required_defaults
    set_optional_defaults
    set_sensitive_defaults
    set_dynamic_defaults
    
    # Validate all variables
    validate_all_variables
    
    success "Environment setup completed successfully"
}

# Display environment summary
show_environment_summary() {
    section "Environment Configuration Summary"
    
    echo "Required Configuration:"
    echo "  Environment: ${ENVIRONMENT:-unset}"
    echo "  AWS Region: ${AWS_REGION:-unset}"
    echo "  Stack Name: ${STACK_NAME:-unset}"
    echo "  Project Name: ${PROJECT_NAME:-unset}"
    echo "  Deployment Type: ${DEPLOYMENT_TYPE:-unset}"
    echo
    
    echo "Infrastructure Configuration:"
    echo "  VPC CIDR: ${VPC_CIDR}"
    echo "  EFS Performance Mode: ${EFS_PERFORMANCE_MODE}"
    echo "  EFS Encryption: ${EFS_ENCRYPTION}"
    echo "  Backup Retention: ${BACKUP_RETENTION_DAYS} days"
    echo
    
    echo "Auto Scaling Configuration:"
    echo "  Min Capacity: ${ASG_MIN_CAPACITY}"
    echo "  Max Capacity: ${ASG_MAX_CAPACITY}"
    echo "  Target Utilization: ${ASG_TARGET_UTILIZATION}%"
    echo "  Spot Instances: ${SPOT_INSTANCES_ENABLED}"
    echo "  Auto Scaling: ${AUTO_SCALING_ENABLED}"
    echo
    
    echo "Security Configuration:"
    echo "  Container Security: ${CONTAINER_SECURITY_ENABLED}"
    echo "  Network Security: ${NETWORK_SECURITY_STRICT}"
    echo "  Secrets Manager: ${SECRETS_MANAGER_ENABLED}"
    echo
    
    echo "Monitoring Configuration:"
    echo "  Monitoring Enabled: ${MONITORING_ENABLED}"
    echo "  Log Level: ${LOG_LEVEL}"
    echo "  Log Format: ${LOG_FORMAT}"
    echo "  Metrics Retention: ${METRICS_RETENTION_DAYS} days"
    echo
    
    echo "API Keys Status:"
    local api_keys="OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY GROQ_API_KEY TOGETHER_API_KEY MISTRAL_API_KEY GEMINI_API_TOKEN"
    for key in $api_keys; do
        if [[ -n "${!key:-}" ]]; then
            echo "  $key: ✅ Set"
        else
            echo "  $key: ❌ Not set"
        fi
    done
}

# Export environment to file
export_environment() {
    local output_file="${1:-${PROJECT_ROOT}/.env.${ENVIRONMENT}}"
    
    log "Exporting environment to: $output_file"
    
    cat > "$output_file" << EOF
# =============================================================================
# GeuseMaker Environment Configuration
# Generated by validate-environment.sh
# Environment: ${ENVIRONMENT}
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# =============================================================================

# Required Configuration
ENVIRONMENT=${ENVIRONMENT}
AWS_REGION=${AWS_REGION}
STACK_NAME=${STACK_NAME}
PROJECT_NAME=${PROJECT_NAME}
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE}

# Infrastructure Configuration
VPC_CIDR=${VPC_CIDR}
EFS_PERFORMANCE_MODE=${EFS_PERFORMANCE_MODE}
EFS_ENCRYPTION=${EFS_ENCRYPTION}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS}

# Auto Scaling Configuration
ASG_MIN_CAPACITY=${ASG_MIN_CAPACITY}
ASG_MAX_CAPACITY=${ASG_MAX_CAPACITY}
ASG_TARGET_UTILIZATION=${ASG_TARGET_UTILIZATION}

# Security Configuration
CONTAINER_SECURITY_ENABLED=${CONTAINER_SECURITY_ENABLED}
NETWORK_SECURITY_STRICT=${NETWORK_SECURITY_STRICT}
SECRETS_MANAGER_ENABLED=${SECRETS_MANAGER_ENABLED}

# Monitoring Configuration
MONITORING_ENABLED=${MONITORING_ENABLED}
LOG_LEVEL=${LOG_LEVEL}
LOG_FORMAT=${LOG_FORMAT}
METRICS_RETENTION_DAYS=${METRICS_RETENTION_DAYS}

# Cost Optimization Configuration
SPOT_INSTANCES_ENABLED=${SPOT_INSTANCES_ENABLED}
SPOT_MAX_PRICE=${SPOT_MAX_PRICE}
AUTO_SCALING_ENABLED=${AUTO_SCALING_ENABLED}
IDLE_TIMEOUT_MINUTES=${IDLE_TIMEOUT_MINUTES}

# Sensitive Variables (set securely via Parameter Store)
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}

# API Keys (optional - set via Parameter Store for full functionality)
OPENAI_API_KEY=${OPENAI_API_KEY}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
GROQ_API_KEY=${GROQ_API_KEY}
TOGETHER_API_KEY=${TOGETHER_API_KEY}
MISTRAL_API_KEY=${MISTRAL_API_KEY}
GEMINI_API_TOKEN=${GEMINI_API_TOKEN}

# Dynamic Variables (set during deployment)
EFS_DNS=${EFS_DNS}
INSTANCE_ID=${INSTANCE_ID}
INSTANCE_TYPE=${INSTANCE_TYPE}
WEBHOOK_URL=${WEBHOOK_URL}
NOTIFICATION_WEBHOOK=${NOTIFICATION_WEBHOOK}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}
EOF
    
    success "Environment exported to: $output_file"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
Environment Variable Validation and Setup Script

USAGE:
    $0 <command> [options]

COMMANDS:
    setup              Setup and validate environment variables
    validate           Validate current environment variables
    show               Show environment configuration summary
    export [file]      Export environment to file
    help               Show this help message

EXAMPLES:
    $0 setup           # Setup environment with defaults and validation
    $0 validate        # Validate current environment variables
    $0 show            # Show current environment summary
    $0 export          # Export to .env.{ENVIRONMENT} file

EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local command="${1:-help}"
    local option="${2:-}"
    
    case "$command" in
        "setup")
            setup_environment
            ;;
        "validate")
            validate_all_variables
            ;;
        "show")
            show_environment_summary
            ;;
        "export")
            export_environment "$option"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi