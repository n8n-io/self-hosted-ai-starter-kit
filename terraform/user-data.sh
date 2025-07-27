#!/bin/bash
# =============================================================================
# EC2 User Data Script for GeuseMaker
# This script is executed when the instance first boots
# =============================================================================

set -euo pipefail

# Configuration from Terraform template with input validation
STACK_NAME="${stack_name}"
ENVIRONMENT="${environment}"
COMPOSE_FILE="${compose_file}"
ENABLE_NVIDIA="${enable_nvidia}"
LOG_GROUP="${log_group}"
AWS_REGION="${aws_region}"

# Input validation to prevent template injection
validate_input() {
    local input="$1"
    local name="$2"
    local pattern="${3:-^[a-zA-Z0-9-_.]+$}"
    
    if [[ ! "$input" =~ $pattern ]]; then
        echo "Error: Invalid $name: '$input' contains disallowed characters" >&2
        exit 1
    fi
    
    echo "$input"
}

# Validate all template inputs
STACK_NAME=$(validate_input "$STACK_NAME" "stack_name" '^[a-zA-Z0-9-]+$')
ENVIRONMENT=$(validate_input "$ENVIRONMENT" "environment" '^[a-zA-Z0-9-]+$')
COMPOSE_FILE=$(validate_input "$COMPOSE_FILE" "compose_file" '^[a-zA-Z0-9.-]+\.yml$')
LOG_GROUP=$(validate_input "$LOG_GROUP" "log_group" '^[a-zA-Z0-9-/_]+$')
AWS_REGION=$(validate_input "$AWS_REGION" "aws_region" '^[a-z0-9-]+$')

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/user-data.log
}

log "Starting GeuseMaker instance initialization..."
log "Stack: $STACK_NAME, Environment: $ENVIRONMENT"

# =============================================================================
# SYSTEM UPDATES
# =============================================================================

# Function to validate all dependencies before proceeding
validate_system_dependencies() {
    log "Validating system dependencies and requirements..."
    
    # Check available disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=15728640  # 15GB in KB (increased from 10GB)
    
    if [ "$available_space" -lt "$required_space" ]; then
        log "Error: Insufficient disk space. Available: $(($available_space/1024/1024))GB, Required: $(($required_space/1024/1024))GB"
        return 1
    fi
    
    # Check memory requirements
    local available_memory=$(free -k | awk 'NR==2{print $2}')
    local required_memory=3145728  # 3GB in KB
    
    if [ "$available_memory" -lt "$required_memory" ]; then
        log "Error: Insufficient memory. Available: $(($available_memory/1024/1024))GB, Required: $(($required_memory/1024/1024))GB"
        return 1
    fi
    
    # Check CPU requirements
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        log "Warning: Less than 2 CPU cores available. Performance may be impacted."
    fi
    
    # Check network connectivity
    if ! ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        log "Error: No internet connectivity available"
        return 1
    fi
    
    # Check for required kernel modules
    local required_modules=("overlay" "br_netfilter")
    for module in "${required_modules[@]}"; do
        if ! modprobe "$module" 2>/dev/null; then
            log "Warning: Unable to load kernel module: $module"
        fi
    done
    
    log "System dependency validation completed successfully"
    return 0
}

log "Updating system packages..."

# Validate system before proceeding
if ! validate_system_dependencies; then
    log "Error: System dependency validation failed. Cannot continue."
    exit 1
fi
export DEBIAN_FRONTEND=noninteractive

# Check for and handle existing package manager locks
wait_for_apt_lock() {
    local max_wait=600  # 10 minutes max
    local wait_time=0
    log "Waiting for package manager locks to be released..."
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
            log "Timeout waiting for package locks, attempting to resolve..."
            # Kill unattended upgrades that might be blocking
            pkill -f unattended-upgrade || true
            sleep 10
            break
        fi
        log "Package manager is locked, waiting 15 seconds..."
        sleep 15
        wait_time=$((wait_time + 15))
    done
    log "Package manager locks released"
}

wait_for_apt_lock

# Perform system updates with error handling
if ! apt-get update; then
    log "Initial apt update failed, retrying after clearing cache..."
    apt-get clean
    apt-get update || log "Warning: System update failed, continuing with installation"
fi

if ! apt-get upgrade -y; then
    log "Warning: System upgrade had issues, continuing with installation"
fi

# Install essential packages with comprehensive error handling
log "Installing essential packages..."
ESSENTIAL_PACKAGES="curl wget unzip git htop jq awscli build-essential ca-certificates gnupg lsb-release"
CRITICAL_PACKAGES="curl wget git"
OPTIONAL_PACKAGES="htop jq awscli build-essential"
SYSTEM_PACKAGES="ca-certificates gnupg lsb-release unzip"

