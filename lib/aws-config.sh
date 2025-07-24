#!/bin/bash
# =============================================================================
# AWS Configuration Management Library
# Configuration defaults, validation, and management functions
# =============================================================================

# =============================================================================
# CONFIGURATION DEFAULTS
# =============================================================================

set_default_configuration() {
    local deployment_type="${1:-spot}"
    
    # Global defaults
    export AWS_REGION="${AWS_REGION:-us-east-1}"
    export ENVIRONMENT="${ENVIRONMENT:-development}"
    export MAX_HEALTH_CHECK_ATTEMPTS="${MAX_HEALTH_CHECK_ATTEMPTS:-10}"
    export HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"
    
    # Instance configuration defaults
    case "$deployment_type" in
        "spot")
            export INSTANCE_TYPE="${INSTANCE_TYPE:-g4dn.xlarge}"
            export SPOT_PRICE="${SPOT_PRICE:-0.50}"
            export SPOT_TYPE="${SPOT_TYPE:-one-time}"
            ;;
        "ondemand")
            export INSTANCE_TYPE="${INSTANCE_TYPE:-g4dn.xlarge}"
            ;;
        "simple")
            export INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
            ;;
    esac
    
    # Networking defaults
    export VPC_CIDR="${VPC_CIDR:-10.0.0.0/16}"
    export SUBNET_CIDR="${SUBNET_CIDR:-10.0.1.0/24}"
    
    # Application defaults
    export COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.gpu-optimized.yml}"
    export APPLICATION_PORT="${APPLICATION_PORT:-5678}"
    
    # Storage defaults
    export EFS_PERFORMANCE_MODE="${EFS_PERFORMANCE_MODE:-generalPurpose}"
    export EFS_THROUGHPUT_MODE="${EFS_THROUGHPUT_MODE:-provisioned}"
    export EFS_PROVISIONED_THROUGHPUT="${EFS_PROVISIONED_THROUGHPUT:-100}"
    
    # Load balancer defaults (for applicable deployment types)
    export ALB_SCHEME="${ALB_SCHEME:-internet-facing}"
    export ALB_TYPE="${ALB_TYPE:-application}"
    
    # CloudFront defaults
    export CLOUDFRONT_PRICE_CLASS="${CLOUDFRONT_PRICE_CLASS:-PriceClass_100}"
    export CLOUDFRONT_MIN_TTL="${CLOUDFRONT_MIN_TTL:-0}"
    export CLOUDFRONT_DEFAULT_TTL="${CLOUDFRONT_DEFAULT_TTL:-3600}"
    export CLOUDFRONT_MAX_TTL="${CLOUDFRONT_MAX_TTL:-86400}"
    
    # Monitoring defaults
    export CLOUDWATCH_LOG_GROUP="${CLOUDWATCH_LOG_GROUP:-/aws/GeuseMaker}"
    export CLOUDWATCH_LOG_RETENTION="${CLOUDWATCH_LOG_RETENTION:-30}"
    
    # Backup defaults
    export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
    export BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-daily}"
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

validate_deployment_config() {
    local deployment_type="$1"
    local stack_name="$2"
    
    log "Validating configuration for $deployment_type deployment..."
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION"
        "INSTANCE_TYPE"
        "ENVIRONMENT"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required configuration variable $var is not set"
            return 1
        fi
    done
    
    # Deployment-specific validation
    case "$deployment_type" in
        "spot")
            validate_spot_configuration
            ;;
        "ondemand")
            validate_ondemand_configuration
            ;;
        "simple")
            validate_simple_configuration
            ;;
        *)
            error "Unknown deployment type: $deployment_type"
            return 1
            ;;
    esac
    
    # Validate instance type for deployment type
    validate_instance_type_compatibility "$deployment_type" "$INSTANCE_TYPE"
    
    success "Configuration validation passed"
    return 0
}

