---
ai_context:
  model_requirements:
    context_window: <8k|16k|32k>_tokens  # Select based on document complexity
    memory_format: <sequential|tabular|hierarchical>  # Choose based on content structure
    reasoning_depth: <required|optional|none>  # Determines AI analysis depth
    attention_focus: <technical|process|analysis>  # Sets primary document purpose
  context_dependencies: []  # List of required documents for full context
  context_chain:
    previous: <file_path>  # Previous document in logical flow
    next: <file_path>  # Next document in logical flow
  metadata:
    created: <YYYY-MM-DD HH:mm:ss A/PM CST>  # Initial document creation time
    updated: <YYYY-MM-DD HH:mm:ss A/PM CST>  # Last modification time
    version: <vX.Y.Z>  # Semantic versioning
    category: <type>  # Document category (e.g., technical, guide, analysis)
    status: <draft|review|active|archived>  # Current document state
    revision_id: "<commit-hash>"  # Git commit hash or unique identifier
    parent_doc: "<file_path>"  # Parent document in hierarchy
    abstract: "<High-level summary>"  # Brief document description
---

# AI Context Header Template Guide

## Field Validation Rules

### Model Requirements
1. **context_window**
   - Valid values: 8k_tokens, 16k_tokens, 32k_tokens
   - Selection guide:
     - 8k: Simple documents, single topic
     - 16k: Standard technical docs, multiple sections
     - 32k: Complex documentation, extensive context

2. **memory_format**
   - Valid values: sequential, tabular, hierarchical
   - Usage:
     - sequential: Step-by-step guides, procedures
     - tabular: Data-heavy docs, comparisons
     - hierarchical: System architecture, nested concepts

3. **reasoning_depth**
   - Valid values: required, optional, none
   - When to use:
     - required: Complex technical analysis
     - optional: General documentation
     - none: Simple reference material

4. **attention_focus**
   - Valid values: technical, process, analysis
   - Purpose:
     - technical: Implementation details, API docs
     - process: Workflows, procedures
     - analysis: Reviews, assessments

### Context Management
1. **context_dependencies**
   - Format: Array of file paths
   - Must be valid existing documents
   - Include only direct dependencies

2. **context_chain**
   - previous/next: Must be valid file paths
   - Maintain bidirectional links
   - Update both documents when changing

### Metadata Requirements
1. **Timestamps**
   - Format: YYYY-MM-DD HH:mm:ss A/PM CST
   - created: Never changes after initial set
   - updated: Change with each modification

2. **Version**
   - Format: vX.Y.Z (semantic versioning)
   - Increment appropriately:
     - X: Major changes
     - Y: Feature additions
     - Z: Minor updates

3. **Category**
   - Must match template type
   - Align with directory structure

4. **Status**
   - Valid progression: draft → review → active
   - Archive when deprecated

5. **Revision Tracking**
   - revision_id: Current git commit hash
   - parent_doc: Direct parent in doc hierarchy
   - abstract: Max 100 characters

## Examples

### Technical Documentation
```yaml
ai_context:
  model_requirements:
    context_window: 16k_tokens
    memory_format: hierarchical
    reasoning_depth: required
    attention_focus: technical
```

### Process Guide
```yaml
ai_context:
  model_requirements:
    context_window: 8k_tokens
    memory_format: sequential
    reasoning_depth: optional
    attention_focus: process
```

### Analysis Document
```yaml
ai_context:
  model_requirements:
    context_window: 32k_tokens
    memory_format: tabular
    reasoning_depth: required
    attention_focus: analysis
```

## Usage Notes
1. Always validate fields before committing
2. Update context chains bidirectionally
3. Maintain semantic versioning
4. Keep abstracts concise and descriptive
5. Verify file paths exist
6. Update timestamps appropriately