# Install in groups with different priorities
install_package_group() {
    local group_name="$1"
    local packages="$2"
    local required="${3:-false}"
    
    log "Installing $group_name packages: $packages"
    
    if apt-get install -y $packages; then
        log "Successfully installed $group_name packages"
        return 0
    else
        log "Group installation failed for $group_name, trying individual packages..."
        local failed_packages=()
        
        for package in $packages; do
            if apt-get install -y "$package"; then
                log "Successfully installed $package"
            else
                log "Failed to install $package"
                failed_packages+=("$package")
                
                if [ "$required" = "true" ]; then
                    log "Error: Critical package $package failed to install"
                    return 1
                fi
            fi
        done
        
        if [ ${#failed_packages[@]} -gt 0 ]; then
            log "Warning: Failed to install packages: ${failed_packages[*]}"
        fi
        return 0
    fi
}

# Install system packages first
install_package_group "system" "$SYSTEM_PACKAGES" false

# Install critical packages (must succeed)
install_package_group "critical" "$CRITICAL_PACKAGES" true

# Install optional packages (can fail)
install_package_group "optional" "$OPTIONAL_PACKAGES" false

# Verify critical packages are available
log "Verifying critical packages..."
for critical_package in $CRITICAL_PACKAGES; do
    if ! command -v "$critical_package" >/dev/null 2>&1; then
        log "Error: Critical package $critical_package is not available after installation"
        # Try to install via snap or alternative methods
        if command -v snap >/dev/null 2>&1; then
            log "Attempting to install $critical_package via snap..."
            snap install "$critical_package" || log "Snap installation also failed for $critical_package"
        fi
        
        # Final check
        if ! command -v "$critical_package" >/dev/null 2>&1; then
            log "Error: Unable to install critical package $critical_package"
            exit 1
        fi
    else
        log "✓ $critical_package is available"
    fi
done

log "Essential packages installation completed"

# =============================================================================
# DOCKER INSTALLATION
# =============================================================================

log "Installing Docker..."

# Check if Docker is already installed
if command -v docker >/dev/null 2>&1; then
    log "Docker is already installed, checking version..."
    docker --version | tee -a /var/log/user-data.log
else
    # Add Docker's official GPG key
    log "Adding Docker repository..."
    mkdir -p /etc/apt/keyrings
    
    if ! curl -fsSL --retry 3 --connect-timeout 30 https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log "Error: Failed to add Docker GPG key"
        exit 1
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package list and install Docker Engine
    wait_for_apt_lock
    if ! apt-get update; then
        log "Error: Failed to update package list after adding Docker repository"
        exit 1
    fi
    
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log "Error: Failed to install Docker packages"
        exit 1
    fi
fi

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Install Docker Compose standalone
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

log "Docker installation completed"

# =============================================================================
# NVIDIA CONTAINER TOOLKIT (FOR GPU INSTANCES)
# =============================================================================

if [ "$ENABLE_NVIDIA" = "true" ]; then
    log "Installing NVIDIA Container Toolkit..."
    
    # Check if NVIDIA GPU is present
    if lspci | grep -i nvidia; then
        # Install NVIDIA drivers if not present
        if ! nvidia-smi >/dev/null 2>&1; then
            log "Installing NVIDIA drivers..."
            apt-get install -y ubuntu-drivers-common
            ubuntu-drivers autoinstall
        fi
        
        # Install NVIDIA Container Toolkit
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -fsSL https://nvidia.github.io/nvidia-docker/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-docker.list
        
        apt-get update
        apt-get install -y nvidia-container-toolkit
        
        # Configure Docker to use NVIDIA runtime
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
        
        log "NVIDIA Container Toolkit installation completed"
    else
        log "No NVIDIA GPU detected, skipping NVIDIA toolkit installation"
    fi
fi

# =============================================================================
# AWS CLOUDWATCH AGENT
# =============================================================================

log "Installing AWS CloudWatch Agent..."

# Download and install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb
dpkg -i /tmp/amazon-cloudwatch-agent.deb
rm /tmp/amazon-cloudwatch-agent.deb

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "GeuseMaker/$STACK_NAME",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": true
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "$LOG_GROUP",
                        "log_stream_name": "{instance_id}/user-data",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/docker.log",
                        "log_group_name": "$LOG_GROUP",
                        "log_stream_name": "{instance_id}/docker",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

log "CloudWatch agent installation completed"

# =============================================================================
# APPLICATION SETUP
# =============================================================================

log "Setting up application directory..."

# Create application directory
mkdir -p /home/ubuntu/GeuseMaker
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker

# Create Docker logging and storage configuration
mkdir -p /etc/docker

# Check available storage drivers and disk space
log "Checking Docker storage requirements and available drivers..."
AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
REQUIRED_SPACE=10485760  # 10GB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    log "Warning: Available disk space is less than 10GB. Consider expanding storage."
fi

# Enhanced Docker storage driver detection with comprehensive fallback
detect_docker_storage_driver() {
    log "Detecting optimal Docker storage driver..."
    
    # Initialize kernel modules that might be needed
    local required_modules="overlay br_netfilter"
    for module in $required_modules; do
        if ! lsmod | grep -q "^$module"; then
            log "Loading kernel module: $module"
            modprobe "$module" 2>/dev/null || log "Warning: Could not load $module module"
        fi
    done
    
    # Check filesystem type first for compatibility assessment
    local root_fs_type
    root_fs_type=$(df -T / | awk 'NR==2 {print $2}' 2>/dev/null || echo "unknown")
    log "Root filesystem type: $root_fs_type"
    
    # Check available disk space for storage driver requirements
    local available_space_gb
    available_space_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}' 2>/dev/null || echo "0")
    log "Available disk space: ${available_space_gb}GB"
    
    # Test overlay2 support (preferred modern driver)
    if test_overlay_support "overlay2"; then
        log "✓ overlay2 storage driver is supported and optimal"
        echo "overlay2"
        return 0
    fi
    
    # Test overlay support (fallback for older systems)
    if test_overlay_support "overlay"; then
        log "✓ overlay storage driver is supported (fallback)"
        echo "overlay"
        return 0
    fi
    
    # Check for aufs support (older Ubuntu systems)
    if [ "$root_fs_type" = "aufs" ] || lsmod | grep -q aufs; then
        log "✓ AUFS filesystem detected, using aufs driver"
        echo "aufs"
        return 0
    fi
    
    # VFS fallback (universal but slow)
    log "⚠ No optimal storage driver found, using vfs (universal but slow)"
    echo "vfs"
    return 0
}

# Test if a specific overlay storage driver is supported
test_overlay_support() {
    local driver="$1"
    
    # Check if the kernel module is available
    if ! modinfo "$driver" >/dev/null 2>&1; then
        log "  $driver module not available in kernel"
        return 1
    fi
    
    # Try to load the module
    if ! modprobe "$driver" 2>/dev/null; then
        log "  Failed to load $driver module"
        return 1
    fi
    
    # Check if the module is actually loaded
    if ! lsmod | grep -q "^$driver"; then
        log "  $driver module not loaded after modprobe"
        return 1
    fi
    
    # Check filesystem compatibility
    local root_fs_type
    root_fs_type=$(df -T / | awk 'NR==2 {print $2}' 2>/dev/null)
    
    case "$root_fs_type" in
        "ext4"|"xfs"|"btrfs")
            log "  Filesystem $root_fs_type is compatible with $driver"
            return 0
            ;;
        *)
            log "  Filesystem $root_fs_type may not be optimal for $driver"
            # Don't fail completely, just warn
            return 0
            ;;
    esac
}

