#!/bin/bash

# =============================================================================
# Codebase Cleanup Script
# Removes temporary files and reorganizes the project structure
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}" >&2; }
warning() { echo -e "${YELLOW}[WARNING] $1${NC}" >&2; }

# Get project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_backup_files() {
    log "Cleaning up backup files..."
    
    local backup_files=(
        "docker-compose.gpu-optimized.yml.backup-20250723-001859"
        "docker-compose.gpu-optimized.yml.backup-20250723-001914"
        "docker-compose.gpu-optimized.yml.backup-20250723-001944"
        "docker-compose.gpu-optimized.yml.backup-20250723-002444"
    )
    
    local removed_count=0
    for file in "${backup_files[@]}"; do
        if [ -f "$file" ]; then
            rm "$file"
            log "Removed backup file: $file"
            ((removed_count++))
        fi
    done
    
    # Find and remove any other backup files
    find . -name "*.backup" -o -name "*.backup-*" -o -name "*~" | while read -r file; do
        if [ -f "$file" ]; then
            rm "$file"
            log "Removed backup file: $file"
            ((removed_count++))
        fi
    done
    
    success "Removed $removed_count backup files"
}

cleanup_system_files() {
    log "Cleaning up system files..."
    
    local removed_count=0
    
    # Remove macOS .DS_Store files
    find . -name ".DS_Store" -type f | while read -r file; do
        rm "$file"
        log "Removed .DS_Store file: $file"
        ((removed_count++))
    done
    
    # Remove Windows Thumbs.db files
    find . -name "Thumbs.db" -type f | while read -r file; do
        rm "$file"
        log "Removed Thumbs.db file: $file"
        ((removed_count++))
    done
    
    # Remove editor swap files
    find . -name "*.swp" -o -name "*.swo" -o -name "*~" | while read -r file; do
        if [ -f "$file" ]; then
            rm "$file"
            log "Removed editor file: $file"
            ((removed_count++))
        fi
    done
    
    success "Removed system and editor files"
}

cleanup_temporary_docs() {
    log "Cleaning up temporary documentation files..."
    
    # Create archive directory
    mkdir -p docs/archive/
    
    local temp_docs=(
        "AMI_SELECTION_FIXES.md"
        "COMPREHENSIVE_HEURISTIC_REVIEW.md"
        "HEURISTIC_REVIEW_CHANGES.md"
        "HEURISTIC_REVIEW_SUMMARY.md"
        "INTELLIGENT_DEPLOYMENT_SUMMARY.md"
    )
    
    local archived_count=0
    for doc in "${temp_docs[@]}"; do
        if [ -f "$doc" ]; then
            mv "$doc" "docs/archive/"
            log "Archived temporary doc: $doc"
            ((archived_count++))
        fi
    done
    
    success "Archived $archived_count temporary documentation files"
}

handle_security_files() {
    log "Checking for security-sensitive files..."
    
    # Check for private key files
    if [ -f "007-key.pem" ]; then
        warning "Found RSA private key file: 007-key.pem"
        read -p "Delete this private key file? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm "007-key.pem"
            success "Removed private key file"
        else
            warning "Private key file kept - ensure it's in .gitignore"
        fi
    fi
    
    # Check for other potential key files
    find . -name "*.pem" -o -name "*.key" -o -name "id_rsa*" | while read -r file; do
        if [ -f "$file" ] && [[ ! "$file" =~ ^./secrets/ ]]; then
            warning "Found potential private key: $file"
            echo "  Consider adding to .gitignore or moving to secrets/ directory"
        fi
    done
}

reorganize_misplaced_files() {
    log "Reorganizing misplaced files..."
    
    # Move test files to tests directory
    local test_files=(
        "test-alb-cloudfront.sh"
        "test-docker-config.sh"
        "test-image-config.sh"
    )
    
    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            mv "$test_file" "tests/"
            log "Moved test file: $test_file -> tests/"
        fi
    done
    
    # Move cleanup script to scripts directory if it exists at root
    if [ -f "cleanup-stack.sh" ] && [ "$PWD/cleanup-stack.sh" != "$PWD/scripts/cleanup-stack.sh" ]; then
        mv "cleanup-stack.sh" "scripts/"
        log "Moved cleanup-stack.sh to scripts/"
    fi
    
    # Move container versions to config directory
    if [ -f "container-versions.lock" ]; then
        mv "container-versions.lock" "config/"
        log "Moved container-versions.lock to config/"
    fi
    
    success "Reorganized misplaced files"
}

