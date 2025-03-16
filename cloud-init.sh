#!/bin/bash
set -euo pipefail  # Exit on error, unset var usage, and pipe failures

# Variables (adjust these for your environment)
REPO_URL="https://github.com/michael-pittman/001-starter-kit.git"
APP_DIR="/opt/001-starter-kit"
EFS_MOUNT_POINT="/mnt/efs"
EFS_PARAM_NAME="/aibuildkit/efs-id"   # SSM Parameter name storing the EFS ID (example)
# If storing multiple app config params in SSM, you can list them below:
PARAM_NAMES=("/aibuildkit/WEBHOOK_URL" "/aibuildkit/POSTGRES_DB" "/aibuildkit/POSTGRES_USER" "/aibuildkit/N8N_USER_MANAGEMENT_JWT_SECRET" "/aibuildkit/N8N_ENCRYPTION_KEY" "/aibuildkit/POSTGRES_PASSWORD")  # example parameter keys

# 1. Update system and install necessary packages
yum update -y
yum install -y amazon-efs-utils nfs-utils docker git awscli

# Start and enable Docker service
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user  # allow ec2-user to run Docker without sudo (optional)

# 2. Install Docker Compose (latest version)
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version  # verify installation

# 3. Clone the AI Starter Kit repository
mkdir -p "$(dirname "$APP_DIR")"
git clone "$REPO_URL" "$APP_DIR"

# 4. Retrieve environment variables from AWS SSM Parameter Store
# Determine AWS region from instance metadata (supports IMDSv2 and IMDSv1)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 30" || true)
if [[ -n "$TOKEN" ]]; then
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
              http://169.254.169.254/latest/meta-data/placement/region)
else
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
fi
export AWS_DEFAULT_REGION="$REGION"

# Create .env file for Docker Compose
rm -f "$APP_DIR/.env"
for param in "${PARAM_NAMES[@]}"; do
    # Fetch parameter value (with decryption for SecureString)
    VALUE=$(aws ssm get-parameter --name "$param" --with-decryption --query "Parameter.Value" --output text)
    # Use the final part of the parameter name (after last '/' if present) as the env var key
    KEY=$(basename "$param")
    echo "$KEY=$VALUE" >> "$APP_DIR/.env"
done

# 5. Mount the EFS file system
# Retrieve EFS filesystem ID from SSM (if configured)
EFS_ID=$(aws ssm get-parameter --name "$EFS_PARAM_NAME" --query "Parameter.Value" --output text || echo "")
if [[ -n "$EFS_ID" ]]; then
    mkdir -p "$EFS_MOUNT_POINT"
    # Add to fstab for persistence and mount now
    echo "${EFS_ID}:/ $EFS_MOUNT_POINT efs _netdev,tls,iam,region=${REGION},nofail 0 0" >> /etc/fstab
    # Mount all filesystems from fstab (including EFS)
    mount -a || { echo "ERROR: EFS mount failed" >&2; exit 1; }
    # Verify mount succeeded
    if mountpoint -q "$EFS_MOUNT_POINT"; then
        echo "EFS mounted at $EFS_MOUNT_POINT"
    else
        echo "ERROR: EFS not mounted at $EFS_MOUNT_POINT" >&2
        exit 1
    fi
else
    echo "WARNING: No EFS ID provided. Skipping EFS mount."
fi

# 6. Launch the Docker Compose application
cd "$APP_DIR"
docker-compose up -d  # start all services in detached mode