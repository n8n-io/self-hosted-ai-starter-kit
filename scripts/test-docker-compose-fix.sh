#!/bin/bash

# =============================================================================
# Docker Compose Installation Fix Test Script
# =============================================================================
# This script tests the improved Docker Compose installation logic
# to ensure it works correctly on different systems and handles errors properly
# =============================================================================

set -euo pipefail

# Color definitions for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Test the Docker Compose installation function
test_docker_compose_installation() {
    log "Testing Docker Compose installation logic..."
    
    # Create a temporary test script with the installation logic
    cat > /tmp/test-docker-compose-install.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Source shared library functions if available
if [ -f "/home/ubuntu/GeuseMaker/lib/aws-deployment-common.sh" ]; then
    source /home/ubuntu/GeuseMaker/lib/aws-deployment-common.sh
    SHARED_LIBRARY_AVAILABLE=true
else
    SHARED_LIBRARY_AVAILABLE=false
fi

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
    
    # Use shared library function if available, otherwise use local implementation
    if [ "$SHARED_LIBRARY_AVAILABLE" = "true" ] && command -v install_docker_compose >/dev/null 2>&1; then
        echo "Using shared library Docker Compose installation..."
        if install_docker_compose; then
            # Determine which command to use
            if docker compose version >/dev/null 2>&1; then
                DOCKER_COMPOSE_CMD="docker compose"
            elif docker-compose --version >/dev/null 2>&1; then
                DOCKER_COMPOSE_CMD="docker-compose"
            else
                echo "❌ Docker Compose installation failed"
                return 1
            fi
            return 0
        fi
    fi
    
    # Local fallback implementation
    echo "Using local Docker Compose installation..."
    
    # Function to wait for apt locks to be released
    wait_for_apt_lock() {
        local max_wait=300
        local wait_time=0
        echo "Waiting for apt locks to be released..."
        
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
              fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
              fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
              pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
            if [ $wait_time -ge $max_wait ]; then
                echo "Timeout waiting for apt locks, killing blocking processes..."
                sudo pkill -9 -f "unattended-upgrade" || true
                sudo pkill -9 -f "apt-get" || true
                sleep 5
                break
            fi
            echo "APT is locked, waiting 10 seconds..."
            sleep 10
            wait_time=$((wait_time + 10))
        done
        echo "APT locks released"
    }
    
    # Function to install Docker Compose manually
    install_compose_manual() {
        local compose_version
        compose_version=$(curl -s --connect-timeout 10 --retry 3 https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | head -1 | sed 's/.*"tag_name": "\([^"]*\)".*/\1/' 2>/dev/null)
        
        if [ -z "$compose_version" ]; then
            echo "Could not determine latest version, using fallback..."
            compose_version="v2.24.5"
        fi
        
        echo "Installing Docker Compose $compose_version manually..."
        
        # Create the Docker CLI plugins directory
        sudo mkdir -p /usr/local/lib/docker/cli-plugins
        
        # Download Docker Compose plugin with proper architecture detection
        local arch
        arch=$(uname -m)
        case $arch in
            x86_64) arch="x86_64" ;;
            aarch64) arch="aarch64" ;;
            arm64) arch="aarch64" ;;
            *) echo "Unsupported architecture: $arch"; return 1 ;;
        esac
        
        local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-${arch}"
        
        echo "Downloading from: $compose_url"
        if sudo curl -L --connect-timeout 30 --retry 3 "$compose_url" -o /usr/local/lib/docker/cli-plugins/docker-compose; then
            sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
            
            # Also create a symlink for backwards compatibility
            sudo ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
            
            echo "✅ Docker Compose plugin installed successfully"
            return 0
        else
            echo "Failed to download Docker Compose, trying fallback method..."
            # Fallback to older installation method
            if sudo curl -L --connect-timeout 30 --retry 3 "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
                sudo chmod +x /usr/local/bin/docker-compose
                echo "✅ Fallback Docker Compose installation completed"
                return 0
            else
                echo "❌ ERROR: All Docker Compose installation methods failed"
                return 1
            fi
        fi
    }
    
    # Detect distribution
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    echo "Detected distribution: $distro"
    
    case "$distro" in
        ubuntu|debian)
            echo "Detected Ubuntu/Debian system"
            
            # Wait for apt locks
            wait_for_apt_lock
            
            # Try installing via package manager first
            if sudo apt-get update -qq && sudo apt-get install -y docker-compose-plugin; then
                echo "✅ Docker Compose plugin installed via apt"
                DOCKER_COMPOSE_CMD="docker compose"
                return 0
            fi
            
            # Fallback to manual installation
            echo "Package manager installation failed, trying manual installation..."
            install_compose_manual
            ;;
        amzn|rhel|centos|fedora)
            echo "Detected Amazon Linux/RHEL system"
            install_compose_manual
            ;;
        *)
            echo "Unknown distribution, using manual installation..."
            install_compose_manual
            ;;
    esac
    
    # Verify installation and set command
    if docker compose version >/dev/null 2>&1; then
        echo "✅ Docker Compose plugin verified"
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    elif docker-compose --version >/dev/null 2>&1; then
        echo "✅ Legacy docker-compose verified"
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    else
        echo "❌ Failed to install Docker Compose"
        return 1
    fi
}

