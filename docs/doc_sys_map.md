---
02/22/2025 11:55 AM CST
---

# Documentation System: Comprehensive Mapping
Path: `docs/doc_sys_map.md`
Last Updated: 2025-02-22 11:55 AM CST
Updated by: muLDer

## Template Foundation (docs/project/00-templates/)

The templates directory serves as the foundation of the documentation system. Each template defines the structure for different types of documentation:

### Core Templates
- `00-ai_header.md`: Base AI context template
  - Path: docs/project/00-templates/00-ai_header.md
  - Purpose: Provides AI-specific metadata structure
  - Usage: Include at the start of all new documents
  - Key Features: Context window sizing, memory format, reasoning depth

- `01-tracking.md`: Progress tracking template
  - Path: docs/project/00-templates/01-tracking.md
  - Purpose: Standardizes progress monitoring
  - Usage: Create new tracking documents in analysis section
  - Key Features: Status tracking, metrics, risk management

- `02-guide.md`: Documentation guide template
  - Path: docs/project/00-templates/02-guide.md
  - Purpose: Structures how-to documentation
  - Usage: Base for all instructional content
  - Key Features: Step-by-step format, prerequisites, troubleshooting

- `03-technical.md`: Technical documentation template
  - Path: docs/project/00-templates/03-technical.md
  - Purpose: Technical specification structure
  - Usage: Foundation for all technical documentation
  - Key Features: Architecture diagrams, API documentation, security considerations

## Active Documentation Sections

### Analysis and Tracking (docs/project/01-analysis/)
This section contains active project tracking and analysis:

- Issues Tracking (`00-tracking/00-issues/`)
  - Current Issues: `00-open_current/master_open.md`
  - Environment Issues: `01-environment/master_env.md`
  - Linter Issues: `02-linter/master_linter.md`

- File Tracking (`00-tracking/01-files/`)
  - Purpose: Track document relationships and dependencies
  - Uses: 01-tracking.md template

- Historical Records (`00-tracking/99-historical/`)
  - Purpose: Archive of resolved issues and completed tracking

### Project Concerns (docs/project/02-concerns/)
Dedicated to documenting and addressing project challenges:
- Should use technical.md template for complex issues
- Should use tracking.md template for ongoing concerns

### Project Planning (docs/project/03-plans/)
Houses project planning documentation:
- Should use guide.md template for process documentation
- Should use technical.md template for technical planning

### Visualization (docs/project/04-charts/)
Contains project-related diagrams and charts:
- Should use technical.md template with Mermaid diagrams
- Reference from other documents as needed

### Scripts (docs/project/05-scripts/)
Project-related scripts and automation:
- Environment Scripts: `00-environment/`
- Project Scripts: `01-project/`
- Should use technical.md template for documentation

### Historical Archive (docs/project/99-historical/)
Archive for outdated documentation:
- Maintains original structure
- Preserves metadata and relationships

## Quick Start Guide

1. Creating New Documentation:
   - Choose appropriate template from 00-templates
   - Copy template to correct section
   - Update AI context parameters
   - Fill in required sections

2. Document Relationships:
   - Update context_chain in AI header
   - Add cross-references in Related Documentation
   - Maintain historical links when archiving

3. Maintenance Pattern:
   - Regular updates to tracking documents
   - Archive outdated content to 99-historical
   - Keep change logs current
   - Update master tracking files

## Template Selection Guide

When creating new documentation, use this guide to select the appropriate template:

| Content Type | Template | Directory | Example Usage |
|-------------|-----------|-----------|---------------|
| Process Documentation | 02-guide.md | 03-plans/ | Development workflows |
| Technical Specs | 03-technical.md | 02-concerns/ | System architecture |
| Progress Tracking | 01-tracking.md | 01-analysis/ | Sprint progress |
| Script Documentation | 03-technical.md | 05-scripts/ | Build scripts |

## Implementation Notes

1. File Naming Convention:
   - Use numerical prefixes for ordering
   - Keep names lowercase with hyphens
   - Include category indicators

2. Directory Management:
   - Maintain numerical ordering
   - Use descriptive directory names
   - Keep consistent depth

3. Document Dependencies:
   - Update context_chain links
   - Maintain relative paths
   - Check cross-references

4. Version Control:
   - Update metadata on changes
   - Maintain change logs
   - Use semantic versioning

This structure provides a modular, scalable documentation system that can grow with your project while maintaining organization and clarity.