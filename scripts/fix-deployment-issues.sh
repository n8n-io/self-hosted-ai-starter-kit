#!/bin/bash

# =============================================================================
# Fix Deployment Issues Script
# Addresses disk space, EFS mounting, and Parameter Store integration
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}" >&2; }
warning() { echo -e "${YELLOW}[WARNING] $1${NC}" >&2; }

# =============================================================================
# DISK SPACE MANAGEMENT
# =============================================================================

cleanup_docker_space() {
    log "Cleaning up Docker to free disk space..."
    
    # Stop all containers to free up space
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    # Remove unused containers, networks, images, and build cache
    docker system prune -af --volumes || true
    
    # Remove unused images more aggressively
    docker image prune -af || true
    
    # Clean up Docker overlay2 directory if needed
    local overlay_usage
    overlay_usage=$(du -sh /var/lib/docker/overlay2 2>/dev/null | cut -f1 || echo "0K")
    log "Docker overlay2 usage after cleanup: $overlay_usage"
    
    success "Docker cleanup completed"
}

expand_root_volume() {
    log "Checking and expanding root volume if needed..."
    
    # Get current disk usage
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt 80 ]; then
        warning "Root volume is ${disk_usage}% full. Attempting to expand..."
        
        # Get the root device
        local root_device
        root_device=$(lsblk -no PKNAME /dev/$(lsblk -no KNAME /))
        
        if [ -n "$root_device" ]; then
            # Resize the partition and filesystem
            sudo growpart "/dev/$root_device" 1 2>/dev/null || true
            sudo resize2fs "/dev/${root_device}1" 2>/dev/null || true
            
            success "Root volume expansion attempted"
        fi
    else
        log "Root volume usage is acceptable (${disk_usage}%)"
    fi
}

# =============================================================================
# EFS MOUNTING
# =============================================================================

setup_efs_mounting() {
    local stack_name="${1:-}"
    local aws_region="${2:-us-east-1}"
    
    if [ -z "$stack_name" ]; then
        error "Stack name required for EFS setup"
        return 1
    fi
    
    log "Setting up EFS mounting for stack: $stack_name"
    
    # Check if EFS exists for this stack
    local efs_id
    efs_id=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Name' && Value=='${stack_name}-efs']].FileSystemId" \
        --output text \
        --region "$aws_region" 2>/dev/null || echo "")
    
    if [ -z "$efs_id" ] || [ "$efs_id" = "None" ]; then
        warning "No EFS found for stack $stack_name. Creating one..."
        create_efs_for_stack "$stack_name" "$aws_region"
        return $?
    fi
    
    # Get EFS DNS name
    local efs_dns="${efs_id}.efs.${aws_region}.amazonaws.com"
    
    # Install EFS utils if not present
    if ! command -v mount.efs &> /dev/null; then
        log "Installing EFS utilities..."
        sudo apt-get update -qq
        sudo apt-get install -y amazon-efs-utils nfs-common
    fi
    
    # Create mount points
    sudo mkdir -p /mnt/efs/{data,models,logs,config}
    
    # Mount EFS
    log "Mounting EFS: $efs_dns"
    if ! mountpoint -q /mnt/efs; then
        sudo mount -t efs -o tls "$efs_id":/ /mnt/efs
        
        # Add to fstab for persistence
        if ! grep -q "$efs_id" /etc/fstab; then
            echo "$efs_id.efs.$aws_region.amazonaws.com:/ /mnt/efs efs tls,_netdev" | sudo tee -a /etc/fstab
        fi
        
        success "EFS mounted successfully"
    else
        log "EFS already mounted"
    fi
    
    # Set proper permissions
    sudo chown -R ubuntu:ubuntu /mnt/efs
    sudo chmod 755 /mnt/efs
    
    # Update environment file with EFS DNS
    if [ -f /home/ubuntu/GeuseMaker/.env ]; then
        if grep -q "EFS_DNS=" /home/ubuntu/GeuseMaker/.env; then
            sed -i "s/EFS_DNS=.*/EFS_DNS=$efs_dns/" /home/ubuntu/GeuseMaker/.env
        else
            echo "EFS_DNS=$efs_dns" >> /home/ubuntu/GeuseMaker/.env
        fi
    fi
    
    log "EFS DNS: $efs_dns"
}

