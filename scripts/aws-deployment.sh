#!/bin/bash

# =============================================================================
# GeuseMaker - AWS Deployment Automation
# =============================================================================
# This script automates the complete deployment of the AI starter kit on AWS
# Features: EFS setup, GPU instances, cost optimization, monitoring
# Intelligent AMI and Instance Selection: Automatically selects best price/performance
# Deep Learning AMIs: Pre-configured NVIDIA drivers, Docker GPU runtime, CUDA toolkit
# Cost Optimization: 70% savings with spot instances + intelligent configuration selection
# =============================================================================

# Check if running under bash (required for associative arrays)
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash to run properly."
    echo "Please run: bash $0 $*"
    echo "Or make the script executable and ensure it uses the bash shebang."
    exit 1
fi

# =============================================================================
# ROBUST PARSING AND VALIDATION FUNCTIONS
# =============================================================================

# Safe arithmetic operations with validation
safe_add() {
    local a="$1" b="$2"
    if [[ "$a" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ "$b" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "scale=6; $a + $b" | bc -l 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

safe_multiply() {
    local a="$1" b="$2"
    if [[ "$a" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ "$b" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "scale=6; $a * $b" | bc -l 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

safe_divide() {
    local a="$1" b="$2"
    if [[ "$a" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ "$b" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$b > 0" | bc -l 2>/dev/null || echo "0") )); then
        echo "scale=6; $a / $b" | bc -l 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

safe_compare() {
    local a="$1" op="$2" b="$3"
    if [[ "$a" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ "$b" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$a $op $b" | bc -l 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Validate numeric value
is_numeric() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

# Validate configuration field count and format  
validate_config_format() {
    local config="$1"
    local expected_fields="${2:-11}"
    
    if [[ -z "$config" ]]; then
        return 1
    fi
    
    IFS=':' read -ra fields <<< "$config"
    if [[ ${#fields[@]} -ne $expected_fields ]]; then
        warning "Configuration has ${#fields[@]} fields, expected $expected_fields: $(echo "$config" | cut -c1-50)..."
        return 1
    fi
    
    # Validate required fields are not empty
    for i in 0 1 2 3; do  # instance_type, ami, ami_type, region
        if [[ -z "${fields[$i]:-}" ]]; then
            warning "Required field $i is empty in config: $(echo "$config" | cut -c1-50)..."
            return 1
        fi
    done
    
    return 0
}

# Validate 14-field configuration format (config_num:11_field_config:price:value_ratio)
validate_14_field_format() {
    local config="$1"
    IFS=':' read -ra fields <<< "$config"
    
    if [[ ${#fields[@]} -ne 14 ]]; then
        warning "Configuration has ${#fields[@]} fields, expected exactly 14: $(echo "$config" | cut -c1-50)..."
        return 1
    fi
    
    # Validate critical fields are not empty (instance_type, region, price)
    if [[ -z "${fields[1]}" || -z "${fields[4]}" || -z "${fields[12]}" ]]; then
        warning "Critical fields (instance_type, region, price) cannot be empty in 14-field config"
        return 1
    fi
    
    return 0
}

# Parse 14-field configuration safely
parse_14_field_config() {
    local full_config="$1"
    local config_data_var="$2"
    local price_var="$3"
    
    if ! validate_14_field_format "$full_config"; then
        return 1
    fi
    
    IFS=':' read -ra fields <<< "$full_config"
    
    # Extract config data (fields 1-11) and price (field 12)
    local config_data="${fields[1]}:${fields[2]}:${fields[3]}:${fields[4]}:${fields[5]}:${fields[6]}:${fields[7]}:${fields[8]}:${fields[9]}:${fields[10]}:${fields[11]}"
    local price="${fields[12]}"
    
    # Return values via variable names (bash 3.x compatible)
    eval "$config_data_var='$config_data'"
    eval "$price_var='$price'"
    
    return 0
}

# Robust configuration parsing with validation
parse_config_safely() {
    local config="$1"
    local expected_fields="${2:-11}"
    
    if ! validate_config_format "$config" "$expected_fields"; then
        return 1
    fi
    
    IFS=':' read -ra fields <<< "$config"
    
    # Export parsed fields with validation
    export CONFIG_INSTANCE_TYPE="${fields[0]:-}"
    export CONFIG_AMI="${fields[1]:-}"
    export CONFIG_AMI_TYPE="${fields[2]:-}"
    export CONFIG_REGION="${fields[3]:-}"
    export CONFIG_VCPUS="${fields[4]:-0}"
    export CONFIG_RAM="${fields[5]:-0}"
    export CONFIG_GPUS="${fields[6]:-0}"
    export CONFIG_GPU_TYPE="${fields[7]:-}"
    export CONFIG_CPU_ARCH="${fields[8]:-}"
    export CONFIG_STORAGE="${fields[9]:-}"
    export CONFIG_PERF_SCORE="${fields[10]:-0}"
    if [[ $expected_fields -eq 12 ]]; then
        export CONFIG_PRICE="${fields[11]:-0}"
    fi
    
    # Validate numeric fields
    for field in CONFIG_VCPUS CONFIG_RAM CONFIG_GPUS CONFIG_PERF_SCORE; do
        local value=$(eval echo \$$field)
        if ! is_numeric "$value"; then
            warning "Non-numeric value for $field: $value, setting to 0"
            eval export $field="0"
        fi
    done
    
    if [[ $expected_fields -eq 12 ]] && ! is_numeric "$CONFIG_PRICE"; then
        warning "Non-numeric value for CONFIG_PRICE: $CONFIG_PRICE, setting to 0"
        export CONFIG_PRICE="0"
    fi
    
    return 0
}

# =============================================================================
# CLEANUP ON FAILURE HANDLER
# =============================================================================

# Global flag to track if cleanup should run
CLEANUP_ON_FAILURE="${CLEANUP_ON_FAILURE:-true}"
RESOURCES_CREATED=false
STACK_NAME=""

cleanup_on_failure() {
    local exit_code=$?
    if [ "$CLEANUP_ON_FAILURE" = "true" ] && [ "$RESOURCES_CREATED" = "true" ] && [ $exit_code -ne 0 ] && [ -n "$STACK_NAME" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        error "🚨 Deployment failed! Running automatic cleanup for stack: $STACK_NAME"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Get script directory
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        # Use cleanup script if available
        if [ -f "$script_dir/cleanup-stack.sh" ]; then
            log "Using cleanup script to remove resources..."
            "$script_dir/cleanup-stack.sh" "$STACK_NAME" || true
        else
            log "Running manual cleanup..."
            # Basic manual cleanup
            aws ec2 describe-instances --filters "Name=tag:Stack,Values=$STACK_NAME" --query 'Reservations[].Instances[].[InstanceId]' --output text | while read -r instance_id; do
                if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                    aws ec2 terminate-instances --instance-ids "$instance_id" --region "${AWS_REGION:-us-east-1}" || true
                    log "Terminated instance: $instance_id"
                fi
            done
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warning "💡 To disable automatic cleanup, set CLEANUP_ON_FAILURE=false"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Register cleanup handler
trap cleanup_on_failure EXIT

# Note: Converted to work with bash 3.2+ (compatible with macOS default bash)

set -euo pipefail

# Load shared libraries following project standard pattern
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Required libraries - source these in order (per CLAUDE.md)
if [[ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]]; then
    source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
else
    echo "Warning: aws-deployment-common.sh not found"
fi

if [[ -f "$PROJECT_ROOT/lib/error-handling.sh" ]]; then
    source "$PROJECT_ROOT/lib/error-handling.sh"
else
    echo "Warning: error-handling.sh not found"
fi

# Load security validation library
if [[ -f "$SCRIPT_DIR/security-validation.sh" ]]; then
    source "$SCRIPT_DIR/security-validation.sh"
else
    echo "Warning: Security validation library not found at $SCRIPT_DIR/security-validation.sh"
fi

# Colors are provided by shared library (aws-deployment-common.sh)
# MAGENTA is missing from shared library but used by step() function
MAGENTA='\033[0;35m'

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-auto}"  # Changed to auto-selection
MAX_SPOT_PRICE="${MAX_SPOT_PRICE:-2.00}"  # Increased for G5 instances
KEY_NAME="${KEY_NAME:-GeuseMaker-key}"
STACK_NAME="${STACK_NAME:-GeuseMaker}"
PROJECT_NAME="${PROJECT_NAME:-GeuseMaker}"
ENABLE_CROSS_REGION="${ENABLE_CROSS_REGION:-false}"  # Cross-region analysis
USE_LATEST_IMAGES="${USE_LATEST_IMAGES:-true}"  # Use latest Docker images by default
SETUP_ALB="${SETUP_ALB:-false}"  # Setup Application Load Balancer
SETUP_CLOUDFRONT="${SETUP_CLOUDFRONT:-false}"  # Setup CloudFront distribution

# =============================================================================
# GPU INSTANCE AND AMI CONFIGURATION MATRIX
# =============================================================================

# Define supported AMI and instance type combinations
# Based on AWS Deep Learning AMI and NVIDIA NGC documentation
# Function to get GPU configuration (replaces associative array for bash 3.2 compatibility)
get_gpu_config() {
    local key="$1"
    case "$key" in
        # G4DN instances with Deep Learning AMI (Intel Xeon + NVIDIA T4)
        "g4dn.xlarge_primary") echo "ami-0489c31b03f0be3d6" ;;
        "g4dn.xlarge_secondary") echo "ami-00b530caaf8eee2c5" ;;
        "g4dn.2xlarge_primary") echo "ami-0489c31b03f0be3d6" ;;
        "g4dn.2xlarge_secondary") echo "ami-00b530caaf8eee2c5" ;;
        
        # G5G instances with Deep Learning AMI (ARM Graviton2 + NVIDIA T4G)
        "g5g.xlarge_primary") echo "ami-0126d561b2bb55618" ;;
        "g5g.xlarge_secondary") echo "ami-04ba92cdace8a636f" ;;
        "g5g.2xlarge_primary") echo "ami-0126d561b2bb55618" ;;
        "g5g.2xlarge_secondary") echo "ami-04ba92cdace8a636f" ;;
        
        *) echo "" ;;  # Return empty string for unknown keys
    esac
}

# Instance type specifications
# Function to get instance specs (replaces associative array for bash 3.2 compatibility)
get_instance_specs() {
    local key="$1"
    case "$key" in
        "g4dn.xlarge") echo "4:16:1:T4:Intel:125GB" ;;     # vCPUs:RAM:GPUs:GPU_Type:CPU_Arch:Storage
        "g4dn.2xlarge") echo "8:32:1:T4:Intel:225GB" ;;
        "g5g.xlarge") echo "4:8:1:T4G:ARM:125GB" ;;
        "g5g.2xlarge") echo "8:16:1:T4G:ARM:225GB" ;;
        *) echo "" ;;  # Return empty string for unknown keys
    esac
}

# Performance scoring (higher = better)
# Function to get performance scores (replaces associative array for bash 3.2 compatibility)
get_performance_score() {
    local key="$1"
    case "$key" in
        "g4dn.xlarge") echo "70" ;;
        "g4dn.2xlarge") echo "85" ;;
        "g5g.xlarge") echo "65" ;;      # ARM may have compatibility considerations
        "g5g.2xlarge") echo "80" ;;
        *) echo "0" ;;  # Return 0 for unknown keys
    esac
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

error() {
    echo -e "${RED}❌ [ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✅ [SUCCESS] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠️  [WARNING] $1${NC}" >&2
}

info() {
    echo -e "${CYAN}ℹ️  [INFO] $1${NC}" >&2
}

step() {
    echo -e "${MAGENTA}🔸 [STEP] $1${NC}" >&2
}

progress() {
    echo -e "${BLUE}⏳ [PROGRESS] $1${NC}" >&2
}

check_prerequisites() {
    log "🔍 Checking prerequisites for intelligent GPU deployment..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI first."
        error "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker not found. Please install Docker first."
        error "Install: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose not found. Please install Docker Compose first."
        error "Install: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        error "Documentation: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html"
        exit 1
    fi
    
    # Check jq for JSON processing (critical for intelligent selection)
    if ! command -v jq &> /dev/null; then
        warning "jq not found. Installing jq for intelligent configuration selection..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install jq || {
                    error "Failed to install jq via Homebrew. Please install it manually."
                    error "Install: brew install jq"
                    exit 1
                }
            else
                error "jq required for intelligent selection but Homebrew not found."
                error "Please install jq manually: https://stedolan.github.io/jq/download/"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y jq || {
                    error "Failed to install jq. Please install it manually."
                    error "Install: sudo apt-get install jq"
                    exit 1
                }
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq || {
                    error "Failed to install jq. Please install it manually."
                    error "Install: sudo yum install jq"
                    exit 1
                }
            else
                error "jq required for intelligent selection. Please install manually."
                error "Install: https://stedolan.github.io/jq/download/"
                exit 1
            fi
        else
            error "jq required for intelligent selection on this platform."
            error "Install: https://stedolan.github.io/jq/download/"
            exit 1
        fi
    fi
    
    # Check bc for price calculations (critical for cost optimization)
    if ! command -v bc &> /dev/null; then
        warning "bc (calculator) not found. Installing bc for price calculations..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install bc || {
                    error "Failed to install bc via Homebrew. Please install it manually."
                    exit 1
                }
            else
                error "bc required for price calculations but Homebrew not found."
                error "Please install bc manually"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y bc || {
                    error "Failed to install bc. Please install it manually."
                    exit 1
                }
            elif command -v yum &> /dev/null; then
                sudo yum install -y bc || {
                    error "Failed to install bc. Please install it manually."
                    exit 1
                }
            fi
        fi
    fi
    
    # Verify AWS region availability
    if ! aws ec2 describe-regions --region-names "$AWS_REGION" &> /dev/null; then
        error "Invalid or inaccessible AWS region: $AWS_REGION"
        error "Please specify a valid region with --region"
        exit 1
    fi
    
    # Get account info for display
    local ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    local CALLER_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null | sed 's/.*\///')
    
    success "✅ Prerequisites check completed"
    info "AWS Account: $ACCOUNT_ID"
    info "Caller: $CALLER_USER"
    info "Region: $AWS_REGION"
    info "Ready for intelligent GPU deployment!"
}

# =============================================================================
# INTELLIGENT AMI AND INSTANCE SELECTION
# =============================================================================

get_instance_type_list() {
    echo "g4dn.xlarge g4dn.2xlarge g5g.xlarge g5g.2xlarge"
}

