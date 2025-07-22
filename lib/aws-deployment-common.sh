#!/bin/bash
# =============================================================================
# AWS Deployment Common Library
# Shared functions for all AWS deployment scripts
# =============================================================================

# =============================================================================
# SHARED LOGGING AND OUTPUT FUNCTIONS
# =============================================================================

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}" >&2; }
warning() { echo -e "${YELLOW}[WARNING] $1${NC}" >&2; }
info() { echo -e "${CYAN}[INFO] $1${NC}" >&2; }

# =============================================================================
# SHARED PREREQUISITE CHECKING
# =============================================================================

check_common_prerequisites() {
    local requirements_met=true

    log "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        info "Install instructions: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        requirements_met=false
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it first."
        info "Install instructions: https://docs.docker.com/get-docker/"
        requirements_met=false
    fi

    # Check/install jq
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Attempting to install..."
        if command -v brew &> /dev/null; then
            brew install jq
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        else
            error "Cannot install jq automatically. Please install it manually."
            requirements_met=false
        fi
    fi

    # Check/install bc
    if ! command -v bc &> /dev/null; then
        warning "bc is not installed. Attempting to install..."
        if command -v brew &> /dev/null; then
            brew install bc
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y bc
        elif command -v yum &> /dev/null; then
            sudo yum install -y bc
        else
            warning "Cannot install bc automatically. Some features may not work."
        fi
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid."
        info "Run 'aws configure' to set up your credentials."
        requirements_met=false
    fi

    if [ "$requirements_met" = false ]; then
        error "Prerequisites check failed. Please resolve the issues above."
        return 1
    fi

    success "All prerequisites check passed."
    return 0
}

# =============================================================================
# SHARED AWS INFRASTRUCTURE FUNCTIONS
# =============================================================================

create_standard_key_pair() {
    local stack_name="$1"
    local key_file="$2"
    
    if [ -z "$stack_name" ] || [ -z "$key_file" ]; then
        error "create_standard_key_pair requires stack_name and key_file parameters"
        return 1
    fi

    log "Creating/checking key pair: ${stack_name}-key"

    # Check if key pair already exists
    if aws ec2 describe-key-pairs --key-names "${stack_name}-key" --region "$AWS_REGION" &> /dev/null; then
        warning "Key pair ${stack_name}-key already exists. Skipping creation."
        
        # Check if local key file exists
        if [ ! -f "$key_file" ]; then
            error "Key pair exists in AWS but local key file $key_file is missing."
            error "Please either delete the AWS key pair or provide the private key file."
            return 1
        fi
    else
        log "Creating new key pair..."
        aws ec2 create-key-pair \
            --key-name "${stack_name}-key" \
            --query 'KeyMaterial' \
            --output text \
            --region "$AWS_REGION" > "$key_file"
        
        chmod 600 "$key_file"
        success "Key pair created: ${stack_name}-key"
    fi

    return 0
}

create_standard_security_group() {
    local stack_name="$1"
    local vpc_id="$2"
    local additional_ports=("${@:3}")
    
    if [ -z "$stack_name" ] || [ -z "$vpc_id" ]; then
        error "create_standard_security_group requires stack_name and vpc_id parameters"
        return 1
    fi

    local sg_name="${stack_name}-sg"
    log "Creating/checking security group: $sg_name"

    # Check if security group exists
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ "$sg_id" = "None" ] || [ -z "$sg_id" ]; then
        log "Creating new security group..."
        sg_id=$(aws ec2 create-security-group \
            --group-name "$sg_name" \
            --description "Security group for $stack_name AI starter kit" \
            --vpc-id "$vpc_id" \
            --query 'GroupId' \
            --output text \
            --region "$AWS_REGION")
        
        # Standard ports for AI starter kit
        local standard_ports=(22 5678 11434 11235 6333)
        
        # Combine standard and additional ports
        local all_ports=("${standard_ports[@]}" "${additional_ports[@]}")
        
        # Add ingress rules
        for port in "${all_ports[@]}"; do
            aws ec2 authorize-security-group-ingress \
                --group-id "$sg_id" \
                --protocol tcp \
                --port "$port" \
                --cidr 0.0.0.0/0 \
                --region "$AWS_REGION" > /dev/null
        done
        
        success "Security group created: $sg_name ($sg_id)"
    else
        warning "Security group $sg_name already exists: $sg_id"
    fi

    echo "$sg_id"
    return 0
}

