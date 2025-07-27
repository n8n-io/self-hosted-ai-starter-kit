#!/bin/bash
# =============================================================================
# Configuration Manager for GeuseMaker
# Enhanced version using centralized configuration management system
# =============================================================================

set -euo pipefail

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
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

# Load the new centralized configuration management system with comprehensive error handling
CONFIG_MANAGEMENT_AVAILABLE=false
CONFIG_MANAGEMENT_ERROR=""

# Enhanced configuration management loading with better error handling
load_config_management_safely() {
    local lib_file="$LIB_DIR/config-management.sh"
    
    # Check if file exists and is readable
    if [[ ! -f "$lib_file" ]]; then
        CONFIG_MANAGEMENT_ERROR="Configuration management file not found"
        return 1
    fi
    
    if [[ ! -r "$lib_file" ]]; then
        CONFIG_MANAGEMENT_ERROR="Configuration management file not readable (permission denied)"
        # Try to fix permissions if we're root or have sudo
        if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
            log "Attempting to fix permissions for config management library..."
            chmod 644 "$lib_file" 2>/dev/null || true
            if [[ ! -r "$lib_file" ]]; then
                CONFIG_MANAGEMENT_ERROR="Cannot fix permissions for configuration management file"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    # Check syntax first in a safer way
    if ! bash -n "$lib_file" 2>/dev/null; then
        CONFIG_MANAGEMENT_ERROR="Configuration management script has syntax errors"
        return 1
    fi
    
    # Try to source in a subshell first to test for runtime errors
    if ! (set -e; source "$lib_file" >/dev/null 2>&1); then
        CONFIG_MANAGEMENT_ERROR="Configuration management script has runtime errors"
        return 1
    fi
    
    # Source it in current shell
    if ! source "$lib_file" 2>/dev/null; then
        CONFIG_MANAGEMENT_ERROR="Failed to source configuration management script"
        return 1
    fi
    
    # Verify required functions are available
    local required_functions="load_config get_config_value generate_env_file"
    local missing_functions=""
    
    for func in $required_functions; do
        if ! declare -f "$func" >/dev/null 2>&1; then
            missing_functions="$missing_functions $func"
        fi
    done
    
    if [[ -n "$missing_functions" ]]; then
        CONFIG_MANAGEMENT_ERROR="Missing required functions:$missing_functions"
        return 1
    fi
    
    return 0
}

if load_config_management_safely; then
    CONFIG_MANAGEMENT_AVAILABLE=true
    log "Centralized configuration management system loaded successfully"
else
    CONFIG_MANAGEMENT_AVAILABLE=false
    if [[ -n "$CONFIG_MANAGEMENT_ERROR" ]]; then
        warning "Enhanced configuration management unavailable: $CONFIG_MANAGEMENT_ERROR"
    else
        warning "Enhanced configuration management unavailable: unknown error"
    fi
    warning "Falling back to legacy mode with reduced functionality"
fi

# =============================================================================
# ENHANCED DEPENDENCY CHECKING AND PARAMETER STORE INTEGRATION
# =============================================================================

