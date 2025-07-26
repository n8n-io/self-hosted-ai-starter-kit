#!/bin/bash

# =============================================================================
# Comprehensive Docker Compose Testing Script
# =============================================================================
# This script consolidates Docker Compose installation and fix testing
# functionality into a single comprehensive test suite
# =============================================================================

set -euo pipefail

# Get script directory for consistent paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color definitions for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
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

# Global variables for tracking test results
TESTS_PASSED=0
TESTS_FAILED=0
DOCKER_COMPOSE_CMD=""

# =============================================================================
# DOCKER COMPOSE DETECTION FUNCTIONS
# =============================================================================

# Detect which Docker Compose command is available
detect_docker_compose_command() {
    log "Detecting Docker Compose command..."
    
    # Check if docker compose plugin is available
    if docker compose version >/dev/null 2>&1; then
        success "Docker Compose plugin is available"
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    fi
    
    # Check if legacy docker-compose is available
    if docker-compose --version >/dev/null 2>&1; then
        success "Legacy docker-compose is available"
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    fi
    
    error "No Docker Compose command found"
    return 1
}

# Test Docker Compose command detection
test_command_detection() {
    log "Testing Docker Compose command detection..."
    
    if detect_docker_compose_command; then
        success "Command detection test passed"
        echo "Detected command: $DOCKER_COMPOSE_CMD"
        return 0
    else
        error "Command detection test failed"
        return 1
    fi
}

# =============================================================================
# DOCKER COMPOSE INSTALLATION FUNCTIONS
# =============================================================================

# Create a comprehensive Docker Compose installation test
test_docker_compose_installation() {
    log "Testing Docker Compose installation logic..."
    
    # Create a temporary test script with the installation logic
    cat > /tmp/test-docker-compose-install.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Source shared library functions if available
SHARED_LIBRARY_AVAILABLE=false
if [ -f "$PWD/lib/aws-deployment-common.sh" ]; then
    source "$PWD/lib/aws-deployment-common.sh"
    SHARED_LIBRARY_AVAILABLE=true
elif [ -f "/home/ubuntu/GeuseMaker/lib/aws-deployment-common.sh" ]; then
    source /home/ubuntu/GeuseMaker/lib/aws-deployment-common.sh
    SHARED_LIBRARY_AVAILABLE=true
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
    
    # Run the test (only if Docker Compose is not already installed)
    log "Running Docker Compose installation test..."
    if ! docker compose version >/dev/null 2>&1 && ! docker-compose --version >/dev/null 2>&1; then
        if /tmp/test-docker-compose-install.sh; then
            success "Docker Compose installation test passed"
            return 0
        else
            error "Docker Compose installation test failed"
            return 1
        fi
    else
        log "Docker Compose already installed, skipping installation test"
        success "Installation test skipped (already installed)"
        return 0
    fi
}

# =============================================================================
# SYSTEM DETECTION TESTS
# =============================================================================

# Test system detection functionality
test_system_detection() {
    log "Testing system detection..."
    
    # Test distribution detection
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "Detected distribution: $ID"
        success "System detection working"
    else
        warning "Could not detect distribution"
        return 1
    fi
    
    # Test architecture detection
    local arch=$(uname -m)
    log "Detected architecture: $arch"
    success "Architecture detection working"
    return 0
}

# Test shared library availability
test_shared_library() {
    log "Testing shared library availability..."
    
    # Check for shared library in project lib directory
    if [ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]; then
        success "Shared library found in project"
        
        # Test if functions are available (skip sourcing on non-Linux systems)
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if source "$PROJECT_ROOT/lib/aws-deployment-common.sh" 2>/dev/null; then
                if command -v install_docker_compose >/dev/null 2>&1; then
                    success "Shared library functions available"
                    return 0
                else
                    warning "Shared library loaded but Docker Compose functions not available"
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
        warning "Shared library not found at expected location"
        return 1
    fi
}

# =============================================================================
# CONFIGURATION VALIDATION TESTS
# =============================================================================