create_standard_iam_role() {
    local stack_name="$1"
    local additional_policies=("${@:2}")
    
    if [ -z "$stack_name" ]; then
        error "create_standard_iam_role requires stack_name parameter"
        return 1
    fi

    local role_name="${stack_name}-role"
    local profile_name="${stack_name}-instance-profile"
    
    log "Creating/checking IAM role: $role_name"

    # Check if role exists
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        warning "IAM role $role_name already exists."
    else
        # Create trust policy
        local trust_policy='{
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
        }'

        # Create role
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "$trust_policy" \
            --region "$AWS_REGION" > /dev/null

        # Standard policies for AI starter kit
        local standard_policies=(
            "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
            "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
            "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        )
        
        # Attach standard policies
        for policy in "${standard_policies[@]}"; do
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy" \
                --region "$AWS_REGION"
        done
        
        # Attach additional policies
        for policy in "${additional_policies[@]+"${additional_policies[@]}"}"; do
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy" \
                --region "$AWS_REGION"
        done

        success "IAM role created: $role_name"
    fi

    # Create instance profile
    if aws iam get-instance-profile --instance-profile-name "$profile_name" &> /dev/null; then
        warning "Instance profile $profile_name already exists."
    else
        aws iam create-instance-profile \
            --instance-profile-name "$profile_name" \
            --region "$AWS_REGION" > /dev/null
        
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$profile_name" \
            --role-name "$role_name" \
            --region "$AWS_REGION"
        
        success "Instance profile created: $profile_name"
    fi

    echo "$profile_name"
    return 0
}

# =============================================================================
# INSTANCE UTILITIES
# =============================================================================

get_instance_public_ip() {
    local instance_id="$1"
    
    if [ -z "$instance_id" ]; then
        error "get_instance_public_ip requires instance_id parameter"
        return 1
    fi
    
    local public_ip
    public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    if [ "$public_ip" = "None" ] || [ -z "$public_ip" ]; then
        error "No public IP found for instance: $instance_id"
        return 1
    fi
    
    echo "$public_ip"
    return 0
}

# =============================================================================
# SHARED EFS FUNCTIONS
# =============================================================================

create_shared_efs() {
    local stack_name="$1"
    local performance_mode="${2:-generalPurpose}"
    
    if [ -z "$stack_name" ]; then
        error "create_shared_efs requires stack_name parameter"
        return 1
    fi

    log "Creating/checking EFS: ${stack_name}-efs"

    # Check if EFS exists
    local efs_id
    efs_id=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Name' && Value=='${stack_name}-efs']].FileSystemId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ -z "$efs_id" ] || [ "$efs_id" = "None" ]; then
        log "Creating new EFS..."
        efs_id=$(aws efs create-file-system \
            --performance-mode "$performance_mode" \
            --throughput-mode provisioned \
            --provisioned-throughput-in-mibps 100 \
            --tags Key=Name,Value="${stack_name}-efs" \
            --query 'FileSystemId' \
            --output text \
            --region "$AWS_REGION")
        
        success "EFS created: ${stack_name}-efs ($efs_id)"
    else
        warning "EFS ${stack_name}-efs already exists: $efs_id"
    fi

    echo "$efs_id"
    return 0
}

