#!/bin/bash
# =============================================================================
# ALB Health Check Configuration Fix
# Fixes ALB health check timeouts and configuration issues
# =============================================================================

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]; then
    source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
fi

# =============================================================================
# ALB HEALTH CHECK CONFIGURATION
# =============================================================================

# Optimized health check settings for containerized applications (bash 3.x compatible)
get_alb_health_check_config() {
    case "$1" in
        "HEALTH_CHECK_TIMEOUT_SECONDS") echo "15" ;;        # Increased from 5s to 15s
        "HEALTH_CHECK_INTERVAL_SECONDS") echo "60" ;;       # Increased from 30s to 60s
        "HEALTHY_THRESHOLD_COUNT") echo "2" ;;              # Keep at 2 for quick recovery
        "UNHEALTHY_THRESHOLD_COUNT") echo "5" ;;            # Increased from 3 to 5
        "DEREGISTRATION_DELAY_TIMEOUT_SECONDS") echo "60" ;; # Time to drain connections
        "LOAD_BALANCING_CROSS_ZONE_ENABLED") echo "true" ;; # Better distribution
        "HEALTH_CHECK_GRACE_PERIOD_SECONDS") echo "300" ;;  # 5 minutes for initial health checks
        "PRESERVE_CLIENT_IP_ENABLED") echo "true" ;;        # Preserve client IP for logging
        *) echo "" ;;
    esac
}

# Service-specific health check endpoints and settings (bash 3.x compatible)
get_service_health_endpoint() {
    case "$1" in
        "n8n") echo "/healthz" ;;
        "ollama") echo "/api/tags" ;;
        "qdrant") echo "/health" ;;
        "crawl4ai") echo "/health" ;;
        "default") echo "/health" ;;
        *) echo "/health" ;;
    esac
}

get_service_health_port() {
    case "$1" in
        "n8n") echo "5678" ;;
        "ollama") echo "11434" ;;
        "qdrant") echo "6333" ;;
        "crawl4ai") echo "11235" ;;
        "default") echo "80" ;;
        *) echo "80" ;;
    esac
}

get_service_startup_time() {
    case "$1" in
        "n8n") echo "180" ;;      # 3 minutes for n8n to start
        "ollama") echo "300" ;;   # 5 minutes for ollama and model loading
        "qdrant") echo "120" ;;   # 2 minutes for qdrant
        "crawl4ai") echo "180" ;; # 3 minutes for crawl4ai
        "default") echo "120" ;;  # 2 minutes default
        *) echo "120" ;;
    esac
}

# =============================================================================
# HEALTH CHECK VALIDATION AND IMPROVEMENT FUNCTIONS
# =============================================================================

# Get improved health check settings for a service
get_health_check_settings() {
    local service_name="${1:-default}"
    local environment="${2:-development}"
    
    local timeout_seconds="$(get_alb_health_check_config "HEALTH_CHECK_TIMEOUT_SECONDS")"
    local interval_seconds="$(get_alb_health_check_config "HEALTH_CHECK_INTERVAL_SECONDS")"
    local healthy_threshold="$(get_alb_health_check_config "HEALTHY_THRESHOLD_COUNT")"
    local unhealthy_threshold="$(get_alb_health_check_config "UNHEALTHY_THRESHOLD_COUNT")"
    local grace_period="$(get_service_startup_time "$service_name")"
    [ -z "$grace_period" ] && grace_period="$(get_service_startup_time "default")"
    
    # Adjust settings based on environment
    case "$environment" in
        "production")
            # Stricter settings for production
            healthy_threshold="3"
            unhealthy_threshold="3"
            ;;
        "development")
            # More lenient settings for development
            timeout_seconds="20"
            interval_seconds="90"
            unhealthy_threshold="8"
            grace_period=$((grace_period + 120))  # Extra 2 minutes for dev
            ;;
        "staging")
            # Balanced settings for staging
            timeout_seconds="18"
            interval_seconds="75"
            unhealthy_threshold="6"
            ;;
    esac
    
    # Return settings as space-separated values
    echo "$timeout_seconds $interval_seconds $healthy_threshold $unhealthy_threshold $grace_period"
}

