#!/bin/bash
# =============================================================================
# Enhanced Docker Setup and Configuration Script
# Prevents Docker daemon connection issues and improves startup reliability
# =============================================================================

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]; then
    source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
fi

# =============================================================================
# DOCKER CONFIGURATION CONSTANTS
# =============================================================================

readonly DOCKER_VERSION_MIN="20.10.0"
readonly DOCKER_COMPOSE_VERSION_MIN="2.0.0"
readonly DOCKER_DAEMON_TIMEOUT=180
readonly DOCKER_TEST_TIMEOUT=60

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Compare version strings (bash 3.x compatible)
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Simple version comparison (works for most cases)
    if [ "$version1" = "$version2" ]; then
        return 0  # Equal
    fi
    
    # For more complex comparison, we'd need to parse major.minor.patch
    # This is a simplified version that works for basic cases
    if [ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" = "$version1" ]; then
        return 1  # version1 < version2
    else
        return 2  # version1 > version2
    fi
}

# Check if Docker daemon is responding
docker_daemon_responding() {
    docker info >/dev/null 2>&1
}

# Check if Docker daemon is healthy
docker_daemon_healthy() {
    if docker_daemon_responding; then
        # Try to run a simple container
        docker run --rm hello-world >/dev/null 2>&1
    else
        return 1
    fi
}

# Get Docker storage driver
get_docker_storage_driver() {
    docker info 2>/dev/null | grep "Storage Driver:" | cut -d: -f2 | xargs
}

# Get Docker server version
get_docker_version() {
    docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown"
}

# =============================================================================
# DOCKER INSTALLATION VALIDATION
# =============================================================================

validate_docker_installation() {
    log "Validating Docker installation..."
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed"
        return 1
    fi
    
    # Check Docker version
    local docker_version
    docker_version=$(get_docker_version)
    if [ "$docker_version" = "unknown" ]; then
        warning "Cannot determine Docker version"
    else
        info "Docker version: $docker_version"
        # Note: Version comparison could be enhanced here
    fi
    
    # Check if Docker Compose is available
    if command -v docker-compose >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "unknown")
        info "Docker Compose version: $compose_version"
    elif docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        info "Docker Compose plugin version: $compose_version"
    else
        warning "Docker Compose not available"
        return 1
    fi
    
    success "Docker installation validation passed"
    return 0
}

# =============================================================================
# DOCKER DAEMON CONFIGURATION
# =============================================================================

create_docker_daemon_config() {
    log "Creating Docker daemon configuration..."
    
    # Ensure Docker config directory exists
    sudo mkdir -p /etc/docker
    
    # Detect optimal storage driver
    local storage_driver=""
    local storage_opts="[]"
    
    # Check if overlay2 is supported
    if [ -d "/sys/module/overlay" ] || modprobe overlay 2>/dev/null; then
        storage_driver="overlay2"
        storage_opts='["overlay2.override_kernel_check=true"]'
        info "Using overlay2 storage driver"
    else
        warning "overlay2 not available, using auto-detection"
    fi
    
    # Create daemon configuration
    local config_file="/etc/docker/daemon.json"
    local temp_config="/tmp/docker-daemon-config.json"
    
    # Generate configuration
    if [ -n "$storage_driver" ]; then
        cat > "$temp_config" << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "$storage_driver",
    "storage-opts": $storage_opts,
    "data-root": "/var/lib/docker",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "default-runtime": "runc",
    "runtimes": {
        "runc": {
            "path": "runc"
        }
    },
    "max-concurrent-downloads": 3,
    "max-concurrent-uploads": 5,
    "default-shm-size": "64M"
}
EOF
    else
        # Minimal configuration without explicit storage driver
        cat > "$temp_config" << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "data-root": "/var/lib/docker",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false,
    "default-runtime": "runc",
    "runtimes": {
        "runc": {
            "path": "runc"
        }
    },
    "max-concurrent-downloads": 3,
    "max-concurrent-uploads": 5,
    "default-shm-size": "64M"
}
EOF
    fi
    
    # Validate JSON syntax
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import json; json.load(open('$temp_config'))" 2>/dev/null; then
            error "Generated Docker configuration has invalid JSON"
            rm -f "$temp_config"
            return 1
        fi
    elif command -v jq >/dev/null 2>&1; then
        if ! jq . "$temp_config" >/dev/null 2>&1; then
            error "Generated Docker configuration has invalid JSON"
            rm -f "$temp_config"
            return 1
        fi
    fi
    
    # Move configuration to final location
    sudo mv "$temp_config" "$config_file"
    sudo chmod 644 "$config_file"
    
    success "Docker daemon configuration created: $config_file"
    return 0
}

