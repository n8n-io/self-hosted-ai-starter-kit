#!/usr/bin/env python3
"""
Template Validator Test Suite
Created: 2025-02-23 08:02:00 AM CST
Author: muLDer
Purpose: Test suite for template validation script
"""

import os
import unittest
from pathlib import Path
from .template_validator import TemplateValidator

class TestTemplateValidator(unittest.TestCase):
    def setUp(self):
        self.workspace_root = Path(__file__).parent.parent.parent.parent.parent
        self.validator = TemplateValidator(str(self.workspace_root))
        self.test_files_dir = Path(__file__).parent / "test_files"
        self.test_files_dir.mkdir(exist_ok=True)

    def create_test_file(self, content: str, filename: str) -> Path:
        """Create a test file with given content."""
        file_path = self.test_files_dir / filename
        file_path.write_text(content)
        return file_path

    def test_valid_technical_doc(self):
        """Test validation of a valid technical document."""
        content = """---
ai_context:
  model_requirements:
    context_window: 16k_tokens
    memory_format: hierarchical
    reasoning_depth: required
    attention_focus: technical
  context_dependencies: []
  context_chain:
    previous: null
    next: null
  metadata:
    created: 2025-02-23 07:58:00 AM CST
    updated: 2025-02-23 07:58:00 AM CST
    version: v1.0.0
    category: technical
    status: active
    revision_id: "test-123"
    parent_doc: null
    abstract: "Test technical document"
---

# Test Technical Document

## System Overview
Test overview

## Implementation Details
Test implementation

## Security Considerations
Test security
"""
        file_path = self.create_test_file(content, "valid_technical.md")
        errors = self.validator.validate_file(str(file_path))
        self.assertEqual(len(errors), 0)

    def test_invalid_context_window(self):
        """Test validation of invalid context window."""
        content = """---
ai_context:
  model_requirements:
    context_window: invalid_size
    memory_format: hierarchical
    reasoning_depth: required
    attention_focus: technical
  context_dependencies: []
  context_chain:
    previous: null
    next: null
  metadata:
    created: 2025-02-23 07:58:00 AM CST
    updated: 2025-02-23 07:58:00 AM CST
    version: v1.0.0
    category: technical
    status: active
    revision_id: "test-123"
    parent_doc: null
    abstract: "Test technical document"
---

# Test Document
"""
        file_path = self.create_test_file(content, "invalid_context_window.md")
        errors = self.validator.validate_file(str(file_path))
        self.assertTrue(any("Invalid context_window" in error for error in errors))

    def test_missing_required_sections(self):
        """Test validation of missing required sections."""
        content = """---
ai_context:
  model_requirements:
    context_window: 16k_tokens
    memory_format: hierarchical
    reasoning_depth: required
    attention_focus: technical
  context_dependencies: []
  context_chain:
    previous: null
    next: null
  metadata:
    created: 2025-02-23 07:58:00 AM CST
    updated: 2025-02-23 07:58:00 AM CST
    version: v1.0.0
    category: technical
    status: active
    revision_id: "test-123"
    parent_doc: null
    abstract: "Test technical document"
---

# Test Document
"""
        file_path = self.create_test_file(content, "missing_sections.md")
        errors = self.validator.validate_file(str(file_path))
        self.assertTrue(any("Missing required section" in error for error in errors))

    def test_invalid_timestamp(self):
        """Test validation of invalid timestamp format."""
        content = """---
ai_context:
  model_requirements:
    context_window: 16k_tokens
    memory_format: hierarchical
    reasoning_depth: required
    attention_focus: technical
  context_dependencies: []
  context_chain:
    previous: null
    next: null
  metadata:
    created: 2025-02-23
    updated: 2025-02-23
    version: v1.0.0
    category: technical
    status: active
    revision_id: "test-123"
    parent_doc: null
    abstract: "Test technical document"
---

# Test Document
"""
        file_path = self.create_test_file(content, "invalid_timestamp.md")
        errors = self.validator.validate_file(str(file_path))
        self.assertTrue(any("Invalid created timestamp" in error for error in errors))

    def test_invalid_version(self):
        """Test validation of invalid version format."""
        content = """---
ai_context:
  model_requirements:
    context_window: 16k_tokens
    memory_format: hierarchical
    reasoning_depth: required
    attention_focus: technical
  context_dependencies: []
  context_chain:
    previous: null
    next: null
  metadata:
    created: 2025-02-23 07:58:00 AM CST
    updated: 2025-02-23 07:58:00 AM CST
    version: 1.0
    category: technical
    status: active
    revision_id: "test-123"
    parent_doc: null
    abstract: "Test technical document"
---

# Test Document
"""
        file_path = self.create_test_file(content, "invalid_version.md")
        errors = self.validator.validate_file(str(file_path))
        self.assertTrue(any("Invalid version format" in error for error in errors))

    def tearDown(self):
        """Clean up test files after each test."""
        for file in self.test_files_dir.glob("*.md"):
            file.unlink()
        self.test_files_dir.rmdir()

if __name__ == '__main__':
    unittest.main() 