fix_n8n_file_extensions() {
    log "Fixing n8n workflow file extensions..."
    
    cd "n8n/demo-data/workflows/" 2>/dev/null || {
        warning "n8n/demo-data/workflows/ directory not found, skipping"
        return 0
    }
    
    local workflow_files=(
        "The Archivist"
        "The Bag"
        "The Ear"
        "The Pen"
        "The Voice"
        "HNIC"
    )
    
    local fixed_count=0
    for file in "${workflow_files[@]}"; do
        if [ -f "$file" ] && [[ ! "$file" =~ \. ]]; then
            # Check if it's a JSON file by looking at content
            if file "$file" | grep -q "JSON\|ASCII text" && head -1 "$file" | grep -q "^{"; then
                mv "$file" "$file.json"
                log "Added .json extension: $file -> $file.json"
                ((fixed_count++))
            fi
        fi
    done
    
    cd "$PROJECT_ROOT"
    success "Fixed $fixed_count file extensions"
}

cleanup_log_files() {
    log "Cleaning up log files..."
    
    local removed_count=0
    find . -name "*.log" -type f | while read -r file; do
        # Skip log files in config directory (these are templates)
        if [[ ! "$file" =~ ^./config/ ]]; then
            rm "$file"
            log "Removed log file: $file"
            ((removed_count++))
        fi
    done
    
    # Clean up Python cache directories
    find . -name "__pycache__" -type d | while read -r dir; do
        rm -rf "$dir"
        log "Removed Python cache: $dir"
    done
    
    success "Cleaned up log files and cache directories"
}

update_gitignore() {
    log "Updating .gitignore..."
    
    local gitignore_additions=(
        "# Backup files"
        "*.backup"
        "*.backup-*"
        "*~"
        ""
        "# System files"
        ".DS_Store"
        "Thumbs.db"
        ""
        "# Private keys and certificates"
        "*.pem"
        "*.key"
        "!secrets/*.key.template"
        ""
        "# Temporary documentation"
        "**/HEURISTIC_REVIEW*.md"
        "**/COMPREHENSIVE_*.md"
        "docs/archive/"
        ""
        "# Editor files"
        "*.swp"
        "*.swo"
        ""
        "# Log files (except templates)"
        "*.log"
        "!config/*.log"
        ""
        "# Python cache"
        "__pycache__/"
        "*.pyc"
        "*.pyo"
    )
    
    # Check if .gitignore exists
    if [ ! -f ".gitignore" ]; then
        touch ".gitignore"
    fi
    
    # Add entries that don't already exist
    local added_count=0
    for entry in "${gitignore_additions[@]}"; do
        if [ -n "$entry" ] && ! grep -Fxq "$entry" ".gitignore"; then
            echo "$entry" >> ".gitignore"
            ((added_count++))
        fi
    done
    
    success "Updated .gitignore with $added_count new entries"
}

