#!/bin/bash

# =============================================================================
# AI-Powered Starter Kit - AWS Deployment Automation
# =============================================================================
# This script automates the complete deployment of the AI starter kit on AWS
# Features: EFS setup, GPU instances, cost optimization, monitoring
# Target: g4dn.xlarge with NVIDIA T4 GPU
# Cost Optimization: 70% savings with spot instances
# =============================================================================

set -euo pipefail

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
MAX_SPOT_PRICE="${MAX_SPOT_PRICE:-0.75}"
KEY_NAME="${KEY_NAME:-ai-starter-kit-key}"
STACK_NAME="${STACK_NAME:-ai-starter-kit}"
PROJECT_NAME="${PROJECT_NAME:-ai-starter-kit}"

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
    echo -e "${GREEN}[SUCCESS] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" >&2
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}" >&2
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker not found. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose not found. Please install Docker Compose first."
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

get_single_availability_zone() {
    aws ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text | awk '{print $1}'
}

get_all_availability_zones() {
    aws ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text
}

get_subnet_for_az() {
    local AZ="$1"
    aws ec2 describe-subnets \
        --filters "Name=availability-zone,Values=$AZ" "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[0].SubnetId' \
        --output text
}

# Add SSM fetch function after utility functions
fetch_ssm_params() {
    log "Fetching parameters from AWS SSM..."
    
    # List of parameters to fetch
    params=(
        "/aibuildkit/n8n/COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE"
        "/aibuildkit/n8n/CORS_ALLOWED_ORIGINS"
        "/aibuildkit/n8n/CORS_ENABLE"
        "/aibuildkit/n8n/ENCRYPTION_KEY"
        "/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET"
        "/aibuildkit/OPENAI_API_KEY"
        "/aibuildkit/POSTGRES_DB"
        "/aibuildkit/POSTGRES_PASSWORD"
        "/aibuildkit/POSTGRES_USER"
        "/aibuildkit/WEBHOOK_URL"
        "/aibuildkit/n8n_id"
    )
    
    # Fetch parameters in batch
    SSM_PARAMS=$(aws ssm get-parameters --names "${params[@]}" --with-decryption --region "$AWS_REGION" --query "Parameters" --output json)
    
    # Export as environment variables
    export N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE") | .Value')
    export N8N_CORS_ALLOWED_ORIGINS=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/CORS_ALLOWED_ORIGINS") | .Value')
    export N8N_CORS_ENABLE=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/CORS_ENABLE") | .Value')
    export N8N_ENCRYPTION_KEY=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/ENCRYPTION_KEY") | .Value')
    export N8N_USER_MANAGEMENT_JWT_SECRET=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET") | .Value')
    export OPENAI_API_KEY=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/OPENAI_API_KEY") | .Value')
    export POSTGRES_DB=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/POSTGRES_DB") | .Value')
    export POSTGRES_PASSWORD=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/POSTGRES_PASSWORD") | .Value')
    export POSTGRES_USER=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/POSTGRES_USER") | .Value')
    export WEBHOOK_URL=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/WEBHOOK_URL") | .Value')
    export N8N_ID=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n_id") | .Value')
    
    success "Fetched parameters from SSM"
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
        --description "Security group for AI Starter Kit" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' \
        --output text)
    
    # Add rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # n8n
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 5678 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # Ollama
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 11434 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # Crawl4AI
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 11235 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # Qdrant
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 6333 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # NFS for EFS
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 2049 \
        --source-group "$SG_ID" \
        --region "$AWS_REGION"
    
    success "Created security group: $SG_ID"
    echo "$SG_ID"
}

create_efs() {
    local SG_ID="$1"
    log "Setting up EFS (Elastic File System)..."
    
    # Check if EFS already exists by searching through all file systems
    EFS_LIST=$(aws efs describe-file-systems \
        --region "$AWS_REGION" \
        --query 'FileSystems[].FileSystemId' \
        --output text 2>/dev/null || echo "")
    
    # Check each EFS to see if it has our tag
    for EFS_ID in $EFS_LIST; do
        if [[ -n "$EFS_ID" && "$EFS_ID" != "None" ]]; then
            EFS_TAGS=$(aws efs list-tags-for-resource \
                --resource-id "$EFS_ID" \
                --region "$AWS_REGION" \
                --query "Tags[?Key=='Name'].Value" \
                --output text 2>/dev/null || echo "")
            
            if [[ "$EFS_TAGS" == "${STACK_NAME}-efs" ]]; then
                warning "EFS already exists: $EFS_ID"
                # Get EFS DNS name
                EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
                export EFS_ID
                echo "$EFS_DNS"
                return 0
            fi
        fi
    done
    
    # Create EFS
    EFS_ID=$(aws efs create-file-system \
        --creation-token "${STACK_NAME}-efs-$(date +%s)" \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --encrypted \
        --region "$AWS_REGION" \
        --query 'FileSystemId' \
        --output text)
    
    # Tag EFS
    aws efs create-tags \
        --file-system-id "$EFS_ID" \
        --tags Key=Name,Value="${STACK_NAME}-efs" Key=Project,Value="$PROJECT_NAME" \
        --region "$AWS_REGION"
    
    # Wait for EFS to be available
    log "Waiting for EFS to become available..."
    while true; do
        EFS_STATE=$(aws efs describe-file-systems \
            --file-system-id "$EFS_ID" \
            --region "$AWS_REGION" \
            --query 'FileSystems[0].LifeCycleState' \
            --output text 2>/dev/null || echo "")
        
        if [[ "$EFS_STATE" == "available" ]]; then
            log "EFS is now available"
            break
        elif [[ "$EFS_STATE" == "creating" ]]; then
            log "EFS is still creating... waiting 10 seconds"
            sleep 10
        else
            warning "EFS state: $EFS_STATE"
            sleep 10
        fi
    done
    
    # Note: Mount target creation is now handled after instance launch
    # when we know which AZ the instance is in
    
    # Get EFS DNS name
    EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
    # Export EFS_ID for cleanup function
    export EFS_ID
    success "Created EFS: $EFS_ID (DNS: $EFS_DNS)"
    echo "$EFS_DNS"
}

