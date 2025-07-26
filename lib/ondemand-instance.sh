#!/bin/bash
# =============================================================================
# On-Demand Instance Deployment Library
# Specialized functions for AWS On-Demand Instance deployments
# =============================================================================

# =============================================================================
# ON-DEMAND INSTANCE LAUNCH
# =============================================================================

launch_ondemand_instance() {
    local stack_name="$1"
    local instance_type="$2"
    local user_data="$3"
    local security_group_id="$4"
    local subnet_id="$5"
    local key_name="$6"
    local iam_instance_profile="$7"
    local additional_tags="$8"
    
    if [ -z "$stack_name" ] || [ -z "$instance_type" ]; then
        error "launch_ondemand_instance requires stack_name and instance_type parameters"
        return 1
    fi

    log "Launching on-demand instance..."
    log "  Instance Type: $instance_type"
    log "  Stack Name: $stack_name"

    # Get optimal AMI for the instance type
    local ami_id
    ami_id=$(get_nvidia_optimized_ami "$AWS_REGION")
    
    if [ -z "$ami_id" ]; then
        error "Failed to get optimized AMI"
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

    # Add IAM instance profile if provided
    if [ -n "$iam_instance_profile" ]; then
        launch_params+=(--iam-instance-profile Name="$iam_instance_profile")
    fi

    # Add user data if provided
    if [ -n "$user_data" ]; then
        local user_data_file
        user_data_file=$(mktemp)
        echo "$user_data" > "$user_data_file"
        launch_params+=(--user-data file://"$user_data_file")
    fi

    # Add block device mappings for GPU instances
    if [[ "$instance_type" =~ ^(g4dn|g5|p3|p4) ]]; then
        launch_params+=(--block-device-mappings '[{
            "DeviceName": "/dev/sda1",
            "Ebs": {
                "VolumeSize": 100,
                "VolumeType": "gp3",
                "DeleteOnTermination": true,
                "Encrypted": true
            }
        }]')
    fi

    # Launch the instance
    local instance_id
    instance_id=$(aws ec2 run-instances "${launch_params[@]}" \
        --query 'Instances[0].InstanceId' \
        --output text)

    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        error "Failed to launch on-demand instance"
        if [ -n "$user_data_file" ]; then
            rm -f "$user_data_file"
        fi
        return 1
    fi

    # Clean up user data file
    if [ -n "$user_data_file" ]; then
        rm -f "$user_data_file"
    fi

    success "On-demand instance launched: $instance_id"

    # Tag the instance
    tag_instance_with_metadata "$instance_id" "$stack_name" "ondemand" "$additional_tags"

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
# LOAD BALANCER SETUP
# =============================================================================

create_application_load_balancer() {
    local stack_name="$1"
    local security_group_id="$2"
    local subnet_ids=("${@:3}")
    
    if [ -z "$stack_name" ] || [ -z "$security_group_id" ] || [ ${#subnet_ids[@]} -eq 0 ]; then
        error "create_application_load_balancer requires stack_name, security_group_id, and subnet_ids parameters"
        return 1
    fi

    local alb_name="${stack_name}-alb"
    log "Creating Application Load Balancer: $alb_name"

    # Check if ALB already exists
    local alb_arn
    alb_arn=$(aws elbv2 describe-load-balancers \
        --names "$alb_name" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ "$alb_arn" != "None" ] && [ -n "$alb_arn" ]; then
        warning "Load balancer $alb_name already exists: $alb_arn"
        echo "$alb_arn"
        return 0
    fi

    # Create the load balancer
    alb_arn=$(aws elbv2 create-load-balancer \
        --name "$alb_name" \
        --subnets "${subnet_ids[@]}" \
        --security-groups "$security_group_id" \
        --scheme "$ALB_SCHEME" \
        --type "$ALB_TYPE" \
        --ip-address-type ipv4 \
        --tags Key=Name,Value="$alb_name" Key=Stack,Value="$stack_name" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$alb_arn" ] || [ "$alb_arn" = "None" ]; then
        error "Failed to create Application Load Balancer"
        return 1
    fi

    success "Application Load Balancer created: $alb_name"
    
    # Wait for ALB to be active
    log "Waiting for load balancer to be active..."
    aws elbv2 wait load-balancer-available \
        --load-balancer-arns "$alb_arn" \
        --region "$AWS_REGION"

    echo "$alb_arn"
    return 0
}

create_target_group() {
    local stack_name="$1"
    local service_name="$2"
    local port="$3"
    local vpc_id="$4"
    local health_check_path="${5:-/}"
    local health_check_port="${6:-traffic-port}"
    
    if [ -z "$stack_name" ] || [ -z "$service_name" ] || [ -z "$port" ] || [ -z "$vpc_id" ]; then
        error "create_target_group requires stack_name, service_name, port, and vpc_id parameters"
        return 1
    fi

    local tg_name="${stack_name}-${service_name}-tg"
    log "Creating target group: $tg_name"

    # Check if target group already exists
    local tg_arn
    tg_arn=$(aws elbv2 describe-target-groups \
        --names "$tg_name" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ "$tg_arn" != "None" ] && [ -n "$tg_arn" ]; then
        warning "Target group $tg_name already exists: $tg_arn"
        echo "$tg_arn"
        return 0
    fi

    # Create target group
    tg_arn=$(aws elbv2 create-target-group \
        --name "$tg_name" \
        --protocol HTTP \
        --port "$port" \
        --vpc-id "$vpc_id" \
        --health-check-protocol HTTP \
        --health-check-path "$health_check_path" \
        --health-check-port "$health_check_port" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --target-type instance \
        --tags Key=Name,Value="$tg_name" Key=Stack,Value="$stack_name" Key=Service,Value="$service_name" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$tg_arn" ] || [ "$tg_arn" = "None" ]; then
        error "Failed to create target group: $tg_name"
        return 1
    fi

    success "Target group created: $tg_name"
    echo "$tg_arn"
    return 0
}

register_instance_with_target_group() {
    local target_group_arn="$1"
    local instance_id="$2"
    local port="$3"
    
    if [ -z "$target_group_arn" ] || [ -z "$instance_id" ] || [ -z "$port" ]; then
        error "register_instance_with_target_group requires target_group_arn, instance_id, and port parameters"
        return 1
    fi

    log "Registering instance $instance_id with target group on port $port..."

    aws elbv2 register-targets \
        --target-group-arn "$target_group_arn" \
        --targets Id="$instance_id",Port="$port" \
        --region "$AWS_REGION"

    if [ $? -eq 0 ]; then
        success "Instance registered with target group"
        
        # Wait for target to be healthy
        log "Waiting for target to be healthy..."
        local max_wait=300
        local elapsed=0
        local check_interval=15
        
        while [ $elapsed -lt $max_wait ]; do
            local target_health
            target_health=$(aws elbv2 describe-target-health \
                --target-group-arn "$target_group_arn" \
                --targets Id="$instance_id",Port="$port" \
                --query 'TargetHealthDescriptions[0].TargetHealth.State' \
                --output text \
                --region "$AWS_REGION")

            case "$target_health" in
                "healthy")
                    success "Target is healthy"
                    return 0
                    ;;
                "unhealthy")
                    warning "Target is unhealthy (${elapsed}s elapsed)"
                    ;;
                "initial"|"draining"|"unused")
                    info "Target health check in progress: $target_health (${elapsed}s elapsed)"
                    ;;
            esac
            
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
        done
        
        warning "Target health check timed out after ${max_wait}s"
        return 1
    else
        error "Failed to register instance with target group"
        return 1
    fi
}

create_alb_listener() {
    local alb_arn="$1"
    local target_group_arn="$2"
    local port="${3:-80}"
    local protocol="${4:-HTTP}"
    
    if [ -z "$alb_arn" ] || [ -z "$target_group_arn" ]; then
        error "create_alb_listener requires alb_arn and target_group_arn parameters"
        return 1
    fi

    log "Creating ALB listener on port $port..."

    local listener_arn
    listener_arn=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol "$protocol" \
        --port "$port" \
        --default-actions Type=forward,TargetGroupArn="$target_group_arn" \
        --query 'Listeners[0].ListenerArn' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$listener_arn" ] || [ "$listener_arn" = "None" ]; then
        error "Failed to create ALB listener"
        return 1
    fi

    success "ALB listener created on port $port"
    echo "$listener_arn"
    return 0
}

# =============================================================================
# CLOUDFRONT SETUP
# =============================================================================

setup_cloudfront_distribution() {
    local stack_name="$1"
    local alb_dns_name="$2"
    local origin_path="${3:-}"
    
    if [ -z "$stack_name" ] || [ -z "$alb_dns_name" ]; then
        error "setup_cloudfront_distribution requires stack_name and alb_dns_name parameters"
        return 1
    fi

    log "Setting up CloudFront distribution for ALB: $alb_dns_name"

    # Set default CloudFront TTL values if not set
    local min_ttl="${CLOUDFRONT_MIN_TTL:-0}"
    local default_ttl="${CLOUDFRONT_DEFAULT_TTL:-86400}"
    local max_ttl="${CLOUDFRONT_MAX_TTL:-31536000}"
    local caller_ref="${stack_name}-$(date +%s)"
    local origin_id="${stack_name}-alb-origin"
    
    # Create distribution configuration with validated JSON structure
    local temp_config_file="/tmp/cloudfront-config-${stack_name}-$(date +%s).json"
    
    # Generate CloudFront configuration with proper escaping and validation
    cat > "$temp_config_file" << EOF
{
    "CallerReference": "${caller_ref}",
    "Comment": "CloudFront distribution for ${stack_name} GeuseMaker",
    "DefaultCacheBehavior": {
        "TargetOriginId": "${origin_id}",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {"Forward": "all"},
            "Headers": {
                "Quantity": 1,
                "Items": ["*"]
            }
        },
        "MinTTL": ${min_ttl},
        "DefaultTTL": ${default_ttl},
        "MaxTTL": ${max_ttl},
        "Compress": true,
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        }
    },
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "${origin_id}",
            "DomainName": "${alb_dns_name}",
            "OriginPath": "${origin_path}",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "http-only",
                "OriginSslProtocols": {
                    "Quantity": 1,
                    "Items": ["TLSv1.2"]
                },
                "OriginReadTimeout": 30,
                "OriginKeepaliveTimeout": 5
            }
        }]
    },
    "Enabled": true,
    "PriceClass": "${CLOUDFRONT_PRICE_CLASS:-PriceClass_100}",
    "CallerReference": "${caller_ref}"
}
EOF

    # Validate JSON syntax before using
    if ! python3 -c "import json; json.load(open('$temp_config_file'))" 2>/dev/null; then
        if command -v jq >/dev/null 2>&1; then
            if ! jq . "$temp_config_file" >/dev/null 2>&1; then
                error "Generated CloudFront configuration has invalid JSON syntax"
                rm -f "$temp_config_file"
                return 1
            fi
        else
            warning "Cannot validate JSON syntax (jq not available)"
        fi
    fi

    # Create the distribution
    local distribution_id
    distribution_id=$(aws cloudfront create-distribution \
        --distribution-config "file://$temp_config_file" \
        --query 'Distribution.Id' \
        --output text \
        --region "$AWS_REGION")

    # Clean up temporary file
    rm -f "$temp_config_file"
    
    if [ -z "$distribution_id" ] || [ "$distribution_id" = "None" ] || [ "$distribution_id" = "null" ]; then
        error "Failed to create CloudFront distribution"
        return 1
    fi

    success "CloudFront distribution created: $distribution_id"
    
    # Get distribution domain name
    local domain_name
    domain_name=$(aws cloudfront get-distribution \
        --id "$distribution_id" \
        --query 'Distribution.DomainName' \
        --output text \
        --region "$AWS_REGION")

    log "CloudFront distribution domain: $domain_name"
    log "Note: Distribution deployment may take 15-20 minutes"

    echo "${distribution_id}:${domain_name}"
    return 0
}