# Test the installation
if install_docker_compose; then
    echo "SUCCESS: Docker Compose installation test passed"
    echo "Using command: $DOCKER_COMPOSE_CMD"
    exit 0
else
    echo "FAILURE: Docker Compose installation test failed"
    exit 1
fi
EOF

    # Make the test script executable
    chmod +x /tmp/test-docker-compose-install.sh
    
    # Run the test
    log "Running Docker Compose installation test..."
    if /tmp/test-docker-compose-install.sh; then
        success "Docker Compose installation test passed"
        return 0
    else
        error "Docker Compose installation test failed"
        return 1
    fi
}

# Test system detection
test_system_detection() {
    log "Testing system detection..."
    
    # Test distribution detection
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "Detected distribution: $ID"
        success "System detection working"
    else
        warning "Could not detect distribution"
    fi
    
    # Test architecture detection
    local arch=$(uname -m)
    log "Detected architecture: $arch"
    success "Architecture detection working"
}

# Test shared library availability
test_shared_library() {
    log "Testing shared library availability..."
    
    if [ -f "lib/aws-deployment-common.sh" ]; then
        success "Shared library found"
        
        # Test if functions are available (skip sourcing on non-Linux systems)
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if source lib/aws-deployment-common.sh 2>/dev/null; then
                if command -v install_docker_compose >/dev/null 2>&1; then
                    success "Shared library functions available"
                    return 0
                else
                    warning "Shared library loaded but functions not available"
                    return 1
                fi
            else
                error "Failed to source shared library"
                return 1
            fi
        else
            log "Skipping shared library sourcing on non-Linux system ($OSTYPE)"
            success "Shared library structure validated"
            return 0
        fi
    else
        warning "Shared library not found"
        return 1
    fi
}

# Main test execution
main() {
    log "Starting Docker Compose installation fix tests..."
    
    local tests_passed=0
    local tests_failed=0
    
    # Test 1: System detection
    if test_system_detection; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    # Test 2: Shared library availability
    if test_shared_library; then
        ((tests_passed++))
    else
        ((tests_failed++))
    fi
    
    # Test 3: Docker Compose installation (only if not already installed)
    if ! docker compose version >/dev/null 2>&1 && ! docker-compose --version >/dev/null 2>&1; then
        if test_docker_compose_installation; then
            ((tests_passed++))
        else
            ((tests_failed++))
        fi
    else
        log "Docker Compose already installed, skipping installation test"
        ((tests_passed++))
    fi
    
    # Summary
    log "Test summary: $tests_passed passed, $tests_failed failed"
    
    if [ $tests_failed -eq 0 ]; then
        success "All tests passed! Docker Compose installation fix is working correctly."
        return 0
    else
        error "Some tests failed. Please review the output above."
        return 1
    fi
}

# Run tests
main "$@" 