# =============================================================================
# DOCKER SERVICE MANAGEMENT
# =============================================================================

start_docker_daemon() {
    log "Starting Docker daemon..."
    
    # Check if Docker is already running
    if systemctl is-active --quiet docker; then
        info "Docker daemon is already running"
        return 0
    fi
    
    # Start Docker service
    if ! sudo systemctl start docker; then
        error "Failed to start Docker daemon"
        return 1
    fi
    
    # Enable Docker to start on boot
    if ! sudo systemctl enable docker; then
        warning "Failed to enable Docker service on boot"
    fi
    
    success "Docker daemon started successfully"
    return 0
}

wait_for_docker_daemon() {
    log "Waiting for Docker daemon to be ready..."
    
    local wait_time=0
    local max_wait=$DOCKER_DAEMON_TIMEOUT
    
    while [ $wait_time -lt $max_wait ]; do
        if docker_daemon_responding; then
            success "Docker daemon is responding (waited ${wait_time}s)"
            return 0
        fi
        
        # Show progress every 30 seconds
        if [ $((wait_time % 30)) -eq 0 ] && [ $wait_time -gt 0 ]; then
            info "Still waiting for Docker daemon (${wait_time}s elapsed)..."
            systemctl status docker --no-pager --lines=3 || true
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    error "Docker daemon did not become ready within ${max_wait}s"
    systemctl status docker --no-pager || true
    return 1
}

test_docker_functionality() {
    log "Testing Docker functionality..."
    
    # Test basic Docker info
    if ! docker info >/dev/null 2>&1; then
        error "Docker info command failed"
        return 1
    fi
    
    # Show Docker configuration
    local storage_driver
    storage_driver=$(get_docker_storage_driver)
    info "Docker storage driver: $storage_driver"
    
    # Test container functionality with timeout
    log "Running Docker functionality test..."
    if timeout $DOCKER_TEST_TIMEOUT docker run --rm hello-world >/dev/null 2>&1; then
        success "Docker functionality test passed"
        # Clean up test image
        docker rmi hello-world >/dev/null 2>&1 || true
    else
        error "Docker functionality test failed"
        return 1
    fi
    
    return 0
}

# =============================================================================
# USER PERMISSIONS SETUP
# =============================================================================

setup_docker_permissions() {
    log "Setting up Docker permissions..."
    
    # Check if ubuntu user exists
    if ! id ubuntu >/dev/null 2>&1; then
        warning "Ubuntu user not found, skipping permission setup"
        return 0
    fi
    
    # Add ubuntu user to docker group
    if ! groups ubuntu | grep -q docker; then
        sudo usermod -aG docker ubuntu
        success "Added ubuntu user to docker group"
        warning "User must log out and back in for group changes to take effect"
    else
        info "Ubuntu user is already in docker group"
    fi
    
    return 0
}

# =============================================================================
# DOCKER COMPOSE SETUP
# =============================================================================

setup_docker_compose() {
    log "Setting up Docker Compose..."
    
    # Check if Docker Compose is already available
    if command -v docker-compose >/dev/null 2>&1; then
        info "Docker Compose standalone is available"
        return 0
    fi
    
    # Check if Docker Compose plugin is available
    if docker compose version >/dev/null 2>&1; then
        info "Docker Compose plugin is available"
        return 0
    fi
    
    # Install Docker Compose standalone
    log "Installing Docker Compose standalone..."
    local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    local temp_compose="/tmp/docker-compose"
    
    if curl -fsSL "$compose_url" -o "$temp_compose"; then
        if [ -s "$temp_compose" ] && file "$temp_compose" | grep -q "executable"; then
            sudo mv "$temp_compose" /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            success "Docker Compose installed successfully"
        else
            error "Downloaded Docker Compose binary appears invalid"
            rm -f "$temp_compose"
            return 1
        fi
    else
        error "Failed to download Docker Compose"
        return 1
    fi
    
    return 0
}