create_efs_for_stack() {
    local stack_name="$1"
    local aws_region="$2"
    
    log "Creating EFS for stack: $stack_name"
    
    # Create EFS
    local efs_id
    efs_id=$(aws efs create-file-system \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --tags Key=Name,Value="${stack_name}-efs" Key=Stack,Value="$stack_name" \
        --query 'FileSystemId' \
        --output text \
        --region "$aws_region")
    
    if [ -z "$efs_id" ]; then
        error "Failed to create EFS"
        return 1
    fi
    
    # Wait for EFS to be available
    log "Waiting for EFS to be available..."
    aws efs wait file-system-available --file-system-id "$efs_id" --region "$aws_region"
    
    # Get VPC and subnet info
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "$aws_region")
    
    local subnet_ids
    mapfile -t subnet_ids < <(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
        --query 'Subnets[].SubnetId' \
        --output text | tr '\t' '\n')
    
    # Create security group for EFS
    local efs_sg_id
    efs_sg_id=$(aws ec2 create-security-group \
        --group-name "${stack_name}-efs-sg" \
        --description "EFS security group for $stack_name" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text \
        --region "$aws_region")
    
    # Add NFS rule to security group
    aws ec2 authorize-security-group-ingress \
        --group-id "$efs_sg_id" \
        --protocol tcp \
        --port 2049 \
        --cidr 10.0.0.0/8 \
        --region "$aws_region"
    
    # Create mount targets
    for subnet_id in "${subnet_ids[@]}"; do
        aws efs create-mount-target \
            --file-system-id "$efs_id" \
            --subnet-id "$subnet_id" \
            --security-groups "$efs_sg_id" \
            --region "$aws_region" 2>/dev/null || true
    done
    
    success "EFS created: $efs_id"
    echo "$efs_id"
}

# =============================================================================
# PARAMETER STORE INTEGRATION
# =============================================================================

setup_parameter_store_integration() {
    local stack_name="${1:-}"
    local aws_region="${2:-us-east-1}"
    
    if [ -z "$stack_name" ]; then
        error "Stack name required for Parameter Store setup"
        return 1
    fi
    
    log "Setting up Parameter Store integration for stack: $stack_name"
    
    # Create parameter store retrieval script
    cat > /home/ubuntu/GeuseMaker/scripts/get-parameters.sh << 'EOF'
#!/bin/bash

# Parameter Store Integration Script
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-GeuseMaker}"

