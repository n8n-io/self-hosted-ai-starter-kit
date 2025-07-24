#!/bin/bash
# Comprehensive test for IAM cleanup that creates and cleans up test resources
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set AWS region
export AWS_REGION="${AWS_REGION:-us-east-1}"

echo "=============================================="
echo "🧪 Comprehensive IAM Cleanup Test"
echo "=============================================="

log() { echo -e "\033[0;34m[$(date +'%Y-%m-%d %H:%M:%S')] $1\033[0m" >&2; }
error() { echo -e "\033[0;31m[ERROR] $1\033[0m" >&2; }
success() { echo -e "\033[0;32m[SUCCESS] $1\033[0m" >&2; }
warning() { echo -e "\033[0;33m[WARNING] $1\033[0m" >&2; }

# Use a unique test stack name
TEST_STACK="test-iam-$(date +%s)"
role_name="${TEST_STACK}-role"
profile_name="${TEST_STACK}-instance-profile"

log "Creating test IAM resources for stack: $TEST_STACK"

# Clean up function to ensure we don't leave test resources
cleanup_test_resources() {
    log "Cleaning up test resources..."
    
    # Remove role from instance profile if exists
    if aws iam get-instance-profile --instance-profile-name "$profile_name" &> /dev/null; then
        aws iam remove-role-from-instance-profile \
            --instance-profile-name "$profile_name" \
            --role-name "$role_name" &> /dev/null || true
        aws iam delete-instance-profile --instance-profile-name "$profile_name" &> /dev/null || true
    fi
    
    # Delete inline policies if they exist
    aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[]' --output text 2>/dev/null | tr '\t' '\n' | while read -r policy_name; do
        if [ -n "$policy_name" ] && [ "$policy_name" != "None" ]; then
            aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" &> /dev/null || true
        fi
    done
    
    # Detach managed policies if they exist
    aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | tr '\t' '\n' | while read -r policy_arn; do
        if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
            aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" &> /dev/null || true
        fi
    done
    
    # Delete role if it exists
    aws iam delete-role --role-name "$role_name" &> /dev/null || true
    
    log "Test resource cleanup completed"
}

# Set up trap to clean up on exit
trap cleanup_test_resources EXIT

# Create test role with trust policy
log "Creating test IAM role: $role_name"
trust_policy='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}'

aws iam create-role \
    --role-name "$role_name" \
    --assume-role-policy-document "$trust_policy" > /dev/null

# Create and attach an inline policy (this causes the "must delete policies first" error)
log "Creating inline policy for role"
inline_policy='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "*"
        }
    ]
}'

aws iam put-role-policy \
    --role-name "$role_name" \
    --policy-name "${TEST_STACK}-custom-policy" \
    --policy-document "$inline_policy"

# Attach a managed policy (this also needs to be detached)
log "Attaching managed policy to role"
aws iam attach-role-policy \
    --role-name "$role_name" \
    --policy-arn "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"

# Create instance profile and add role (this causes the "must remove roles from instance profile first" error)
log "Creating instance profile and associating role"
aws iam create-instance-profile --instance-profile-name "$profile_name" > /dev/null
aws iam add-role-to-instance-profile \
    --instance-profile-name "$profile_name" \
    --role-name "$role_name"

success "✅ Test IAM resources created successfully"

# Now verify the resources exist
log "Verifying test resources were created:"
if aws iam get-role --role-name "$role_name" &> /dev/null; then
    log "  ✓ Role exists: $role_name"
else
    error "  ❌ Role creation failed"
    exit 1
fi

inline_count=$(aws iam list-role-policies --role-name "$role_name" --query 'length(PolicyNames)' --output text)
log "  ✓ Inline policies: $inline_count"

managed_count=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'length(AttachedPolicies)' --output text)
log "  ✓ Managed policies: $managed_count"

if aws iam get-instance-profile --instance-profile-name "$profile_name" &> /dev/null; then
    log "  ✓ Instance profile exists: $profile_name"
else
    error "  ❌ Instance profile creation failed"
    exit 1
fi

echo ""
log "🚀 Now testing the cleanup-stack.sh script..."

# Test the actual cleanup script
if "$PROJECT_ROOT/scripts/cleanup-stack.sh" "$TEST_STACK"; then
    success "✅ cleanup-stack.sh completed successfully!"
else
    error "❌ cleanup-stack.sh failed"
    exit 1
fi

echo ""
log "Verifying all resources were cleaned up:"

# Check if resources were properly deleted
if aws iam get-role --role-name "$role_name" &> /dev/null; then
    error "  ❌ Role still exists: $role_name"
    exit 1
else
    log "  ✅ Role deleted: $role_name"
fi

if aws iam get-instance-profile --instance-profile-name "$profile_name" &> /dev/null; then
    error "  ❌ Instance profile still exists: $profile_name"
    exit 1
else
    log "  ✅ Instance profile deleted: $profile_name"
fi

success "🎉 Comprehensive IAM cleanup test PASSED!"
echo ""
echo "=============================================="
echo "✅ All IAM cleanup issues have been resolved:"
echo "   • Inline policies are deleted first"
echo "   • Managed policies are detached"
echo "   • Roles are removed from instance profiles"
echo "   • Instance profiles are deleted"
echo "   • Roles are deleted last"
echo ""
echo "The cleanup-stack.sh script now handles all IAM"
echo "resource dependencies correctly!"
echo "=============================================="