validate_spot_configuration() {
    # Validate spot-specific configuration
    if [ -z "$SPOT_PRICE" ]; then
        error "SPOT_PRICE is required for spot deployment"
        return 1
    fi
    
    # Validate spot price range
    if ! echo "$SPOT_PRICE" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        error "SPOT_PRICE must be a valid number: $SPOT_PRICE"
        return 1
    fi
    
    # Check if spot price is reasonable (between $0.10 and $50.00)
    if (( $(echo "$SPOT_PRICE < 0.10" | bc -l) )); then
        error "SPOT_PRICE too low (minimum $0.10): $SPOT_PRICE"
        return 1
    fi
    
    if (( $(echo "$SPOT_PRICE > 50.00" | bc -l) )); then
        error "SPOT_PRICE too high (maximum $50.00): $SPOT_PRICE"
        return 1
    fi
    
    # Validate spot type
    local valid_spot_types=("one-time" "persistent")
    if [[ ! " ${valid_spot_types[*]} " =~ " ${SPOT_TYPE} " ]]; then
        error "SPOT_TYPE must be one of: ${valid_spot_types[*]}"
        return 1
    fi
    
    return 0
}

validate_ondemand_configuration() {
    # Validate on-demand specific configuration
    
    # Check for GPU instance types if using GPU-optimized compose file
    if [[ "$COMPOSE_FILE" == *"gpu"* ]] && [[ ! "$INSTANCE_TYPE" =~ ^(g4dn|g5|p3|p4) ]]; then
        warning "Using GPU-optimized compose file with non-GPU instance type: $INSTANCE_TYPE"
    fi
    
    return 0
}

validate_simple_configuration() {
    # Validate simple deployment configuration
    
    # Warn if using GPU instances for simple deployment
    if [[ "$INSTANCE_TYPE" =~ ^(g4dn|g5|p3|p4) ]]; then
        warning "Using GPU instance type for simple deployment: $INSTANCE_TYPE"
        warning "Consider using compute-optimized instances instead"
    fi
    
    return 0
}

validate_instance_type_compatibility() {
    local deployment_type="$1"
    local instance_type="$2"
    
    # Define instance type families
    local gpu_instances=("g4dn" "g5" "p3" "p4")
    local compute_instances=("c5" "c5n" "c6i")
    local general_instances=("t3" "t3a" "m5" "m5a" "m6i")
    
    # Check if instance type is valid for deployment type
    case "$deployment_type" in
        "spot")
            # Spot can use any instance type, but recommend GPU for AI workloads
            if [[ ! "$instance_type" =~ ^(g4dn|g5|p3|p4) ]]; then
                warning "Spot deployment typically benefits from GPU instances"
            fi
            ;;
        "simple")
            # Simple deployment should use cost-effective instances
            if [[ "$instance_type" =~ ^(g4dn|g5|p3|p4) ]]; then
                warning "Simple deployment using expensive GPU instance: $instance_type"
            fi
            ;;
    esac
    
    return 0
}

# =============================================================================
# SERVICE PORT DEFINITIONS
# =============================================================================

get_service_ports() {
    local service_name="$1"
    
    case "$service_name" in
        "n8n")
            echo "5678"
            ;;
        "ollama")
            echo "11434"
            ;;
        "qdrant")
            echo "6333"
            ;;
        "crawl4ai")
            echo "11235"
            ;;
        "postgres")
            echo "5432"
            ;;
        "ssh")
            echo "22"
            ;;
        "all")
            echo "22 5678 11434 6333 11235 5432"
            ;;
        *)
            error "Unknown service: $service_name"
            return 1
            ;;
    esac
    
    return 0
}

get_standard_service_list() {
    local deployment_type="$1"
    
    case "$deployment_type" in
        "spot"|"ondemand")
            echo "n8n:5678 ollama:11434 qdrant:6333 crawl4ai:11235"
            ;;
        "simple")
            echo "n8n:5678 ollama:11434"
            ;;
        *)
            echo "n8n:5678"
            ;;
    esac
    
    return 0
}