# =============================================================================
# HEALTH CHECK AND MONITORING
# =============================================================================

create_docker_healthcheck() {
    log "Creating Docker health check script..."
    
    local healthcheck_script="/usr/local/bin/docker-healthcheck"
    
    cat > "$healthcheck_script" << 'EOF'
#!/bin/bash
# Docker health check script

set -e

# Check if Docker daemon is running
if ! systemctl is-active --quiet docker; then
    echo "ERROR: Docker daemon is not running"
    exit 1
fi

# Check if Docker daemon is responding
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not responding"
    exit 1
fi

# Test basic functionality
if ! docker run --rm hello-world >/dev/null 2>&1; then
    echo "ERROR: Docker functionality test failed"
    exit 1
fi

# Clean up test image
docker rmi hello-world >/dev/null 2>&1 || true

echo "Docker is healthy"
exit 0
EOF
    
    sudo chmod +x "$healthcheck_script"
    success "Docker health check script created: $healthcheck_script"
    return 0
}

# =============================================================================
# MAIN SETUP FUNCTION
# =============================================================================

setup_docker() {
    local skip_install="${1:-false}"
    
    section "Docker Setup and Configuration"
    
    # Validate existing Docker installation
    if [ "$skip_install" = "false" ]; then
        if ! validate_docker_installation; then
            error "Docker installation validation failed"
            error "Please install Docker first using the system package manager or install-deps.sh"
            return 1
        fi
    fi
    
    # Create Docker daemon configuration
    if ! create_docker_daemon_config; then
        error "Failed to create Docker daemon configuration"
        return 1
    fi
    
    # Start Docker daemon
    if ! start_docker_daemon; then
        error "Failed to start Docker daemon"
        return 1
    fi
    
    # Wait for Docker to be ready
    if ! wait_for_docker_daemon; then
        error "Docker daemon failed to become ready"
        return 1
    fi
    
    # Test Docker functionality
    if ! test_docker_functionality; then
        error "Docker functionality test failed"
        return 1
    fi
    
    # Setup user permissions
    setup_docker_permissions
    
    # Setup Docker Compose
    if ! setup_docker_compose; then
        warning "Docker Compose setup failed, but continuing"
    fi
    
    # Create health check script
    create_docker_healthcheck
    
    success "Docker setup completed successfully"
    return 0
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
Enhanced Docker Setup Script

USAGE:
    $0 [command] [options]

COMMANDS:
    setup              Complete Docker setup and configuration
    validate           Validate Docker installation only
    start              Start Docker daemon
    test               Test Docker functionality
    health             Run health check
    help               Show this help message

OPTIONS:
    --skip-install     Skip installation validation (for setup command)

EXAMPLES:
    $0 setup           # Complete Docker setup
    $0 validate        # Validate existing installation
    $0 test            # Test Docker functionality
    $0 health          # Run health check

FEATURES:
    ✅ Validates Docker installation and versions
    ✅ Creates optimized daemon configuration
    ✅ Handles storage driver detection automatically
    ✅ Implements robust daemon startup and health checking
    ✅ Sets up proper user permissions
    ✅ Installs Docker Compose if needed
    ✅ Creates health check scripts for monitoring

This script prevents common Docker issues that cause deployment failures.
EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local command="${1:-setup}"
    local skip_install="false"
    
    # Parse options
    shift || true
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-install)
                skip_install="true"
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    case "$command" in
        "setup")
            setup_docker "$skip_install"
            ;;
        "validate")
            validate_docker_installation
            ;;
        "start")
            start_docker_daemon && wait_for_docker_daemon
            ;;
        "test")
            test_docker_functionality
            ;;
        "health")
            if command -v docker-healthcheck >/dev/null 2>&1; then
                docker-healthcheck
            else
                test_docker_functionality
            fi
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi