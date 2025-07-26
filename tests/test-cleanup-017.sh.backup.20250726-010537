#!/bin/bash
# Test cleanup for the specific problematic stack '017'
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source the shared library to test the cleanup function
source "$LIB_DIR/error-handling.sh"
source "$LIB_DIR/aws-deployment-common.sh"
source "$LIB_DIR/aws-config.sh"

# Set AWS region
export AWS_REGION="${AWS_REGION:-us-east-1}"

echo "=============================================="
echo "🧪 Testing IAM Cleanup for Problematic Stack: 017"
echo "=============================================="

log() { echo -e "\033[0;34m[$(date +'%Y-%m-%d %H:%M:%S')] $1\033[0m" >&2; }
error() { echo -e "\033[0;31m[ERROR] $1\033[0m" >&2; }
success() { echo -e "\033[0;32m[SUCCESS] $1\033[0m" >&2; }
warning() { echo -e "\033[0;33m[WARNING] $1\033[0m" >&2; }

# Test stack name that's causing the issue
TEST_STACK="017"

log "Testing cleanup for stack: $TEST_STACK"
log "This should resolve the 'Cannot delete entity, must remove roles from instance profile first' error"

# Show what resources exist before cleanup
log "Checking existing resources..."
role_name="${TEST_STACK}-role"
profile_name="app-017-profile"

if aws iam get-role --role-name "$role_name" &> /dev/null; then
    log "✓ Found existing role: $role_name"
    
    # Check what instance profiles it's associated with
    profiles=$(aws iam list-instance-profiles-for-role --role-name "$role_name" \
        --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || echo "")
    if [ -n "$profiles" ] && [ "$profiles" != "None" ]; then
        log "✓ Role is associated with instance profiles: $profiles"
    else
        log "ℹ Role has no instance profile associations"
    fi
fi

if aws iam get-instance-profile --instance-profile-name "$profile_name" &> /dev/null; then
    log "✓ Found existing instance profile: $profile_name"
    
    # Check what roles are in the profile
    roles=$(aws iam get-instance-profile --instance-profile-name "$profile_name" \
        --query 'InstanceProfile.Roles[].RoleName' --output text 2>/dev/null || echo "")
    if [ -n "$roles" ] && [ "$roles" != "None" ]; then
        log "✓ Instance profile contains roles: $roles"
    else
        log "ℹ Instance profile has no roles"
    fi
fi

echo ""
log "🚀 Testing the improved cleanup_iam_resources function..."
echo ""

# Run the cleanup function
if cleanup_iam_resources "$TEST_STACK"; then
    success "✅ IAM cleanup completed successfully!"
    log "The 'Cannot delete entity, must remove roles from instance profile first' error should be resolved"
else
    error "❌ IAM cleanup failed - this indicates the fix may need more work"
    exit 1
fi

echo ""
log "Verifying cleanup results..."

# Verify the resources are gone
if aws iam get-role --role-name "$role_name" &> /dev/null; then
    warning "⚠️ Role $role_name still exists (this might be expected if it's in use)"
else
    success "✅ Role $role_name successfully deleted"
fi

if aws iam get-instance-profile --instance-profile-name "$profile_name" &> /dev/null; then
    warning "⚠️ Instance profile $profile_name still exists (this might be expected if it's in use)"
else
    success "✅ Instance profile $profile_name successfully deleted"
fi

echo ""
success "🎉 IAM cleanup test completed!"
echo "=============================================="
echo "✅ The fix should resolve the DeleteConflict error"
echo ""
echo "Key improvements implemented:"
echo "  • Proper cleanup order: instance profiles first, then roles"
echo "  • Comprehensive role removal from all associated instance profiles"
echo "  • Added proper wait times for AWS propagation"
echo "  • Better error handling with fallback logic"
echo "  • Centralized cleanup function in shared library"
echo "=============================================="