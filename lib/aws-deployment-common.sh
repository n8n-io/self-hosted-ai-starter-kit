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

# Enhanced logging functions for human-readable output
log() { echo -e "${BLUE}🕐 [$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2; }
error() { echo -e "${RED}❌ [ERROR] $1${NC}" >&2; }
success() { echo -e "${GREEN}✅ [SUCCESS] $1${NC}" >&2; }
warning() { echo -e "${YELLOW}⚠️  [WARNING] $1${NC}" >&2; }
info() { echo -e "${CYAN}ℹ️  [INFO] $1${NC}" >&2; }

# Deployment progress functions for better user experience
step() { echo -e "${MAGENTA}🔸 [STEP] $1${NC}" >&2; }
progress() { echo -e "${BLUE}⏳ [PROGRESS] $1${NC}" >&2; }

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
            --description "Security group for $stack_name GeuseMaker" \
            --vpc-id "$vpc_id" \
            --query 'GroupId' \
            --output text \
            --region "$AWS_REGION")
        
        # Standard ports for GeuseMaker
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
    # Ensure profile name starts with letter for AWS IAM compliance
    local profile_name
    if [[ "${stack_name}" =~ ^[0-9] ]]; then
        # Use simple prefix for numeric stacks to avoid AWS restrictions
        local clean_name=$(echo "${stack_name}" | sed 's/[^a-zA-Z0-9]//g')
        profile_name="app-${clean_name}-profile"
    else
        profile_name="${stack_name}-instance-profile"
    fi
    
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

        # Standard policies for GeuseMaker
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
        
        # Check if role is associated with the instance profile
        local associated_roles
        associated_roles=$(aws iam get-instance-profile \
            --instance-profile-name "$profile_name" \
            --query 'InstanceProfile.Roles[].RoleName' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ ! "$associated_roles" =~ "$role_name" ]]; then
            log "Associating role $role_name with instance profile $profile_name"
            aws iam add-role-to-instance-profile \
                --instance-profile-name "$profile_name" \
                --role-name "$role_name" \
                --region "$AWS_REGION"
            success "Role associated with existing instance profile"
        else
            success "Role already associated with instance profile"
        fi
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
    
    # Wait a moment for IAM propagation
    sleep 2

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

refresh_instance_public_ip() {
    local instance_id="$1"
    
    if [ -z "$instance_id" ]; then
        error "refresh_instance_public_ip requires instance_id parameter"
        return 1
    fi
    
    local public_ip
    public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ "$public_ip" = "None" ] || [ -z "$public_ip" ] || [ "$public_ip" = "null" ]; then
        return 1
    fi
    
    echo "$public_ip"
    return 0
}