# Check and install missing tools with improved error handling and graceful fallback
check_and_install_required_tools() {
    log "Checking and installing required tools..."
    local missing_tools=()
    local optional_tools=()
    local critical_tools="bash grep sed awk"
    local enhanced_tools="yq jq python3"
    local all_tools="$critical_tools $enhanced_tools"
    
    # First check critical tools that must be available
    local critical_missing=()
    for tool in $critical_tools; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            critical_missing+=("$tool")
        fi
    done
    
    if [ ${#critical_missing[@]} -gt 0 ]; then
        error "Critical tools missing: ${critical_missing[*]}"
        error "Cannot continue without these basic tools"
        return 1
    fi
    
    # Check enhanced tools (these are optional for basic functionality)
    for tool in $enhanced_tools; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    # If enhanced tools are missing, try to install them (but don't fail if we can't)
    if [ ${#missing_tools[@]} -gt 0 ]; then
        warning "Enhanced tools missing: ${missing_tools[*]}"
        warning "Basic functionality will work, but some features may be limited"
        
        # Only try to install if we have permission and package manager
        local can_install=false
        local install_method=""
        
        if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
            if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v apt-get >/dev/null 2>&1; then
                can_install=true
                install_method="apt-get"
            elif [[ "$OSTYPE" == "darwin"* ]] && command -v brew >/dev/null 2>&1; then
                can_install=true
                install_method="brew"
            fi
        fi
        
        if [ "$can_install" = "true" ]; then
            log "Attempting to install missing tools via $install_method..."
            
            case "$install_method" in
                "apt-get")
                    if sudo apt-get update -qq 2>/dev/null; then
                        for tool in "${missing_tools[@]}"; do
                            case "$tool" in
                                "yq")
                                    install_yq_ubuntu || warning "Failed to install yq, will use fallback methods"
                                    ;;
                                "jq"|"python3")
                                    sudo apt-get install -y "$tool" 2>/dev/null || warning "Failed to install $tool"
                                    ;;
                            esac
                        done
                    else
                        warning "Could not update package manager, skipping automatic installation"
                    fi
                    ;;
                "brew")
                    for tool in "${missing_tools[@]}"; do
                        brew install "$tool" 2>/dev/null || warning "Failed to install $tool"
                    done
                    ;;
            esac
            
            # Re-check what's still missing
            local still_missing=()
            for tool in "${missing_tools[@]}"; do
                if ! command -v "$tool" >/dev/null 2>&1; then
                    still_missing+=("$tool")
                fi
            done
            
            if [ ${#still_missing[@]} -eq 0 ]; then
                success "All enhanced tools are now available"
            else
                warning "Some enhanced tools could not be installed: ${still_missing[*]}"
                warning "Will use fallback implementations where possible"
            fi
        else
            warning "Cannot install tools automatically (no package manager or permissions)"
            warning "Install manually: apt-get install yq jq python3 (Ubuntu) or brew install yq jq python3 (macOS)"
            warning "System will use fallback methods with reduced functionality"
        fi
    else
        success "All required and enhanced tools are available"
    fi
    
    # Log what's available for debugging
    local available_tools=""
    for tool in $all_tools; do
        if command -v "$tool" >/dev/null 2>&1; then
            available_tools="$available_tools $tool"
        fi
    done
    debug "Available tools:$available_tools"
    
    return 0
}

# Enhanced yq installation for Ubuntu
install_yq_ubuntu() {
    log "Installing yq YAML processor..."
    
    # Method 1: Try official repository
    if command -v apt-add-repository >/dev/null 2>&1; then
        if sudo apt-add-repository ppa:rmescandon/yq -y 2>/dev/null && \
           sudo apt-get update -qq 2>/dev/null && \
           sudo apt-get install -y yq 2>/dev/null; then
            success "yq installed via official repository"
            return 0
        fi
    fi
    
    # Method 2: Direct download from GitHub releases
    local yq_version
    yq_version=$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest | grep '"tag_name":' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/' 2>/dev/null)
    if [ -z "$yq_version" ]; then
        yq_version="v4.35.2"  # Fallback version
    fi
    
    local yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_linux_amd64"
    local temp_yq="/tmp/yq_temp"
    
    if curl -fsSL "$yq_url" -o "$temp_yq" && [ -s "$temp_yq" ]; then
        if file "$temp_yq" | grep -q "executable"; then
            sudo mv "$temp_yq" /usr/local/bin/yq
            sudo chmod +x /usr/local/bin/yq
            success "yq installed via direct download"
            return 0
        else
            rm -f "$temp_yq"
        fi
    fi
    
    # Method 3: Try pip installation
    if command -v pip3 >/dev/null 2>&1; then
        if pip3 install --user yq 2>/dev/null; then
            success "yq installed via pip3"
            return 0
        fi
    fi
    
    error "Failed to install yq via all methods"
    return 1
}

# Fetch environment variables from Parameter Store with improved error handling and defaults
fetch_parameter_store_variables() {
    local aws_region="${AWS_REGION:-us-east-1}"
    log "Fetching environment variables from Parameter Store (region: $aws_region)..."
    
    # Initialize default values for critical variables
    export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 32 2>/dev/null || echo 'default-postgres-password')}"
    export N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(openssl rand -base64 32 2>/dev/null || echo 'default-n8n-encryption-key')}"
    export N8N_USER_MANAGEMENT_JWT_SECRET="${N8N_USER_MANAGEMENT_JWT_SECRET:-$(openssl rand -base64 32 2>/dev/null || echo 'default-jwt-secret')}"
    export OPENAI_API_KEY="${OPENAI_API_KEY:-your-openai-api-key-here}"
    export WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:5678}"
    export EFS_DNS="${EFS_DNS:-}"
    export INSTANCE_ID="${INSTANCE_ID:-}"
    
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        warning "AWS CLI not available, using default environment variables"
        warning "Set AWS environment variables manually if needed"
        return 0
    fi
    
    # Test AWS credentials and permissions
    if ! aws sts get-caller-identity --region "$aws_region" >/dev/null 2>&1; then
        warning "AWS credentials not configured or invalid, using defaults"
        return 0
    fi
    
    # Check if we can access Parameter Store with a simple test
    if ! aws ssm describe-parameters --max-results 1 --region "$aws_region" >/dev/null 2>&1; then
        warning "Cannot access Parameter Store (permissions or service unavailable), using defaults"
        return 0
    fi
    
    # Fetch parameters with /aibuildkit prefix
    local parameters
    if ! parameters=$(aws ssm get-parameters-by-path \
        --path "/aibuildkit" \
        --recursive \
        --with-decryption \
        --query 'Parameters[].{Name:Name,Value:Value}' \
        --output json \
        --region "$aws_region" 2>/dev/null); then
        warning "Failed to fetch parameters from Parameter Store, using defaults"
        return 0
    fi
    
    if [ -z "$parameters" ] || [ "$parameters" = "[]" ] || [ "$parameters" = "null" ]; then
        warning "No parameters found in Parameter Store with /aibuildkit prefix"
        log "Using default values. To add parameters:"
        log "  aws ssm put-parameter --name '/aibuildkit/OPENAI_API_KEY' --value 'your-key' --type SecureString"
        log "  aws ssm put-parameter --name '/aibuildkit/POSTGRES_PASSWORD' --value 'your-password' --type SecureString"
        return 0
    fi
    
    # Parse and set environment variables with multiple fallback methods
    local param_count=0
    local processing_method=""
    
    # Try jq first (preferred)
    if command -v jq >/dev/null 2>&1; then
        processing_method="jq"
        while IFS= read -r param; do
            if [ -n "$param" ] && [ "$param" != "null" ]; then
                local name value
                name=$(echo "$param" | jq -r '.Name' 2>/dev/null | sed 's|^/aibuildkit/||' | sed 's|/|_|g' | sed 's|-|_|g' | tr '[:lower:]' '[:upper:]')
                value=$(echo "$param" | jq -r '.Value' 2>/dev/null)
                
                if [ -n "$name" ] && [ "$name" != "null" ] && [ -n "$value" ] && [ "$value" != "null" ]; then
                    export "$name=$value"
                    debug "Set $name from Parameter Store (via jq)"
                    param_count=$((param_count + 1))
                fi
            fi
        done <<< "$(echo "$parameters" | jq -c '.[]' 2>/dev/null || echo '')"
    # Fallback to python3 if jq not available
    elif command -v python3 >/dev/null 2>&1; then
        processing_method="python3"
        local python_output
        python_output=$(python3 -c "
import json
import sys
import os

try:
    data = json.loads('$parameters')
    for param in data:
        name = param.get('Name', '').replace('/aibuildkit/', '').replace('/', '_').replace('-', '_').upper()
        value = param.get('Value', '')
        if name and value:
            print(f'{name}={value}')
except Exception as e:
    sys.stderr.write(f'Error processing parameters: {e}\n')
" 2>/dev/null)
        
        if [ -n "$python_output" ]; then
            while IFS='=' read -r name value; do
                if [ -n "$name" ] && [ -n "$value" ]; then
                    export "$name=$value"
                    debug "Set $name from Parameter Store (via python3)"
                    param_count=$((param_count + 1))
                fi
            done <<< "$python_output"
        fi
    # Last resort: basic text processing
    else
        processing_method="text"
        warning "No JSON processor available, using basic text parsing"
        # Extract parameters using grep and sed (limited functionality)
        local param_lines
        param_lines=$(echo "$parameters" | grep -o '"Name":"[^"]*"' | sed 's/"Name":"//g' | sed 's/"//g')
        if [ -n "$param_lines" ]; then
            warning "Basic parameter extraction attempted, but values cannot be safely retrieved without JSON processor"
            warning "Please install jq or python3 for full Parameter Store integration"
        fi
    fi
    
    if [ $param_count -gt 0 ]; then
        success "Loaded $param_count environment variables from Parameter Store (method: $processing_method)"
    else
        warning "No valid parameters loaded from Parameter Store"
        warning "Using default values for all environment variables"
    fi
    
    # Log non-sensitive variable status for debugging
    local critical_vars="POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET OPENAI_API_KEY"
    for var in $critical_vars; do
        if [ -n "${!var:-}" ]; then
            debug "$var is set (length: ${#var} characters)"
        else
            warning "$var is not set or empty"
        fi
    done
}