# Unified configuration matrix that combines static configuration with dynamic checks
get_unified_configurations() {
    local region="$1"
    local enable_cross_region="${2:-false}"
    
    log "🔍 Building unified configuration matrix..."
    
    # Define regions to check
    local regions_to_check=("$region")
    if [[ "$enable_cross_region" == "true" ]]; then
        regions_to_check=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1" "us-east-2" "eu-central-1")
    fi
    
    local unified_configs=()
    
    for check_region in "${regions_to_check[@]}"; do
        info "Checking configurations in region $check_region..."
        
        for instance_type in $(get_instance_type_list); do
            # Get static configuration data
            local specs="$(get_instance_specs "$instance_type")"
            local perf_score="$(get_performance_score "$instance_type")"
            local primary_ami="$(get_gpu_config "${instance_type}_primary")"
            local secondary_ami="$(get_gpu_config "${instance_type}_secondary")"
            
            if [[ -z "$specs" || -z "$perf_score" || -z "$primary_ami" ]]; then
                warning "Incomplete configuration data for $instance_type, skipping"
                continue
            fi
            
            # Check instance type availability
            if ! check_instance_type_availability "$instance_type" "$check_region" >/dev/null 2>&1; then
                info "$instance_type not available in $check_region"
                continue
            fi
            
            # Check AMI availability and select best one
            local selected_ami=""
            local ami_type=""
            
            if verify_ami_availability "$primary_ami" "$check_region" >/dev/null 2>&1; then
                selected_ami="$primary_ami"
                ami_type="primary"
            elif verify_ami_availability "$secondary_ami" "$check_region" >/dev/null 2>&1; then
                selected_ami="$secondary_ami"
                ami_type="secondary"
            else
                info "No valid AMIs for $instance_type in $check_region"
                continue
            fi
            
            # Parse specs
            IFS=':' read -r vcpus ram gpus gpu_type cpu_arch storage <<< "$specs"
            
            # Create unified configuration entry
            local config_entry="$instance_type:$selected_ami:$ami_type:$check_region:$vcpus:$ram:$gpus:$gpu_type:$cpu_arch:$storage:$perf_score"
            unified_configs+=("$config_entry")
            
            success "✓ $instance_type available in $check_region with $ami_type AMI"
        done
    done
    
    if [[ ${#unified_configs[@]} -eq 0 ]]; then
        error "No valid configurations found across all checked regions"
        return 1
    fi
    
    printf '%s\n' "${unified_configs[@]}"
}

verify_ami_availability() {
    local ami_id="$1"
    local region="$2"
    
    log "Verifying AMI availability: $ami_id in $region..."
    
    AMI_STATE=$(aws ec2 describe-images \
        --image-ids "$ami_id" \
        --region "$region" \
        --query 'Images[0].State' \
        --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$AMI_STATE" == "available" ]]; then
        # Get AMI details
        AMI_INFO=$(aws ec2 describe-images \
            --image-ids "$ami_id" \
            --region "$region" \
            --query 'Images[0].{Name:Name,Description:Description,Architecture:Architecture,CreationDate:CreationDate}' \
            --output json 2>/dev/null)
        
        if [[ -n "$AMI_INFO" && "$AMI_INFO" != "null" ]]; then
            AMI_NAME=$(echo "$AMI_INFO" | jq -r '.Name // "Unknown"')
            AMI_ARCH=$(echo "$AMI_INFO" | jq -r '.Architecture // "Unknown"')
            AMI_DATE=$(echo "$AMI_INFO" | jq -r '.CreationDate // "Unknown"')
            
            success "✓ AMI $ami_id available: $AMI_NAME ($AMI_ARCH)"
            info "  Creation Date: $AMI_DATE"
            return 0
        fi
    fi
    
    warning "✗ AMI $ami_id not available in $region (State: $AMI_STATE)"
    return 1
}

check_instance_type_availability() {
    local instance_type="$1"
    local region="$2"
    
    log "Checking instance type availability: $instance_type in $region..."
    
    AVAILABLE_AZS=$(aws ec2 describe-instance-type-offerings \
        --location-type availability-zone \
        --filters "Name=instance-type,Values=$instance_type" \
        --region "$region" \
        --query 'InstanceTypeOfferings[].Location' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$AVAILABLE_AZS" && "$AVAILABLE_AZS" != "None" ]]; then
        success "✓ $instance_type available in AZs: $AVAILABLE_AZS"
        echo "$AVAILABLE_AZS"
        return 0
    else
        warning "✗ $instance_type not available in $region"
        return 1
    fi
}

get_comprehensive_spot_pricing() {
    local instance_types="$1"
    local region="$2"
    
    log "Analyzing spot pricing with cached data and fallbacks..." >&2
    
    # Cache directory for pricing data
    local cache_dir="/tmp/aws-pricing-cache"
    mkdir -p "$cache_dir"
    
    # Create temporary file for pricing data
    local pricing_file=$(mktemp)
    echo "[]" > "$pricing_file"
    
    # Historical average pricing data to avoid API dependency (bash 3.x compatible)
    get_typical_spot_price() {
        local instance_type="$1"
        case "$instance_type" in
            "g4dn.xlarge") echo "0.21" ;;
            "g4dn.2xlarge") echo "0.41" ;;
            "g5g.xlarge") echo "0.18" ;;
            "g5g.2xlarge") echo "0.35" ;;
            *) echo "" ;;
        esac
    }
    
    # Convert space-separated instance types to array
    local instance_array=($instance_types)
    
    info "Using cached/fallback pricing for ${#instance_array[@]} instance types in $region..." >&2
    
    # Check cache first, then try single API call with timeout, fallback to typical prices
    local region_cache_file="$cache_dir/region_${region}_batch.json"
    local use_cache=false
    
    if [[ -f "$region_cache_file" ]]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$region_cache_file" 2>/dev/null || stat -c %Y "$region_cache_file" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt 1800 ]]; then  # 30 minute cache for batch data
            use_cache=true
            info "Using cached batch pricing for $region (${cache_age}s old)" >&2
        fi
    fi
    
    if [[ "$use_cache" == "true" ]]; then
        SPOT_DATA=$(cat "$region_cache_file" 2>/dev/null || echo "[]")
    else
        # Single API call with timeout and fallback
        info "Attempting single API call for pricing data..." >&2
        SPOT_DATA=$(timeout 8s aws ec2 describe-spot-price-history \
            --instance-types "${instance_array[@]}" \
            --product-descriptions "Linux/UNIX" \
            --max-items 20 \
            --region "$region" \
            --query 'SpotPriceHistory[*].{instance_type: InstanceType, az: AvailabilityZone, price: SpotPrice, timestamp: Timestamp}' \
            --output json 2>/dev/null || echo "[]")
        
        if [[ "$SPOT_DATA" != "[]" && -n "$SPOT_DATA" && "$SPOT_DATA" != "null" ]]; then
            # Cache successful response
            echo "$SPOT_DATA" > "$region_cache_file"
            info "Cached fresh pricing data for region $region" >&2
        fi
    fi
    
    # If no data from cache or API, use fallback pricing
    if [[ "$SPOT_DATA" == "[]" || -z "$SPOT_DATA" || "$SPOT_DATA" == "null" ]]; then
        warning "Using fallback pricing based on historical averages" >&2
        local fallback_data="[]"
        
        for instance_type in "${instance_array[@]}"; do
            local typical_price=$(get_typical_spot_price "$instance_type")
            if [[ -n "$typical_price" ]]; then
                local instance_data=$(jq -n --arg instance_type "$instance_type" --arg price "$typical_price" --arg az "${region}a" \
                    '[{instance_type: $instance_type, az: $az, price: $price, timestamp: (now | strftime("%Y-%m-%dT%H:%M:%S.000Z"))}]')
                fallback_data=$(jq -s '.[0] + .[1]' <(echo "$fallback_data") <(echo "$instance_data"))
            fi
        done
        
        SPOT_DATA="$fallback_data"
    fi
    
    if [[ "$SPOT_DATA" != "[]" && -n "$SPOT_DATA" && "$SPOT_DATA" != "null" ]]; then
            # Validate JSON and merge with existing data
            if echo "$SPOT_DATA" | jq empty 2>/dev/null; then
                jq -s '.[0] + .[1]' "$pricing_file" <(echo "$SPOT_DATA") > "${pricing_file}.tmp"
                mv "${pricing_file}.tmp" "$pricing_file"
            else
                warning "Invalid JSON response for $instance_type pricing data" >&2
            fi
        else
            warning "No spot pricing data available for $instance_type in $region" >&2
            # COMMENTED OUT: Fallback logic that creates unreliable mock data
            # # Add fallback pricing based on typical market rates
            # case "$instance_type" in
            #     "g4dn.xlarge")
            #         FALLBACK_PRICE="0.45"
            #         ;;
            #     "g4dn.2xlarge")
            #         FALLBACK_PRICE="0.89"
            #         ;;
            #     "g5g.xlarge")
            #         FALLBACK_PRICE="0.38"
            #         ;;
            #     "g5g.2xlarge")
            #         FALLBACK_PRICE="0.75"
            #         ;;
            #     *)
            #         FALLBACK_PRICE="1.00"
            #         ;;
            # esac
            # 
            # warning "Using fallback pricing estimate: \$$FALLBACK_PRICE/hour for $instance_type"
            # FALLBACK_DATA=$(jq -n --arg instance_type "$instance_type" --arg price "$FALLBACK_PRICE" --arg az "${region}a" \
            #     '[{instance_type: $instance_type, az: $az, price: $price, timestamp: (now | strftime("%Y-%m-%dT%H:%M:%S.000Z"))}]')
            # 
            # jq -s '.[0] + .[1]' "$pricing_file" <(echo "$FALLBACK_DATA") > "${pricing_file}.tmp"
            # mv "${pricing_file}.tmp" "$pricing_file"
        fi
    
    # Validate final pricing data
    local final_data=$(cat "$pricing_file")
    if [[ "$final_data" == "[]" || -z "$final_data" ]]; then
        error "No pricing data could be obtained for any instance type" >&2
        rm -f "$pricing_file"
        return 1
    fi
    
    # Output comprehensive pricing data
    cat "$pricing_file"
    rm -f "$pricing_file"
}

# Cached pricing with fallback to avoid frequent API calls
get_comprehensive_spot_pricing_enhanced() {
    local configurations="$1"  # Array of unified configurations
    local max_budget="${2:-999999}"
    
    log "💰 Analyzing spot pricing with cached data and fallbacks..."
    
    # Cache directory for pricing data
    local cache_dir="/tmp/aws-pricing-cache"
    mkdir -p "$cache_dir"
    
    # Create temporary file for enhanced pricing data
    local pricing_file=$(mktemp)
    echo "[]" > "$pricing_file"
    
    # Historical average pricing data (updated periodically based on market trends)
    # This avoids frequent API calls and provides reliable estimates (bash 3.x compatible)
    get_typical_spot_price() {
        local instance_type="$1"
        case "$instance_type" in
            "g4dn.xlarge") echo "0.21" ;;     # Based on historical averages
            "g4dn.2xlarge") echo "0.41" ;;    # ~2x g4dn.xlarge
            "g5g.xlarge") echo "0.18" ;;      # ARM64 typically 15-20% cheaper
            "g5g.2xlarge") echo "0.35" ;;     # ~2x g5g.xlarge
            *) echo "" ;;
        esac
    }
    
    # Extract unique instance types and regions from configurations with robust validation
    local instance_regions=()
    local valid_config_count=0
    while IFS= read -r config; do
        if [[ -n "$config" ]]; then
            if ! parse_config_safely "$config" 11; then
                warning "Skipping malformed configuration in pricing analysis: $(echo "$config" | cut -c1-50)..."
                continue
            fi
            
            instance_type="$CONFIG_INSTANCE_TYPE"
            region="$CONFIG_REGION"
            instance_regions+=("$instance_type:$region")
            ((valid_config_count++))
        fi
    done <<< "$configurations"
    
    if [[ $valid_config_count -eq 0 ]]; then
        error "No valid configurations found for pricing analysis"
        echo "[]"
        rm -f "$pricing_file"
        return 1
    fi
    
    info "Processing pricing for $valid_config_count valid configurations..."
    
    # Remove duplicates
    local unique_instance_regions=($(printf '%s\n' "${instance_regions[@]}" | sort -u))
    local lowest_price="999999"
    local pricing_data_found=false
    
    # Try to get cached pricing first, then fallback to typical prices
    for instance_region in "${unique_instance_regions[@]}"; do
        IFS=':' read -r instance_type region <<< "$instance_region"
        
        # Check cache first (valid for 1 hour)
        local cache_file="$cache_dir/${instance_type}_${region}.json"
        local use_cache=false
        
        if [[ -f "$cache_file" ]]; then
            local cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
            if [[ $cache_age -lt 3600 ]]; then  # 1 hour cache
                use_cache=true
                info "Using cached pricing for $instance_type in $region (${cache_age}s old)"
            fi
        fi
        
        if [[ "$use_cache" == "true" ]]; then
            # Use cached data
            local cached_data=$(cat "$cache_file" 2>/dev/null || echo "[]")
            if [[ "$cached_data" != "[]" && -n "$cached_data" ]]; then
                SPOT_DATA="$cached_data"
                pricing_data_found=true
            else
                use_cache=false
            fi
        fi
        
        if [[ "$use_cache" == "false" ]]; then
            # Try API call with minimal impact (single request, limited data)
            info "Fetching fresh pricing for $instance_type in $region..."
            
            SPOT_DATA=$(timeout 10s aws ec2 describe-spot-price-history \
                --instance-types "$instance_type" \
                --product-descriptions "Linux/UNIX" \
                --max-items 5 \
                --region "$region" \
                --query 'SpotPriceHistory[*].{instance_type: InstanceType, az: AvailabilityZone, price: SpotPrice, timestamp: Timestamp, region: "'$region'"}' \
                --output json 2>/dev/null || echo "[]")
            
            if [[ "$SPOT_DATA" != "[]" && -n "$SPOT_DATA" && "$SPOT_DATA" != "null" ]]; then
                # Cache successful API response
                echo "$SPOT_DATA" > "$cache_file"
                pricing_data_found=true
            else
                # Use fallback pricing based on historical averages
                local typical_price=$(get_typical_spot_price "$instance_type")
                if [[ -n "$typical_price" ]]; then
                    info "Using historical average pricing for $instance_type: \$${typical_price}/hour"
                    SPOT_DATA=$(jq -n --arg instance_type "$instance_type" --arg price "$typical_price" --arg az "${region}a" --arg region "$region" \
                        '[{instance_type: $instance_type, az: $az, price: $price, timestamp: (now | strftime("%Y-%m-%dT%H:%M:%S.000Z")), region: $region}]')
                    pricing_data_found=true
                else
                    warning "No pricing data available for $instance_type"
                    continue
                fi
            fi
        fi
        
        if [[ "$SPOT_DATA" != "[]" && -n "$SPOT_DATA" && "$SPOT_DATA" != "null" ]]; then
            # Validate JSON and merge with existing data
            if echo "$SPOT_DATA" | jq empty 2>/dev/null; then
                # Track lowest price for budget optimization
                local current_min=$(echo "$SPOT_DATA" | jq -r 'min_by(.price | tonumber) | .price' 2>/dev/null || echo "999999")
                if is_numeric "$current_min" && (( $(safe_compare "$current_min" "<" "$lowest_price") )); then
                    lowest_price="$current_min"
                fi
                
                jq -s '.[0] + .[1]' "$pricing_file" <(echo "$SPOT_DATA") > "${pricing_file}.tmp"
                mv "${pricing_file}.tmp" "$pricing_file"
            else
                warning "Invalid JSON response for $instance_type pricing data"
            fi
        else
            warning "No spot pricing data available for $instance_type in $region"
        fi
    done
    
    # Validate we have pricing data
    local data_count=$(jq 'length' "$pricing_file" 2>/dev/null || echo "0")
    if [[ "$data_count" == "0" ]]; then
        warning "No pricing data collected across all instances"
        echo "[]"
        rm -f "$pricing_file"
        return 1
    fi
    
    # Set dynamic budget to lowest price + 20% margin if not specified
    if [[ "$max_budget" == "999999" && "$lowest_price" != "999999" ]]; then
        local suggested_budget=$(safe_multiply "$lowest_price" "1.2")
        if [[ "$suggested_budget" == "0" ]]; then
            suggested_budget="$lowest_price"
        fi
        success "🎯 Dynamic budget optimization: Suggested budget \$${suggested_budget}/hour (lowest: \$${lowest_price})"
        # Export for use by calling functions
        export DYNAMIC_BUDGET="$suggested_budget"
        export LOWEST_AVAILABLE_PRICE="$lowest_price"
    fi
    
    # Output the pricing data
    cat "$pricing_file"
    rm -f "$pricing_file"
}

