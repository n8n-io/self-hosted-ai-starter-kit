#!/bin/bash
# =============================================================================
# Cleanup Consolidation Script
# Removes redundant cleanup scripts and updates references to use consolidated version
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2; }
error() { echo -e "${RED}❌ [ERROR] $1${NC}" >&2; }
success() { echo -e "${GREEN}✅ [SUCCESS] $1${NC}" >&2; }
warning() { echo -e "${YELLOW}⚠️  [WARNING] $1${NC}" >&2; }
info() { echo -e "${CYAN}ℹ️  [INFO] $1${NC}" >&2; }
step() { echo -e "${PURPLE}🔸 [STEP] $1${NC}" >&2; }

# Files to be removed (redundant cleanup scripts)
REDUNDANT_CLEANUP_FILES=(
    "cleanup-unified.sh"
    "cleanup-comparison.sh"
    "cleanup-codebase.sh"
    "quick-cleanup-test.sh"
    "test-cleanup-integration.sh"
    "test-cleanup-unified.sh"
)

# Backup files to be removed
BACKUP_FILES=(
    "aws-deployment.sh.backup"
    "aws-deployment.sh.bak"
)

# Test files to be removed (redundant test scripts)
REDUNDANT_TEST_FILES=(
    "test-cleanup-017.sh"
    "test-cleanup-iam.sh"
    "test-full-iam-cleanup.sh"
    "test-inline-policy-cleanup.sh"
)

# Files to update with new cleanup script references
FILES_TO_UPDATE=(
    "aws-deployment.sh"
    "aws-deployment-unified.sh"
    "aws-deployment-simple.sh"
    "aws-deployment-ondemand.sh"
)

# Function to backup a file before modification
backup_file() {
    local file_path="$1"
    local backup_path="${file_path}.backup.$(date +%Y%m%d-%H%M%S)"
    
    if [ -f "$file_path" ]; then
        cp "$file_path" "$backup_path"
        log "Backed up $file_path to $backup_path"
    fi
}

# Function to remove redundant cleanup files
remove_redundant_cleanup_files() {
    step "Removing redundant cleanup files..."
    
    local removed_count=0
    for file in "${REDUNDANT_CLEANUP_FILES[@]}"; do
        local file_path="$SCRIPT_DIR/$file"
        if [ -f "$file_path" ]; then
            backup_file "$file_path"
            rm "$file_path"
            success "Removed redundant cleanup file: $file"
            ((removed_count++))
        else
            info "File not found (already removed): $file"
        fi
    done
    
    success "Removed $removed_count redundant cleanup files"
}

# Function to remove backup files
remove_backup_files() {
    step "Removing backup files..."
    
    local removed_count=0
    for file in "${BACKUP_FILES[@]}"; do
        local file_path="$SCRIPT_DIR/$file"
        if [ -f "$file_path" ]; then
            rm "$file_path"
            success "Removed backup file: $file"
            ((removed_count++))
        else
            info "Backup file not found: $file"
        fi
    done
    
    # Also remove any other backup files
    find "$SCRIPT_DIR" -name "*.backup" -o -name "*.bak" | while read -r file; do
        if [ -f "$file" ]; then
            rm "$file"
            success "Removed backup file: $file"
            ((removed_count++))
        fi
    done
    
    success "Removed $removed_count backup files"
}

# Function to remove redundant test files
remove_redundant_test_files() {
    step "Removing redundant test files..."
    
    local removed_count=0
    for file in "${REDUNDANT_TEST_FILES[@]}"; do
        local file_path="$PROJECT_ROOT/tests/$file"
        if [ -f "$file_path" ]; then
            backup_file "$file_path"
            rm "$file_path"
            success "Removed redundant test file: $file"
            ((removed_count++))
        else
            info "Test file not found: $file"
        fi
    done
    
    success "Removed $removed_count redundant test files"
}

