#!/bin/bash
# =============================================================================
# Simple Instance Deployment Library
# Specialized functions for simple AWS deployments
# =============================================================================

# =============================================================================
# SIMPLE INSTANCE LAUNCH
# =============================================================================

launch_simple_instance() {
    local stack_name="$1"
    local instance_type="$2"
    local user_data="$3"
    local security_group_id="$4"
    local subnet_id="$5"
    local key_name="$6"
    
    if [ -z "$stack_name" ] || [ -z "$instance_type" ]; then
        error "launch_simple_instance requires stack_name and instance_type parameters"
        return 1
    fi

    log "Launching simple instance..."
    log "  Instance Type: $instance_type"
    log "  Stack Name: $stack_name"

    # Get Ubuntu 22.04 LTS AMI (suitable for simple deployments)
    local ami_id
    ami_id=$(get_ubuntu_ami "$AWS_REGION")
    
    if [ -z "$ami_id" ]; then
        error "Failed to get Ubuntu AMI"
        return 1
    fi

    # Prepare launch parameters
    local launch_params=(
        --image-id "$ami_id"
        --instance-type "$instance_type"
        --key-name "$key_name"
        --security-group-ids "$security_group_id"
        --subnet-id "$subnet_id"
        --associate-public-ip-address
        --instance-initiated-shutdown-behavior terminate
        --region "$AWS_REGION"
    )

    # Add user data if provided
    if [ -n "$user_data" ]; then
        local user_data_file
        user_data_file=$(mktemp)
        echo "$user_data" > "$user_data_file"
        launch_params+=(--user-data file://"$user_data_file")
    fi

    # Simple instance uses standard storage
    launch_params+=(--block-device-mappings '[{
        "DeviceName": "/dev/sda1",
        "Ebs": {
            "VolumeSize": 30,
            "VolumeType": "gp3",
            "DeleteOnTermination": true,
            "Encrypted": true
        }
    }]')

    # Launch the instance
    local instance_id
    instance_id=$(aws ec2 run-instances "${launch_params[@]}" \
        --query 'Instances[0].InstanceId' \
        --output text)

    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        error "Failed to launch simple instance"
        if [ -n "$user_data_file" ]; then
            rm -f "$user_data_file"
        fi
        return 1
    fi

    # Clean up user data file
    if [ -n "$user_data_file" ]; then
        rm -f "$user_data_file"
    fi

    success "Simple instance launched: $instance_id"

    # Tag the instance
    tag_instance_with_metadata "$instance_id" "$stack_name" "simple"

    # Wait for instance to be running
    log "Waiting for instance to be running..."
    if ! wait_for_instance_running "$instance_id"; then
        error "Instance failed to reach running state"
        return 1
    fi

    echo "$instance_id"
    return 0
}

wait_for_instance_running() {
    local instance_id="$1"
    local max_wait="${2:-300}"  # 5 minutes default
    local check_interval="${3:-10}"
    
    log "Waiting for instance to be running: $instance_id"
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local instance_state
        instance_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text \
            --region "$AWS_REGION")

        case "$instance_state" in
            "running")
                success "Instance is running: $instance_id"
                return 0
                ;;
            "pending")
                info "Instance pending... (${elapsed}s elapsed)"
                ;;
            "terminated"|"stopping"|"stopped")
                error "Instance reached unexpected state: $instance_state"
                return 1
                ;;
        esac
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    error "Instance failed to reach running state within ${max_wait}s"
    return 1
}

# =============================================================================
# SIMPLE USER DATA GENERATION
# =============================================================================

create_simple_user_data() {
    local stack_name="$1"
    local compose_file="${2:-docker-compose.yml}"
    
    cat << EOF
#!/bin/bash
# Simple GeuseMaker Instance Setup
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y curl wget unzip git htop

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
mkdir -p /home/ubuntu/GeuseMaker
chown ubuntu:ubuntu /home/ubuntu/GeuseMaker

# Install basic monitoring tools
apt-get install -y htop iotop nethogs

# Configure automatic security updates
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# Signal completion
touch /tmp/user-data-complete
echo "Simple instance setup completed at \$(date)" >> /var/log/user-data.log
EOF
}

# =============================================================================
# SIMPLE DEPLOYMENT VALIDATION
# =============================================================================

