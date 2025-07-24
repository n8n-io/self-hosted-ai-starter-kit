#!/bin/bash

# =============================================================================
# Security Validation Library
# =============================================================================
# Provides common security validation functions for deployment scripts
# Created as part of security improvements identified in heuristic review
# =============================================================================

set -euo pipefail

# Colors for output (only define if not already set)
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
fi

# =============================================================================
# INPUT VALIDATION FUNCTIONS
# =============================================================================

# Validate AWS region against allowed list
validate_aws_region() {
    local region="$1"
    local allowed_regions=(
        "us-east-1" "us-east-2" "us-west-1" "us-west-2"
        "eu-west-1" "eu-west-2" "eu-central-1"
        "ap-southeast-1" "ap-southeast-2" "ap-northeast-1"
    )
    
    for allowed in "${allowed_regions[@]}"; do
        if [[ "$region" == "$allowed" ]]; then
            return 0
        fi
    done
    
    echo -e "${RED}Error: Invalid AWS region '$region'${NC}" >&2
    echo -e "${YELLOW}Allowed regions: ${allowed_regions[*]}${NC}" >&2
    return 1
}

# Validate instance type against supported GPU instances
validate_instance_type() {
    local instance_type="$1"
    local allowed_types=(
        "g4dn.xlarge" "g4dn.2xlarge" "g4dn.4xlarge"
        "g5g.xlarge" "g5g.2xlarge" "g5g.4xlarge"
        "p3.2xlarge" "p3.8xlarge"
        "auto"  # Special case for auto-selection
    )
    
    for allowed in "${allowed_types[@]}"; do
        if [[ "$instance_type" == "$allowed" ]]; then
            return 0
        fi
    done
    
    echo -e "${RED}Error: Invalid instance type '$instance_type'${NC}" >&2
    echo -e "${YELLOW}Allowed types: ${allowed_types[*]}${NC}" >&2
    return 1
}

