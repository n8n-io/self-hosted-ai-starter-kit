#!/bin/bash

# Simple Docker Image Version Updater
# Updates Docker Compose files to use latest tags

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.gpu-optimized.yml"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

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

# Validate Docker Compose
validate() {
    log "Validating Docker Compose configuration..."
    if docker-compose -f "$COMPOSE_FILE" config > /dev/null 2>&1; then
        success "Docker Compose configuration is valid"
    else
        echo "Docker Compose configuration validation failed"
        exit 1
    fi
}

# Main function
main() {
    local command="${1:-update}"
    
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
        *)
            echo "Usage: $0 [update|show|validate]"
            echo "  update   - Update images to latest (default)"
            echo "  show     - Show current image versions"
            echo "  validate - Validate Docker Compose configuration"
            ;;
    esac
}

main "$@"