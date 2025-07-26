#!/bin/bash
set -euo pipefail

echo "Starting GeuseMaker deployment..."

# Source shared library functions if available
if [ -f "/home/ubuntu/GeuseMaker/lib/aws-deployment-common.sh" ]; then
    source /home/ubuntu/GeuseMaker/lib/aws-deployment-common.sh
    SHARED_LIBRARY_AVAILABLE=true
else
    SHARED_LIBRARY_AVAILABLE=false
fi

# Install Docker Compose if not present
local_install_docker_compose() {
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
        
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ||               fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ||               fuser /var/lib/dpkg/lock >/dev/null 2>&1 ||               pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
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

# Install Docker Compose
if ! local_install_docker_compose; then
    echo "Error: Could not install Docker Compose. Deployment cannot continue."
    exit 1
fi

echo "Using Docker Compose command: $DOCKER_COMPOSE_CMD"

# Mount EFS
sudo mkdir -p /mnt/efs
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc fs-0f0559e6a7f8af500.efs.us-east-1.amazonaws.com:/ /mnt/efs
echo "fs-0f0559e6a7f8af500.efs.us-east-1.amazonaws.com:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,_netdev 0 0" | sudo tee -a /etc/fstab

# Clone repository if it doesn't exist
if [ ! -d "/home/ubuntu/GeuseMaker" ]; then
    git clone https://github.com/michael-pittman/001-starter-kit.git /home/ubuntu/GeuseMaker
fi
cd /home/ubuntu/GeuseMaker

# Update Docker images to latest versions (unless overridden)
if [ "${USE_LATEST_IMAGES:-true}" = "true" ]; then
    echo "Updating Docker images to latest versions..."
    if [ -f "scripts/simple-update-images.sh" ]; then
        chmod +x scripts/simple-update-images.sh
        ./scripts/simple-update-images.sh update
    else
        echo "Warning: Image update script not found, using default versions"
    fi
fi

# Create comprehensive .env file with all required variables
cat > .env << EOFENV
# PostgreSQL Configuration
POSTGRES_DB=n8n_db
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=n8n_password_$(openssl rand -hex 32)

# n8n Configuration
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -hex 32)
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5678

# n8n Security Settings
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=https://n8n.geuse.io,https://localhost:5678
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

# AWS Configuration
EFS_DNS=fs-0f0559e6a7f8af500.efs.us-east-1.amazonaws.com
INSTANCE_ID=i-0e48de2d6bedd03a9
AWS_DEFAULT_REGION=us-east-1
INSTANCE_TYPE=g4dn.xlarge

# Image version control
USE_LATEST_IMAGES=true

# API Keys (empty by default - can be configured via SSM)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
MISTRAL_API_KEY=
GEMINI_API_TOKEN=
EOFENV

# Start GPU-optimized services using the detected Docker Compose command
export EFS_DNS=fs-0f0559e6a7f8af500.efs.us-east-1.amazonaws.com
sudo -E $DOCKER_COMPOSE_CMD -f docker-compose.gpu-optimized.yml up -d

echo "Deployment completed!"