validate_simple_deployment() {
    local instance_ip="$1"
    local basic_services=("${@:2}")
    
    if [ -z "$instance_ip" ]; then
        error "validate_simple_deployment requires instance_ip parameter"
        return 1
    fi

    # Default services for simple deployment
    if [ ${#basic_services[@]} -eq 0 ]; then
        basic_services=("n8n:5678" "ollama:11434")
    fi

    log "Validating simple deployment on $instance_ip..."
    
    # Check SSH connectivity
    if ! validate_ssh_connectivity "$instance_ip"; then
        error "SSH connectivity check failed"
        return 1
    fi

    # Check Docker installation
    if ! validate_docker_installation "$instance_ip"; then
        error "Docker installation check failed"
        return 1
    fi

    # Check service endpoints
    validate_service_endpoints "$instance_ip" "${basic_services[@]}"
    
    return $?
}

validate_ssh_connectivity() {
    local instance_ip="$1"
    local key_file="${2:-${STACK_NAME}-key.pem}"
    
    log "Validating SSH connectivity to $instance_ip..."
    
    if [ ! -f "$key_file" ]; then
        error "Key file not found: $key_file"
        return 1
    fi

    # Test SSH connection
    if ssh -i "$key_file" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$instance_ip" "echo 'SSH connectivity test passed'" &> /dev/null; then
        success "SSH connectivity validated"
        return 0
    else
        error "SSH connectivity test failed"
        return 1
    fi
}

validate_docker_installation() {
    local instance_ip="$1"
    local key_file="${2:-${STACK_NAME}-key.pem}"
    
    log "Validating Docker installation on $instance_ip..."
    
    # Check Docker daemon
    if ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$instance_ip" "docker --version && docker info" &> /dev/null; then
        success "Docker installation validated"
        return 0
    else
        error "Docker installation validation failed"
        return 1
    fi
}

# =============================================================================
# SIMPLE MONITORING SETUP
# =============================================================================

setup_simple_monitoring() {
    local stack_name="$1"
    local instance_id="$2"
    
    if [ -z "$stack_name" ] || [ -z "$instance_id" ]; then
        error "setup_simple_monitoring requires stack_name and instance_id parameters"
        return 1
    fi

    log "Setting up simple monitoring for: $instance_id"

    # Create basic CloudWatch alarms
    create_basic_alarms "$stack_name" "$instance_id"

    # Optional: Set up basic log monitoring
    setup_basic_logging "$stack_name" "$instance_id"

    success "Simple monitoring configured"
    return 0
}

create_basic_alarms() {
    local stack_name="$1"
    local instance_id="$2"
    
    # Basic CPU alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-cpu-utilization" \
        --alarm-description "High CPU utilization alert for ${stack_name}" \
        --metric-name "CPUUtilization" \
        --namespace "AWS/EC2" \
        --statistic "Average" \
        --period 300 \
        --threshold 85 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --region "$AWS_REGION"

    # Instance status alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${stack_name}-status-check" \
        --alarm-description "Instance status check failure for ${stack_name}" \
        --metric-name "StatusCheckFailed_Instance" \
        --namespace "AWS/EC2" \
        --statistic "Maximum" \
        --period 60 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --evaluation-periods 1 \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --region "$AWS_REGION"

    success "Basic CloudWatch alarms created"
}

setup_basic_logging() {
    local stack_name="$1"
    local instance_id="$2"
    
    # Create basic log group
    local log_group="/aws/ec2/${stack_name}"
    aws logs create-log-group \
        --log-group-name "$log_group" \
        --region "$AWS_REGION" 2>/dev/null || true

    # Set retention to 7 days for simple deployment
    aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days 7 \
        --region "$AWS_REGION" 2>/dev/null || true

    info "Basic logging configured with 7-day retention"
}

# =============================================================================
# SIMPLE COST ANALYSIS
# =============================================================================

analyze_simple_deployment_costs() {
    local instance_type="$1"
    local hours_per_day="${2:-8}"
    local days="${3:-30}"
    
    if [ -z "$instance_type" ]; then
        error "analyze_simple_deployment_costs requires instance_type parameter"
        return 1
    fi

    log "Analyzing costs for simple deployment..."

    # Get hourly rate for instance type
    local hourly_rate
    case "$instance_type" in
        "t3.micro")
            hourly_rate="0.0104"
            ;;
        "t3.small")
            hourly_rate="0.0208"
            ;;
        "t3.medium")
            hourly_rate="0.0416"
            ;;
        "t3.large")
            hourly_rate="0.0832"
            ;;
        *)
            warning "Pricing not available for instance type: $instance_type"
            return 1
            ;;
    esac

    local total_hours
    total_hours=$(echo "$hours_per_day * $days" | bc -l)
    
    local compute_cost
    compute_cost=$(echo "$hourly_rate * $total_hours" | bc -l)

    # Simple deployment storage cost (30GB)
    local storage_cost
    storage_cost=$(echo "0.08 * 30 / 30 * $days" | bc -l)  # $0.08/GB/month

    # Minimal data transfer for simple deployment
    local data_transfer_cost
    data_transfer_cost=$(echo "0.09 * 1 * $days" | bc -l)  # 1GB/day

    local total_cost
    total_cost=$(echo "$compute_cost + $storage_cost + $data_transfer_cost" | bc -l)

    info "=== Simple Deployment Cost Analysis ==="
    info "Instance Type: $instance_type"
    info "Usage: ${hours_per_day} hours/day for $days days"
    info "Total Runtime: $total_hours hours"
    info "Compute Cost: \$${compute_cost}"
    info "Storage Cost (30GB): \$${storage_cost}"
    info "Data Transfer Cost: \$${data_transfer_cost}"
    info "Total Estimated Cost: \$${total_cost}"
    info ""
    info "Cost per day: \$$(echo "$total_cost / $days" | bc -l)"
    info "Cost per hour of usage: \$$(echo "$total_cost / $total_hours" | bc -l)"

    return 0
}

