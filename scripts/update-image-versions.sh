#!/bin/bash

# Update Docker Image Versions Script
# This script updates Docker Compose files to use latest tags or configured versions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/image-versions.yml"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.gpu-optimized.yml"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to extract value from YAML (simple parser)
get_yaml_value() {
    local file="$1"
    local key="$2"
    local section="$3"
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    if [ -n "$section" ]; then
        # Extract value from specific section like "services/postgres"
        if [[ "$section" == *"/"* ]]; then
            local main_section="${section%%/*}"
            local sub_section="${section#*/}"
            awk -v main="$main_section:" -v sub="$sub_section:" -v key="$key:" '
            $0 ~ main {in_main=1; next}
            in_main && /^[a-zA-Z]/ && $0 !~ /^[ \t]/ {in_main=0}
            in_main && $0 ~ sub {in_sub=1; next}
            in_sub && /^[ \t][a-zA-Z]/ && $0 !~ /^[ \t][ \t]/ {in_sub=0}
            in_sub && $0 ~ key {
                gsub(/^[ \t]*[^:]*:[ \t]*/, "")
                gsub(/^"/, ""); gsub(/"$/, "")
                print $0
                exit
            }' "$file"
        else
            # Simple section lookup
            awk -v section="$section:" -v key="$key:" '
            $0 ~ section {in_section=1; next}
            in_section && /^[a-zA-Z]/ && $0 !~ /^[ \t]/ {in_section=0}
            in_section && $0 ~ key {
                gsub(/^[ \t]*[^:]*:[ \t]*/, "")
                gsub(/^"/, ""); gsub(/"$/, "")
                print $0
                exit
            }' "$file"
        fi
    else
        # Extract value from root level
        awk -v key="$key:" '
        $0 ~ key && !/^[ \t]/ {
            gsub(/^[ \t]*[^:]*:[ \t]*/, "")
            gsub(/^"/, ""); gsub(/"$/, "")
            print $0
            exit
        }' "$file"
    fi
}

# Function to get service image configuration
get_service_image() {
    local service="$1"
    local environment="${2:-development}"
    local use_latest="${3:-true}"
    
    # Check if configuration file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        warn "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    # First check environment-specific overrides
    local env_image
    env_image=$(get_yaml_value "$CONFIG_FILE" "image" "environments/$environment/$service")
    
    if [ -n "$env_image" ]; then
        echo "$env_image"
        return 0
    fi
    
    # Get default image and settings
    local base_image
    local default_tag
    local fallback_tag
    
    base_image=$(get_yaml_value "$CONFIG_FILE" "image" "services/$service")
    default_tag=$(get_yaml_value "$CONFIG_FILE" "default" "services/$service")
    fallback_tag=$(get_yaml_value "$CONFIG_FILE" "fallback" "services/$service")
    
    if [ -z "$base_image" ]; then
        warn "No configuration found for service: $service"
        return 1
    fi
    
    # Determine which tag to use
    if [ "$use_latest" = "true" ] && [ "$default_tag" = "latest" ]; then
        echo "${base_image}:latest"
    elif [ "$use_latest" = "true" ] && [ -n "$default_tag" ] && [ "$default_tag" != "latest" ]; then
        echo "${base_image}:${default_tag}"
    elif [ -n "$fallback_tag" ]; then
        echo "${base_image}:${fallback_tag}"
    else
        echo "${base_image}:latest"
    fi
}

# Function to update Docker Compose file
update_compose_file() {
    local environment="${1:-development}"
    local use_latest="${2:-true}"
    local backup="${3:-true}"
    
    log "Updating Docker Compose file with environment: $environment"
    
    # Create backup if requested
    if [ "$backup" = "true" ]; then
        cp "$COMPOSE_FILE" "${COMPOSE_FILE}${BACKUP_SUFFIX}"
        log "Backup created: ${COMPOSE_FILE}${BACKUP_SUFFIX}"
    fi
    
    # Update services with their corresponding config mappings
    update_service_image "postgres" "postgres" "$environment" "$use_latest"
    update_service_image "n8n" "n8n" "$environment" "$use_latest"
    update_service_image "qdrant" "qdrant" "$environment" "$use_latest"
    update_service_image "ollama" "ollama" "$environment" "$use_latest"
    update_service_image "ollama-model-init" "ollama" "$environment" "$use_latest"
    update_service_image "gpu-monitor" "cuda" "$environment" "$use_latest"
    update_service_image "health-check" "curl" "$environment" "$use_latest"
    update_service_image "crawl4ai" "crawl4ai" "$environment" "$use_latest"
}