# Function to update deployment scripts to use consolidated cleanup
update_deployment_scripts() {
    step "Updating deployment scripts to use consolidated cleanup..."
    
    local updated_count=0
    for file in "${FILES_TO_UPDATE[@]}"; do
        local file_path="$SCRIPT_DIR/$file"
        if [ -f "$file_path" ]; then
            backup_file "$file_path"
            
            # Update references from cleanup-unified.sh to cleanup-consolidated.sh
            if sed -i.bak 's/cleanup-unified\.sh/cleanup-consolidated.sh/g' "$file_path"; then
                success "Updated $file to use consolidated cleanup script"
                ((updated_count++))
            else
                warning "Failed to update $file"
            fi
            
            # Remove the temporary .bak file created by sed
            rm -f "${file_path}.bak"
        else
            warning "Deployment script not found: $file"
        fi
    done
    
    success "Updated $updated_count deployment scripts"
}

# Function to update documentation
update_documentation() {
    step "Updating documentation..."
    
    # Update README.md if it exists
    local readme_path="$PROJECT_ROOT/README.md"
    if [ -f "$readme_path" ]; then
        backup_file "$readme_path"
        
        # Update any references to old cleanup scripts
        sed -i.bak 's/cleanup-unified\.sh/cleanup-consolidated.sh/g' "$readme_path"
        sed -i.bak 's/cleanup-stack\.sh/cleanup-consolidated.sh/g' "$readme_path"
        
        # Remove the temporary .bak file
        rm -f "${readme_path}.bak"
        
        success "Updated README.md with consolidated cleanup references"
    fi
    
    # Update any documentation files in docs/
    find "$PROJECT_ROOT/docs" -name "*.md" -type f | while read -r doc_file; do
        if [ -f "$doc_file" ]; then
            backup_file "$doc_file"
            
            # Update references
            sed -i.bak 's/cleanup-unified\.sh/cleanup-consolidated.sh/g' "$doc_file"
            sed -i.bak 's/cleanup-stack\.sh/cleanup-consolidated.sh/g' "$doc_file"
            
            # Remove the temporary .bak file
            rm -f "${doc_file}.bak"
            
            log "Updated documentation: $doc_file"
        fi
    done
    
    success "Updated documentation files"
}

# Function to create a migration guide
create_migration_guide() {
    step "Creating migration guide..."
    
    local migration_guide="$PROJECT_ROOT/docs/cleanup-migration-guide.md"
    
    cat > "$migration_guide" << 'EOF'
# Cleanup Script Migration Guide

## Overview

The cleanup functionality has been consolidated into a single, comprehensive script: `cleanup-consolidated.sh`. This replaces multiple redundant cleanup scripts with a unified solution.

## What Changed

### Removed Scripts
- `cleanup-unified.sh` → Replaced by `cleanup-consolidated.sh`
- `cleanup-comparison.sh` → Functionality integrated into consolidated script
- `cleanup-codebase.sh` → Functionality integrated into consolidated script
- `quick-cleanup-test.sh` → Replaced by `test-cleanup-consolidated.sh`
- `test-cleanup-integration.sh` → Replaced by `test-cleanup-consolidated.sh`
- `test-cleanup-unified.sh` → Replaced by `test-cleanup-consolidated.sh`

### Updated Scripts
- All deployment scripts now reference `cleanup-consolidated.sh`
- Documentation updated to reflect new script name

## Migration Steps

### 1. Update Your Scripts
If you have custom scripts that reference the old cleanup scripts, update them:

```bash
# Old
./scripts/cleanup-unified.sh --dry-run my-stack

# New
./scripts/cleanup-consolidated.sh --dry-run my-stack
```

### 2. Update Documentation
If you have documentation referencing old cleanup scripts, update the references.

### 3. Test the New Script
Run the comprehensive test suite:

```bash
./scripts/test-cleanup-consolidated.sh
```

## New Features

The consolidated cleanup script includes all features from the previous scripts plus:

- **Codebase Cleanup**: Remove backup files, system files, and temporary files
- **Enhanced Error Handling**: Better error recovery and reporting
- **Progress Tracking**: Detailed counters for deleted, skipped, and failed resources
- **Comprehensive Testing**: Full test suite for all functionality
- **Better Documentation**: Improved help and usage information

## Usage Examples

```bash
# Basic stack cleanup
./scripts/cleanup-consolidated.sh my-stack

# Dry run to see what would be deleted
./scripts/cleanup-consolidated.sh --dry-run --verbose my-stack

# Force cleanup without confirmation
./scripts/cleanup-consolidated.sh --force my-stack

# Cleanup specific resource types
./scripts/cleanup-consolidated.sh --mode specific --efs --instances my-stack

# Cleanup local codebase files
./scripts/cleanup-consolidated.sh --mode codebase --dry-run

# Cleanup all resources in a region
./scripts/cleanup-consolidated.sh --mode all --region us-west-2
```

## Benefits

1. **Single Source of Truth**: One script handles all cleanup scenarios
2. **Reduced Maintenance**: No more managing multiple cleanup scripts
3. **Consistent Interface**: Same command-line interface for all cleanup operations
4. **Better Error Handling**: Comprehensive error handling and recovery
5. **Enhanced Safety**: Multiple safety features and confirmation prompts
6. **Comprehensive Testing**: Full test coverage for all functionality

## Rollback

If you need to rollback, the original files have been backed up with timestamps. You can restore them if needed:

```bash
# Example backup file
./scripts/cleanup-unified.sh.backup.20250726-120000
```

## Support

For issues or questions about the consolidated cleanup script, refer to:
- The script help: `./scripts/cleanup-consolidated.sh --help`
- The test suite: `./scripts/test-cleanup-consolidated.sh`
- This migration guide
EOF

    success "Created migration guide: $migration_guide"
}

