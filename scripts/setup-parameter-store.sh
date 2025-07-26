#!/bin/bash

# =============================================================================
# Parameter Store Setup Script
# Creates required parameters in AWS Systems Manager Parameter Store
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }
success() { echo -e "${GREEN}✅ [SUCCESS] $1${NC}" >&2; }
warning() { echo -e "${YELLOW}[WARNING] $1${NC}" >&2; }

# =============================================================================
# PARAMETER CREATION FUNCTIONS
# =============================================================================

create_parameter() {
    local name="$1"
    local value="$2"
    local type="${3:-String}"
    local description="$4"
    local aws_region="${5:-us-east-1}"
    
    # Check if parameter already exists
    if aws ssm get-parameter --name "$name" --region "$aws_region" &>/dev/null; then
        warning "Parameter $name already exists. Skipping creation."
        return 0
    fi
    
    # Create parameter
    aws ssm put-parameter \
        --name "$name" \
        --value "$value" \
        --type "$type" \
        --description "$description" \
        --region "$aws_region" \
        --overwrite > /dev/null
    
    success "Created parameter: $name"
}

create_secure_parameter() {
    local name="$1"
    local value="$2"
    local description="$3"
    local aws_region="${4:-us-east-1}"
    
    create_parameter "$name" "$value" "SecureString" "$description" "$aws_region"
}

# =============================================================================
# GENERATE SECURE VALUES
# =============================================================================

generate_secure_password() {
    openssl rand -hex 32
}

generate_encryption_key() {
    openssl rand -hex 32
}

generate_jwt_secret() {
    openssl rand -hex 32
}

# =============================================================================
# SETUP FUNCTIONS
# =============================================================================

setup_database_parameters() {
    local aws_region="$1"
    
    log "Setting up database parameters..."
    
    create_secure_parameter \
        "/aibuildkit/POSTGRES_PASSWORD" \
        "$(generate_secure_password)" \
        "PostgreSQL database password for GeuseMaker" \
        "$aws_region"
}

setup_n8n_parameters() {
    local aws_region="$1"
    
    log "Setting up n8n parameters..."
    
    create_secure_parameter \
        "/aibuildkit/n8n/ENCRYPTION_KEY" \
        "$(generate_encryption_key)" \
        "n8n encryption key for data protection" \
        "$aws_region"
    
    create_secure_parameter \
        "/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET" \
        "$(generate_jwt_secret)" \
        "n8n JWT secret for user management" \
        "$aws_region"
    
    create_parameter \
        "/aibuildkit/n8n/CORS_ENABLE" \
        "true" \
        "String" \
        "Enable CORS for n8n" \
        "$aws_region"
    
    create_parameter \
        "/aibuildkit/n8n/CORS_ALLOWED_ORIGINS" \
        "*" \
        "String" \
        "Allowed CORS origins for n8n (should be restricted in production)" \
        "$aws_region"
    
    create_parameter \
        "/aibuildkit/n8n/COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE" \
        "true" \
        "String" \
        "Allow community packages tool usage in n8n" \
        "$aws_region"
}

setup_api_key_placeholders() {
    local aws_region="$1"
    
    log "Setting up API key placeholders..."
    
    # Create placeholder parameters for API keys (empty by default)
    local api_keys=(
        "OPENAI_API_KEY:OpenAI API key for LLM services"
        "ANTHROPIC_API_KEY:Anthropic Claude API key"
        "DEEPSEEK_API_KEY:DeepSeek API key for local models"
        "GROQ_API_KEY:Groq API key for fast inference"
        "TOGETHER_API_KEY:Together AI API key"
        "MISTRAL_API_KEY:Mistral AI API key"
        "GEMINI_API_TOKEN:Google Gemini API token"
    )
    
    for key_info in "${api_keys[@]}"; do
        local key_name="${key_info%:*}"
        local description="${key_info#*:}"
        
        create_secure_parameter \
            "/aibuildkit/$key_name" \
            "" \
            "$description (placeholder - add your actual key)" \
            "$aws_region"
    done
    
    warning "API key placeholders created. You need to update them with actual values:"
    echo ""
    for key_info in "${api_keys[@]}"; do
        local key_name="${key_info%:*}"
        echo "  aws ssm put-parameter --name '/aibuildkit/$key_name' --value 'YOUR_ACTUAL_KEY' --type SecureString --overwrite --region $aws_region"
    done
    echo ""
}

setup_webhook_parameter() {
    local aws_region="$1"
    local default_webhook="${2:-http://localhost:5678}"
    
    log "Setting up webhook parameter..."
    
    create_parameter \
        "/aibuildkit/WEBHOOK_URL" \
        "$default_webhook" \
        "String" \
        "Base webhook URL for n8n (will be updated with actual IP during deployment)" \
        "$aws_region"
}

