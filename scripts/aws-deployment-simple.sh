#!/bin/bash

# =============================================================================
# GeuseMaker - Simple AWS Deployment (On-Demand Instances)
# =============================================================================
# This script automates deployment using on-demand instances to avoid spot limits
# Features: Simplified setup, reliable deployment, quick startup
# Target: g4dn.xlarge with NVIDIA T4 GPU
# =============================================================================

set -euo pipefail

# =============================================================================
# CLEANUP ON FAILURE HANDLER
# =============================================================================

# Global flag to track if cleanup should run
CLEANUP_ON_FAILURE="${CLEANUP_ON_FAILURE:-true}"
RESOURCES_CREATED=false
STACK_NAME=""

cleanup_on_failure() {
    local exit_code=$?
    if [ "$CLEANUP_ON_FAILURE" = "true" ] && [ "$RESOURCES_CREATED" = "true" ] && [ $exit_code -ne 0 ] && [ -n "$STACK_NAME" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        error "🚨 Deployment failed! Running automatic cleanup for stack: $STACK_NAME"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Get script directory
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        # Use unified cleanup script if available (preferred)
        if [ -f "$script_dir/cleanup-consolidated.sh" ]; then
            log "Using unified cleanup script to remove all resources..."
            "$script_dir/cleanup-consolidated.sh" --force "$STACK_NAME" || {
                warning "Unified cleanup script failed, falling back to manual cleanup..."
                run_manual_cleanup
            }
        # Fallback to legacy cleanup script if it exists
        elif [ -f "$script_dir/cleanup-stack.sh" ]; then
            log "Using legacy cleanup script to remove resources..."
            "$script_dir/cleanup-stack.sh" "$STACK_NAME" || {
                warning "Legacy cleanup script failed, falling back to manual cleanup..."
                run_manual_cleanup
            }
        else
            log "No cleanup script found, running manual cleanup..."
            run_manual_cleanup
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warning "💡 To disable automatic cleanup, set CLEANUP_ON_FAILURE=false"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Manual cleanup function for fallback
run_manual_cleanup() {
    log "Running comprehensive manual cleanup..."
    
    # Cleanup EC2 instances
    log "Cleaning up EC2 instances..."
    local instance_ids
    instance_ids=$(aws ec2 describe-instances \
        --filters "Name=tag:Stack,Values=$STACK_NAME" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text --region "${AWS_REGION:-us-east-1}" 2>/dev/null || echo "")
    
    if [ -n "$instance_ids" ] && [ "$instance_ids" != "None" ]; then
        for instance_id in $instance_ids; do
            if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                aws ec2 terminate-instances --instance-ids "$instance_id" --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1 || true
                log "Terminated instance: $instance_id"
            fi
        done
    fi
    
    # Cleanup security groups
    log "Cleaning up security groups..."
    local sg_ids
    sg_ids=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${STACK_NAME}-*" \
        --query 'SecurityGroups[].GroupId' \
        --output text --region "${AWS_REGION:-us-east-1}" 2>/dev/null || echo "")
    
    if [ -n "$sg_ids" ] && [ "$sg_ids" != "None" ]; then
        for sg_id in $sg_ids; do
            if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
                # Wait a bit for instances to be terminated
                sleep 5
                aws ec2 delete-security-group --group-id "$sg_id" --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1 || true
                log "Deleted security group: $sg_id"
            fi
        done
    fi
    
    # Cleanup IAM resources
    log "Cleaning up IAM resources..."
    local profile_name=""
    if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then
        local clean_name
        clean_name=$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')
        profile_name="app-${clean_name}-profile"
    else
        profile_name="${STACK_NAME}-instance-profile"
    fi
    
    # Remove role from instance profile
    if aws iam get-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1; then
        local role_names
        role_names=$(aws iam get-instance-profile --instance-profile-name "$profile_name" \
            --query 'InstanceProfile.Roles[].RoleName' --output text 2>/dev/null || echo "")
        
        for role_name in $role_names; do
            if [ -n "$role_name" ]; then
                aws iam remove-role-from-instance-profile \
                    --instance-profile-name "$profile_name" \
                    --role-name "$role_name" >/dev/null 2>&1 || true
                log "Removed role $role_name from instance profile"
            fi
        done
        
        aws iam delete-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1 || true
        log "Deleted instance profile: $profile_name"
    fi
    
    # Delete IAM role
    local role_name="${STACK_NAME}-role"
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        # Detach policies first
        local policy_arns
        policy_arns=$(aws iam list-attached-role-policies --role-name "$role_name" \
            --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        for policy_arn in $policy_arns; do
            if [ -n "$policy_arn" ]; then
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" >/dev/null 2>&1 || true
                log "Detached policy: $policy_arn"
            fi
        done
        
        aws iam delete-role --role-name "$role_name" >/dev/null 2>&1 || true
        log "Deleted IAM role: $role_name"
    fi
    
    success "Manual cleanup completed for stack: $STACK_NAME"
}

# Register cleanup handler
trap cleanup_on_failure EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-g4dn.xlarge}"
KEY_NAME="${KEY_NAME:-GeuseMaker-key-simple}"
STACK_NAME="${STACK_NAME:-GeuseMaker-simple}"
PROJECT_NAME="${PROJECT_NAME:-GeuseMaker}"
SETUP_ALB="${SETUP_ALB:-false}"  # Setup Application Load Balancer
SETUP_CLOUDFRONT="${SETUP_CLOUDFRONT:-false}"  # Setup CloudFront distribution

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✅ [SUCCESS] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" >&2
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}" >&2
}