get_simple_deployment_recommendations() {
    local instance_type="$1"
    local usage_pattern="${2:-development}"
    
    info "=== Simple Deployment Recommendations ==="
    
    case "$usage_pattern" in
        "development")
            info "💡 For development workloads:"
            info "   - Consider t3.small or t3.medium for basic AI experimentation"
            info "   - Use instance scheduling to reduce costs during non-working hours"
            info "   - Enable automated backups for important work"
            ;;
        "learning")
            info "💡 For learning and experimentation:"
            info "   - t3.micro or t3.small is sufficient for learning"
            info "   - Consider spot instances for additional cost savings"
            info "   - Use the AWS Free Tier if eligible"
            ;;
        "testing")
            info "💡 For testing workloads:"
            info "   - t3.medium provides good balance of performance and cost"
            info "   - Implement automated testing to minimize runtime"
            info "   - Use infrastructure as code for consistent deployments"
            ;;
        "production")
            warning "Simple deployment not recommended for production workloads"
            info "Consider upgrading to on-demand or spot deployment with:"
            info "   - Load balancing for high availability"
            info "   - Auto-scaling for demand fluctuation"
            info "   - Enhanced monitoring and alerting"
            ;;
    esac
    
    info ""
    info "💡 General recommendations:"
    info "   - Monitor CPU and memory usage to right-size your instance"
    info "   - Enable CloudWatch basic monitoring"
    info "   - Set up billing alerts to avoid unexpected charges"
    info "   - Use tags to track resource usage and costs"

    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

get_ubuntu_ami() {
    local region="$1"
    
    # Get the latest Ubuntu 22.04 LTS AMI
    local ami_id
    ami_id=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters \
            "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$region")

    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        error "Failed to find Ubuntu 22.04 LTS AMI in region: $region"
        return 1
    fi

    echo "$ami_id"
    return 0
}

display_simple_deployment_summary() {
    local stack_name="$1"
    local instance_id="$2"
    local instance_ip="$3"
    local cost_estimate="$4"
    
    echo
    success "=== Simple Deployment Summary ==="
    echo "Stack Name: $stack_name"
    echo "Instance ID: $instance_id"
    echo "Public IP: $instance_ip"
    echo "Environment: $ENVIRONMENT"
    echo ""
    echo "🌐 Access URLs:"
    echo "   SSH: ssh -i ${stack_name}-key.pem ubuntu@${instance_ip}"
    echo "   n8n: http://${instance_ip}:5678"
    echo "   Ollama: http://${instance_ip}:11434"
    echo ""
    echo "📊 Basic Monitoring:"
    echo "   CloudWatch Dashboard: AWS Console > CloudWatch > Dashboards"
    echo "   Instance Metrics: AWS Console > EC2 > Instances > $instance_id"
    echo ""
    echo "💰 Estimated Cost: \$${cost_estimate}/month"
    echo ""
    info "Next Steps:"
    info "1. Wait for instance initialization to complete (~5 minutes)"
    info "2. SSH into the instance and verify Docker installation"
    info "3. Deploy your AI applications using Docker Compose"
    info "4. Set up regular backups for important data"
    info "5. Monitor usage and optimize costs as needed"
    echo
}

validate_simple_configuration() {
    local instance_type="$1"
    
    # Validate that instance type is appropriate for simple deployment
    local recommended_types=("t3.micro" "t3.small" "t3.medium" "t3.large")
    
    if [[ ! " ${recommended_types[*]} " =~ " ${instance_type} " ]]; then
        warning "Instance type $instance_type may be oversized for simple deployment"
        info "Recommended types for simple deployment: ${recommended_types[*]}"
    fi

    # Check if GPU instance is being used unnecessarily
    if [[ "$instance_type" =~ ^(g4dn|g5|p3|p4) ]]; then
        warning "GPU instance type detected for simple deployment"
        warning "This will significantly increase costs without providing benefits"
        info "Consider switching to a general-purpose instance type"
    fi

    return 0
}