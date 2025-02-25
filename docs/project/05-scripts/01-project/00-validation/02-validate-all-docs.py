#!/usr/bin/env python3
"""
Documentation Validation Script
Created: 2025-02-23 07:59:30 AM CST
Author: muLDer
Purpose: Validate all documentation files in the workspace
"""

import os
import sys
from pathlib import Path
from .template_validator import TemplateValidator

def find_markdown_files(start_path: Path) -> list[Path]:
    """Find all markdown files in the workspace."""
    markdown_files = []
    for root, _, files in os.walk(start_path):
        for file in files:
            if file.endswith('.md'):
                markdown_files.append(Path(root) / file)
    return markdown_files

def main():
    """Main entry point for validation script."""
    # Get workspace root (parent of doc_standards)
    workspace_root = Path(__file__).parent.parent.parent.parent.parent
    
    # Initialize validator
    validator = TemplateValidator(str(workspace_root))
    
    # Find all markdown files
    markdown_files = find_markdown_files(workspace_root)
    
    # Track validation results
    total_files = len(markdown_files)
    failed_files = 0
    error_count = 0
    
    print(f"\nValidating {total_files} documentation files...\n")
    
    # Validate each file
    for file_path in markdown_files:
        errors = validator.validate_file(str(file_path))
        if errors:
            failed_files += 1
            error_count += len(errors)
            print(f"\n❌ Validation errors in {file_path}:")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"✅ {file_path}")
    
    # Print summary
    print(f"\nValidation Summary:")
    print(f"Total files checked: {total_files}")
    print(f"Files with errors: {failed_files}")
    print(f"Total errors found: {error_count}")
    print(f"Success rate: {((total_files - failed_files) / total_files * 100):.1f}%")
    
    return 1 if failed_files > 0 else 0

if __name__ == '__main__':
    # Add the parent directory to Python path for imports
    sys.path.insert(0, str(Path(__file__).parent))
    sys.exit(main()) 