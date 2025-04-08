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

# 1. Update system and install required packages using yum
yum update -y
yum install -y docker amazon-efs-utils nfs-utils jq git awscli

# Start and enable Docker service
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user  # allow ec2-user to run Docker without sudo

# 2. Install Docker Compose (latest version)
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version  # verify installation

# 3. Clone the AI Starter Kit repository into APP_DIR
mkdir -p "$(dirname "$APP_DIR")"
git clone "$REPO_URL" "$APP_DIR"

# 4. Hardcode AWS region to us-east-1
export AWS_DEFAULT_REGION="us-east-1"
echo "Using AWS region: $AWS_DEFAULT_REGION"

# 5. Retrieve environment variables from AWS SSM Parameter Store and write .env in APP_DIR
rm -f "$APP_DIR/.env"
for param in "${PARAM_NAMES[@]}"; do
    VALUE=$(aws ssm get-parameter --region us-east-1 --name "$param" --with-decryption --query "Parameter.Value" --output text)
    KEY=$(basename "$param")
    echo "$KEY=$VALUE" >> "$APP_DIR/.env"
done

# 6. Mount the EFS file system using the EFS ID from SSM
EFS_ID=$(aws ssm get-parameter --region us-east-1 --name "$EFS_PARAM_NAME" --query "Parameter.Value" --output text || echo "")
if [[ -n "$EFS_ID" ]]; then
    mkdir -p "$EFS_MOUNT_POINT"
    echo "${EFS_ID}:/ $EFS_MOUNT_POINT efs _netdev,tls,iam,region=${AWS_DEFAULT_REGION},nofail 0 0" >> /etc/fstab
    mount -a || { echo "ERROR: EFS mount failed" >&2; exit 1; }
    if mountpoint -q "$EFS_MOUNT_POINT"; then
        echo "EFS mounted at $EFS_MOUNT_POINT"
        # Get EFS DNS name and add it to .env file
        EFS_DNS="${EFS_ID}.efs.${AWS_DEFAULT_REGION}.amazonaws.com"
        echo "EFS_DNS=${EFS_DNS}" >> "$APP_DIR/.env"
        echo "EFS_DNS=${EFS_DNS}" >> /etc/environment
        source /etc/environment
    else
        echo "ERROR: EFS not mounted at $EFS_MOUNT_POINT" >&2
        exit 1
    fi
else
    echo "WARNING: No EFS ID provided. Skipping EFS mount."
    # Set a default local path for development/testing
    echo "EFS_DNS=localhost" >> "$APP_DIR/.env"
    echo "EFS_DNS=localhost" >> /etc/environment
    source /etc/environment
fi

# 7. Allocate subdirectories on EFS for each service and set permissions
mkdir -p /mnt/efs/n8n /mnt/efs/postgres /mnt/efs/ollama /mnt/efs/qdrant
chown -R 1000:1000 /mnt/efs/n8n       # n8n container runs as non-root (uid 1000)
chown -R 999:999   /mnt/efs/postgres   # Postgres container (uid 999)
chown -R 0:0     /mnt/efs/ollama       # Ollama runs as root
chown -R 0:0     /mnt/efs/qdrant       # Qdrant runs as root (adjust if needed)
chmod -R 770 /mnt/efs/n8n /mnt/efs/postgres /mnt/efs/ollama /mnt/efs/qdrant

# 8. Set up GPU support for Ollama
# Check for NVIDIA GPU
if lspci | grep -i nvidia > /dev/null; then
    echo "NVIDIA GPU detected. Installing NVIDIA drivers and container toolkit..."
    # Install NVIDIA drivers
    yum install -y nvidia-driver-latest-dkms
    # Install NVIDIA Container Toolkit
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/yum.repos.d/nvidia-docker.list
    yum install -y nvidia-container-toolkit
    systemctl restart docker
    # Test NVIDIA GPU access
    docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
    echo "NVIDIA GPU setup complete"
elif lspci | grep -i amd > /dev/null; then
    echo "AMD GPU detected. Setting up AMD GPU support..."
    # Install AMD drivers and ROCm
    yum install -y rocm-dkms
    # Add current user to video group
    usermod -aG video ec2-user
    # Create necessary device files if they don't exist
    mkdir -p /dev/dri
    mknod -m 666 /dev/dri/renderD128 c 226 128 || true
    mknod -m 666 /dev/kfd c 10 235 || true
    echo "AMD GPU setup complete"
else
    echo "No GPU detected. Ollama will run on CPU."
    # Remove GPU-specific device mounts from docker-compose.yml
    sed -i '/devices:/,/\/dev\/kfd/d' "$APP_DIR/docker-compose.yml"
    sed -i '/deploy:/,/capabilities: \[gpu\]/d' "$APP_DIR/docker-compose.yml"
fi

# 9. Launch the Docker Compose application
cd "$APP_DIR"
# Export EFS_DNS for docker-compose
export EFS_DNS=$(grep EFS_DNS "$APP_DIR/.env" | cut -d '=' -f2)
# Using the legacy docker-compose command; it automatically loads docker-compose.yml and .env from APP_DIR
docker-compose up -d

# 10. Print success message with public IP (fallback to local IP if not available)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || true)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 || true)
fi
echo "==============================================="
echo "AI Starter Kit deployment complete! Access n8n at: https://$PUBLIC_IP:5678/"
echo "==============================================="

# 11. Set up Spot Instance Termination Handling
cat <<'EOF' > /usr/local/bin/spot-termination-check.sh
#!/bin/bash
CHECK_INTERVAL=60
while true; do
  TERMINATION_TIME=$(curl -s http://169.254.169.254/latest/meta-data/spot/termination-time || true)
  if [ ! -z "$TERMINATION_TIME" ]; then
    echo "Spot instance termination notice received at $TERMINATION_TIME. Initiating graceful shutdown..."
    cd /opt/001-starter-kit && docker-compose down
    shutdown -h now
    exit 0
  fi
  sleep ${CHECK_INTERVAL}
done
EOF
chmod +x /usr/local/bin/spot-termination-check.sh
nohup /usr/local/bin/spot-termination-check.sh >/var/log/spot-termination.log 2>&1 &