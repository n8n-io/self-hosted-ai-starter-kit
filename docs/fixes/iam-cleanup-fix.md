# IAM Cleanup Fix - DeleteConflict Error Resolution

## Problem Description

The `cleanup-consolidated.sh` script was failing with multiple IAM-related DeleteConflict errors:

**Error 1**: Instance Profile Association
```
[2025-07-24 12:08:46] Cleaning up IAM role: 017-role

An error occurred (DeleteConflict) when calling the DeleteRole operation: Cannot delete entity, must remove roles from instance profile first.
```

**Error 2**: Inline Policy Dependencies  
```
[2025-07-24 12:19:49] Cleaning up IAM role: 015-role

An error occurred (DeleteConflict) when calling the DeleteRole operation: Cannot delete entity, must delete policies first.
```

## Root Cause

The script was attempting to delete IAM roles without properly handling all their dependencies. AWS requires a specific cleanup order, and the original script was missing several critical steps:

**Missing Steps:**
1. **Inline Policy Deletion**: Roles with inline policies (created via `put-role-policy`) must have these deleted first
2. **Managed Policy Detachment**: Attached managed policies must be detached before role deletion
3. **Instance Profile Removal**: Roles must be removed from all associated instance profiles
4. **Multiple Profile Handling**: Roles can be associated with multiple instance profiles

**Required Cleanup Order:**
1. Delete all inline policies from roles (`delete-role-policy`)
2. Detach all managed policies from roles (`detach-role-policy`)
3. Remove roles from all instance profiles (`remove-role-from-instance-profile`)
4. Delete instance profiles (`delete-instance-profile`)
5. Delete roles (`delete-role`)

The original script only handled managed policies and basic instance profile removal, missing inline policies entirely.

## Solution Implemented

### 1. Enhanced `cleanup-consolidated.sh`

Updated the cleanup script with improved IAM cleanup logic that:

- Properly removes roles from instance profiles before deletion
- Handles roles associated with multiple instance profiles
- Includes proper wait times for AWS propagation
- Uses comprehensive error handling with `|| true` fallbacks

### 2. Added `cleanup_iam_resources()` Function

Created a reusable function in `lib/aws-deployment-common.sh` that:

- Follows the correct cleanup order
- Handles both numeric stack names (e.g., "017") and regular stack names
- Uses the same naming conventions as the deployment scripts
- Includes proper error handling and logging

### 3. Comprehensive Testing

Added multiple test scripts to validate the complete fix:

- `tests/test-cleanup-iam.sh` - General IAM cleanup validation
- `tests/test-cleanup-017.sh` - Specific test for the "017" stack
- `tests/test-inline-policy-cleanup.sh` - Tests handling of inline policies
- `tests/test-full-iam-cleanup.sh` - Comprehensive end-to-end test that creates and cleans up all resource types

## Key Changes Made

### `scripts/cleanup-consolidated.sh`

```bash
# OLD: Inline IAM cleanup with potential race conditions
# NEW: Use shared cleanup function
log "Cleaning up IAM resources..."
cleanup_iam_resources "$STACK_NAME"
```

### `lib/aws-deployment-common.sh`

Added new function:

```bash
cleanup_iam_resources() {
    local stack_name="$1"
    
    # Step 1: Remove roles from instance profile first
    # Step 2: Delete instance profile
    # Step 3: Clean up the role:
    #   - Delete all inline policies (delete-role-policy)
    #   - Detach all managed policies (detach-role-policy)  
    #   - Remove from any remaining instance profiles
    #   - Delete the role
}
```

## Verification Steps

1. **Syntax Validation**: All scripts pass `bash -n` syntax checking
2. **Function Testing**: Test scripts validate the cleanup logic for all scenarios
3. **AWS API Ordering**: The cleanup now follows AWS requirements exactly
4. **End-to-End Testing**: Comprehensive test creates real AWS resources and verifies cleanup
5. **Real-World Validation**: Successfully cleaned up the problematic "015-role" with inline policies

## Usage

The fix is automatically applied when running:

```bash
# Using the cleanup script directly
./scripts/cleanup-consolidated.sh 017

# Using the Make target
make destroy STACK_NAME=017

# Using the unified deployment script
./scripts/aws-deployment-unified.sh --cleanup 017
```

## Breaking Changes

None. The fix is backward compatible and improves the existing cleanup functionality without changing the API.

## Benefits

1. **Eliminates ALL DeleteConflict errors** - Handles both instance profile and policy dependency errors
2. **Complete Policy Support** - Handles both inline policies and managed policies correctly
3. **Improves reliability** - More robust error handling and AWS propagation waits
4. **Better maintainability** - Centralized IAM cleanup logic in shared library
5. **Enhanced logging** - Clear progress indicators during cleanup process
6. **Comprehensive coverage** - Handles all edge cases including multiple instance profile associations
7. **Backward Compatible** - No breaking changes to existing functionality

## Related Files

- `scripts/cleanup-consolidated.sh` - Main cleanup script (enhanced)
- `lib/aws-deployment-common.sh` - Shared library (added comprehensive function)
- `tests/test-cleanup-iam.sh` - General IAM cleanup validation
- `tests/test-cleanup-017.sh` - Specific stack test
- `tests/test-inline-policy-cleanup.sh` - Inline policy handling test
- `tests/test-full-iam-cleanup.sh` - Comprehensive end-to-end validation