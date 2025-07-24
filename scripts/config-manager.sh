#!/bin/bash

# =============================================================================
# Configuration Management Script
# =============================================================================
# Centralized configuration management for the AI starter kit
# Supports multiple environments and dynamic configuration generation
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"

# Load security validation if available
if [[ -f "$SCRIPT_DIR/security-validation.sh" ]]; then
    source "$SCRIPT_DIR/security-validation.sh"
fi

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}" >&2
}

error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

# Check if required tools are available
check_dependencies() {
    local missing_tools=()
    
    for tool in yq jq envsubst; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
        echo "Install them with:"
        echo "  brew install yq jq gettext  # macOS"
        echo "  apt-get install yq jq gettext-base  # Ubuntu"
        return 1
    fi
    
    return 0
}

# Validate environment name
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

# Load environment configuration
load_environment_config() {
    local env="$1"
    local config_file="$CONFIG_DIR/environments/${env}.yml"
    
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
        return 1
    fi
    
    log "Loading configuration for environment: $env"
    export CONFIG_FILE="$config_file"
    export ENVIRONMENT="$env"
    
    # Extract key values using yq
    export STACK_NAME=$(yq eval '.global.stack_name' "$config_file")
    export AWS_REGION=$(yq eval '.global.region' "$config_file")
    export PROJECT_NAME=$(yq eval '.global.project_name' "$config_file")
    
    success "Configuration loaded for $env environment"
    return 0
}

