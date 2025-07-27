#!/bin/bash
# =============================================================================
# Variable Management Library 
# Unified environment variable initialization and management system
# =============================================================================
# This library provides a robust, unified system for setting and managing
# environment variables across all deployment scripts and instances.
# 
# Key Features:
# - Parameter Store integration with multiple fallback methods
# - Secure default generation for critical variables
# - Comprehensive validation and error handling
# - Bash 3.x/4.x compatibility (macOS and Linux)
# - Docker Compose environment file generation
# =============================================================================

# Prevent multiple sourcing
if [[ "${VARIABLE_MANAGEMENT_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly VARIABLE_MANAGEMENT_LIB_LOADED=true

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly VARIABLE_MANAGEMENT_VERSION="1.0.0"
readonly VAR_CACHE_FILE="/tmp/geuse-variable-cache"
readonly VAR_ENV_FILE="/tmp/geuse-variables.env"
readonly VAR_FALLBACK_FILE="/tmp/geuse-fallback-variables.env"

# Parameter Store paths
readonly PARAM_STORE_PREFIX="/aibuildkit"
readonly PARAM_POSTGRES_PASSWORD="${PARAM_STORE_PREFIX}/POSTGRES_PASSWORD"
readonly PARAM_N8N_ENCRYPTION_KEY="${PARAM_STORE_PREFIX}/n8n/ENCRYPTION_KEY"
readonly PARAM_N8N_JWT_SECRET="${PARAM_STORE_PREFIX}/n8n/USER_MANAGEMENT_JWT_SECRET"
readonly PARAM_OPENAI_API_KEY="${PARAM_STORE_PREFIX}/OPENAI_API_KEY"
readonly PARAM_WEBHOOK_URL="${PARAM_STORE_PREFIX}/WEBHOOK_URL"
readonly PARAM_N8N_CORS_ENABLE="${PARAM_STORE_PREFIX}/n8n/CORS_ENABLE"
readonly PARAM_N8N_CORS_ORIGINS="${PARAM_STORE_PREFIX}/n8n/CORS_ALLOWED_ORIGINS"

# Critical variables that must be set
readonly CRITICAL_VARIABLES="POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET"

# Optional variables with fallbacks
readonly OPTIONAL_VARIABLES="OPENAI_API_KEY WEBHOOK_URL N8N_CORS_ENABLE N8N_CORS_ALLOWED_ORIGINS"

# AWS regions to try for Parameter Store access
readonly AWS_REGIONS="us-east-1 us-west-2 eu-west-1"

# =============================================================================
# LOGGING AND ERROR HANDLING
# =============================================================================

# Internal logging function (fallback if main logging not available)
var_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        ERROR)
            if declare -f error >/dev/null 2>&1; then
                error "$message"
            else
                echo "[$timestamp] ERROR: $message" >&2
            fi
            ;;
        WARN|WARNING)
            if declare -f warning >/dev/null 2>&1; then
                warning "$message"
            else
                echo "[$timestamp] WARNING: $message" >&2
            fi
            ;;
        SUCCESS)
            if declare -f success >/dev/null 2>&1; then
                success "$message"
            else
                echo "[$timestamp] SUCCESS: $message"
            fi
            ;;
        *)
            if declare -f log >/dev/null 2>&1; then
                log "$message"
            else
                echo "[$timestamp] INFO: $message"
            fi
            ;;
    esac
}

# =============================================================================
# SECURE VALUE GENERATION
# =============================================================================

