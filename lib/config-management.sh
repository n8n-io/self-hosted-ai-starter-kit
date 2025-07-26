#!/bin/bash
# =============================================================================
# Configuration Management Library 
# Centralized configuration system for GeuseMaker project
# =============================================================================
# This library provides centralized configuration management for the GeuseMaker
# project, supporting multiple environments, deployment types, and integrating
# with the existing shared library system.
# =============================================================================

# Prevent multiple sourcing
if [[ "${CONFIG_MANAGEMENT_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly CONFIG_MANAGEMENT_LIB_LOADED=true

# =============================================================================
# CONFIGURATION CONSTANTS AND DEFAULTS
# =============================================================================

# Project structure
readonly CONFIG_MANAGEMENT_VERSION="1.0.0"
readonly PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
readonly ENVIRONMENTS_DIR="${CONFIG_DIR}/environments"
readonly LIB_DIR="${PROJECT_ROOT}/lib"

# Default values (bash 3.x compatible)
readonly DEFAULT_ENVIRONMENT="development"
readonly DEFAULT_REGION="us-east-1"
readonly DEFAULT_DEPLOYMENT_TYPE="simple"

# Valid options arrays (bash 3.x/4.x compatible)
readonly VALID_ENVIRONMENTS="development staging production"
readonly VALID_DEPLOYMENT_TYPES="simple spot ondemand"
readonly VALID_REGIONS="us-east-1 us-west-2 eu-west-1 ap-southeast-1"

# Configuration cache
CONFIG_CACHE_LOADED=false
CURRENT_ENVIRONMENT=""
CURRENT_DEPLOYMENT_TYPE=""
CONFIG_FILE_PATH=""

# =============================================================================
# DEPENDENCY MANAGEMENT
# =============================================================================

# Check if required dependencies are available
check_config_dependencies() {
    local missing_tools=()
    local optional_tools=()
    
    # Required tools
    for tool in yq jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    # Optional tools (graceful degradation)
    for tool in envsubst bc; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            optional_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Missing required dependencies: ${missing_tools[*]}"
        else
            echo "ERROR: Missing required dependencies: ${missing_tools[*]}" >&2
        fi
        echo "Install with:" >&2
        echo "  macOS: brew install yq jq" >&2
        echo "  Ubuntu: apt-get install yq jq" >&2
        return 1
    fi
    
    if [[ ${#optional_tools[@]} -gt 0 ]]; then
        if declare -f warning >/dev/null 2>&1; then
            warning "Optional tools missing (some features may be limited): ${optional_tools[*]}"
        else
            echo "WARNING: Optional tools missing: ${optional_tools[*]}" >&2
        fi
    fi
    
    return 0
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate environment name (bash 3.x compatible)
validate_environment() {
    local env="$1"
    
    if [[ -z "$env" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Environment name cannot be empty"
        else
            echo "ERROR: Environment name cannot be empty" >&2
        fi
        return 1
    fi
    
    # Check against valid environments (bash 3.x compatible)
    local valid=false
    for valid_env in $VALID_ENVIRONMENTS; do
        if [[ "$env" == "$valid_env" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" != "true" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Invalid environment: $env. Valid options: $VALID_ENVIRONMENTS"
        else
            echo "ERROR: Invalid environment: $env. Valid options: $VALID_ENVIRONMENTS" >&2
        fi
        return 1
    fi
    
    return 0
}

# Validate deployment type (bash 3.x compatible)
validate_deployment_type() {
    local type="$1"
    
    if [[ -z "$type" ]]; then
        type="$DEFAULT_DEPLOYMENT_TYPE"
    fi
    
    # Check against valid deployment types (bash 3.x compatible)
    local valid=false
    for valid_type in $VALID_DEPLOYMENT_TYPES; do
        if [[ "$type" == "$valid_type" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" != "true" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Invalid deployment type: $type. Valid options: $VALID_DEPLOYMENT_TYPES"
        else
            echo "ERROR: Invalid deployment type: $type. Valid options: $VALID_DEPLOYMENT_TYPES" >&2
        fi
        return 1
    fi
    
    return 0
}

# Validate AWS region (bash 3.x compatible)
validate_aws_region() {
    local region="$1"
    
    if [[ -z "$region" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "AWS region cannot be empty"
        else
            echo "ERROR: AWS region cannot be empty" >&2
        fi
        return 1
    fi
    
    # Basic AWS region format validation
    if [[ ! "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
        if declare -f warning >/dev/null 2>&1; then
            warning "AWS region format may be invalid: $region"
        else
            echo "WARNING: AWS region format may be invalid: $region" >&2
        fi
    fi
    
    return 0
}

# Validate stack name
validate_stack_name() {
    local stack_name="$1"
    
    if [[ -z "$stack_name" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Stack name cannot be empty"
        else
            echo "ERROR: Stack name cannot be empty" >&2
        fi
        return 1
    fi
    
    # CloudFormation stack name validation
    if [[ ${#stack_name} -gt 128 ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Stack name too long (max 128 characters): $stack_name"
        else
            echo "ERROR: Stack name too long: $stack_name" >&2
        fi
        return 1
    fi
    
    if [[ ! "$stack_name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Invalid stack name format. Must start with letter, contain only alphanumeric and hyphens: $stack_name"
        else
            echo "ERROR: Invalid stack name format: $stack_name" >&2
        fi
        return 1
    fi
    
    return 0
}

# =============================================================================
# CONFIGURATION LOADING AND CACHING
# =============================================================================

# Get configuration file path for environment
get_config_file_path() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    echo "${ENVIRONMENTS_DIR}/${env}.yml"
}

# Check if configuration file exists
config_file_exists() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    local config_file
    config_file=$(get_config_file_path "$env")
    [[ -f "$config_file" ]]
}

# Load configuration for environment with caching
load_config() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    local deployment_type="${2:-$DEFAULT_DEPLOYMENT_TYPE}"
    local force_reload="${3:-false}"
    
    # Validate inputs
    validate_environment "$env" || return 1
    validate_deployment_type "$deployment_type" || return 1
    
    # Check cache
    if [[ "$CONFIG_CACHE_LOADED" == "true" && "$CURRENT_ENVIRONMENT" == "$env" && "$CURRENT_DEPLOYMENT_TYPE" == "$deployment_type" && "$force_reload" != "true" ]]; then
        return 0
    fi
    
    local config_file
    config_file=$(get_config_file_path "$env")
    
    if [[ ! -f "$config_file" ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Configuration file not found: $config_file"
        else
            echo "ERROR: Configuration file not found: $config_file" >&2
        fi
        return 1
    fi
    
    # Load configuration
    if declare -f log >/dev/null 2>&1; then
        log "Loading configuration: environment=$env, type=$deployment_type"
    fi
    
    # Set global variables
    export ENVIRONMENT="$env"
    export DEPLOYMENT_TYPE="$deployment_type"
    export CONFIG_FILE="$config_file"
    export CONFIG_FILE_PATH="$config_file"
    
    # Cache configuration data
    CURRENT_ENVIRONMENT="$env"
    CURRENT_DEPLOYMENT_TYPE="$deployment_type"
    CONFIG_CACHE_LOADED=true
    
    return 0
}

# Clear configuration cache
clear_config_cache() {
    CONFIG_CACHE_LOADED=false
    CURRENT_ENVIRONMENT=""
    CURRENT_DEPLOYMENT_TYPE=""
    CONFIG_FILE_PATH=""
}

# =============================================================================
# CONFIGURATION VALUE RETRIEVAL
# =============================================================================

# Get configuration value with fallback (yq wrapper with error handling)
get_config_value() {
    local path="$1"
    local fallback="${2:-}"
    local config_file="${CONFIG_FILE:-$(get_config_file_path "$CURRENT_ENVIRONMENT")}"
    
    if [[ ! -f "$config_file" ]]; then
        echo "$fallback"
        return 1
    fi
    
    local value
    if value=$(yq eval "$path" "$config_file" 2>/dev/null); then
        if [[ "$value" == "null" || "$value" == "" ]]; then
            echo "$fallback"
        else
            echo "$value"
        fi
    else
        echo "$fallback"
        return 1
    fi
}

# Get global configuration values
get_global_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".global.$key" "$fallback"
}

# Get infrastructure configuration values
get_infrastructure_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".infrastructure.$key" "$fallback"
}

# Get application configuration values
get_application_config() {
    local app="$1"
    local key="$2"
    local fallback="${3:-}"
    get_config_value ".applications.$app.$key" "$fallback"
}

# Get security configuration values
get_security_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".security.$key" "$fallback"
}

# Get monitoring configuration values
get_monitoring_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".monitoring.$key" "$fallback"
}

# Get cost optimization configuration values
get_cost_config() {
    local key="$1"
    local fallback="${2:-}"
    get_config_value ".cost_optimization.$key" "$fallback"
}

# =============================================================================
# ENVIRONMENT VARIABLE GENERATION
# =============================================================================

# Generate base environment variables (common to all deployment types)
generate_base_env_vars() {
    cat << EOF
# =============================================================================
# Base Configuration Variables
# Generated by lib/config-management.sh v${CONFIG_MANAGEMENT_VERSION}
# Environment: ${ENVIRONMENT}
# Deployment Type: ${DEPLOYMENT_TYPE}
# Generated at: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# =============================================================================

# Global Configuration
ENVIRONMENT=${ENVIRONMENT}
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE}
AWS_REGION=$(get_global_config "region" "$DEFAULT_REGION")
STACK_NAME=$(get_global_config "stack_name" "GeuseMaker-${ENVIRONMENT}")
PROJECT_NAME=$(get_global_config "project_name" "GeuseMaker")

# Infrastructure Configuration
VPC_CIDR=$(get_infrastructure_config "networking.vpc_cidr" "10.0.0.0/16")
EFS_PERFORMANCE_MODE=$(get_infrastructure_config "storage.efs_performance_mode" "generalPurpose")
EFS_ENCRYPTION=$(get_infrastructure_config "storage.efs_encryption" "true")
BACKUP_RETENTION_DAYS=$(get_infrastructure_config "storage.backup_retention_days" "30")

# Auto Scaling Configuration
ASG_MIN_CAPACITY=$(get_infrastructure_config "auto_scaling.min_capacity" "1")
ASG_MAX_CAPACITY=$(get_infrastructure_config "auto_scaling.max_capacity" "3")
ASG_TARGET_UTILIZATION=$(get_infrastructure_config "auto_scaling.target_utilization" "70")

# Security Configuration
CONTAINER_SECURITY_ENABLED=$(get_security_config "container_security.run_as_non_root" "true")
NETWORK_SECURITY_STRICT=$(get_security_config "network_security.cors_strict_mode" "true")
SECRETS_MANAGER_ENABLED=$(get_security_config "secrets_management.use_aws_secrets_manager" "true")

# Monitoring Configuration
MONITORING_ENABLED=$(get_monitoring_config "metrics.enabled" "true")
LOG_LEVEL=$(get_monitoring_config "logging.level" "info")
LOG_FORMAT=$(get_monitoring_config "logging.format" "json")
METRICS_RETENTION_DAYS=$(get_monitoring_config "metrics.retention_days" "30")

# Cost Optimization Configuration
SPOT_INSTANCES_ENABLED=$(get_cost_config "spot_instances.enabled" "false")
SPOT_MAX_PRICE=$(get_cost_config "spot_instances.max_price" "1.00")
AUTO_SCALING_ENABLED=$(get_cost_config "auto_scaling.scale_down_enabled" "true")
IDLE_TIMEOUT_MINUTES=$(get_cost_config "auto_scaling.idle_timeout_minutes" "30")
EOF
}

# Generate application-specific environment variables
generate_app_env_vars() {
    cat << EOF

# =============================================================================
# Application Configuration Variables
# =============================================================================

# PostgreSQL Configuration
POSTGRES_DB=$(get_application_config "postgres" "config.database_name" "n8n")
POSTGRES_MAX_CONNECTIONS=$(get_application_config "postgres" "config.max_connections" "100")
POSTGRES_SHARED_BUFFERS=$(get_application_config "postgres" "config.shared_buffers" "256MB")
POSTGRES_EFFECTIVE_CACHE_SIZE=$(get_application_config "postgres" "config.effective_cache_size" "1GB")

# n8n Configuration
N8N_CORS_ENABLED=$(get_application_config "n8n" "config.cors_enable" "true")
N8N_CORS_ALLOWED_ORIGINS=$(get_application_config "n8n" "config.cors_allowed_origins" "*")
N8N_PAYLOAD_SIZE_MAX=$(get_application_config "n8n" "config.payload_size_max" "16")
N8N_METRICS=$(get_application_config "n8n" "config.metrics" "true")
N8N_LOG_LEVEL=$(get_application_config "n8n" "config.log_level" "info")

# Ollama Configuration
OLLAMA_HOST=0.0.0.0
OLLAMA_GPU_MEMORY_FRACTION=$(get_application_config "ollama" "resources.gpu_memory_fraction" "0.80")
OLLAMA_MAX_LOADED_MODELS=$(get_application_config "ollama" "config.max_loaded_models" "2")
OLLAMA_CONCURRENT_REQUESTS=$(get_application_config "ollama" "config.concurrent_requests" "4")

# Qdrant Configuration
QDRANT__SERVICE__HTTP_PORT=6333
QDRANT__SERVICE__GRPC_PORT=6334
QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS=$(get_application_config "qdrant" "config.max_search_threads" "4")
QDRANT__STORAGE__PERFORMANCE__MAX_OPTIMIZATION_THREADS=$(get_application_config "qdrant" "config.max_optimization_threads" "2")
QDRANT__STORAGE__WAL__WAL_CAPACITY_MB=$(get_application_config "qdrant" "config.wal_capacity_mb" "128")

# Crawl4AI Configuration
CRAWL4AI_RATE_LIMITING_ENABLED=$(get_application_config "crawl4ai" "config.rate_limiting_enabled" "true")
CRAWL4AI_DEFAULT_LIMIT=$(get_application_config "crawl4ai" "config.default_limit" "1000/minute")
CRAWL4AI_MAX_CONCURRENT_SESSIONS=$(get_application_config "crawl4ai" "config.max_concurrent_sessions" "2")
CRAWL4AI_BROWSER_POOL_SIZE=$(get_application_config "crawl4ai" "config.browser_pool_size" "1")
EOF
}

# Generate secrets placeholders (to be filled by deployment scripts)
generate_secrets_env_vars() {
    cat << EOF

# =============================================================================
# Secrets and Dynamic Variables
# These will be populated by deployment scripts from AWS Parameter Store/Secrets Manager
# =============================================================================

# Database Secrets
POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}

# n8n Secrets
N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_USER_MANAGEMENT_JWT_SECRET}

# API Keys
OPENAI_API_KEY=\${OPENAI_API_KEY}

# AWS Infrastructure (populated by deployment scripts)
EFS_DNS=\${EFS_DNS}
INSTANCE_ID=\${INSTANCE_ID}
INSTANCE_TYPE=\${INSTANCE_TYPE}

# Monitoring and Health Check URLs
WEBHOOK_URL=\${WEBHOOK_URL}
NOTIFICATION_WEBHOOK=\${NOTIFICATION_WEBHOOK}

# Default region for AWS services
AWS_DEFAULT_REGION=\${AWS_REGION}
EOF
}

# Generate complete environment file
generate_env_file() {
    local output_file="${1:-}"
    local env="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    
    if [[ -z "$output_file" ]]; then
        output_file="${PROJECT_ROOT}/.env.${env}"
    fi
    
    # Ensure configuration is loaded
    if [[ "$CONFIG_CACHE_LOADED" != "true" ]]; then
        load_config "$env" || return 1
    fi
    
    # Generate complete environment file
    {
        generate_base_env_vars
        generate_app_env_vars  
        generate_secrets_env_vars
    } > "$output_file"
    
    if declare -f success >/dev/null 2>&1; then
        success "Environment file generated: $output_file"
    else
        echo "Environment file generated: $output_file"
    fi
    
    return 0
}

# =============================================================================
# DOCKER COMPOSE INTEGRATION
# =============================================================================

# Generate Docker Compose environment section for a service
generate_docker_env_section() {
    local service="$1"
    
    case "$service" in
        postgres)
            cat << EOF
    environment:
      - POSTGRES_DB=\${POSTGRES_DB:-n8n}
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_MAX_CONNECTIONS=\${POSTGRES_MAX_CONNECTIONS:-100}
      - POSTGRES_SHARED_BUFFERS=\${POSTGRES_SHARED_BUFFERS:-256MB}
      - POSTGRES_EFFECTIVE_CACHE_SIZE=\${POSTGRES_EFFECTIVE_CACHE_SIZE:-1GB}
EOF
            ;;
        n8n)
            cat << EOF
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB:-n8n}
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_JWT_SECRET=\${N8N_USER_MANAGEMENT_JWT_SECRET}
      - N8N_CORS_ENABLED=\${N8N_CORS_ENABLED:-true}
      - N8N_CORS_ALLOWED_ORIGINS=\${N8N_CORS_ALLOWED_ORIGINS:-*}
      - N8N_PAYLOAD_SIZE_MAX=\${N8N_PAYLOAD_SIZE_MAX:-16}
      - N8N_METRICS=\${N8N_METRICS:-true}
      - N8N_LOG_LEVEL=\${N8N_LOG_LEVEL:-info}
EOF
            ;;
        ollama)
            cat << EOF
    environment:
      - OLLAMA_HOST=\${OLLAMA_HOST:-0.0.0.0}
      - OLLAMA_GPU_MEMORY_FRACTION=\${OLLAMA_GPU_MEMORY_FRACTION:-0.80}
      - OLLAMA_MAX_LOADED_MODELS=\${OLLAMA_MAX_LOADED_MODELS:-2}
      - OLLAMA_CONCURRENT_REQUESTS=\${OLLAMA_CONCURRENT_REQUESTS:-4}
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
EOF
            ;;
        qdrant)
            cat << EOF
    environment:
      - QDRANT__SERVICE__HTTP_PORT=\${QDRANT__SERVICE__HTTP_PORT:-6333}
      - QDRANT__SERVICE__GRPC_PORT=\${QDRANT__SERVICE__GRPC_PORT:-6334}
      - QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS=\${QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS:-4}
      - QDRANT__STORAGE__PERFORMANCE__MAX_OPTIMIZATION_THREADS=\${QDRANT__STORAGE__PERFORMANCE__MAX_OPTIMIZATION_THREADS:-2}
      - QDRANT__STORAGE__WAL__WAL_CAPACITY_MB=\${QDRANT__STORAGE__WAL__WAL_CAPACITY_MB:-128}
EOF
            ;;
        crawl4ai)
            cat << EOF
    environment:
      - CRAWL4AI_RATE_LIMITING_ENABLED=\${CRAWL4AI_RATE_LIMITING_ENABLED:-true}
      - CRAWL4AI_DEFAULT_LIMIT=\${CRAWL4AI_DEFAULT_LIMIT:-1000/minute}
      - CRAWL4AI_MAX_CONCURRENT_SESSIONS=\${CRAWL4AI_MAX_CONCURRENT_SESSIONS:-2}
      - CRAWL4AI_BROWSER_POOL_SIZE=\${CRAWL4AI_BROWSER_POOL_SIZE:-1}
      - OPENAI_API_KEY=\${OPENAI_API_KEY}
EOF
            ;;
        *)
            if declare -f warning >/dev/null 2>&1; then
                warning "Unknown service for Docker environment generation: $service"
            fi
            return 1
            ;;
    esac
}

# =============================================================================
# DEPLOYMENT TYPE SPECIFIC CONFIGURATION
# =============================================================================

# Apply deployment type specific overrides
apply_deployment_type_overrides() {
    local deployment_type="${DEPLOYMENT_TYPE:-$DEFAULT_DEPLOYMENT_TYPE}"
    
    case "$deployment_type" in
        spot)
            export SPOT_INSTANCES_ENABLED=true
            export SPOT_MAX_PRICE=$(get_cost_config "spot_instances.max_price" "2.00")
            export AUTO_SCALING_ENABLED=true
            ;;
        ondemand)
            export SPOT_INSTANCES_ENABLED=false
            export AUTO_SCALING_ENABLED=true
            ;;
        simple)  
            export SPOT_INSTANCES_ENABLED=false
            export AUTO_SCALING_ENABLED=false
            export ASG_MIN_CAPACITY=1
            export ASG_MAX_CAPACITY=1
            ;;
        *)
            if declare -f warning >/dev/null 2>&1; then
                warning "Unknown deployment type: $deployment_type"
            fi
            ;;
    esac
}

# =============================================================================
# HIGH-LEVEL CONFIGURATION FUNCTIONS
# =============================================================================

# Initialize configuration system
init_config() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    local deployment_type="${2:-$DEFAULT_DEPLOYMENT_TYPE}"
    
    # Check dependencies
    check_config_dependencies || return 1
    
    # Load configuration
    load_config "$env" "$deployment_type" || return 1
    
    # Apply deployment type overrides
    apply_deployment_type_overrides
    
    if declare -f success >/dev/null 2>&1; then
        success "Configuration system initialized: environment=$env, type=$deployment_type"
    fi
    
    return 0
}

# Generate all configuration files for an environment
generate_all_config_files() {
    local env="${1:-$DEFAULT_ENVIRONMENT}"
    local deployment_type="${2:-$DEFAULT_DEPLOYMENT_TYPE}"
    
    # Initialize configuration
    init_config "$env" "$deployment_type" || return 1
    
    # Generate environment file
    generate_env_file "${PROJECT_ROOT}/.env.${env}" || return 1
    
    if declare -f success >/dev/null 2>&1; then
        success "All configuration files generated for environment: $env"
    fi
    
    return 0
}

# Get configuration summary for display
get_config_summary() {
    local env="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    
    cat << EOF
Configuration Summary:
  Environment: $env
  Deployment Type: ${DEPLOYMENT_TYPE:-$DEFAULT_DEPLOYMENT_TYPE}
  AWS Region: $(get_global_config "region" "$DEFAULT_REGION")
  Stack Name: $(get_global_config "stack_name" "GeuseMaker-${env}")
  Project: $(get_global_config "project_name" "GeuseMaker")
  
Instance Configuration:
  Spot Instances: ${SPOT_INSTANCES_ENABLED:-false}
  Auto Scaling: ${AUTO_SCALING_ENABLED:-true}
  Min Capacity: ${ASG_MIN_CAPACITY:-1}
  Max Capacity: ${ASG_MAX_CAPACITY:-3}
  
Security Settings:
  Container Security: ${CONTAINER_SECURITY_ENABLED:-true}
  Secrets Manager: ${SECRETS_MANAGER_ENABLED:-true}
  Network Security: ${NETWORK_SECURITY_STRICT:-true}
EOF
}

# =============================================================================
# LIBRARY INITIALIZATION
# =============================================================================

# Auto-initialize if environment variables are set
if [[ -n "${AUTO_INIT_CONFIG:-}" && "${AUTO_INIT_CONFIG}" == "true" ]]; then
    init_config "${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}" "${DEPLOYMENT_TYPE:-$DEFAULT_DEPLOYMENT_TYPE}"
fi

# Export main functions for external use
export -f validate_environment validate_deployment_type validate_aws_region validate_stack_name
export -f load_config get_config_value get_global_config get_infrastructure_config 
export -f get_application_config get_security_config get_monitoring_config get_cost_config
export -f generate_env_file generate_docker_env_section init_config generate_all_config_files
export -f get_config_summary apply_deployment_type_overrides check_config_dependencies

if declare -f log >/dev/null 2>&1; then
    log "Configuration management library loaded (v${CONFIG_MANAGEMENT_VERSION})"
fi