create_efs_mount_target() {
    local SG_ID="$1"
    local INSTANCE_AZ="$2"
    
    if [[ -z "$EFS_ID" ]]; then
        error "EFS_ID not set. Cannot create mount target."
        return 1
    fi
    
    log "Creating EFS mount target in $INSTANCE_AZ (where instance is running)..."
    
    # Check if mount target already exists in this AZ
    EXISTING_MT=$(aws efs describe-mount-targets \
        --file-system-id "$EFS_ID" \
        --region "$AWS_REGION" \
        --query "MountTargets[?AvailabilityZoneName=='$INSTANCE_AZ'].MountTargetId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING_MT" && "$EXISTING_MT" != "None" ]]; then
        warning "EFS mount target already exists in $INSTANCE_AZ: $EXISTING_MT"
        return 0
    fi
    
    # Get subnet ID for the instance AZ
    SUBNET_ID=$(get_subnet_for_az "$INSTANCE_AZ")
    
    if [[ "$SUBNET_ID" != "None" && -n "$SUBNET_ID" ]]; then
        aws efs create-mount-target \
            --file-system-id "$EFS_ID" \
            --subnet-id "$SUBNET_ID" \
            --security-groups "$SG_ID" \
            --region "$AWS_REGION" || {
            warning "Mount target creation failed in $INSTANCE_AZ, but continuing..."
            return 0
        }
        success "Created EFS mount target in $INSTANCE_AZ"
    else
        error "No suitable subnet found in $INSTANCE_AZ"
        return 1
    fi
}

# Create main target group for n8n
create_target_group() {
    local SG_ID="$1"
    local INSTANCE_ID="$2"
    
    log "Creating target group for n8n..."
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
    
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "${STACK_NAME}-n8n-tg" \
        --protocol HTTP \
        --port 5678 \
        --vpc-id "$VPC_ID" \
        --health-check-protocol HTTP \
        --health-check-port 5678 \
        --health-check-path /healthz \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 10 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --target-type instance \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Register instance to target group
    aws elbv2 register-targets \
        --target-group-arn "$TARGET_GROUP_ARN" \
        --targets Id="$INSTANCE_ID" Port=5678 \
        --region "$AWS_REGION"
    
    success "Created n8n target group: $TARGET_GROUP_ARN"
    echo "$TARGET_GROUP_ARN"
}

# Add qdrant target group creation after n8n target group
create_qdrant_target_group() {
    local SG_ID="$1"
    local INSTANCE_ID="$2"
    
    log "Creating target group for qdrant..."
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
    
    QDRANT_TG_ARN=$(aws elbv2 create-target-group \
        --name "${STACK_NAME}-qdrant-tg" \
        --protocol HTTP \
        --port 6333 \
        --vpc-id "$VPC_ID" \
        --health-check-protocol HTTP \
        --health-check-port 6333 \
        --health-check-path /healthz \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 10 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --target-type instance \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Register instance to qdrant target group
    aws elbv2 register-targets \
        --target-group-arn "$QDRANT_TG_ARN" \
        --targets Id="$INSTANCE_ID" Port=6333 \
        --region "$AWS_REGION"
    
    success "Created qdrant target group: $QDRANT_TG_ARN"
    echo "$QDRANT_TG_ARN"
}

# =============================================================================
# SPOT INSTANCE MANAGEMENT
# =============================================================================

create_launch_template() {
    local SG_ID="$1"
    
    log "Creating launch template for spot instances..."
    
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
    cat > user-data.sh << 'EOF'
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
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
apt-get update && apt-get install -y nvidia-docker2

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
apt-get install -y jq curl wget git htop nvtop awscli nfs-common

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Restart services
systemctl restart docker
systemctl enable docker

# Create mount point for EFS
mkdir -p /mnt/efs

# Signal that setup is complete
touch /tmp/user-data-complete

EOF

    # Encode user data
    # Use platform-specific base64 command
    if [[ "$OSTYPE" == "darwin"* ]]; then
        USER_DATA=$(base64 -i user-data.sh | tr -d '\n')
    else
        USER_DATA=$(base64 -w 0 user-data.sh)
    fi
    
    # Create launch template
    aws ec2 create-launch-template \
        --launch-template-name "${STACK_NAME}-launch-template" \
        --launch-template-data "{
            \"ImageId\": \"$AMI_ID\",
            \"InstanceType\": \"$INSTANCE_TYPE\",
            \"KeyName\": \"$KEY_NAME\",
            \"SecurityGroupIds\": [\"$SG_ID\"],
            \"UserData\": \"$USER_DATA\",
            \"IamInstanceProfile\": {
                \"Name\": \"${STACK_NAME}-instance-profile\"
            },
            \"InstanceMarketOptions\": {
                \"MarketType\": \"spot\",
                \"SpotOptions\": {
                    \"MaxPrice\": \"$MAX_SPOT_PRICE\",
                    \"SpotInstanceType\": \"one-time\",
                    \"InstanceInterruptionBehavior\": \"terminate\"
                }
            },
            \"TagSpecifications\": [
                {
                    \"ResourceType\": \"instance\",
                    \"Tags\": [
                        {\"Key\": \"Name\", \"Value\": \"${STACK_NAME}-gpu-instance\"},
                        {\"Key\": \"Project\", \"Value\": \"$PROJECT_NAME\"},
                        {\"Key\": \"SpotInstance\", \"Value\": \"true\"},
                        {\"Key\": \"CostOptimized\", \"Value\": \"true\"}
                    ]
                }
            ]
        }" \
        --region "$AWS_REGION" > /dev/null
    
    success "Created launch template: ${STACK_NAME}-launch-template"
}