# Detect storage driver and set appropriate options with error handling
STORAGE_DRIVER=""
STORAGE_OPTS='[]'

# Safely detect storage driver with fallback
if STORAGE_DRIVER=$(detect_docker_storage_driver 2>/dev/null); then
    log "Detected storage driver: $STORAGE_DRIVER"
else
    log "Storage driver detection failed, using auto-detection"
    STORAGE_DRIVER=""
fi

# Configure storage options based on detected driver
case "$STORAGE_DRIVER" in
    "overlay2")
        STORAGE_OPTS='["overlay2.override_kernel_check=true"]'
        log "Using overlay2 with kernel check override"
        ;;
    "overlay")
        STORAGE_OPTS='["overlay.override_kernel_check=true"]'
        log "Using overlay with kernel check override"
        ;;
    "aufs")
        STORAGE_OPTS='[]'
        log "Using aufs storage driver"
        ;;
    "vfs")
        STORAGE_OPTS='[]'
        log "Using vfs storage driver (fallback mode)"
        ;;
    "")
        # Auto-detection mode - let Docker choose
        STORAGE_OPTS='[]'
        log "Using Docker auto-detection for storage driver"
        ;;
    *)
        log "Warning: Unknown storage driver '$STORAGE_DRIVER', using auto-detection"
        STORAGE_DRIVER=""
        STORAGE_OPTS='[]'
        ;;
esac

# Create Docker daemon configuration with comprehensive error handling
create_docker_daemon_config() {
    local config_file="/etc/docker/daemon.json"
    local temp_config="/tmp/docker-daemon.json.tmp"
    
    log "Creating Docker daemon configuration..."
    
    # Create base configuration with proper JSON escaping
    local config_content
    if [ -n "$STORAGE_DRIVER" ] && [ "$STORAGE_DRIVER" != "auto" ]; then
        # Escape variables properly for JSON to prevent injection
        local escaped_storage_driver
        escaped_storage_driver=$(printf '%s' "$STORAGE_DRIVER" | sed 's/"/\\"/g' | sed "s/'/\\'/g")
        # Validate STORAGE_OPTS is valid JSON
        if ! echo "$STORAGE_OPTS" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
            log "Warning: STORAGE_OPTS contains invalid JSON, using empty array"
            STORAGE_OPTS='[]'
        fi
        config_content='{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "'"$escaped_storage_driver"'",
    "storage-opts": '"$STORAGE_OPTS"',
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
    }
}'
    else
        # Minimal configuration without explicit storage driver
        config_content='{
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
    }
}'
    fi
    
    # Write to temp file first
    echo "$config_content" > "$temp_config"
    
    # Validate JSON syntax before using it
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import json; json.load(open('$temp_config'))" 2>/dev/null; then
            log "Error: Generated Docker configuration has invalid JSON syntax"
            rm -f "$temp_config"
            return 1
        fi
    elif command -v jq >/dev/null 2>&1; then
        if ! jq '.' "$temp_config" >/dev/null 2>&1; then
            log "Error: Generated Docker configuration has invalid JSON syntax"
            rm -f "$temp_config"
            return 1
        fi
    else
        # Basic JSON validation using grep
        if ! grep -q '{' "$temp_config" || ! grep -q '}' "$temp_config"; then
            log "Error: Generated Docker configuration appears to be invalid"
            rm -f "$temp_config"
            return 1
        fi
    fi
    
    # Move validated config to final location
    mv "$temp_config" "$config_file"
    chmod 644 "$config_file"
    
    log "Docker daemon configuration created successfully"
    return 0
}

# Create the Docker configuration
if ! create_docker_daemon_config; then
    log "Failed to create Docker daemon config, creating minimal fallback"
    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}
EOF
    chmod 644 /etc/docker/daemon.json
fi

# Ensure Docker data directory exists with proper permissions
mkdir -p /var/lib/docker
chown root:root /var/lib/docker
chmod 700 /var/lib/docker

# Enhanced Docker service management with comprehensive error handling
manage_docker_service() {
    log "Managing Docker service startup..."
    
    # Check if Docker is already running and healthy
    if systemctl is-active --quiet docker && docker info >/dev/null 2>&1; then
        log "Docker is already running and healthy, checking configuration..."
        
        # Only restart if configuration has changed
        if [ -f /etc/docker/daemon.json ]; then
            local current_config_hash
            current_config_hash=$(md5sum /etc/docker/daemon.json 2>/dev/null | cut -d' ' -f1)
            local last_config_hash
            last_config_hash=$(cat /tmp/last-docker-config-hash 2>/dev/null || echo "")
            
            if [ "$current_config_hash" = "$last_config_hash" ]; then
                log "Docker configuration unchanged, skipping restart"
                return 0
            else
                log "Docker configuration changed, restart required"
                echo "$current_config_hash" > /tmp/last-docker-config-hash
            fi
        fi
    fi
    
    # Validate Docker configuration before restart
    log "Validating Docker daemon configuration..."
    if [ -f /etc/docker/daemon.json ]; then
        if ! validate_docker_config /etc/docker/daemon.json; then
            log "Warning: Docker configuration validation failed, using minimal config"
            create_minimal_docker_config
        fi
    else
        log "No Docker configuration found, creating minimal config"
        create_minimal_docker_config
    fi
    
    # Attempt graceful restart first
    log "Restarting Docker daemon..."
    if systemctl is-active --quiet docker; then
        if systemctl restart docker; then
            log "Docker restarted successfully"
        else
            log "Graceful restart failed, attempting stop and start..."
            systemctl stop docker
            sleep 5
            if ! systemctl start docker; then
                log "Docker start failed, attempting recovery..."
                recover_docker_service
            fi
        fi
    else
        log "Docker not running, starting fresh..."
        if ! systemctl start docker; then
            log "Docker start failed, attempting recovery..."
            recover_docker_service
        fi
    fi
    
    # Enable Docker to start on boot
    systemctl enable docker || log "Warning: Could not enable Docker service"
}

