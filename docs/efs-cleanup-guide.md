# EFS Cleanup Guide

This guide explains the enhanced EFS (Elastic File System) cleanup functionality in the consolidated cleanup script.

## Overview

The cleanup script now includes comprehensive EFS cleanup capabilities with multiple modes to handle different scenarios:

1. **Stack-based cleanup** - Cleanup EFS file systems associated with specific stacks
2. **Pattern-based cleanup** - Cleanup EFS file systems matching name patterns
3. **Failed deployment cleanup** - Cleanup specific failed deployment EFS file systems

## Cleanup Modes

### 1. Stack-based EFS Cleanup (Default)

Cleanup EFS file systems associated with a specific stack:

```bash
./scripts/cleanup-consolidated.sh 052
```

This will find and delete EFS file systems tagged with the stack name "052".

### 2. Pattern-based EFS Cleanup

Cleanup EFS file systems matching a name pattern:

```bash
./scripts/cleanup-consolidated.sh --mode efs "test-*"
./scripts/cleanup-consolidated.sh --mode efs "*-efs"
./scripts/cleanup-consolidated.sh --mode efs "051-efs"
```

This will find and delete EFS file systems whose names match the specified pattern.

### 3. Failed Deployment EFS Cleanup

Cleanup specific failed deployment EFS file systems (051-efs through 059-efs):

```bash
./scripts/cleanup-consolidated.sh --mode failed-deployments
```

This will delete the specific EFS file systems from failed deployments:
- fs-0e713d7f70c5c28e5 (051-efs)
- fs-016b6b42fe4e1251d (052-efs)
- fs-081412d661c7359b6 (053-efs)
- fs-08b9502f5bcb7db98 (054-efs)
- fs-043c227f27b0a57c5 (055-efs)
- fs-0e50ce2a955e271a1 (056-efs)
- fs-09b78c8e0b3439f73 (057-efs)
- fs-05e2980141f1c4cf5 (058-efs)
- fs-0cb64b1f87cbda05f (059-efs)

## Safety Features

### Dry Run Mode

Preview what would be deleted without actually deleting:

```bash
./scripts/cleanup-consolidated.sh --mode failed-deployments --dry-run --verbose
```

### Confirmation Prompts

By default, the script will prompt for confirmation before deleting resources. Use `--force` to skip confirmation:

```bash
./scripts/cleanup-consolidated.sh --mode failed-deployments --force
```

### Verbose Output

Get detailed information about the cleanup process:

```bash
./scripts/cleanup-consolidated.sh --mode efs "test-*" --verbose
```

## EFS Cleanup Process

The EFS cleanup process follows these steps:

1. **Discovery** - Find EFS file systems based on the specified criteria
2. **Mount Target Cleanup** - Delete all mount targets associated with the EFS file systems
3. **Wait Period** - Wait for mount target deletion to complete (30 seconds)
4. **File System Deletion** - Delete the EFS file systems themselves
5. **Verification** - Show remaining EFS file systems (in verbose mode)

## Error Handling

The script includes comprehensive error handling:

- **Graceful failures** - If one EFS file system fails to delete, others will still be processed
- **Resource counting** - Tracks successful deletions, skipped resources, and failures
- **Detailed logging** - Provides clear feedback about what was processed
- **Safe AWS commands** - Uses safe AWS command execution that doesn't exit on individual failures

## Examples

### Cleanup Failed Deployments
```bash
# Preview failed deployment cleanup
./scripts/cleanup-consolidated.sh --mode failed-deployments --dry-run --verbose

# Execute failed deployment cleanup
./scripts/cleanup-consolidated.sh --mode failed-deployments --verbose
```

### Cleanup Test EFS File Systems
```bash
# Preview test EFS cleanup
./scripts/cleanup-consolidated.sh --mode efs "test-*" --dry-run

# Execute test EFS cleanup
./scripts/cleanup-consolidated.sh --mode efs "test-*" --force
```

### Cleanup Specific Stack EFS
```bash
# Preview stack EFS cleanup
./scripts/cleanup-consolidated.sh 052 --dry-run --verbose

# Execute stack EFS cleanup
./scripts/cleanup-consolidated.sh 052 --verbose
```

## Integration with Existing Cleanup

The EFS cleanup functionality is fully integrated with the existing cleanup script:

- **Resource flags** - Use `--efs` flag with specific mode for EFS-only cleanup
- **Combined cleanup** - EFS cleanup can be combined with other resource types
- **Consistent interface** - Uses the same command-line interface as other cleanup operations

## Best Practices

1. **Always use dry-run first** - Preview what will be deleted before executing
2. **Use verbose mode** - Get detailed information about the cleanup process
3. **Check remaining resources** - Verify what EFS file systems remain after cleanup
4. **Backup important data** - Ensure important data is backed up before cleanup
5. **Use appropriate patterns** - Be specific with patterns to avoid unintended deletions

## Troubleshooting

### Common Issues

1. **Permission errors** - Ensure AWS credentials have EFS deletion permissions
2. **Mount target deletion failures** - Some mount targets may take time to delete
3. **Pattern matching issues** - Verify pattern syntax and test with dry-run first

### Debug Mode

For troubleshooting, use verbose mode and check AWS CLI output:

```bash
./scripts/cleanup-consolidated.sh --mode efs "pattern" --verbose
```

## Security Considerations

- **Least privilege** - Ensure AWS credentials have only necessary EFS permissions
- **Audit trail** - All cleanup operations are logged with timestamps
- **Confirmation** - Default confirmation prompts prevent accidental deletions
- **Resource verification** - Script verifies resources exist before attempting deletion 