create_iam_role() {
    log "Creating IAM role for EC2 instances..."
    
    # Check if role exists
    if aws iam get-role --role-name "${STACK_NAME}-role" &> /dev/null; then
        warning "IAM role already exists"
        return 0
    fi
    
    # Create trust policy
    cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create role
    aws iam create-role \
        --role-name "${STACK_NAME}-role" \
        --assume-role-policy-document file://trust-policy.json || {
        warning "Role ${STACK_NAME}-role may already exist, continuing..."
    }
    
    # Attach essential policies
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy || {
        warning "CloudWatchAgentServerPolicy may already be attached, continuing..."
    }
    
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore || {
        warning "AmazonSSMManagedInstanceCore may already be attached, continuing..."
    }
    
    # Create custom policy for EFS and AWS service access
    cat > custom-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeMountTargets", 
                "ec2:Describe*",
                "cloudwatch:PutMetricData",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    aws iam create-policy \
        --policy-name "${STACK_NAME}-custom-policy" \
        --policy-document file://custom-policy.json || true
    
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/${STACK_NAME}-custom-policy" || {
        warning "Custom policy may already be attached, continuing..."
    }
    
    # Create instance profile
    aws iam create-instance-profile --instance-profile-name "${STACK_NAME}-instance-profile" || true
    aws iam add-role-to-instance-profile \
        --instance-profile-name "${STACK_NAME}-instance-profile" \
        --role-name "${STACK_NAME}-role" || true
    
    # Wait for IAM propagation
    log "Waiting for IAM role propagation..."
    sleep 30
    
    success "Created IAM role and instance profile"
}