# Validate Docker configuration file
validate_docker_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log "Docker config file not found: $config_file"
        return 1
    fi
    
    # Test JSON syntax with multiple validators
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json; json.load(open('$config_file'))" 2>/dev/null; then
            return 0
        fi
    elif command -v jq >/dev/null 2>&1; then
        if jq '.' "$config_file" >/dev/null 2>&1; then
            return 0
        fi
    else
        # Basic validation - check for balanced braces
        local open_braces
        local close_braces
        open_braces=$(grep -o '{' "$config_file" | wc -l)
        close_braces=$(grep -o '}' "$config_file" | wc -l)
        if [ "$open_braces" -eq "$close_braces" ] && [ "$open_braces" -gt 0 ]; then
            return 0
        fi
    fi
    
    log "Docker configuration validation failed"
    return 1
}

# Create minimal Docker configuration
create_minimal_docker_config() {
    log "Creating minimal Docker configuration..."
    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "data-root": "/var/lib/docker"
}
EOF
    chmod 644 /etc/docker/daemon.json
}

# Recover Docker service when standard methods fail
recover_docker_service() {
    log "Attempting Docker service recovery..."
    
    # Clean up any existing Docker processes
    pkill -f dockerd || true
    sleep 5
    
    # Remove problematic configuration
    if [ -f /etc/docker/daemon.json ]; then
        mv /etc/docker/daemon.json /etc/docker/daemon.json.backup
        log "Backed up problematic Docker configuration"
    fi
    
    # Create absolute minimal configuration
    mkdir -p /etc/docker
    echo '{}' > /etc/docker/daemon.json
    chmod 644 /etc/docker/daemon.json
    
    # Try to start with minimal config
    if systemctl start docker; then
        log "Docker recovered with minimal configuration"
        return 0
    else
        log "Docker recovery failed, checking for deeper issues..."
        
        # Check for disk space issues
        local available_space
        available_space=$(df /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
        if [ "$available_space" -lt 1048576 ]; then  # Less than 1GB
            log "Critical: Low disk space may be preventing Docker startup"
            log "Available space: $(($available_space/1024))MB"
        fi
        
        # Check for permission issues
        if [ ! -w /var/lib/docker ]; then
            log "Critical: Permission issues with Docker data directory"
            chown -R root:root /var/lib/docker || true
            chmod 700 /var/lib/docker || true
        fi
        
        # Final attempt
        systemctl start docker || log "Critical: Docker could not be started even after recovery attempts"
    fi
}

# Execute Docker service management
manage_docker_service

# Enhanced Docker readiness check with intelligent backoff
wait_for_docker_ready() {
    log "Waiting for Docker to be ready..."
    local max_attempts=90  # Reduced from 120 to be more reasonable
    local docker_ready=false
    local last_error=""
    local consecutive_failures=0
    
    for i in $(seq 1 $max_attempts); do
        # Check if Docker is responding
        if docker info >/dev/null 2>&1; then
            log "✓ Docker is ready (attempt $i)"
            docker_ready=true
            break
        else
            # Capture the error for diagnostics
            last_error=$(docker info 2>&1 | head -n1 || echo "Unknown error")
            consecutive_failures=$((consecutive_failures + 1))
        fi
        
        # Provide periodic status updates and diagnostics
        case $i in
            15)
                log "Docker startup taking longer than expected, checking service status..."
                if systemctl is-active --quiet docker; then
                    log "Docker service is running, but not responding to API calls"
                else
                    log "Docker service is not active, attempting to start..."
                    systemctl start docker || true
                fi
                ;;
            30)
                log "Docker still not ready after 1 minute, checking logs..."
                journalctl -u docker --no-pager --lines=5 --since="5 minutes ago" || true
                log "Last error: $last_error"
                ;;
            45)
                log "Docker startup issues persist, checking system resources..."
                # Check disk space
                local free_space_mb
                free_space_mb=$(df /var/lib/docker | awk 'NR==2 {print int($4/1024)}' 2>/dev/null || echo "unknown")
                log "Available disk space: ${free_space_mb}MB"
                
                # Check if Docker daemon is actually running
                if ! pgrep -f dockerd >/dev/null; then
                    log "Docker daemon process not found, attempting restart..."
                    systemctl restart docker || true
                    sleep 10
                fi
                ;;
            60)
                log "Docker readiness check has failed multiple times, attempting recovery..."
                if [ $consecutive_failures -gt 30 ]; then
                    log "Too many consecutive failures, attempting service recovery..."
                    recover_docker_service
                    consecutive_failures=0
                    sleep 10
                fi
                ;;
            75)
                log "Final diagnostic check before timeout..."
                systemctl status docker --no-pager --lines=3 || true
                log "Docker socket status:"
                ls -la /var/run/docker.sock 2>/dev/null || log "Docker socket not found"
                ;;
        esac
        
        # Adaptive sleep timing - shorter at first, longer as we continue
        if [ $i -lt 30 ]; then
            sleep 2
        elif [ $i -lt 60 ]; then
            sleep 3
        else
            sleep 5
        fi
    done
    
    if [ "$docker_ready" = "true" ]; then
        log "✓ Docker is ready and operational"
        return 0
    else
        log "⚠ Docker readiness check timed out after $max_attempts attempts"
        log "Last error: $last_error"
        
        # Final status check
        if systemctl is-active --quiet docker; then
            log "Docker service is running but may have API issues"
        else
            log "Docker service is not running"
        fi
        
        return 1
    fi
}

# Execute the Docker readiness check
DOCKER_READY=false
if wait_for_docker_ready; then
    DOCKER_READY=true
