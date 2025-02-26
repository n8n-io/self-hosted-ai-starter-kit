---
02/22/2025 11:55 AM CST
---

# Documentation Validation Rules
Path: `docs/doc_validation_rules.md`
Last Updated: 2025-02-22 11:55 AM CST
Updated by: muLDer

## File Structure Validation

### Required Elements
1. AI Context Header
   - Must include all required fields
   - Context window size must match document type
   - Memory format must be appropriate for content
   - Version number must follow semantic versioning

2. Document Metadata
   - Creation date in specified format
   - Last update date in specified format
   - Clear status indicator
   - Appropriate category designation

3. Content Structure
   - Main title matching filename
   - Last updated timestamp
   - Appropriate sections based on template
   - Change log section

## Naming Conventions

### Files
- Must start with numerical prefix
- Use lowercase letters
- Words separated by hyphens
- Extension must be .md
- Maximum filename length: 50 characters

### Directories
- Must start with numerical prefix
- Use lowercase letters
- Words separated by hyphens
- Maximum directory name length: 30 characters

## Content Validation

### Cross-References
- All internal links must use relative paths
- Links must point to existing documents
- Context chain must be properly maintained
- Related documentation must be valid

### Code Blocks
- Must specify language when applicable
- Must be properly formatted
- Must include necessary comments
- Must follow project style guide

### Diagrams
- Must use supported formats (Mermaid)
- Must include descriptive titles
- Must be properly integrated with text
- Must follow visual style guide

## Metadata Validation

### Version Numbers
- Must follow semantic versioning (X.Y.Z)
- Must be incremented appropriately
- Must be documented in change log
- Must align with project versioning

### Dates and Times
- Must use specified format: YYYY-MM-DD HH:mm:ss CST
- Must include timezone
- Must be updated when content changes
- Must be consistent across document

## Implementation Guide

### Automated Checks
```javascript
// Example validation script
function validateDocument(content) {
    checkAIContext(content);
    checkMetadata(content);
    checkStructure(content);
    checkNaming(content);
    validateLinks(content);
    validateVersioning(content);
}
```

### Manual Review Checklist
1. Content Quality
   - Clear and concise writing
   - Logical flow of information
   - Appropriate level of detail
   - Consistent terminology

2. Technical Accuracy
   - Correct technical information
   - Updated requirements
   - Valid configuration examples
   - Current best practices

3. Completeness
   - All required sections present
   - All examples provided
   - All prerequisites listed
   - All dependencies documented

## Maintenance Requirements

### Regular Updates
- Review active documents monthly
- Update outdated information
- Archive obsolete content
- Refresh examples and references

### Version Control
- Commit messages must reference document versions
- Major changes require review
- Track document dependencies
- Maintain change history

### Quality Assurance
- Peer review for technical content
- Validation script execution
- Link checking
- Format verification