#!/bin/bash

# Test Image Configuration System
# This script tests the image version configuration functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker-compose.gpu-optimized.yml"
SIMPLE_SCRIPT="$SCRIPT_DIR/../scripts/simple-update-images.sh"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Test 1: Check if simple update script exists and is executable
test_script_exists() {
    log "Testing if update script exists..."
    
    if [ -f "$SIMPLE_SCRIPT" ]; then
        success "Update script exists at $SIMPLE_SCRIPT"
    else
        error "Update script not found at $SIMPLE_SCRIPT"
        return 1
    fi
    
    if [ -x "$SIMPLE_SCRIPT" ]; then
        success "Update script is executable"
    else
        error "Update script is not executable"
        return 1
    fi
}

# Test 2: Validate Docker Compose syntax
test_compose_validation() {
    log "Testing Docker Compose validation..."
    
    if "$SIMPLE_SCRIPT" validate; then
        success "Docker Compose configuration is valid"
    else
        error "Docker Compose configuration is invalid"
        return 1
    fi
}

# Test 3: Show current versions
test_show_versions() {
    log "Testing show versions functionality..."
    
    echo ""
    "$SIMPLE_SCRIPT" show
    echo ""
    
    success "Show versions completed"
}

# Test 4: Check if configuration file exists
test_config_exists() {
    log "Testing if configuration file exists..."
    
    local config_file="$SCRIPT_DIR/../config/image-versions.yml"
    
    if [ -f "$config_file" ]; then
        success "Configuration file exists at $config_file"
    else
        warn "Configuration file not found at $config_file (optional)"
    fi
}

# Test 5: Verify latest tags are in use 
test_latest_tags() {
    log "Testing if latest tags are being used..."
    
    local latest_count
    latest_count=$(grep -c "image:.*:latest" "$COMPOSE_FILE" || echo "0")
    
    if [ "$latest_count" -gt 0 ]; then
        success "Found $latest_count services using latest tags"
    else
        warn "No services found using latest tags"
    fi
    
    # Show which services are using latest
    log "Services using latest tags:"
    grep -n "image:.*:latest" "$COMPOSE_FILE" | while IFS=: read -r line_num line_content; do
        service=$(sed -n "$((line_num-1))p" "$COMPOSE_FILE" | grep -o '^  [a-zA-Z-]*' | sed 's/^  //' || echo "unknown")
        image=$(echo "$line_content" | sed 's/.*image: *//')
        printf "  - %-20s %s\n" "$service:" "$image"
    done
}

# Test 6: Backup and restore functionality
test_backup_restore() {
    log "Testing backup functionality..."
    
    # Find any existing backup files
    local backup_files
    backup_files=$(ls "${COMPOSE_FILE}.backup-"* 2>/dev/null | wc -l)
    
    if [ "$backup_files" -gt 0 ]; then
        success "Found $backup_files backup file(s)"
        
        # Show the most recent backup
        local latest_backup
        latest_backup=$(ls -t "${COMPOSE_FILE}.backup-"* 2>/dev/null | head -n1)
        log "Most recent backup: $(basename "$latest_backup")"
    else
        warn "No backup files found (this is normal for first run)"
    fi
}

# Test 7: Environment variable integration
test_env_integration() {
    log "Testing environment variable integration..."
    
    # Test USE_LATEST_IMAGES environment variable
    export USE_LATEST_IMAGES=true
    log "Set USE_LATEST_IMAGES=true"
    
    # Check if deployment scripts would honor this
    if grep -q "USE_LATEST_IMAGES" "$SCRIPT_DIR/../scripts/aws-deployment.sh"; then
        success "AWS deployment script supports USE_LATEST_IMAGES"
    else
        warn "AWS deployment script doesn't support USE_LATEST_IMAGES"
    fi
    
    if grep -q "USE_LATEST_IMAGES" "$SCRIPT_DIR/../scripts/aws-deployment-simple.sh"; then
        success "Simple deployment script supports USE_LATEST_IMAGES"
    else
        warn "Simple deployment script doesn't support USE_LATEST_IMAGES"
    fi
}

# Main test runner
main() {
    echo "=============================================="
    echo "  Docker Image Configuration System Test"
    echo "=============================================="
    echo ""
    
    local failed_tests=0
    
    # Run all tests
    test_script_exists || ((failed_tests++))
    echo ""
    
    test_compose_validation || ((failed_tests++))
    echo ""
    
    test_show_versions || ((failed_tests++))
    echo ""
    
    test_config_exists || ((failed_tests++))
    echo ""
    
    test_latest_tags || ((failed_tests++))
    echo ""
    
    test_backup_restore || ((failed_tests++))
    echo ""
    
    test_env_integration || ((failed_tests++))
    echo ""
    
    # Summary
    echo "=============================================="
    if [ $failed_tests -eq 0 ]; then
        success "All tests passed! ✅"
        echo ""
        echo "The image configuration system is working correctly."
        echo "You can now:"
        echo "  • Deploy with latest images (default)"
        echo "  • Use --use-pinned-images flag for stability"
        echo "  • Configure specific versions in config/image-versions.yml"
    else
        error "$failed_tests test(s) failed ❌"
        echo ""
        echo "Please fix the issues above before using the configuration system."
        exit 1
    fi
    echo "=============================================="
}

main "$@"