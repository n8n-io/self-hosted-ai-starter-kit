#!/bin/bash
# =============================================================================
# Docker Compose Installation Shared Library
# =============================================================================
# This library provides robust Docker Compose installation functions
# that can be sourced by other scripts without name conflicts
# =============================================================================

# Function to wait for apt locks to be released
shared_wait_for_apt_lock() {
    local max_wait=300
    local wait_time=0
    echo "$(date): Waiting for apt locks to be released..."
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
            echo "$(date): Timeout waiting for apt locks, killing blocking processes..."
            sudo pkill -9 -f "unattended-upgrade" || true
            sudo pkill -9 -f "apt-get" || true
            sleep 5
            break
        fi
        echo "$(date): APT is locked, waiting 10 seconds..."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    echo "$(date): APT locks released"
}

# Function to install Docker Compose manually
shared_install_compose_manual() {
    local compose_version
    compose_version=$(curl -s --connect-timeout 10 --retry 3 https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | head -1 | sed 's/.*"tag_name": "\([^"]*\)".*/\1/' 2>/dev/null)
    
    if [ -z "$compose_version" ]; then
        echo "$(date): Could not determine latest version, using fallback..."
        compose_version="v2.24.5"
    fi
    
    echo "$(date): Installing Docker Compose $compose_version manually..."
    
    # Create the Docker CLI plugins directory
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    
    # Download Docker Compose plugin with proper architecture detection
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        arm64) arch="aarch64" ;;
        *) echo "$(date): Unsupported architecture: $arch"; return 1 ;;
    esac
    
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-${arch}"
    
    echo "$(date): Downloading from: $compose_url"
    if sudo curl -L --connect-timeout 30 --retry 3 "$compose_url" -o /usr/local/lib/docker/cli-plugins/docker-compose; then
        sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
        
        # Also create a symlink for backwards compatibility
        sudo ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
        
        echo "$(date): Docker Compose plugin installed successfully"
        return 0
    else
        echo "$(date): Failed to download Docker Compose, trying fallback method..."
        # Fallback to older installation method
        if sudo curl -L --connect-timeout 30 --retry 3 "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
            sudo chmod +x /usr/local/bin/docker-compose
            echo "$(date): Fallback Docker Compose installation completed"
            return 0
        else
            echo "$(date): ERROR: All Docker Compose installation methods failed"
            return 1
        fi
    fi
}

# Main shared Docker Compose installation function
shared_install_docker_compose() {
    # Detect distribution
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="$ID"
    fi
    
    echo "$(date): Detecting distribution: $distro"
    
    # Check if Docker Compose is already installed
    if command -v docker compose >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
        echo "$(date): Docker Compose already installed"
        # Verify it works
        if docker compose version >/dev/null 2>&1; then
            echo "$(date): Docker Compose plugin verified working"
            return 0
        elif docker-compose version >/dev/null 2>&1; then
            echo "$(date): Legacy docker-compose binary found, installing plugin version..."
        else
            echo "$(date): Docker Compose found but not working, reinstalling..."
        fi
    fi
    
    # Install Docker Compose plugin (preferred method)
    echo "$(date): Installing Docker Compose plugin..."
    
    case "$distro" in
        ubuntu|debian)
            # Install Docker Compose plugin via apt (Ubuntu 20.04+ and Debian 11+)
            echo "$(date): Attempting apt package manager installation..."
            shared_wait_for_apt_lock
            if apt-get update -qq && apt-get install -y docker-compose-plugin; then
                echo "$(date): Docker Compose plugin installed via apt"
                return 0
            else
                echo "$(date): Package manager installation failed, trying manual download..."
                shared_install_compose_manual
            fi
            ;;
        amzn|rhel|centos|fedora)
            # For Amazon Linux and RHEL-based systems, use manual installation
            echo "$(date): Installing via manual download for RHEL-based system..."
            shared_install_compose_manual
            ;;
        *)
            echo "$(date): Unknown distribution, using manual installation..."
            shared_install_compose_manual
            ;;
    esac
    
    # Verify installation
    shared_verify_docker_compose_installation
}

# Function to verify Docker Compose installation
shared_verify_docker_compose_installation() {
    echo "$(date): Verifying Docker Compose installation..."
    
    # Test Docker Compose plugin first (preferred)
    if docker compose version >/dev/null 2>&1; then
        local version
        version=$(docker compose version 2>/dev/null | head -1)
        echo "$(date): Docker Compose plugin verified: $version"
        return 0
    fi
    
    # Test legacy docker-compose binary
    if command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
        local version
        version=$(docker-compose version 2>/dev/null | head -1)
        echo "$(date): Legacy docker-compose verified: $version"
        return 0
    fi
    
    echo "$(date): ERROR: Neither 'docker compose' nor 'docker-compose' command found or working"
    return 1
}