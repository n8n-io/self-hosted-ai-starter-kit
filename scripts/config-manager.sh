#!/bin/bash
# =============================================================================
# Configuration Manager for GeuseMaker
# Enhanced version using centralized configuration management system
# =============================================================================

set -euo pipefail

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"
CONFIG_DIR="$PROJECT_ROOT/config"

# =============================================================================
# LOAD SHARED LIBRARIES
# =============================================================================

# Load error handling first
if [ -f "$LIB_DIR/error-handling.sh" ]; then
    source "$LIB_DIR/error-handling.sh"
    init_error_handling "resilient"
fi

# Load core libraries
if [ -f "$LIB_DIR/aws-deployment-common.sh" ]; then
    source "$LIB_DIR/aws-deployment-common.sh"
fi

# Load the new centralized configuration management system
if [ -f "$LIB_DIR/config-management.sh" ]; then
    source "$LIB_DIR/config-management.sh"
    CONFIG_MANAGEMENT_AVAILABLE=true
else
    CONFIG_MANAGEMENT_AVAILABLE=false
    warning "Centralized configuration management not available, using legacy mode"
fi

# =============================================================================
# LEGACY FUNCTIONS (for backward compatibility)
# =============================================================================

# Legacy configuration loading (fallback when new system is not available)
legacy_load_environment_config() {
    local env="$1"
    local config_file="$CONFIG_DIR/environments/${env}.yml"
    
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
        return 1
    fi
    
    log "Loading legacy configuration for environment: $env"
    export CONFIG_FILE="$config_file"
    export ENVIRONMENT="$env"
    
    # Extract key values using yq (if available)
    if command -v yq >/dev/null 2>&1; then
        export STACK_NAME=$(yq eval '.global.stack_name' "$config_file")
        export AWS_REGION=$(yq eval '.global.region' "$config_file")
        export PROJECT_NAME=$(yq eval '.global.project_name' "$config_file")
    else
        # Fallback to grep-based extraction
        export STACK_NAME=$(grep -A1 'stack_name:' "$config_file" | tail -n1 | sed 's/.*: //')
        export AWS_REGION=$(grep -A1 'region:' "$config_file" | tail -n1 | sed 's/.*: //')
        export PROJECT_NAME=$(grep -A1 'project_name:' "$config_file" | tail -n1 | sed 's/.*: //')
    fi
    
    success "Legacy configuration loaded for $env environment"
    return 0
}