# =============================================================================
# ENHANCED MONITORING
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
    local log_group="${CLOUDWATCH_LOG_GROUP}/${ENVIRONMENT}"
    aws logs create-log-group \
        --log-group-name "$log_group" \
        --region "$AWS_REGION" 2>/dev/null || true

    # Set log retention
    aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days "$CLOUDWATCH_LOG_RETENTION" \
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
        --region "$AWS_REGION"

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
        --region "$AWS_REGION"

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
        --region "$AWS_REGION"
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
        --region "$AWS_REGION"

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
        --region "$AWS_REGION"
}

# =============================================================================
# COST OPTIMIZATION
# =============================================================================

analyze_ondemand_costs() {
    local instance_type="$1"
    local hours="${2:-24}"
    local include_storage="${3:-true}"
    local include_data_transfer="${4:-true}"
    
    if [ -z "$instance_type" ]; then
        error "analyze_ondemand_costs requires instance_type parameter"
        return 1
    fi

    log "Analyzing on-demand costs for $instance_type..."

    # Get on-demand pricing (simplified lookup)
    local hourly_rate
    case "$instance_type" in
        "g4dn.xlarge")
            hourly_rate="0.526"
            ;;
        "g4dn.2xlarge")
            hourly_rate="0.752"
            ;;
        "g5.xlarge")
            hourly_rate="1.006"
            ;;
        "t3.medium")
            hourly_rate="0.0416"
            ;;
        "t3.large")
            hourly_rate="0.0832"
            ;;
        "c5.xlarge")
            hourly_rate="0.17"
            ;;
        *)
            warning "Pricing not available for instance type: $instance_type"
            return 1
            ;;
    esac

    local compute_cost
    compute_cost=$(echo "$hourly_rate * $hours" | bc -l)

    local storage_cost="0"
    if [ "$include_storage" = "true" ]; then
        # Estimate EBS cost (100GB GP3)
        storage_cost=$(echo "0.08 * $hours / 24" | bc -l)  # $0.08/GB/month
    fi

    local data_transfer_cost="0"
    if [ "$include_data_transfer" = "true" ]; then
        # Estimate data transfer cost (1GB/hour)
        data_transfer_cost=$(echo "0.09 * $hours" | bc -l)  # $0.09/GB out
    fi

    local total_cost
    total_cost=$(echo "$compute_cost + $storage_cost + $data_transfer_cost" | bc -l)

    info "=== On-Demand Cost Analysis ==="
    info "Instance Type: $instance_type"
    info "Duration: ${hours} hours"
    info "Compute Cost: \$${compute_cost}"
    if [ "$include_storage" = "true" ]; then
        info "Storage Cost: \$${storage_cost}"
    fi
    if [ "$include_data_transfer" = "true" ]; then
        info "Data Transfer Cost: \$${data_transfer_cost}"
    fi
    info "Total Estimated Cost: \$${total_cost}"

    return 0
}

