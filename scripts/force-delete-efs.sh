#!/bin/bash
# Force delete remaining EFS file systems

set -e

echo "🗑️  Force deleting remaining EFS file systems..."

# Remaining EFS IDs from the image
EFS_IDS=(
    "fs-031043fb45a2e376d"  # 34-efs
    "fs-0e203dfabd1945ca3"  # 35-efs
    "fs-0e713d7f70c5c28e5"  # 051-efs
    "fs-016b6b42fe4e1251d"  # 052-efs
    "fs-0df0329ff5634843b"  # test-cached-pricing-efs
)

for efs_id in "${EFS_IDS[@]}"; do
    echo "Processing EFS: $efs_id"
    
    # Check if EFS exists
    if aws efs describe-file-systems --file-system-ids "$efs_id" &>/dev/null; then
        # Get mount targets
        mount_targets=$(aws efs describe-mount-targets --file-system-id "$efs_id" --query 'MountTargets[].MountTargetId' --output text 2>/dev/null || echo "")
        
        if [ -n "$mount_targets" ]; then
            echo "  Found mount targets: $mount_targets"
            for mt_id in $mount_targets; do
                echo "    Deleting mount target: $mt_id"
                aws efs delete-mount-target --mount-target-id "$mt_id" || true
            done
            echo "  Waiting for mount targets to be deleted..."
            sleep 15
        fi
        
        # Delete the EFS file system
        echo "  Deleting EFS file system..."
        aws efs delete-file-system --file-system-id "$efs_id" || true
        echo "  ✅ Deleted EFS: $efs_id"
    else
        echo "  ⚠️  EFS $efs_id does not exist or already deleted"
    fi
done

echo "✅ Force EFS cleanup completed!" 