create_efs_mount_target_for_az() {
    local efs_id="$1"
    local subnet_id="$2"
    local security_group_id="$3"
    
    if [ -z "$efs_id" ] || [ -z "$subnet_id" ] || [ -z "$security_group_id" ]; then
        error "create_efs_mount_target_for_az requires efs_id, subnet_id, and security_group_id parameters"
        return 1
    fi

    log "Creating EFS mount target for subnet: $subnet_id"

    # Check if mount target exists
    local mount_target_id
    mount_target_id=$(aws efs describe-mount-targets \
        --file-system-id "$efs_id" \
        --query "MountTargets[?SubnetId=='$subnet_id'].MountTargetId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ -z "$mount_target_id" ] || [ "$mount_target_id" = "None" ]; then
        aws efs create-mount-target \
            --file-system-id "$efs_id" \
            --subnet-id "$subnet_id" \
            --security-groups "$security_group_id" \
            --region "$AWS_REGION" > /dev/null
        
        success "EFS mount target created for subnet: $subnet_id"
    else
        warning "EFS mount target already exists for subnet: $subnet_id"
    fi

    return 0
}

# =============================================================================
# SHARED INSTANCE MANAGEMENT
# =============================================================================

wait_for_ssh_ready() {
    local instance_ip="$1"
    local key_file="$2"
    local max_attempts="${3:-30}"
    local sleep_interval="${4:-10}"
    
    if [ -z "$instance_ip" ] || [ -z "$key_file" ]; then
        error "wait_for_ssh_ready requires instance_ip and key_file parameters"
        return 1
    fi

    log "Waiting for SSH to be ready on $instance_ip..."
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if ssh -i "$key_file" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$instance_ip" "echo 'SSH is ready'" &> /dev/null; then
            success "SSH is ready on $instance_ip"
            return 0
        fi
        
        info "SSH attempt $attempt/$max_attempts failed. Waiting ${sleep_interval}s..."
        sleep $sleep_interval
        ((attempt++))
    done

    error "SSH failed to become ready after $max_attempts attempts"
    return 1
}

tag_instance_with_metadata() {
    local instance_id="$1"
    local stack_name="$2"
    local deployment_type="$3"
    local additional_tags="$4"
    
    if [ -z "$instance_id" ] || [ -z "$stack_name" ]; then
        error "tag_instance_with_metadata requires instance_id and stack_name parameters"
        return 1
    fi

    log "Tagging instance: $instance_id"

    # Standard tags
    aws ec2 create-tags \
        --resources "$instance_id" \
        --tags \
            Key=Name,Value="$stack_name" \
            Key=Stack,Value="$stack_name" \
            Key=DeploymentType,Value="${deployment_type:-unknown}" \
            Key=Environment,Value="${ENVIRONMENT:-development}" \
            Key=CreatedBy,Value="ai-starter-kit" \
            Key=CreatedAt,Value="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --region "$AWS_REGION"

    # Additional tags if provided
    if [ -n "$additional_tags" ]; then
        aws ec2 create-tags \
            --resources "$instance_id" \
            --tags $additional_tags \
            --region "$AWS_REGION"
    fi

    success "Instance tagged successfully"
    return 0
}

# =============================================================================
# SHARED APPLICATION DEPLOYMENT
# =============================================================================

stream_provisioning_logs() {
    local instance_ip="$1"
    local key_file="$2"
    local log_prefix="${3:-[INSTANCE]}"
    
    if [ -z "$instance_ip" ] || [ -z "$key_file" ]; then
        error "stream_provisioning_logs requires instance_ip and key_file parameters"
        return 1
    fi
    
    info "Starting real-time provisioning logs from $instance_ip..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 REAL-TIME INSTANCE LOGS (press Ctrl+C to stop deployment)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Stream multiple log sources simultaneously  
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" "
        # Function to prefix and stream logs
        stream_log() {
            local logfile=\"\$1\"
            local prefix=\"\$2\"
            if [ -f \"\$logfile\" ]; then
                tail -F \"\$logfile\" 2>/dev/null | while read -r line; do
                    echo \"$log_prefix [\$prefix] \$line\"
                done &
            fi
        }
        
        # Create deployment log if it doesn't exist
        sudo touch /var/log/deployment.log
        sudo chmod 644 /var/log/deployment.log
        
        # Stream various log sources
        stream_log \"/var/log/cloud-init-output.log\" \"INIT\"
        stream_log \"/var/log/deployment.log\" \"DEPLOY\"
        stream_log \"/var/log/docker.log\" \"DOCKER\"
        
        # Stream syslog but filter for relevant messages only
        if [ -f \"/var/log/syslog\" ]; then
            tail -F /var/log/syslog 2>/dev/null | grep -E \"(docker|systemd|cloud-init)\" | while read -r line; do
                echo \"$log_prefix [SYSTEM] \$line\"
            done &
        fi
        
        # Also stream any existing docker-compose logs
        if [ -d \"/home/ubuntu/ai-starter-kit\" ]; then
            cd /home/ubuntu/ai-starter-kit
            if command -v docker-compose >/dev/null 2>&1; then
                docker-compose logs --tail=50 -f 2>/dev/null | while read -r line; do
                    echo \"$log_prefix [COMPOSE] \$line\"
                done &
            fi
        fi
        
        # Keep the connection alive and wait for termination
        wait
    " &
    
    # Store the SSH PID for cleanup
    STREAM_PID=$!
    
    # Give logs a moment to start flowing
    sleep 2
}

stop_provisioning_logs() {
    if [ -n "${STREAM_PID:-}" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        info "📋 Stopping log stream - deployment phase completed"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        kill $STREAM_PID 2>/dev/null || true
        unset STREAM_PID
    fi
}

deploy_application_stack() {
    local instance_ip="$1"
    local key_file="$2"
    local stack_name="$3"
    local compose_file="${4:-docker-compose.gpu-optimized.yml}"
    local environment="${5:-development}"
    local follow_logs="${6:-true}"
    
    if [ -z "$instance_ip" ] || [ -z "$key_file" ] || [ -z "$stack_name" ]; then
        error "deploy_application_stack requires instance_ip, key_file, and stack_name parameters"
        return 1
    fi

    log "Deploying application stack to $instance_ip..."
    
    # Start log streaming if requested
    if [ "$follow_logs" = "true" ]; then
        stream_provisioning_logs "$instance_ip" "$key_file"
        # Register cleanup function
        trap 'stop_provisioning_logs' EXIT INT TERM
    fi

    # Copy project files
    info "Copying project files..."
    rsync -avz -e "ssh -i $key_file -o StrictHostKeyChecking=no" \
        --exclude='.git' \
        --exclude='*.log' \
        --exclude='*.pem' \
        --exclude='*.key' \
        --exclude='.env*' \
        ./ ubuntu@"$instance_ip":/home/ubuntu/ai-starter-kit/

    # Generate environment configuration
    info "Generating environment configuration..."
    if [ "$follow_logs" = "true" ]; then
        info "Watch the [INSTANCE] logs below for detailed progress..."
        sleep 3  # Give user time to see the message
    fi
    
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" << EOF
cd /home/ubuntu/ai-starter-kit
echo "\$(date): Starting environment configuration..." | tee -a /var/log/deployment.log
chmod +x scripts/config-manager.sh
echo "\$(date): Generating $environment configuration..." | tee -a /var/log/deployment.log
./scripts/config-manager.sh generate $environment 2>&1 | tee -a /var/log/deployment.log
echo "\$(date): Setting up environment variables..." | tee -a /var/log/deployment.log
./scripts/config-manager.sh env $environment 2>&1 | tee -a /var/log/deployment.log
echo "\$(date): Environment configuration completed" | tee -a /var/log/deployment.log
EOF

    # Deploy application
    info "Starting application stack..."
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" << EOF
cd /home/ubuntu/ai-starter-kit
echo "\$(date): Starting application deployment..." | tee -a /var/log/deployment.log

# Install missing dependencies first
echo "\$(date): Installing missing dependencies..." | tee -a /var/log/deployment.log
sudo apt-get update -qq
sudo apt-get install -y docker-compose yq jq gettext-base 2>&1 | tee -a /var/log/deployment.log

# Pull latest images
echo "\$(date): Pulling Docker images..." | tee -a /var/log/deployment.log
docker-compose -f $compose_file pull 2>&1 | tee -a /var/log/deployment.log

# Start services
echo "\$(date): Starting Docker services..." | tee -a /var/log/deployment.log
docker-compose -f $compose_file up -d 2>&1 | tee -a /var/log/deployment.log

# Wait for services to stabilize
echo "\$(date): Waiting for services to stabilize..." | tee -a /var/log/deployment.log
sleep 30

# Check service status
echo "\$(date): Checking service status..." | tee -a /var/log/deployment.log
docker-compose -f $compose_file ps 2>&1 | tee -a /var/log/deployment.log

echo "\$(date): Application deployment completed" | tee -a /var/log/deployment.log
EOF

    # Stop log streaming
    if [ "$follow_logs" = "true" ]; then
        sleep 5  # Allow final logs to flow
        stop_provisioning_logs
    fi

    success "Application stack deployed successfully"
    return 0
}

# =============================================================================
# SHARED VALIDATION AND MONITORING
# =============================================================================

validate_service_endpoints() {
    local instance_ip="$1"
    local services=("${@:2}")
    local max_attempts="${MAX_HEALTH_CHECK_ATTEMPTS:-10}"
    local sleep_interval="${HEALTH_CHECK_INTERVAL:-15}"
    
    if [ -z "$instance_ip" ]; then
        error "validate_service_endpoints requires instance_ip parameter"
        return 1
    fi

    # Default services if none provided
    if [ ${#services[@]} -eq 0 ]; then
        services=("n8n:5678" "ollama:11434" "qdrant:6333")
    fi

    log "Validating service endpoints..."
    
    local all_healthy=true
    for service_port in "${services[@]}"; do
        local service_name="${service_port%:*}"
        local port="${service_port#*:}"
        
        info "Checking $service_name on port $port..."
        
        local attempt=1
        local service_healthy=false
        
        while [ $attempt -le $max_attempts ]; do
            if curl -s --connect-timeout 5 "http://$instance_ip:$port" > /dev/null; then
                success "$service_name is healthy"
                service_healthy=true
                break
            fi
            
            warning "$service_name health check attempt $attempt/$max_attempts failed"
            sleep $sleep_interval
            ((attempt++))
        done
        
        if [ "$service_healthy" = false ]; then
            error "$service_name failed health checks"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = true ]; then
        success "All services are healthy"
        return 0
    else
        warning "Some services failed health checks"
        return 1
    fi
}

# =============================================================================
# SHARED CLEANUP FUNCTIONS
# =============================================================================

cleanup_aws_resources() {
    local stack_name="$1"
    local cleanup_order=("${@:2}")
    
    if [ -z "$stack_name" ]; then
        error "cleanup_aws_resources requires stack_name parameter"
        return 1
    fi

    warning "Starting cleanup of AWS resources for stack: $stack_name"

    # Default cleanup order if none provided
    if [ ${#cleanup_order[@]} -eq 0 ]; then
        cleanup_order=("instances" "load-balancers" "target-groups" "security-groups" "efs" "iam" "key-pairs")
    fi

    for resource_type in "${cleanup_order[@]}"; do
        case "$resource_type" in
            "instances")
                cleanup_instances "$stack_name"
                ;;
            "load-balancers")
                cleanup_load_balancers "$stack_name"
                ;;
            "target-groups")
                cleanup_target_groups "$stack_name"
                ;;
            "security-groups")
                cleanup_security_groups "$stack_name"
                ;;
            "efs")
                cleanup_efs "$stack_name"
                ;;
            "iam")
                cleanup_iam_resources "$stack_name"
                ;;
            "key-pairs")
                cleanup_key_pairs "$stack_name"
                ;;
            *)
                warning "Unknown resource type for cleanup: $resource_type"
                ;;
        esac
    done

    success "Cleanup completed for stack: $stack_name"
    return 0
}