wait_for_ssh_ready() {
    local instance_ip="$1"
    local key_file="$2"
    local max_attempts="${3:-60}"  # Default for non-GPU instances
    local sleep_interval="${4:-30}"  # 30 seconds for better reliability
    local instance_type="${5:-}"  # Instance type for GPU detection
    local instance_id="${6:-}"  # Instance ID for IP refresh
    
    if [ -z "$instance_ip" ] || [ -z "$key_file" ]; then
        error "wait_for_ssh_ready requires instance_ip and key_file parameters"
        return 1
    fi

    # Detect GPU instances and extend timeout
    local is_gpu_instance=false
    if [[ "$instance_type" =~ ^(g[0-9]|p[0-9]|inf[0-9]) ]]; then
        is_gpu_instance=true
        # GPU instances need more time for driver installation and user data
        if [ "$max_attempts" -eq 60 ]; then  # Only override if using default
            max_attempts=90  # 45 minutes (90 * 30s)
        fi
        log "GPU instance detected ($instance_type) - extending SSH timeout to $((max_attempts * sleep_interval / 60)) minutes"
        warning "GPU instances take 20-30+ minutes to boot due to NVIDIA driver installation and comprehensive setup"
        info "You can monitor progress in the AWS EC2 Console under 'Instance Settings > Get System Log'"
    fi

    # Ensure we have the latest public IP before starting
    local current_ip="$instance_ip"
    if [ -n "$instance_id" ]; then
        local refreshed_ip
        refreshed_ip=$(refresh_instance_public_ip "$instance_id")
        if [ $? -eq 0 ] && [ "$refreshed_ip" != "$current_ip" ]; then
            warning "Public IP changed from $current_ip to $refreshed_ip - using latest IP"
            current_ip="$refreshed_ip"
        fi
    fi
    
    log "Waiting for SSH to be ready on $current_ip..."
    info "Using public IP: $current_ip (retrieved from AWS API)"
    log "Maximum wait time: $((max_attempts * sleep_interval / 60)) minutes ($max_attempts attempts, ${sleep_interval}s intervals)"
    
    local attempt=1
    local progress_interval=10  # Show progress every 10 attempts (5 minutes)
    local last_troubleshoot_attempt=0
    local last_ip_refresh=0
    
    while [ $attempt -le $max_attempts ]; do
        # Refresh IP every 20 attempts (10 minutes) if instance_id is provided
        if [ -n "$instance_id" ] && [ $((attempt - last_ip_refresh)) -ge 20 ]; then
            local refreshed_ip
            refreshed_ip=$(refresh_instance_public_ip "$instance_id")
            if [ $? -eq 0 ] && [ "$refreshed_ip" != "$current_ip" ]; then
                warning "Public IP changed from $current_ip to $refreshed_ip during SSH wait - switching to new IP"
                current_ip="$refreshed_ip"
            fi
            last_ip_refresh=$attempt
        fi
        
        # First check if SSH port is open
        if nc -z -w5 "$current_ip" 22 2>/dev/null; then
            # Then try SSH connection
            if ssh -i "$key_file" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes ubuntu@"$current_ip" "echo 'SSH is ready'" &> /dev/null; then
                success "SSH is ready on $current_ip (attempt $attempt/$max_attempts)"
                return 0
            fi
        fi
        
        # Show progress every 10 attempts (5 minutes with 30s intervals)
        if [ $((attempt % progress_interval)) -eq 0 ]; then
            local elapsed_minutes=$((attempt * sleep_interval / 60))
            local total_minutes=$((max_attempts * sleep_interval / 60))
            local percent_complete=$((attempt * 100 / max_attempts))
            info "SSH attempt $attempt/$max_attempts failed. Elapsed: ${elapsed_minutes}/${total_minutes} minutes (${percent_complete}% complete)"
            info "Current target IP: $current_ip"
            
            # Show troubleshooting notes after 30 minutes for any instance type
            if [ $elapsed_minutes -ge 30 ] && [ $((attempt - last_troubleshoot_attempt)) -ge 20 ]; then
                last_troubleshoot_attempt=$attempt
                warning "SSH wait has exceeded 30 minutes. Troubleshooting suggestions:"
                warning "1. Check AWS EC2 Console: Instance Settings > Get System Log for boot progress"
                warning "2. Check AWS EC2 Console: Monitoring tab for CPU/Network activity"
                warning "3. Verify current public IP in AWS Console matches: $current_ip"
                if [ "$is_gpu_instance" = true ]; then
                    warning "4. GPU instances: User data installs NVIDIA drivers and Docker GPU support (can take 20-30+ minutes)"
                    warning "5. GPU instances: Check CloudWatch logs in /aws/GeuseMaker/development for detailed progress"
                else
                    warning "4. Check CloudWatch logs for user data script progress"
                fi
                warning "6. Verify Security Group allows SSH (port 22) from your IP"
                warning "7. Instance will continue waiting until ${total_minutes} minute timeout"
            fi
        else
            info "SSH attempt $attempt/$max_attempts failed on $current_ip. Waiting ${sleep_interval}s..."
        fi
        
        sleep $sleep_interval
        ((attempt++))
    done

    error "SSH failed to become ready after $max_attempts attempts ($((max_attempts * sleep_interval / 60)) minutes)"
    error "Final target IP was: $current_ip"
    error "Instance may still be booting or have configuration issues. Check:"
    error "1. AWS EC2 Console > Instance Settings > Get System Log"
    error "2. AWS EC2 Console > Monitoring tab for activity"
    error "3. Verify public IP in AWS Console matches script target: $current_ip"
    if [ "$is_gpu_instance" = true ]; then
        error "4. CloudWatch logs: /aws/GeuseMaker/development"
        error "5. GPU driver installation can take 20-30+ minutes"
    fi
    error "6. Security group SSH access (port 22)"
    warning "Instance is NOT being terminated - you can continue troubleshooting in AWS Console"
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
            Key=CreatedBy,Value="GeuseMaker" \
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
        if [ -d \"/home/ubuntu/GeuseMaker\" ]; then
            cd /home/ubuntu/GeuseMaker
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
    
    # Sanitize inputs to prevent command injection
    stack_name=$(echo "$stack_name" | sed 's/[^a-zA-Z0-9-]//g')
    environment=$(echo "$environment" | sed 's/[^a-zA-Z0-9-]//g')
    compose_file=$(basename "$compose_file" | sed 's/[^a-zA-Z0-9.-]//g')
    
    # Validate sanitized inputs
    if [[ -z "$stack_name" ]] || [[ -z "$environment" ]] || [[ -z "$compose_file" ]]; then
        error "Invalid input after sanitization"
        return 1
    fi
    
    # Validate stack name length
    if [[ ${#stack_name} -gt 32 ]]; then
        error "Stack name too long: '$stack_name'. Maximum 32 characters."
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
        ./ ubuntu@"$instance_ip":/home/ubuntu/GeuseMaker/

    # Run deployment fixes first
    info "Running deployment fixes (disk space, EFS, Parameter Store)..."
    if [ "$follow_logs" = "true" ]; then
        info "Watch the [INSTANCE] logs below for detailed progress..."
        sleep 3  # Give user time to see the message
    fi
    
    # Copy and run the fix script
    scp -i "$key_file" -o StrictHostKeyChecking=no \
        ./scripts/fix-deployment-issues.sh ubuntu@"$instance_ip":/tmp/
    
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" \
        "chmod +x /tmp/fix-deployment-issues.sh && sudo /tmp/fix-deployment-issues.sh '$stack_name' '$AWS_REGION' 2>&1 | tee -a /var/log/deployment.log"

    # Generate environment configuration
    info "Generating environment configuration..."
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" << EOF
cd /home/ubuntu/GeuseMaker
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
cd /home/ubuntu/GeuseMaker

# Ensure deployment log exists and is writable
sudo touch /var/log/deployment.log 2>/dev/null || touch \$HOME/deployment.log
DEPLOY_LOG=\$([ -w /var/log/deployment.log ] && echo "/var/log/deployment.log" || echo "\$HOME/deployment.log")

echo "\$(date): Starting application deployment..." | tee -a "\$DEPLOY_LOG"

# Function to wait for apt locks to be released
wait_for_apt_lock() {
    local max_wait=300
    local wait_time=0
    echo "\$(date): Waiting for apt locks to be released..." | tee -a "\$DEPLOY_LOG"
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
        if [ \$wait_time -ge \$max_wait ]; then
            echo "\$(date): Timeout waiting for apt locks, killing blocking processes..." | tee -a "\$DEPLOY_LOG"
            sudo pkill -9 -f "unattended-upgrade" || true
            sudo pkill -9 -f "apt-get" || true
            sleep 5
            break
        fi
        echo "\$(date): APT is locked, waiting 10 seconds..." | tee -a "\$DEPLOY_LOG"
        sleep 10
        wait_time=\$((wait_time + 10))
    done
    echo "\$(date): APT locks released" | tee -a "\$DEPLOY_LOG"
}

# Wait for any ongoing apt operations to complete
wait_for_apt_lock

# Install missing dependencies first
echo "\$(date): Installing missing dependencies..." | tee -a "\$DEPLOY_LOG"
sudo apt-get update -qq 2>&1 | tee -a "\$DEPLOY_LOG"

# Install docker-compose and other dependencies
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "\$(date): Installing docker-compose..." | tee -a "\$DEPLOY_LOG"
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

sudo apt-get install -y yq jq gettext-base 2>&1 | tee -a "\$DEPLOY_LOG"

# Verify docker-compose installation
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "\$(date): ERROR: docker-compose installation failed" | tee -a "\$DEPLOY_LOG"
    exit 1
fi

# Pull latest images
echo "\$(date): Pulling Docker images..." | tee -a "\$DEPLOY_LOG"
docker-compose -f $compose_file pull 2>&1 | tee -a "\$DEPLOY_LOG"

# Start services
echo "\$(date): Starting Docker services..." | tee -a "\$DEPLOY_LOG"
docker-compose -f $compose_file up -d 2>&1 | tee -a "\$DEPLOY_LOG"

# Wait for services to stabilize
echo "\$(date): Waiting for services to stabilize..." | tee -a "\$DEPLOY_LOG"
sleep 30

# Check service status
echo "\$(date): Checking service status..." | tee -a "\$DEPLOY_LOG"
docker-compose -f $compose_file ps 2>&1 | tee -a "\$DEPLOY_LOG"

echo "\$(date): Application deployment completed" | tee -a "\$DEPLOY_LOG"
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
    
    # Try multiple tagging strategies to find instances
    local instance_ids=""
    
    # Strategy 1: Look for Stack tag (new tagging)
    local stack_tagged_instances
    stack_tagged_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Stack,Values=$stack_name" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    # Strategy 2: Look for Name tag with stack pattern (legacy tagging)
    local name_tagged_instances
    name_tagged_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${stack_name}-*" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    # Combine results and remove duplicates
    instance_ids=$(echo "$stack_tagged_instances $name_tagged_instances" | tr ' ' '\n' | grep -v "^$" | sort -u | tr '\n' ' ' | xargs)

    if [ -n "$instance_ids" ] && [ "$instance_ids" != "None" ]; then
        echo "$instance_ids" | tr ' ' '\n' | while read -r instance_id; do
            if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                aws ec2 terminate-instances --instance-ids "$instance_id" --region "$AWS_REGION" > /dev/null 2>&1 || true
                success "Terminated instance: $instance_id"
            fi
        done
    else
        info "No instances found for cleanup"
    fi
}

cleanup_security_groups() {
    local stack_name="$1"
    
    log "Cleaning up security groups for stack: $stack_name"
    
    # Try multiple strategies to find security groups
    local sg_ids=""
    
    # Strategy 1: Look for Stack tag
    local stack_tagged_sgs
    stack_tagged_sgs=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Stack,Values=${stack_name}" \
        --query 'SecurityGroups[].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    # Strategy 2: Look for group name pattern
    local name_pattern_sgs
    name_pattern_sgs=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${stack_name}-*" \
        --query 'SecurityGroups[].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    # Combine results and remove duplicates
    sg_ids=$(echo "$stack_tagged_sgs $name_pattern_sgs" | tr ' ' '\n' | grep -v "^$" | sort -u | tr '\n' ' ' | xargs)

    if [ -n "$sg_ids" ] && [ "$sg_ids" != "None" ]; then
        echo "$sg_ids" | tr ' ' '\n' | while read -r sg_id; do
            if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
                # Wait a bit for instances to be terminated first
                sleep 5
                aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" > /dev/null 2>&1 || true
                success "Deleted security group: $sg_id"
            fi
        done
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
# MONITORING FUNCTIONS
# =============================================================================

setup_cloudwatch_monitoring() {
    local stack_name="$1"
    local instance_id="$2"
    local alb_arn="$3"
    
    if [ -z "$stack_name" ] || [ -z "$instance_id" ]; then
        error "setup_cloudwatch_monitoring requires stack_name and instance_id parameters"
        return 1
    fi

    log "Setting up CloudWatch monitoring for instance: $instance_id"

    # Create CloudWatch log group
    local log_group="${CLOUDWATCH_LOG_GROUP:-/aws/GeuseMaker}/${ENVIRONMENT:-development}"
    aws logs create-log-group \
        --log-group-name "$log_group" \
        --region "$AWS_REGION" 2>/dev/null || true

    # Set log retention
    aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days "${CLOUDWATCH_LOG_RETENTION:-7}" \
        --region "$AWS_REGION" 2>/dev/null || true

    # Create custom metrics alarms
    create_instance_alarms "$stack_name" "$instance_id"
    
    if [ -n "$alb_arn" ]; then
        create_alb_alarms "$stack_name" "$alb_arn"
    fi

    success "CloudWatch monitoring configured"
    return 0
}

create_instance_alarms() {
    local stack_name="$1"
    local instance_id="$2"
    
    # High CPU alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-high-cpu" \
        --alarm-description "High CPU utilization for ${stack_name}" \
        --metric-name "CPUUtilization" \
        --namespace "AWS/EC2" \
        --statistic "Average" \
        --period 300 \
        --threshold 80 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --region "$AWS_REGION" || true

    # High memory alarm (if CloudWatch agent is installed)
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-high-memory" \
        --alarm-description "High memory utilization for ${stack_name}" \
        --metric-name "MemoryUtilization" \
        --namespace "CWAgent" \
        --statistic "Average" \
        --period 300 \
        --threshold 90 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --region "$AWS_REGION" || true

    # Instance status check alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-instance-status" \
        --alarm-description "Instance status check failed for ${stack_name}" \
        --metric-name "StatusCheckFailed_Instance" \
        --namespace "AWS/EC2" \
        --statistic "Maximum" \
        --period 60 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --evaluation-periods 1 \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --region "$AWS_REGION" || true
}

create_alb_alarms() {
    local stack_name="$1"
    local alb_arn="$2"
    
    # Extract ALB name from ARN
    local alb_name
    alb_name=$(echo "$alb_arn" | cut -d'/' -f2-3)

    # High response time alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-alb-high-response-time" \
        --alarm-description "High response time for ${stack_name} ALB" \
        --metric-name "TargetResponseTime" \
        --namespace "AWS/ApplicationELB" \
        --statistic "Average" \
        --period 300 \
        --threshold 5 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=LoadBalancer,Value="$alb_name" \
        --region "$AWS_REGION" || true

    # High error rate alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-alb-high-errors" \
        --alarm-description "High error rate for ${stack_name} ALB" \
        --metric-name "HTTPCode_Target_5XX_Count" \
        --namespace "AWS/ApplicationELB" \
        --statistic "Sum" \
        --period 300 \
        --threshold 10 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=LoadBalancer,Value="$alb_name" \
        --region "$AWS_REGION" || true
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

generate_user_data_script() {
    local stack_name="$1"
    local additional_commands="$2"
    
    cat << EOF
#!/bin/bash
# GeuseMaker Instance Setup
set -e

# Function to wait for apt locks to be released
wait_for_apt_lock() {
    local max_wait=600
    local wait_time=0
    echo "\$(date): Waiting for apt locks to be released..."
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
        if [ \$wait_time -ge \$max_wait ]; then
            echo "\$(date): Timeout waiting for apt locks, forcefully killing processes..."
            pkill -9 -f "unattended-upgrade" || true
            pkill -9 -f "apt-get" || true
            sleep 5
            break
        fi
        echo "\$(date): APT is locked by another process, waiting 15 seconds..."
        sleep 15
        wait_time=\$((wait_time + 15))
    done
    echo "\$(date): APT locks released or timeout reached"
}

# Wait for cloud-init and unattended-upgrades to complete
echo "\$(date): Waiting for initial cloud-init processes to complete..."
cloud-init status --wait || true

# Kill any running unattended-upgrade processes that may be holding locks
echo "\$(date): Stopping unattended-upgrades to prevent lock conflicts..."
systemctl stop unattended-upgrades || true
pkill -f unattended-upgrade || true
sleep 5

wait_for_apt_lock

# Expand root filesystem if needed
echo "\$(date): Expanding root filesystem..."
growpart /dev/\$(lsblk -no PKNAME /dev/\$(lsblk -no KNAME /)) 1 2>/dev/null || true
resize2fs /dev/\$(lsblk -no KNAME /) 2>/dev/null || true

# Clean up space before starting
echo "\$(date): Cleaning up disk space..."
apt-get clean || true
apt-get autoremove -y || true
rm -rf /var/lib/apt/lists/* || true
rm -rf /tmp/* || true
rm -rf /var/tmp/* || true

# Update system
echo "\$(date): Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# Install Docker
echo "\$(date): Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install Docker Compose
echo "\$(date): Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Optimize Docker daemon for limited disk space
echo "\$(date): Optimizing Docker configuration..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DOCKEREOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.size=25G"
    ],
    "max-concurrent-downloads": 2,
    "max-concurrent-uploads": 2,
    "live-restore": true
}
DOCKEREOF

# Install NVIDIA Container Toolkit (for GPU instances)
if lspci | grep -i nvidia; then
    echo "\$(date): Installing NVIDIA Docker support..."
    distribution=\$(. /etc/os-release;echo \$ID\$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/\$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
    wait_for_apt_lock
    apt-get update -qq
    apt-get install -y nvidia-container-toolkit
    systemctl restart docker
fi

# Install CloudWatch agent
echo "\$(date): Installing CloudWatch agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Create application directory
echo "\$(date): Setting up application directory..."
mkdir -p /home/ubuntu/GeuseMaker
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker

# Additional commands
$additional_commands

# Signal completion
echo "\$(date): User data script completed successfully"
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