get_parameter() {
    local param_name="$1"
    local default_value="${2:-}"
    
    # Try to get parameter from AWS Systems Manager
    local value
    value=$(aws ssm get-parameter \
        --name "/aibuildkit/$param_name" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "$default_value")
    
    if [ "$value" = "None" ] || [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Get all parameters and create environment file
{
    echo "# Auto-generated environment file from Parameter Store"
    echo "# Generated on: $(date)"
    echo ""
    
    # PostgreSQL Configuration
    echo "POSTGRES_DB=n8n"
    echo "POSTGRES_USER=n8n"
    echo "POSTGRES_PASSWORD=$(get_parameter 'POSTGRES_PASSWORD' "$(openssl rand -hex 32)")"
    echo ""
    
    # n8n Configuration
    echo "N8N_ENCRYPTION_KEY=$(get_parameter 'n8n/ENCRYPTION_KEY' "$(openssl rand -hex 32)")"
    echo "N8N_USER_MANAGEMENT_JWT_SECRET=$(get_parameter 'n8n/USER_MANAGEMENT_JWT_SECRET' "$(openssl rand -hex 32)")"
    echo "N8N_HOST=0.0.0.0"
    echo "N8N_PORT=5678"
    echo "N8N_PROTOCOL=http"
    echo ""
    
    # API Keys
    echo "OPENAI_API_KEY=$(get_parameter 'OPENAI_API_KEY')"
    echo "ANTHROPIC_API_KEY=$(get_parameter 'ANTHROPIC_API_KEY')"
    echo "DEEPSEEK_API_KEY=$(get_parameter 'DEEPSEEK_API_KEY')"
    echo "GROQ_API_KEY=$(get_parameter 'GROQ_API_KEY')"
    echo "TOGETHER_API_KEY=$(get_parameter 'TOGETHER_API_KEY')"
    echo "MISTRAL_API_KEY=$(get_parameter 'MISTRAL_API_KEY')"
    echo "GEMINI_API_TOKEN=$(get_parameter 'GEMINI_API_TOKEN')"
    echo ""
    
    # n8n Security Settings
    echo "N8N_CORS_ENABLE=$(get_parameter 'n8n/CORS_ENABLE' 'true')"
    echo "N8N_CORS_ALLOWED_ORIGINS=$(get_parameter 'n8n/CORS_ALLOWED_ORIGINS' '*')"
    echo "N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=$(get_parameter 'n8n/COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE' 'true')"
    echo ""
    
    # AWS Configuration
    echo "INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo '')"
    echo "INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo '')"
    echo "AWS_DEFAULT_REGION=$AWS_REGION"
    echo ""
    
    # Webhook URL
    local public_ip
    public_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'localhost')
    echo "WEBHOOK_URL=$(get_parameter 'WEBHOOK_URL' "http://$public_ip:5678")"
    echo ""
    
    # EFS Configuration
    echo "EFS_DNS=${EFS_DNS:-}"
    
} > /home/ubuntu/GeuseMaker/.env

chmod 600 /home/ubuntu/GeuseMaker/.env
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker/.env

echo "Environment file updated from Parameter Store"
EOF
    
    chmod +x /home/ubuntu/GeuseMaker/scripts/get-parameters.sh
    
    # Run the parameter retrieval
    cd /home/ubuntu/GeuseMaker
    STACK_NAME="$stack_name" AWS_REGION="$aws_region" ./scripts/get-parameters.sh
    
    success "Parameter Store integration completed"
}

# =============================================================================
# DOCKER OPTIMIZATION
# =============================================================================

optimize_docker_for_limited_space() {
    log "Optimizing Docker configuration for limited disk space..."
    
    # Create Docker daemon configuration for space optimization
    sudo mkdir -p /etc/docker
    cat << 'EOF' | sudo tee /etc/docker/daemon.json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.size=20G"
    ],
    "max-concurrent-downloads": 3,
    "max-concurrent-uploads": 3,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    }
}
EOF
    
    # Restart Docker to apply configuration
    sudo systemctl restart docker
    
    # Wait for Docker to be ready
    sleep 10
    
    success "Docker optimization completed"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local stack_name="${1:-}"
    local aws_region="${2:-us-east-1}"
    
    if [ -z "$stack_name" ]; then
        echo "Usage: $0 <stack-name> [aws-region]"
        echo "Example: $0 my-geuse-stack us-east-1"
        exit 1
    fi
    
    log "Starting deployment fixes for stack: $stack_name"
    
    # Fix disk space issues first
    cleanup_docker_space
    expand_root_volume
    optimize_docker_for_limited_space
    
    # Setup EFS mounting
    setup_efs_mounting "$stack_name" "$aws_region"
    
    # Setup Parameter Store integration
    setup_parameter_store_integration "$stack_name" "$aws_region"
    
    success "All deployment issues have been addressed!"
    
    log "Next steps:"
    log "1. Verify EFS is mounted: df -h | grep efs"
    log "2. Check environment variables: cat /home/ubuntu/GeuseMaker/.env"
    log "3. Restart Docker services: cd /home/ubuntu/GeuseMaker && docker-compose -f docker-compose.gpu-optimized.yml up -d"
}

# Execute main function with all arguments
main "$@"