# Generate Docker Compose override file
generate_docker_compose_override() {
    local env="$1"
    local output_file="$PROJECT_ROOT/docker-compose.override.yml"
    
    log "Generating Docker Compose override for $env environment"
    
    # Create override file with environment-specific settings
    cat > "$output_file" << EOF
# Generated Docker Compose Override
# Environment: $env
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# DO NOT EDIT MANUALLY - Use config-manager.sh to regenerate

version: '3.8'

services:
  postgres:
    deploy:
      resources:
        limits:
          memory: $(yq eval '.applications.postgres.resources.memory_limit' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.postgres.resources.cpu_limit' "$CONFIG_FILE")'
        reservations:
          memory: $(yq eval '.applications.postgres.resources.memory_reservation' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.postgres.resources.cpu_reservation' "$CONFIG_FILE")'
    environment:
      - POSTGRES_MAX_CONNECTIONS=$(yq eval '.applications.postgres.config.max_connections' "$CONFIG_FILE")
      - POSTGRES_SHARED_BUFFERS=$(yq eval '.applications.postgres.config.shared_buffers' "$CONFIG_FILE")
      - POSTGRES_EFFECTIVE_CACHE_SIZE=$(yq eval '.applications.postgres.config.effective_cache_size' "$CONFIG_FILE")

  n8n:
    deploy:
      resources:
        limits:
          memory: $(yq eval '.applications.n8n.resources.memory_limit' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.n8n.resources.cpu_limit' "$CONFIG_FILE")'
        reservations:
          memory: $(yq eval '.applications.n8n.resources.memory_reservation' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.n8n.resources.cpu_reservation' "$CONFIG_FILE")'
    environment:
      - N8N_CORS_ALLOWED_ORIGINS=$(yq eval '.applications.n8n.config.cors_allowed_origins' "$CONFIG_FILE")
      - N8N_PAYLOAD_SIZE_MAX=$(yq eval '.applications.n8n.config.payload_size_max' "$CONFIG_FILE")
      - N8N_METRICS=$(yq eval '.applications.n8n.config.metrics' "$CONFIG_FILE")
      - N8N_LOG_LEVEL=$(yq eval '.applications.n8n.config.log_level // "info"' "$CONFIG_FILE")

  ollama:
    deploy:
      resources:
        limits:
          memory: $(yq eval '.applications.ollama.resources.memory_limit' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.ollama.resources.cpu_limit' "$CONFIG_FILE")'
        reservations:
          memory: $(yq eval '.applications.ollama.resources.memory_reservation' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.ollama.resources.cpu_reservation' "$CONFIG_FILE")'
    environment:
      - OLLAMA_GPU_MEMORY_FRACTION=$(yq eval '.applications.ollama.resources.gpu_memory_fraction' "$CONFIG_FILE")
      - OLLAMA_MAX_LOADED_MODELS=$(yq eval '.applications.ollama.config.max_loaded_models' "$CONFIG_FILE")
      - OLLAMA_CONCURRENT_REQUESTS=$(yq eval '.applications.ollama.config.concurrent_requests' "$CONFIG_FILE")

  qdrant:
    deploy:
      resources:
        limits:
          memory: $(yq eval '.applications.qdrant.resources.memory_limit' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.qdrant.resources.cpu_limit' "$CONFIG_FILE")'
        reservations:
          memory: $(yq eval '.applications.qdrant.resources.memory_reservation' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.qdrant.resources.cpu_reservation' "$CONFIG_FILE")'
    environment:
      - QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS=$(yq eval '.applications.qdrant.config.max_search_threads' "$CONFIG_FILE")
      - QDRANT__STORAGE__PERFORMANCE__MAX_OPTIMIZATION_THREADS=$(yq eval '.applications.qdrant.config.max_optimization_threads' "$CONFIG_FILE")
      - QDRANT__STORAGE__WAL__WAL_CAPACITY_MB=$(yq eval '.applications.qdrant.config.wal_capacity_mb' "$CONFIG_FILE")

  crawl4ai:
    deploy:
      resources:
        limits:
          memory: $(yq eval '.applications.crawl4ai.resources.memory_limit' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.crawl4ai.resources.cpu_limit' "$CONFIG_FILE")'
        reservations:
          memory: $(yq eval '.applications.crawl4ai.resources.memory_reservation' "$CONFIG_FILE")
          cpus: '$(yq eval '.applications.crawl4ai.resources.cpu_reservation' "$CONFIG_FILE")'
    environment:
      - CRAWL4AI_RATE_LIMITING_ENABLED=$(yq eval '.applications.crawl4ai.config.rate_limiting_enabled' "$CONFIG_FILE")
      - CRAWL4AI_DEFAULT_LIMIT=$(yq eval '.applications.crawl4ai.config.default_limit // "2000/minute"' "$CONFIG_FILE")
      - CRAWL4AI_MAX_CONCURRENT_SESSIONS=$(yq eval '.applications.crawl4ai.config.max_concurrent_sessions' "$CONFIG_FILE")
EOF

    success "Docker Compose override generated: $output_file"
    return 0
}

# Generate environment file
generate_env_file() {
    local env="$1"
    local output_file="$PROJECT_ROOT/.env.${env}"
    
    log "Generating environment file for $env"
    
    cat > "$output_file" << EOF
# Generated Environment Configuration
# Environment: $env
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# DO NOT EDIT MANUALLY - Use config-manager.sh to regenerate

# Global Configuration
ENVIRONMENT=$env
AWS_REGION=$(yq eval '.global.region' "$CONFIG_FILE")
STACK_NAME=$(yq eval '.global.stack_name' "$CONFIG_FILE")
PROJECT_NAME=$(yq eval '.global.project_name' "$CONFIG_FILE")

# Infrastructure Configuration
VPC_CIDR=$(yq eval '.infrastructure.networking.vpc_cidr' "$CONFIG_FILE")
EFS_PERFORMANCE_MODE=$(yq eval '.infrastructure.storage.efs_performance_mode' "$CONFIG_FILE")
EFS_ENCRYPTION=$(yq eval '.infrastructure.storage.efs_encryption' "$CONFIG_FILE")
BACKUP_RETENTION_DAYS=$(yq eval '.infrastructure.storage.backup_retention_days' "$CONFIG_FILE")

# Auto Scaling Configuration
ASG_MIN_CAPACITY=$(yq eval '.infrastructure.auto_scaling.min_capacity' "$CONFIG_FILE")
ASG_MAX_CAPACITY=$(yq eval '.infrastructure.auto_scaling.max_capacity' "$CONFIG_FILE")
ASG_TARGET_UTILIZATION=$(yq eval '.infrastructure.auto_scaling.target_utilization' "$CONFIG_FILE")

# Security Configuration
CONTAINER_SECURITY_ENABLED=$(yq eval '.security.container_security.run_as_non_root' "$CONFIG_FILE")
NETWORK_SECURITY_STRICT=$(yq eval '.security.network_security.cors_strict_mode' "$CONFIG_FILE")
SECRETS_MANAGER_ENABLED=$(yq eval '.security.secrets_management.use_aws_secrets_manager' "$CONFIG_FILE")

# Monitoring Configuration
MONITORING_ENABLED=$(yq eval '.monitoring.metrics.enabled' "$CONFIG_FILE")
LOG_LEVEL=$(yq eval '.monitoring.logging.level' "$CONFIG_FILE")
LOG_FORMAT=$(yq eval '.monitoring.logging.format' "$CONFIG_FILE")
METRICS_RETENTION_DAYS=$(yq eval '.monitoring.metrics.retention_days' "$CONFIG_FILE")

# Cost Optimization Configuration
SPOT_INSTANCES_ENABLED=$(yq eval '.cost_optimization.spot_instances.enabled' "$CONFIG_FILE")
SPOT_MAX_PRICE=$(yq eval '.cost_optimization.spot_instances.max_price' "$CONFIG_FILE")
AUTO_SCALING_ENABLED=$(yq eval '.cost_optimization.auto_scaling.scale_down_enabled' "$CONFIG_FILE")
IDLE_TIMEOUT_MINUTES=$(yq eval '.cost_optimization.auto_scaling.idle_timeout_minutes' "$CONFIG_FILE")

# Application-specific placeholders (to be filled by deployment scripts)
POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_USER_MANAGEMENT_JWT_SECRET}
OPENAI_API_KEY=\${OPENAI_API_KEY}

# EFS DNS (set by deployment script)
EFS_DNS=\${EFS_DNS}
INSTANCE_ID=\${INSTANCE_ID}
EOF

    success "Environment file generated: $output_file"
    return 0
}

# Generate Terraform variables file
generate_terraform_vars() {
    local env="$1"
    local output_file="$PROJECT_ROOT/terraform/${env}.tfvars"
    
    log "Generating Terraform variables for $env"
    
    # Create terraform directory if it doesn't exist
    mkdir -p "$PROJECT_ROOT/terraform"
    
    cat > "$output_file" << EOF
# Generated Terraform Variables
# Environment: $env
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# DO NOT EDIT MANUALLY - Use config-manager.sh to regenerate

# Global Configuration
environment = "$env"
aws_region = "$(yq eval '.global.region' "$CONFIG_FILE")"
stack_name = "$(yq eval '.global.stack_name' "$CONFIG_FILE")"
project_name = "$(yq eval '.global.project_name' "$CONFIG_FILE")"

# Infrastructure Configuration
vpc_cidr = "$(yq eval '.infrastructure.networking.vpc_cidr' "$CONFIG_FILE")"
public_subnet_cidrs = $(yq eval '.infrastructure.networking.public_subnets' "$CONFIG_FILE" | yq -o json)
private_subnet_cidrs = $(yq eval '.infrastructure.networking.private_subnets' "$CONFIG_FILE" | yq -o json)

# Instance Configuration
preferred_instance_types = $(yq eval '.infrastructure.instance_types.preferred' "$CONFIG_FILE" | yq -o json)
fallback_instance_types = $(yq eval '.infrastructure.instance_types.fallback' "$CONFIG_FILE" | yq -o json)

# Auto Scaling Configuration
asg_min_capacity = $(yq eval '.infrastructure.auto_scaling.min_capacity' "$CONFIG_FILE")
asg_max_capacity = $(yq eval '.infrastructure.auto_scaling.max_capacity' "$CONFIG_FILE")
asg_target_utilization = $(yq eval '.infrastructure.auto_scaling.target_utilization' "$CONFIG_FILE")

# Storage Configuration
efs_performance_mode = "$(yq eval '.infrastructure.storage.efs_performance_mode' "$CONFIG_FILE")"
efs_encryption_enabled = $(yq eval '.infrastructure.storage.efs_encryption' "$CONFIG_FILE")
backup_retention_days = $(yq eval '.infrastructure.storage.backup_retention_days' "$CONFIG_FILE")

# Security Configuration
container_security_enabled = $(yq eval '.security.container_security.run_as_non_root' "$CONFIG_FILE")
secrets_manager_enabled = $(yq eval '.security.secrets_management.use_aws_secrets_manager' "$CONFIG_FILE")
encryption_at_rest = $(yq eval '.security.secrets_management.encryption_at_rest' "$CONFIG_FILE")

# Monitoring Configuration
monitoring_enabled = $(yq eval '.monitoring.metrics.enabled' "$CONFIG_FILE")
log_retention_days = $(yq eval '.monitoring.logging.retention_days' "$CONFIG_FILE")
metrics_retention_days = $(yq eval '.monitoring.metrics.retention_days' "$CONFIG_FILE")

# Cost Optimization Configuration
spot_instances_enabled = $(yq eval '.cost_optimization.spot_instances.enabled' "$CONFIG_FILE")
spot_max_price = "$(yq eval '.cost_optimization.spot_instances.max_price' "$CONFIG_FILE")"
auto_scaling_enabled = $(yq eval '.cost_optimization.auto_scaling.scale_down_enabled' "$CONFIG_FILE")

# Tags
default_tags = {
  Environment = "$env"
  Project = "$(yq eval '.global.project_name' "$CONFIG_FILE")"
  ManagedBy = "terraform"
  GeneratedBy = "config-manager"
}
EOF

    success "Terraform variables generated: $output_file"
    return 0
}

# Validate configuration
validate_configuration() {
    local env="$1"
    
    log "Validating configuration for $env environment"
    
    # Load configuration
    load_environment_config "$env" || return 1
    
    # Validate using security validation if available
    if declare -f validate_aws_region >/dev/null 2>&1; then
        validate_aws_region "$AWS_REGION" || return 1
    fi
    
    # Validate required fields
    local required_fields=("stack_name" "region" "project_name")
    for field in "${required_fields[@]}"; do
        local value=$(yq eval ".global.$field" "$CONFIG_FILE")
        if [[ "$value" == "null" || -z "$value" ]]; then
            error "Required field missing: global.$field"
            return 1
        fi
    done
    
    # Validate resource limits don't exceed physical constraints
    local postgres_cpu=$(yq eval '.applications.postgres.resources.cpu_limit' "$CONFIG_FILE" | sed 's/"//g')
    local n8n_cpu=$(yq eval '.applications.n8n.resources.cpu_limit' "$CONFIG_FILE" | sed 's/"//g')
    local ollama_cpu=$(yq eval '.applications.ollama.resources.cpu_limit' "$CONFIG_FILE" | sed 's/"//g')
    local qdrant_cpu=$(yq eval '.applications.qdrant.resources.cpu_limit' "$CONFIG_FILE" | sed 's/"//g')
    local crawl4ai_cpu=$(yq eval '.applications.crawl4ai.resources.cpu_limit' "$CONFIG_FILE" | sed 's/"//g')
    
    local total_cpu=$(echo "$postgres_cpu + $n8n_cpu + $ollama_cpu + $qdrant_cpu + $crawl4ai_cpu" | bc)
    if (( $(echo "$total_cpu > 4.0" | bc -l) )); then
        warning "Total CPU allocation ($total_cpu) exceeds g4dn.xlarge capacity (4.0 vCPUs)"
    fi
    
    success "Configuration validation passed for $env"
    return 0
}

# Generate all configuration files
generate_all() {
    local env="$1"
    
    log "Generating all configuration files for $env environment"
    
    # Validate first
    validate_configuration "$env" || return 1
    
    # Generate files
    generate_docker_compose_override "$env" || return 1
    generate_env_file "$env" || return 1
    generate_terraform_vars "$env" || return 1
    
    success "All configuration files generated for $env environment"
    
    # Show summary
    echo
    echo "Generated files:"
    echo "  - docker-compose.override.yml"
    echo "  - .env.$env"
    echo "  - terraform/$env.tfvars"
    echo
    echo "Usage:"
    echo "  docker-compose -f docker-compose.gpu-optimized.yml -f docker-compose.override.yml up"
    echo "  source .env.$env && ./scripts/aws-deployment.sh"
    echo
    
    return 0
}

# Display configuration summary
show_config() {
    local env="$1"
    
    load_environment_config "$env" || return 1
    
    echo -e "${BLUE}=== Configuration Summary for $env ===${NC}"
    echo
    echo "Global Settings:"
    echo "  Environment: $(yq eval '.global.environment' "$CONFIG_FILE")"
    echo "  Region: $(yq eval '.global.region' "$CONFIG_FILE")"
    echo "  Stack Name: $(yq eval '.global.stack_name' "$CONFIG_FILE")"
    echo "  Project: $(yq eval '.global.project_name' "$CONFIG_FILE")"
    echo
    echo "Resource Allocation:"
    echo "  PostgreSQL: $(yq eval '.applications.postgres.resources.cpu_limit' "$CONFIG_FILE") CPU, $(yq eval '.applications.postgres.resources.memory_limit' "$CONFIG_FILE") RAM"
    echo "  n8n: $(yq eval '.applications.n8n.resources.cpu_limit' "$CONFIG_FILE") CPU, $(yq eval '.applications.n8n.resources.memory_limit' "$CONFIG_FILE") RAM"
    echo "  Ollama: $(yq eval '.applications.ollama.resources.cpu_limit' "$CONFIG_FILE") CPU, $(yq eval '.applications.ollama.resources.memory_limit' "$CONFIG_FILE") RAM"
    echo "  Qdrant: $(yq eval '.applications.qdrant.resources.cpu_limit' "$CONFIG_FILE") CPU, $(yq eval '.applications.qdrant.resources.memory_limit' "$CONFIG_FILE") RAM"
    echo "  Crawl4AI: $(yq eval '.applications.crawl4ai.resources.cpu_limit' "$CONFIG_FILE") CPU, $(yq eval '.applications.crawl4ai.resources.memory_limit' "$CONFIG_FILE") RAM"
    echo
    echo "Security Settings:"
    echo "  Non-root containers: $(yq eval '.security.container_security.run_as_non_root' "$CONFIG_FILE")"
    echo "  Secrets Manager: $(yq eval '.security.secrets_management.use_aws_secrets_manager' "$CONFIG_FILE")"
    echo "  CORS strict mode: $(yq eval '.security.network_security.cors_strict_mode' "$CONFIG_FILE")"
    echo
    echo "Cost Optimization:"
    echo "  Spot instances: $(yq eval '.cost_optimization.spot_instances.enabled' "$CONFIG_FILE")"
    echo "  Max spot price: \$$(yq eval '.cost_optimization.spot_instances.max_price' "$CONFIG_FILE")/hour"
    echo "  Auto scaling: $(yq eval '.cost_optimization.auto_scaling.scale_down_enabled' "$CONFIG_FILE")"
    echo
}

# Display help
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

DEPENDENCIES:
    yq                YAML processor
    jq                JSON processor
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
    
    if [[ -z "$command" ]]; then
        show_help
        exit 1
    fi
    
    # Commands that don't require environment
    case "$command" in
        help)
            show_help
            exit 0
            ;;
    esac
    
    # Validate environment parameter
    if [[ -z "$environment" ]]; then
        error "Environment parameter required"
        show_help
        exit 1
    fi
    
    # Check dependencies
    check_dependencies || exit 1
    
    # Validate environment
    validate_environment "$environment" || exit 1
    
    # Execute command
    case "$command" in
        generate)
            generate_all "$environment"
            ;;
        validate)
            validate_configuration "$environment"
            ;;
        show)
            show_config "$environment"
            ;;
        override)
            load_environment_config "$environment" && generate_docker_compose_override "$environment"
            ;;
        env)
            load_environment_config "$environment" && generate_env_file "$environment"
            ;;
        terraform)
            load_environment_config "$environment" && generate_terraform_vars "$environment"
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi