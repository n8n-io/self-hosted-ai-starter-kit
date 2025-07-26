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

log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    htop \
    jq \
    awscli \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release

# =============================================================================
# DOCKER INSTALLATION
# =============================================================================

log "Installing Docker..."

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

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

# Create Docker logging configuration
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}
EOF

systemctl restart docker

# Create environment-specific configuration
mkdir -p /home/ubuntu/GeuseMaker/config
cat > /home/ubuntu/GeuseMaker/config/environment.env << EOF
# GeuseMaker Environment Configuration
STACK_NAME=$STACK_NAME
ENVIRONMENT=$ENVIRONMENT
AWS_REGION=$AWS_REGION
COMPOSE_FILE=$COMPOSE_FILE

# Service Configuration
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$(openssl rand -base64 32)

# Database Configuration
POSTGRES_PASSWORD=$(openssl rand -base64 32)
POSTGRES_DB=n8n
POSTGRES_USER=n8n

# Vector Database Configuration
QDRANT_API_KEY=$(openssl rand -base64 32)

# Monitoring Configuration
ENABLE_METRICS=true
LOG_LEVEL=info
EOF

chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/config/environment.env
chmod 600 /home/ubuntu/GeuseMaker/config/environment.env

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

# Health check endpoints and expected responses
declare -A HEALTH_ENDPOINTS=(
    ["n8n"]="http://localhost:5678/healthz"
    ["ollama"]="http://localhost:11434/api/tags"
    ["qdrant"]="http://localhost:6333/health"
    ["crawl4ai"]="http://localhost:11235/health"
)

# Service startup times (in seconds)
declare -A STARTUP_TIMES=(
    ["postgres"]=30
    ["qdrant"]=45
    ["ollama"]=60
    ["n8n"]=90
    ["crawl4ai"]=30
)

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
    if [ -n "${STARTUP_TIMES[$service]}" ]; then
        log "Waiting for $service to be ready (${STARTUP_TIMES[$service]}s)..."
        sleep "${STARTUP_TIMES[$service]}"
    fi
done

# Perform health checks
all_healthy=true
for service in "${!HEALTH_ENDPOINTS[@]}"; do
    endpoint="${HEALTH_ENDPOINTS[$service]}"
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
# Startup script for GeuseMaker services

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting GeuseMaker services..."

# Load environment variables
if [ -f config/environment.env ]; then
    set -a
    source config/environment.env
    set +a
fi

# Start services with Docker Compose
if [ -f "$COMPOSE_FILE" ]; then
    log "Starting services using $COMPOSE_FILE..."
    
    # Pull latest images first
    log "Pulling latest Docker images..."
    docker-compose -f "$COMPOSE_FILE" pull
    
    # Start services in background
    log "Starting services..."
    docker-compose -f "$COMPOSE_FILE" up -d
    
    # Wait for services to initialize
    log "Waiting for services to initialize..."
    sleep 60
    
    # Check service status
    log "Checking service status..."
    docker-compose -f "$COMPOSE_FILE" ps
    
    # Run health checks
    log "Running health checks..."
    ./health-check.sh
    
else
    log "Error: Compose file $COMPOSE_FILE not found"
    exit 1
fi

log "GeuseMaker services startup completed"
EOF

chmod +x /home/ubuntu/GeuseMaker/start-services.sh
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/start-services.sh

# Create improved health check script
cat > /home/ubuntu/GeuseMaker/health-check.sh << 'EOF'
#!/bin/bash
# Enhanced health check script for GeuseMaker services

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Health check endpoints and expected responses
declare -A HEALTH_ENDPOINTS=(
    ["n8n"]="http://localhost:5678/healthz"
    ["ollama"]="http://localhost:11434/api/tags"
    ["qdrant"]="http://localhost:6333/health"
    ["crawl4ai"]="http://localhost:11235/health"
)

# Service startup times (in seconds)
declare -A STARTUP_TIMES=(
    ["postgres"]=30
    ["qdrant"]=45
    ["ollama"]=60
    ["n8n"]=90
    ["crawl4ai"]=30
)

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
    if [ -n "${STARTUP_TIMES[$service]}" ]; then
        log "Waiting for $service to be ready (${STARTUP_TIMES[$service]}s)..."
        sleep "${STARTUP_TIMES[$service]}"
    fi
done

# Perform health checks
all_healthy=true
for service in "${!HEALTH_ENDPOINTS[@]}"; do
    endpoint="${HEALTH_ENDPOINTS[$service]}"
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