# =============================================================================
# SECURITY VALIDATION
# =============================================================================

# Get script directory for sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source security validation functions if available
if [ -f "$SCRIPT_DIR/security-validation.sh" ]; then
    source "$SCRIPT_DIR/security-validation.sh"
else
    warning "Security validation script not found at $SCRIPT_DIR/security-validation.sh"
fi

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq not found. Installing jq for JSON processing..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq || {
                error "Failed to install jq. Please install it manually."
                exit 1
            }
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq || {
                error "Failed to install jq. Please install it manually."
                exit 1
            }
        fi
    fi
    
    success "Prerequisites check completed"
}

# =============================================================================
# INFRASTRUCTURE SETUP
# =============================================================================

create_key_pair() {
    log "Setting up SSH key pair..."
    
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
        warning "Key pair $KEY_NAME already exists"
        return 0
    fi
    
    # Create key pair
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$AWS_REGION" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    
    chmod 600 "${KEY_NAME}.pem"
    success "Created SSH key pair: ${KEY_NAME}.pem"
}

create_security_group() {
    log "Creating security group..."
    
    # Check if security group exists
    SG_ID=$(aws ec2 describe-security-groups \
        --group-names "${STACK_NAME}-sg" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$SG_ID" != "None" ]]; then
        warning "Security group already exists: $SG_ID"
        echo "$SG_ID"
        return 0
    fi
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    # Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name "${STACK_NAME}-sg" \
        --description "Security group for GeuseMaker (Simple)" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' \
        --output text)
    
    # Add rules for common ports
    ports=(22 5678 11434 11235 6333)
    for port in "${ports[@]}"; do
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port "$port" \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"
    done
    
    success "Created security group: $SG_ID"
    echo "$SG_ID"
}

launch_instance() {
    local SG_ID="$1"
    
    log "Launching on-demand instance..."
    
    # Get latest Ubuntu AMI with GPU support
    AMI_ID=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters \
            "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*" \
            "Name=state,Values=available" \
        --region "$AWS_REGION" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    info "Using AMI: $AMI_ID"
    
    # Create user data script
    cat > user-data-simple.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Update system
apt-get update && apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install NVIDIA drivers and Docker GPU support
apt-get install -y ubuntu-drivers-common
ubuntu-drivers autoinstall

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit

# Configure Docker daemon for GPU
cat > /etc/docker/daemon.json << 'EODAEMON'
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EODAEMON

# Install additional tools
apt-get install -y jq curl wget git htop awscli

# Restart services
systemctl restart docker
systemctl enable docker

# Signal that setup is complete
touch /tmp/user-data-complete

EOF

    # Encode user data
    if [[ "$OSTYPE" == "darwin"* ]]; then
        USER_DATA=$(base64 -i user-data-simple.sh | tr -d '\n')
    else
        USER_DATA=$(base64 -w 0 user-data-simple.sh)
    fi
    
    # Launch instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --user-data "$USER_DATA" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${STACK_NAME}-gpu-instance},{Key=Project,Value=$PROJECT_NAME}]" \
        --region "$AWS_REGION" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
        error "Failed to launch instance"
        return 1
    fi
    
    # Wait for instance to be running
    log "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
    
    # Get public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    success "Instance launched: $INSTANCE_ID (IP: $PUBLIC_IP)"
    echo "$INSTANCE_ID:$PUBLIC_IP"
}

# =============================================================================
# APPLICATION DEPLOYMENT
# =============================================================================

wait_for_instance_ready() {
    local PUBLIC_IP="$1"
    
    log "Waiting for instance to be ready for SSH..."
    
    for i in {1..30}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" "test -f /tmp/user-data-complete" &> /dev/null; then
            success "Instance is ready!"
            return 0
        fi
        info "Attempt $i/30: Instance not ready yet, waiting 30 seconds..."
        sleep 30
    done
    
    error "Instance failed to become ready after 15 minutes"
    return 1
}

deploy_application() {
    local PUBLIC_IP="$1"
    local INSTANCE_ID="$2"
    
    log "Deploying GeuseMaker application..."
    
    # Create deployment script
    cat > deploy-app-simple.sh << EOF
#!/bin/bash
set -euo pipefail

echo "Starting GeuseMaker deployment..."

# Clone repository
git clone https://github.com/michael-pittman/001-starter-kit.git /home/ubuntu/GeuseMaker || true
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
cat > .env << 'EOFENV'
# PostgreSQL Configuration
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=n8n_password_$(openssl rand -hex 32)

# n8n Configuration
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -hex 32)
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://$PUBLIC_IP:5678

# n8n Security Settings
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=*
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

# AWS Configuration
INSTANCE_ID=$INSTANCE_ID
INSTANCE_TYPE=$INSTANCE_TYPE
AWS_DEFAULT_REGION=$AWS_REGION

# API Keys (empty by default - can be configured manually)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
MISTRAL_API_KEY=
GEMINI_API_TOKEN=

# EFS Configuration (not used in simple deployment)
EFS_DNS=
EOFENV

# Start GPU-optimized services
sudo -E docker-compose -f docker-compose.gpu-optimized.yml up -d

echo "Deployment completed!"
EOF

    # Copy application files and deploy
    log "Copying application files..."
    
    # Copy the entire repository
    rsync -avz --exclude '.git' --exclude 'node_modules' --exclude '*.log' \
        -e "ssh -o StrictHostKeyChecking=no -i ${KEY_NAME}.pem" \
        ./ "ubuntu@$PUBLIC_IP:/home/ubuntu/GeuseMaker/"
    
    # Run deployment
    log "Running deployment script..."
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" \
        "chmod +x /home/ubuntu/GeuseMaker/deploy-app-simple.sh && /home/ubuntu/GeuseMaker/deploy-app-simple.sh"
    
    success "Application deployment completed!"
}

