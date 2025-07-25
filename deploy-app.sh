#!/bin/bash
set -euo pipefail

echo "Starting GeuseMaker deployment..."

# Mount EFS
sudo mkdir -p /mnt/efs
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc fs-0e50ce2a955e271a1.efs.us-east-1.amazonaws.com:/ /mnt/efs
echo "fs-0e50ce2a955e271a1.efs.us-east-1.amazonaws.com:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,_netdev 0 0" | sudo tee -a /etc/fstab

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
EFS_DNS=fs-0e50ce2a955e271a1.efs.us-east-1.amazonaws.com
INSTANCE_ID=i-099011396a2feee90
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

# Start GPU-optimized services
export EFS_DNS=fs-0e50ce2a955e271a1.efs.us-east-1.amazonaws.com
sudo -E docker-compose -f docker-compose.gpu-optimized.yml up -d

echo "Deployment completed!"