# Generate secure random string (bash 3.x/4.x compatible)
generate_secure_random() {
    local length="${1:-32}"
    local charset="${2:-hex}"
    
    case "$charset" in
        hex)
            if command -v openssl >/dev/null 2>&1; then
                openssl rand -hex "$length" 2>/dev/null
            elif command -v dd >/dev/null 2>&1 && command -v xxd >/dev/null 2>&1; then
                dd if=/dev/urandom bs=1 count="$length" 2>/dev/null | xxd -p | tr -d '\n'
            elif [ -r /dev/urandom ]; then
                head -c "$length" /dev/urandom | od -An -tx1 | tr -d ' \n'
            else
                # Fallback using date and process ID
                echo "$(date +%s)$(echo $$)" | sha256sum 2>/dev/null | cut -c1-"$((length*2))" || echo "fallback$(date +%s)$(echo $$)"
            fi
            ;;
        base64)
            if command -v openssl >/dev/null 2>&1; then
                openssl rand -base64 "$length" 2>/dev/null | tr -d '\n'
            elif [ -r /dev/urandom ] && command -v base64 >/dev/null 2>&1; then
                head -c "$length" /dev/urandom | base64 | tr -d '\n'
            else
                # Fallback
                echo "$(date +%s)$(echo $$)" | base64 2>/dev/null | tr -d '\n' | head -c "$length"
            fi
            ;;
        *)
            var_log ERROR "Unknown charset for random generation: $charset"
            return 1
            ;;
    esac
}

