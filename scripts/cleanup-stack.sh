#!/bin/bash
# Quick cleanup script for AWS resources
set -e

STACK_NAME="${1:-001}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source required libraries
source "$LIB_DIR/error-handling.sh"
source "$LIB_DIR/aws-deployment-common.sh"
source "$LIB_DIR/aws-config.sh"

# Set AWS region if not already set
export AWS_REGION="${AWS_REGION:-us-east-1}"

log() { echo -e "\033[0;34m[$(date +'%Y-%m-%d %H:%M:%S')] $1\033[0m" >&2; }
error() { echo -e "\033[0;31m[ERROR] $1\033[0m" >&2; }
success() { echo -e "\033[0;32m✅ [SUCCESS] $1\033[0m" >&2; }
warning() { echo -e "\033[0;33m[WARNING] $1\033[0m" >&2; }

echo "=============================================="
echo "🗑️  AWS Resource Cleanup for Stack: $STACK_NAME"
echo "=============================================="

# Cleanup instances first (most important)
log "Cleaning up EC2 instances..."
cleanup_instances "$STACK_NAME"

# Cleanup security groups
log "Cleaning up security groups..."
cleanup_security_groups "$STACK_NAME"

# Cleanup key pairs
log "Cleaning up key pairs..."
cleanup_key_pairs "$STACK_NAME"

# Cleanup spot instance requests first
log "Cleaning up spot instance requests..."
aws ec2 describe-spot-instance-requests \
    --filters "Name=tag:Stack,Values=${STACK_NAME}" "Name=state,Values=open,active" \
    --query 'SpotInstanceRequests[].SpotInstanceRequestId' \
    --output text | tr '\t' '\n' | while read -r spot_id; do
    if [ -n "$spot_id" ] && [ "$spot_id" != "None" ]; then
        aws ec2 cancel-spot-instance-requests --spot-instance-request-ids "$spot_id" --region "$AWS_REGION" || true
        log "Cancelled spot instance request: $spot_id"
    fi
done

# Manual cleanup for resources that don't have functions yet
log "Cleaning up additional resources manually..."

# Cleanup CloudFront distributions
log "Cleaning up CloudFront distributions..."
distributions=$(aws cloudfront list-distributions --output json 2>/dev/null || echo '{"DistributionList":{"Items":[]}}')
if [ "$distributions" != '{"DistributionList":{"Items":[]}}' ]; then
    echo "$distributions" | jq -r ".DistributionList.Items[]? | select(.Comment // \"\" | contains(\"${STACK_NAME}\")) | .Id" 2>/dev/null | while read -r dist_id; do
        if [ -n "$dist_id" ] && [ "$dist_id" != "null" ] && [ "$dist_id" != "None" ]; then
            # First disable the distribution
            config=$(aws cloudfront get-distribution-config --id "$dist_id" --query DistributionConfig --output json 2>/dev/null) || continue
            etag=$(aws cloudfront get-distribution-config --id "$dist_id" --query ETag --output text 2>/dev/null) || continue
            
            if [ -n "$config" ] && [ -n "$etag" ] && [ "$config" != "null" ] && [ "$etag" != "null" ]; then
                echo "$config" | jq '.Enabled = false' > "/tmp/disabled-config-${dist_id}.json" 2>/dev/null || continue
                aws cloudfront update-distribution \
                    --id "$dist_id" \
                    --distribution-config "file:///tmp/disabled-config-${dist_id}.json" \
                    --if-match "$etag" 2>/dev/null || true
                log "Disabled CloudFront distribution: $dist_id (deletion will occur after deployment completes)"
                rm -f "/tmp/disabled-config-${dist_id}.json"
            fi
        fi
    done
fi

# Cleanup ALB and Target Groups
log "Cleaning up Application Load Balancers..."
alb_list=$(aws elbv2 describe-load-balancers --output json 2>/dev/null || echo '{"LoadBalancers":[]}')
if [ "$alb_list" != '{"LoadBalancers":[]}' ]; then
    echo "$alb_list" | jq -r ".LoadBalancers[]? | select(.LoadBalancerName | contains(\"${STACK_NAME}\")) | .LoadBalancerArn" 2>/dev/null | while read -r alb_arn; do
        if [ -n "$alb_arn" ] && [ "$alb_arn" != "None" ] && [ "$alb_arn" != "null" ]; then
            # Delete associated target groups first
            tg_list=$(aws elbv2 describe-target-groups --load-balancer-arn "$alb_arn" --output json 2>/dev/null || echo '{"TargetGroups":[]}')
            if [ "$tg_list" != '{"TargetGroups":[]}' ]; then
                echo "$tg_list" | jq -r '.TargetGroups[]?.TargetGroupArn' 2>/dev/null | while read -r tg_arn; do
                    if [ -n "$tg_arn" ] && [ "$tg_arn" != "null" ]; then
                        aws elbv2 delete-target-group --target-group-arn "$tg_arn" --region "$AWS_REGION" || true
                        log "Deleted target group: $tg_arn"
                    fi
                done
            fi
            
            # Delete the ALB
            aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$AWS_REGION" || true
            log "Deleted ALB: $alb_arn"
        fi
    done