# =============================================================================
# VALIDATION AND MANAGEMENT
# =============================================================================

list_parameters() {
    local aws_region="$1"
    
    log "Listing all GeuseMaker parameters..."
    
    aws ssm get-parameters-by-path \
        --path "/aibuildkit" \
        --recursive \
        --query 'Parameters[].{Name:Name,Type:Type,LastModified:LastModifiedDate}' \
        --output table \
        --region "$aws_region"
}

validate_parameters() {
    local aws_region="$1"
    
    log "Validating parameter setup..."
    
    local required_params=(
        "/aibuildkit/POSTGRES_PASSWORD"
        "/aibuildkit/n8n/ENCRYPTION_KEY"
        "/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET"
        "/aibuildkit/WEBHOOK_URL"
    )
    
    local missing_params=()
    
    for param in "${required_params[@]}"; do
        if ! aws ssm get-parameter --name "$param" --region "$aws_region" &>/dev/null; then
            missing_params+=("$param")
        fi
    done
    
    if [ ${#missing_params[@]} -eq 0 ]; then
        success "All required parameters are present"
        return 0
    else
        error "Missing required parameters:"
        for param in "${missing_params[@]}"; do
            echo "  - $param"
        done
        return 1
    fi
}

cleanup_parameters() {
    local aws_region="$1"
    
    warning "This will delete ALL GeuseMaker parameters!"
    read -p "Are you sure? Type 'yes' to confirm: " -r
    
    if [[ ! $REPLY == "yes" ]]; then
        log "Cleanup cancelled"
        return 0
    fi
    
    log "Cleaning up parameters..."
    
    # Get all parameter names (bash 3.x compatible)
    local param_names_raw
    param_names_raw=$(aws ssm get-parameters-by-path \
        --path "/aibuildkit" \
        --recursive \
        --query 'Parameters[].Name' \
        --output text \
        --region "$aws_region" | tr '\t' '\n')
    # Convert to array bash 3.x compatible way
    local param_names
    param_names=($param_names_raw)
    
    # Delete each parameter
    for param_name in "${param_names[@]}"; do
        if [ -n "$param_name" ]; then
            aws ssm delete-parameter --name "$param_name" --region "$aws_region"
            log "Deleted parameter: $param_name"
        fi
    done
    
    success "Parameter cleanup completed"
}

# =============================================================================
# IAM PERMISSIONS CHECK
# =============================================================================

check_iam_permissions() {
    local aws_region="$1"
    
    log "Checking IAM permissions for Parameter Store..."
    
    # Test basic SSM permissions
    if ! aws ssm describe-parameters --region "$aws_region" &>/dev/null; then
        error "Missing SSM permissions. Ensure your AWS credentials have the following policies:"
        echo "  - AmazonSSMFullAccess (or custom policy with ssm:* permissions)"
        return 1
    fi
    
    success "IAM permissions look good"
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  setup     Set up all required parameters (default)"
    echo "  list      List all existing parameters"
    echo "  validate  Validate parameter setup"
    echo "  cleanup   Delete all parameters (destructive!)"
    echo ""
    echo "Options:"
    echo "  --region REGION    AWS region (default: us-east-1)"
    echo "  --webhook-url URL  Base webhook URL (default: http://localhost:5678)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 setup --region us-west-2"
    echo "  $0 list --region us-east-1"
    echo "  $0 validate"
}

main() {
    local command="setup"
    local aws_region="us-east-1"
    local webhook_url="http://localhost:5678"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            setup|list|validate|cleanup)
                command="$1"
                shift
                ;;
            --region)
                aws_region="$2"
                shift 2
                ;;
            --webhook-url)
                webhook_url="$2"
                shift 2
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
    
    log "Starting Parameter Store $command in region: $aws_region"
    
    # Check IAM permissions first
    if ! check_iam_permissions "$aws_region"; then
        exit 1
    fi
    
    case "$command" in
        "setup")
            setup_database_parameters "$aws_region"
            setup_n8n_parameters "$aws_region"
            setup_api_key_placeholders "$aws_region"
            setup_webhook_parameter "$aws_region" "$webhook_url"
            
            success "Parameter Store setup completed!"
            echo ""
            warning "Next steps:"
            echo "1. Update API keys with your actual values"
            echo "2. Run validation: $0 validate --region $aws_region"
            echo "3. Deploy your stack"
            ;;
        "list")
            list_parameters "$aws_region"
            ;;
        "validate")
            validate_parameters "$aws_region"
            ;;
        "cleanup")
            cleanup_parameters "$aws_region"
            ;;
    esac
}

# Execute main function with all arguments
main "$@"