#!/bin/bash
# =============================================================================
# Spot Instance Deployment Library
# Specialized functions for AWS Spot Instance deployments
# =============================================================================

# =============================================================================
# SPOT PRICING ANALYSIS
# =============================================================================

analyze_spot_pricing() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    local availability_zones=("${@:3}")
    
    if [ -z "$instance_type" ]; then
        error "analyze_spot_pricing requires instance_type parameter"
        return 1
    fi

    log "Analyzing spot pricing for $instance_type in $region..."

    # Get all AZs if none specified
    if [ ${#availability_zones[@]} -eq 0 ]; then
        mapfile -t availability_zones < <(aws ec2 describe-availability-zones \
            --region "$region" \
            --query 'AvailabilityZones[].ZoneName' \
            --output text | tr '\t' '\n')
    fi

    local best_az=""
    local best_price=""
    local current_prices=()

    # Check pricing in each AZ
    for az in "${availability_zones[@]}"; do
        local price_info
        price_info=$(aws ec2 describe-spot-price-history \
            --instance-types "$instance_type" \
            --availability-zone "$az" \
            --product-descriptions "Linux/UNIX" \
            --max-items 1 \
            --region "$region" \
            --query 'SpotPriceHistory[0].[AvailabilityZone,SpotPrice,Timestamp]' \
            --output text 2>/dev/null)

        if [ -n "$price_info" ]; then
            local current_price
            current_price=$(echo "$price_info" | cut -f2)
            current_prices+=("$az:$current_price")
            
            if [ -z "$best_price" ] || (( $(echo "$current_price < $best_price" | bc -l) )); then
                best_az="$az"
                best_price="$current_price"
            fi
            
            info "Spot price in $az: \$${current_price}/hour"
        fi
    done

    if [ -n "$best_az" ]; then
        success "Best spot price: \$${best_price}/hour in $best_az"
        echo "$best_az:$best_price"
    else
        error "Could not retrieve spot pricing information"
        return 1
    fi

    return 0
}

get_optimal_spot_configuration() {
    local instance_type="$1"
    local max_price="$2"
    local region="${3:-$AWS_REGION}"
    
    if [ -z "$instance_type" ] || [ -z "$max_price" ]; then
        error "get_optimal_spot_configuration requires instance_type and max_price parameters"
        return 1
    fi

    log "Finding optimal spot configuration for $instance_type (max: \$${max_price}/hour)..."

    # Analyze current pricing
    local pricing_result
    pricing_result=$(analyze_spot_pricing "$instance_type" "$region")
    
    if [ $? -ne 0 ]; then
        error "Failed to analyze spot pricing"
        return 1
    fi

    local best_az="${pricing_result%:*}"
    local best_price="${pricing_result#*:}"

    # Check if best price is within budget
    if (( $(echo "$best_price > $max_price" | bc -l) )); then
        warning "Best available spot price (\$${best_price}) exceeds maximum (\$${max_price})"
        
        # Suggest alternative instance types
        suggest_alternative_instance_types "$instance_type" "$max_price" "$region"
        return 1
    fi

    # Calculate recommended bid price (10% above current price)
    local recommended_bid
    recommended_bid=$(echo "$best_price * 1.1" | bc -l)
    
    # Cap at max price
    if (( $(echo "$recommended_bid > $max_price" | bc -l) )); then
        recommended_bid="$max_price"
    fi

    success "Optimal configuration found:"
    info "  Availability Zone: $best_az"
    info "  Current Price: \$${best_price}/hour"
    info "  Recommended Bid: \$${recommended_bid}/hour"

    echo "${best_az}:${recommended_bid}"
    return 0
}

suggest_alternative_instance_types() {
    local target_instance_type="$1"
    local max_price="$2"
    local region="$3"
    
    log "Suggesting alternative instance types within budget..."

    # Alternative instance types based on target type
    local alternatives=()
    case "$target_instance_type" in
        "g4dn.xlarge")
            alternatives=("g4dn.large" "g5.large" "c5.xlarge" "m5.xlarge")
            ;;
        "g4dn.2xlarge")
            alternatives=("g4dn.xlarge" "g5.xlarge" "c5.2xlarge" "m5.2xlarge")
            ;;
        "g5.xlarge")
            alternatives=("g4dn.xlarge" "g5.large" "c5.xlarge")
            ;;
        *)
            warning "No alternatives defined for instance type: $target_instance_type"
            return 1
            ;;
    esac

    info "Checking alternative instance types:"
    for alt_type in "${alternatives[@]}"; do
        local pricing_result
        pricing_result=$(analyze_spot_pricing "$alt_type" "$region" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            local best_price="${pricing_result#*:}"
            if (( $(echo "$best_price <= $max_price" | bc -l) )); then
                success "  $alt_type: \$${best_price}/hour ✓"
            else
                info "  $alt_type: \$${best_price}/hour (over budget)"
            fi
        fi
    done
}