# =============================================================================
# VALIDATION AND RESULTS
# =============================================================================

validate_deployment() {
    local PUBLIC_IP="$1"
    
    log "Validating deployment..."
    
    # Wait for services to start
    sleep 120
    
    local endpoints=(
        "http://$PUBLIC_IP:5678/healthz:n8n"
        "http://$PUBLIC_IP:11434/api/tags:Ollama"
        "http://$PUBLIC_IP:6333/healthz:Qdrant"
        "http://$PUBLIC_IP:11235/health:Crawl4AI"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r url service <<< "$endpoint_info"
        
        log "Testing $service at $url..."
        local retry=0
        local max_retries=5
        while [ $retry -lt $max_retries ]; do
            if curl -f -s "$url" > /dev/null 2>&1; then
                success "$service is healthy"
                break
            fi
            retry=$((retry+1))
            info "Attempt $retry/$max_retries: $service not ready, waiting 30s..."
            sleep 30
        done
        if [ $retry -eq $max_retries ]; then
            warning "$service may still be starting up"
        fi
    done
    
    success "Deployment validation completed!"
}

display_results() {
    local PUBLIC_IP="$1"
    local INSTANCE_ID="$2"
    
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}   AI STARTER KIT DEPLOYED!    ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${BLUE}Instance Information:${NC}"
    echo -e "  Instance ID: ${YELLOW}$INSTANCE_ID${NC}"
    echo -e "  Public IP: ${YELLOW}$PUBLIC_IP${NC}"
    echo -e "  Instance Type: ${YELLOW}$INSTANCE_TYPE${NC}"
    echo ""
    echo -e "${BLUE}Service URLs:${NC}"
    echo -e "  ${GREEN}n8n Workflow Editor:${NC}     http://$PUBLIC_IP:5678"
    echo -e "  ${GREEN}Crawl4AI Web Scraper:${NC}    http://$PUBLIC_IP:11235"
    echo -e "  ${GREEN}Qdrant Vector Database:${NC}  http://$PUBLIC_IP:6333"
    echo -e "  ${GREEN}Ollama AI Models:${NC}        http://$PUBLIC_IP:11434"
    echo ""
    echo -e "${BLUE}SSH Access:${NC}"
    echo -e "  ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Wait 5-10 minutes for all services to fully start"
    echo -e "  2. Access n8n at http://$PUBLIC_IP:5678 to set up workflows"
    echo -e "  3. Check service logs: ssh to instance and run 'docker-compose logs'"
    echo ""
    echo -e "${YELLOW}Cost Information:${NC}"
    echo -e "  - On-demand g4dn.xlarge: ~$0.75/hour (~$18/day)"
    echo -e "  - Remember to terminate when not in use!"
    echo ""
}