else
    log "Warning: Proceeding despite Docker readiness issues"
fi

# Verify Docker configuration and log detailed information
log "Verifying Docker configuration..."
if [ "$DOCKER_READY" = "true" ]; then
    # Get detailed Docker info
    docker info 2>/dev/null | grep -E "(Storage Driver|Logging Driver|Cgroup Driver|Server Version)" || {
        log "Basic Docker info not available, checking if Docker daemon is running"
        systemctl is-active docker || log "Docker daemon is not active"
    }
    
    # Test basic Docker functionality
    if docker run --rm hello-world >/dev/null 2>&1; then
        log "Docker functionality test passed"
    else
        log "Warning: Docker functionality test failed"
    fi
else
    log "Warning: Docker readiness check failed, attempting to continue"
fi

# =============================================================================
# ENVIRONMENT VARIABLE INITIALIZATION
# =============================================================================

# Source the unified variable management library
PROJECT_ROOT="/home/ubuntu/GeuseMaker"
mkdir -p "$PROJECT_ROOT/lib"

# Download variable management library if not present
if [ ! -f "$PROJECT_ROOT/lib/variable-management.sh" ]; then
    log "Setting up variable management system..."
    
    # Create a temporary variable management system for bootstrap
    cat > "$PROJECT_ROOT/lib/variable-management.sh" << 'VARLIB_EOF'
#!/bin/bash
# Bootstrap Variable Management for EC2 Instance

var_log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $level: $*" | tee -a /var/log/user-data.log
}

generate_secure_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 2>/dev/null | tr -d '\n'
    else
        echo "secure_$(date +%s)_$(echo $$ | tail -c 6)"
    fi
}

generate_encryption_key() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32 2>/dev/null
    else
        echo "$(date +%s | sha256sum | cut -c1-64)"
    fi
}

check_aws_availability() {
    command -v aws >/dev/null 2>&1 && aws sts get-caller-identity >/dev/null 2>&1
}

get_parameter_store_value() {
    local param_name="$1"
    local default_value="$2"
    local region="${AWS_REGION:-us-east-1}"
    
    if check_aws_availability; then
        local value
        value=$(aws ssm get-parameter --name "$param_name" --with-decryption --region "$region" --query 'Parameter.Value' --output text 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$value" ] && [ "$value" != "None" ]; then
            echo "$value"
            return 0
        fi
    fi
    echo "$default_value"
    return 1
}

init_all_variables() {
    var_log INFO "Initializing environment variables with Parameter Store integration"
    
    # Critical variables with secure defaults
    export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(get_parameter_store_value '/aibuildkit/POSTGRES_PASSWORD' "$(generate_secure_password)")}"
    export N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(get_parameter_store_value '/aibuildkit/n8n/ENCRYPTION_KEY' "$(generate_encryption_key)")}"
    export N8N_USER_MANAGEMENT_JWT_SECRET="${N8N_USER_MANAGEMENT_JWT_SECRET:-$(get_parameter_store_value '/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET' "$(generate_secure_password)")}"
    
    # Optional variables
    export OPENAI_API_KEY="${OPENAI_API_KEY:-$(get_parameter_store_value '/aibuildkit/OPENAI_API_KEY' '')}"
    export WEBHOOK_URL="${WEBHOOK_URL:-$(get_parameter_store_value '/aibuildkit/WEBHOOK_URL' 'http://localhost:5678')}"
    export N8N_CORS_ENABLE="${N8N_CORS_ENABLE:-$(get_parameter_store_value '/aibuildkit/n8n/CORS_ENABLE' 'true')}"
    export N8N_CORS_ALLOWED_ORIGINS="${N8N_CORS_ALLOWED_ORIGINS:-$(get_parameter_store_value '/aibuildkit/n8n/CORS_ALLOWED_ORIGINS' '*')}"
    
    # Additional service variables
    export N8N_BASIC_AUTH_ACTIVE="${N8N_BASIC_AUTH_ACTIVE:-true}"
    export N8N_BASIC_AUTH_USER="${N8N_BASIC_AUTH_USER:-admin}"
    export N8N_BASIC_AUTH_PASSWORD="${N8N_BASIC_AUTH_PASSWORD:-$(generate_secure_password)}"
    export POSTGRES_DB="${POSTGRES_DB:-n8n}"
    export POSTGRES_USER="${POSTGRES_USER:-n8n}"
    export ENABLE_METRICS="${ENABLE_METRICS:-true}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"
    
    # Infrastructure variables
    export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
    
    var_log SUCCESS "Environment variables initialized successfully"
}

generate_docker_env_file() {
    local output_file="${1:-/home/ubuntu/GeuseMaker/config/environment.env}"
    
    var_log INFO "Generating Docker environment file: $output_file"
    
    mkdir -p "$(dirname "$output_file")"
    
    cat > "$output_file" << EOF
# =============================================================================
# GeuseMaker Environment Configuration
# Generated: $(date)
# =============================================================================

# Infrastructure Configuration
STACK_NAME=$STACK_NAME
ENVIRONMENT=$ENVIRONMENT
AWS_REGION=$AWS_REGION
COMPOSE_FILE=$COMPOSE_FILE
AWS_DEFAULT_REGION=$AWS_REGION

# Database Configuration
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# n8n Configuration
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET
N8N_BASIC_AUTH_ACTIVE=$N8N_BASIC_AUTH_ACTIVE
N8N_BASIC_AUTH_USER=$N8N_BASIC_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_BASIC_AUTH_PASSWORD
N8N_CORS_ENABLE=$N8N_CORS_ENABLE
N8N_CORS_ALLOWED_ORIGINS=$N8N_CORS_ALLOWED_ORIGINS

# API Keys
OPENAI_API_KEY=$OPENAI_API_KEY

# Service Configuration
WEBHOOK_URL=$WEBHOOK_URL
ENABLE_METRICS=$ENABLE_METRICS
LOG_LEVEL=$LOG_LEVEL

# Instance Information
EFS_DNS=\${EFS_DNS:-}
INSTANCE_ID=\${INSTANCE_ID:-}
INSTANCE_TYPE=\${INSTANCE_TYPE:-}
EOF
    
    chmod 600 "$output_file"
    chown ubuntu:ubuntu "$output_file"
    
    var_log SUCCESS "Docker environment file generated: $output_file"
}