# Generate secure password
generate_secure_password() {
    local password
    password=$(generate_secure_random 32 base64)
    if [ -n "$password" ] && [ ${#password} -ge 16 ]; then
        echo "$password"
    else
        # Emergency fallback
        echo "secure_$(date +%s)_$(echo $$ | tail -c 6)"
    fi
}

# Generate encryption key
generate_encryption_key() {
    local key
    key=$(generate_secure_random 32 hex)
    if [ -n "$key" ] && [ ${#key} -ge 32 ]; then
        echo "$key"
    else
        # Emergency fallback
        echo "$(date +%s | sha256sum | cut -c1-64)"
    fi
}

# Generate JWT secret
generate_jwt_secret() {
    generate_secure_password
}

# =============================================================================
# AWS PARAMETER STORE INTEGRATION
# =============================================================================

# Check if AWS CLI is available and configured
check_aws_availability() {
    if ! command -v aws >/dev/null 2>&1; then
        var_log WARN "AWS CLI not available"
        return 1
    fi
    
    # Check for AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        var_log WARN "AWS credentials not configured or expired"
        return 1
    fi
    
    return 0
}

# Get parameter from AWS Parameter Store with retries and multiple regions
get_parameter_store_value() {
    local param_name="$1"
    local default_value="${2:-}"
    local param_type="${3:-String}"
    local current_region="${AWS_REGION:-us-east-1}"
    
    if ! check_aws_availability; then
        echo "$default_value"
        return 1
    fi
    
    # Try current region first
    local regions_to_try="$current_region"
    
    # Add other common regions if current region fails
    for region in $AWS_REGIONS; do
        if [ "$region" != "$current_region" ]; then
            regions_to_try="$regions_to_try $region"
        fi
    done
    
    for region in $regions_to_try; do
        var_log INFO "Trying to get parameter $param_name from region $region"
        
        local value
        if [ "$param_type" = "SecureString" ]; then
            value=$(aws ssm get-parameter --name "$param_name" --with-decryption --region "$region" --query 'Parameter.Value' --output text 2>/dev/null)
        else
            value=$(aws ssm get-parameter --name "$param_name" --region "$region" --query 'Parameter.Value' --output text 2>/dev/null)
        fi
        
        if [ $? -eq 0 ] && [ -n "$value" ] && [ "$value" != "None" ] && [ "$value" != "null" ]; then
            var_log SUCCESS "Retrieved parameter $param_name from region $region"
            echo "$value"
            return 0
        else
            var_log WARN "Failed to get parameter $param_name from region $region"
        fi
        
        # Brief pause between regions to avoid rate limiting
        sleep 1
    done
    
    var_log WARN "Could not retrieve parameter $param_name from any region, using default"
    echo "$default_value"
    return 1
}

# Batch get parameters from Parameter Store (more efficient)
get_parameters_batch() {
    local param_names="$1"
    local region="${AWS_REGION:-us-east-1}"
    
    if ! check_aws_availability; then
        return 1
    fi
    
    # Convert space-separated names to proper format for AWS CLI
    local param_names_array=""
    for name in $param_names; do
        if [ -z "$param_names_array" ]; then
            param_names_array="\"$name\""
        else
            param_names_array="$param_names_array,\"$name\""
        fi
    done
    
    var_log INFO "Batch retrieving parameters from region $region"
    
    # Get parameters in batch
    local result
    result=$(aws ssm get-parameters --names "[$param_names_array]" --with-decryption --region "$region" --output json 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        var_log SUCCESS "Successfully retrieved batch parameters from region $region"
        echo "$result"
        return 0
    else
        var_log WARN "Batch parameter retrieval failed from region $region"
        return 1
    fi
}

# Extract parameter value from batch result
extract_parameter_from_batch() {
    local batch_result="$1"
    local param_name="$2"
    local default_value="${3:-}"
    
    if [ -z "$batch_result" ]; then
        echo "$default_value"
        return 1
    fi
    
    # Extract value using multiple methods for compatibility
    local value=""
    
    # Try jq first (most reliable)
    if command -v jq >/dev/null 2>&1; then
        value=$(echo "$batch_result" | jq -r ".Parameters[] | select(.Name==\"$param_name\") | .Value" 2>/dev/null)
    fi
    
    # Fallback to grep/sed for basic extraction
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        value=$(echo "$batch_result" | grep -A 3 "\"Name\": \"$param_name\"" | grep '"Value":' | sed 's/.*"Value": *"\([^"]*\)".*/\1/' | head -n1)
    fi
    
    if [ -n "$value" ] && [ "$value" != "null" ] && [ "$value" != "" ]; then
        echo "$value"
        return 0
    else
        echo "$default_value"
        return 1
    fi
}

# =============================================================================
# VARIABLE INITIALIZATION AND MANAGEMENT
# =============================================================================

# Initialize critical variables with secure defaults
init_critical_variables() {
    var_log INFO "Initializing critical variables with secure defaults"
    
    # Generate secure defaults for critical variables
    export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(generate_secure_password)}"
    export N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(generate_encryption_key)}"
    export N8N_USER_MANAGEMENT_JWT_SECRET="${N8N_USER_MANAGEMENT_JWT_SECRET:-$(generate_jwt_secret)}"
    
    var_log SUCCESS "Critical variables initialized with secure defaults"
}

# Initialize optional variables with reasonable defaults
init_optional_variables() {
    var_log INFO "Initializing optional variables with defaults"
    
    # Set reasonable defaults for optional variables
    export OPENAI_API_KEY="${OPENAI_API_KEY:-}"
    export WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:5678}"
    export N8N_CORS_ENABLE="${N8N_CORS_ENABLE:-true}"
    export N8N_CORS_ALLOWED_ORIGINS="${N8N_CORS_ALLOWED_ORIGINS:-*}"
    export N8N_BASIC_AUTH_ACTIVE="${N8N_BASIC_AUTH_ACTIVE:-true}"
    export N8N_BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER:-admin}"
    export N8N_BASIC_AUTH_PASSWORD="${N8N_BASIC_AUTH_PASSWORD:-$(generate_secure_password)}"
    
    # Database configuration
    export POSTGRES_DB="${POSTGRES_DB:-n8n}"
    export POSTGRES_USER="${POSTGRES_USER:-n8n}"
    
    # Service configuration
    export ENABLE_METRICS="${ENABLE_METRICS:-true}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"
    
    var_log SUCCESS "Optional variables initialized with defaults"
}

# Load variables from Parameter Store with fallbacks
load_variables_from_parameter_store() {
    var_log INFO "Loading variables from AWS Parameter Store"
    
    if ! check_aws_availability; then
        var_log WARN "AWS not available, using local defaults"
        return 1
    fi
    
    # Try batch retrieval first (more efficient)
    local all_params="$PARAM_POSTGRES_PASSWORD $PARAM_N8N_ENCRYPTION_KEY $PARAM_N8N_JWT_SECRET $PARAM_OPENAI_API_KEY $PARAM_WEBHOOK_URL $PARAM_N8N_CORS_ENABLE $PARAM_N8N_CORS_ORIGINS"
    
    local batch_result
    batch_result=$(get_parameters_batch "$all_params")
    
    if [ $? -eq 0 ] && [ -n "$batch_result" ]; then
        var_log INFO "Using batch parameter retrieval"
        
        # Extract values from batch result
        local postgres_password
        local n8n_encryption_key
        local n8n_jwt_secret
        local openai_api_key
        local webhook_url
        local n8n_cors_enable
        local n8n_cors_origins
        
        postgres_password=$(extract_parameter_from_batch "$batch_result" "$PARAM_POSTGRES_PASSWORD" "$POSTGRES_PASSWORD")
        n8n_encryption_key=$(extract_parameter_from_batch "$batch_result" "$PARAM_N8N_ENCRYPTION_KEY" "$N8N_ENCRYPTION_KEY")
        n8n_jwt_secret=$(extract_parameter_from_batch "$batch_result" "$PARAM_N8N_JWT_SECRET" "$N8N_USER_MANAGEMENT_JWT_SECRET")
        openai_api_key=$(extract_parameter_from_batch "$batch_result" "$PARAM_OPENAI_API_KEY" "$OPENAI_API_KEY")
        webhook_url=$(extract_parameter_from_batch "$batch_result" "$PARAM_WEBHOOK_URL" "$WEBHOOK_URL")
        n8n_cors_enable=$(extract_parameter_from_batch "$batch_result" "$PARAM_N8N_CORS_ENABLE" "$N8N_CORS_ENABLE")
        n8n_cors_origins=$(extract_parameter_from_batch "$batch_result" "$PARAM_N8N_CORS_ORIGINS" "$N8N_CORS_ALLOWED_ORIGINS")
        
        # Update variables only if we got valid values
        if [ -n "$postgres_password" ]; then export POSTGRES_PASSWORD="$postgres_password"; fi
        if [ -n "$n8n_encryption_key" ]; then export N8N_ENCRYPTION_KEY="$n8n_encryption_key"; fi
        if [ -n "$n8n_jwt_secret" ]; then export N8N_USER_MANAGEMENT_JWT_SECRET="$n8n_jwt_secret"; fi
        if [ -n "$openai_api_key" ]; then export OPENAI_API_KEY="$openai_api_key"; fi
        if [ -n "$webhook_url" ]; then export WEBHOOK_URL="$webhook_url"; fi
        if [ -n "$n8n_cors_enable" ]; then export N8N_CORS_ENABLE="$n8n_cors_enable"; fi
        if [ -n "$n8n_cors_origins" ]; then export N8N_CORS_ALLOWED_ORIGINS="$n8n_cors_origins"; fi
        
        var_log SUCCESS "Variables loaded from Parameter Store via batch retrieval"
        return 0
    else
        var_log WARN "Batch retrieval failed, trying individual parameter requests"
        
        # Fallback to individual parameter retrieval
        local loaded_count=0
        
        # Critical parameters
        local postgres_password
        postgres_password=$(get_parameter_store_value "$PARAM_POSTGRES_PASSWORD" "$POSTGRES_PASSWORD" "SecureString")
        if [ $? -eq 0 ]; then
            export POSTGRES_PASSWORD="$postgres_password"
            loaded_count=$((loaded_count + 1))
        fi
        
        local n8n_encryption_key
        n8n_encryption_key=$(get_parameter_store_value "$PARAM_N8N_ENCRYPTION_KEY" "$N8N_ENCRYPTION_KEY" "SecureString")
        if [ $? -eq 0 ]; then
            export N8N_ENCRYPTION_KEY="$n8n_encryption_key"
            loaded_count=$((loaded_count + 1))
        fi
        
        local n8n_jwt_secret
        n8n_jwt_secret=$(get_parameter_store_value "$PARAM_N8N_JWT_SECRET" "$N8N_USER_MANAGEMENT_JWT_SECRET" "SecureString")
        if [ $? -eq 0 ]; then
            export N8N_USER_MANAGEMENT_JWT_SECRET="$n8n_jwt_secret"
            loaded_count=$((loaded_count + 1))
        fi
        
        # Optional parameters
        local openai_api_key
        openai_api_key=$(get_parameter_store_value "$PARAM_OPENAI_API_KEY" "$OPENAI_API_KEY" "SecureString")
        if [ $? -eq 0 ]; then
            export OPENAI_API_KEY="$openai_api_key"
            loaded_count=$((loaded_count + 1))
        fi
        
        local webhook_url
        webhook_url=$(get_parameter_store_value "$PARAM_WEBHOOK_URL" "$WEBHOOK_URL" "String")
        if [ $? -eq 0 ]; then
            export WEBHOOK_URL="$webhook_url"
            loaded_count=$((loaded_count + 1))
        fi
        
        if [ $loaded_count -gt 0 ]; then
            var_log SUCCESS "Loaded $loaded_count parameters from Parameter Store"
            return 0
        else
            var_log WARN "Could not load any parameters from Parameter Store"
            return 1
        fi
    fi
}

# Load variables from environment file
load_variables_from_file() {
    local env_file="$1"
    
    if [ ! -f "$env_file" ]; then
        var_log WARN "Environment file not found: $env_file"
        return 1
    fi
    
    var_log INFO "Loading variables from file: $env_file"
    
    # Source the file safely
    if set -a && source "$env_file" && set +a; then
        var_log SUCCESS "Variables loaded from file: $env_file"
        return 0
    else
        var_log ERROR "Failed to load variables from file: $env_file"
        return 1
    fi
}

# Save current variables to cache file
save_variables_to_cache() {
    local cache_file="${1:-$VAR_CACHE_FILE}"
    
    var_log INFO "Saving variables to cache: $cache_file"
    
    cat > "$cache_file" << EOF
# GeuseMaker Variable Cache
# Generated: $(date)
# Version: $VARIABLE_MANAGEMENT_VERSION

# Critical Variables
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET

# Optional Variables
OPENAI_API_KEY=$OPENAI_API_KEY
WEBHOOK_URL=$WEBHOOK_URL
N8N_CORS_ENABLE=$N8N_CORS_ENABLE
N8N_CORS_ALLOWED_ORIGINS=$N8N_CORS_ALLOWED_ORIGINS
N8N_BASIC_AUTH_ACTIVE=$N8N_BASIC_AUTH_ACTIVE
N8N_BASIC_AUTH_USER=$N8N_BASIC_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_BASIC_AUTH_PASSWORD

# Database Configuration
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER

# Service Configuration
ENABLE_METRICS=$ENABLE_METRICS
LOG_LEVEL=$LOG_LEVEL

# Infrastructure Variables
AWS_REGION=${AWS_REGION:-us-east-1}
STACK_NAME=${STACK_NAME:-GeuseMaker}
ENVIRONMENT=${ENVIRONMENT:-development}
EFS_DNS=${EFS_DNS:-}
INSTANCE_ID=${INSTANCE_ID:-}
INSTANCE_TYPE=${INSTANCE_TYPE:-}
EOF
    
    chmod 600 "$cache_file"
    var_log SUCCESS "Variables saved to cache: $cache_file"
}

# =============================================================================
# VARIABLE VALIDATION
# =============================================================================

# Validate that critical variables are set and not empty (bash 3.x compatible)
validate_critical_variables() {
    var_log INFO "Validating critical variables"
    
    local validation_errors=""
    local error_count=0
    
    # Check critical variables
    for var in $CRITICAL_VARIABLES; do
        local value
        eval "value=\$$var"
        
        if [ -z "$value" ]; then
            validation_errors="$validation_errors\n$var is not set or empty"
            error_count=$((error_count + 1))
        elif [ ${#value} -lt 8 ]; then
            validation_errors="$validation_errors\n$var is too short (minimum 8 characters)"
            error_count=$((error_count + 1))
        fi
    done
    
    # Check for common insecure values
    case "$POSTGRES_PASSWORD" in
        password|postgres)
            validation_errors="$validation_errors\nPOSTGRES_PASSWORD uses a common insecure value"
            error_count=$((error_count + 1))
            ;;
    esac
    
    case "$N8N_ENCRYPTION_KEY" in
        test)
            validation_errors="$validation_errors\nN8N_ENCRYPTION_KEY is insecure or too short"
            error_count=$((error_count + 1))
            ;;
        *)
            if [ ${#N8N_ENCRYPTION_KEY} -lt 32 ]; then
                validation_errors="$validation_errors\nN8N_ENCRYPTION_KEY is insecure or too short"
                error_count=$((error_count + 1))
            fi
            ;;
    esac
    
    # Report validation results
    if [ $error_count -eq 0 ]; then
        var_log SUCCESS "All critical variables are valid"
        return 0
    else
        var_log ERROR "Critical variable validation failed:"
        echo -e "$validation_errors" | while IFS= read -r error; do
            if [ -n "$error" ]; then
                var_log ERROR "  - $error"
            fi
        done
        return 1
    fi
}

# Validate optional variables (bash 3.x compatible)
validate_optional_variables() {
    var_log INFO "Validating optional variables"
    
    local validation_warnings=""
    
    # Check API keys format
    if [ -n "$OPENAI_API_KEY" ]; then
        case "$OPENAI_API_KEY" in
            sk-*)
                # Valid OpenAI API key format
                ;;
            *)
                validation_warnings="$validation_warnings\nOPENAI_API_KEY does not match expected format"
                ;;
        esac
    else
        validation_warnings="$validation_warnings\nOPENAI_API_KEY is not set - AI features may not work"
    fi
    
    # Check webhook URL format
    if [ -n "$WEBHOOK_URL" ]; then
        case "$WEBHOOK_URL" in
            http://*|https://*)
                # Valid URL format
                ;;
            *)
                validation_warnings="$validation_warnings\nWEBHOOK_URL does not appear to be a valid URL"
                ;;
        esac
    fi
    
    # Report warnings
    if [ -n "$validation_warnings" ]; then
        echo -e "$validation_warnings" | while IFS= read -r warning; do
            if [ -n "$warning" ]; then
                var_log WARN "$warning"
            fi
        done
    fi
    
    var_log SUCCESS "Optional variable validation completed"
    return 0
}

