#!/bin/bash
# Direct EFS deletion script

set -euo pipefail

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

# EFS file systems to delete
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

echo "🚀 Starting direct EFS deletion..."

# Show current EFS file systems
echo "Current EFS file systems:"
aws efs describe-file-systems \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'FileSystems[].{ID:FileSystemId,Name:Name,State:LifeCycleState}' \
    --output table

echo
echo "⚠️  WARNING: This will permanently delete the following EFS file systems:"
for fs_id in "${EFS_FILE_SYSTEMS[@]}"; do
    echo "  - $fs_id"
done
echo
echo "This action cannot be undone!"
echo
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Deletion cancelled by user"
    exit 0
fi

# Delete each EFS file system
for fs_id in "${EFS_FILE_SYSTEMS[@]}"; do
    echo "Deleting EFS file system $fs_id..."
    
    # Get mount targets
    mount_targets=$(aws efs describe-mount-targets \
        --file-system-id "$fs_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'MountTargets[].MountTargetId' \
        --output text 2>/dev/null || echo "")
    
    # Delete mount targets first
    if [ -n "$mount_targets" ]; then
        echo "  Deleting mount targets: $mount_targets"
        for mount_target in $mount_targets; do
            aws efs delete-mount-target \
                --mount-target-id "$mount_target" \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE" || echo "  Failed to delete mount target $mount_target"
        done
        
        # Wait for mount targets to be deleted
        echo "  Waiting for mount targets to be deleted..."
        sleep 30
    fi
    
    # Delete the file system
    aws efs delete-file-system \
        --file-system-id "$fs_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" && echo "  ✅ Successfully deleted EFS file system $fs_id" || echo "  ❌ Failed to delete EFS file system $fs_id"
done

echo
echo "🎉 EFS deletion completed!"
echo
echo "Remaining EFS file systems:"
aws efs describe-file-systems \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'FileSystems[].{ID:FileSystemId,Name:Name,State:LifeCycleState}' \
    --output table 