# =============================================================================
# SPOT INSTANCE LAUNCH
# =============================================================================

launch_spot_instance_with_failover() {
    local stack_name="$1"
    local instance_type="$2"
    local spot_price="$3"
    local user_data="$4"
    local security_group_id="$5"
    local subnet_id="$6"
    local key_name="$7"
    local iam_instance_profile="$8"
    
    if [ -z "$stack_name" ] || [ -z "$instance_type" ] || [ -z "$spot_price" ]; then
        error "launch_spot_instance_with_failover requires stack_name, instance_type, and spot_price parameters"
        return 1
    fi

    log "Launching spot instance with failover strategy..."

    # Get optimal spot configuration
    local optimal_config
    optimal_config=$(get_optimal_spot_configuration "$instance_type" "$spot_price")
    
    if [ $? -ne 0 ]; then
        error "Failed to get optimal spot configuration"
        return 1
    fi

    local target_az="${optimal_config%:*}"
    local bid_price="${optimal_config#*:}"

    # Get AMI for the instance type
    local ami_id
    ami_id=$(get_nvidia_optimized_ami "$AWS_REGION")
    
    if [ -z "$ami_id" ]; then
        error "Failed to get optimized AMI"
        return 1
    fi

    # Create spot instance request
    log "Creating spot instance request..."
    log "  Instance Type: $instance_type"
    log "  Bid Price: \$${bid_price}/hour"
    log "  Availability Zone: $target_az"

    # Create spot launch specification
    local launch_spec='{
        "ImageId": "'$ami_id'",
        "InstanceType": "'$instance_type'",
        "KeyName": "'$key_name'",
        "SecurityGroupIds": ["'$security_group_id'"],
        "SubnetId": "'$subnet_id'",
        "UserData": "'$(echo -n "$user_data" | base64 -w 0)'",
        "IamInstanceProfile": {"Name": "'$iam_instance_profile'"},
        "Placement": {"AvailabilityZone": "'$target_az'"}
    }'

    # Submit spot instance request
    local spot_request_id
    spot_request_id=$(aws ec2 request-spot-instances \
        --spot-price "$bid_price" \
        --instance-count 1 \
        --type "$SPOT_TYPE" \
        --launch-specification "$launch_spec" \
        --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
        --output text \
        --region "$AWS_REGION")

    if [ -z "$spot_request_id" ] || [ "$spot_request_id" = "None" ]; then
        error "Failed to create spot instance request"
        return 1
    fi

    success "Spot instance request created: $spot_request_id"

    # Wait for spot request to be fulfilled
    local instance_id
    instance_id=$(wait_for_spot_fulfillment "$spot_request_id" "$stack_name")
    
    if [ $? -ne 0 ]; then
        warning "Spot request failed or timed out. Attempting failover..."
        
        # Cancel the failed request
        aws ec2 cancel-spot-instance-requests \
            --spot-instance-request-ids "$spot_request_id" \
            --region "$AWS_REGION" > /dev/null
        
        # Try fallback strategy
        instance_id=$(launch_spot_instance_fallback "$stack_name" "$instance_type" "$spot_price" "$user_data" "$security_group_id" "$subnet_id" "$key_name" "$iam_instance_profile")
        
        if [ $? -ne 0 ]; then
            error "All spot launch strategies failed"
            return 1
        fi
    fi

    echo "$instance_id"
    return 0
}