fi

# Cleanup CloudWatch alarms
log "Deleting CloudWatch alarms..."
aws cloudwatch describe-alarms --query "MetricAlarms[?starts_with(AlarmName, '${STACK_NAME}-')].AlarmName" --output text | tr '\t' '\n' | while read -r alarm_name; do
    if [ -n "$alarm_name" ]; then
        aws cloudwatch delete-alarms --alarm-names "$alarm_name" --region "$AWS_REGION" || true
        log "Deleted alarm: $alarm_name"
    fi
done

# Cleanup CloudWatch log groups
log "Deleting CloudWatch log groups..."
aws logs describe-log-groups --query "logGroups[?contains(logGroupName, '${STACK_NAME}')].logGroupName" --output text | tr '\t' '\n' | while read -r log_group; do
    if [ -n "$log_group" ]; then
        aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" || true
        log "Deleted log group: $log_group"
    fi
done

# Cleanup EFS (if any)
log "Cleaning up EFS resources..."
aws efs describe-file-systems --query "FileSystems[?Tags[?Key=='Name' && Value=='${STACK_NAME}-efs']].FileSystemId" --output text | while read -r efs_id; do
    if [ -n "$efs_id" ] && [ "$efs_id" != "None" ]; then
        # Delete mount targets first
        aws efs describe-mount-targets --file-system-id "$efs_id" --query 'MountTargets[].MountTargetId' --output text | tr '\t' '\n' | while read -r mt_id; do
            if [ -n "$mt_id" ]; then
                aws efs delete-mount-target --mount-target-id "$mt_id" --region "$AWS_REGION" || true
                log "Deleted mount target: $mt_id"
            fi
        done
        # Wait a bit for mount targets to be deleted
        sleep 10
        # Delete the file system
        aws efs delete-file-system --file-system-id "$efs_id" --region "$AWS_REGION" || true
        log "Deleted EFS: $efs_id"
    fi
done

# Cleanup IAM resources
log "Cleaning up IAM resources..."

# Get the profile name based on stack name
profile_name=""
if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then
    clean_name=$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')
    profile_name="app-${clean_name}-profile"
else
    profile_name="${STACK_NAME}-instance-profile"
fi

# Remove role from instance profile first
if aws iam get-instance-profile --instance-profile-name "$profile_name" &> /dev/null; then
    log "Removing roles from instance profile: $profile_name"
    aws iam get-instance-profile --instance-profile-name "$profile_name" \
        --query 'InstanceProfile.Roles[].RoleName' --output text | tr '\t' '\n' | while read -r role_name; do
        if [ -n "$role_name" ]; then
            aws iam remove-role-from-instance-profile \
                --instance-profile-name "$profile_name" \
                --role-name "$role_name" || true
            log "Removed role $role_name from instance profile"
        fi
    done
    
    # Delete instance profile
    aws iam delete-instance-profile --instance-profile-name "$profile_name" || true
    log "Deleted instance profile: $profile_name"
fi

# Delete IAM role
role_name="${STACK_NAME}-role"
if aws iam get-role --role-name "$role_name" &> /dev/null; then
    log "Cleaning up IAM role: $role_name"
    
    # Detach policies first
    aws iam list-attached-role-policies --role-name "$role_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text | tr '\t' '\n' | while read -r policy_arn; do
        if [ -n "$policy_arn" ]; then
            aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" || true
            log "Detached policy: $policy_arn"
        fi
    done
    
    # Delete the role
    aws iam delete-role --role-name "$role_name" || true
    log "Deleted IAM role: $role_name"
fi

# Additional cleanup for any remaining resources with stack tag
log "Final sweep: Cleaning up any remaining tagged resources..."

# Check for any remaining instances
remaining_instances=$(aws ec2 describe-instances \
    --filters "Name=tag:Stack,Values=${STACK_NAME}" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$remaining_instances" ] && [ "$remaining_instances" != "None" ]; then
    warning "Found remaining instances: $remaining_instances"
    for instance_id in $remaining_instances; do
        aws ec2 terminate-instances --instance-ids "$instance_id" --region "$AWS_REGION" || true
        log "Force terminated: $instance_id"
    done
fi

# Cleanup EFS access points (if any)
aws efs describe-access-points --query "AccessPoints[?Tags[?Key=='Stack' && Value=='${STACK_NAME}']].AccessPointId" --output text | tr '\t' '\n' | while read -r ap_id; do
    if [ -n "$ap_id" ] && [ "$ap_id" != "None" ]; then
        aws efs delete-access-point --access-point-id "$ap_id" --region "$AWS_REGION" || true
        log "Deleted EFS access point: $ap_id"
    fi
done

# Summary
success "Cleanup completed for stack: $STACK_NAME"
echo "=============================================="
echo "✅ All resources for stack '$STACK_NAME' have been cleaned up"
echo ""
echo "Note: CloudFront distributions require manual deletion after they are disabled."
echo "You can delete them from the AWS Console after 15-20 minutes."
echo "=============================================="