validate_critical_variables() {
    var_log INFO "Validating critical variables"
    
    local validation_errors=()
    
    if [ -z "$POSTGRES_PASSWORD" ] || [ ${#POSTGRES_PASSWORD} -lt 8 ]; then
        validation_errors+=("POSTGRES_PASSWORD is not set or too short")
    fi
    
    if [ -z "$N8N_ENCRYPTION_KEY" ] || [ ${#N8N_ENCRYPTION_KEY} -lt 32 ]; then
        validation_errors+=("N8N_ENCRYPTION_KEY is not set or too short")
    fi
    
    if [ -z "$N8N_USER_MANAGEMENT_JWT_SECRET" ] || [ ${#N8N_USER_MANAGEMENT_JWT_SECRET} -lt 8 ]; then
        validation_errors+=("N8N_USER_MANAGEMENT_JWT_SECRET is not set or too short")
    fi
    
    if [ ${#validation_errors[@]} -eq 0 ]; then
        var_log SUCCESS "All critical variables are valid"
        return 0
    else
        var_log ERROR "Critical variable validation failed:"
        for error in "${validation_errors[@]}"; do
            var_log ERROR "  - $error"
        done
        return 1
    fi
}
VARLIB_EOF
    
    chmod +x "$PROJECT_ROOT/lib/variable-management.sh"
fi

# Source the variable management library
log "Loading variable management system..."
source "$PROJECT_ROOT/lib/variable-management.sh"

# Initialize all environment variables
if ! init_all_variables; then
    log "Warning: Variable initialization had issues, but continuing with defaults"
fi

# Validate critical variables
if ! validate_critical_variables; then
    log "Error: Critical variable validation failed"
    exit 1
fi

# Create configuration directory and generate environment file
mkdir -p /home/ubuntu/GeuseMaker/config
generate_docker_env_file "/home/ubuntu/GeuseMaker/config/environment.env"

# Create additional fallback environment file for Docker Compose
cat > /home/ubuntu/GeuseMaker/.env << EOF
# Docker Compose Environment File
# This file is automatically sourced by Docker Compose

# Database Configuration
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# n8n Configuration
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET
N8N_BASIC_AUTH_ACTIVE=$N8N_BASIC_AUTH_ACTIVE
N8N_BASIC_AUTH_USER=$N8N_BASIC_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_BASIC_AUTH_PASSWORD
N8N_CORS_ENABLE=$N8N_CORS_ENABLE
N8N_CORS_ALLOWED_ORIGINS=$N8N_CORS_ALLOWED_ORIGINS

# API Keys
OPENAI_API_KEY=$OPENAI_API_KEY

# Service Configuration
WEBHOOK_URL=$WEBHOOK_URL
ENABLE_METRICS=$ENABLE_METRICS
LOG_LEVEL=$LOG_LEVEL

# Infrastructure
AWS_REGION=$AWS_REGION
AWS_DEFAULT_REGION=$AWS_REGION
STACK_NAME=$STACK_NAME
ENVIRONMENT=$ENVIRONMENT
EOF

chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/.env
chmod 600 /home/ubuntu/GeuseMaker/.env

log "Environment variable initialization completed successfully"

log "Application setup completed"

# =============================================================================
# SECURITY HARDENING
# =============================================================================

log "Applying security hardening..."

# Configure automatic security updates
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
systemctl enable unattended-upgrades

# Configure fail2ban for SSH protection
apt-get install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Set up log rotation for Docker logs
cat > /etc/logrotate.d/docker << EOF
/var/log/docker.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        systemctl reload docker
    endscript
}
EOF

# Configure UFW firewall (basic setup)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 5678/tcp comment 'n8n'
ufw allow 11434/tcp comment 'Ollama'
ufw allow 6333/tcp comment 'Qdrant'
ufw allow 11235/tcp comment 'Crawl4AI'
ufw --force enable

log "Security hardening completed"

# =============================================================================
# MONITORING AND HEALTH CHECKS
# =============================================================================

log "Setting up monitoring and health checks..."

# Create health check script
cat > /home/ubuntu/GeuseMaker/health-check.sh << 'EOF'
#!/bin/bash
# Enhanced health check script for GeuseMaker services

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Health check endpoints and expected responses (bash 3.x compatible)
get_health_endpoint() {
    local service="$1"
    case "$service" in
        "n8n") echo "http://localhost:5678/healthz" ;;
        "ollama") echo "http://localhost:11434/api/tags" ;;
        "qdrant") echo "http://localhost:6333/health" ;;
        "crawl4ai") echo "http://localhost:11235/health" ;;
        *) return 1 ;;
    esac
}

# Service startup times (in seconds) (bash 3.x compatible)
get_startup_time() {
    local service="$1"
    case "$service" in
        "postgres") echo "30" ;;
        "qdrant") echo "45" ;;
        "ollama") echo "60" ;;
        "n8n") echo "90" ;;
        "crawl4ai") echo "30" ;;
        *) echo "30" ;;  # default
    esac
}

log "Starting comprehensive health checks..."

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    log "ERROR: Docker is not running"
    exit 1
fi

# Check if services are running
log "Checking Docker service status..."
docker-compose -f "$COMPOSE_FILE" ps

# Wait for services to be ready
for service in postgres qdrant ollama n8n crawl4ai; do
    local startup_time=$(get_startup_time "$service")
    if [ -n "$startup_time" ]; then
        log "Waiting for $service to be ready (${startup_time}s)..."
        sleep "$startup_time"
    fi
done