# Helper function to update individual service
update_service_image() {
    local compose_service="$1"
    local config_service="$2"
    local environment="$3"
    local use_latest="$4"
    
    local new_image
    new_image=$(get_service_image "$config_service" "$environment" "$use_latest")
    
    if [ -n "$new_image" ]; then
        log "Updating $compose_service to use image: $new_image"
        
        # Use sed to update the image line for this service
        sed -i.tmp "/^  $compose_service:/,/^  [a-zA-Z]/ s|image: .*|image: $new_image|" "$COMPOSE_FILE"
        rm -f "${COMPOSE_FILE}.tmp"
        
        success "Updated $compose_service image"
    else
        warn "Could not determine image for service: $compose_service"
    fi
}

# Function to validate Docker Compose file
validate_compose() {
    log "Validating Docker Compose configuration..."
    
    if docker-compose -f "$COMPOSE_FILE" config > /dev/null 2>&1; then
        success "Docker Compose configuration is valid"
        return 0
    else
        error "Docker Compose configuration is invalid"
        return 1
    fi
}

# Function to show current image versions
show_current_versions() {
    log "Current image versions in Docker Compose:"
    echo
    
    grep -n "image:" "$COMPOSE_FILE" | while IFS=: read -r line_num line_content; do
        service=$(sed -n "$((line_num-1))p" "$COMPOSE_FILE" | grep -o '^  [a-zA-Z-]*' | sed 's/^  //' || echo "unknown")
        image=$(echo "$line_content" | sed 's/.*image: *//')
        printf "  %-20s %s\n" "$service:" "$image"
    done
    echo
}

# Function to pull all images and check availability
test_image_availability() {
    log "Testing image availability..."
    
    local failed_count=0
    
    grep "image:" "$COMPOSE_FILE" | sed 's/.*image: *//' | sort -u | while read -r image; do
        if [ -n "$image" ]; then
            log "Testing image: $image"
            if docker pull "$image" > /dev/null 2>&1; then
                success "✓ $image"
            else
                warn "✗ $image (failed to pull)"
                ((failed_count++))
            fi
        fi
    done
    
    if [ $failed_count -eq 0 ]; then
        success "All images are available"
    else
        warn "Some images failed to pull (count: $failed_count)"
    fi
}

# Main function
main() {
    local command="${1:-update}"
    local environment="${2:-development}"
    local use_latest="${3:-true}"
    
    case "$command" in
        "update")
            show_current_versions
            update_compose_file "$environment" "$use_latest" true
            validate_compose
            show_current_versions
            ;;
        "show")
            show_current_versions
            ;;
        "validate")
            validate_compose
            ;;
        "test")
            test_image_availability
            ;;
        "restore")
            local backup_file="${2:-}"
            if [ -z "$backup_file" ]; then
                # Find the most recent backup
                backup_file=$(ls -t "${COMPOSE_FILE}.backup-"* 2>/dev/null | head -n1)
            fi
            
            if [ -f "$backup_file" ]; then
                cp "$backup_file" "$COMPOSE_FILE"
                success "Restored from backup: $backup_file"
            else
                error "No backup file found"
            fi
            ;;
        "help"|*)
            cat << EOF
Usage: $0 [COMMAND] [ENVIRONMENT] [USE_LATEST]

Commands:
  update      Update Docker Compose file with configured image versions (default)
  show        Show current image versions in Docker Compose file
  validate    Validate Docker Compose configuration
  test        Test availability of all images
  restore     Restore from backup file
  help        Show this help message

Environments:
  development (default) - Use latest tags where configured
  production           - Use pinned versions for stability
  testing             - Use known-good versions

Examples:
  $0 update development true    # Update to latest versions (default)
  $0 update production false    # Update to production-pinned versions
  $0 show                       # Show current versions
  $0 test                       # Test if all images can be pulled
  $0 restore                    # Restore from most recent backup

Configuration file: $CONFIG_FILE
Target file: $COMPOSE_FILE
EOF
            ;;
    esac
}

# Check dependencies
if ! command -v docker >/dev/null 2>&1; then
    error "Docker is required but not installed"
fi

if ! command -v docker-compose >/dev/null 2>&1; then
    error "Docker Compose is required but not installed"
fi

# Run main function with all arguments
main "$@"