# Validate spot price (must be numeric and reasonable)
validate_spot_price() {
    local price="$1"
    
    # Check if numeric
    if ! [[ "$price" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo -e "${RED}Error: Spot price must be numeric: '$price'${NC}" >&2
        return 1
    fi
    
    # Check reasonable range (0.10 to 50.00)
    if (( $(echo "$price < 0.10" | bc -l) )) || (( $(echo "$price > 50.00" | bc -l) )); then
        echo -e "${RED}Error: Spot price outside reasonable range (0.10-50.00): '$price'${NC}" >&2
        return 1
    fi
    
    return 0
}

# Validate stack name (alphanumeric, hyphens, no spaces)
validate_stack_name() {
    local name="$1"
    
    if [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        echo -e "${RED}Error: Stack name contains invalid characters: '$name'${NC}" >&2
        echo -e "${YELLOW}Use only alphanumeric characters and hyphens${NC}" >&2
        return 1
    fi
    
    if [[ ${#name} -lt 3 ]] || [[ ${#name} -gt 63 ]]; then
        echo -e "${RED}Error: Stack name must be 3-63 characters: '$name'${NC}" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# CREDENTIAL AND SECRET VALIDATION
# =============================================================================

# Generate secure password with specified entropy
generate_secure_password() {
    local bits="${1:-256}"  # Default to 256-bit entropy
    local hex_chars=$((bits / 4))
    
    openssl rand -hex "$hex_chars"
}

# Validate password strength
validate_password_strength() {
    local password="$1"
    local min_length="${2:-24}"  # Minimum length for strong passwords
    
    if [[ ${#password} -lt $min_length ]]; then
        echo -e "${RED}Error: Password too short (min $min_length chars): ${#password}${NC}" >&2
        return 1
    fi
    
    # Check for hex pattern (secure random generation)
    if [[ ! "$password" =~ ^[a-fA-F0-9]+$ ]]; then
        echo -e "${YELLOW}Warning: Password not hex-encoded (may be weak)${NC}" >&2
    fi
    
    return 0
}

# Check for hardcoded secrets in files
check_for_secrets() {
    local file="$1"
    local patterns=(
        "password.*="
        "secret.*="
        "key.*="
        "token.*="
        "aws_access_key"
        "aws_secret"
    )
    
    for pattern in "${patterns[@]}"; do
        if grep -qi "$pattern" "$file" 2>/dev/null; then
            echo -e "${YELLOW}Warning: Potential secret found in $file (pattern: $pattern)${NC}" >&2
        fi
    done
}

# =============================================================================
# AWS RESOURCE VALIDATION
# =============================================================================

# Validate AWS CLI credentials
validate_aws_credentials() {
    local profile="${1:-default}"
    
    if ! aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
        echo -e "${RED}Error: Invalid AWS credentials for profile '$profile'${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✓ AWS credentials validated for profile '$profile'${NC}" >&2
    return 0
}

# Check AWS quotas for instance type
check_aws_quotas() {
    local instance_type="$1"
    local region="$2"
    local profile="${3:-default}"
    
    # Map instance types to quota codes
    local quota_code=""
    case "$instance_type" in
        g4dn.*) quota_code="L-DB2E81BA" ;;  # Running On-Demand G instances
        g5g.*) quota_code="L-DB2E81BA" ;;   # Same quota family
        p3.*) quota_code="L-417A185B" ;;    # Running On-Demand P instances
        *) 
            echo -e "${YELLOW}Warning: Unknown quota code for instance type '$instance_type'${NC}" >&2
            return 0
            ;;
    esac
    
    # Check current quota (requires service-quotas CLI access)
    if command -v aws >/dev/null 2>&1; then
        local quota_info
        quota_info=$(aws service-quotas get-service-quota \
            --service-code ec2 \
            --quota-code "$quota_code" \
            --region "$region" \
            --profile "$profile" 2>/dev/null || echo "")
        
        if [[ -n "$quota_info" ]]; then
            local quota_value
            quota_value=$(echo "$quota_info" | jq -r '.Quota.Value // "unknown"')
            echo -e "${GREEN}✓ Current quota for $instance_type: $quota_value vCPUs${NC}" >&2
        fi
    fi
    
    return 0
}

# =============================================================================
# SECURITY CONFIGURATION VALIDATION
# =============================================================================

# Validate CORS configuration
validate_cors_config() {
    local cors_origins="$1"
    
    if [[ "$cors_origins" == "*" ]]; then
        echo -e "${RED}Error: CORS wildcard (*) is insecure for production${NC}" >&2
        echo -e "${YELLOW}Specify exact domains instead: https://yourdomain.com${NC}" >&2
        return 1
    fi
    
    # Validate each origin
    IFS=',' read -ra origins <<< "$cors_origins"
    for origin in "${origins[@]}"; do
        if [[ ! "$origin" =~ ^https?://[a-zA-Z0-9.-]+$ ]]; then
            echo -e "${RED}Error: Invalid CORS origin format: '$origin'${NC}" >&2
            return 1
        fi
    done
    
    return 0
}

# Validate Docker security configuration
validate_docker_security() {
    local compose_file="$1"
    
    # Check for privileged containers
    if grep -q "privileged.*true" "$compose_file" 2>/dev/null; then
        echo -e "${YELLOW}Warning: Privileged containers found in $compose_file${NC}" >&2
    fi
    
    # Check for host network mode
    if grep -q "network_mode.*host" "$compose_file" 2>/dev/null; then
        echo -e "${YELLOW}Warning: Host network mode found in $compose_file${NC}" >&2
    fi
    
    # Check for volume mounts from root
    if grep -q ":/.*:.*" "$compose_file" | grep -q "^/" 2>/dev/null; then
        echo -e "${YELLOW}Warning: Root filesystem mounts found in $compose_file${NC}" >&2
    fi
    
    return 0
}

# =============================================================================
# MAIN VALIDATION ORCHESTRATION
# =============================================================================

# Run comprehensive security validation
run_security_validation() {
    local aws_region="${1:-us-east-1}"
    local instance_type="${2:-auto}"
    local stack_name="${3:-GeuseMaker}"
    local profile="${4:-default}"
    
    echo -e "${BLUE}=== Running Security Validation ===${NC}"
    
    local errors=0
    
    # Validate inputs
    echo "Validating inputs..."
    validate_aws_region "$aws_region" || ((errors++))
    validate_instance_type "$instance_type" || ((errors++))
    validate_stack_name "$stack_name" || ((errors++))
    
    # Validate AWS access
    echo "Validating AWS access..."
    validate_aws_credentials "$profile" || ((errors++))
    
    # Check for secrets in files
    echo "Checking for hardcoded secrets..."
    find . -name "*.json" -o -name "*.yml" -o -name "*.yaml" | while read -r file; do
        check_for_secrets "$file"
    done
    
    # Validate Docker configurations
    echo "Validating Docker security..."
    find . -name "docker-compose*.yml" | while read -r file; do
        validate_docker_security "$file"
    done
    
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✓ Security validation passed${NC}"
        return 0
    else
        echo -e "${RED}✗ Security validation failed with $errors errors${NC}"
        return 1
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Sanitize file path to prevent directory traversal
sanitize_path() {
    local path="$1"
    
    # Remove any ../ patterns
    path="${path//..\/}"
    path="${path//\.\.}"
    
    # Ensure path doesn't start with /
    path="${path#/}"
    
    echo "$path"
}

# Escape shell arguments to prevent injection
escape_shell_arg() {
    local arg="$1"
    printf '%q' "$arg"
}

# Export functions for use in other scripts
export -f validate_aws_region validate_instance_type validate_spot_price
export -f validate_stack_name generate_secure_password validate_password_strength
export -f validate_aws_credentials check_aws_quotas validate_cors_config
export -f validate_docker_security run_security_validation
export -f sanitize_path escape_shell_arg