# Perform health checks
all_healthy=true
for service in n8n ollama qdrant crawl4ai; do
    endpoint=$(get_health_endpoint "$service")
    log "Checking $service at $endpoint..."
    
    # Try multiple times with increasing delays
    for attempt in {1..5}; do
        if curl -f -s --max-time 10 "$endpoint" > /dev/null 2>&1; then
            log "✅ $service is healthy"
            break
        else
            log "⚠️  $service health check attempt $attempt/5 failed"
            if [ $attempt -lt 5 ]; then
                sleep $((attempt * 10))
            else
                log "❌ $service failed all health checks"
                all_healthy=false
            fi
        fi
    done
done

if [ "$all_healthy" = true ]; then
    log "🎉 All services are healthy!"
    exit 0
else
    log "❌ Some services are unhealthy. Check logs with: docker-compose -f $COMPOSE_FILE logs"
    exit 1
fi
EOF

chmod +x /home/ubuntu/GeuseMaker/health-check.sh
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/health-check.sh

# Set up health check cron job
cat > /etc/cron.d/GeuseMaker-health << EOF
# Health check for GeuseMaker services
*/5 * * * * ubuntu /home/ubuntu/GeuseMaker/health-check.sh >> /var/log/health-check.log 2>&1
EOF

log "Monitoring setup completed"

# =============================================================================
# FINALIZATION
# =============================================================================

# Create startup script for services
cat > /home/ubuntu/GeuseMaker/start-services.sh << 'EOF'
#!/bin/bash
# Startup script for GeuseMaker services with comprehensive variable management

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/start-services.log
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a /var/log/start-services.log >&2
}

success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1" | tee -a /var/log/start-services.log
}

log "Starting GeuseMaker services with enhanced variable management..."

# =============================================================================
# VARIABLE INITIALIZATION
# =============================================================================

# Load variable management library if available
if [ -f lib/variable-management.sh ]; then
    log "Loading variable management library..."
    source lib/variable-management.sh
    
    # Initialize variables with Parameter Store integration
    if ! init_all_variables; then
        log "Warning: Variable initialization had issues, continuing with fallbacks"
    fi
    
    # Validate critical variables
    if command -v validate_critical_variables >/dev/null 2>&1; then
        if ! validate_critical_variables; then
            error "Critical variable validation failed"
            exit 1
        fi
    fi
    
    # Generate fresh environment file
    if command -v generate_docker_env_file >/dev/null 2>&1; then
        generate_docker_env_file ".env"
    fi
else
    log "Variable management library not found, using traditional approach"
fi

# Load environment variables from multiple sources
log "Loading environment variables..."

# 1. Load from config/environment.env if available
if [ -f config/environment.env ]; then
    log "Loading from config/environment.env"
    set -a
    source config/environment.env
    set +a
else
    log "Warning: config/environment.env not found"
fi

# 2. Load from .env file if available (Docker Compose default)
if [ -f .env ]; then
    log "Loading from .env file"
    set -a
    source .env
    set +a
else
    log "Warning: .env file not found"
fi

# 3. Emergency fallback - generate minimal required variables
if [ -z "${POSTGRES_PASSWORD:-}" ]; then
    log "Emergency: Generating POSTGRES_PASSWORD"
    export POSTGRES_PASSWORD="$(openssl rand -base64 32 2>/dev/null || echo "emergency_$(date +%s)")"
fi

if [ -z "${N8N_ENCRYPTION_KEY:-}" ]; then
    log "Emergency: Generating N8N_ENCRYPTION_KEY"
    export N8N_ENCRYPTION_KEY="$(openssl rand -hex 32 2>/dev/null || echo "emergency_$(date +%s)")"
fi

# Set default values for essential variables
export POSTGRES_DB="${POSTGRES_DB:-n8n}"
export POSTGRES_USER="${POSTGRES_USER:-n8n}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"

# =============================================================================
# VARIABLE VALIDATION AND LOGGING
# =============================================================================

log "Validating environment variables..."

# Check critical variables
local critical_vars="POSTGRES_PASSWORD N8N_ENCRYPTION_KEY"
local validation_passed=true

