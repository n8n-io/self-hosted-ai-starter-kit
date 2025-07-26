#!/bin/bash
# =============================================================================
# Delete Failed EFS File Systems
# Script to safely delete EFS file systems from failed deployments
# =============================================================================

set -euo pipefail

# Source common libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/lib/error-handling.sh"
source "$PROJECT_ROOT/lib/aws-config.sh"

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

# EFS file systems to delete (from the image)
EFS_FILE_SYSTEMS=(
    "fs-0e713d7f70c5c28e5"  # 051-efs
    "fs-016b6b42fe4e1251d"  # 052-efs
    "fs-081412d661c7359b6"  # 053-efs
    "fs-08b9502f5bcb7db98"  # 054-efs
    "fs-043c227f27b0a57c5"  # 055-efs
    "fs-0e50ce2a955e271a1"  # 056-efs
    "fs-09b78c8e0b3439f73"  # 057-efs
    "fs-05e2980141f1c4cf5"  # 058-efs
    "fs-0cb64b1f87cbda05f"  # 059-efs
)

# Simple logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error logging function
error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Function to check if EFS file system exists
check_efs_exists() {
    local fs_id="$1"
    
    if aws efs describe-file-systems \
        --file-system-ids "$fs_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'FileSystems[0].FileSystemId' \
        --output text 2>/dev/null | grep -q "$fs_id"; then
        return 0
    else
        return 1
    fi
}

# Function to get EFS mount targets
get_mount_targets() {
    local fs_id="$1"
    
    aws efs describe-mount-targets \
        --file-system-id "$fs_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'MountTargets[].MountTargetId' \
        --output text 2>/dev/null || echo ""
}

# Function to delete mount targets
delete_mount_targets() {
    local fs_id="$1"
    local mount_targets
    
    log "Getting mount targets for EFS $fs_id..."
    mount_targets=$(get_mount_targets "$fs_id")
    
    if [ -n "$mount_targets" ]; then
        for mount_target in $mount_targets; do
            log "Deleting mount target $mount_target..."
            aws efs delete-mount-target \
                --mount-target-id "$mount_target" \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE" || {
                error "Failed to delete mount target $mount_target"
                return 1
            }
        done
        
        # Wait for mount targets to be deleted
        log "Waiting for mount targets to be deleted..."
        sleep 30
    else
        log "No mount targets found for EFS $fs_id"
    fi
}

# Function to delete EFS file system
delete_efs_file_system() {
    local fs_id="$1"
    
    log "Deleting EFS file system $fs_id..."
    
    # First delete mount targets
    delete_mount_targets "$fs_id"
    
    # Then delete the file system
    aws efs delete-file-system \
        --file-system-id "$fs_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" || {
        error "Failed to delete EFS file system $fs_id"
        return 1
    }
    
    log "✅ Successfully deleted EFS file system $fs_id"
}

# Function to list all EFS file systems
list_all_efs() {
    log "Listing all EFS file systems in region $AWS_REGION..."
    
    aws efs describe-file-systems \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'FileSystems[].{ID:FileSystemId,Name:Name,State:LifeCycleState,Size:SizeInBytes.Value}' \
        --output table
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    
    if ! aws sts get-caller-identity \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        error "Invalid AWS credentials or profile '$AWS_PROFILE' not found"
        return 1
    fi
    
    local account_id=$(aws sts get-caller-identity \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Account' \
        --output text)
    
    log "✅ AWS credentials validated for account: $account_id"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    echo "⚠️  WARNING: This will permanently delete the following EFS file systems:"
    echo
    for fs_id in "${EFS_FILE_SYSTEMS[@]}"; do
        echo "  - $fs_id"
    done
    echo
    echo "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Function to check for existing EFS file systems
check_existing_efs() {
    local existing_count=0
    
    log "Checking for existing EFS file systems..."
    
    for fs_id in "${EFS_FILE_SYSTEMS[@]}"; do
        if check_efs_exists "$fs_id"; then
            log "Found existing EFS file system: $fs_id"
            ((existing_count++))
        else
            log "EFS file system $fs_id does not exist or has already been deleted"
        fi
    done
    
    if [ "$existing_count" -eq 0 ]; then
        log "No existing EFS file systems found to delete"
        return 1
    fi
    
    log "Found $existing_count EFS file system(s) to delete"
    return 0
}

# Main function
main() {
    log "🚀 Starting EFS cleanup process..."
    
    # Validate AWS credentials
    validate_aws_credentials
    
    # Check for existing EFS file systems
    if ! check_existing_efs; then
        log "No EFS file systems to delete"
        exit 0
    fi
    
    # Show current EFS file systems
    echo
    log "Current EFS file systems:"
    list_all_efs
    
    # Confirm deletion
    confirm_deletion
    
    # Delete each EFS file system
    local success_count=0
    local failure_count=0
    
    for fs_id in "${EFS_FILE_SYSTEMS[@]}"; do
        if check_efs_exists "$fs_id"; then
            if delete_efs_file_system "$fs_id"; then
                ((success_count++))
            else
                ((failure_count++))
            fi
        else
            log "Skipping $fs_id - already deleted or does not exist"
        fi
    done
    
    # Summary
    echo
    log "🎉 EFS cleanup completed!"
    log "Successfully deleted: $success_count file system(s)"
    if [ "$failure_count" -gt 0 ]; then
        log "Failed to delete: $failure_count file system(s)"
    fi
    
    # Show remaining EFS file systems
    echo
    log "Remaining EFS file systems:"
    list_all_efs
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 