launch_spot_instance() {
    local SG_ID="$1"
    local EFS_DNS="$2"
    
    log "Launching spot instance with multi-AZ fallback..."
    
    # Create user data script
    cat > user-data.sh << 'EOF'
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
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
apt-get update && apt-get install -y nvidia-docker2

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
apt-get install -y jq curl wget git htop nvtop awscli nfs-common

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Restart services
systemctl restart docker
systemctl enable docker

# Create mount point for EFS
mkdir -p /mnt/efs

# Signal that setup is complete
touch /tmp/user-data-complete

EOF

    # Get AMI ID once for all attempts
    AMI_ID=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters \
            "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*" \
            "Name=state,Values=available" \
        --region "$AWS_REGION" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    info "Using AMI: $AMI_ID"
    
    # Get all available zones
    AVAILABLE_ZONES=($(get_all_availability_zones))
    info "Available AZs: ${AVAILABLE_ZONES[*]}"
    
    # Try each availability zone until one succeeds
    for AZ in "${AVAILABLE_ZONES[@]}"; do
        log "Attempting spot instance launch in AZ: $AZ"
        
        # Get subnet for this AZ
        SUBNET_ID=$(get_subnet_for_az "$AZ")
        if [[ "$SUBNET_ID" == "None" || -z "$SUBNET_ID" ]]; then
            warning "No suitable subnet found in $AZ, skipping..."
            continue
        fi
        
        info "Using subnet $SUBNET_ID in $AZ"
        
        # Create spot instance request with specific subnet (which determines AZ)
        REQUEST_ID=$(aws ec2 request-spot-instances \
            --spot-price "$MAX_SPOT_PRICE" \
            --instance-count 1 \
            --type "one-time" \
            --launch-specification "{
                \"ImageId\": \"$AMI_ID\",
                \"InstanceType\": \"$INSTANCE_TYPE\",
                \"KeyName\": \"$KEY_NAME\",
                \"SecurityGroupIds\": [\"$SG_ID\"],
                \"SubnetId\": \"$SUBNET_ID\",
                \"IamInstanceProfile\": {
                    \"Name\": \"${STACK_NAME}-instance-profile\"
                },
                \"UserData\": \"$(if [[ "$OSTYPE" == "darwin"* ]]; then base64 -i user-data.sh | tr -d '\n'; else base64 -w 0 user-data.sh; fi)\"
            }" \
            --region "$AWS_REGION" \
            --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
            --output text 2>/dev/null) || {
            warning "Failed to create spot instance request in $AZ, trying next AZ..."
            continue
        }
        
        # Check if REQUEST_ID is valid
        if [[ -z "$REQUEST_ID" || "$REQUEST_ID" == "None" || "$REQUEST_ID" == "null" ]]; then
            warning "Invalid spot instance request ID in $AZ: $REQUEST_ID, trying next AZ..."
            continue
        fi
        
        info "Spot instance request ID: $REQUEST_ID in $AZ"
        
        # Wait for spot request to be fulfilled with timeout
        log "Waiting for spot instance to be launched in $AZ..."
        if aws ec2 wait spot-instance-request-fulfilled \
            --spot-instance-request-ids "$REQUEST_ID" \
            --region "$AWS_REGION" \
            --waiter-config maxAttempts=10,delay=30; then
            
            # Get instance ID with error checking
            INSTANCE_ID=$(aws ec2 describe-spot-instance-requests \
                --spot-instance-request-ids "$REQUEST_ID" \
                --region "$AWS_REGION" \
                --query 'SpotInstanceRequests[0].InstanceId' \
                --output text)
            
            if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" && "$INSTANCE_ID" != "null" ]]; then
                # Wait for instance to be running
                log "Waiting for instance to be running..."
                aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
                
                # Get public IP and actual AZ
                INSTANCE_INFO=$(aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --region "$AWS_REGION" \
                    --query 'Reservations[0].Instances[0].{PublicIp:PublicIpAddress,AZ:Placement.AvailabilityZone}' \
                    --output json)
                
                PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIp')
                ACTUAL_AZ=$(echo "$INSTANCE_INFO" | jq -r '.AZ')
                
                # Tag instance
                aws ec2 create-tags \
                    --resources "$INSTANCE_ID" \
                    --tags Key=Name,Value="${STACK_NAME}-gpu-instance" Key=Project,Value="$PROJECT_NAME" Key=AvailabilityZone,Value="$ACTUAL_AZ" \
                    --region "$AWS_REGION"
                
                success "Spot instance launched: $INSTANCE_ID (IP: $PUBLIC_IP) in AZ: $ACTUAL_AZ"
                
                # Clean up temporary user data file
                rm -f user-data.sh
                
                echo "$INSTANCE_ID:$PUBLIC_IP:$ACTUAL_AZ"
                return 0
            else
                warning "Failed to get instance ID from spot request in $AZ, trying next AZ..."
                continue
            fi
        else
            warning "Spot instance request timed out in $AZ, trying next AZ..."
            # Cancel the failed request
            aws ec2 cancel-spot-instance-requests --spot-instance-request-ids "$REQUEST_ID" --region "$AWS_REGION" 2>/dev/null || true
            continue
        fi
    done
    
    # If we get here, all AZs failed
    error "Failed to launch spot instance in any availability zone. This may be due to:"
    error "  1. Spot instance capacity constraints across all AZs"
    error "  2. Service limits on spot instances"
    error "  3. Instance type not available in this region"
    error "  4. Spot price too low (current max: $MAX_SPOT_PRICE)"
    
    # Clean up temporary file
    rm -f user-data.sh
    
    return 1
}

# Add CloudFront setup after instance launch
setup_cloudfront() {
    local PUBLIC_IP="$1"
    log "Setting up CloudFront distribution for geuse.io..."
    
    # Create origin access identity
    OAI_ID=$(aws cloudfront create-cloud-front-origin-access-identity --cloud-front-origin-access-identity-config CallerReference="$(date +%s)" Comment="AI Starter Kit OAI" --query 'CloudFrontOriginAccessIdentity.Id' --output text)
    
    # Create distribution
    DISTRIBUTION_ID=$(aws cloudfront create-distribution --distribution-config '{
        "CallerReference": "'"$(date +%s)"'",
        "Comment": "AI Starter Kit Distribution",
        "Enabled": true,
        "Origins": {
            "Quantity": 1,
            "Items": [{
                "Id": "EC2Origin",
                "DomainName": "'"$PUBLIC_IP"'",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]},
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                }
            }]
        },
        "DefaultCacheBehavior": {
            "TargetOriginId": "EC2Origin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {"Quantity": 7, "Items": ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"], "CachedMethods": {"Quantity": 3, "Items": ["HEAD", "GET", "OPTIONS"]}},
            "Compress": true,
            "ForwardedValues": {
                "QueryString": true,
                "Cookies": {"Forward": "all"},
                "Headers": {"Quantity": 1, "Items": ["*"]}
            },
            "MinTTL": 0,
            "DefaultTTL": 3600,
            "MaxTTL": 86400
        },
        "ViewerCertificate": {
            "CloudFrontDefaultCertificate": true
        },
        "Aliases": {
            "Quantity": 1,
            "Items": ["geuse.io"]
        }
    }' --query 'Distribution.Id' --output text)
    
    # Wait for distribution to deploy
    aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
    
    DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query 'Distribution.DomainName' --output text)
    
    success "CloudFront distribution created: $DISTRIBUTION_DOMAIN"
    echo "Point your CNAME record for geuse.io to $DISTRIBUTION_DOMAIN"
    
    export DISTRIBUTION_DOMAIN
}