# Test Docker Compose configuration validation
test_compose_configuration() {
    log "Testing Docker Compose configuration validation..."
    
    # Test main GPU-optimized configuration
    local compose_file="$PROJECT_ROOT/docker-compose.gpu-optimized.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        warning "GPU-optimized Docker Compose file not found: $compose_file"
        
        # Try the regular docker-compose.yml
        compose_file="$PROJECT_ROOT/docker-compose.yml"
        if [[ ! -f "$compose_file" ]]; then
            warning "No Docker Compose files found"
            return 1
        fi
    fi
    
    log "Validating configuration file: $(basename "$compose_file")"
    
    if [ -n "$DOCKER_COMPOSE_CMD" ] && $DOCKER_COMPOSE_CMD -f "$compose_file" config >/dev/null 2>&1; then
        success "Docker Compose configuration is valid"
        return 0
    else
        error "Docker Compose configuration validation failed"
        return 1
    fi
}

# Test Docker Compose service definitions
test_service_definitions() {
    log "Testing Docker Compose service definitions..."
    
    local compose_file="$PROJECT_ROOT/docker-compose.gpu-optimized.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        compose_file="$PROJECT_ROOT/docker-compose.yml"
        if [[ ! -f "$compose_file" ]]; then
            warning "No Docker Compose files found for service testing"
            return 1
        fi
    fi
    
    # Expected services in the AI starter kit
    local expected_services=("ollama" "postgres" "n8n" "qdrant")
    local services_found=0
    
    for service in "${expected_services[@]}"; do
        if grep -q "^[[:space:]]*${service}:" "$compose_file"; then
            log "Found service: $service"
            ((services_found++))
        else
            warning "Service not found: $service"
        fi
    done
    
    if [ $services_found -gt 0 ]; then
        success "Found $services_found expected services"
        return 0
    else
        error "No expected services found in Docker Compose configuration"
        return 1
    fi
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

# Test error handling for missing Docker daemon
test_docker_daemon_availability() {
    log "Testing Docker daemon availability..."
    
    if docker info >/dev/null 2>&1; then
        success "Docker daemon is running"
        return 0
    else
        warning "Docker daemon is not running or not accessible"
        return 1
    fi
}

# Test Docker permissions
test_docker_permissions() {
    log "Testing Docker permissions..."
    
    if docker ps >/dev/null 2>&1; then
        success "Docker permissions are correct"
        return 0
    else
        warning "Docker permissions issue detected (may need sudo or user group membership)"
        return 1
    fi
}

# =============================================================================
# COMPREHENSIVE TEST RUNNER
# =============================================================================

# Run a single test and track results
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log "Running test: $test_name"
    
    if $test_function; then
        success "Test passed: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        error "Test failed: $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Main test execution function
main() {
    log "Starting comprehensive Docker Compose tests..."
    
    # Initialize test counters
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Test 1: Docker daemon availability (prerequisite)
    run_test "Docker daemon availability" test_docker_daemon_availability
    
    # Test 2: Docker permissions
    run_test "Docker permissions" test_docker_permissions
    
    # Test 3: System detection
    run_test "System detection" test_system_detection
    
    # Test 4: Shared library availability
    run_test "Shared library availability" test_shared_library
    
    # Test 5: Command detection
    run_test "Docker Compose command detection" test_command_detection
    
    # Test 6: Installation (if needed)
    if [ -z "$DOCKER_COMPOSE_CMD" ]; then
        run_test "Docker Compose installation" test_docker_compose_installation
        # Re-detect command after installation
        detect_docker_compose_command
    else
        log "Skipping installation test - Docker Compose already available"
        ((TESTS_PASSED++))
    fi
    
    # Test 7: Configuration validation
    run_test "Docker Compose configuration validation" test_compose_configuration
    
    # Test 8: Service definitions
    run_test "Docker Compose service definitions" test_service_definitions
    
    # Summary
    echo
    log "Test Summary:"
    echo "  Tests passed: $TESTS_PASSED"
    echo "  Tests failed: $TESTS_FAILED"
    echo "  Total tests: $((TESTS_PASSED + TESTS_FAILED))"
    
    if [ -n "$DOCKER_COMPOSE_CMD" ]; then
        echo "  Docker Compose command: $DOCKER_COMPOSE_CMD"
        echo "  Version: $($DOCKER_COMPOSE_CMD version --short 2>/dev/null || echo "Unknown")"
    fi
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        success "All Docker Compose tests passed!"
        return 0
    else
        error "$TESTS_FAILED test(s) failed"
        return 1
    fi
}

# Cleanup function
cleanup() {
    # Remove temporary files
    rm -f /tmp/test-docker-compose-install.sh
}

# Set up signal handlers for cleanup
trap cleanup EXIT INT TERM

# Run the tests
main "$@"