# Legacy Docker Compose override generation
legacy_generate_docker_compose_override() {
    local env="$1"
    local output_file="$PROJECT_ROOT/docker-compose.override.yml"
    
    log "Generating legacy Docker Compose override for $env environment"
    
    # Create override file with environment-specific settings
    cat > "$output_file" << EOF
# Generated Docker Compose Override (Legacy Mode)
# Environment: $env
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# DO NOT EDIT MANUALLY - Use config-manager.sh to regenerate

version: '3.8'

services:
  postgres:
    environment:
      - POSTGRES_DB=\${POSTGRES_DB:-n8n}
      - POSTGRES_USER=\${POSTGRES_USER:-n8n}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
        reservations:
          memory: 512M
          cpus: '0.25'

  n8n:
    environment:
      - N8N_HOST=\${N8N_HOST:-0.0.0.0}
      - N8N_PORT=5678
      - WEBHOOK_URL=\${WEBHOOK_URL:-http://localhost:5678}
      - N8N_CORS_ENABLE=\${N8N_CORS_ENABLE:-true}
      - N8N_CORS_ALLOWED_ORIGINS=\${N8N_CORS_ALLOWED_ORIGINS:-*}
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.25'

  ollama:
    environment:
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=\${OLLAMA_ORIGINS:-http://localhost:*}
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '1.0'
        reservations:
          memory: 2G
          cpus: '0.5'

  qdrant:
    environment:
      - QDRANT__SERVICE__HTTP_PORT=6333
      - QDRANT__SERVICE__GRPC_PORT=6334
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
        reservations:
          memory: 512M
          cpus: '0.25'

  crawl4ai:
    environment:
      - CRAWL4AI_HOST=0.0.0.0
      - CRAWL4AI_PORT=11235
      - CRAWL4AI_RATE_LIMITING_ENABLED=false
      - CRAWL4AI_MAX_CONCURRENT_SESSIONS=1
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
        reservations:
          memory: 512M
          cpus: '0.25'
EOF

    success "Legacy Docker Compose override generated: $output_file"
    return 0
}

# Legacy environment file generation
legacy_generate_env_file() {
    local env="$1"
    local output_file="$PROJECT_ROOT/.env.${env}"
    
    log "Generating legacy environment file for $env"
    
    cat > "$output_file" << EOF
# Generated Environment Configuration (Legacy Mode)
# Environment: $env
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# DO NOT EDIT MANUALLY - Use config-manager.sh to regenerate

# Global Configuration
ENVIRONMENT=$env
AWS_REGION=us-east-1
STACK_NAME=GeuseMaker-$env
PROJECT_NAME=GeuseMaker

# Infrastructure Configuration
VPC_CIDR=10.0.0.0/16
EFS_PERFORMANCE_MODE=generalPurpose
EFS_ENCRYPTION=false
BACKUP_RETENTION_DAYS=7

# Auto Scaling Configuration
ASG_MIN_CAPACITY=1
ASG_MAX_CAPACITY=2
ASG_TARGET_UTILIZATION=80

# Security Configuration
CONTAINER_SECURITY_ENABLED=false
NETWORK_SECURITY_STRICT=false
SECRETS_MANAGER_ENABLED=false

# Monitoring Configuration
MONITORING_ENABLED=true
LOG_LEVEL=debug
LOG_FORMAT=text
METRICS_RETENTION_DAYS=7

# Cost Optimization Configuration
SPOT_INSTANCES_ENABLED=false
SPOT_MAX_PRICE=1.00
AUTO_SCALING_ENABLED=true
IDLE_TIMEOUT_MINUTES=10

# Application-specific placeholders (to be filled by deployment scripts)
POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_USER_MANAGEMENT_JWT_SECRET}
OPENAI_API_KEY=\${OPENAI_API_KEY}

# EFS DNS (set by deployment script)
EFS_DNS=\${EFS_DNS}
INSTANCE_ID=\${INSTANCE_ID}
EOF

    success "Legacy environment file generated: $output_file"
    return 0
}

# =============================================================================
# ENHANCED FUNCTIONS (using new centralized system)
# =============================================================================

# Enhanced configuration loading with fallback
enhanced_load_environment_config() {
    local env="$1"
    
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
        log "Using enhanced configuration management system"
        
        # Use the new centralized system
        local config_file="$CONFIG_DIR/environments/${env}.yml"
        if load_configuration "$config_file" "$env"; then
            success "Enhanced configuration loaded for $env environment"
            return 0
        else
            warning "Enhanced configuration loading failed, falling back to legacy mode"
            return legacy_load_environment_config "$env"
        fi
    else
        log "Using legacy configuration management system"
        return legacy_load_environment_config "$env"
    fi
}

# Enhanced Docker Compose override generation
enhanced_generate_docker_compose_override() {
    local env="$1"
    local output_file="$PROJECT_ROOT/docker-compose.override.yml"
    
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
        log "Using enhanced Docker Compose generation"
        
        local config_file="$CONFIG_DIR/environments/${env}.yml"
        if generate_docker_compose "$config_file" "$env" "$output_file"; then
            success "Enhanced Docker Compose override generated: $output_file"
            return 0
        else
            warning "Enhanced Docker Compose generation failed, falling back to legacy mode"
            return legacy_generate_docker_compose_override "$env"
        fi
    else
        log "Using legacy Docker Compose generation"
        return legacy_generate_docker_compose_override "$env"
    fi
}

# Enhanced environment file generation
enhanced_generate_env_file() {
    local env="$1"
    local output_file="$PROJECT_ROOT/.env.${env}"
    
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
        log "Using enhanced environment file generation"
        
        local config_file="$CONFIG_DIR/environments/${env}.yml"
        if generate_environment_file "$config_file" "$env" "$output_file"; then
            success "Enhanced environment file generated: $output_file"
            return 0
        else
            warning "Enhanced environment file generation failed, falling back to legacy mode"
            return legacy_generate_env_file "$env"
        fi
    else
        log "Using legacy environment file generation"
        return legacy_generate_env_file "$env"
    fi
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Validate environment
validate_environment() {
    local env="$1"
    local valid_environments=("development" "staging" "production")
    
    for valid_env in "${valid_environments[@]}"; do
        if [[ "$env" == "$valid_env" ]]; then
            return 0
        fi
    done
    
    error "Invalid environment: $env"
    echo "Valid environments: ${valid_environments[*]}"
    return 1
}

# Generate all configuration files
generate_all_config_files() {
    local env="$1"
    
    log "Generating all configuration files for environment: $env"
    
    # Validate environment
    if ! validate_environment "$env"; then
        return 1
    fi
    
    # Load configuration
    if ! enhanced_load_environment_config "$env"; then
        error "Failed to load configuration for $env"
        return 1
    fi
    
    # Generate environment file
    if ! enhanced_generate_env_file "$env"; then
        error "Failed to generate environment file for $env"
        return 1
    fi
    
    # Generate Docker Compose override
    if ! enhanced_generate_docker_compose_override "$env"; then
        error "Failed to generate Docker Compose override for $env"
        return 1
    fi
    
    # Generate Terraform variables (if Terraform is used)
    if [ -d "$PROJECT_ROOT/terraform" ]; then
        generate_terraform_variables "$env"
    fi
    
    success "All configuration files generated for $env environment"
    return 0
}

# Generate Terraform variables
generate_terraform_variables() {
    local env="$1"
    local output_file="$PROJECT_ROOT/terraform/${env}.tfvars"
    
    log "Generating Terraform variables for $env environment"
    
    cat > "$output_file" << EOF
# Generated Terraform Variables
# Environment: $env
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# DO NOT EDIT MANUALLY - Use config-manager.sh to regenerate

stack_name = "GeuseMaker-$env"
environment = "$env"
aws_region = "us-east-1"
owner = "GeuseMaker"

# Instance configuration
instance_type = "t3.micro"
key_name = "GeuseMaker-key"

# Networking
vpc_cidr = "10.0.0.0/16"
subnet_cidr = "10.0.1.0/24"

# Storage
ebs_volume_size = 20
ebs_volume_type = "gp3"

# Auto scaling
min_size = 1
max_size = 2
desired_capacity = 1

# Tags
tags = {
  Environment = "$env"
  Project     = "GeuseMaker"
  ManagedBy   = "config-manager"
}
EOF

    success "Terraform variables generated: $output_file"
    return 0
}

# Validate configuration
validate_configuration() {
    local env="$1"
    
    log "Validating configuration for environment: $env"
    
    # Validate environment
    if ! validate_environment "$env"; then
        return 1
    fi
    
    # Check if configuration file exists
    local config_file="$CONFIG_DIR/environments/${env}.yml"
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Use enhanced validation if available
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
        if validate_configuration_file "$config_file"; then
            success "Configuration validation passed for $env"
            return 0
        else
            error "Configuration validation failed for $env"
            return 1
        fi
    else
        # Basic validation for legacy mode
        if command -v yq >/dev/null 2>&1; then
            if yq eval '.' "$config_file" >/dev/null 2>&1; then
                success "Basic configuration validation passed for $env"
                return 0
            else
                error "Basic configuration validation failed for $env"
                return 1
            fi
        else
            warning "yq not available, skipping configuration validation"
            return 0
        fi
    fi
}

# Show configuration summary
show_configuration_summary() {
    local env="$1"
    
    log "Showing configuration summary for environment: $env"
    
    # Load configuration
    if ! enhanced_load_environment_config "$env"; then
        error "Failed to load configuration for $env"
        return 1
    fi
    
    echo
    echo "Configuration Summary for $env Environment"
    echo "=========================================="
    echo "Environment: $env"
    echo "Stack Name: ${STACK_NAME:-N/A}"
    echo "AWS Region: ${AWS_REGION:-N/A}"
    echo "Project Name: ${PROJECT_NAME:-N/A}"
    echo
    
    # Show enhanced summary if available
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
        if declare -f get_config_summary >/dev/null 2>&1; then
            get_config_summary
        fi
    fi
    
    echo "Configuration Management System: $([ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ] && echo "Enhanced" || echo "Legacy")"
    echo
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
Configuration Manager for GeuseMaker

USAGE:
    $0 <command> <environment>

COMMANDS:
    generate <env>     Generate all configuration files for environment
    validate <env>     Validate configuration for environment
    show <env>         Show configuration summary for environment
    override <env>     Generate only Docker Compose override
    env <env>          Generate only environment file
    terraform <env>    Generate only Terraform variables
    help              Show this help message

ENVIRONMENTS:
    development       Development environment configuration
    staging           Staging environment configuration  
    production        Production environment configuration

EXAMPLES:
    $0 generate development     # Generate all files for development
    $0 validate production      # Validate production configuration
    $0 show staging            # Show staging configuration summary
    $0 override development    # Generate only Docker Compose override

FEATURES:
    ✅ Enhanced configuration management system (when available)
    ✅ Legacy mode fallback for backward compatibility
    ✅ Comprehensive validation and error handling
    ✅ Integration with shared libraries
    ✅ Cross-platform compatibility (bash 3.x/4.x)

DEPENDENCIES:
    yq                YAML processor (recommended)
    jq                JSON processor (recommended)
    envsubst          Environment variable substitution

FILES GENERATED:
    docker-compose.override.yml   Environment-specific Docker Compose overrides
    .env.<environment>           Environment variables
    terraform/<env>.tfvars       Terraform variables file

EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local command="${1:-}"
    local environment="${2:-}"
    
    case "$command" in
        "generate")
            if [[ -z "$environment" ]]; then
                error "Environment not specified"
                show_help
                exit 1
            fi
            generate_all_config_files "$environment"
            ;;
        "validate")
            if [[ -z "$environment" ]]; then
                error "Environment not specified"
                show_help
                exit 1
            fi
            validate_configuration "$environment"
            ;;
        "show")
            if [[ -z "$environment" ]]; then
                error "Environment not specified"
                show_help
                exit 1
            fi
            show_configuration_summary "$environment"
            ;;
        "override")
            if [[ -z "$environment" ]]; then
                error "Environment not specified"
                show_help
                exit 1
            fi
            enhanced_load_environment_config "$environment" && enhanced_generate_docker_compose_override "$environment"
            ;;
        "env")
            if [[ -z "$environment" ]]; then
                error "Environment not specified"
                show_help
                exit 1
            fi
            enhanced_load_environment_config "$environment" && enhanced_generate_env_file "$environment"
            ;;
        "terraform")
            if [[ -z "$environment" ]]; then
                error "Environment not specified"
                show_help
                exit 1
            fi
            generate_terraform_variables "$environment"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        "")
            show_help
            exit 1
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