# Function to validate the consolidation
validate_consolidation() {
    step "Validating consolidation..."
    
    # Check that the consolidated script exists and is executable
    if [ ! -f "$SCRIPT_DIR/cleanup-consolidated.sh" ]; then
        error "Consolidated cleanup script not found!"
        return 1
    fi
    
    if [ ! -x "$SCRIPT_DIR/cleanup-consolidated.sh" ]; then
        error "Consolidated cleanup script is not executable!"
        return 1
    fi
    
    # Check that the test script exists and is executable
    if [ ! -f "$SCRIPT_DIR/test-cleanup-consolidated.sh" ]; then
        error "Consolidated test script not found!"
        return 1
    fi
    
    if [ ! -x "$SCRIPT_DIR/test-cleanup-consolidated.sh" ]; then
        error "Consolidated test script is not executable!"
        return 1
    fi
    
    # Test that the consolidated script works
    if ! "$SCRIPT_DIR/cleanup-consolidated.sh" --help >/dev/null 2>&1; then
        error "Consolidated cleanup script is not working properly!"
        return 1
    fi
    
    success "Consolidation validation passed"
}

# Function to show consolidation summary
show_consolidation_summary() {
    echo ""
    echo "=============================================="
    echo "📊 CLEANUP CONSOLIDATION SUMMARY"
    echo "=============================================="
    echo ""
    echo "✅ Consolidated cleanup script created:"
    echo "   • scripts/cleanup-consolidated.sh"
    echo "   • scripts/test-cleanup-consolidated.sh"
    echo ""
    echo "🗑️  Removed redundant files:"
    echo "   • Multiple cleanup scripts consolidated"
    echo "   • Backup files cleaned up"
    echo "   • Redundant test files removed"
    echo ""
    echo "🔄 Updated references:"
    echo "   • Deployment scripts updated"
    echo "   • Documentation updated"
    echo "   • Migration guide created"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Test the consolidated script: ./scripts/test-cleanup-consolidated.sh"
    echo "   2. Review the migration guide: docs/cleanup-migration-guide.md"
    echo "   3. Update any custom scripts to use the new consolidated script"
    echo ""
    echo "🎉 Cleanup consolidation completed successfully!"
    echo "=============================================="
}

# Main execution function
main() {
    echo "=============================================="
    echo "🔄 CLEANUP CONSOLIDATION PROCESS"
    echo "=============================================="
    echo ""
    
    # Remove redundant files
    remove_redundant_cleanup_files
    remove_backup_files
    remove_redundant_test_files
    
    # Update references
    update_deployment_scripts
    update_documentation
    
    # Create migration guide
    create_migration_guide
    
    # Validate consolidation
    validate_consolidation
    
    # Show summary
    show_consolidation_summary
}

# Run main function
main "$@" 