# =============================================================================
# DOCKER COMPOSE ENVIRONMENT FILE GENERATION
# =============================================================================

# Generate Docker Compose environment file
generate_docker_env_file() {
    local output_file="${1:-$VAR_ENV_FILE}"
    local include_comments="${2:-true}"
    
    var_log INFO "Generating Docker Compose environment file: $output_file"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    
    # Backup existing file
    if [ -f "$output_file" ]; then
        local backup_file="${output_file}.backup.$(date +%s)"
        cp "$output_file" "$backup_file"
        var_log INFO "Backed up existing environment file to: $backup_file"
    fi
    
    cat > "$output_file" << EOF
$([ "$include_comments" = "true" ] && cat << 'COMMENTS'
# =============================================================================
# GeuseMaker Docker Compose Environment File
# Generated by Variable Management System v$VARIABLE_MANAGEMENT_VERSION
# Generated: $(date)
# =============================================================================
# This file contains all environment variables needed for Docker Compose
# deployment. All sensitive values are securely generated or loaded from
# AWS Parameter Store.
# =============================================================================

COMMENTS
)
# Infrastructure Configuration
STACK_NAME=${STACK_NAME:-GeuseMaker}
ENVIRONMENT=${ENVIRONMENT:-development}
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_DEFAULT_REGION=${AWS_REGION:-us-east-1}
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.gpu-optimized.yml}