wait_for_spot_fulfillment() {
    local spot_request_id="$1"
    local stack_name="$2"
    local max_wait="${3:-300}"  # 5 minutes default
    local check_interval="${4:-10}"
    
    log "Waiting for spot request fulfillment: $spot_request_id"
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local request_state
        request_state=$(aws ec2 describe-spot-instance-requests \
            --spot-instance-request-ids "$spot_request_id" \
            --query 'SpotInstanceRequests[0].State' \
            --output text \
            --region "$AWS_REGION")

        case "$request_state" in
            "active")
                local instance_id
                instance_id=$(aws ec2 describe-spot-instance-requests \
                    --spot-instance-request-ids "$spot_request_id" \
                    --query 'SpotInstanceRequests[0].InstanceId' \
                    --output text \
                    --region "$AWS_REGION")
                
                success "Spot instance launched: $instance_id"
                
                # Tag the instance
                tag_instance_with_metadata "$instance_id" "$stack_name" "spot" \
                    "Key=SpotRequestId,Value=$spot_request_id"
                
                echo "$instance_id"
                return 0
                ;;
            "failed"|"cancelled"|"closed")
                local status_code
                status_code=$(aws ec2 describe-spot-instance-requests \
                    --spot-instance-request-ids "$spot_request_id" \
                    --query 'SpotInstanceRequests[0].Status.Code' \
                    --output text \
                    --region "$AWS_REGION")
                
                error "Spot request failed with status: $status_code"
                return 1
                ;;
            "open")
                info "Spot request pending... (${elapsed}s elapsed)"
                ;;
        esac
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    error "Spot request timed out after ${max_wait}s"
    return 1
}

launch_spot_instance_fallback() {
    local stack_name="$1"
    local instance_type="$2"
    local max_price="$3"
    local user_data="$4"
    local security_group_id="$5"
    local subnet_id="$6"
    local key_name="$7"
    local iam_instance_profile="$8"
    
    log "Attempting spot instance fallback strategies..."

    # Strategy 1: Try alternative availability zones
    local azs
    mapfile -t azs < <(aws ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --query 'AvailabilityZones[].ZoneName' \
        --output text | tr '\t' '\n')

    for az in "${azs[@]}"; do
        log "Trying availability zone: $az"
        
        # Get subnet for this AZ
        local az_subnet_id
        az_subnet_id=$(aws ec2 describe-subnets \
            --filters "Name=availability-zone,Values=$az" "Name=state,Values=available" \
            --query 'Subnets[0].SubnetId' \
            --output text \
            --region "$AWS_REGION")

        if [ "$az_subnet_id" != "None" ] && [ -n "$az_subnet_id" ]; then
            # Try spot launch in this AZ
            local launch_spec='{
                "ImageId": "'$(get_nvidia_optimized_ami "$AWS_REGION")'",
                "InstanceType": "'$instance_type'",
                "KeyName": "'$key_name'",
                "SecurityGroupIds": ["'$security_group_id'"],
                "SubnetId": "'$az_subnet_id'",
                "UserData": "'$(echo -n "$user_data" | base64 -w 0)'",
                "IamInstanceProfile": {"Name": "'$iam_instance_profile'"},
                "Placement": {"AvailabilityZone": "'$az'"}
            }'

            local spot_request_id
            spot_request_id=$(aws ec2 request-spot-instances \
                --spot-price "$max_price" \
                --instance-count 1 \
                --type "one-time" \
                --launch-specification "$launch_spec" \
                --query 'SpotInstanceRequests[0].SpotInstanceRequestId' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null)

            if [ -n "$spot_request_id" ] && [ "$spot_request_id" != "None" ]; then
                local instance_id
                instance_id=$(wait_for_spot_fulfillment "$spot_request_id" "$stack_name" 120)
                
                if [ $? -eq 0 ]; then
                    success "Fallback spot launch successful in $az"
                    echo "$instance_id"
                    return 0
                fi
                
                # Cancel failed request
                aws ec2 cancel-spot-instance-requests \
                    --spot-instance-request-ids "$spot_request_id" \
                    --region "$AWS_REGION" > /dev/null
            fi
        fi
    done

    # Strategy 2: Try lower instance types
    warning "Trying alternative instance types for spot launch..."
    
    local alternative_types=()
    case "$instance_type" in
        "g4dn.2xlarge")
            alternative_types=("g4dn.xlarge" "g4dn.large")
            ;;
        "g4dn.xlarge")
            alternative_types=("g4dn.large")
            ;;
        "g5.xlarge")
            alternative_types=("g4dn.xlarge" "g4dn.large")
            ;;
    esac

    for alt_type in "${alternative_types[@]}"; do
        log "Trying alternative instance type: $alt_type"
        
        local optimal_config
        optimal_config=$(get_optimal_spot_configuration "$alt_type" "$max_price" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            local target_az="${optimal_config%:*}"
            local bid_price="${optimal_config#*:}"
            
            # Get subnet for target AZ
            local target_subnet_id
            target_subnet_id=$(aws ec2 describe-subnets \
                --filters "Name=availability-zone,Values=$target_az" "Name=state,Values=available" \
                --query 'Subnets[0].SubnetId' \
                --output text \
                --region "$AWS_REGION")

            if [ "$target_subnet_id" != "None" ] && [ -n "$target_subnet_id" ]; then
                local instance_id
                instance_id=$(launch_spot_instance_with_failover "$stack_name" "$alt_type" "$bid_price" "$user_data" "$security_group_id" "$target_subnet_id" "$key_name" "$iam_instance_profile")
                
                if [ $? -eq 0 ]; then
                    warning "Successfully launched alternative instance type: $alt_type"
                    echo "$instance_id"
                    return 0
                fi
            fi
        fi
    done

    error "All fallback strategies failed"
    return 1
}

