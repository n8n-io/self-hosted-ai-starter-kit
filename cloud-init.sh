MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -e

# 1. Install updates and Docker
apt-get update && apt-get install -y docker.io docker-compose-plugin amazon-efs-utils jq

# 2. Mount EFS file system (assuming EFS ID is stored in an SSM parameter or known)
EFS_ID="$(aws ssm get-parameter --name "/myapp/efs-id" --query Parameter.Value --output text)"  # retrieve EFS FS ID from SSM
mkdir -p /mnt/efs
# Use EFS mount helper for mounting with TLS
mount -t efs ${EFS_ID}:/ /mnt/efs || { echo "EFS mount failed"; exit 1; }

# 3. Create dedicated directories on EFS for each service
mkdir -p /mnt/efs/n8n /mnt/efs/postgres /mnt/efs/ollama /mnt/efs/qdrant

# 4. Set appropriate permissions for each directory to avoid permission issues
# Assuming 'postgres' user inside container has uid/gid 999:999, and 'node' user for n8n is 1000:1000
chown -R 1000:1000 /mnt/efs/n8n       # n8n container runs as non-root user (uid 1000)
chown -R 999:999 /mnt/efs/postgres   # Postgres container default user (uid 999)
chown -R 0:0   /mnt/efs/ollama       # Ollama runs as root by default in official image
chown -R 0:0   /mnt/efs/qdrant       # Assume Qdrant runs as root (adjust if needed)

chmod -R 770 /mnt/efs/n8n /mnt/efs/postgres /mnt/efs/ollama /mnt/efs/qdrant

# 5. Retrieve secrets from AWS SSM and populate .env
echo "Fetching secrets from SSM Parameter Store..."
AWS_DEFAULT_REGION="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)"  # get region
export AWS_DEFAULT_REGION

# Example: fetch DB password and an n8n encryption key from SSM (parameters should exist and IAM role attached for access)
DB_PASSWORD=$(aws ssm get-parameter --with-decryption --name "/aibuildkit/POSTGRES_PASSWORD" --query Parameter.Value --output text)
ENCRYPTION_KEY=$(aws ssm get-parameter --with-decryption --name "/aibuildkit/N8N_ENCRYPTION_KEY" --query Parameter.Value --output text)
N8N_USER_MANAGEMENT_JWT_SECRET=$(aws ssm get-parameter --with-decryption --name "/aibuildkit/N8N_USER_MANAGEMENT_JWT_SECRET" --query Parameter.Value --output text)

# Write to .env file
cat > /opt/myapp/.env <<EOF
# .env file for docker-compose
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n_db
DB_POSTGRESDB_USER=n8n_user
DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
# Additional n8n configs
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
WEBHOOK_URL=https://n8n.geuse.io/
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}
EOF

# 6. Detect GPU and install NVIDIA components if present
if lspci | grep -qi "NVIDIA"; then
    echo "NVIDIA GPU detected, installing drivers and toolkit..."
    # (Installation commands for NVIDIA drivers and container toolkit appropriate for the OS)
    distribution=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    if [[ "$distribution" =~ ^\"?ubuntu\"?$ ]]; then
        apt-get install -y nvidia-driver-525 nvidia-container-toolkit
    else
        # Amazon Linux or others
        amazon-linux-extras install -y kernel-nvidia
        yum install -y nvidia-driver nvidia-container-toolkit
    fi
    # Enable GPU usage flag for containers (e.g., Ollama can use CUDA if available)
    echo "ENABLE_CUDA=1" >> /opt/myapp/.env
fi

# 7. Start Docker Compose to launch all containers
docker compose -f /opt/myapp/docker-compose.yml --env-file /opt/myapp/.env up -d
--==BOUNDARY==--
