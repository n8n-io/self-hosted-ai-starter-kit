#!/bin/bash
# Comprehensive EFS Cleanup Script
# Removes EFS file systems and all associated resources

set -e

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
info() { echo -e "\033[0;36mℹ️  [INFO] $1\033[0m" >&2; }

echo "=============================================="
echo "🗑️  EFS File System Cleanup"
echo "=============================================="

# Function to cleanup a single EFS file system
cleanup_efs_filesystem() {
    local efs_id="$1"
    local efs_name="$2"
    
    log "Cleaning up EFS: $efs_name ($efs_id)"
    
    # Check if EFS exists
    if ! aws efs describe-file-systems --file-system-ids "$efs_id" &>/dev/null; then
        warning "EFS $efs_id does not exist or is already deleted"
        return 0
    fi
    
    # Get mount targets
    local mount_targets
    mount_targets=$(aws efs describe-mount-targets \
        --file-system-id "$efs_id" \
        --query 'MountTargets[].MountTargetId' \
        --output text 2>/dev/null || echo "")
    
    # Delete mount targets first
    if [ -n "$mount_targets" ] && [ "$mount_targets" != "None" ]; then
        echo "$mount_targets" | tr '\t' '\n' | while read -r mt_id; do
            if [ -n "$mt_id" ] && [ "$mt_id" != "None" ]; then
                log "Deleting mount target: $mt_id"
                aws efs delete-mount-target --mount-target-id "$mt_id" --region "$AWS_REGION" || true
                success "Deleted mount target: $mt_id"
            fi
        done
        
        # Wait for mount targets to be fully deleted
        log "Waiting for mount targets to be fully deleted..."
        sleep 15
    fi
    
    # Delete access points
    local access_points
    access_points=$(aws efs describe-access-points \
        --file-system-id "$efs_id" \
        --query 'AccessPoints[].AccessPointId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$access_points" ] && [ "$access_points" != "None" ]; then
        echo "$access_points" | tr '\t' '\n' | while read -r ap_id; do
            if [ -n "$ap_id" ] && [ "$ap_id" != "None" ]; then
                log "Deleting access point: $ap_id"
                aws efs delete-access-point --access-point-id "$ap_id" --region "$AWS_REGION" || true
                success "Deleted access point: $ap_id"
            fi
        done
    fi
    
    # Delete the file system
    log "Deleting EFS file system: $efs_id"
    aws efs delete-file-system --file-system-id "$efs_id" --region "$AWS_REGION" || true
    success "Deleted EFS file system: $efs_name ($efs_id)"
}

# Function to cleanup EFS by name pattern
cleanup_efs_by_pattern() {
    local pattern="$1"
    
    log "Cleaning up EFS file systems matching pattern: $pattern"
    
    local efs_list
    efs_list=$(aws efs describe-file-systems \
        --query "FileSystems[?contains(Name, '$pattern')].{Name:Name,FileSystemId:FileSystemId}" \
        --output json 2>/dev/null || echo '[]')
    
    if [ "$efs_list" = "[]" ]; then
        info "No EFS file systems found matching pattern: $pattern"
        return 0
    fi
    
    echo "$efs_list" | jq -r '.[] | "\(.FileSystemId) \(.Name)"' | while read -r efs_id efs_name; do
        if [ -n "$efs_id" ] && [ -n "$efs_name" ]; then
            cleanup_efs_filesystem "$efs_id" "$efs_name"
        fi
    done
}

# Function to cleanup specific EFS file systems
cleanup_specific_efs() {
    local efs_ids=("$@")
    
    for efs_id in "${efs_ids[@]}"; do
        local efs_name
        efs_name=$(aws efs describe-file-systems \
            --file-system-ids "$efs_id" \
            --query 'FileSystems[0].Name' \
            --output text 2>/dev/null || echo "unknown")
        
        cleanup_efs_filesystem "$efs_id" "$efs_name"
    done
}

# Function to list all EFS file systems
list_all_efs() {
    log "Listing all EFS file systems:"
    aws efs describe-file-systems \
        --query 'FileSystems[].{Name:Name,FileSystemId:FileSystemId,CreationTime:CreationTime,State:LifeCycleState}' \
        --output table
}

# Main cleanup function
main_cleanup() {
    local action="$1"
    shift
    
    case "$action" in
        "list")
            list_all_efs
            ;;
        "pattern")
            if [ $# -eq 0 ]; then
                error "Please provide a pattern to match EFS names"
                exit 1
            fi
            cleanup_efs_by_pattern "$1"
            ;;
        "specific")
            if [ $# -eq 0 ]; then
                error "Please provide EFS IDs to delete"
                exit 1
            fi
            cleanup_specific_efs "$@"
            ;;
        "all")
            log "Cleaning up ALL EFS file systems (use with caution!)"
            local efs_list
            efs_list=$(aws efs describe-file-systems \
                --query 'FileSystems[].{Name:Name,FileSystemId:FileSystemId}' \
                --output json 2>/dev/null || echo '[]')
            
            echo "$efs_list" | jq -r '.[] | "\(.FileSystemId) \(.Name)"' | while read -r efs_id efs_name; do
                if [ -n "$efs_id" ] && [ -n "$efs_name" ]; then
                    cleanup_efs_filesystem "$efs_id" "$efs_name"
                fi
            done
            ;;
        "numbered")
            log "Cleaning up numbered EFS file systems (27-efs, 30-efs, 31-efs, 33-efs, 34-efs, 35-efs, 051-efs, 052-efs)"
            cleanup_efs_by_pattern "27-efs"
            cleanup_efs_by_pattern "30-efs"
            cleanup_efs_by_pattern "31-efs"
            cleanup_efs_by_pattern "33-efs"
            cleanup_efs_by_pattern "34-efs"
            cleanup_efs_by_pattern "35-efs"
            cleanup_efs_by_pattern "051-efs"
            cleanup_efs_by_pattern "052-efs"
            ;;
        *)
            echo "Usage: $0 {list|pattern <pattern>|specific <efs-id1> [efs-id2] ...|all|numbered}"
            echo ""
            echo "Commands:"
            echo "  list                    - List all EFS file systems"
            echo "  pattern <pattern>       - Cleanup EFS matching pattern (e.g., '27-efs')"
            echo "  specific <efs-id1> ...  - Cleanup specific EFS by ID"
            echo "  all                     - Cleanup ALL EFS file systems (use with caution!)"
            echo "  numbered                - Cleanup numbered EFS (27-efs through 052-efs)"
            echo ""
            echo "Examples:"
            echo "  $0 list"
            echo "  $0 pattern '27-efs'"
            echo "  $0 specific fs-0495b0b220620c153"
            echo "  $0 numbered"
            echo "  $0 all"
            exit 1
            ;;
    esac
}

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials are not configured or invalid"
    exit 1
fi

# Run main cleanup
main_cleanup "$@"

success "EFS cleanup completed!"
echo "==============================================" 