for var in $critical_vars; do
    local value
    eval "value=\$$var"
    if [ -z "$value" ]; then
        error "Critical variable $var is not set"
        validation_passed=false
    elif [ ${#value} -lt 8 ]; then
        error "Critical variable $var is too short (${#value} chars)"
        validation_passed=false
    else
        log "✓ $var is set (${#value} chars)"
    fi
done

if [ "$validation_passed" != "true" ]; then
    error "Variable validation failed"
    exit 1
fi

# Log non-sensitive variables for debugging
log "Environment summary:"
log "  POSTGRES_DB: ${POSTGRES_DB}"
log "  POSTGRES_USER: ${POSTGRES_USER}"
log "  AWS_REGION: ${AWS_REGION}"
log "  COMPOSE_FILE: ${COMPOSE_FILE:-docker-compose.gpu-optimized.yml}"

# =============================================================================
# DOCKER COMPOSE SERVICE MANAGEMENT
# =============================================================================

# Determine compose file to use
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.gpu-optimized.yml}"

if [ ! -f "$COMPOSE_FILE" ]; then
    error "Compose file not found: $COMPOSE_FILE"
    
    # Try fallback files
    local fallback_files="docker-compose.gpu-optimized.yml docker-compose.yml docker-compose.gpu.yml"
    for fallback in $fallback_files; do
        if [ -f "$fallback" ]; then
            log "Using fallback compose file: $fallback"
            COMPOSE_FILE="$fallback"
            break
        fi
    done
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "No valid compose file found"
        exit 1
    fi
fi

log "Using compose file: $COMPOSE_FILE"

# =============================================================================
# SERVICE STARTUP PROCESS
# =============================================================================

log "Starting Docker Compose services..."

# Step 1: Validate Docker Compose configuration
log "Validating Docker Compose configuration..."
if ! docker-compose -f "$COMPOSE_FILE" config >/dev/null 2>&1; then
    error "Docker Compose configuration is invalid"
    docker-compose -f "$COMPOSE_FILE" config || true
    exit 1
fi
success "Docker Compose configuration is valid"

# Step 2: Stop any existing services
log "Stopping any existing services..."
if docker-compose -f "$COMPOSE_FILE" ps -q | grep -q .; then
    log "Found running services, stopping them..."
    docker-compose -f "$COMPOSE_FILE" down || log "Warning: Some services may not have stopped cleanly"
else
    log "No running services found"
fi

# Step 3: Pull latest images
log "Pulling latest Docker images..."
if ! docker-compose -f "$COMPOSE_FILE" pull; then
    log "Warning: Failed to pull some images, continuing with local images"
fi

# Step 4: Start services
log "Starting services in background..."
if ! docker-compose -f "$COMPOSE_FILE" up -d; then
    error "Failed to start Docker services"
    
    # Show logs for debugging
    log "Showing Docker Compose logs for debugging:"
    docker-compose -f "$COMPOSE_FILE" logs --tail=50 || true
    exit 1
fi

# Step 5: Wait for services to initialize
log "Waiting for services to initialize..."
sleep 30

# Step 6: Check service status
log "Checking service status..."
docker-compose -f "$COMPOSE_FILE" ps

# Step 7: Verify services are actually running
log "Verifying service health..."
local failed_services=""
local running_services

if running_services=$(docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=running" 2>/dev/null); then
    log "Running services: $running_services"
else
    log "Unable to get service status"
fi

# Check for failed services
if failed_services=$(docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=exited" 2>/dev/null); then
    if [ -n "$failed_services" ]; then
        error "Failed services detected: $failed_services"
        
        # Show logs for failed services
        for service in $failed_services; do
            log "Logs for failed service $service:"
            docker-compose -f "$COMPOSE_FILE" logs --tail=20 "$service" || true
        done
        
        exit 1
    fi
fi

# =============================================================================
# HEALTH CHECKS
# =============================================================================

# Run health checks if available
if [ -f health-check.sh ]; then
    log "Running health checks..."
    if ! ./health-check.sh; then
        log "Warning: Health checks failed, but services appear to be running"
    else
        success "Health checks passed"
    fi
else
    log "Health check script not found, performing basic checks..."
    
    # Basic port checks
    local ports="5432 5678 6333 11434"
    for port in $ports; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log "✓ Port $port is listening"
        else
            log "- Port $port is not listening"
        fi
    done
fi

success "GeuseMaker services startup completed successfully!"

# =============================================================================
# POST-STARTUP INFORMATION
# =============================================================================

log "Service startup summary:"
docker-compose -f "$COMPOSE_FILE" ps

log "To monitor services:"
log "  docker-compose -f $COMPOSE_FILE logs -f"
log ""
log "To stop services:"
log "  docker-compose -f $COMPOSE_FILE down"
log ""
log "To restart services:"
log "  docker-compose -f $COMPOSE_FILE restart"

# Save startup information
cat > startup-info.txt << INFO_EOF
GeuseMaker Service Startup Information
======================================

Startup Time: $(date)
Compose File: $COMPOSE_FILE
Environment: ${ENVIRONMENT:-development}
Stack Name: ${STACK_NAME:-GeuseMaker}

Service Status:
$(docker-compose -f "$COMPOSE_FILE" ps)

Environment Variables Loaded:
- Database: ${POSTGRES_DB} (user: ${POSTGRES_USER})
- Region: ${AWS_REGION}
- Metrics: ${ENABLE_METRICS:-true}
- Log Level: ${LOG_LEVEL:-info}

Logs Location:
- Startup Log: /var/log/start-services.log
- Service Logs: docker-compose -f $COMPOSE_FILE logs

INFO_EOF

log "Startup information saved to startup-info.txt"
EOF

chmod +x /home/ubuntu/GeuseMaker/start-services.sh
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/start-services.sh

# Note: Health check script already created earlier in the script

# Automatically start services after user-data completion
log "Scheduling automatic service startup..."
cat > /home/ubuntu/GeuseMaker/auto-start.sh << 'EOF'
#!/bin/bash
# Automatic service startup script

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Wait for user-data to complete
while [ ! -f /tmp/user-data-complete ]; do
    log "Waiting for user-data script to complete..."
    sleep 10
done

log "User-data completed, starting services..."

# Change to GeuseMaker directory
cd /home/ubuntu/GeuseMaker

# Load environment
if [ -f config/environment.env ]; then
    set -a
    source config/environment.env
    set +a
fi

# Start services
./start-services.sh

log "Automatic service startup completed"
EOF

chmod +x /home/ubuntu/GeuseMaker/auto-start.sh
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/auto-start.sh

# Run auto-start in background
nohup /home/ubuntu/GeuseMaker/auto-start.sh > /var/log/auto-start.log 2>&1 &

# Signal completion
touch /tmp/user-data-complete
log "User data script completed successfully!"

# Final status message
cat > /home/ubuntu/GeuseMaker/deployment-info.txt << EOF
GeuseMaker Deployment Information
====================================

Stack Name: $STACK_NAME
Environment: $ENVIRONMENT
Deployment Time: $(date)

Instance Information:
- Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
- Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)
- Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
- Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

Services:
- n8n Workflow Automation: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5678
- Ollama LLM API: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):11434
- Qdrant Vector DB: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):6333
- Crawl4AI Service: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):11235

Next Steps:
1. SSH into the instance: ssh -i your-key.pem ubuntu@$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
2. Navigate to: cd GeuseMaker
3. Deploy application: ./start-services.sh
4. Check health: ./health-check.sh
5. Access n8n at the URL above to start building workflows

Configuration Files:
- Environment: config/environment.env
- Health Check: health-check.sh
- Service Startup: start-services.sh

Monitoring:
- CloudWatch Logs: $LOG_GROUP
- Health Check Log: /var/log/health-check.log
- User Data Log: /var/log/user-data.log

For troubleshooting, check the logs above or contact support.
EOF

chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/deployment-info.txt

log "Deployment information saved to /home/ubuntu/GeuseMaker/deployment-info.txt"

# End of user data script