# Update create_alb function to add qdrant listener rule
create_alb() {
    local SG_ID="$1"
    local TARGET_GROUP_ARN="$2"
    local QDRANT_TG_ARN="$3"
    
    log "Creating Application Load Balancer..."
    
    # Check if ALB exists
    ALB_ARN=$(aws elbv2 describe-load-balancers \
        --names "${STACK_NAME}-alb" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$ALB_ARN" != "None" ]]; then
        warning "ALB already exists: $ALB_ARN"
        ALB_DNS=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$ALB_ARN" \
            --region "$AWS_REGION" \
            --query 'LoadBalancers[0].DNSName' \
            --output text)
        echo "$ALB_DNS"
        return 0
    fi
    
    # Get subnets
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[].SubnetId' \
        --output text)
    
    # Create ALB
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${STACK_NAME}-alb" \
        --type application \
        --scheme internet-facing \
        --subnets $SUBNET_IDS \
        --security-groups "$SG_ID" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    # Create listener
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    
    # Add host-header rule for qdrant
    aws elbv2 create-rule \
        --listener-arn "$LISTENER_ARN" \
        --priority 10 \
        --conditions Field=host-header,Values=qdrant.geuse.io \
        --actions Type=forward,TargetGroupArn="$QDRANT_TG_ARN" \
        --region "$AWS_REGION"
    
    # Get ALB DNS
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    success "Created ALB: $ALB_DNS"
    echo "$ALB_DNS"
}

# Update setup_cloudfront to include qdrant subdomain and cache behavior
setup_cloudfront() {
    local ALB_DNS="$1"
    log "Setting up CloudFront distribution with subdomains..."
    
    # Create origin access identity
    OAI_ID=$(aws cloudfront create-cloud-front-origin-access-identity --cloud-front-origin-access-identity-config CallerReference="$(date +%s)" Comment="AI Starter Kit OAI" --query 'CloudFrontOriginAccessIdentity.Id' --output text)
    
    # Create distribution with multiple aliases and behaviors
    DISTRIBUTION_ID=$(aws cloudfront create-distribution --distribution-config '{
        "CallerReference": "'"$(date +%s)"'",
        "Comment": "AI Starter Kit Distribution with subdomains",
        "Enabled": true,
        "Origins": {
            "Quantity": 1,
            "Items": [{
                "Id": "ALBOrigin",
                "DomainName": "'"$ALB_DNS"'",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]},
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                }
            }]
        },
        "DefaultCacheBehavior": {
            "TargetOriginId": "ALBOrigin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {"Quantity": 7, "Items": ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"], "CachedMethods": {"Quantity": 3, "Items": ["HEAD", "GET", "OPTIONS"]}},
            "Compress": true,
            "ForwardedValues": {
                "QueryString": true,
                "Cookies": {"Forward": "all"},
                "Headers": {"Quantity": 1, "Items": ["*"]},
                "QueryStringCacheKeys": {"Quantity": 0}
            },
            "MinTTL": 0,
            "DefaultTTL": 0,
            "MaxTTL": 0
        },
        "CacheBehaviors": {
            "Quantity": 1,
            "Items": [{
                "PathPattern": "*",
                "TargetOriginId": "ALBOrigin",
                "ViewerProtocolPolicy": "redirect-to-https",
                "AllowedMethods": {"Quantity": 7, "Items": ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"], "CachedMethods": {"Quantity": 3, "Items": ["HEAD", "GET", "OPTIONS"]}},
                "Compress": true,
                "ForwardedValues": {
                    "QueryString": true,
                    "Cookies": {"Forward": "all"},
                    "Headers": {"Quantity": 2, "Items": ["Host", "*"]}
                },
                "MinTTL": 0,
                "DefaultTTL": 0,
                "MaxTTL": 0
            }]
        },
        "ViewerCertificate": {
            "CloudFrontDefaultCertificate": true
        },
        "Aliases": {
            "Quantity": 2,
            "Items": ["n8n.geuse.io", "qdrant.geuse.io"]
        }
    }' --query 'Distribution.Id' --output text)
    
    # Wait for distribution to deploy
    aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
    
    DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query 'Distribution.DomainName' --output text)
    
    success "CloudFront distribution created: $DISTRIBUTION_DOMAIN"
    echo "Update DNS: Point n8n.geuse.io and qdrant.geuse.io CNAMEs to $DISTRIBUTION_DOMAIN"
    
    export DISTRIBUTION_DOMAIN
}