create_missing_directories() {
    log "Creating missing directories..."
    
    local directories=(
        "docs/archive"
        "tests/scripts"
        "tests/fixtures"
        "logs"
        "tmp"
    )
    
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log "Created directory: $dir"
        fi
    done
    
    success "Created missing directories"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_cleanup() {
    log "Validating cleanup results..."
    
    local issues=0
    
    # Check for remaining backup files
    if find . -name "*.backup*" -o -name "*~" | grep -q .; then
        warning "Backup files still found:"
        find . -name "*.backup*" -o -name "*~"
        ((issues++))
    fi
    
    # Check for .DS_Store files
    if find . -name ".DS_Store" | grep -q .; then
        warning ".DS_Store files still found:"
        find . -name ".DS_Store"
        ((issues++))
    fi
    
    # Check for private keys in wrong locations
    if find . -name "*.pem" -not -path "./secrets/*" | grep -q .; then
        warning "Private key files found outside secrets directory:"
        find . -name "*.pem" -not -path "./secrets/*"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        success "Cleanup validation passed - no issues found"
    else
        warning "Cleanup validation found $issues issues to review"
    fi
    
    return $issues
}

generate_cleanup_report() {
    log "Generating cleanup report..."
    
    cat > "docs/archive/cleanup-report-$(date +%Y%m%d-%H%M%S).md" << EOF
# Codebase Cleanup Report

**Date**: $(date)
**Script**: scripts/cleanup-codebase.sh

## Actions Performed

### Files Removed
- Backup files: docker-compose.gpu-optimized.yml.backup-*
- System files: .DS_Store, Thumbs.db
- Editor files: *.swp, *.swo
- Log files: *.log (except templates)
- Python cache: __pycache__ directories

### Files Reorganized
- Test files moved to tests/
- Scripts moved to scripts/
- Configuration files moved to config/
- Temporary docs archived to docs/archive/

### File Extensions Fixed
- n8n workflow files without extensions renamed to .json

### Security Actions
- Private key files reviewed and handled
- .gitignore updated to prevent future accumulation

### Directories Created
- docs/archive/
- tests/scripts/
- tests/fixtures/
- logs/
- tmp/

## File Structure After Cleanup

\`\`\`
001-starter-kit/
├── scripts/           # All deployment and utility scripts
├── lib/              # Shared libraries
├── docs/             # Documentation (temp files archived)
├── tests/            # All test files consolidated here
├── config/           # Configuration files
├── secrets/          # Secure credential templates
├── n8n/              # n8n workflows and data
├── terraform/        # Infrastructure as Code
├── tools/            # Utility tools
├── assets/           # Media and static files
└── tmp/              # Temporary files (gitignored)
\`\`\`

## Maintenance Recommendations

1. Run this cleanup script monthly
2. Use proper branching for temporary work
3. Follow naming conventions consistently
4. Keep private keys in secrets/ directory only
5. Archive temporary documentation regularly

EOF

    success "Cleanup report generated: docs/archive/cleanup-report-$(date +%Y%m%d-%H%M%S).md"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run     Show what would be done without making changes"
    echo "  --force       Skip confirmation prompts"
    echo "  --help        Show this help message"
    echo ""
    echo "This script will:"
    echo "  - Remove backup and temporary files"
    echo "  - Clean up system files (.DS_Store, etc.)"
    echo "  - Reorganize misplaced files"
    echo "  - Fix file extensions"
    echo "  - Update .gitignore"
    echo "  - Create missing directories"
}

main() {
    local dry_run=false
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "Starting codebase cleanup..."
    log "Project root: $PROJECT_ROOT"
    
    if [ "$dry_run" = true ]; then
        warning "DRY RUN MODE - No changes will be made"
        return 0
    fi
    
    if [ "$force" != true ]; then
        echo ""
        warning "This will clean up temporary files and reorganize the codebase."
        warning "Some files will be deleted permanently."
        read -p "Continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled"
            exit 0
        fi
    fi
    
    echo ""
    log "Starting cleanup operations..."
    
    # Execute cleanup functions
    cleanup_backup_files
    cleanup_system_files
    cleanup_temporary_docs
    handle_security_files
    reorganize_misplaced_files
    fix_n8n_file_extensions
    cleanup_log_files
    update_gitignore
    create_missing_directories
    
    # Validation
    echo ""
    validate_cleanup
    
    # Generate report
    generate_cleanup_report
    
    echo ""
    success "Codebase cleanup completed successfully!"
    echo ""
    log "Next steps:"
    log "1. Review the cleanup report in docs/archive/"
    log "2. Test that all scripts still work correctly"
    log "3. Commit the cleaned up codebase"
    log "4. Consider running this cleanup monthly"
}

# Execute main function with all arguments
main "$@"