# =============================================================================
# SPOT INSTANCE MONITORING
# =============================================================================

monitor_spot_instance_interruption() {
    local instance_id="$1"
    local notification_topic="$2"
    
    if [ -z "$instance_id" ]; then
        error "monitor_spot_instance_interruption requires instance_id parameter"
        return 1
    fi

    log "Setting up spot instance interruption monitoring for: $instance_id"

    # Create CloudWatch alarm for spot interruption
    local alarm_name="spot-interruption-${instance_id}"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "Monitor spot instance interruption for $instance_id" \
        --metric-name "StatusCheckFailed_Instance" \
        --namespace "AWS/EC2" \
        --statistic "Maximum" \
        --period 60 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --evaluation-periods 1 \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --region "$AWS_REGION"

    if [ -n "$notification_topic" ]; then
        aws cloudwatch put-metric-alarm \
            --alarm-name "$alarm_name" \
            --alarm-actions "$notification_topic" \
            --region "$AWS_REGION"
    fi

    success "Spot instance monitoring configured"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

get_nvidia_optimized_ami() {
    local region="$1"
    
    # Get the latest NVIDIA-optimized AMI
    local ami_id
    ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=Deep Learning AMI GPU TensorFlow*Ubuntu*" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$region" 2>/dev/null)

    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        # Fallback to Ubuntu 22.04 LTS
        ami_id=$(aws ec2 describe-images \
            --owners 099720109477 \
            --filters \
                "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
                "Name=state,Values=available" \
            --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
            --output text \
            --region "$region")
    fi

    echo "$ami_id"
    return 0
}

calculate_spot_savings() {
    local spot_price="$1"
    local instance_type="$2"
    local hours="${3:-24}"
    
    if [ -z "$spot_price" ] || [ -z "$instance_type" ]; then
        error "calculate_spot_savings requires spot_price and instance_type parameters"
        return 1
    fi

    # Get on-demand price (simplified lookup)
    local ondemand_price
    case "$instance_type" in
        "g4dn.xlarge")
            ondemand_price="0.526"
            ;;
        "g4dn.2xlarge")
            ondemand_price="0.752"
            ;;
        "g5.xlarge")
            ondemand_price="1.006"
            ;;
        *)
            warning "On-demand price not available for $instance_type"
            return 1
            ;;
    esac

    local spot_cost
    spot_cost=$(echo "$spot_price * $hours" | bc -l)
    
    local ondemand_cost
    ondemand_cost=$(echo "$ondemand_price * $hours" | bc -l)
    
    local savings
    savings=$(echo "$ondemand_cost - $spot_cost" | bc -l)
    
    local savings_percentage
    savings_percentage=$(echo "scale=1; ($savings / $ondemand_cost) * 100" | bc -l)

    info "=== Spot Instance Cost Analysis ==="
    info "Instance Type: $instance_type"
    info "Duration: ${hours} hours"
    info "Spot Cost: \$${spot_cost}"
    info "On-Demand Cost: \$${ondemand_cost}"
    info "Savings: \$${savings} (${savings_percentage}%)"
    
    return 0
}