# =============================================================================
# ENVIRONMENT-SPECIFIC CONFIGURATION
# =============================================================================

apply_environment_overrides() {
    local environment="$1"
    
    case "$environment" in
        "production")
            # Production overrides
            export MAX_HEALTH_CHECK_ATTEMPTS="20"
            export HEALTH_CHECK_INTERVAL="30"
            export CLOUDWATCH_LOG_RETENTION="90"
            export BACKUP_RETENTION_DAYS="30"
            export EFS_PERFORMANCE_MODE="maxIO"
            export EFS_PROVISIONED_THROUGHPUT="500"
            ;;
        "staging")
            # Staging overrides
            export MAX_HEALTH_CHECK_ATTEMPTS="15"
            export HEALTH_CHECK_INTERVAL="20"
            export CLOUDWATCH_LOG_RETENTION="30"
            export BACKUP_RETENTION_DAYS="14"
            ;;
        "development")
            # Development overrides (defaults are already set for dev)
            export CLOUDWATCH_LOG_RETENTION="7"
            export BACKUP_RETENTION_DAYS="3"
            ;;
        *)
            warning "Unknown environment: $environment. Using development defaults."
            ;;
    esac
    
    return 0
}

# =============================================================================
# COST OPTIMIZATION CONFIGURATION
# =============================================================================

get_cost_optimized_configuration() {
    local deployment_type="$1"
    local budget_tier="${2:-medium}"
    
    case "$budget_tier" in
        "low")
            case "$deployment_type" in
                "spot")
                    export INSTANCE_TYPE="g4dn.xlarge"
                    export SPOT_PRICE="0.30"
                    ;;
                "ondemand")
                    export INSTANCE_TYPE="t3.large"
                    ;;
                "simple")
                    export INSTANCE_TYPE="t3.medium"
                    ;;
            esac
            export EFS_PERFORMANCE_MODE="generalPurpose"
            export EFS_PROVISIONED_THROUGHPUT="100"
            ;;
        "medium")
            # Use default configuration (already optimized for medium budget)
            ;;
        "high")
            case "$deployment_type" in
                "spot")
                    export INSTANCE_TYPE="g4dn.2xlarge"
                    export SPOT_PRICE="1.00"
                    ;;
                "ondemand")
                    export INSTANCE_TYPE="g4dn.xlarge"
                    ;;
            esac
            export EFS_PERFORMANCE_MODE="maxIO"
            export EFS_PROVISIONED_THROUGHPUT="500"
            ;;
        *)
            warning "Unknown budget tier: $budget_tier. Using medium defaults."
            ;;
    esac
    
    return 0
}

# =============================================================================
# REGION-SPECIFIC CONFIGURATION
# =============================================================================

apply_region_specific_configuration() {
    local region="$1"
    
    case "$region" in
        "us-east-1")
            # US East 1 specific configuration
            export CLOUDFRONT_PRICE_CLASS="PriceClass_All"
            ;;
        "us-west-2")
            # US West 2 specific configuration
            export CLOUDFRONT_PRICE_CLASS="PriceClass_100"
            ;;
        "eu-west-1")
            # EU West 1 specific configuration
            export CLOUDFRONT_PRICE_CLASS="PriceClass_200"
            ;;
        *)
            # Default for other regions
            export CLOUDFRONT_PRICE_CLASS="PriceClass_100"
            ;;
    esac
    
    return 0
}

# =============================================================================
# CONFIGURATION DISPLAY
# =============================================================================

