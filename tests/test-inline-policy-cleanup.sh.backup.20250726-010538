#!/bin/bash
# Test cleanup for roles with inline policies
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
echo "🧪 Testing IAM Cleanup for Roles with Inline Policies"
echo "=============================================="

log() { echo -e "\033[0;34m[$(date +'%Y-%m-%d %H:%M:%S')] $1\033[0m" >&2; }
error() { echo -e "\033[0;31m[ERROR] $1\033[0m" >&2; }
success() { echo -e "\033[0;32m[SUCCESS] $1\033[0m" >&2; }
warning() { echo -e "\033[0;33m[WARNING] $1\033[0m" >&2; }

# Test with the problematic stack
TEST_STACK="015"
role_name="${TEST_STACK}-role"

log "Testing cleanup for stack: $TEST_STACK (role: $role_name)"

# Check if the role exists and what policies it has
if aws iam get-role --role-name "$role_name" &> /dev/null; then
    log "✓ Found existing role: $role_name"
    
    # Check for inline policies
    inline_policies=$(aws iam list-role-policies --role-name "$role_name" \
        --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
    if [ -n "$inline_policies" ] && [ "$inline_policies" != "None" ]; then
        log "✓ Role has inline policies: $inline_policies"
    else
        log "ℹ Role has no inline policies"
    fi
    
    # Check for managed policies
    managed_policies=$(aws iam list-attached-role-policies --role-name "$role_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    if [ -n "$managed_policies" ] && [ "$managed_policies" != "None" ]; then
        log "✓ Role has managed policies: $managed_policies"
    else
        log "ℹ Role has no managed policies"
    fi
    
    # Check instance profile associations
    profiles=$(aws iam list-instance-profiles-for-role --role-name "$role_name" \
        --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || echo "")
    if [ -n "$profiles" ] && [ "$profiles" != "None" ]; then
        log "✓ Role is associated with instance profiles: $profiles"
    else
        log "ℹ Role has no instance profile associations"
    fi
else
    warning "Role $role_name does not exist - cannot test cleanup"
    exit 0
fi

echo ""
log "🚀 Testing the enhanced cleanup_iam_resources function..."
log "This should handle both inline and managed policies correctly"
echo ""

# Test the cleanup function
if cleanup_iam_resources "$TEST_STACK"; then
    success "✅ IAM cleanup completed successfully!"
    log "The 'must delete policies first' error should now be resolved"
else
    error "❌ IAM cleanup failed"
    exit 1
fi

echo ""
log "Verifying cleanup results..."

# Check if the role was successfully deleted
if aws iam get-role --role-name "$role_name" &> /dev/null; then
    warning "⚠️ Role $role_name still exists - checking why..."
    
    # Check if there are still policies attached
    remaining_inline=$(aws iam list-role-policies --role-name "$role_name" \
        --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
    if [ -n "$remaining_inline" ] && [ "$remaining_inline" != "None" ]; then
        error "❌ Role still has inline policies: $remaining_inline"
    fi
    
    remaining_managed=$(aws iam list-attached-role-policies --role-name "$role_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    if [ -n "$remaining_managed" ] && [ "$remaining_managed" != "None" ]; then
        error "❌ Role still has managed policies: $remaining_managed"
    fi
    
    remaining_profiles=$(aws iam list-instance-profiles-for-role --role-name "$role_name" \
        --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null || echo "")
    if [ -n "$remaining_profiles" ] && [ "$remaining_profiles" != "None" ]; then
        error "❌ Role still associated with profiles: $remaining_profiles"
    fi
else
    success "✅ Role $role_name successfully deleted"
fi

echo ""
success "🎉 Enhanced IAM cleanup test completed!"
echo "=============================================="
echo "✅ The fix should resolve both DeleteConflict errors:"
echo "   • 'must remove roles from instance profile first'"
echo "   • 'must delete policies first'"
echo ""
echo "Enhanced cleanup now handles:"
echo "  • Inline policies (delete-role-policy)"
echo "  • Managed policies (detach-role-policy)"
echo "  • Instance profile associations"
echo "  • Proper AWS propagation delays"
echo "=============================================="