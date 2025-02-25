---
ai_context:
  model_requirements:
    context_window: 16k_tokens
    memory_format: hierarchical
    reasoning_depth: required
    attention_focus: process
  context_dependencies: []
  context_chain:
    previous: doc_standards/01-project/README.md
    next: doc_standards/01-project/00-templates/00-ai_header.md
  metadata:
    created: 2025-02-22 12:00:00 PM CST
    updated: 2025-02-22 12:00:00 PM CST
    version: v1.0.0
    category: documentation
    status: active
    revision_id: "<commit-hash>"   # New field: unique revision identifier
    parent_doc: "<file_path>"  # New field: hierarchical relationship
    abstract: "<High-level summary>"  # New field for quick context
---

# Documentation Templates
- **Path:** `doc_standards/01-project/00-templates/README.md`
- **Last Updated:** 2025-02-22 12:00:00 PM CST
- **Updated by:** muLDer
- **Purpose:** [Brief description of the document’s intended purpose]  
- **Authors:** [Primary Author(s) and Contributors]  
- **Version History:**  
  - **v1.0.0:** Initial creation – [Summary of changes]  
- **Dependencies/References:** [List related documents or external links]

## Available Templates
- [doc_standards/01-project/00-ai_header.md](doc_standards/01-project/00-ai_header.md) - Base AI context template
- [doc_standards/01-project/01-tracking.md](doc_standards/01-project/01-tracking.md) - Progress tracking template
- [doc_standards/01-project/02-guide.md](doc_standards/01-project/02-guide.md) - Documentation guide template
- [doc_standards/01-project/03-technical.md](doc_standards/01-project/03-technical.md) - Technical documentation template

## Template Selection Guide
| Content Type | Template | Usage |
|-------------|----------|--------|
| Project Overview | 00-ai_header.md | Base structure for all docs |
| Progress Reports | 01-tracking.md | Issue/progress tracking |
| How-To Guides | 02-guide.md | Step-by-step instructions |
| Technical Specs | 03-technical.md | System/API documentation |

## Usage Guidelines
1. Copy appropriate template
2. Update AI context parameters
3. Fill required sections
4. Maintain change log

## Change Log
- 2025-02-22 12:00:00 CST - Initial template documentation