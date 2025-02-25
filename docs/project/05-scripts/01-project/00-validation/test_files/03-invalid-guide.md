---
ai_context:
  model_requirements:
    context_window: small
    memory_format: basic
    reasoning_depth: unknown
    attention_focus: any
  context_dependencies: ["non-existent-file.md"]
  context_chain:
    previous: "missing-file.md"
    next: null
  metadata:
    created: 2025/02/23
    updated: 2025/02/23
    version: 1.0
    category: guide
    status: draft
    revision_id: ""
    parent_doc: ""
    abstract: "This is an extremely long abstract that definitely exceeds the maximum allowed length of 100 characters and should trigger a validation error in the system when checked"
---

# Invalid Guide Document

- **Path:** `01-project/05-scripts/01-project/00-validation/test_files/03-invalid-guide.md`
- **Last Updated:** Invalid Date
- **Updated by:** Unknown
- **Purpose:** Test validation error detection
- **Version History:**
  - **1.0:** Initial creation

## Incomplete Guide
This document intentionally omits required sections and includes invalid metadata
to test the validation system's error detection capabilities.

## Partial Steps
1. Step one without context
2. Step two without details

## References
- Invalid reference 1
- Missing reference 2 