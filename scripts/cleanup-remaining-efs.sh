#!/bin/bash
# Quick script to delete remaining EFS file systems

set -e

echo "🗑️  Deleting remaining EFS file systems..."

# List of EFS IDs from the image that need to be deleted
EFS_IDS=(
    "fs-0701aea2ef303ec54"  # 30-efs
    "fs-0527a214f25554fe1"  # 31-efs
    "fs-00b96e104a3758722"  # 33-efs
    "fs-031043fb45a2e376d"  # 34-efs
    "fs-0e203dfabd1945ca3"  # 35-efs
    "fs-0e713d7f70c5c28e5"  # 051-efs
    "fs-016b6b42fe4e1251d"  # 052-efs
    "fs-0df0329ff5634843b"  # test-cached-pricing-efs
)

for efs_id in "${EFS_IDS[@]}"; do
    echo "Deleting EFS: $efs_id"
    
    # Check if EFS exists
    if aws efs describe-file-systems --file-system-ids "$efs_id" &>/dev/null; then
        # Delete mount targets first
        mount_targets=$(aws efs describe-mount-targets --file-system-id "$efs_id" --query 'MountTargets[].MountTargetId' --output text 2>/dev/null || echo "")
        
        if [ -n "$mount_targets" ]; then
            echo "  Deleting mount targets..."
            for mt_id in $mount_targets; do
                aws efs delete-mount-target --mount-target-id "$mt_id" || true
                echo "    Deleted mount target: $mt_id"
            done
            echo "  Waiting for mount targets to be deleted..."
            sleep 10
        fi
        
        # Delete the EFS file system
        aws efs delete-file-system --file-system-id "$efs_id" || true
        echo "  ✅ Deleted EFS: $efs_id"
    else
        echo "  ⚠️  EFS $efs_id does not exist or already deleted"
    fi
done

echo "✅ EFS cleanup completed!" 