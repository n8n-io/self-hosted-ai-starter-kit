#!/usr/bin/env python3
"""
Template Validation Script
Created: 2025-02-23 10:10:00 AM CST
Author: muLDer
Purpose: Validate documentation files against template standards
"""

import os
import re
import yaml
import datetime
from pathlib import Path
from typing import Dict, List, Optional

class TemplateValidator:
    VALID_CONTEXT_WINDOWS = {'8k_tokens', '16k_tokens', '32k_tokens'}
    VALID_MEMORY_FORMATS = {'sequential', 'tabular', 'hierarchical'}
    VALID_REASONING_DEPTHS = {'required', 'optional', 'none'}
    VALID_ATTENTION_FOCUSES = {'technical', 'process', 'analysis'}
    VALID_CATEGORIES = {'technical', 'guide', 'analysis', 'tracking'}
    VALID_STATUSES = {'draft', 'review', 'active', 'archived'}
    
    def __init__(self, workspace_root: str):
        self.workspace_root = Path(workspace_root)
        
    def validate_file(self, file_path: str) -> List[str]:
        """Validate a single documentation file."""
        errors = []
        file_path = Path(file_path)
        
        if not file_path.exists():
            return [f"File not found: {file_path}"]
            
        try:
            content = file_path.read_text(encoding='utf-8')
            front_matter = self._extract_front_matter(content)
            if not front_matter:
                return [f"No valid front matter found in {file_path}"]
                
            errors.extend(self._validate_ai_context(front_matter, file_path))
            errors.extend(self._validate_metadata(front_matter, file_path))
            errors.extend(self._validate_document_structure(content, file_path))
            
        except Exception as e:
            errors.append(f"Error processing {file_path}: {str(e)}")
            
        return errors
    
    def _extract_front_matter(self, content: str) -> Optional[Dict]:
        """Extract and parse YAML front matter."""
        front_matter_match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
        if not front_matter_match:
            return None
            
        try:
            return yaml.safe_load(front_matter_match.group(1))
        except yaml.YAMLError:
            return None
    
    def _validate_ai_context(self, front_matter: Dict, file_path: Path) -> List[str]:
        """Validate AI context section."""
        errors = []
        ai_context = front_matter.get('ai_context', {})
        
        if not ai_context:
            errors.append(f"Missing ai_context in {file_path}")
            return errors
            
        # Validate model requirements
        model_reqs = ai_context.get('model_requirements', {})
        if not model_reqs:
            errors.append(f"Missing model_requirements in {file_path}")
        else:
            # Context window validation
            context_window = model_reqs.get('context_window')
            if not context_window or context_window not in self.VALID_CONTEXT_WINDOWS:
                errors.append(f"Invalid context_window in {file_path}")
                
            # Memory format validation
            memory_format = model_reqs.get('memory_format')
            if not memory_format or memory_format not in self.VALID_MEMORY_FORMATS:
                errors.append(f"Invalid memory_format in {file_path}")
                
            # Reasoning depth validation
            reasoning_depth = model_reqs.get('reasoning_depth')
            if not reasoning_depth or reasoning_depth not in self.VALID_REASONING_DEPTHS:
                errors.append(f"Invalid reasoning_depth in {file_path}")
                
            # Attention focus validation
            attention_focus = model_reqs.get('attention_focus')
            if not attention_focus or attention_focus not in self.VALID_ATTENTION_FOCUSES:
                errors.append(f"Invalid attention_focus in {file_path}")
        
        # Validate context chain
        context_chain = ai_context.get('context_chain', {})
        if not context_chain:
            errors.append(f"Missing context_chain in {file_path}")
        else:
            previous = context_chain.get('previous')
            next_doc = context_chain.get('next')
            
            if previous and not self._validate_file_reference(previous):
                errors.append(f"Invalid previous link in {file_path}")
            if next_doc and not self._validate_file_reference(next_doc):
                errors.append(f"Invalid next link in {file_path}")
        
        return errors
    
    def _validate_metadata(self, front_matter: Dict, file_path: Path) -> List[str]:
        """Validate metadata section."""
        errors = []
        metadata = front_matter.get('ai_context', {}).get('metadata', {})
        
        if not metadata:
            errors.append(f"Missing metadata in {file_path}")
            return errors
            
        # Validate timestamps
        for field in ['created', 'updated']:
            timestamp = metadata.get(field)
            if not timestamp or not self._validate_timestamp(timestamp):
                errors.append(f"Invalid {field} timestamp in {file_path}")
        
        # Validate version
        version = metadata.get('version')
        if not version or not re.match(r'^v\d+\.\d+\.\d+$', version):
            errors.append(f"Invalid version format in {file_path}")
            
        # Validate category
        category = metadata.get('category')
        if not category or category not in self.VALID_CATEGORIES:
            errors.append(f"Invalid category in {file_path}")
            
        # Validate status
        status = metadata.get('status')
        if not status or status not in self.VALID_STATUSES:
            errors.append(f"Invalid status in {file_path}")
            
        # Validate revision_id and parent_doc
        if not metadata.get('revision_id'):
            errors.append(f"Missing revision_id in {file_path}")
        if not metadata.get('parent_doc'):
            errors.append(f"Missing parent_doc in {file_path}")
            
        # Validate abstract
        abstract = metadata.get('abstract')
        if not abstract or len(abstract) > 100:
            errors.append(f"Invalid abstract in {file_path}")
            
        return errors
    
    def _validate_document_structure(self, content: str, file_path: Path) -> List[str]:
        """Validate document structure."""
        errors = []
        
        # Check for required sections
        required_sections = {
            'technical': ['System Overview', 'Implementation Details', 'Security Considerations'],
            'guide': ['Prerequisites', 'Step-by-Step Guide', 'Troubleshooting'],
            'analysis': ['Executive Summary', 'Analysis', 'Recommendations'],
            'tracking': ['Current Status', 'Progress Summary', 'Metrics']
        }
        
        # Get document category from front matter
        front_matter = self._extract_front_matter(content)
        if front_matter:
            category = front_matter.get('ai_context', {}).get('metadata', {}).get('category')
            if category in required_sections:
                for section in required_sections[category]:
                    if not re.search(rf'^##\s+{section}', content, re.MULTILINE):
                        errors.append(f"Missing required section '{section}' in {file_path}")
        
        return errors
    
    def _validate_timestamp(self, timestamp: str) -> bool:
        """Validate timestamp format."""
        try:
            datetime.datetime.strptime(timestamp, '%Y-%m-%d %I:%M:%S %p CST')
            return True
        except ValueError:
            return False
    
    def _validate_file_reference(self, file_path: str) -> bool:
        """Validate file reference exists."""
        if file_path == 'null':
            return True
        return (self.workspace_root / file_path).exists()

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Validate documentation templates')
    parser.add_argument('workspace_root', help='Root directory of the workspace')
    parser.add_argument('files', nargs='+', help='Files to validate')
    args = parser.parse_args()
    
    validator = TemplateValidator(args.workspace_root)
    exit_code = 0
    
    for file_path in args.files:
        errors = validator.validate_file(file_path)
        if errors:
            print(f"\nValidation errors in {file_path}:")
            for error in errors:
                print(f"  - {error}")
            exit_code = 1
        else:
            print(f"\n✅ {file_path} passed validation")
    
    exit(exit_code)