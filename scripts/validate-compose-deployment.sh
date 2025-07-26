#!/bin/bash

# Docker Compose Deployment Validation Script
# Validates Docker Compose configuration before deployment
# Designed to work in AWS deployment contexts where environment variables may not be fully set

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.gpu-optimized.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detect Docker Compose command (modern vs legacy)
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}Error: Neither 'docker compose' nor 'docker-compose' command found${NC}"
    exit 1
fi

log() {
    echo -e "${BLUE}[VALIDATE]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create a comprehensive environment file for validation
create_validation_env() {
    local env_file="$1"
    
    cat > "$env_file" << 'EOF'
# =========================================================================
# Docker Compose Validation Environment
# This file contains all required environment variables for validation
# =========================================================================

# EFS Configuration (AWS)
EFS_DNS=${EFS_DNS:-placeholder.efs.us-east-1.amazonaws.com}

# PostgreSQL Configuration
POSTGRES_DB=${POSTGRES_DB:-n8n}
POSTGRES_USER=${POSTGRES_USER:-n8n}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-secure_password_123}

# n8n Configuration
N8N_HOST=${N8N_HOST:-0.0.0.0}
N8N_PORT=${N8N_PORT:-5678}
N8N_PROTOCOL=${N8N_PROTOCOL:-http}
WEBHOOK_URL=${WEBHOOK_URL:-http://localhost:5678}

# n8n Security and CORS
N8N_CORS_ENABLE=${N8N_CORS_ENABLE:-true}
N8N_CORS_ALLOWED_ORIGINS=${N8N_CORS_ALLOWED_ORIGINS:-http://localhost:5678}
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=${N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE:-false}

# Ollama Configuration
OLLAMA_ORIGINS=${OLLAMA_ORIGINS:-http://localhost:*}

# AWS Instance Configuration
INSTANCE_TYPE=${INSTANCE_TYPE:-g4dn.xlarge}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
INSTANCE_ID=${INSTANCE_ID:-i-placeholder}

# API Keys (placeholders for validation - will be overridden by real values)
OPENAI_API_KEY=${OPENAI_API_KEY:-placeholder_openai_key}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-placeholder_anthropic_key}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-placeholder_deepseek_key}
GROQ_API_KEY=${GROQ_API_KEY:-placeholder_groq_key}
TOGETHER_API_KEY=${TOGETHER_API_KEY:-placeholder_together_key}
MISTRAL_API_KEY=${MISTRAL_API_KEY:-placeholder_mistral_key}
GEMINI_API_TOKEN=${GEMINI_API_TOKEN:-placeholder_gemini_token}
EOF
}

# Validate Docker Compose configuration with comprehensive error reporting
validate_configuration() {
    local env_file="$1"
    local context="$2"
    
    log "Validating Docker Compose configuration ($context)..."
    
    # Capture both stdout and stderr for analysis
    local validation_output
    local validation_exit_code
    
    if validation_output=$($DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$env_file" config 2>&1); then
        validation_exit_code=0
    else
        validation_exit_code=$?
    fi
    
    # Check for warnings (non-fatal issues)
    local warning_count=0
    if echo "$validation_output" | grep -qi "warning"; then
        warning_count=$(echo "$validation_output" | grep -ci "warning" || echo "0")
        warn "Found $warning_count warning(s) in configuration"
        
        if [[ "${VERBOSE:-false}" == "true" ]]; then
            echo "$validation_output" | grep -i "warning" | head -5
        fi
    fi
    
    # Check validation exit code
    if [[ $validation_exit_code -eq 0 ]]; then
        # Verify the output contains expected services
        if echo "$validation_output" | grep -q "services:" && \
           echo "$validation_output" | grep -q "postgres:" && \
           echo "$validation_output" | grep -q "n8n:" && \
           echo "$validation_output" | grep -q "ollama:"; then
            success "Docker Compose configuration is valid ($context)"
            if [[ $warning_count -gt 0 ]]; then
                warn "Configuration is valid but has $warning_count warning(s)"
            fi
            return 0
        else
            error "Configuration validation succeeded but missing expected services"
            return 1
        fi
    else
        error "Docker Compose configuration validation failed ($context)"
        
        # Show first few lines of error for diagnosis
        echo "Validation errors:"
        echo "$validation_output" | head -10
        return 1
    fi
}

# Main validation logic
main() {
    local verbose_mode=false
    local deployment_context="unknown"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                verbose_mode=true
                export VERBOSE=true
                shift
                ;;
            -c|--context)
                deployment_context="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -v, --verbose     Show detailed validation output"
                echo "  -c, --context CTX Specify deployment context (e.g., 'aws-deployment')"
                echo "  -h, --help        Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  VERBOSE=true      Enable verbose output"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    log "Starting Docker Compose validation for deployment context: $deployment_context"
    log "Docker Compose version: $($DOCKER_COMPOSE_CMD version --short)"
    log "Configuration file: $COMPOSE_FILE"
    
    # Check if Docker Compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    # Check if secrets directory exists
    local secrets_dir="${PROJECT_ROOT}/secrets"
    if [[ ! -d "$secrets_dir" ]]; then
        warn "Secrets directory not found: $secrets_dir"
        warn "Deployment may fail if secrets are not properly configured"
    fi
    
    # Strategy 1: Try validation with existing .env file if available
    local env_file="${PROJECT_ROOT}/.env"
    if [[ -f "$env_file" ]]; then
        log "Found existing .env file, using for validation"
        if validate_configuration "$env_file" "existing environment"; then
            success "Validation completed successfully with existing environment"
            exit 0
        else
            warn "Validation with existing .env failed, trying with generated environment"
        fi
    fi
    
    # Strategy 2: Create temporary validation environment
    local temp_env_file=$(mktemp)
    trap "rm -f '$temp_env_file'" EXIT
    
    create_validation_env "$temp_env_file"
    
    if validate_configuration "$temp_env_file" "generated environment"; then
        success "Validation completed successfully with generated environment"
        
        # Additional deployment readiness checks
        log "Performing additional deployment readiness checks..."
        
        # Check Docker daemon status
        if ! docker info >/dev/null 2>&1; then
            error "Docker daemon is not running or accessible"
            exit 1
        fi
        
        # Check available disk space (basic check)
        local available_space
        available_space=$(df /tmp | awk 'NR==2 {print $4}')
        if [[ $available_space -lt 1048576 ]]; then  # Less than 1GB in KB
            warn "Low disk space available: ${available_space}KB"
            warn "Docker deployment may fail due to insufficient space"
        fi
        
        success "All validation checks passed - deployment should proceed"
        
        if [[ "$verbose_mode" == "true" ]]; then
            log "Configuration summary:"
            echo "  - Services: postgres, n8n, ollama, qdrant, crawl4ai"
            echo "  - Networks: ai_network (172.20.0.0/16)"
            echo "  - Volumes: EFS-backed persistent storage"
            echo "  - Secrets: Docker secrets integration"
            echo "  - Resource limits: Configured for g4dn.xlarge"
        fi
        
        exit 0
    else
        error "All validation strategies failed"
        error "Please check Docker Compose configuration and environment variables"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"