#!/bin/bash

# Simple Docker Image Version Updater
# Updates Docker Compose files to use latest tags

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.gpu-optimized.yml"

# Detect Docker Compose command (modern vs legacy)
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' command found"
    exit 1
fi

# Source unified logging if available
if [[ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]]; then
    source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
else
    # Fallback logging functions with basic formatting
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
    
    log() { echo -e "${BLUE}[INFO]${NC} $1"; }
    success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
    warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
    info() { echo -e "${BLUE}[INFO]${NC} $1"; }
fi

# Create backup
create_backup() {
    local backup_file="${COMPOSE_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$COMPOSE_FILE" "$backup_file"
    log "Backup created: $backup_file"
}

# Update images to latest
update_to_latest() {
    log "Updating Docker images to latest versions..."
    
    # Create backup first
    create_backup
    
    # Update specific images to latest
    sed -i.tmp 's|image: postgres:.*|image: postgres:latest|g' "$COMPOSE_FILE"
    sed -i.tmp 's|image: n8nio/n8n:.*|image: n8nio/n8n:latest|g' "$COMPOSE_FILE"
    sed -i.tmp 's|image: qdrant/qdrant:.*|image: qdrant/qdrant:latest|g' "$COMPOSE_FILE"
    sed -i.tmp 's|image: ollama/ollama:.*|image: ollama/ollama:latest|g' "$COMPOSE_FILE"
    sed -i.tmp 's|image: curlimages/curl:.*|image: curlimages/curl:latest|g' "$COMPOSE_FILE"
    sed -i.tmp 's|image: unclecode/crawl4ai:.*|image: unclecode/crawl4ai:latest|g' "$COMPOSE_FILE"
    
    # Keep CUDA version pinned for compatibility
    # sed -i.tmp 's|image: nvidia/cuda:.*|image: nvidia/cuda:latest|g' "$COMPOSE_FILE"
    
    # Clean up temp files
    rm -f "${COMPOSE_FILE}.tmp"
    
    success "Images updated to latest versions"
}

# Show current versions
show_versions() {
    log "Current image versions:"
    echo
    grep -n "image:" "$COMPOSE_FILE" | while IFS=: read -r line_num line_content; do
        image=$(echo "$line_content" | sed 's/.*image: *//')
        printf "  Line %-3s: %s\n" "$line_num" "$image"
    done
    echo
}

# Validate Docker Compose with environment variable handling
validate() {
    log "Validating Docker Compose configuration..."
    
    # Check if we're in a deployment context where .env might be available
    local env_file="${PROJECT_ROOT}/.env"
    local validation_failed=false
    
    # Try validation with environment file if it exists
    if [[ -f "$env_file" ]]; then
        log "Using existing .env file for validation"
        if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$env_file" config > /dev/null 2>&1; then
            success "Docker Compose configuration is valid (with .env)"
            return 0
        else
            log "Validation with .env failed, trying with minimal environment..."
            validation_failed=true
        fi
    fi
    
    # Create temporary minimal environment for validation
    local temp_env_file=$(mktemp)
    cat > "$temp_env_file" << 'EOF'
# Minimal environment for Docker Compose validation
EFS_DNS=placeholder.efs.region.amazonaws.com
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=placeholder
N8N_HOST=0.0.0.0
WEBHOOK_URL=http://localhost:5678
N8N_CORS_ALLOWED_ORIGINS=http://localhost:5678
OLLAMA_ORIGINS=http://localhost:*
INSTANCE_TYPE=g4dn.xlarge
AWS_DEFAULT_REGION=us-east-1
INSTANCE_ID=i-placeholder
# API Keys (placeholders for validation)
OPENAI_API_KEY=placeholder
ANTHROPIC_API_KEY=placeholder
DEEPSEEK_API_KEY=placeholder
GROQ_API_KEY=placeholder
TOGETHER_API_KEY=placeholder
MISTRAL_API_KEY=placeholder
GEMINI_API_TOKEN=placeholder
EOF
    
    # Attempt validation with minimal environment
    if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$temp_env_file" config > /dev/null 2>&1; then
        success "Docker Compose configuration is valid (with minimal environment)"
        rm -f "$temp_env_file"
        return 0
    else
        log "Validation with minimal environment failed, attempting syntax-only check..."
        
        # Try basic YAML syntax validation without variable substitution
        if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" config --quiet 2>/dev/null | grep -q "services:"; then
            success "Docker Compose YAML syntax is valid (variables may need runtime resolution)"
            rm -f "$temp_env_file"
            return 0
        else
            echo "Docker Compose configuration validation failed"
            echo "This may be due to:"
            echo "  1. Missing required environment variables during deployment"
            echo "  2. Docker Compose version compatibility issues"  
            echo "  3. Syntax errors in the configuration file"
            
            # Show specific errors if in verbose mode
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo ""
                echo "Detailed validation errors:"
                $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$temp_env_file" config 2>&1 | head -20
            fi
            
            rm -f "$temp_env_file"
            exit 1
        fi
    fi
}

# Main function
main() {
    local command="${1:-update}"
    
    # Handle verbose flag
    if [[ "$command" == "-v" || "$command" == "--verbose" ]]; then
        export VERBOSE=true
        command="${2:-update}"
    fi
    
    case "$command" in
        "update")
            show_versions
            update_to_latest
            validate
            show_versions
            ;;
        "show")
            show_versions
            ;;
        "validate")
            validate
            ;;
        "test")
            log "Testing Docker Compose validation with current configuration..."
            validate
            success "All validation tests passed"
            ;;
        "validate-deployment")
            log "Running comprehensive deployment validation..."
            if [[ -f "${PROJECT_ROOT}/scripts/validate-compose-deployment.sh" ]]; then
                "${PROJECT_ROOT}/scripts/validate-compose-deployment.sh" --context "image-update" ${VERBOSE:+--verbose}
            else
                warn "Deployment validation script not found, using basic validation"
                validate
            fi
            ;;
        *)
            echo "Usage: $0 [-v|--verbose] [update|show|validate|test|validate-deployment]"
            echo ""
            echo "Commands:"
            echo "  update              - Update images to latest and validate (default)"
            echo "  show                - Show current image versions"
            echo "  validate            - Validate Docker Compose configuration"
            echo "  test                - Test validation without making changes"
            echo "  validate-deployment - Run comprehensive deployment validation"
            echo ""
            echo "Options:"
            echo "  -v, --verbose  - Show detailed validation errors"
            echo ""
            echo "Environment Variables:"
            echo "  VERBOSE=true   - Enable verbose output"
            ;;
    esac
}

main "$@"