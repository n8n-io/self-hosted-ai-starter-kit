#!/bin/bash
# Quick cleanup script for AWS resources
set -e

STACK_NAME="${1:-001}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required libraries
source "$LIB_DIR/error-handling.sh"
source "$LIB_DIR/aws-deployment-common.sh"
source "$LIB_DIR/aws-config.sh"

# Set AWS region if not already set
export AWS_REGION="${AWS_REGION:-us-east-1}"

log() { echo -e "\033[0;34m[$(date +'%Y-%m-%d %H:%M:%S')] $1\033[0m" >&2; }
error() { echo -e "\033[0;31m[ERROR] $1\033[0m" >&2; }
success() { echo -e "\033[0;32m[SUCCESS] $1\033[0m" >&2; }
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

# Manual cleanup for resources that don't have functions yet
log "Cleaning up additional resources manually..."

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

success "Cleanup completed for stack: $STACK_NAME"
echo "=============================================="
echo "✅ All resources for stack '$STACK_NAME' have been cleaned up"
echo "=============================================="