# =============================================================================
# CLEANUP FUNCTION
# =============================================================================

cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    
    # Terminate instance
    if [ ! -z "${INSTANCE_ID:-}" ]; then
        log "Terminating instance $INSTANCE_ID..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
    fi
    
    # Delete security group
    if [ ! -z "${SG_ID:-}" ]; then
        log "Deleting security group..."
        sleep 30  # Wait for dependencies
        aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" || true
    fi
    
    # Delete key pair
    log "Deleting key pair and temporary files..."
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$AWS_REGION" || true
    rm -f "${KEY_NAME}.pem" user-data-simple.sh deploy-app-simple.sh
    
    warning "Cleanup completed."
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    echo -e "${CYAN}"
    cat << 'EOF'
 _____ _____   _____ _             _            _   _ _ _   
|  _  |     | |   __| |_ ___ ___ _| |_ ___ ___  | | | |_| |_ 
|     |-   -| |__   |  _| .'|  _|  _| -_|  _|  | |_| | |  _|
|__|__|_____| |_____|_| |__,|_| |_| |___|_|    |___|_|_|_|  
                                                           
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Simple AWS Deployment (On-Demand Instances)${NC}"
    echo -e "${BLUE}Reliable | Fast Setup | No Spot Limits${NC}"
    echo ""
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    
    log "Starting simplified AWS deployment..."
    
    # Mark that we're starting to create resources
    RESOURCES_CREATED=true
    
    create_key_pair
    
    SG_ID=$(create_security_group)
    
    # Launch instance
    INSTANCE_INFO=$(launch_instance "$SG_ID")
    INSTANCE_ID=$(echo "$INSTANCE_INFO" | cut -d: -f1)
    PUBLIC_IP=$(echo "$INSTANCE_INFO" | cut -d: -f2)

    wait_for_instance_ready "$PUBLIC_IP"
    deploy_application "$PUBLIC_IP" "$INSTANCE_ID"
    validate_deployment "$PUBLIC_IP"
    
    display_results "$PUBLIC_IP" "$INSTANCE_ID"
    
    # Clean up temporary files
    rm -f user-data-simple.sh deploy-app-simple.sh
    
    success "GeuseMaker deployment completed successfully!"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --region REGION         AWS region (default: us-east-1)"
    echo "  --instance-type TYPE    Instance type (default: g4dn.xlarge)"
    echo "  --key-name NAME         SSH key name (default: GeuseMaker-key-simple)"
    echo "  --stack-name NAME       Stack name (default: GeuseMaker-simple)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 --region us-west-2                # Deploy in different region"
    echo "  $0 --instance-type g4dn.2xlarge      # Use larger instance"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --key-name)
            KEY_NAME="$2"
            shift 2
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@" 