get_cost_optimization_recommendations() {
    local instance_type="$1"
    local usage_hours_per_day="${2:-8}"
    
    if [ -z "$instance_type" ]; then
        error "get_cost_optimization_recommendations requires instance_type parameter"
        return 1
    fi

    info "=== Cost Optimization Recommendations ==="
    
    # Recommend spot instances for development
    if [ "$ENVIRONMENT" = "development" ]; then
        info "💡 Consider using spot instances for development workloads (60-90% savings)"
    fi
    
    # Recommend scheduling for low usage
    if (( $(echo "$usage_hours_per_day < 12" | bc -l) )); then
        info "💡 Consider implementing auto-start/stop scheduling for cost savings"
    fi
    
    # Recommend Reserved Instances for high usage
    if (( $(echo "$usage_hours_per_day > 16" | bc -l) )) && [ "$ENVIRONMENT" = "production" ]; then
        info "💡 Consider Reserved Instances for production workloads (up to 72% savings)"
    fi
    
    # Recommend right-sizing
    info "💡 Monitor CPU and memory utilization to right-size your instances"
    info "💡 Use CloudWatch metrics to identify underutilized resources"
    
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
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

get_alb_dns_name() {
    local alb_arn="$1"
    
    if [ -z "$alb_arn" ]; then
        error "get_alb_dns_name requires alb_arn parameter"
        return 1
    fi

    local dns_name
    dns_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION")

    if [ "$dns_name" = "None" ] || [ -z "$dns_name" ]; then
        error "No DNS name found for ALB: $alb_arn"
        return 1
    fi

    echo "$dns_name"
    return 0
}