create_auto_scaling_group() {
    local SG_ID="$1"
    local EFS_DNS="$2"
    
    log "Creating Auto Scaling Group for cost optimization..."
    
    # Check if ASG already exists
    if aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "${STACK_NAME}-asg" \
        --region "$AWS_REGION" &> /dev/null; then
        warning "Auto Scaling Group already exists"
        echo "${STACK_NAME}-asg"
        return 0
    fi
    
    # Get subnets for ASG
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[0:2].SubnetId' \
        --output text | tr '\t' ',')
    
    # Create Auto Scaling Group
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name "${STACK_NAME}-asg" \
        --launch-template "LaunchTemplateName=${STACK_NAME}-launch-template,Version=\$Latest" \
        --min-size 1 \
        --max-size 3 \
        --desired-capacity 1 \
        --vpc-zone-identifier "$SUBNET_IDS" \
        --health-check-type EC2 \
        --health-check-grace-period 300 \
        --default-cooldown 300 \
        --tags \
            "Key=Name,Value=${STACK_NAME}-asg-instance,PropagateAtLaunch=true,ResourceId=${STACK_NAME}-asg,ResourceType=auto-scaling-group" \
            "Key=Project,Value=$PROJECT_NAME,PropagateAtLaunch=true,ResourceId=${STACK_NAME}-asg,ResourceType=auto-scaling-group" \
            "Key=CostOptimized,Value=true,PropagateAtLaunch=true,ResourceId=${STACK_NAME}-asg,ResourceType=auto-scaling-group" \
        --region "$AWS_REGION"
    
    # Create scaling policies for cost optimization
    
    # Scale up policy (when GPU utilization > 80%)
    SCALE_UP_POLICY_ARN=$(aws autoscaling put-scaling-policy \
        --auto-scaling-group-name "${STACK_NAME}-asg" \
        --policy-name "${STACK_NAME}-scale-up" \
        --policy-type TargetTrackingScaling \
        --target-tracking-configuration '{
            "TargetValue": 75.0,
            "CustomizedMetricSpecification": {
                "MetricName": "GPUUtilization",
                "Namespace": "GPU/Monitoring",
                "Statistic": "Average"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }' \
        --region "$AWS_REGION" \
        --query 'PolicyARN' \
        --output text)
    
    # Create CloudWatch alarm for high GPU utilization
    aws cloudwatch put-metric-alarm \
        --alarm-name "${STACK_NAME}-high-gpu-utilization" \
        --alarm-description "Scale up when GPU utilization is high" \
        --metric-name GPUUtilization \
        --namespace GPU/Monitoring \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$SCALE_UP_POLICY_ARN" \
        --region "$AWS_REGION"
    
    # Create CloudWatch alarm for low GPU utilization  
    aws cloudwatch put-metric-alarm \
        --alarm-name "${STACK_NAME}-low-gpu-utilization" \
        --alarm-description "Scale down when GPU utilization is low" \
        --metric-name GPUUtilization \
        --namespace GPU/Monitoring \
        --statistic Average \
        --period 900 \
        --threshold 20 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 3 \
        --treat-missing-data notBreaching \
        --region "$AWS_REGION"
    
    # Wait for ASG to stabilize
    log "Waiting for Auto Scaling Group to stabilize..."
    sleep 30
    
    success "Created Auto Scaling Group: ${STACK_NAME}-asg"
    echo "${STACK_NAME}-asg"
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
    local EFS_DNS="$2"
    local INSTANCE_ID="$3"
    
    log "Deploying AI Starter Kit application with SSM parameters..."
    
    # Fetch SSM params with error handling
    fetch_ssm_params || { error "Failed to fetch SSM parameters"; return 1; }
    
    # Create deployment script using SSM vars
    cat > deploy-app.sh << EOF
#!/bin/bash
set -euo pipefail

echo "Starting AI Starter Kit deployment..."

# Mount EFS
sudo mkdir -p /mnt/efs
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc $EFS_DNS:/ /mnt/efs
echo "$EFS_DNS:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,_netdev 0 0" | sudo tee -a /etc/fstab

# Clone repository
git clone https://github.com/michael-pittman/001-starter-kit.git /home/ubuntu/ai-starter-kit || true
cd /home/ubuntu/ai-starter-kit

# Create .env from SSM parameters
cat > .env << 'EOFENV'
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET
N8N_HOST=0.0.0.0
N8N_PORT=5678
WEBHOOK_URL=$WEBHOOK_URL
EFS_DNS=$EFS_DNS
INSTANCE_ID=$INSTANCE_ID
INSTANCE_TYPE=$INSTANCE_TYPE
AWS_DEFAULT_REGION=$AWS_REGION
OPENAI_API_KEY=$OPENAI_API_KEY
N8N_CORS_ENABLE=$N8N_CORS_ENABLE
N8N_CORS_ALLOWED_ORIGINS=$N8N_CORS_ALLOWED_ORIGINS
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=$N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE
N8N_ID=$N8N_ID
EOFENV

# Start GPU-optimized services
export EFS_DNS=$EFS_DNS
sudo -E docker-compose -f docker-compose.gpu-optimized.yml up -d

echo "Deployment completed!"
EOF

    # Copy application files and deploy
    log "Copying application files..."
    
    # Copy the entire repository
    rsync -avz --exclude '.git' --exclude 'node_modules' --exclude '*.log' \
        -e "ssh -o StrictHostKeyChecking=no -i ${KEY_NAME}.pem" \
        ./ "ubuntu@$PUBLIC_IP:/home/ubuntu/ai-starter-kit/"
    
    # Run deployment
    log "Running deployment script..."
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" \
        "chmod +x /home/ubuntu/ai-starter-kit/deploy-app.sh && /home/ubuntu/ai-starter-kit/deploy-app.sh"
    
    success "Application deployment completed!"
}

setup_monitoring() {
    local PUBLIC_IP="$1"
    
    log "Setting up monitoring and cost optimization..."
    
    # Copy monitoring scripts
    scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" \
        "scripts/cost-optimization-automation.py" \
        "ubuntu@$PUBLIC_IP:/home/ubuntu/cost-optimization.py"
    
    # Install monitoring script
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" << 'EOF'
# Install Python dependencies
sudo apt-get install -y python3-pip
pip3 install boto3 schedule requests nvidia-ml-py3 psutil

# Create systemd service for cost optimization
sudo cat > /etc/systemd/system/cost-optimization.service << 'EOFSERVICE'
[Unit]
Description=AI Starter Kit Cost Optimization
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/usr/bin/python3 /home/ubuntu/cost-optimization.py --action schedule
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Start cost optimization service
sudo systemctl daemon-reload
sudo systemctl enable cost-optimization.service
sudo systemctl start cost-optimization.service

echo "Monitoring setup completed!"
EOF

    success "Monitoring and cost optimization setup completed!"
}

# =============================================================================
# VALIDATION AND HEALTH CHECKS
# =============================================================================

validate_deployment() {
    local PUBLIC_IP="$1"
    
    log "Validating deployment..."
    
    # Wait with backoff
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
        local max_retries=10
        local backoff=30
        while [ $retry -lt $max_retries ]; do
            if curl -f -s "$url" > /dev/null 2>&1; then
                success "$service is healthy"
                break
            fi
            retry=$((retry+1))
            info "Attempt $retry/$max_retries: $service not ready, waiting ${backoff}s..."
            sleep $backoff
            backoff=$((backoff * 2))  # Exponential backoff
        done
        if [ $retry -eq $max_retries ]; then
            error "$service failed health check after $max_retries attempts"
        fi
    done
    
    success "Deployment validation completed!"
}

display_results() {
    local PUBLIC_IP="$1"
    local INSTANCE_ID="$2"
    local EFS_DNS="$3"
    local INSTANCE_AZ="$4"
    
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}   AI STARTER KIT DEPLOYED!    ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${BLUE}Instance Information:${NC}"
    echo -e "  Instance ID: ${YELLOW}$INSTANCE_ID${NC}"
    echo -e "  Public IP: ${YELLOW}$PUBLIC_IP${NC}"
    echo -e "  Instance Type: ${YELLOW}$INSTANCE_TYPE${NC}"
    echo -e "  Availability Zone: ${YELLOW}$INSTANCE_AZ${NC}"
    echo -e "  EFS DNS: ${YELLOW}$EFS_DNS${NC}"
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
    echo -e "  4. Configure API keys in .env file for enhanced features"
    echo ""
    echo -e "${YELLOW}Cost Information:${NC}"
    echo -e "  - Single spot instance saves ~70% vs on-demand"
    echo -e "  - No auto-scaling to avoid spot instance limits"
    echo -e "  - Expected cost: ~$6-8/day (single g4dn.xlarge spot)"
    echo ""
    echo -e "${YELLOW}Instance Details:${NC}"
    echo -e "  - Single spot instance deployment with multi-AZ fallback"
    echo -e "  - Deployed in $INSTANCE_AZ (automatically selected)"
    echo -e "  - CloudWatch monitoring enabled"
    echo -e "  - EFS shared storage available"
    echo -e "  - SSM management access"
    echo -e "  - Optimized for spot instance availability across all AZs"
    echo ""
}

