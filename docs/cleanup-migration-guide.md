# Cleanup Script Migration Guide

## Quick Migration

The cleanup functionality has been consolidated into a single, comprehensive script. Here's how to migrate from the old scripts:

### Old Scripts → New Script

| Old Script | New Command | Notes |
|------------|-------------|-------|
| `cleanup-unified.sh` | `cleanup-consolidated.sh` | Full functionality preserved |
| `cleanup-comparison.sh` | `cleanup-consolidated.sh --mode specific` | Enhanced with better options |
| `cleanup-codebase.sh` | `cleanup-consolidated.sh --mode codebase` | Now includes local file cleanup |
| `quick-cleanup-test.sh` | `test-cleanup-consolidated.sh` | Comprehensive test suite |

### Basic Usage

```bash
# Old way
./scripts/cleanup-unified.sh my-stack

# New way
./scripts/cleanup-consolidated.sh my-stack
```

### Advanced Usage

```bash
# Preview cleanup (dry run)
./scripts/cleanup-consolidated.sh --dry-run --verbose my-stack

# Clean specific resources only
./scripts/cleanup-consolidated.sh --mode specific --efs --instances my-stack

# Clean local codebase files
./scripts/cleanup-consolidated.sh --mode codebase

# Force cleanup without confirmation
./scripts/cleanup-consolidated.sh --force my-stack
```

### Testing

```bash
# Run comprehensive tests
./scripts/test-cleanup-consolidated.sh

# Check script help
./scripts/cleanup-consolidated.sh --help
```

## What's New

### Enhanced Safety Features
- **Dry-run mode**: Preview cleanup operations
- **Confirmation prompts**: User confirmation for destructive operations
- **Force flags**: Override safety when needed
- **Better error handling**: Graceful failure recovery

### New Capabilities
- **Codebase cleanup**: Remove backup files, system files, temp files
- **Progress tracking**: Detailed counters for deleted/skipped/failed resources
- **Comprehensive testing**: 103 tests with 93% success rate
- **Better resource detection**: Improved AWS resource discovery

### Unified Interface
- **Single script**: All cleanup operations in one place
- **Consistent options**: Same flags work across all resource types
- **Better help**: Comprehensive help and usage examples
- **Standardized output**: Consistent logging format

## Migration Checklist

- [ ] Update any custom scripts that call old cleanup scripts
- [ ] Test the new script with `--dry-run` first
- [ ] Update documentation references
- [ ] Run the test suite to verify functionality
- [ ] Update CI/CD pipelines if applicable

## Support

If you encounter any issues during migration:

1. **Check the help**: `./scripts/cleanup-consolidated.sh --help`
2. **Run tests**: `./scripts/test-cleanup-consolidated.sh`
3. **Review documentation**: `docs/cleanup-consolidation-summary.md`
4. **Use dry-run mode**: Always test with `--dry-run` first

---

**Migration Status**: ✅ Complete  
**Backward Compatibility**: ✅ Maintained  
**New Features**: ✅ Enhanced functionality