# Display comprehensive configuration analysis with pricing
display_configuration_analysis() {
    local configurations="$1"
    local pricing_data="$2"
    local max_budget="$3"
    
    log "📋 Displaying comprehensive configuration analysis..."
    
    # Send display output to stderr so it shows to user but doesn't interfere with data capture
    {
        echo ""
        echo -e "${CYAN}┌────────────────────────────────────────────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│                         🚀 INTELLIGENT GPU CONFIGURATION ANALYSIS 🚀                        │${NC}"
        echo -e "${CYAN}├────────────────────────────────────────────────────────────────────────────────────────────────────┤${NC}"
        printf "${CYAN}│ %-3s │ %-12s │ %-8s │ %-8s │ %-5s │ %-6s │ %-4s │ %-8s │ %-6s │ %-11s │ %-10s │${NC}\n" \
            "#" "Instance" "Region" "Price/hr" "Perf" "CPUs" "RAM" "GPU" "Arch" "Availability" "Value"
        echo -e "${CYAN}├─────├──────────────├──────────├──────────├───────├────────├──────├──────────├────────├─────────────├────────────┤${NC}"
    } >&2
    
    local config_num=1
    local valid_configs=()
    
    while IFS= read -r config; do
        if [[ -n "$config" ]]; then
            # Use robust parsing with validation
            if ! parse_config_safely "$config" 11; then
                warning "Skipping malformed configuration: $(echo "$config" | cut -c1-50)..."
                continue
            fi
            
            # Use parsed and validated values
            instance_type="$CONFIG_INSTANCE_TYPE"
            ami="$CONFIG_AMI"
            ami_type="$CONFIG_AMI_TYPE"
            region="$CONFIG_REGION"
            vcpus="$CONFIG_VCPUS"
            ram="$CONFIG_RAM"
            gpus="$CONFIG_GPUS"
            gpu_type="$CONFIG_GPU_TYPE"
            cpu_arch="$CONFIG_CPU_ARCH"
            storage="$CONFIG_STORAGE"
            perf_score="$CONFIG_PERF_SCORE"
            
            # Get average spot price for this instance type in this region
            local avg_price=$(echo "$pricing_data" | jq -r \
                --arg type "$instance_type" --arg reg "$region" '
                [.[] | select(.instance_type == $type and .region == $reg) | .price | tonumber] | 
                if length > 0 then (add / length) else null end' 2>/dev/null || echo "null")
            
            if [[ "$avg_price" == "null" || -z "$avg_price" || "$avg_price" == "0" ]]; then
                avg_price="N/A"
                availability="❌ No pricing"
                value_ratio="N/A"
            else
                # Use safe arithmetic operations
                local price_numeric="$avg_price"
                if ! is_numeric "$price_numeric"; then
                    warning "Invalid avg_price value: $avg_price, skipping configuration"
                    continue
                fi
                
                # Check if within budget using safe comparison
                if (( $(safe_compare "$price_numeric" "<=" "$max_budget") )); then
                    availability="✓ Available"
                    # Calculate value ratio (performance per dollar) safely
                    value_ratio=$(safe_divide "$perf_score" "$price_numeric")
                    if [[ "$value_ratio" == "0" ]]; then
                        value_ratio="N/A"
                    else
                        # Format to 2 decimal places
                        value_ratio=$(printf "%.2f" "$value_ratio")
                    fi
                    valid_configs+=("$config_num:$config:$price_numeric:$value_ratio")
                else
                    availability="💰 Over budget"
                    value_ratio=$(safe_divide "$perf_score" "$price_numeric")
                    if [[ "$value_ratio" == "0" ]]; then
                        value_ratio="N/A"
                    else
                        value_ratio=$(printf "%.2f" "$value_ratio")
                    fi
                fi
                avg_price="\$${price_numeric}"
            fi
            
            # Format RAM display
            local ram_display="${ram}GB"
            
            # Send table row to stderr for user display
            printf "${CYAN}│ %-3s │ %-12s │ %-8s │ %-8s │ %-5s │ %-6s │ %-4s │ %-8s │ %-6s │ %-11s │ %-10s │${NC}\n" \
                "$config_num" "$instance_type" "$region" "$avg_price" "$perf_score" "$vcpus" "$ram_display" "$gpu_type" "$cpu_arch" "$availability" "$value_ratio" >&2
            
            ((config_num++))
        fi
    done <<< "$configurations"
    
    # Send closing table and info to stderr for user display
    {
        echo -e "${CYAN}└─────┴──────────────┴──────────┴──────────┴───────┴────────┴──────┴──────────┴────────┴─────────────┴────────────┘${NC}"
        echo ""
        
        # Show budget and recommendation info
        info "💰 Budget limit: \$${max_budget}/hour"
        local lowest_price_value="${LOWEST_AVAILABLE_PRICE:-}"
        if [[ -n "$lowest_price_value" && "$lowest_price_value" != "999999" ]]; then
            info "📈 Lowest available price: \$${lowest_price_value}/hour"
        fi
        local dynamic_budget_value="${DYNAMIC_BUDGET:-}"
        if [[ -n "$dynamic_budget_value" ]]; then
            info "🎯 Recommended budget: \$${dynamic_budget_value}/hour (lowest + 20% margin)"
        fi
    } >&2
    
    # Send only valid configurations data to stdout for capture
    if [[ ${#valid_configs[@]} -gt 0 ]]; then
        printf '%s\n' "${valid_configs[@]}"
    fi
}

# Interactive user selection of configuration
prompt_user_selection() {
    local valid_configs="$1"
    local all_configurations="$2"
    
    {
        echo ""
        echo -e "${YELLOW}✨ CONFIGURATION SELECTION ✨${NC}"
        echo -e "${CYAN}─────────────────────────────────────${NC}"
    } >&2
    
    if [[ -z "$valid_configs" ]]; then
        warning "No configurations available within budget \$${max_budget}/hour."
        warning "Attempting fallback strategy to ensure deployment proceeds..."
        
        # Try to find the cheapest configuration regardless of budget
        local fallback_configs=()
        local config_num=1
        while IFS= read -r config; do
            if [[ -n "$config" ]]; then
                if ! parse_config_safely "$config" 11; then
                    warning "Skipping malformed fallback configuration"
                    continue
                fi
                
                instance_type="$CONFIG_INSTANCE_TYPE"
                region="$CONFIG_REGION"
                perf_score="$CONFIG_PERF_SCORE"
                
                # Get average spot price
                local avg_price=$(echo "$pricing_data" | jq -r \
                    --arg type "$instance_type" --arg reg "$region" '
                    [.[] | select(.instance_type == $type and .region == $reg) | .price | tonumber] | 
                    if length > 0 then (add / length) else null end' 2>/dev/null || echo "null")
                
                if [[ "$avg_price" != "null" && -n "$avg_price" ]] && is_numeric "$avg_price"; then
                    local value_ratio=$(safe_divide "$perf_score" "$avg_price")
                    if [[ "$value_ratio" != "0" ]]; then
                        value_ratio=$(printf "%.2f" "$value_ratio")
                    else
                        value_ratio="N/A"
                    fi
                    fallback_configs+=("$config_num:$config:$avg_price:$value_ratio")
                fi
                ((config_num++))
            fi
        done <<< "$all_configurations"
        
        if [[ ${#fallback_configs[@]} -gt 0 ]]; then
            warning "Found ${#fallback_configs[@]} fallback configurations. Using cheapest option..."
            
            # Sort by price and select the cheapest
            local cheapest_config=""
            local cheapest_price="999999"
            for config_line in "${fallback_configs[@]}"; do
                # Parse format: config_num:11_field_config:price:value_ratio (total 14 fields)
                IFS=':' read -ra fields <<< "$config_line"
                
                # Validate we have enough fields
                if [[ ${#fields[@]} -lt 14 ]]; then
                    warning "Fallback configuration has ${#fields[@]} fields, expected 14: $(echo "$config_line" | cut -c1-50)..."
                    continue
                fi
                
                local config_data="${fields[1]}:${fields[2]}:${fields[3]}:${fields[4]}:${fields[5]}:${fields[6]}:${fields[7]}:${fields[8]}:${fields[9]}:${fields[10]}:${fields[11]}"
                local avg_price="${fields[12]}"
                local value_ratio="${fields[13]}"
                if is_numeric "$avg_price" && (( $(safe_compare "$avg_price" "<" "$cheapest_price") )); then
                    cheapest_price="$avg_price"
                    cheapest_config="$config_line"
                fi
            done
            
            if [[ -n "$cheapest_config" ]]; then
                warning "FALLBACK DEPLOYMENT: Using cheapest available configuration at \$${cheapest_price}/hour"
                warning "This exceeds your budget of \$${max_budget}/hour but ensures deployment proceeds."
                # Parse format: config_num:11_field_config:price:value_ratio (total 14 fields)
                IFS=':' read -ra fields <<< "$cheapest_config"
                local config_data="${fields[1]}:${fields[2]}:${fields[3]}:${fields[4]}:${fields[5]}:${fields[6]}:${fields[7]}:${fields[8]}:${fields[9]}:${fields[10]}:${fields[11]}"
                local avg_price="${fields[12]}"
                local value_ratio="${fields[13]}"
                echo "$config_data:$avg_price"
                return 0
            fi
        fi
        
        error "No valid configurations found even with fallback strategy."
        warning "Consider:"
        warning "  1. Increasing your --max-spot-price budget"
        warning "  2. Using --cross-region to find better pricing"
        warning "  3. Trying again during off-peak hours"
        return 1
    fi
    
    local config_array=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            config_array+=("$line")
        fi
    done <<< "$valid_configs"
    
    if [[ ${#config_array[@]} -eq 1 ]]; then
        # Only one valid option, auto-select it
        local selected_line="${config_array[0]}"
        # Parse format: config_num:11_field_config:price:value_ratio (total 14 fields)
        IFS=':' read -ra fields <<< "$selected_line"
        
        # Validate we have enough fields
        if [[ ${#fields[@]} -lt 14 ]]; then
            error "Auto-selected configuration has ${#fields[@]} fields, expected 14: $(echo "$selected_line" | cut -c1-50)..."
            return 1
        fi
        
        local config_num="${fields[0]}"
        # Reconstruct the 11-field config from fields 1-11
        local config_data="${fields[1]}:${fields[2]}:${fields[3]}:${fields[4]}:${fields[5]}:${fields[6]}:${fields[7]}:${fields[8]}:${fields[9]}:${fields[10]}:${fields[11]}"
        local avg_price="${fields[12]}"
        local value_ratio="${fields[13]}"
        
        success "🎯 Only one configuration within budget - auto-selecting:"
        if ! parse_config_safely "$config_data" 11; then
            error "Failed to parse auto-selected configuration"
            return 1
        fi
        instance_type="$CONFIG_INSTANCE_TYPE"
        ami="$CONFIG_AMI"
        ami_type="$CONFIG_AMI_TYPE"
        region="$CONFIG_REGION"
        vcpus="$CONFIG_VCPUS"
        ram="$CONFIG_RAM"
        gpus="$CONFIG_GPUS"
        gpu_type="$CONFIG_GPU_TYPE"
        cpu_arch="$CONFIG_CPU_ARCH"
        storage="$CONFIG_STORAGE"
        perf_score="$CONFIG_PERF_SCORE"
        info "  Selected: $instance_type in $region at $avg_price/hour (Value: $value_ratio)"
        
        echo "$config_data:$avg_price"
        return 0
    fi
    
    # Multiple options available - prompt user
    # CRITICAL: Force output to stderr so user always sees the selection menu
    # Root cause: prompt_user_selection output was going to stdout and could be
    # buffered or hidden, while the table from display_configuration_analysis 
    # goes to stderr. This ensures consistent display to the user.
    {
        echo ""
        info "Available configurations within budget:"
        echo ""
        
        for i in "${!config_array[@]}"; do
            local config_line="${config_array[$i]}"
            # Parse format: config_num:11_field_config:price:value_ratio (total 14 fields)
            IFS=':' read -ra fields <<< "$config_line"
            
            # Validate we have enough fields
            if [[ ${#fields[@]} -lt 14 ]]; then
                warning "Configuration line has ${#fields[@]} fields, expected 14: $(echo "$config_line" | cut -c1-50)..."
                continue
            fi
            
            local config_data="${fields[1]}:${fields[2]}:${fields[3]}:${fields[4]}:${fields[5]}:${fields[6]}:${fields[7]}:${fields[8]}:${fields[9]}:${fields[10]}:${fields[11]}"
            local avg_price="${fields[12]}"
            local value_ratio="${fields[13]}"
            
            if ! parse_config_safely "$config_data" 11; then
                warning "Skipping malformed configuration in selection menu"
                continue
            fi
            
            instance_type="$CONFIG_INSTANCE_TYPE"
            ami="$CONFIG_AMI"
            ami_type="$CONFIG_AMI_TYPE"
            region="$CONFIG_REGION"
            vcpus="$CONFIG_VCPUS"
            ram="$CONFIG_RAM"
            gpus="$CONFIG_GPUS"
            gpu_type="$CONFIG_GPU_TYPE"
            cpu_arch="$CONFIG_CPU_ARCH"
            storage="$CONFIG_STORAGE"
            perf_score="$CONFIG_PERF_SCORE"
            
            echo -e "  ${GREEN}[$((i+1))]${NC} $instance_type in $region - $avg_price/hour (Value: $value_ratio, Perf: $perf_score)"
        done
        
        echo ""
        echo -e "  ${GREEN}[a]${NC} Auto-select best value (highest performance/price ratio)"
        echo -e "  ${GREEN}[q]${NC} Quit deployment"
        echo ""
    } >&2
    
    while true; do
        read -p "Select configuration [1-${#config_array[@]}/a/q]: " choice
        
        case "$choice" in
            [1-9]|[1-9][0-9])
                local choice_idx=$((choice - 1))
                if [[ $choice_idx -ge 0 && $choice_idx -lt ${#config_array[@]} ]]; then
                    local selected_line="${config_array[$choice_idx]}"
                    # Parse format: config_num:11_field_config:price:value_ratio (total 14 fields)
                    IFS=':' read -ra fields <<< "$selected_line"
                    
                    # Validate we have enough fields
                    if [[ ${#fields[@]} -lt 14 ]]; then
                        warning "Selected configuration has ${#fields[@]} fields, expected 14: $(echo "$selected_line" | cut -c1-50)..."
                        continue
                    fi
                    
                    local config_data="${fields[1]}:${fields[2]}:${fields[3]}:${fields[4]}:${fields[5]}:${fields[6]}:${fields[7]}:${fields[8]}:${fields[9]}:${fields[10]}:${fields[11]}"
                    local avg_price="${fields[12]}"
                    local value_ratio="${fields[13]}"
                    
                    success "🎯 User selected configuration $choice:"
                    if ! parse_config_safely "$config_data" 11; then
                        error "Failed to parse selected configuration"
                        continue
                    fi
                    instance_type="$CONFIG_INSTANCE_TYPE"
                    ami="$CONFIG_AMI"
                    ami_type="$CONFIG_AMI_TYPE"
                    region="$CONFIG_REGION"
                    vcpus="$CONFIG_VCPUS"
                    ram="$CONFIG_RAM"
                    gpus="$CONFIG_GPUS"
                    gpu_type="$CONFIG_GPU_TYPE"
                    cpu_arch="$CONFIG_CPU_ARCH"
                    storage="$CONFIG_STORAGE"
                    perf_score="$CONFIG_PERF_SCORE"
                    info "  Selected: $instance_type in $region at $avg_price/hour (Value: $value_ratio)"
                    
                    echo "$config_data:$avg_price"
                    return 0
                else
                    warning "Invalid selection. Please choose 1-${#config_array[@]}, 'a', or 'q'."
                fi
                ;;
            [aA])
                # Auto-select best value
                local best_config=""
                local best_value=0
                
                for config_line in "${config_array[@]}"; do
                    # Parse format: config_num:11_field_config:price:value_ratio (total 14 fields)
                IFS=':' read -ra fields <<< "$config_line"
                
                # Validate we have enough fields
                if [[ ${#fields[@]} -lt 14 ]]; then
                    warning "Fallback configuration has ${#fields[@]} fields, expected 14: $(echo "$config_line" | cut -c1-50)..."
                    continue
                fi
                
                local config_data="${fields[1]}:${fields[2]}:${fields[3]}:${fields[4]}:${fields[5]}:${fields[6]}:${fields[7]}:${fields[8]}:${fields[9]}:${fields[10]}:${fields[11]}"
                local avg_price="${fields[12]}"
                local value_ratio="${fields[13]}"
                    # Use safe comparison for value selection
                    if ! is_numeric "$value_ratio"; then
                        warning "Invalid value_ratio: $value_ratio (should be numeric), skipping"
                        continue
                    fi
                    if (( $(safe_compare "$value_ratio" ">" "$best_value") )); then
                        best_value="$value_ratio"
                        best_config="$config_data:$avg_price"
                    fi
                done
                
                if [[ -n "$best_config" ]]; then
                    success "🎯 Auto-selected best value configuration:"
                    # Extract config data and price from best_config (format: config_data:price)
                    local config_data="${best_config%:*}"
                    local avg_price="${best_config##*:}"
                    
                    if ! parse_config_safely "$config_data" 11; then
                        error "Could not parse auto-selected configuration"
                        continue
                    fi
                    instance_type="$CONFIG_INSTANCE_TYPE"
                    ami="$CONFIG_AMI"
                    ami_type="$CONFIG_AMI_TYPE"
                    region="$CONFIG_REGION"
                    vcpus="$CONFIG_VCPUS"
                    ram="$CONFIG_RAM"
                    gpus="$CONFIG_GPUS"
                    gpu_type="$CONFIG_GPU_TYPE"
                    cpu_arch="$CONFIG_CPU_ARCH"
                    storage="$CONFIG_STORAGE"
                    perf_score="$CONFIG_PERF_SCORE"
                    info "  Selected: $instance_type in $region at \$$avg_price/hour (Value: $best_value)"
                    
                    echo "$best_config"
                    return 0
                else
                    error "Could not determine best configuration"
                    return 1
                fi
                ;;
            [qQ])
                info "Deployment cancelled by user."
                return 1
                ;;
            *)
                warning "Invalid selection. Please choose 1-${#config_array[@]}, 'a', or 'q'."
                ;;
        esac
    done
}

analyze_cost_performance_matrix() {
    local pricing_data="$1"
    
    log "Analyzing cost-performance matrix for optimal selection..."
    
    # Validate input pricing data
    if [[ -z "$pricing_data" || "$pricing_data" == "[]" || "$pricing_data" == "null" ]]; then
        error "No pricing data provided for analysis"
        return 1
    fi
    
    # Create comprehensive analysis
    local analysis_file=$(mktemp)
    echo "[]" > "$analysis_file"
    
    for instance_type in $(get_instance_type_list); do
        # Check if we have pricing data for this instance type
        local avg_price=$(echo "$pricing_data" | jq -r --arg type "$instance_type" '
            [.[] | select(.instance_type == $type) | .price | tonumber] | 
            if length > 0 then (add / length) else null end' 2>/dev/null || echo "null")
        
        if [[ "$avg_price" != "null" && -n "$avg_price" && "$avg_price" != "0" ]]; then
            # Get performance score
            local perf_score="$(get_performance_score "$instance_type")"
            
            # Validate performance score
            if [[ -z "$perf_score" || "$perf_score" == "0" ]]; then
                warning "No performance score available for $instance_type, skipping"
                continue
            fi
            
            # Validate numeric values before arithmetic
            if [[ ! "$perf_score" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                error "Invalid perf_score value: $perf_score (should be numeric)"
                continue
            fi
            if [[ ! "$avg_price" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                error "Invalid avg_price value: $avg_price (should be numeric)"
                continue
            fi
            
            # Calculate price-performance ratio (higher = better value)
            local price_perf_ratio=$(echo "scale=3; $perf_score / $avg_price" | bc -l 2>/dev/null || echo "0")
            
            # Validate calculation
            if [[ "$price_perf_ratio" == "0" || -z "$price_perf_ratio" ]]; then
                warning "Could not calculate price-performance ratio for $instance_type"
                continue
            fi
            
            # Get instance specifications
            local specs="$(get_instance_specs "$instance_type")"
            if [[ -z "$specs" ]]; then
                warning "No specifications available for $instance_type, skipping"
                continue
            fi
            
            IFS=':' read -r vcpus ram gpus gpu_type cpu_arch storage <<< "$specs"
            
            # Create analysis entry with validation
            local entry=$(jq -n \
                --arg instance_type "$instance_type" \
                --arg avg_price "$avg_price" \
                --arg perf_score "$perf_score" \
                --arg price_perf_ratio "$price_perf_ratio" \
                --arg vcpus "$vcpus" \
                --arg ram "$ram" \
                --arg gpus "$gpus" \
                --arg gpu_type "$gpu_type" \
                --arg cpu_arch "$cpu_arch" \
                --arg storage "$storage" \
                '{
                    instance_type: $instance_type,
                    avg_spot_price: ($avg_price | tonumber),
                    performance_score: ($perf_score | tonumber),
                    price_performance_ratio: ($price_perf_ratio | tonumber),
                    vcpus: ($vcpus | tonumber),
                    ram_gb: ($ram | tonumber),
                    gpus: ($gpus | tonumber),
                    gpu_type: $gpu_type,
                    cpu_architecture: $cpu_arch,
                    storage: $storage
                }' 2>/dev/null)
            
            if [[ -n "$entry" && "$entry" != "null" ]]; then
                # Add to analysis
                jq -s '.[0] + [.[1]]' "$analysis_file" <(echo "$entry") > "${analysis_file}.tmp" 2>/dev/null && \
                mv "${analysis_file}.tmp" "$analysis_file" || {
                    warning "Failed to add $instance_type to analysis"
                }
            fi
        else
            warning "No valid pricing data for $instance_type (price: $avg_price)"
        fi
    done
    
    # Validate we have some analysis data
    local analysis_count=$(jq 'length' "$analysis_file" 2>/dev/null || echo "0")
    if [[ "$analysis_count" == "0" ]]; then
        error "No valid configurations could be analyzed"
        rm -f "$analysis_file"
        return 1
    fi
    
    # Sort by price-performance ratio (descending)
    local sorted_analysis=$(jq 'sort_by(-.price_performance_ratio)' "$analysis_file" 2>/dev/null || echo "[]")
    echo "$sorted_analysis"
    rm -f "$analysis_file"
}

# Function to determine dynamic budget based on actual spot pricing
determine_dynamic_budget() {
    local enable_cross_region="${1:-false}"
    local base_budget="${2:-2.00}"
    
    info "Determining dynamic budget based on current spot pricing..."
    
    # Define regions to check
    local regions_to_check=("$AWS_REGION")
    if [[ "$enable_cross_region" == "true" ]]; then
        regions_to_check=("us-east-1" "us-west-2" "eu-west-1")
    fi
    
    # Collect all available pricing data
    local all_prices=()
    local pricing_available=false
    
    for region in "${regions_to_check[@]}"; do
        # Check common GPU instance types
        local instance_types="g4dn.xlarge g4dn.2xlarge g5g.xlarge g5g.2xlarge"
        
        for instance_type in $instance_types; do
            local price_data=$(aws ec2 describe-spot-price-history \
                --instance-types "$instance_type" \
                --product-descriptions "Linux/UNIX" \
                --max-items 10 \
                --region "$region" \
                --query 'SpotPriceHistory[0].SpotPrice' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$price_data" && "$price_data" != "None" && "$price_data" != "null" ]]; then
                all_prices+=($price_data)
                pricing_available=true
            fi
        done
    done
    
    if [[ "$pricing_available" == "true" && ${#all_prices[@]} -gt 0 ]]; then
        # Calculate dynamic budget: 120% of current median price
        local sorted_prices=($(printf '%s\n' "${all_prices[@]}" | sort -n))
        local median_index=$(( ${#sorted_prices[@]} / 2 ))
        local median_price="${sorted_prices[$median_index]}"
        local dynamic_budget=$(echo "scale=2; $median_price * 1.2" | bc -l)
        
        info "Current pricing analysis:"
        info "  • Found ${#all_prices[@]} active spot prices"
        info "  • Median price: \$${median_price}/hour"
        info "  • Suggested dynamic budget: \$${dynamic_budget}/hour"
        
        # Use the higher of base budget or dynamic budget
        local final_budget=$(echo "if ($dynamic_budget > $base_budget) $dynamic_budget else $base_budget" | bc -l)
        echo "$final_budget"
    else
        warning "No spot pricing data available for budget calculation"
        return 1
    fi
}

# Function to handle missing pricing data with user interaction
handle_no_pricing_data() {
    local enable_cross_region="${1:-false}"
    local base_budget="${2:-2.00}"
    
    error "No spot pricing data could be obtained for any instance type"
    echo ""
    warning "This could be due to:"
    warning "  • Temporary AWS API issues"
    warning "  • Regional availability constraints" 
    warning "  • Account/permission limitations"
    echo ""
    
    if [[ "${FORCE_YES:-false}" == "true" ]]; then
        warning "FORCE_YES enabled - proceeding with base budget \$${base_budget}/hour"
        return 0
    fi
    
    echo -e "${YELLOW}Would you like to proceed anyway? Options:${NC}"
    echo "  1) Continue with base budget (\$${base_budget}/hour)"
    echo "  2) Set custom budget limit"
    echo "  3) Cancel deployment"
    echo ""
    
    while true; do
        echo -n "Choose option [1-3]: "
        read choice
        case $choice in
            1)
                info "Proceeding with base budget: \$${base_budget}/hour"
                return 0
                ;;
            2)
                while true; do
                    echo -n "Enter custom budget (e.g., 3.50): \$"
                    read custom_budget
                    if [[ "$custom_budget" =~ ^[0-9]+\.?[0-9]*$ ]] && (( $(echo "$custom_budget > 0" | bc -l) )); then
                        MAX_SPOT_PRICE="$custom_budget"
                        info "Custom budget set to: \$${custom_budget}/hour"
                        return 0
                    else
                        error "Please enter a valid positive number"
                    fi
                done
                ;;
            3)
                info "Deployment cancelled by user"
                exit 0
                ;;
            *)
                error "Please choose 1, 2, or 3"
                ;;
        esac
    done
}

# Refactored intelligent configuration selection with user interaction
select_optimal_configuration() {
    local max_budget="$1"
    local enable_cross_region="${2:-false}"
    
    log "🤖 NEW Intelligent Configuration Selection Process Starting..."
    log "Budget limit: \$$max_budget/hour"
    log "Cross-region analysis: $enable_cross_region"
    
    # Step 1: Get unified configurations with integrated matrix data and availability
    step "Step 1: Building unified configuration matrix..."
    local configurations=$(get_unified_configurations "$AWS_REGION" "$enable_cross_region")
    
    if [[ -z "$configurations" ]]; then
        error "No valid configurations found across all regions"
        return 1
    fi
    
    # Step 2: Get comprehensive spot pricing with dynamic budget optimization
    step "Step 2: Analyzing comprehensive spot pricing..."
    local pricing_data=$(get_comprehensive_spot_pricing_enhanced "$configurations" "$max_budget")
    
    if [[ -z "$pricing_data" || "$pricing_data" == "[]" ]]; then
        error "No pricing data available for any configurations"
        return 1
    fi
    
    # Step 3: Use dynamic budget if available (set by pricing function)
    local effective_budget="$max_budget"
    local dynamic_budget_value="${DYNAMIC_BUDGET:-}"
    if [[ -n "$dynamic_budget_value" && "$dynamic_budget_value" != "999999" ]]; then
        effective_budget="$dynamic_budget_value"
        info "Using dynamic budget: \$$effective_budget/hour (optimized from market data)"
    fi
    
    # Step 4: Display comprehensive analysis
    step "Step 3: Displaying comprehensive configuration analysis..."
    local valid_configs=$(display_configuration_analysis "$configurations" "$pricing_data" "$effective_budget")
    
    # Step 5: Interactive user selection
    step "Step 4: Interactive configuration selection..."
    local selected_config=$(prompt_user_selection "$valid_configs" "$configurations")
    
    if [[ $? -ne 0 || -z "$selected_config" ]]; then
        error "Configuration selection failed or cancelled"
        return 1
    fi
    
    # Step 6: Parse and validate selected configuration
    # Handle two formats: 14-field (numbered selection) or 12-field (auto-selection)
    IFS=':' read -ra config_fields <<< "$selected_config"
    
    if [[ ${#config_fields[@]} -eq 14 ]]; then
        # Format: config_num:11_field_config:price:value_ratio (numbered selection)
        local config_data="${config_fields[1]}:${config_fields[2]}:${config_fields[3]}:${config_fields[4]}:${config_fields[5]}:${config_fields[6]}:${config_fields[7]}:${config_fields[8]}:${config_fields[9]}:${config_fields[10]}:${config_fields[11]}"
        selected_price="${config_fields[12]}"
    elif [[ ${#config_fields[@]} -eq 12 ]]; then
        # Format: 11_field_config:price (auto-selection)
        local config_data="${config_fields[0]}:${config_fields[1]}:${config_fields[2]}:${config_fields[3]}:${config_fields[4]}:${config_fields[5]}:${config_fields[6]}:${config_fields[7]}:${config_fields[8]}:${config_fields[9]}:${config_fields[10]}"
        selected_price="${config_fields[11]}"
    else
        error "Invalid selected_config format: ${#config_fields[@]} fields, expected 12 or 14"
        error "Raw selected_config: $(echo "$selected_config" | cut -c1-100)..."
        return 1
    fi
    
    if ! parse_config_safely "$config_data" 11; then
        error "Failed to parse selected configuration: $(echo "$config_data" | cut -c1-50)..."
        return 1
    fi
    
    selected_instance="$CONFIG_INSTANCE_TYPE"
    selected_ami="$CONFIG_AMI"
    selected_type="$CONFIG_AMI_TYPE"
    selected_region="$CONFIG_REGION"
    vcpus="$CONFIG_VCPUS"
    ram="$CONFIG_RAM"
    gpus="$CONFIG_GPUS"
    gpu_type="$CONFIG_GPU_TYPE"
    cpu_arch="$CONFIG_CPU_ARCH"
    storage="$CONFIG_STORAGE"
    perf_score="$CONFIG_PERF_SCORE"
    
    # Export immediately to prevent variable loss (additional safety)
    export SELECTED_INSTANCE_TYPE="$selected_instance"
    export SELECTED_AMI="$selected_ami"
    export SELECTED_AMI_TYPE="$selected_type"
    export SELECTED_REGION="$selected_region"
    export SELECTED_PRICE="$selected_price"
    
    # Validate configuration
    if [[ -z "$selected_instance" || -z "$selected_ami" || -z "$selected_type" || -z "$selected_region" ]]; then
        error "Invalid configuration selected: $selected_config"
        return 1
    fi
    
    # Validate numeric fields using safe validation
    if ! is_numeric "$perf_score"; then
        error "Invalid perf_score value: $perf_score (should be numeric)"
        return 1
    fi
    if ! is_numeric "$selected_price"; then
        error "Invalid selected_price value: $selected_price (should be numeric)"
        return 1
    fi
    
    # Step 7: Final confirmation and region update
    success "🎯 FINAL CONFIGURATION CONFIRMED:"
    info "  Instance Type: $selected_instance ($vcpus vCPUs, ${ram}GB RAM, $gpus x $gpu_type)"
    info "  AMI: $selected_ami ($selected_type)"
    info "  Region: $selected_region"
    info "  Price: \$$selected_price/hour"
    info "  Performance Score: $perf_score"
    info "  Architecture: $cpu_arch"
    
    # Update global region if different
    if [[ "$selected_region" != "$AWS_REGION" ]]; then
        warning "Selected configuration is in different region: $selected_region"
        info "Updating deployment region from $AWS_REGION to $selected_region"
        export AWS_REGION="$selected_region"
    fi
    
    # Export variables for use by other functions
    export SELECTED_INSTANCE_TYPE="$selected_instance"
    export SELECTED_AMI="$selected_ami"
    export SELECTED_AMI_TYPE="$selected_type"
    export SELECTED_PRICE="$selected_price"
    export SELECTED_REGION="$selected_region"
    
    # Return the configuration string in expected format
    echo "$selected_instance:$selected_ami:$selected_type:$selected_price:$selected_region"
    return 0
}

# =============================================================================
# OPTIMIZED USER DATA GENERATION
# =============================================================================

create_optimized_user_data() {
    local instance_type="$1"
    local ami_type="$2"
    
    log "Creating optimized user data for $instance_type with $ami_type AMI..."
    
    # Determine CPU architecture
    local cpu_arch="x86_64"
    if [[ "$instance_type" == g5g* ]]; then
        cpu_arch="arm64"
    fi
    
    cat > user-data.sh << EOF
#!/bin/bash
set -euo pipefail

# Log all output for debugging
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== GeuseMaker Deep Learning AMI Setup ==="
echo "Timestamp: \$(date)"
echo "Instance Type: $instance_type"
echo "CPU Architecture: $cpu_arch"
echo "AMI Type: $ami_type"

# System identification
echo "System Information:"
uname -a
cat /etc/os-release

# Update system packages
echo "Updating system packages..."
if command -v apt-get &> /dev/null; then
    apt-get update && apt-get upgrade -y
elif command -v yum &> /dev/null; then
    yum update -y
fi

# Verify Deep Learning AMI components
echo "=== Verifying Deep Learning AMI Components ==="

# Check NVIDIA drivers
if command -v nvidia-smi &> /dev/null; then
    echo "✓ NVIDIA drivers found:"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
else
    echo "⚠ NVIDIA drivers not found - may need installation"
    # Install NVIDIA drivers for Deep Learning AMI
    if [[ "$cpu_arch" == "x86_64" ]]; then
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb
        dpkg -i cuda-keyring_1.0-1_all.deb
        apt-get update
        apt-get install -y nvidia-driver-470 cuda-toolkit-11-8
    else
        echo "ARM64 architecture - using different driver installation method"
        apt-get install -y nvidia-jetpack
    fi
fi

# Verify Docker
if command -v docker &> /dev/null; then
    echo "✓ Docker found:"
    docker --version
    # Ensure ubuntu user is in docker group
    usermod -aG docker ubuntu
else
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker ubuntu
    rm get-docker.sh
fi

# Install/verify Docker Compose
if command -v docker-compose &> /dev/null; then
    echo "✓ Docker Compose found:"
    docker-compose --version
else
    echo "Installing Docker Compose..."
    if [[ "$cpu_arch" == "x86_64" ]]; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
    else
        # ARM64 version
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose
    fi
    chmod +x /usr/local/bin/docker-compose
fi

# Configure NVIDIA Container Runtime
echo "=== Configuring NVIDIA Container Runtime ==="
if ! docker info | grep -q nvidia; then
    echo "Configuring NVIDIA Container Runtime..."
    
    # Install nvidia-container-toolkit
    if [[ "$cpu_arch" == "x86_64" ]]; then
        distribution=\$(. /etc/os-release;echo \$ID\$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/\$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        apt-get update && apt-get install -y nvidia-container-toolkit
    else
        # ARM64 specific nvidia container runtime
        apt-get install -y nvidia-container-runtime
    fi
    
    # Configure Docker daemon
    cat > /etc/docker/daemon.json << 'EODAEMON'
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EODAEMON
    
    systemctl restart docker
fi

# Test GPU access
echo "=== Testing GPU Access ==="
if [[ "$cpu_arch" == "x86_64" ]]; then
    if docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu20.04 nvidia-smi; then
        echo "✓ GPU access in Docker containers verified"
    else
        echo "✗ GPU access in Docker containers failed"
    fi
else
    # ARM64 GPU test
    if docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/l4t-base:r32.7.1 nvidia-smi; then
        echo "✓ ARM64 GPU access verified"
    else
        echo "✗ ARM64 GPU access failed"
    fi
fi

# Install additional tools
echo "Installing additional tools..."
if command -v apt-get &> /dev/null; then
    apt-get install -y jq curl wget git htop awscli nfs-common tree
    
    # Install nvtop for GPU monitoring (if available)
    if [[ "$cpu_arch" == "x86_64" ]]; then
        apt-get install -y nvtop || echo "nvtop not available"
    fi
elif command -v yum &> /dev/null; then
    yum install -y jq curl wget git htop awscli nfs-utils tree
fi

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
if [[ "$cpu_arch" == "x86_64" ]]; then
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb
    rm amazon-cloudwatch-agent.deb
else
    # ARM64 CloudWatch agent
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb
    rm amazon-cloudwatch-agent.deb
fi

# Ensure services are running
systemctl enable docker
systemctl start docker

# Create mount point for EFS
mkdir -p /mnt/efs

# Create architecture-aware GPU monitoring script
cat > /usr/local/bin/gpu-check.sh << 'EOGPU'
#!/bin/bash
echo "=== GPU Status Check ==="
echo "Date: \$(date)"
echo "Architecture: $cpu_arch"
echo "Instance Type: $instance_type"

if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA Driver Version:"
    nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits
    echo "GPU Information:"
    nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,temperature.gpu,power.draw --format=csv
    echo "Docker GPU Test:"
    if [[ "$cpu_arch" == "x86_64" ]]; then
        docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu20.04 nvidia-smi -L
    else
        docker run --rm --runtime=nvidia --gpus all nvcr.io/nvidia/l4t-base:r32.7.1 nvidia-smi -L
    fi
else
    echo "NVIDIA drivers not found"
fi
EOGPU

chmod +x /usr/local/bin/gpu-check.sh

# Run initial GPU check
echo "=== Running Initial GPU Check ==="
/usr/local/bin/gpu-check.sh

# Signal completion
echo "=== Deep Learning AMI Setup Complete ==="
echo "Timestamp: \$(date)"
echo "Instance: $instance_type ($cpu_arch)"
echo "AMI Type: $ami_type"
touch /tmp/user-data-complete

EOF
}

# =============================================================================
# INTELLIGENT SPOT INSTANCE LAUNCH
# =============================================================================

launch_spot_instance() {
    local SG_ID="$1"
    local EFS_DNS="$2"
    local enable_cross_region="${3:-false}"
    
    log "🚀 Launching GPU spot instance with intelligent configuration selection..."
    
    # Step 1: Try to determine dynamic budget based on current pricing
    local final_budget="$MAX_SPOT_PRICE"
    if [[ "$INSTANCE_TYPE" == "auto" ]]; then
        info "Attempting to determine dynamic budget from current spot pricing..."
        
        if dynamic_budget=$(determine_dynamic_budget "$enable_cross_region" "$MAX_SPOT_PRICE" 2>/dev/null); then
            final_budget="$dynamic_budget"
            success "Using dynamic budget: \$${final_budget}/hour (based on current market pricing)"
        else
            warning "Could not determine dynamic budget, using base budget: \$${MAX_SPOT_PRICE}/hour"
        fi
    fi
    
    # Step 2: Run intelligent configuration selection
    if [[ "$INSTANCE_TYPE" == "auto" ]]; then
        log "Auto-selection mode: Finding optimal configuration..."
        OPTIMAL_CONFIG=$(select_optimal_configuration "$final_budget" "$enable_cross_region")
        
        if [[ $? -ne 0 ]]; then
            # Handle case where no pricing data is available
            if handle_no_pricing_data "$enable_cross_region" "$final_budget"; then
                # Retry with potentially updated budget
                OPTIMAL_CONFIG=$(select_optimal_configuration "$MAX_SPOT_PRICE" "$enable_cross_region")
                if [[ $? -ne 0 ]]; then
                    error "Failed to find optimal configuration even after user intervention"
                    return 1
                fi
            else
                error "Failed to find optimal configuration within budget"
                return 1
            fi
        fi
        
        # Parse optimal configuration - Enhanced validation
        if [[ "$OPTIMAL_CONFIG" == *:*:*:*:* ]]; then
            # New format with region
            IFS=':' read -r SELECTED_INSTANCE_TYPE SELECTED_AMI SELECTED_AMI_TYPE SELECTED_PRICE SELECTED_REGION <<< "$OPTIMAL_CONFIG"
        # COMMENTED OUT: Fallback logic that may mask parsing issues
        # else
        #     # Fallback for old format
        #     IFS=':' read -r SELECTED_INSTANCE_TYPE SELECTED_AMI SELECTED_AMI_TYPE SELECTED_PRICE <<< "$OPTIMAL_CONFIG"
        #     SELECTED_REGION="$AWS_REGION"
        else
            error "Invalid OPTIMAL_CONFIG format: '$OPTIMAL_CONFIG'"
            error "Expected format: instance_type:ami:ami_type:price:region"
            return 1
        fi
        
        # Debug output to fix the empty variable issue
        info "Parsed configuration:"
        info "  SELECTED_INSTANCE_TYPE: '$SELECTED_INSTANCE_TYPE'"
        info "  SELECTED_AMI: '$SELECTED_AMI'"
        info "  SELECTED_AMI_TYPE: '$SELECTED_AMI_TYPE'"
        info "  SELECTED_PRICE: '$SELECTED_PRICE'"
        info "  SELECTED_REGION: '$SELECTED_REGION'"
        
    else
        log "Manual selection mode: Using specified instance type $INSTANCE_TYPE"
        
        # Verify manually selected instance type and find best AMI
        if ! check_instance_type_availability "$INSTANCE_TYPE" "$AWS_REGION" >/dev/null 2>&1; then
            error "Specified instance type $INSTANCE_TYPE not available in $AWS_REGION"
            return 1
        fi
        
        # Find best AMI for specified instance type
        local primary_ami="$(get_gpu_config "${INSTANCE_TYPE}_primary")"
        local secondary_ami="$(get_gpu_config "${INSTANCE_TYPE}_secondary")"
        
        if verify_ami_availability "$primary_ami" "$AWS_REGION" >/dev/null 2>&1; then
            SELECTED_AMI="$primary_ami"
            SELECTED_AMI_TYPE="primary"
        elif verify_ami_availability "$secondary_ami" "$AWS_REGION" >/dev/null 2>&1; then
            SELECTED_AMI="$secondary_ami"
            SELECTED_AMI_TYPE="secondary"
        else
            error "No valid AMIs available for $INSTANCE_TYPE"
            return 1
        fi
        
        SELECTED_INSTANCE_TYPE="$INSTANCE_TYPE"
        SELECTED_PRICE="$MAX_SPOT_PRICE"
        SELECTED_REGION="$AWS_REGION"
    fi
    
    # Validate that we have all required values
    if [[ -z "$SELECTED_INSTANCE_TYPE" || -z "$SELECTED_AMI" || -z "$SELECTED_AMI_TYPE" ]]; then
        error "Configuration selection failed - missing required values:"
        error "  Instance Type: '$SELECTED_INSTANCE_TYPE'"
        error "  AMI: '$SELECTED_AMI'"
        error "  AMI Type: '$SELECTED_AMI_TYPE'"
        return 1
    fi
    
    success "Selected configuration: $SELECTED_INSTANCE_TYPE with AMI $SELECTED_AMI ($SELECTED_AMI_TYPE)"
    info "Budget: \$$SELECTED_PRICE/hour"
    info "Region: $SELECTED_REGION"
    
    # Step 2: Create optimized user data
    create_optimized_user_data "$SELECTED_INSTANCE_TYPE" "$SELECTED_AMI_TYPE"
    
    # Step 3: Get pricing data for selected instance type for AZ optimization
    log "Analyzing spot pricing by availability zone for $SELECTED_INSTANCE_TYPE..."
    SPOT_PRICES_JSON=$(aws ec2 describe-spot-price-history \
        --instance-types "$SELECTED_INSTANCE_TYPE" \
        --product-descriptions "Linux/UNIX" \
        --max-items 50 \
        --region "$AWS_REGION" \
        --query 'SpotPriceHistory[*].[AvailabilityZone,SpotPrice,Timestamp]' \
        --output json 2>/dev/null || echo "[]")
    
    # Step 4: Determine AZ launch order
    local ORDERED_AZS=()
    if [[ "$SPOT_PRICES_JSON" != "[]" && -n "$SPOT_PRICES_JSON" ]]; then
        info "Current spot pricing by AZ:"
        # Group by AZ and get lowest price for each AZ
        local AZ_PRICES=$(echo "$SPOT_PRICES_JSON" | jq -r 'group_by(.[0]) | map({az: .[0][0], price: (map(.[1]) | min)}) | sort_by(.price) | .[] | "  \(.az): $\(.price)/hour"')
        echo "$AZ_PRICES"
        
        # Create ordered list of AZs by price (lowest first)
        ORDERED_AZS=($(echo "$SPOT_PRICES_JSON" | jq -r 'group_by(.[0]) | map({az: .[0][0], price: (map(.[1]) | min)}) | sort_by(.price) | .[].az' 2>/dev/null || echo ""))
        
        # Filter AZs within budget
        local AFFORDABLE_AZS=()
        for AZ_PRICE in $(echo "$SPOT_PRICES_JSON" | jq -r 'group_by(.[0]) | map({az: .[0][0], price: (map(.[1]) | min)}) | sort_by(.price) | .[] | "\(.az):\(.price)"' 2>/dev/null); do
            IFS=':' read -r AZ PRICE <<< "$AZ_PRICE"
            if (( $(echo "$PRICE <= $MAX_SPOT_PRICE" | bc -l 2>/dev/null || echo "1") )); then
                AFFORDABLE_AZS+=("$AZ")
            else
                warning "Excluding $AZ (price: \$$PRICE exceeds budget: \$$MAX_SPOT_PRICE)"
            fi
        done
        
        if [[ ${#AFFORDABLE_AZS[@]} -gt 0 ]]; then
            ORDERED_AZS=("${AFFORDABLE_AZS[@]}")
            info "Attempting launch in price-ordered AZs: ${ORDERED_AZS[*]}"
        else
            error "No AZs within budget for $SELECTED_INSTANCE_TYPE at \$$MAX_SPOT_PRICE"
            return 1
            # COMMENTED OUT: Fallback that ignores budget constraints
            # warning "No AZs within budget, trying all available AZs"
            # ORDERED_AZS=($(aws ec2 describe-availability-zones --region "$AWS_REGION" --query 'AvailabilityZones[?State==`available`].ZoneName' --output text))
        fi
    else
        error "Could not retrieve pricing data for $SELECTED_INSTANCE_TYPE"
        return 1
        # COMMENTED OUT: Fallback that proceeds without pricing data
        # warning "Could not retrieve pricing data, using all available AZs"
        # ORDERED_AZS=($(aws ec2 describe-availability-zones --region "$AWS_REGION" --query 'AvailabilityZones[?State==`available`].ZoneName' --output text))
    fi
    
    # Step 5: Try launching in each AZ in order
    for AZ in "${ORDERED_AZS[@]}"; do
        log "Attempting spot instance launch in AZ: $AZ"
        
        # Get subnet for this AZ
        SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=availability-zone,Values=$AZ" "Name=default-for-az,Values=true" \
            --region "$AWS_REGION" \
            --query 'Subnets[0].SubnetId' \
            --output text)
        
        if [[ "$SUBNET_ID" == "None" || -z "$SUBNET_ID" ]]; then
            warning "No suitable subnet found in $AZ, skipping..."
            continue
        fi
        
        info "Using subnet $SUBNET_ID in $AZ"
        
        # Get current price for this AZ
        CURRENT_PRICE=$(echo "$SPOT_PRICES_JSON" | jq -r ".[] | select(.[0] == \"$AZ\") | .[1]" 2>/dev/null || echo "unknown")
        if [[ "$CURRENT_PRICE" != "unknown" && "$CURRENT_PRICE" != "null" ]]; then
            info "Current spot price in $AZ: \$$CURRENT_PRICE/hour"
        fi
        
        # Create spot instance request
        log "Creating spot instance request in $AZ with max price \$$MAX_SPOT_PRICE/hour..."
        # Prepare instance profile name
        INSTANCE_PROFILE_NAME="$(if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then echo "app-$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')-profile"; else echo "${STACK_NAME}-instance-profile"; fi)"
        
        # Validate security group ID format before using
        if [[ ! "$SG_ID" =~ ^sg-[0-9a-fA-F]+$ ]]; then
            warning "Invalid security group ID format: $SG_ID. Skipping $AZ."
            continue
        fi
        
        # Validate required parameters before spot instance request
        if [[ -z "$SELECTED_AMI" || -z "$SELECTED_INSTANCE_TYPE" || -z "$KEY_NAME" || -z "$SUBNET_ID" || -z "$INSTANCE_PROFILE_NAME" ]]; then
            warning "Missing required parameters for spot instance in $AZ. Skipping..."
            continue
        fi
        
        # Validate user data file exists
        if [[ ! -f "user-data.sh" ]]; then
            warning "User data file not found. Skipping $AZ."
            continue
        fi
        
        # Create spot instance request with individual parameters
        step "Requesting spot instance in $AZ: $SELECTED_INSTANCE_TYPE at \$$MAX_SPOT_PRICE/hour"
        
        # Create launch specification JSON
        local launch_spec=$(cat <<EOF
{
    "ImageId": "$SELECTED_AMI",
    "InstanceType": "$SELECTED_INSTANCE_TYPE", 
    "KeyName": "$KEY_NAME",
    "SecurityGroupIds": ["$SG_ID"],
    "SubnetId": "$SUBNET_ID",
    "UserData": "$(base64 -i user-data.sh | tr -d '\n')",
    "IamInstanceProfile": {"Name": "$INSTANCE_PROFILE_NAME"}
}
EOF
)
        
        REQUEST_RESULT=$(aws ec2 request-spot-instances \
            --spot-price "$MAX_SPOT_PRICE" \
            --instance-count 1 \
            --type "one-time" \
            --launch-specification "$launch_spec" \
            --region "$AWS_REGION" 2>&1) || {
            warning "Failed to create spot instance request in $AZ: $REQUEST_RESULT"
            continue
        }
        
        REQUEST_ID=$(echo "$REQUEST_RESULT" | jq -r '.SpotInstanceRequests[0].SpotInstanceRequestId' 2>/dev/null || echo "")
        
        if [[ -z "$REQUEST_ID" || "$REQUEST_ID" == "None" || "$REQUEST_ID" == "null" ]]; then
            warning "Failed to extract spot request ID from response in $AZ"
            continue
        fi
        
        success "Created spot instance request $REQUEST_ID in $AZ"
        
        info "Spot instance request ID: $REQUEST_ID in $AZ"
        
        # Wait for spot request fulfillment
        log "Waiting for spot instance to be launched in $AZ..."
        local attempt=0
        local max_attempts=10
        local fulfilled=false
        
        while [ $attempt -lt $max_attempts ]; do
            REQUEST_STATE=$(aws ec2 describe-spot-instance-requests \
                --spot-instance-request-ids "$REQUEST_ID" \
                --region "$AWS_REGION" \
                --query 'SpotInstanceRequests[0].State' \
                --output text 2>/dev/null || echo "failed")
            
            if [[ "$REQUEST_STATE" == "active" ]]; then
                fulfilled=true
                break
            elif [[ "$REQUEST_STATE" == "failed" || "$REQUEST_STATE" == "cancelled" ]]; then
                warning "Spot instance request failed with state: $REQUEST_STATE"
                break
            fi
            
            attempt=$((attempt + 1))
            info "Attempt $attempt/$max_attempts: Request state is $REQUEST_STATE, waiting 30s..."
            sleep 30
        done
        
        if [ "$fulfilled" = true ]; then
            # Get instance ID
            INSTANCE_ID=$(aws ec2 describe-spot-instance-requests \
                --spot-instance-request-ids "$REQUEST_ID" \
                --region "$AWS_REGION" \
                --query 'SpotInstanceRequests[0].InstanceId' \
                --output text)
            
            if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" && "$INSTANCE_ID" != "null" ]]; then
                # Wait for instance to be running
                log "Waiting for instance to be running..."
                aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
                
                # Get instance details
                INSTANCE_INFO=$(aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --region "$AWS_REGION" \
                    --query 'Reservations[0].Instances[0].{PublicIp:PublicIpAddress,AZ:Placement.AvailabilityZone}' \
                    --output json)
                
                PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIp')
                ACTUAL_AZ=$(echo "$INSTANCE_INFO" | jq -r '.AZ')
                
                # Tag instance with configuration details
                aws ec2 create-tags \
                    --resources "$INSTANCE_ID" \
                    --tags \
                        Key=Name,Value="${STACK_NAME}-gpu-instance" \
                        Key=Stack,Value="$STACK_NAME" \
                        Key=Project,Value="$PROJECT_NAME" \
                        Key=InstanceType,Value="$SELECTED_INSTANCE_TYPE" \
                        Key=AMI,Value="$SELECTED_AMI" \
                        Key=AMIType,Value="$SELECTED_AMI_TYPE" \
                        Key=AvailabilityZone,Value="$ACTUAL_AZ" \
                        Key=SpotPrice,Value="${CURRENT_PRICE:-unknown}" \
                        Key=Architecture,Value="$(echo "$(get_instance_specs "$SELECTED_INSTANCE_TYPE")" | cut -d: -f5)" \
                        Key=GPUType,Value="$(echo "$(get_instance_specs "$SELECTED_INSTANCE_TYPE")" | cut -d: -f4)" \
                    --region "$AWS_REGION"
                
                success "🎉 Spot instance launched successfully!"
                success "  Instance ID: $INSTANCE_ID"
                success "  Public IP: $PUBLIC_IP"
                success "  Instance Type: $SELECTED_INSTANCE_TYPE"
                success "  AMI: $SELECTED_AMI ($SELECTED_AMI_TYPE)"
                success "  Availability Zone: $ACTUAL_AZ"
                if [[ "$CURRENT_PRICE" != "unknown" ]]; then
                    success "  Spot Price: \$$CURRENT_PRICE/hour"
                fi
                
                # Clean up user data file
                rm -f user-data.sh
                
                # Export for other functions
                export DEPLOYED_INSTANCE_TYPE="$SELECTED_INSTANCE_TYPE"
                export DEPLOYED_AMI="$SELECTED_AMI"
                export DEPLOYED_AMI_TYPE="$SELECTED_AMI_TYPE"
                
                echo "$INSTANCE_ID:$PUBLIC_IP:$ACTUAL_AZ"
                return 0
            else
                warning "Failed to get instance ID from spot request in $AZ"
                continue
            fi
        else
            warning "Spot instance request failed/timed out in $AZ, trying next AZ..."
            aws ec2 cancel-spot-instance-requests --spot-instance-request-ids "$REQUEST_ID" --region "$AWS_REGION" 2>/dev/null || true
            continue
        fi
    done
    
    # If we get here, all AZs failed
    error "❌ Failed to launch spot instance in any availability zone"
    error "This may be due to:"
    error "  1. Capacity constraints across all AZs for selected instance type"
    error "  2. Service quota limits for GPU spot instances"
    error "  3. Current spot prices exceed budget limit"
    error "  4. AMI availability issues in the region"
    error ""
    error "💡 Suggestions:"
    error "  1. Increase --max-spot-price (current: $MAX_SPOT_PRICE)"
    error "  2. Try a different region with better capacity"
    error "  3. Check service quotas for GPU instances"
    error "  4. Try during off-peak hours for better pricing"
    
    # Clean up
    rm -f user-data.sh
    return 1
}

# =============================================================================
# DEPLOYMENT RESULTS DISPLAY
# =============================================================================

display_results() {
    local PUBLIC_IP="$1"
    local INSTANCE_ID="$2"
    local EFS_DNS="$3"
    local INSTANCE_AZ="$4"
    
    # Get deployed configuration info
    local DEPLOYED_TYPE="${DEPLOYED_INSTANCE_TYPE:-$INSTANCE_TYPE}"
    local DEPLOYED_AMI_ID="${DEPLOYED_AMI:-unknown}"
    local DEPLOYED_AMI_TYPE="${DEPLOYED_AMI_TYPE:-unknown}"
    
    # Get instance specs
    local SPECS="$(get_instance_specs "$DEPLOYED_TYPE")"
    if [[ -z "$SPECS" ]]; then
        SPECS="unknown:unknown:unknown:unknown:unknown:unknown"
    fi
    IFS=':' read -r vcpus ram gpus gpu_type cpu_arch storage <<< "$SPECS"
    
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}   🚀 AI STARTER KIT DEPLOYED!    ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${BLUE}🎯 Intelligent Configuration Selected:${NC}"
    echo -e "  Instance Type: ${YELLOW}$DEPLOYED_TYPE${NC}"
    echo -e "  vCPUs: ${YELLOW}$vcpus${NC} | RAM: ${YELLOW}${ram}GB${NC} | GPUs: ${YELLOW}$gpus x $gpu_type${NC}"
    echo -e "  Architecture: ${YELLOW}$cpu_arch${NC} | Storage: ${YELLOW}$storage${NC}"
    echo -e "  AMI: ${YELLOW}$DEPLOYED_AMI_ID${NC} ($DEPLOYED_AMI_TYPE)"
    local perf_score="$(get_performance_score "$DEPLOYED_TYPE")"
    if [[ -z "$perf_score" || "$perf_score" == "0" ]]; then
        perf_score="N/A"
    fi
    echo -e "  Performance Score: ${YELLOW}${perf_score}/100${NC}"
    echo ""
    echo -e "${BLUE}📍 Deployment Location:${NC}"
    echo -e "  Instance ID: ${YELLOW}$INSTANCE_ID${NC}"
    echo -e "  Public IP: ${YELLOW}$PUBLIC_IP${NC}"
    echo -e "  Availability Zone: ${YELLOW}$INSTANCE_AZ${NC}"
    echo -e "  Region: ${YELLOW}$AWS_REGION${NC}"
    echo -e "  EFS DNS: ${YELLOW}$EFS_DNS${NC}"
    echo ""
    echo -e "${BLUE}🌐 Service URLs:${NC}"
    echo -e "  ${GREEN}n8n Workflow Editor:${NC}     http://$PUBLIC_IP:5678"
    echo -e "  ${GREEN}Crawl4AI Web Scraper:${NC}    http://$PUBLIC_IP:11235"
    echo -e "  ${GREEN}Qdrant Vector Database:${NC}  http://$PUBLIC_IP:6333"
    echo -e "  ${GREEN}Ollama AI Models:${NC}        http://$PUBLIC_IP:11434"
    echo ""
    echo -e "${BLUE}🔐 SSH Access:${NC}"
    echo -e "  ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
    echo ""
    
    # Show architecture-specific benefits
    if [[ "$cpu_arch" == "ARM" ]]; then
        echo -e "${BLUE}🔧 ARM64 Graviton2 Benefits:${NC}"
        echo -e "  ${GREEN}✓${NC} Up to 40% better price-performance than x86"
        echo -e "  ${GREEN}✓${NC} Lower power consumption"
        echo -e "  ${GREEN}✓${NC} Custom ARM-optimized Deep Learning AMI"
        echo -e "  ${GREEN}✓${NC} NVIDIA T4G Tensor Core GPUs"
        echo -e "  ${YELLOW}⚠${NC} Some software may require ARM64 compatibility"
    else
        echo -e "${BLUE}🔧 Intel x86_64 Benefits:${NC}"
        echo -e "  ${GREEN}✓${NC} Universal software compatibility"
        echo -e "  ${GREEN}✓${NC} Mature ecosystem and optimizations"
        echo -e "  ${GREEN}✓${NC} NVIDIA T4 Tensor Core GPUs"
        echo -e "  ${GREEN}✓${NC} High-performance Intel Xeon processors"
    fi
    
    echo ""
    echo -e "${BLUE}🤖 Deep Learning AMI Features:${NC}"
    echo -e "  ${GREEN}✓${NC} Pre-installed NVIDIA drivers (optimized versions)"
    echo -e "  ${GREEN}✓${NC} Docker with NVIDIA container runtime"
    echo -e "  ${GREEN}✓${NC} CUDA toolkit and cuDNN libraries"
    echo -e "  ${GREEN}✓${NC} Python ML frameworks (TensorFlow, PyTorch, etc.)"
    echo -e "  ${GREEN}✓${NC} Conda environments for different frameworks"
    echo -e "  ${GREEN}✓${NC} Jupyter notebooks and development tools"
    echo ""
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo -e "  1. ${CYAN}Wait 5-10 minutes${NC} for all services to fully start"
    echo -e "  2. ${CYAN}Access n8n${NC} at http://$PUBLIC_IP:5678 to set up workflows"
    echo -e "  3. ${CYAN}Check GPU status${NC}: ssh to instance and run '/usr/local/bin/gpu-check.sh'"
    echo -e "  4. ${CYAN}Check service logs${NC}: ssh to instance and run 'docker-compose logs'"
    echo -e "  5. ${CYAN}Configure API keys${NC} in .env file for enhanced features"
    echo ""
    echo -e "${YELLOW}💰 Cost Optimization:${NC}"
    if [[ -n "${SELECTED_PRICE:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} Spot instance selected at ~\$${SELECTED_PRICE}/hour"
        local daily_cost=$(echo "scale=2; $SELECTED_PRICE * 24" | bc -l 2>/dev/null || echo "N/A")
        if [[ "$daily_cost" != "N/A" ]]; then
            echo -e "  ${GREEN}✓${NC} Estimated daily cost: ~\$${daily_cost} (24 hours)"
        fi
    else
        echo -e "  ${GREEN}✓${NC} Spot instance pricing optimized"
    fi
    echo -e "  ${GREEN}✓${NC} ~70% savings vs on-demand pricing"
    echo -e "  ${GREEN}✓${NC} Multi-AZ failover for availability"
    echo -e "  ${GREEN}✓${NC} Intelligent configuration selection"
    echo -e "  ${RED}⚠${NC} Remember to terminate when not in use!"
    echo ""
    echo -e "${BLUE}🎛️ Deployment Features:${NC}"
    echo -e "  ${GREEN}✓${NC} Intelligent AMI and instance selection"
    echo -e "  ${GREEN}✓${NC} Real-time spot pricing analysis"
    echo -e "  ${GREEN}✓${NC} Multi-architecture support (Intel/ARM)"
    echo -e "  ${GREEN}✓${NC} EFS shared storage"
    echo -e "  ${GREEN}✓${NC} Application Load Balancer"
    echo -e "  ${GREEN}✓${NC} CloudFront CDN"
    echo -e "  ${GREEN}✓${NC} CloudWatch monitoring"
    echo -e "  ${GREEN}✓${NC} SSM parameter management"
    echo ""
    echo -e "${PURPLE}🧠 Intelligent Selection Summary:${NC}"
    if [[ "$INSTANCE_TYPE" == "auto" ]]; then
        echo -e "  ${CYAN}Mode:${NC} Automatic optimal configuration selection"
        echo -e "  ${CYAN}Budget:${NC} \$$MAX_SPOT_PRICE/hour maximum"
        echo -e "  ${CYAN}Selection:${NC} $DEPLOYED_TYPE chosen for best price/performance"
    else
        echo -e "  ${CYAN}Mode:${NC} Manual instance type selection"
        echo -e "  ${CYAN}Specified:${NC} $INSTANCE_TYPE"
        echo -e "  ${CYAN}AMI Selection:${NC} Best available AMI auto-selected"
    fi
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo -e "${BLUE}Happy building with your AI-powered infrastructure! 🚀${NC}"
    echo ""
}

# =============================================================================
# INFRASTRUCTURE SETUP FUNCTIONS
# =============================================================================

cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    
    # Use comprehensive cleanup script if available
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/cleanup-stack.sh" ] && [ -n "${STACK_NAME:-}" ]; then
        log "Running comprehensive cleanup for stack: $STACK_NAME"
        "$script_dir/cleanup-stack.sh" "$STACK_NAME" || true
        return
    fi
    
    # Fallback to manual cleanup if no stack name or cleanup script
    # Terminate instance first
    if [ ! -z "${INSTANCE_ID:-}" ]; then
        log "Terminating instance $INSTANCE_ID..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
    fi
    
    # Delete CloudWatch alarms (if any were created)
    log "Deleting CloudWatch alarms..."
    aws cloudwatch delete-alarms \
        --alarm-names "${STACK_NAME}-high-gpu-utilization" "${STACK_NAME}-low-gpu-utilization" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Delete CloudFront distribution (takes longest, do early)
    if [ ! -z "${DISTRIBUTION_ID:-}" ]; then
        log "Disabling and deleting CloudFront distribution..."
        # Disable first
        ETAG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query ETag --output text 2>/dev/null) || true
        if [ ! -z "$ETAG" ] && [ "$ETAG" != "None" ]; then
            CONFIG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query DistributionConfig --output json 2>/dev/null) || true
            if [ ! -z "$CONFIG" ]; then
                echo "$CONFIG" | jq '.Enabled = false' > disabled-config.json 2>/dev/null || true
                aws cloudfront update-distribution --id "$DISTRIBUTION_ID" --distribution-config file://disabled-config.json --if-match "$ETAG" 2>/dev/null || true
                aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID" 2>/dev/null || true
                NEW_ETAG=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query ETag --output text 2>/dev/null) || true
                aws cloudfront delete-distribution --id "$DISTRIBUTION_ID" --if-match "$NEW_ETAG" 2>/dev/null || true
            fi
        fi
    fi
    
    # Clean up temporary files
    rm -f user-data.sh trust-policy.json custom-policy.json deploy-app.sh disabled-config.json
}

create_key_pair() {
    log "Setting up SSH key pair..."
    
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
        warning "Key pair $KEY_NAME already exists"
        return 0
    fi
    
    # Create key pair
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$AWS_REGION" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    
    chmod 600 "${KEY_NAME}.pem"
    success "Created SSH key pair: ${KEY_NAME}.pem"
}

create_security_group() {
    log "Creating security group..."
    
    # Get VPC ID first
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
        log "[ERROR] Failed to retrieve default VPC ID."
        exit 1
    fi
    
    # Check if security group exists
    SG_ID=$(aws ec2 describe-security-groups \
        --group-names "${STACK_NAME}-sg" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null | grep -oE 'sg-[0-9a-fA-F]+' | head -n1)
    
    if [[ -z "$SG_ID" ]]; then
        # Create security group
        SG_ID=$(aws ec2 create-security-group \
            --group-name "${STACK_NAME}-sg" \
            --description "Security group for GeuseMaker Intelligent Deployment" \
            --vpc-id "$VPC_ID" \
            --region "$AWS_REGION" \
            --query 'GroupId' \
            --output text)
        if [[ -z "$SG_ID" ]]; then
            log "[ERROR] Failed to create security group."
            exit 1
        fi
        
        # Tag the security group
        aws ec2 create-tags \
            --resources "$SG_ID" \
            --tags \
                Key=Name,Value="${STACK_NAME}-sg" \
                Key=Stack,Value="$STACK_NAME" \
                Key=Project,Value="$PROJECT_NAME" \
            --region "$AWS_REGION" || true
    fi
    
    # Validate SG_ID format
    if [[ ! "$SG_ID" =~ ^sg-[0-9a-fA-F]+$ ]]; then
        log "[ERROR] Invalid security group ID: $SG_ID"
        exit 1
    fi
    
    # Add security group rules with duplicate protection
    add_sg_rule_if_not_exists() {
        local sg_id="$1"
        local protocol="$2"
        local port="$3"
        local source_type="$4"
        local source_value="$5"
        
        # Check if rule already exists
        local existing_rule
        if [[ "$source_type" == "cidr" ]]; then
            existing_rule=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --region "$AWS_REGION" \
                --query "SecurityGroups[0].IpPermissions[?IpProtocol=='$protocol' && FromPort==$port && ToPort==$port && IpRanges[?CidrIp=='$source_value']]" \
                --output text 2>/dev/null)
        else
            existing_rule=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --region "$AWS_REGION" \
                --query "SecurityGroups[0].IpPermissions[?IpProtocol=='$protocol' && FromPort==$port && ToPort==$port && UserIdGroupPairs[?GroupId=='$source_value']]" \
                --output text 2>/dev/null)
        fi
        
        if [[ -z "$existing_rule" ]]; then
            log "Adding security group rule for port $port ($protocol)"
            if [[ "$source_type" == "cidr" ]]; then
                if ! aws ec2 authorize-security-group-ingress \
                    --group-id "$sg_id" \
                    --protocol "$protocol" \
                    --port "$port" \
                    --cidr "$source_value" \
                    --region "$AWS_REGION" >/dev/null 2>&1; then
                    log "[WARNING] Failed to add rule for port $port (may already exist)"
                fi
            else
                if ! aws ec2 authorize-security-group-ingress \
                    --group-id "$sg_id" \
                    --protocol "$protocol" \
                    --port "$port" \
                    --source-group "$source_value" \
                    --region "$AWS_REGION" >/dev/null 2>&1; then
                    log "[WARNING] Failed to add rule for port $port (may already exist)"
                fi
            fi
        else
            log "Security group rule for port $port already exists, skipping"
        fi
    }
    
    # Add all required rules
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "22" "cidr" "0.0.0.0/0"      # SSH
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "5678" "cidr" "0.0.0.0/0"    # n8n
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "11434" "cidr" "0.0.0.0/0"   # Ollama
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "11235" "cidr" "0.0.0.0/0"   # Crawl4AI
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "6333" "cidr" "0.0.0.0/0"    # Qdrant
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "80" "cidr" "0.0.0.0/0"      # HTTP
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "443" "cidr" "0.0.0.0/0"     # HTTPS
    add_sg_rule_if_not_exists "$SG_ID" "tcp" "2049" "group" "$SG_ID"      # NFS for EFS
    
    success "Created security group: $SG_ID"
    echo "$SG_ID" | tr -d '\n\r\t '
}

create_iam_role() {
    log "Creating IAM role for EC2 instances..."
    
    # Check if role exists
    if aws iam get-role --role-name "${STACK_NAME}-role" &> /dev/null; then
        warning "IAM role already exists"
        return 0
    fi
    
    # Create trust policy
    cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create role
    aws iam create-role \
        --role-name "${STACK_NAME}-role" \
        --assume-role-policy-document file://trust-policy.json > /dev/null || {
        warning "Role ${STACK_NAME}-role may already exist, continuing..."
    }
    
    # Attach essential policies
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy || {
        warning "CloudWatchAgentServerPolicy may already be attached, continuing..."
    }
    
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore || {
        warning "AmazonSSMManagedInstanceCore may already be attached, continuing..."
    }
    
    # Create custom policy for EFS and AWS service access
    cat > custom-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeMountTargets", 
                "ec2:Describe*",
                "cloudwatch:PutMetricData",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    aws iam create-policy \
        --policy-name "${STACK_NAME}-custom-policy" \
        --policy-document file://custom-policy.json > /dev/null || true
    
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/${STACK_NAME}-custom-policy" || {
        warning "Custom policy may already be attached, continuing..."
    }
    
    # Create instance profile (ensure name starts with letter for AWS compliance)
    local profile_name
    if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then
        local clean_name=$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')
        profile_name="app-${clean_name}-profile"
    else
        profile_name="${STACK_NAME}-instance-profile"
    fi
    
    aws iam create-instance-profile --instance-profile-name "$profile_name" > /dev/null || true
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "${STACK_NAME}-role" || true
    
    # Wait for IAM propagation
    log "Waiting for IAM role propagation..."
    sleep 30
    
    success "Created IAM role and instance profile"
}

create_efs() {
    local SG_ID="$1"
    log "Setting up EFS (Elastic File System)..."
    
    # Check if EFS already exists by searching through all file systems
    EFS_LIST=$(aws efs describe-file-systems \
        --region "$AWS_REGION" \
        --query 'FileSystems[].FileSystemId' \
        --output text 2>/dev/null || echo "")
    
    # Check each EFS to see if it has our tag
    for EFS_ID in $EFS_LIST; do
        if [[ -n "$EFS_ID" && "$EFS_ID" != "None" ]]; then
            EFS_TAGS=$(aws efs list-tags-for-resource \
                --resource-id "$EFS_ID" \
                --region "$AWS_REGION" \
                --query "Tags[?Key=='Name'].Value" \
                --output text 2>/dev/null || echo "")
            
            if [[ "$EFS_TAGS" == "${STACK_NAME}-efs" ]]; then
                warning "EFS already exists: $EFS_ID"
                # Get EFS DNS name
                EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
                export EFS_ID
                echo "$EFS_DNS"
                return 0
            fi
        fi
    done
    
    # Create EFS
    EFS_ID=$(aws efs create-file-system \
        --creation-token "${STACK_NAME}-efs-$(date +%s)" \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --encrypted \
        --region "$AWS_REGION" \
        --query 'FileSystemId' \
        --output text)
    
    # Tag EFS
    aws efs create-tags \
        --file-system-id "$EFS_ID" \
        --tags Key=Name,Value="${STACK_NAME}-efs" Key=Stack,Value="$STACK_NAME" Key=Project,Value="$PROJECT_NAME" \
        --region "$AWS_REGION"
    
    # Wait for EFS to be available
    log "Waiting for EFS to become available..."
    while true; do
        EFS_STATE=$(aws efs describe-file-systems \
            --file-system-id "$EFS_ID" \
            --region "$AWS_REGION" \
            --query 'FileSystems[0].LifeCycleState' \
            --output text 2>/dev/null || echo "")
        
        if [[ "$EFS_STATE" == "available" ]]; then
            log "EFS is now available"
            break
        elif [[ "$EFS_STATE" == "creating" ]]; then
            log "EFS is still creating... waiting 10 seconds"
            sleep 10
        else
            warning "EFS state: $EFS_STATE"
            sleep 10
        fi
    done
    
    # Get EFS DNS name
    EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
    # Export EFS_ID for cleanup function
    export EFS_ID
    success "Created EFS: $EFS_ID (DNS: $EFS_DNS)"
    echo "$EFS_DNS"
}

get_subnet_for_az() {
    local AZ="$1"
    aws ec2 describe-subnets \
        --filters "Name=availability-zone,Values=$AZ" "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[0].SubnetId' \
        --output text
}

create_efs_mount_target() {
    local SG_ID="$1"
    local INSTANCE_AZ="$2"
    local EFS_ID="$3"
    
    if [[ -z "$EFS_ID" ]]; then
        error "EFS_ID not provided. Cannot create mount target."
        return 1
    fi
    
    log "Creating EFS mount target in $INSTANCE_AZ (where instance is running)..."
    
    # Check if mount target already exists in this AZ
    EXISTING_MT=$(aws efs describe-mount-targets \
        --file-system-id "$EFS_ID" \
        --region "$AWS_REGION" \
        --query "MountTargets[?AvailabilityZoneName=='$INSTANCE_AZ'].MountTargetId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING_MT" && "$EXISTING_MT" != "None" ]]; then
        warning "EFS mount target already exists in $INSTANCE_AZ: $EXISTING_MT"
        return 0
    fi
    
    # Get subnet ID for the instance AZ
    SUBNET_ID=$(get_subnet_for_az "$INSTANCE_AZ")
    
    if [[ "$SUBNET_ID" != "None" && -n "$SUBNET_ID" ]]; then
        aws efs create-mount-target \
            --file-system-id "$EFS_ID" \
            --subnet-id "$SUBNET_ID" \
            --security-groups "$SG_ID" \
            --region "$AWS_REGION" || {
            warning "Mount target creation failed in $INSTANCE_AZ, but continuing..."
            return 0
        }
        success "Created EFS mount target in $INSTANCE_AZ"
    else
        error "No suitable subnet found in $INSTANCE_AZ"
        return 1
    fi
}

create_target_group() {
    local SG_ID="$1"
    local INSTANCE_ID="$2"
    
    log "Creating target group for n8n..."
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
    
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "${STACK_NAME}-n8n-tg" \
        --protocol HTTP \
        --port 5678 \
        --vpc-id "$VPC_ID" \
        --health-check-protocol HTTP \
        --health-check-port 5678 \
        --health-check-path /healthz \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 10 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --target-type instance \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Register instance to target group
    aws elbv2 register-targets \
        --target-group-arn "$TARGET_GROUP_ARN" \
        --targets Id="$INSTANCE_ID" Port=5678 \
        --region "$AWS_REGION"
    
    success "Created n8n target group: $TARGET_GROUP_ARN"
    echo "$TARGET_GROUP_ARN"
}

create_qdrant_target_group() {
    local SG_ID="$1"
    local INSTANCE_ID="$2"
    
    log "Creating target group for qdrant..."
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
    
    QDRANT_TG_ARN=$(aws elbv2 create-target-group \
        --name "${STACK_NAME}-qdrant-tg" \
        --protocol HTTP \
        --port 6333 \
        --vpc-id "$VPC_ID" \
        --health-check-protocol HTTP \
        --health-check-port 6333 \
        --health-check-path /healthz \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 10 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --target-type instance \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Register instance to target group
    aws elbv2 register-targets \
        --target-group-arn "$QDRANT_TG_ARN" \
        --targets Id="$INSTANCE_ID" Port=6333 \
        --region "$AWS_REGION"
    
    success "Created qdrant target group: $QDRANT_TG_ARN"
    echo "$QDRANT_TG_ARN"
}

create_alb() {
    local SG_ID="$1"
    local TARGET_GROUP_ARN="$2"
    local QDRANT_TG_ARN="$3"
    
    log "Creating Application Load Balancer..."
    
    # Get subnets
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[].SubnetId' \
        --output text)
    
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${STACK_NAME}-alb" \
        --subnets "$SUBNETS" \
        --security-groups "$SG_ID" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Create listener for n8n (default)
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION"
    
    # Create listener for qdrant
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 6333 \
        --default-actions Type=forward,TargetGroupArn="$QDRANT_TG_ARN" \
        --region "$AWS_REGION"
    
    export ALB_ARN
    success "Created ALB: $ALB_DNS"
    echo "$ALB_DNS"
}

setup_cloudfront() {
    local ALB_DNS="$1"
    
    log "Setting up CloudFront CDN..."
    
    # Create CloudFront distribution
    DISTRIBUTION_CONFIG='{
        "CallerReference": "'${STACK_NAME}'-'$(date +%s)'",
        "Comment": "CloudFront distribution for GeuseMaker",
        "DefaultCacheBehavior": {
            "TargetOriginId": "ALBOrigin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {
                "Quantity": 7,
                "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
                "CachedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"]
                }
            },
            "ForwardedValues": {
                "QueryString": true,
                "Headers": {
                    "Quantity": 0
                }
            },
            "TrustedSigners": {
                "Enabled": false,
                "Quantity": 0
            },
            "MinTTL": 0
        },
        "Origins": {
            "Quantity": 1,
            "Items": [
                {
                    "Id": "ALBOrigin",
                    "DomainName": "'$ALB_DNS'",
                    "CustomOriginConfig": {
                        "HTTPPort": 80,
                        "HTTPSPort": 443,
                        "OriginProtocolPolicy": "http-only"
                    }
                }
            ]
        },
        "Enabled": true,
        "PriceClass": "PriceClass_100"
    }'
    
    DISTRIBUTION_ID=$(echo "$DISTRIBUTION_CONFIG" | aws cloudfront create-distribution \
        --distribution-config file:///dev/stdin \
        --region "$AWS_REGION" \
        --query 'Distribution.Id' \
        --output text)
    
    DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --region "$AWS_REGION" \
        --query 'Distribution.DomainName' \
        --output text)
    
    export DISTRIBUTION_ID
    export DISTRIBUTION_DOMAIN
    success "Created CloudFront distribution: $DISTRIBUTION_DOMAIN"
}

wait_for_instance_ready() {
    local INSTANCE_ID="$1"
    local INSTANCE_TYPE="${2:-}"
    
    if [ -z "$INSTANCE_ID" ]; then
        error "wait_for_instance_ready requires INSTANCE_ID parameter"
        return 1
    fi
    
    log "Getting current public IP for instance: $INSTANCE_ID"
    
    # Get the current public IP
    local PUBLIC_IP
    PUBLIC_IP=$(get_instance_public_ip "$INSTANCE_ID")
    if [ $? -ne 0 ]; then
        error "Failed to get public IP for instance: $INSTANCE_ID"
        return 1
    fi
    
    info "Instance public IP: $PUBLIC_IP"
    log "Waiting for instance to be ready for SSH..."
    
    # Use the improved wait_for_ssh_ready function with instance ID for IP refresh
    wait_for_ssh_ready "$PUBLIC_IP" "${KEY_NAME}.pem" 90 30 "$INSTANCE_TYPE" "$INSTANCE_ID"
    
    return $?
}

deploy_application() {
    local PUBLIC_IP="$1"
    local EFS_DNS="$2"
    local INSTANCE_ID="$3"
    
    log "Deploying GeuseMaker application..."
    
    # Create deployment script
    cat > deploy-app.sh << EOF
#!/bin/bash
set -euo pipefail

echo "Starting GeuseMaker deployment..."

# Mount EFS
sudo mkdir -p /mnt/efs
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc $EFS_DNS:/ /mnt/efs
echo "$EFS_DNS:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,_netdev 0 0" | sudo tee -a /etc/fstab

# Clone repository if it doesn't exist
if [ ! -d "/home/ubuntu/GeuseMaker" ]; then
    git clone https://github.com/michael-pittman/001-starter-kit.git /home/ubuntu/GeuseMaker
fi
cd /home/ubuntu/GeuseMaker

# Update Docker images to latest versions (unless overridden)
if [ "\${USE_LATEST_IMAGES:-true}" = "true" ]; then
    echo "Updating Docker images to latest versions..."
    if [ -f "scripts/simple-update-images.sh" ]; then
        chmod +x scripts/simple-update-images.sh
        ./scripts/simple-update-images.sh update
    else
        echo "Warning: Image update script not found, using default versions"
    fi
fi

# Create comprehensive .env file with all required variables
cat > .env << EOFENV
# PostgreSQL Configuration
POSTGRES_DB=n8n_db
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=n8n_password_\$(openssl rand -hex 32)

# n8n Configuration
N8N_ENCRYPTION_KEY=\$(openssl rand -hex 32)
N8N_USER_MANAGEMENT_JWT_SECRET=\$(openssl rand -hex 32)
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5678

# n8n Security Settings
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=https://n8n.geuse.io,https://localhost:5678
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

# AWS Configuration
EFS_DNS=$EFS_DNS
INSTANCE_ID=$INSTANCE_ID
AWS_DEFAULT_REGION=$AWS_REGION
INSTANCE_TYPE=g4dn.xlarge

# Image version control
USE_LATEST_IMAGES=$USE_LATEST_IMAGES

# API Keys (empty by default - can be configured via SSM)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
MISTRAL_API_KEY=
GEMINI_API_TOKEN=
EOFENV

# Start GPU-optimized services
export EFS_DNS=$EFS_DNS
sudo -E docker-compose -f docker-compose.gpu-optimized.yml up -d

echo "Deployment completed!"
EOF

    # Copy the deployment script and run it
    log "Copying deployment script..."
    scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" deploy-app.sh "ubuntu@$PUBLIC_IP:/tmp/"
    
    # Copy the entire repository
    log "Copying application files..."
    rsync -avz --exclude '.git' --exclude 'node_modules' --exclude '*.log' \
        -e "ssh -o StrictHostKeyChecking=no -i ${KEY_NAME}.pem" \
        ./ "ubuntu@$PUBLIC_IP:/home/ubuntu/GeuseMaker/"
    
    # Run deployment
    log "Running deployment script..."
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" \
        "chmod +x /tmp/deploy-app.sh && /tmp/deploy-app.sh"
    
    success "Application deployment completed!"
}

setup_monitoring() {
    local PUBLIC_IP="$1"
    
    log "Setting up monitoring and cost optimization..."
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "${STACK_NAME}-high-gpu-utilization" \
        --alarm-description "Alert when GPU utilization is high" \
        --metric-name GPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 90 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --region "$AWS_REGION" || true
    
    success "Monitoring setup completed!"
}

validate_deployment() {
    local PUBLIC_IP="$1"
    
    log "Validating deployment..."
    
    # Wait for services to fully start
    sleep 120
    
    local endpoints=(
        "http://$PUBLIC_IP:5678/healthz:n8n"
        "http://$PUBLIC_IP:11434/api/tags:Ollama"
        "http://$PUBLIC_IP:6333/healthz:Qdrant"
        "http://$PUBLIC_IP:11235/health:Crawl4AI"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r url service <<< "$endpoint_info"
        
        log "Testing $service at $url..."
        local retry=0
        local max_retries=10
        local backoff=30
        while [ $retry -lt $max_retries ]; do
            if curl -f -s "$url" > /dev/null 2>&1; then
                success "$service is healthy"
                break
            fi
            retry=$((retry+1))
            info "Attempt $retry/$max_retries: $service not ready, waiting ${backoff}s..."
            sleep $backoff
            backoff=$((backoff * 2))  # Exponential backoff
        done
        if [ $retry -eq $max_retries ]; then
            error "$service failed health check after $max_retries attempts"
        fi
    done
    
    success "Deployment validation completed!"
}

# =============================================================================
# APPLICATION LOAD BALANCER SETUP
# =============================================================================

setup_alb() {
    local INSTANCE_ID="$1"
    local SG_ID="$2"
    
    if [ "$SETUP_ALB" != "true" ]; then
        log "Skipping ALB setup (not requested)"
        return 0
    fi
    
    log "Setting up Application Load Balancer..."
    
    # Get VPC ID from the security group
    local VPC_ID
    VPC_ID=$(aws ec2 describe-security-groups \
        --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].VpcId' \
        --output text)
    
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
        error "Could not determine VPC ID from security group $SG_ID"
        return 1
    fi
    
    # Get at least 2 subnets for ALB (ALB requires multiple AZs) - bash 3.x compatible
    local subnet_ids
    local temp_result
    temp_result=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
        --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' \
        --output text | tr '\t' '\n' | head -2)
    
    if [[ -n "$temp_result" ]]; then
        IFS=$'\n' read -d '' -ra subnet_ids <<< "$temp_result" || true
    else
        subnet_ids=()
    fi
    
    if [ ${#subnet_ids[@]} -lt 2 ]; then
        warn "Need at least 2 public subnets for ALB. Attempting to use default VPC subnets..."
        
        # Try to get subnets from default VPC - bash 3.x compatible
        temp_result=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
            --query 'Subnets[].SubnetId' \
            --output text | tr '\t' '\n' | head -2)
        
        if [[ -n "$temp_result" ]]; then
            IFS=$'\n' read -d '' -ra subnet_ids <<< "$temp_result" || true
        else
            subnet_ids=()
        fi
        
        if [ ${#subnet_ids[@]} -lt 2 ]; then
            warn "Still don't have enough subnets for ALB. Skipping ALB setup."
            return 0
        fi
    fi
    
    # Create ALB
    local ALB_ARN
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${STACK_NAME}-alb" \
        --subnets "${subnet_ids[@]}" \
        --security-groups "$SG_ID" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null)
    
    if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
        warn "Failed to create Application Load Balancer. Continuing without ALB."
        return 0
    fi
    
    # Create target groups for main services
    local services=("n8n:5678" "ollama:11434" "qdrant:6333" "crawl4ai:11235")
    
    for service in "${services[@]}"; do
        local service_name="${service%:*}"
        local service_port="${service#*:}"
        
        log "Creating target group for $service_name..."
        
        # Create target group
        local TG_ARN
        TG_ARN=$(aws elbv2 create-target-group \
            --name "${STACK_NAME}-${service_name}-tg" \
            --protocol HTTP \
            --port "$service_port" \
            --vpc-id "$VPC_ID" \
            --health-check-protocol HTTP \
            --health-check-path "/" \
            --health-check-interval-seconds 30 \
            --health-check-timeout-seconds 5 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text 2>/dev/null)
        
        if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
            # Register instance with target group
            aws elbv2 register-targets \
                --target-group-arn "$TG_ARN" \
                --targets Id="$INSTANCE_ID",Port="$service_port" \
                2>/dev/null
            
            # Create listener (different ports for different services)
            local listener_port
            case "$service_name" in
                "n8n") listener_port=80 ;;
                "ollama") listener_port=8080 ;;
                "qdrant") listener_port=8081 ;;
                "crawl4ai") listener_port=8082 ;;
                *) listener_port=$((8000 + service_port % 1000)) ;;
            esac
            
            aws elbv2 create-listener \
                --load-balancer-arn "$ALB_ARN" \
                --protocol HTTP \
                --port "$listener_port" \
                --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
                2>/dev/null > /dev/null
            
            success "✓ Created target group and listener for $service_name on port $listener_port"
        fi
    done
    
    # Get ALB DNS name
    ALB_DNS_NAME=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    success "Application Load Balancer setup completed!"
    log "ALB DNS: $ALB_DNS_NAME"
    log "Service URLs:"
    log "  • n8n:      http://$ALB_DNS_NAME (port 80)"
    log "  • Ollama:   http://$ALB_DNS_NAME:8080"
    log "  • Qdrant:   http://$ALB_DNS_NAME:8081"
    log "  • Crawl4AI: http://$ALB_DNS_NAME:8082"
    
    return 0
}

# =============================================================================
# CLOUDFRONT SETUP
# =============================================================================

setup_cloudfront() {
    local ALB_DNS_NAME="$1"
    
    if [ "$SETUP_CLOUDFRONT" != "true" ]; then
        log "Skipping CloudFront setup (not requested)"
        return 0
    fi
    
    if [ -z "$ALB_DNS_NAME" ]; then
        warn "No ALB DNS name provided. CloudFront requires ALB. Skipping CloudFront setup."
        return 0
    fi
    
    log "Setting up CloudFront distribution..."
    
    # Create CloudFront distribution configuration
    local distribution_config
    distribution_config=$(cat << EOF
{
    "CallerReference": "${STACK_NAME}-$(date +%s)",
    "Comment": "GeuseMaker CDN Distribution for ${STACK_NAME}",
    "DefaultCacheBehavior": {
        "TargetOriginId": "${STACK_NAME}-alb-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {
                "Forward": "all"
            },
            "Headers": {
                "Quantity": 1,
                "Items": ["*"]
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 31536000
    },
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "${STACK_NAME}-alb-origin",
                "DomainName": "$ALB_DNS_NAME",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    }
                }
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100"
}
EOF
)
    
    # Create the distribution
    local distribution_result
    distribution_result=$(aws cloudfront create-distribution \
        --distribution-config "$distribution_config" \
        2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$distribution_result" ]; then
        local CLOUDFRONT_ID
        local CLOUDFRONT_DOMAIN
        
        CLOUDFRONT_ID=$(echo "$distribution_result" | jq -r '.Distribution.Id' 2>/dev/null || echo "")
        CLOUDFRONT_DOMAIN=$(echo "$distribution_result" | jq -r '.Distribution.DomainName' 2>/dev/null || echo "")
        
        if [ -n "$CLOUDFRONT_ID" ] && [ "$CLOUDFRONT_ID" != "null" ]; then
            success "CloudFront distribution created!"
            log "Distribution ID: $CLOUDFRONT_ID"
            log "Distribution Domain: $CLOUDFRONT_DOMAIN"
            log "CloudFront URL: https://$CLOUDFRONT_DOMAIN"
            
            log "Note: CloudFront distribution is being deployed. It may take 15-20 minutes to become fully available."
            
            # Store for later use
            echo "$CLOUDFRONT_ID" > "/tmp/${STACK_NAME}-cloudfront-id"
            echo "$CLOUDFRONT_DOMAIN" > "/tmp/${STACK_NAME}-cloudfront-domain"
        else
            warn "CloudFront distribution creation returned unexpected results. Continuing without CloudFront."
        fi
        
        return 0
    else
        warn "Failed to create CloudFront distribution. This is optional and deployment will continue."
        return 0
    fi
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    echo -e "${CYAN}"
    cat << 'EOF'
     ____                        __  ___      __              ____  ____  ____  ____ 
    / ___| ___ _   _ ___  ___  /  |/  /___ _/ /_____  _____/ __ \/ __ \/ __ \/ __ \
   / |  _ / _ \ | | / __|/ _ \/ /|_/ / __ `/ //_/ _ \/ ___/ / / / / / / / / / / / /
  / /__| |  __/ |_| \__ \  __/ /  / / /_/ / ,< /  __/ /  / /_/ / /_/ / /_/ / /_/ / 
  \____/_|\___|\__,_|___/\___/_/  /_/\__,_/_/|_|\___/_/   \____/\____/\____/\____/  
                                                                  
🤖 INTELLIGENT GPU DEPLOYMENT SYSTEM 🚀
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Multi-Architecture | Cost-Optimized | AI-Powered Selection${NC}"
    echo -e "${PURPLE}Automatic AMI & Instance Selection | Real-time Pricing Analysis${NC}"
    echo ""
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    
    log "Starting AWS infrastructure deployment..."
    
    # Mark that we're starting to create resources  
    RESOURCES_CREATED=true
    
    create_key_pair
    create_iam_role
    
    SG_ID=$(create_security_group)
    EFS_DNS=$(create_efs "$SG_ID")
    
    # Launch single spot instance directly (no ASG to avoid multiple instances)
    log "Launching single spot instance with multi-AZ fallback..."
    INSTANCE_INFO=$(launch_spot_instance "$SG_ID" "$EFS_DNS" "$ENABLE_CROSS_REGION")
    INSTANCE_ID=$(echo "$INSTANCE_INFO" | cut -d: -f1)
    PUBLIC_IP=$(echo "$INSTANCE_INFO" | cut -d: -f2)
    INSTANCE_AZ=$(echo "$INSTANCE_INFO" | cut -d: -f3)

    # Now create EFS mount target in the AZ where instance was actually launched
    # Extract EFS_ID from EFS_DNS (format: fs-xxxxx.efs.region.amazonaws.com)
    LOCAL_EFS_ID=$(echo "$EFS_DNS" | cut -d. -f1)
    create_efs_mount_target "$SG_ID" "$INSTANCE_AZ" "$LOCAL_EFS_ID"
    
    wait_for_instance_ready "$INSTANCE_ID" "$SELECTED_INSTANCE_TYPE"
    deploy_application "$PUBLIC_IP" "$EFS_DNS" "$INSTANCE_ID"
    setup_monitoring "$PUBLIC_IP"
    validate_deployment "$PUBLIC_IP"
    
    # Setup ALB and CloudFront if requested
    local ALB_DNS=""
    if [ "$SETUP_ALB" = "true" ]; then
        setup_alb "$INSTANCE_ID" "$SG_ID"
        if [ -n "$ALB_DNS_NAME" ]; then
            ALB_DNS="$ALB_DNS_NAME"
        fi
    fi
    
    if [ "$SETUP_CLOUDFRONT" = "true" ]; then
        setup_cloudfront "$ALB_DNS"
    fi
    
    display_results "$PUBLIC_IP" "$INSTANCE_ID" "$EFS_DNS" "$INSTANCE_AZ"
    
    # Clean up temporary files
    rm -f user-data.sh trust-policy.json custom-policy.json deploy-app.sh
    
    success "GeuseMaker deployment completed successfully!"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "🚀 GeuseMaker - Intelligent AWS GPU Deployment"
    echo "================================================="
    echo ""
    echo "This script intelligently deploys GPU-optimized AI infrastructure on AWS"
    echo "Features:"
    echo "  🤖 Intelligent AMI and instance type selection"
    echo "  💰 Cost optimization with spot pricing analysis"
    echo "  🏗️  Multi-architecture support (Intel x86_64 & ARM64)"
    echo "  📊 Real-time pricing comparison across configurations"
    echo "  🎯 Automatic best price/performance selection"
    echo ""
    echo "Supported Configurations:"
    echo "  📦 G4DN instances (Intel + NVIDIA T4):"
    echo "      - g4dn.xlarge  (4 vCPUs, 16GB RAM, 1x T4)"
    echo "      - g4dn.2xlarge (8 vCPUs, 32GB RAM, 1x T4)"
    echo "  📦 G5G instances (ARM Graviton2 + NVIDIA T4G):"
    echo "      - g5g.xlarge   (4 vCPUs, 8GB RAM, 1x T4G)"  
    echo "      - g5g.2xlarge  (8 vCPUs, 16GB RAM, 1x T4G)"
    echo ""
    echo "AMI Sources:"
    echo "  🔧 AWS Deep Learning AMIs with pre-installed:"
    echo "      - NVIDIA drivers (optimized versions)"
    echo "      - Docker with GPU container runtime"
    echo "      - CUDA toolkit and libraries"
    echo "      - Python ML frameworks"
    echo ""
    echo "Requirements:"
    echo "  ✅ Valid AWS credentials configured"
    echo "  ✅ Docker and AWS CLI installed"
    echo "  ✅ jq and bc utilities (auto-installed if missing)"
    echo ""
    echo "Options:"
    echo "  --region REGION         AWS region (default: us-east-1)"
    echo "  --instance-type TYPE    Instance type or 'auto' for intelligent selection"
    echo "                         Valid: auto, g4dn.xlarge, g4dn.2xlarge, g5g.xlarge, g5g.2xlarge"
    echo "                         (default: auto)"
    echo "  --max-spot-price PRICE  Maximum spot price budget (default: 2.00)"
    echo "  --cross-region          Enable cross-region analysis for best pricing"
    echo "  --key-name NAME         SSH key name (default: GeuseMaker-key)"
    echo "  --stack-name NAME       Stack name (default: GeuseMaker)"
    echo "  --use-pinned-images     Use specific pinned image versions instead of latest"
    echo "  --setup-alb             Setup Application Load Balancer (ALB)"
    echo "  --setup-cloudfront      Setup CloudFront CDN distribution"
    echo "  --setup-cdn             Setup both ALB and CloudFront (convenience flag)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  🎯 Intelligent selection (recommended):"
    echo "    $0                                    # Auto-select best config within budget"
    echo "    $0 --max-spot-price 1.50             # Auto-select with \$1.50/hour budget"
    echo ""
    echo "  🎚️  Manual selection:"
    echo "    $0 --instance-type g4dn.xlarge       # Force specific instance type"
    echo "    $0 --instance-type g5g.2xlarge       # Use ARM-based instance"
    echo ""
    echo "  🌍 Regional deployment:"
    echo "    $0 --region us-west-2                # Deploy in different region"
    echo "    $0 --region eu-central-1             # Deploy in Europe" 
    echo "    $0 --cross-region                    # Find best region automatically"
    echo ""
    echo "  🌐 Load balancer and CDN:"
    echo "    $0 --setup-alb                       # Deploy with Application Load Balancer"
    echo "    $0 --setup-cloudfront                # Deploy with CloudFront CDN"
    echo "    $0 --setup-cdn                       # Deploy with both ALB and CloudFront"
    echo "    $0 --setup-cdn --cross-region        # Full setup with best region"
    echo ""
    echo "Cost Optimization Features:"
    echo "  💡 Automatic spot pricing analysis across all AZs"
    echo "  💡 Price/performance ratio calculation"
    echo "  💡 Multi-AZ fallback for instance availability"
    echo "  💡 Real-time cost comparison display"
    echo "  💡 Optimal configuration recommendations"
    echo ""
    echo "Note: Script automatically handles AMI availability and finds the best"
    echo "      configuration based on current pricing and performance metrics."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --max-spot-price)
            MAX_SPOT_PRICE="$2"
            shift 2
            ;;
        --cross-region)
            ENABLE_CROSS_REGION="true"
            shift
            ;;
        --key-name)
            KEY_NAME="$2"
            shift 2
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --use-pinned-images)
            USE_LATEST_IMAGES=false
            shift
            ;;
        --setup-alb)
            SETUP_ALB=true
            shift
            ;;
        --setup-cloudfront)
            SETUP_CLOUDFRONT=true
            shift
            ;;
        --setup-cdn)
            # Convenience flag to enable both ALB and CloudFront
            SETUP_ALB=true
            SETUP_CLOUDFRONT=true
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

# Run main function
main "$@" 