display_configuration_summary() {
    local deployment_type="$1"
    local stack_name="$2"
    
    echo
    info "=== Deployment Configuration Summary ==="
    echo "Stack Name: $stack_name"
    echo "Deployment Type: $deployment_type"
    echo "Environment: $ENVIRONMENT"
    echo "AWS Region: $AWS_REGION"
    echo "Instance Type: $INSTANCE_TYPE"
    
    case "$deployment_type" in
        "spot")
            echo "Spot Price: \$${SPOT_PRICE}/hour"
            echo "Spot Type: $SPOT_TYPE"
            ;;
    esac
    
    echo "Compose File: $COMPOSE_FILE"
    echo "Application Port: $APPLICATION_PORT"
    echo "Health Check Attempts: $MAX_HEALTH_CHECK_ATTEMPTS"
    echo "Health Check Interval: ${HEALTH_CHECK_INTERVAL}s"
    echo "CloudWatch Log Retention: ${CLOUDWATCH_LOG_RETENTION} days"
    echo "Backup Retention: ${BACKUP_RETENTION_DAYS} days"
    echo
}

# =============================================================================
# CONFIGURATION EXPORT
# =============================================================================

export_configuration_to_env_file() {
    local env_file="$1"
    local deployment_type="$2"
    
    if [ -z "$env_file" ]; then
        error "export_configuration_to_env_file requires env_file parameter"
        return 1
    fi
    
    log "Exporting configuration to: $env_file"
    
    cat > "$env_file" << EOF
# GeuseMaker Deployment Configuration
# Generated on: $(date)
# Deployment Type: $deployment_type

# Global Configuration
AWS_REGION=$AWS_REGION
ENVIRONMENT=$ENVIRONMENT
STACK_NAME=$STACK_NAME

# Instance Configuration
INSTANCE_TYPE=$INSTANCE_TYPE
EOF

    if [ "$deployment_type" = "spot" ]; then
        cat >> "$env_file" << EOF
SPOT_PRICE=$SPOT_PRICE
SPOT_TYPE=$SPOT_TYPE
EOF
    fi

    cat >> "$env_file" << EOF

# Application Configuration
COMPOSE_FILE=$COMPOSE_FILE
APPLICATION_PORT=$APPLICATION_PORT

# Health Check Configuration
MAX_HEALTH_CHECK_ATTEMPTS=$MAX_HEALTH_CHECK_ATTEMPTS
HEALTH_CHECK_INTERVAL=$HEALTH_CHECK_INTERVAL

# Storage Configuration
EFS_PERFORMANCE_MODE=$EFS_PERFORMANCE_MODE
EFS_THROUGHPUT_MODE=$EFS_THROUGHPUT_MODE
EFS_PROVISIONED_THROUGHPUT=$EFS_PROVISIONED_THROUGHPUT

# Monitoring Configuration
CLOUDWATCH_LOG_GROUP=$CLOUDWATCH_LOG_GROUP
CLOUDWATCH_LOG_RETENTION=$CLOUDWATCH_LOG_RETENTION

# Backup Configuration
BACKUP_RETENTION_DAYS=$BACKUP_RETENTION_DAYS
BACKUP_SCHEDULE=$BACKUP_SCHEDULE
EOF

    success "Configuration exported to: $env_file"
    return 0
}

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

load_configuration_from_env_file() {
    local env_file="$1"
    
    if [ -z "$env_file" ]; then
        error "load_configuration_from_env_file requires env_file parameter"
        return 1
    fi
    
    if [ ! -f "$env_file" ]; then
        error "Environment file not found: $env_file"
        return 1
    fi
    
    log "Loading configuration from: $env_file"
    
    # Source the environment file
    set -a  # Automatically export all variables
    source "$env_file"
    set +a
    
    success "Configuration loaded from: $env_file"
    return 0
}

# =============================================================================
# CONFIGURATION VALIDATION HELPERS
# =============================================================================

validate_required_configuration() {
    local deployment_type="$1"
    local required_vars=()
    
    # Base required variables
    required_vars+=("AWS_REGION" "ENVIRONMENT" "INSTANCE_TYPE")
    
    # Deployment-specific required variables
    case "$deployment_type" in
        "spot")
            required_vars+=("SPOT_PRICE" "SPOT_TYPE")
            ;;
    esac
    
    # Check all required variables
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        error "Missing required configuration variables: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}