# =============================================================================
# CLEANUP FUNCTION
# =============================================================================

cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    
    # Terminate instance first
    if [ ! -z "${INSTANCE_ID:-}" ]; then
        log "Terminating instance $INSTANCE_ID..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
    fi
    
    # Note: No Auto Scaling Group to delete (using single spot instance)
    
    # Delete CloudWatch alarms (if any were created)
    log "Deleting CloudWatch alarms..."
    aws cloudwatch delete-alarms \
        --alarm-names "${STACK_NAME}-high-gpu-utilization" "${STACK_NAME}-low-gpu-utilization" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Delete CloudFront distribution (takes longest, do early)
    if [ ! -z "${DISTRIBUTION_ID:-}" ]; then
        log "Disabling and deleting CloudFront distribution..."
        # Disable first
        ETAG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query ETag --output text 2>/dev/null) || true
        if [ ! -z "$ETAG" ] && [ "$ETAG" != "None" ]; then
            CONFIG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query DistributionConfig --output json 2>/dev/null) || true
            if [ ! -z "$CONFIG" ]; then
                echo "$CONFIG" | jq '.Enabled = false' > disabled-config.json 2>/dev/null || true
                aws cloudfront update-distribution --id "$DISTRIBUTION_ID" --distribution-config file://disabled-config.json --if-match "$ETAG" 2>/dev/null || true
                aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID" 2>/dev/null || true
                NEW_ETAG=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query ETag --output text 2>/dev/null) || true
                aws cloudfront delete-distribution --id "$DISTRIBUTION_ID" --if-match "$NEW_ETAG" 2>/dev/null || true
            fi
        fi
    fi
    
    # Wait for ALB dependencies to clear, then delete ALB
    if [ ! -z "${ALB_ARN:-}" ]; then
        log "Deleting Application Load Balancer..."
        sleep 30  # Wait for connections to clear
        aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" || true
        # Wait for ALB to be deleted before deleting target groups
        sleep 60
    fi
    
    # Delete target groups after ALB is gone
    if [ ! -z "${TARGET_GROUP_ARN:-}" ]; then
        log "Deleting n8n target group..."
        aws elbv2 delete-target-group --target-group-arn "$TARGET_GROUP_ARN" --region "$AWS_REGION" || true
    fi
    if [ ! -z "${QDRANT_TG_ARN:-}" ]; then
        log "Deleting qdrant target group..."
        aws elbv2 delete-target-group --target-group-arn "$QDRANT_TG_ARN" --region "$AWS_REGION" || true
    fi
    
    # Note: No launch template to delete (using direct spot instance)
    
    # Delete EFS mount targets and file system
    if [ ! -z "${EFS_ID:-}" ]; then
        log "Deleting EFS mount targets and file system..."
        MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --query 'MountTargets[].MountTargetId' --output text --region "$AWS_REGION" 2>/dev/null) || true
        for MT in $MOUNT_TARGETS; do
            if [ ! -z "$MT" ] && [ "$MT" != "None" ]; then
                aws efs delete-mount-target --mount-target-id "$MT" --region "$AWS_REGION" || true
            fi
        done
        sleep 30  # Wait for mount targets to be deleted
        aws efs delete-file-system --file-system-id "$EFS_ID" --region "$AWS_REGION" || true
    fi
    
    # Delete security group (wait for all dependencies to clear)
    if [ ! -z "${SG_ID:-}" ]; then
        log "Deleting security group..."
        # Wait longer for EFS mount targets and other dependencies to fully detach
        sleep 60
        # Retry security group deletion with better error handling
        local retry_count=0
        while [ $retry_count -lt 3 ]; do
            if aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" 2>/dev/null; then
                success "Security group deleted"
                break
            else
                retry_count=$((retry_count + 1))
                warning "Security group deletion attempt $retry_count failed, waiting 30s..."
                sleep 30
            fi
        done
        if [ $retry_count -eq 3 ]; then
            warning "Security group $SG_ID could not be deleted due to dependencies. Please delete manually."
        fi
    fi
    
    # Delete IAM resources
    log "Cleaning up IAM resources..."
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || ""
    aws iam remove-role-from-instance-profile --instance-profile-name "${STACK_NAME}-instance-profile" --role-name "${STACK_NAME}-role" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "${STACK_NAME}-instance-profile" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${STACK_NAME}-role" --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${STACK_NAME}-role" --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true
    if [ ! -z "$ACCOUNT_ID" ]; then
        aws iam detach-role-policy --role-name "${STACK_NAME}-role" --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${STACK_NAME}-custom-policy" 2>/dev/null || true
        aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${STACK_NAME}-custom-policy" 2>/dev/null || true
    fi
    aws iam delete-role --role-name "${STACK_NAME}-role" 2>/dev/null || true
    
    # Delete key pair and local files
    log "Deleting key pair and temporary files..."
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$AWS_REGION" || true
    rm -f "${KEY_NAME}.pem" user-data.sh trust-policy.json custom-policy.json deploy-app.sh disabled-config.json
    
    warning "Cleanup completed. Please verify in AWS console that all resources are deleted."
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
    echo -e "${BLUE}AWS Deployment Automation${NC}"
    echo -e "${BLUE}GPU-Optimized | Cost-Efficient | Production-Ready${NC}"
    echo ""
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    
    log "Starting AWS infrastructure deployment..."
    create_key_pair
    create_iam_role
    
    SG_ID=$(create_security_group)
    EFS_DNS=$(create_efs "$SG_ID")
    
    # Launch single spot instance directly (no ASG to avoid multiple instances)
    log "Launching single spot instance with multi-AZ fallback..."
    INSTANCE_INFO=$(launch_spot_instance "$SG_ID" "$EFS_DNS")
    INSTANCE_ID=$(echo "$INSTANCE_INFO" | cut -d: -f1)
    PUBLIC_IP=$(echo "$INSTANCE_INFO" | cut -d: -f2)
    INSTANCE_AZ=$(echo "$INSTANCE_INFO" | cut -d: -f3)

    # Now create EFS mount target in the AZ where instance was actually launched
    create_efs_mount_target "$SG_ID" "$INSTANCE_AZ"

    TARGET_GROUP_ARN=$(create_target_group "$SG_ID" "$INSTANCE_ID")
    QDRANT_TG_ARN=$(create_qdrant_target_group "$SG_ID" "$INSTANCE_ID")
    ALB_DNS=$(create_alb "$SG_ID" "$TARGET_GROUP_ARN" "$QDRANT_TG_ARN")
    
    setup_cloudfront "$ALB_DNS"
    
    wait_for_instance_ready "$PUBLIC_IP"
    deploy_application "$PUBLIC_IP" "$EFS_DNS" "$INSTANCE_ID"
    setup_monitoring "$PUBLIC_IP"
    validate_deployment "$PUBLIC_IP"
    
    display_results "$PUBLIC_IP" "$INSTANCE_ID" "$EFS_DNS" "$INSTANCE_AZ"
    
    # Clean up temporary files
    rm -f user-data.sh trust-policy.json custom-policy.json deploy-app.sh
    
    success "AI Starter Kit deployment completed successfully!"
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
    echo "  --max-spot-price PRICE  Maximum spot price (default: 0.75)"
    echo "  --key-name NAME         SSH key name (default: ai-starter-kit-key)"
    echo "  --stack-name NAME       Stack name (default: ai-starter-kit)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 --region us-west-2                # Deploy in different region"
    echo "  $0 --instance-type g4dn.2xlarge      # Use larger instance"
    echo "  $0 --max-spot-price 1.00             # Higher spot price limit"
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
        --max-spot-price)
            MAX_SPOT_PRICE="$2"
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