# Instance Information
INSTANCE_ID=${INSTANCE_ID:-}
INSTANCE_TYPE=${INSTANCE_TYPE:-}
AVAILABILITY_ZONE=${AVAILABILITY_ZONE:-}
PUBLIC_IP=${PUBLIC_IP:-}
PRIVATE_IP=${PRIVATE_IP:-}

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

# API Keys and External Services
OPENAI_API_KEY=$OPENAI_API_KEY

# Service URLs and Configuration
WEBHOOK_URL=$WEBHOOK_URL
ENABLE_METRICS=$ENABLE_METRICS
LOG_LEVEL=$LOG_LEVEL

# EFS Configuration (if available)
EFS_DNS=${EFS_DNS:-}

# Generation metadata
VAR_GENERATION_TIME=$(date)
VAR_GENERATION_METHOD=unified
VAR_GENERATION_VERSION=$VARIABLE_MANAGEMENT_VERSION
EOF
    
    # Set secure permissions
    chmod 600 "$output_file"
    chown ubuntu:ubuntu "$output_file" 2>/dev/null || true
    
    var_log SUCCESS "Docker environment file generated: $output_file"
}

# =============================================================================
# HIGH-LEVEL INITIALIZATION FUNCTIONS
# =============================================================================

# Initialize all variables with comprehensive fallback strategy
init_all_variables() {
    local force_refresh="${1:-false}"
    local cache_file="${2:-$VAR_CACHE_FILE}"
    
    var_log INFO "Initializing all variables (force_refresh=$force_refresh)"
    
    # Step 1: Initialize infrastructure variables (EC2 metadata)
    init_infrastructure_variables
    
    # Step 2: Initialize with secure defaults
    init_critical_variables
    init_optional_variables
    
    # Step 3: Try to load from cache if not forcing refresh
    if [ "$force_refresh" != "true" ] && [ -f "$cache_file" ]; then
        var_log INFO "Attempting to load variables from cache"
        if load_variables_from_file "$cache_file"; then
            var_log INFO "Variables loaded from cache, skipping Parameter Store"
        else
            var_log WARN "Cache load failed, proceeding to Parameter Store"
            force_refresh="true"
        fi
    fi
    
    # Step 4: Try to load from Parameter Store (if cache failed or force refresh)
    if [ "$force_refresh" = "true" ] || [ ! -f "$cache_file" ]; then
        var_log INFO "Loading variables from Parameter Store"
        if load_variables_from_parameter_store; then
            var_log INFO "Variables loaded from Parameter Store"
            # Save to cache for future use
            save_variables_to_cache "$cache_file"
        else
            var_log WARN "Parameter Store load failed, using defaults"
            # Save defaults to cache
            save_variables_to_cache "$cache_file"
        fi
    fi
    
    # Step 5: Validate all variables
    if ! validate_critical_variables; then
        var_log ERROR "Critical variable validation failed"
        return 1
    fi
    
    validate_optional_variables
    
    # Step 6: Generate Docker environment file
    generate_docker_env_file
    
    var_log SUCCESS "Variable initialization completed successfully"
    return 0
}