cleanup_instances() {
    local stack_name="$1"
    
    log "Cleaning up instances for stack: $stack_name"
    
    local instance_ids
    instance_ids=$(aws ec2 describe-instances \
        --filters "Name=tag:Stack,Values=$stack_name" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ -n "$instance_ids" ] && [ "$instance_ids" != "None" ]; then
        aws ec2 terminate-instances --instance-ids $instance_ids --region "$AWS_REGION" > /dev/null
        success "Terminated instances: $instance_ids"
    else
        info "No instances found for cleanup"
    fi
}

cleanup_security_groups() {
    local stack_name="$1"
    
    log "Cleaning up security groups for stack: $stack_name"
    
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${stack_name}-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
        aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" > /dev/null
        success "Deleted security group: $sg_id"
    else
        info "No security groups found for cleanup"
    fi
}

cleanup_key_pairs() {
    local stack_name="$1"
    
    log "Cleaning up key pairs for stack: $stack_name"
    
    if aws ec2 describe-key-pairs --key-names "${stack_name}-key" --region "$AWS_REGION" &> /dev/null; then
        aws ec2 delete-key-pair --key-name "${stack_name}-key" --region "$AWS_REGION"
        success "Deleted key pair: ${stack_name}-key"
        
        # Remove local key file
        local key_file="${stack_name}-key.pem"
        if [ -f "$key_file" ]; then
            rm -f "$key_file"
            info "Removed local key file: $key_file"
        fi
    else
        info "No key pairs found for cleanup"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

generate_user_data_script() {
    local stack_name="$1"
    local additional_commands="$2"
    
    cat << EOF
#!/bin/bash
# AI Starter Kit Instance Setup
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install NVIDIA Container Toolkit (for GPU instances)
if lspci | grep -i nvidia; then
    distribution=\$(. /etc/os-release;echo \$ID\$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/\$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
    apt-get update
    apt-get install -y nvidia-container-toolkit
    systemctl restart docker
fi

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Create application directory
mkdir -p /home/ubuntu/ai-starter-kit
chown ubuntu:ubuntu /home/ubuntu/ai-starter-kit

# Additional commands
$additional_commands

# Signal completion
touch /tmp/user-data-complete
EOF
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

validate_deployment_configuration() {
    local stack_name="$1"
    local deployment_type="$2"
    
    # Source security validation
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/../scripts/security-validation.sh" ]; then
        source "$script_dir/../scripts/security-validation.sh"
    else
        warning "Security validation script not found. Some validations will be skipped."
        return 0
    fi

    log "Validating deployment configuration..."

    # Validate stack name
    if ! validate_stack_name "$stack_name"; then
        error "Invalid stack name: $stack_name"
        return 1
    fi

    # Validate AWS region
    if ! validate_aws_region "$AWS_REGION"; then
        error "Invalid AWS region: $AWS_REGION"
        return 1
    fi

    # Validate deployment type
    local valid_types=("spot" "ondemand" "simple")
    if [[ ! " ${valid_types[*]} " =~ " ${deployment_type} " ]]; then
        error "Invalid deployment type: $deployment_type. Must be one of: ${valid_types[*]}"
        return 1
    fi

    success "Deployment configuration validation passed"
    return 0
}