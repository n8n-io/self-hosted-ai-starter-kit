---
ai_context:
  model_requirements:
    context_window: 8k_tokens  # Simple documentation
    memory_format: sequential  # Step-by-step instructions
    reasoning_depth: optional  # Basic documentation
    attention_focus: technical  # Implementation focus
  context_dependencies: []
  context_chain:
    previous: "doc_standards/01-project/05-scripts/README.md"
    next: null
  metadata:
    created: 2025-02-23 07:51:30 AM CST
    updated: 2025-02-23 07:51:30 AM CST
    version: v1.0.0
    category: guide
    status: active
    revision_id: "init-validation-readme"
    parent_doc: "doc_standards/01-project/05-scripts/README.md"
    abstract: "Documentation for template validation scripts and tools"
---

# Template Validation Scripts
- **Path:** `doc_standards/01-project/05-scripts/00-validation/README.md`
- **Last Updated:** 2025-02-23 07:51:30 AM CST
- **Updated by:** muLDer
- **Purpose:** Document the template validation tools and their usage
- **Version History:**
  - **v1.0.0:** Initial creation - Basic validation script documentation

## Overview
This directory contains scripts for validating documentation templates and ensuring they follow the established standards.

## Scripts

### 00-template-validator.py
Template validation script that checks:
- AI context headers
- Metadata fields
- Document structure
- Required sections
- File references
- Timestamp formats

#### Usage
```bash
python 00-template-validator.py <workspace_root> <file1> [file2 ...]
```

Example:
```bash
python 00-template-validator.py /path/to/workspace doc1.md doc2.md
```

## Requirements
- Python 3.8+
- Dependencies listed in `requirements.txt`

### Installation
```bash
pip install -r requirements.txt
```

## Validation Rules

### AI Context Validation
- Context window sizes: 8k_tokens, 16k_tokens, 32k_tokens
- Memory formats: sequential, tabular, hierarchical
- Reasoning depths: required, optional, none
- Attention focus: technical, process, analysis

### Metadata Validation
- Timestamps in format: YYYY-MM-DD HH:mm:ss A/PM CST
- Semantic versioning: vX.Y.Z
- Valid categories: technical, guide, analysis, tracking
- Valid statuses: draft, review, active, archived

### Document Structure
Each document type requires specific sections:
- Technical: System Overview, Implementation Details, Security Considerations
- Guide: Prerequisites, Step-by-Step Guide, Troubleshooting
- Analysis: Executive Summary, Analysis, Recommendations
- Tracking: Current Status, Progress Summary, Metrics

## Error Messages
- Missing AI context: "Missing ai_context in {file}"
- Invalid context window: "Invalid context_window in {file}"
- Missing required section: "Missing required section '{section}' in {file}"
- Invalid timestamp: "Invalid {field} timestamp in {file}"

## Best Practices
1. Run validation before committing changes
2. Fix all validation errors before merging
3. Keep dependencies up to date
4. Add new validation rules as standards evolve

## Related Documentation
- Template Standards
- Documentation Guidelines
- Git Workflow Guide 