# Initialize infrastructure variables from EC2 metadata
init_infrastructure_variables() {
    var_log INFO "Initializing infrastructure variables from EC2 metadata"
    
    # Function to get EC2 metadata with timeout
    get_ec2_metadata() {
        local path="$1"
        local default="${2:-}"
        local timeout="${3:-5}"
        
        if command -v curl >/dev/null 2>&1; then
            curl -s --max-time "$timeout" --connect-timeout "$timeout" "http://169.254.169.254/latest/meta-data/$path" 2>/dev/null || echo "$default"
        else
            echo "$default"
        fi
    }
    
    # Get instance metadata
    export INSTANCE_ID="${INSTANCE_ID:-$(get_ec2_metadata "instance-id" "")}"
    export INSTANCE_TYPE="${INSTANCE_TYPE:-$(get_ec2_metadata "instance-type" "")}"
    export AVAILABILITY_ZONE="${AVAILABILITY_ZONE:-$(get_ec2_metadata "placement/availability-zone" "")}"
    export PUBLIC_IP="${PUBLIC_IP:-$(get_ec2_metadata "public-ipv4" "")}"
    export PRIVATE_IP="${PRIVATE_IP:-$(get_ec2_metadata "local-ipv4" "")}"
    
    # Set AWS region from metadata if not set
    if [ -z "${AWS_REGION:-}" ] && [ -n "$AVAILABILITY_ZONE" ]; then
        export AWS_REGION="${AVAILABILITY_ZONE%?}"  # Remove last character (AZ letter)
    fi
    
    # Ensure AWS_REGION has a default
    export AWS_REGION="${AWS_REGION:-us-east-1}"
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    # Set deployment environment variables
    export STACK_NAME="${STACK_NAME:-GeuseMaker}"
    export ENVIRONMENT="${ENVIRONMENT:-development}"
    export COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.gpu-optimized.yml}"
    
    var_log SUCCESS "Infrastructure variables initialized"
}