# Fix file permissions for deployment scripts
fix_file_permissions() {
    local file="$1"
    if [ -f "$file" ]; then
        # Make readable by all, writable by owner
        chmod 644 "$file" 2>/dev/null || true
        # If running as root, try to change ownership to ubuntu
        if [ "$EUID" -eq 0 ] && id ubuntu >/dev/null 2>&1; then
            chown ubuntu:ubuntu "$file" 2>/dev/null || true
        fi
        debug "Fixed permissions for $file"
    fi
}

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
        export STACK_NAME=$(grep -A1 'stack_name:' "$config_file" | tail -n1 | sed 's/.*: //' | tr -d '"'\''\' | head -c 128)
        export AWS_REGION=$(grep -A1 'region:' "$config_file" | tail -n1 | sed 's/.*: //' | tr -d '"'\''\' | head -c 32)
        export PROJECT_NAME=$(grep -A1 'project_name:' "$config_file" | tail -n1 | sed 's/.*: //' | tr -d '"'\''\' | head -c 64)
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
    fix_file_permissions "$output_file"
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
    fix_file_permissions "$output_file"
    return 0
}

# =============================================================================
# ENHANCED FUNCTIONS (using new centralized system)
# =============================================================================

# Enhanced configuration loading with comprehensive fallback and error handling
enhanced_load_environment_config() {
    local env="$1"
    
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
        log "Using enhanced configuration management system"
        
        # Check if the load_config function exists (correct function name)
        if declare -f load_config >/dev/null 2>&1; then
            # Use the new centralized system
            local config_file="$CONFIG_DIR/environments/${env}.yml"
            if [ -f "$config_file" ]; then
                # Try to load configuration with proper error handling
                local load_result
                if load_result=$(load_config "$env" "simple" 2>&1); then
                    success "Enhanced configuration loaded for $env environment"
                    return 0
                else
                    warning "Enhanced configuration loading failed: $load_result"
                    warning "Falling back to legacy mode"
                    return legacy_load_environment_config "$env"
                fi
            else
                warning "Configuration file not found: $config_file"
                warning "Falling back to legacy mode"
                return legacy_load_environment_config "$env"
            fi
        else
            warning "Enhanced configuration functions not available (load_config not found)"
            warning "Available functions: $(declare -F | grep -E '(load_|config)' | awk '{print $3}' | tr '\n' ' ' || echo 'none')"
            return legacy_load_environment_config "$env"
        fi
    else
        log "Using legacy configuration management system"
        return legacy_load_environment_config "$env"
    fi
}

# Enhanced Docker Compose override generation with improved error handling
enhanced_generate_docker_compose_override() {
    local env="$1"
    local output_file="$PROJECT_ROOT/docker-compose.override.yml"
    
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
        log "Using enhanced Docker Compose generation"
        
        # Check if the generate_docker_compose function exists
        if declare -f generate_docker_compose >/dev/null 2>&1; then
            local config_file="$CONFIG_DIR/environments/${env}.yml"
            if [ -f "$config_file" ]; then
                # Try enhanced generation with proper error capture
                local gen_result
                if gen_result=$(generate_docker_compose "$config_file" "$env" "$output_file" 2>&1); then
                    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                        success "Enhanced Docker Compose override generated: $output_file"
                        return 0
                    else
                        warning "Enhanced generation succeeded but output file is empty or missing"
                    fi
                else
                    warning "Enhanced Docker Compose generation failed: $gen_result"
                fi
            else
                warning "Configuration file not found for enhanced generation: $config_file"
            fi
            warning "Falling back to legacy mode"
            return legacy_generate_docker_compose_override "$env"
        else
            warning "Enhanced Docker Compose functions not available (generate_docker_compose not found)"
            return legacy_generate_docker_compose_override "$env"
        fi
    else
        log "Using legacy Docker Compose generation"
        return legacy_generate_docker_compose_override "$env"
    fi
}

# Enhanced environment file generation with robust error handling
enhanced_generate_env_file() {
    local env="$1"
    local output_file="$PROJECT_ROOT/.env.${env}"
    
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
        log "Using enhanced environment file generation"
        
        # Check if the generate_environment_file function exists
        if declare -f generate_environment_file >/dev/null 2>&1; then
            local config_file="$CONFIG_DIR/environments/${env}.yml"
            if [ -f "$config_file" ]; then
                # Try enhanced generation with error capture
                local env_result
                if env_result=$(generate_environment_file "$config_file" "$env" "$output_file" 2>&1); then
                    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                        success "Enhanced environment file generated: $output_file"
                        return 0
                    else
                        warning "Enhanced generation succeeded but output file is empty or missing"
                    fi
                else
                    warning "Enhanced environment file generation failed: $env_result"
                fi
            else
                warning "Configuration file not found for enhanced generation: $config_file"
            fi
            warning "Falling back to legacy mode"
            return legacy_generate_env_file "$env"
        elif declare -f generate_env_file >/dev/null 2>&1; then
            # Try the alternative function name
            log "Using generate_env_file function instead"
            local config_file="$CONFIG_DIR/environments/${env}.yml"
            if [ -f "$config_file" ]; then
                # Ensure configuration is loaded first
                if load_config "$env" "simple" 2>/dev/null; then
                    if generate_env_file "$output_file" 2>/dev/null; then
                        success "Enhanced environment file generated: $output_file"
                        return 0
                    fi
                fi
            fi
            warning "Alternative enhanced generation failed, falling back to legacy mode"
            return legacy_generate_env_file "$env"
        else
            warning "Enhanced environment file functions not available"
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
    
    # Check and install required tools first
    check_and_install_required_tools
    
    # Fetch environment variables from Parameter Store
    fetch_parameter_store_variables
    
    # Validate environment with improved error handling
    if ! validate_environment "$env" 2>/dev/null; then
        error "Invalid environment: $env"
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
    
    # Generate Docker image overrides if image version management is available
    if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ] && declare -f generate_docker_image_overrides >/dev/null 2>&1; then
        generate_docker_image_overrides
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
    images <env>       Generate only Docker image overrides
    validate-images    Validate image version configuration
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
    $0 images production       # Generate Docker image overrides for production
    $0 validate-images         # Validate image version configuration

FEATURES:
    ✅ Enhanced configuration management system (when available)
    ✅ Centralized image version management with environment strategies
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
    docker-compose.images.yml     Environment-specific Docker image overrides
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
        "images")
            if [[ -z "$environment" ]]; then
                error "Environment not specified"
                show_help
                exit 1
            fi
            if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
                enhanced_load_environment_config "$environment" && generate_docker_image_overrides
            else
                error "Image management requires enhanced configuration system"
                exit 1
            fi
            ;;
        "validate-images")
            if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ] && declare -f validate_image_versions >/dev/null 2>&1; then
                validate_image_versions
            else
                error "Image validation requires enhanced configuration system"
                exit 1
            fi
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
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi