#!/bin/bash

# Test script for Docker Compose installation logic
# This script tests the installation function that was added to deploy-app.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Test the Docker Compose installation function
test_docker_compose_installation() {
    log "Testing Docker Compose installation logic..."
    
    # Install Docker Compose if not present
    install_docker_compose() {
        echo "Checking Docker Compose installation..."
        
        # Check if docker compose plugin is available
        if docker compose version >/dev/null 2>&1; then
            echo "✅ Docker Compose plugin is already installed"
            DOCKER_COMPOSE_CMD="docker compose"
            return 0
        fi
        
        # Check if legacy docker-compose is available
        if docker-compose --version >/dev/null 2>&1; then
            echo "✅ Legacy docker-compose is available"
            DOCKER_COMPOSE_CMD="docker-compose"
            return 0
        fi
        
        echo "📦 Installing Docker Compose..."
        
        # Detect distribution
        if command -v apt-get >/dev/null 2>&1; then
            # Ubuntu/Debian
            echo "Detected Ubuntu/Debian system"
            
            # Try installing via package manager first
            if sudo apt-get update && sudo apt-get install -y docker-compose-plugin; then
                echo "✅ Docker Compose plugin installed via apt"
                DOCKER_COMPOSE_CMD="docker compose"
                return 0
            fi
            
            # Fallback to manual installation
            echo "Package manager installation failed, trying manual installation..."
            
            # Get latest version from GitHub
            COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v2.24.5")
            
            # Download and install Docker Compose plugin
            sudo mkdir -p /usr/local/lib/docker/cli-plugins
            sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/lib/docker/cli-plugins/docker-compose
            sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
            
            if docker compose version >/dev/null 2>&1; then
                echo "✅ Docker Compose plugin installed manually"
                DOCKER_COMPOSE_CMD="docker compose"
                return 0
            fi
            
        elif command -v yum >/dev/null 2>&1; then
            # Amazon Linux/RHEL
            echo "Detected Amazon Linux/RHEL system"
            
            # Manual installation for RHEL-based systems
            COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v2.24.5")
            
            sudo mkdir -p /usr/local/lib/docker/cli-plugins
            sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/lib/docker/cli-plugins/docker-compose
            sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
            
            if docker compose version >/dev/null 2>&1; then
                echo "✅ Docker Compose plugin installed"
                DOCKER_COMPOSE_CMD="docker compose"
                return 0
            fi
        fi
        
        # Final fallback - install legacy docker-compose
        echo "Plugin installation failed, installing legacy docker-compose..."
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        
        if docker-compose --version >/dev/null 2>&1; then
            echo "✅ Legacy docker-compose installed"
            DOCKER_COMPOSE_CMD="docker-compose"
            return 0
        fi
        
        echo "❌ Failed to install Docker Compose"
        return 1
    }
    
    # Test the installation
    if install_docker_compose; then
        success "Docker Compose installation test passed"
        echo "Using command: $DOCKER_COMPOSE_CMD"
        
        # Test the command
        if $DOCKER_COMPOSE_CMD version >/dev/null 2>&1; then
            success "Docker Compose command works correctly"
            $DOCKER_COMPOSE_CMD version
            return 0
        else
            error "Docker Compose command failed after installation"
            return 1
        fi
    else
        error "Docker Compose installation test failed"
        return 1
    fi
}

# Test Docker Compose command detection
test_command_detection() {
    log "Testing Docker Compose command detection..."
    
    # Test if docker compose plugin works
    if docker compose version >/dev/null 2>&1; then
        success "Docker Compose plugin is available"
        DOCKER_COMPOSE_CMD="docker compose"
    elif docker-compose --version >/dev/null 2>&1; then
        success "Legacy docker-compose is available"
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        error "No Docker Compose command found"
        return 1
    fi
    
    echo "Detected command: $DOCKER_COMPOSE_CMD"
    return 0
}

# Test Docker Compose configuration validation
test_compose_validation() {
    log "Testing Docker Compose configuration validation..."
    
    local compose_file="docker-compose.gpu-optimized.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        warning "Docker Compose file not found: $compose_file"
        return 0
    fi
    
    if $DOCKER_COMPOSE_CMD -f "$compose_file" config >/dev/null 2>&1; then
        success "Docker Compose configuration is valid"
        return 0
    else
        error "Docker Compose configuration validation failed"
        return 1
    fi
}

# Main test execution
main() {
    log "Starting Docker Compose installation tests..."
    
    local tests_passed=0
    local tests_failed=0
    
    # Test 1: Command detection
    if test_command_detection; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    # Test 2: Installation (if needed)
    if ! test_command_detection; then
        if test_docker_compose_installation; then
            ((tests_passed++))
        else
            ((tests_failed++))
        fi
    else
        log "Skipping installation test - Docker Compose already available"
        ((tests_passed++))
    fi
    
    # Test 3: Configuration validation
    if test_compose_validation; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    # Summary
    echo
    log "Test Summary:"
    echo "  Tests passed: $tests_passed"
    echo "  Tests failed: $tests_failed"
    
    if [[ $tests_failed -eq 0 ]]; then
        success "All Docker Compose tests passed!"
        return 0
    else
        error "Some Docker Compose tests failed"
        return 1
    fi
}

# Run the tests
main "$@" 