# Quick initialization for scripts that need basic variables
init_essential_variables() {
    var_log INFO "Quick initialization of essential variables"
    
    # Initialize only critical variables with secure defaults
    init_critical_variables
    
    # Set minimal required variables
    export POSTGRES_DB="${POSTGRES_DB:-n8n}"
    export POSTGRES_USER="${POSTGRES_USER:-n8n}"
    export AWS_REGION="${AWS_REGION:-us-east-1}"
    export ENVIRONMENT="${ENVIRONMENT:-development}"
    
    var_log SUCCESS "Essential variables initialized"
}

# Update specific variable and save to cache
update_variable() {
    local var_name="$1"
    local var_value="$2"
    local save_to_cache="${3:-true}"
    
    if [ -z "$var_name" ] || [ -z "$var_value" ]; then
        var_log ERROR "Variable name and value are required"
        return 1
    fi
    
    var_log INFO "Updating variable: $var_name"
    
    # Export the variable
    export "$var_name=$var_value"
    
    # Update cache if requested
    if [ "$save_to_cache" = "true" ]; then
        save_variables_to_cache
    fi
    
    var_log SUCCESS "Variable updated: $var_name"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Display current variable status
show_variable_status() {
    var_log INFO "Current Variable Status:"
    echo ""
    echo "Critical Variables:"
    for var in $CRITICAL_VARIABLES; do
        local value
        eval "value=\$$var"
        if [ -n "$value" ]; then
            echo "  ✓ $var: [SET - ${#value} chars]"
        else
            echo "  ✗ $var: [NOT SET]"
        fi
    done
    
    echo ""
    echo "Optional Variables:"
    for var in $OPTIONAL_VARIABLES; do
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
    echo ""
}

# Clear all cached variables
clear_variable_cache() {
    local cache_files="$VAR_CACHE_FILE $VAR_ENV_FILE $VAR_FALLBACK_FILE"
    
    var_log INFO "Clearing variable cache"
    
    for file in $cache_files; do
        if [ -f "$file" ]; then
            rm -f "$file"
            var_log INFO "Removed cache file: $file"
        fi
    done
    
    var_log SUCCESS "Variable cache cleared"
}

# =============================================================================
# LIBRARY INITIALIZATION AND EXPORTS
# =============================================================================

# Export functions for use by other scripts
if command -v export >/dev/null 2>&1; then
    # Core initialization functions
    export -f init_all_variables init_essential_variables init_critical_variables init_optional_variables 2>/dev/null || true
    
    # Parameter Store functions
    export -f load_variables_from_parameter_store get_parameter_store_value check_aws_availability 2>/dev/null || true
    
    # Validation functions
    export -f validate_critical_variables validate_optional_variables 2>/dev/null || true
    
    # File generation functions
    export -f generate_docker_env_file save_variables_to_cache load_variables_from_file 2>/dev/null || true
    
    # Utility functions
    export -f show_variable_status clear_variable_cache update_variable 2>/dev/null || true
    
    # Secure generation functions
    export -f generate_secure_password generate_encryption_key generate_jwt_secret 2>/dev/null || true
fi

var_log INFO "Variable Management Library loaded (v$VARIABLE_MANAGEMENT_VERSION)"