# Create or update target group with improved health check settings
create_improved_target_group() {
    local tg_name="$1"
    local port="$2"
    local vpc_id="$3"
    local stack_name="$4"
    local service_name="${5:-default}"
    local environment="${6:-development}"
    
    local health_check_path="$(get_service_health_endpoint "$service_name")"
    [ -z "$health_check_path" ] && health_check_path="$(get_service_health_endpoint "default")"
    local health_check_port="$(get_service_health_port "$service_name")"
    [ -z "$health_check_port" ] && health_check_port="$port"
    
    # Get optimized health check settings
    local settings
    settings=$(get_health_check_settings "$service_name" "$environment")
    read -r timeout_seconds interval_seconds healthy_threshold unhealthy_threshold grace_period <<< "$settings"
    
    log "Creating target group with improved health check settings:"
    log "  Service: $service_name"
    log "  Health check path: $health_check_path"
    log "  Health check port: $health_check_port"
    log "  Timeout: ${timeout_seconds}s"
    log "  Interval: ${interval_seconds}s"
    log "  Healthy threshold: $healthy_threshold"
    log "  Unhealthy threshold: $unhealthy_threshold"
    log "  Grace period: ${grace_period}s"
    
    # Check if target group already exists
    local existing_tg_arn
    existing_tg_arn=$(aws elbv2 describe-target-groups \
        --names "$tg_name" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [ "$existing_tg_arn" != "None" ] && [ -n "$existing_tg_arn" ]; then
        log "Target group $tg_name already exists, updating health check settings..."
        
        # Update existing target group health check settings
        aws elbv2 modify-target-group \
            --target-group-arn "$existing_tg_arn" \
            --health-check-protocol HTTP \
            --health-check-path "$health_check_path" \
            --health-check-port "$health_check_port" \
            --health-check-interval-seconds "$interval_seconds" \
            --health-check-timeout-seconds "$timeout_seconds" \
            --healthy-threshold-count "$healthy_threshold" \
            --unhealthy-threshold-count "$unhealthy_threshold" \
            --region "$AWS_REGION" >/dev/null
        
        success "Updated target group health check settings: $tg_name"
        echo "$existing_tg_arn"
        return 0
    fi
    
    # Create new target group with improved settings
    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "$tg_name" \
        --protocol HTTP \
        --port "$port" \
        --vpc-id "$vpc_id" \
        --health-check-protocol HTTP \
        --health-check-path "$health_check_path" \
        --health-check-port "$health_check_port" \
        --health-check-interval-seconds "$interval_seconds" \
        --health-check-timeout-seconds "$timeout_seconds" \
        --healthy-threshold-count "$healthy_threshold" \
        --unhealthy-threshold-count "$unhealthy_threshold" \
        --target-type instance \
        --tags Key=Name,Value="$tg_name" Key=Stack,Value="$stack_name" Key=Service,Value="$service_name" Key=Environment,Value="$environment" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION")
    
    if [ -z "$tg_arn" ] || [ "$tg_arn" = "None" ]; then
        error "Failed to create target group: $tg_name"
        return 1
    fi
    
    # Configure additional target group attributes
    aws elbv2 modify-target-group-attributes \
        --target-group-arn "$tg_arn" \
        --attributes \
            Key=deregistration_delay.timeout_seconds,Value="$(get_alb_health_check_config "DEREGISTRATION_DELAY_TIMEOUT_SECONDS")" \
            Key=load_balancing.cross_zone.enabled,Value="$(get_alb_health_check_config "LOAD_BALANCING_CROSS_ZONE_ENABLED")" \
            Key=preserve_client_ip.enabled,Value="$(get_alb_health_check_config "PRESERVE_CLIENT_IP_ENABLED")" \
        --region "$AWS_REGION" >/dev/null
    
    success "Created target group with improved health check settings: $tg_name"
    echo "$tg_arn"
    return 0
}

# Fix existing target groups
fix_existing_target_groups() {
    local stack_name="${1:-}"
    local environment="${2:-development}"
    
    if [ -z "$stack_name" ]; then
        error "Stack name is required"
        return 1
    fi
    
    log "Finding and fixing existing target groups for stack: $stack_name"
    
    # Get all target groups for this stack
    local target_groups
    target_groups=$(aws elbv2 describe-target-groups \
        --query "TargetGroups[?contains(Tags[?Key=='Stack'].Value, '$stack_name')].{Name:TargetGroupName,Arn:TargetGroupArn}" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -z "$target_groups" ]; then
        warning "No target groups found for stack: $stack_name"
        return 0
    fi
    
    # Process each target group
    echo "$target_groups" | while IFS=$'\t' read -r tg_name tg_arn; do
        if [ -n "$tg_name" ] && [ -n "$tg_arn" ]; then
            log "Fixing target group: $tg_name"
            
            # Determine service name from target group name
            local service_name="default"
            for service in n8n ollama qdrant crawl4ai; do
                if [[ "$tg_name" =~ $service ]]; then
                    service_name="$service"
                    break
                fi
            done
            
            # Get optimized settings
            local settings
            settings=$(get_health_check_settings "$service_name" "$environment")
            read -r timeout_seconds interval_seconds healthy_threshold unhealthy_threshold grace_period <<< "$settings"
            
            local health_check_path="$(get_service_health_endpoint "$service_name")"
            [ -z "$health_check_path" ] && health_check_path="$(get_service_health_endpoint "default")"
            local health_check_port="$(get_service_health_port "$service_name")"
            [ -z "$health_check_port" ] && health_check_port="80"
            
            # Update the target group
            if aws elbv2 modify-target-group \
                --target-group-arn "$tg_arn" \
                --health-check-protocol HTTP \
                --health-check-path "$health_check_path" \
                --health-check-port "$health_check_port" \
                --health-check-interval-seconds "$interval_seconds" \
                --health-check-timeout-seconds "$timeout_seconds" \
                --healthy-threshold-count "$healthy_threshold" \
                --unhealthy-threshold-count "$unhealthy_threshold" \
                --region "$AWS_REGION" >/dev/null 2>&1; then
                
                success "Fixed health check settings for: $tg_name"
            else
                error "Failed to update health check settings for: $tg_name"
            fi
        fi
    done
}

# Validate health check configuration
validate_health_check_config() {
    local tg_arn="$1"
    local expected_service="${2:-default}"
    
    log "Validating health check configuration for target group..."
    
    # Get current health check settings
    local health_check_info
    health_check_info=$(aws elbv2 describe-target-groups \
        --target-group-arns "$tg_arn" \
        --query 'TargetGroups[0].{Path:HealthCheckPath,Port:HealthCheckPort,Protocol:HealthCheckProtocol,Timeout:HealthCheckTimeoutSeconds,Interval:HealthCheckIntervalSeconds,Healthy:HealthyThresholdCount,Unhealthy:UnhealthyThresholdCount}' \
        --output json \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ -z "$health_check_info" ]; then
        error "Failed to get health check information"
        return 1
    fi
    
    # Parse the information
    local path=$(echo "$health_check_info" | jq -r '.Path')
    local port=$(echo "$health_check_info" | jq -r '.Port')
    local protocol=$(echo "$health_check_info" | jq -r '.Protocol')
    local timeout=$(echo "$health_check_info" | jq -r '.Timeout')
    local interval=$(echo "$health_check_info" | jq -r '.Interval')
    local healthy=$(echo "$health_check_info" | jq -r '.Healthy')
    local unhealthy=$(echo "$health_check_info" | jq -r '.Unhealthy')
    
    log "Current health check configuration:"
    log "  Path: $path"
    log "  Port: $port"
    log "  Protocol: $protocol"
    log "  Timeout: ${timeout}s"
    log "  Interval: ${interval}s"
    log "  Healthy threshold: $healthy"
    log "  Unhealthy threshold: $unhealthy"
    
    # Validate against recommended settings
    local issues=0
    
    if [ "$timeout" -lt 10 ]; then
        warning "Health check timeout is too low: ${timeout}s (recommended: 15s+)"
        issues=$((issues + 1))
    fi
    
    if [ "$interval" -lt 45 ]; then
        warning "Health check interval is too frequent: ${interval}s (recommended: 60s+)"
        issues=$((issues + 1))
    fi
    
    if [ "$unhealthy" -lt 4 ]; then
        warning "Unhealthy threshold is too strict: $unhealthy (recommended: 5+)"
        issues=$((issues + 1))
    fi
    
    if [ "$protocol" != "HTTP" ]; then
        warning "Health check protocol should be HTTP for containerized apps: $protocol"
        issues=$((issues + 1))
    fi
    
    # Check if path matches expected service
    local expected_path="$(get_service_health_endpoint "$expected_service")"
    [ -z "$expected_path" ] && expected_path="$(get_service_health_endpoint "default")"
    if [ "$path" != "$expected_path" ]; then
        warning "Health check path may not be optimal for $expected_service: $path (recommended: $expected_path)"
        issues=$((issues + 1))
    fi
    
    if [ $issues -eq 0 ]; then
        success "Health check configuration looks good"
        return 0
    else
        warning "Found $issues potential issues with health check configuration"
        return 1
    fi
}

# Create health check monitoring script
create_health_check_monitor() {
    local output_file="${1:-$PROJECT_ROOT/scripts/monitor-health-checks.sh}"
    
    log "Creating health check monitoring script: $output_file"
    
    cat > "$output_file" << 'EOF'
#!/bin/bash
# Health Check Monitoring Script
# Monitors ALB target group health and provides troubleshooting information

set -euo pipefail

# Get all target groups and their health status
monitor_target_groups() {
    local stack_name="${1:-}"
    
    if [ -n "$stack_name" ]; then
        echo "Monitoring target groups for stack: $stack_name"
        aws elbv2 describe-target-groups \
            --query "TargetGroups[?contains(Tags[?Key=='Stack'].Value, '$stack_name')].[TargetGroupName,TargetGroupArn]" \
            --output text
    else
        echo "Monitoring all target groups:"
        aws elbv2 describe-target-groups \
            --query 'TargetGroups[].[TargetGroupName,TargetGroupArn]' \
            --output text
    fi | while IFS=$'\t' read -r tg_name tg_arn; do
        if [ -n "$tg_name" ] && [ -n "$tg_arn" ]; then
            echo
            echo "Target Group: $tg_name"
            echo "ARN: $tg_arn"
            
            # Get target health
            local health_status
            health_status=$(aws elbv2 describe-target-health \
                --target-group-arn "$tg_arn" \
                --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
                --output text 2>/dev/null || echo "No targets")
            
            if [ "$health_status" != "No targets" ]; then
                echo "Target Health:"
                echo "$health_status" | while IFS=$'\t' read -r target_id state reason description; do
                    echo "  Target: $target_id"
                    echo "    State: $state"
                    echo "    Reason: $reason"
                    echo "    Description: $description"
                done
            else
                echo "  No targets registered"
            fi
            
            # Get health check configuration
            echo "Health Check Configuration:"
            aws elbv2 describe-target-groups \
                --target-group-arns "$tg_arn" \
                --query 'TargetGroups[0].{Path:HealthCheckPath,Port:HealthCheckPort,Timeout:HealthCheckTimeoutSeconds,Interval:HealthCheckIntervalSeconds,Healthy:HealthyThresholdCount,Unhealthy:UnhealthyThresholdCount}' \
                --output table
            
            echo "----------------------------------------"
        fi
    done
}

# Main execution
if [ $# -eq 0 ]; then
    monitor_target_groups
else
    monitor_target_groups "$1"
fi
EOF
    
    chmod +x "$output_file"
    success "Created health check monitoring script: $output_file"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
ALB Health Check Configuration Fix Script

USAGE:
    $0 <command> [options]

COMMANDS:
    fix <stack-name> [environment]    Fix health check settings for existing target groups
    create <tg-name> <port> <vpc-id> <stack-name> [service] [environment]    Create target group with improved settings
    validate <target-group-arn> [service]    Validate health check configuration
    monitor [stack-name]              Create health check monitoring script
    show-config [service] [environment]    Show recommended health check settings
    help                              Show this help message

EXAMPLES:
    $0 fix my-stack development       # Fix health checks for development stack
    $0 create my-tg 80 vpc-123 my-stack n8n production    # Create target group for n8n
    $0 validate arn:aws:elbv2:...     # Validate target group health check config
    $0 monitor my-stack               # Create monitoring script for stack
    $0 show-config ollama production  # Show recommended settings for ollama in production

SUPPORTED SERVICES:
    n8n, ollama, qdrant, crawl4ai, default

ENVIRONMENTS:
    development, staging, production

EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    local command="${1:-help}"
    
    case "$command" in
        "fix")
            local stack_name="${2:-}"
            local environment="${3:-development}"
            if [ -z "$stack_name" ]; then
                error "Stack name is required for fix command"
                show_help
                exit 1
            fi
            fix_existing_target_groups "$stack_name" "$environment"
            ;;
        "create")
            local tg_name="${2:-}"
            local port="${3:-}"
            local vpc_id="${4:-}"
            local stack_name="${5:-}"
            local service="${6:-default}"
            local environment="${7:-development}"
            if [ -z "$tg_name" ] || [ -z "$port" ] || [ -z "$vpc_id" ] || [ -z "$stack_name" ]; then
                error "Missing required parameters for create command"
                show_help
                exit 1
            fi
            create_improved_target_group "$tg_name" "$port" "$vpc_id" "$stack_name" "$service" "$environment"
            ;;
        "validate")
            local tg_arn="${2:-}"
            local service="${3:-default}"
            if [ -z "$tg_arn" ]; then
                error "Target group ARN is required for validate command"
                show_help
                exit 1
            fi
            validate_health_check_config "$tg_arn" "$service"
            ;;
        "monitor")
            local stack_name="${2:-}"
            create_health_check_monitor
            if [ -n "$stack_name" ]; then
                log "To monitor your stack, run: ./scripts/monitor-health-checks.sh $stack_name"
            else
                log "To monitor all target groups, run: ./scripts/monitor-health-checks.sh"
            fi
            ;;
        "show-config")
            local service="${2:-default}"
            local environment="${3:-development}"
            log "Recommended health check settings for $service in $environment:"
            local settings
            settings=$(get_health_check_settings "$service" "$environment")
            read -r timeout interval healthy unhealthy grace <<< "$settings"
            echo "  Timeout: ${timeout}s"
            echo "  Interval: ${interval}s"
            echo "  Healthy threshold: $healthy"
            echo "  Unhealthy threshold: $unhealthy"
            echo "  Grace period: ${grace}s"
            local health_path="$(get_service_health_endpoint "$service")"
            [ -z "$health_path" ] && health_path="$(get_service_health_endpoint "default")"
            local health_port="$(get_service_health_port "$service")"
            [ -z "$health_port" ] && health_port="80"
            echo "  Health check path: $health_path"
            echo "  Health check port: $health_port"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi