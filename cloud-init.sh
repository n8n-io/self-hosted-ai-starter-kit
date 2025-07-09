#!/bin/bash
set -euo pipefail  # Exit on error, unset variable usage, and pipe failures

# Variables (adjust these for your environment)
REPO_URL="https://github.com/michael-pittman/001-starter-kit.git"
APP_DIR="/opt/001-starter-kit"
EFS_MOUNT_POINT="/mnt/efs"
EFS_PARAM_NAME="/aibuildkit/efs-id"   # SSM parameter storing the EFS ID
# List of SSM parameters for environment variables
PARAM_NAMES=(
  "/aibuildkit/WEBHOOK_URL"
  "/aibuildkit/POSTGRES_DB"
  "/aibuildkit/POSTGRES_USER"
  "/aibuildkit/N8N_USER_MANAGEMENT_JWT_SECRET"
  "/aibuildkit/N8N_ENCRYPTION_KEY"
  "/aibuildkit/POSTGRES_PASSWORD"
  "/aibuildkit/ollama_api_key"
  "/aibuildkit/N8N_CORS_ALLOWED_ORIGINS"
  "/aibuildkit/N8N_CORS_ENABLE"
  "/aibuildkit/N8N_HOST"
  "/aibuildkit/N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE"
)

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
error_exit() {
    log "ERROR: $1" >&2
    exit 1
}

# 1. Update system and install required packages using yum
log "Updating system and installing required packages..."
yum update -y || error_exit "System update failed"
yum install -y docker amazon-efs-utils nfs-utils jq git awscli || error_exit "Package installation failed"

# Start and enable Docker service
log "Starting Docker service..."
systemctl enable docker && systemctl start docker || error_exit "Docker service start failed"
usermod -aG docker ec2-user  # allow ec2-user to run Docker without sudo

# 2. Install Docker Compose (latest version)
log "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose || error_exit "Docker Compose download failed"
chmod +x /usr/local/bin/docker-compose
docker-compose --version || error_exit "Docker Compose installation verification failed"

# 3. Enable Docker BuildKit for faster builds
log "Enabling Docker BuildKit..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "features": {
    "buildkit": true
  },
  "experimental": true,
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5,
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
systemctl restart docker || error_exit "Docker restart failed"

# 4. Clone the AI Starter Kit repository into APP_DIR
log "Cloning repository..."
mkdir -p "$(dirname "$APP_DIR")"
git clone "$REPO_URL" "$APP_DIR" || error_exit "Repository clone failed"

# 5. Hardcode AWS region to us-east-1
export AWS_DEFAULT_REGION="us-east-1"
log "Using AWS region: $AWS_DEFAULT_REGION"

# 6. Retrieve environment variables from AWS SSM Parameter Store and write .env in APP_DIR
log "Retrieving environment variables from SSM..."
rm -f "$APP_DIR/.env"
for param in "${PARAM_NAMES[@]}"; do
    VALUE=$(aws ssm get-parameter --region us-east-1 --name "$param" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
    if [[ -n "$VALUE" ]]; then
        KEY=$(basename "$param")
        echo "$KEY=$VALUE" >> "$APP_DIR/.env"
    else
        log "WARNING: Failed to retrieve parameter $param"
    fi
done

# 7. Mount the EFS file system using the EFS ID from SSM
log "Setting up EFS mount..."
EFS_ID=$(aws ssm get-parameter --region us-east-1 --name "$EFS_PARAM_NAME" --query "Parameter.Value" --output text 2>/dev/null || echo "")
if [[ -n "$EFS_ID" ]]; then
    mkdir -p "$EFS_MOUNT_POINT"
    echo "${EFS_ID}:/ $EFS_MOUNT_POINT efs _netdev,tls,iam,region=${AWS_DEFAULT_REGION},nofail 0 0" >> /etc/fstab
    mount -a || error_exit "EFS mount failed"
    if mountpoint -q "$EFS_MOUNT_POINT"; then
        log "EFS mounted at $EFS_MOUNT_POINT"
        # Get EFS DNS name and add it to .env file
        EFS_DNS="${EFS_ID}.efs.${AWS_DEFAULT_REGION}.amazonaws.com"
        echo "EFS_DNS=${EFS_DNS}" >> "$APP_DIR/.env"
        echo "EFS_DNS=${EFS_DNS}" >> /etc/environment
        source /etc/environment
    else
        error_exit "EFS not mounted at $EFS_MOUNT_POINT"
    fi
else
    log "WARNING: No EFS ID provided. Skipping EFS mount."
    # Set a default local path for development/testing
    echo "EFS_DNS=localhost" >> "$APP_DIR/.env"
    echo "EFS_DNS=localhost" >> /etc/environment
    source /etc/environment
fi

# 8. Allocate subdirectories on EFS for each service and set permissions
log "Setting up EFS directories and permissions..."
mkdir -p /mnt/efs/n8n /mnt/efs/postgres /mnt/efs/ollama /mnt/efs/qdrant
chown -R 1000:1000 /mnt/efs/n8n       # n8n container runs as non-root (uid 1000)
chown -R 999:999   /mnt/efs/postgres   # Postgres container (uid 999)
chown -R 0:0     /mnt/efs/ollama       # Ollama runs as root
chown -R 0:0     /mnt/efs/qdrant       # Qdrant runs as root (adjust if needed)
chmod -R 770 /mnt/efs/n8n /mnt/efs/postgres /mnt/efs/ollama /mnt/efs/qdrant

# 9. Set up GPU support for Ollama
log "Checking for GPU support..."
if lspci | grep -i nvidia > /dev/null; then
    log "NVIDIA GPU detected. Installing NVIDIA drivers and container toolkit..."
    # Install NVIDIA drivers
    yum install -y nvidia-driver-latest-dkms || log "WARNING: NVIDIA driver installation failed"
    # Install NVIDIA Container Toolkit
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add - || log "WARNING: NVIDIA GPG key addition failed"
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/yum.repos.d/nvidia-docker.list
    yum install -y nvidia-container-toolkit || log "WARNING: NVIDIA container toolkit installation failed"
    systemctl restart docker
    # Test NVIDIA GPU access
    docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi || log "WARNING: NVIDIA GPU test failed"
    log "NVIDIA GPU setup complete"
elif lspci | grep -i amd > /dev/null; then
    log "AMD GPU detected. Setting up AMD GPU support..."
    # Install AMD drivers and ROCm
    yum install -y rocm-dkms || log "WARNING: AMD ROCm installation failed"
    # Add current user to video group
    usermod -aG video ec2-user
    # Create necessary device files if they don't exist
    mkdir -p /dev/dri
    mknod -m 666 /dev/dri/renderD128 c 226 128 2>/dev/null || true
    mknod -m 666 /dev/kfd c 10 235 2>/dev/null || true
    log "AMD GPU setup complete"
else
    log "No GPU detected. Ollama will run on CPU."
    # Remove GPU-specific device mounts from docker-compose.yml
    sed -i '/devices:/,/\/dev\/kfd/d' "$APP_DIR/docker-compose.yml" 2>/dev/null || true
    sed -i '/deploy:/,/capabilities: \[gpu\]/d' "$APP_DIR/docker-compose.yml" 2>/dev/null || true
fi

# 10. Pre-build Docker images for efficiency with BuildKit
log "Pre-building Docker images with BuildKit..."
cd "$APP_DIR"

# Set BuildKit environment variables
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Create a build cache directory
mkdir -p /tmp/docker-build-cache

# Build images in parallel with BuildKit caching
log "Building images in parallel..."
docker buildx create --use --name multiarch-builder || true

# Build images with BuildKit
log "Building n8n image..."
docker buildx build --platform linux/amd64 --cache-from n8nio/n8n:latest --tag n8n-with-curl:latest -f Dockerfile.n8n . &
N8N_PID=$!

log "Building postgres image..."
docker buildx build --platform linux/amd64 --cache-from postgres:latest --tag postgres-with-curl:latest -f Dockerfile.postgres . &
POSTGRES_PID=$!

log "Building qdrant image..."
docker buildx build --platform linux/amd64 --cache-from qdrant/qdrant:latest --tag qdrant-with-curl:latest -f Dockerfile.qdrant . &
QDRANT_PID=$!

log "Building ollama image..."
docker buildx build --platform linux/amd64 --cache-from ollama/ollama:latest --tag ollama-with-curl:latest -f Dockerfile.ollama . &
OLLAMA_PID=$!

# Wait for all builds to complete
wait $N8N_PID $POSTGRES_PID $QDRANT_PID $OLLAMA_PID

# Verify all images were built successfully
log "Verifying image builds..."
if ! docker images | grep -q "n8n-with-curl"; then
    error_exit "n8n image build failed"
fi
if ! docker images | grep -q "postgres-with-curl"; then
    error_exit "postgres image build failed"
fi
if ! docker images | grep -q "qdrant-with-curl"; then
    error_exit "qdrant image build failed"
fi
if ! docker images | grep -q "ollama-with-curl"; then
    error_exit "ollama image build failed"
fi

log "All Docker images built successfully!"

# 11. Launch the Docker Compose application with BuildKit
log "Launching Docker Compose application..."
# Export EFS_DNS for docker-compose
export EFS_DNS=$(grep EFS_DNS "$APP_DIR/.env" | cut -d '=' -f2)

# Using Docker Compose with BuildKit and parallel builds
docker compose up -d --force-recreate --build --parallel --scale ollama-init=1 || error_exit "Docker Compose startup failed"

# 12. Wait for services to be healthy
log "Waiting for services to be healthy..."
sleep 30

# Check service health
log "Checking service health..."
docker compose ps

# 13. Print success message with public IP (fallback to local IP if not available)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || true)
fi
echo "==============================================="
echo "AI Starter Kit deployment complete!"
echo "Access n8n at: https://$PUBLIC_IP:5678/"
echo "Access Ollama at: http://$PUBLIC_IP:11434/"
echo "Access Qdrant at: http://$PUBLIC_IP:6333/"
echo "==============================================="

# 14. Set up Spot Instance Termination Handling
log "Setting up spot instance termination handling..."
cat <<'EOF' > /usr/local/bin/spot-termination-check.sh
#!/bin/bash
CHECK_INTERVAL=60
while true; do
  TERMINATION_TIME=$(curl -s http://169.254.169.254/latest/meta-data/spot/termination-time 2>/dev/null || true)
  if [ ! -z "$TERMINATION_TIME" ]; then
    echo "Spot instance termination notice received at $TERMINATION_TIME. Initiating graceful shutdown..."
    cd /opt/001-starter-kit && docker compose down
    shutdown -h now
    exit 0
  fi
  sleep ${CHECK_INTERVAL}
done
EOF
chmod +x /usr/local/bin/spot-termination-check.sh
nohup /usr/local/bin/spot-termination-check.sh >/var/log/spot-termination.log 2>&1 &
<<<<<<< HEAD

# 15. Set up log rotation for Docker
log "Setting up log rotation..."
cat > /etc/logrotate.d/docker << EOF
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=1M
    missingok
    delaycompress
    copytruncate
}
EOF

log "Deployment completed successfully!"
=======
>>>>>>> cef86fbd0accf87199bfceabf9bb74ca3bc144f9
