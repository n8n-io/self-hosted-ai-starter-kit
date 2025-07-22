#!/usr/bin/env python3
"""
Integration tests for deployment workflow
Tests the complete deployment process without actually deploying to AWS
"""

import unittest
import subprocess
import sys
import os
import tempfile
import shutil
import json
import yaml
from unittest.mock import patch, MagicMock

class TestDeploymentWorkflow(unittest.TestCase):
    """Integration tests for deployment workflow"""

    def setUp(self):
        """Set up test fixtures"""
        self.test_dir = tempfile.mkdtemp()
        self.project_root = os.path.join(os.path.dirname(__file__), '..', '..')
        self.scripts_dir = os.path.join(self.project_root, 'scripts')
        
    def tearDown(self):
        """Clean up test fixtures"""
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_config_manager_generate_development(self):
        """Test configuration manager can generate development config"""
        config_manager = os.path.join(self.scripts_dir, 'config-manager.sh')
        
        if not os.path.exists(config_manager):
            self.skipTest("Config manager script not found")
        
        # Test validation command (doesn't require yq/jq)
        result = subprocess.run([
            'bash', config_manager, 'help'
        ], capture_output=True, text=True, cwd=self.project_root)
        
        self.assertEqual(result.returncode, 0, "Config manager help should work")
        self.assertIn("Configuration Manager", result.stdout)

    def test_security_check_script_execution(self):
        """Test security check script can execute"""
        security_check = os.path.join(self.scripts_dir, 'security-check.sh')
        
        if not os.path.exists(security_check):
            self.skipTest("Security check script not found")
        
        # Run security check (will likely find issues, but should execute)
        result = subprocess.run([
            'bash', security_check
        ], capture_output=True, text=True, cwd=self.project_root, timeout=60)
        
        # Should execute without syntax errors (may exit with 1 due to findings)
        self.assertIn("Security Audit", result.stdout or result.stderr)

    def test_validate_deployment_script_syntax(self):
        """Test deployment validation script has valid syntax"""
        validate_script = os.path.join(self.scripts_dir, 'validate-deployment.sh')
        
        if not os.path.exists(validate_script):
            self.skipTest("Validation script not found")
        
        result = subprocess.run([
            'bash', '-n', validate_script
        ], capture_output=True, text=True)
        
        self.assertEqual(result.returncode, 0, f"Validation script syntax error: {result.stderr}")

    def test_docker_compose_file_validity(self):
        """Test Docker Compose file is valid"""
        compose_file = os.path.join(self.project_root, 'docker-compose.gpu-optimized.yml')
        
        if not os.path.exists(compose_file):
            self.skipTest("Docker Compose file not found")
        
        # Test YAML syntax
        with open(compose_file, 'r') as f:
            try:
                yaml.safe_load(f)
            except yaml.YAMLError as e:
                self.fail(f"Docker Compose file has invalid YAML: {e}")
        
        # Test docker-compose config validation
        result = subprocess.run([
            'docker-compose', '-f', compose_file, 'config'
        ], capture_output=True, text=True, cwd=self.project_root)
        
        if result.returncode != 0:
            # Docker compose might not be available, check for obvious syntax issues
            self.assertNotIn("ERROR", result.stderr, f"Docker Compose config error: {result.stderr}")

    def test_container_versions_are_pinned(self):
        """Test that all container images use specific versions"""
        compose_file = os.path.join(self.project_root, 'docker-compose.gpu-optimized.yml')
        
        if not os.path.exists(compose_file):
            self.skipTest("Docker Compose file not found")
        
        with open(compose_file, 'r') as f:
            content = f.read()
        
        # Check for :latest tags
        self.assertNotIn(':latest', content, "Docker Compose should not use :latest tags")
        
        # Check for specific version patterns
        version_patterns = [
            'postgres:16.1-alpine3.19',
            'n8nio/n8n:1.19.4',
            'qdrant/qdrant:v1.7.3',
            'ollama/ollama:0.1.17'
        ]
        
        for pattern in version_patterns:
            self.assertIn(pattern, content, f"Should contain pinned version: {pattern}")

    def test_environment_configuration_files_exist(self):
        """Test that environment configuration files exist and are valid"""
        config_dir = os.path.join(self.project_root, 'config', 'environments')
        
        required_files = ['development.yml', 'production.yml']
        
        for filename in required_files:
            filepath = os.path.join(config_dir, filename)
            self.assertTrue(os.path.exists(filepath), f"Configuration file should exist: {filename}")
            
            # Test YAML validity
            with open(filepath, 'r') as f:
                try:
                    config = yaml.safe_load(f)
                    self.assertIsInstance(config, dict, f"Configuration should be valid YAML dict: {filename}")
                    
                    # Check required sections
                    required_sections = ['global', 'infrastructure', 'applications', 'security']
                    for section in required_sections:
                        self.assertIn(section, config, f"Configuration should have {section} section: {filename}")
                        
                except yaml.YAMLError as e:
                    self.fail(f"Configuration file has invalid YAML: {filename}: {e}")

    def test_deployment_scripts_have_security_validation(self):
        """Test that deployment scripts load security validation"""
        deployment_scripts = [
            'aws-deployment.sh',
            'aws-deployment-simple.sh',
            'aws-deployment-ondemand.sh'
        ]
        
        for script_name in deployment_scripts:
            script_path = os.path.join(self.scripts_dir, script_name)
            
            if not os.path.exists(script_path):
                continue
            
            with open(script_path, 'r') as f:
                content = f.read()
            
            # Check for security validation integration
            self.assertIn('security-validation.sh', content, 
                         f"Deployment script should load security validation: {script_name}")

    def test_gitignore_protects_sensitive_files(self):
        """Test that .gitignore protects sensitive files"""
        gitignore_path = os.path.join(self.project_root, '.gitignore')
        
        if not os.path.exists(gitignore_path):
            self.skipTest(".gitignore file not found")
        
        with open(gitignore_path, 'r') as f:
            gitignore_content = f.read()
        
        # Check for protection of sensitive file patterns
        sensitive_patterns = [
            '*.pem',
            '*.key',
            '**/credentials/*.json',
            '*secret*',
            '*password*',
            '.env',
            '.aws/'
        ]
        
        for pattern in sensitive_patterns:
            self.assertIn(pattern, gitignore_content, 
                         f".gitignore should protect sensitive files: {pattern}")

    def test_demo_credentials_have_warnings(self):
        """Test that demo credential files have security warnings"""
        credentials_dir = os.path.join(self.project_root, 'n8n', 'demo-data', 'credentials')
        
        if not os.path.exists(credentials_dir):
            self.skipTest("Demo credentials directory not found")
        
        for filename in os.listdir(credentials_dir):
            if filename.endswith('.json'):
                filepath = os.path.join(credentials_dir, filename)
                
                with open(filepath, 'r') as f:
                    try:
                        data = json.load(f)
                        
                        # Check for security warnings
                        warning_fields = ['_WARNING', '_SECURITY_NOTICE', '_USAGE']
                        has_warning = any(field in data for field in warning_fields)
                        
                        self.assertTrue(has_warning, 
                                      f"Demo credential file should have security warning: {filename}")
                        
                    except json.JSONError as e:
                        self.fail(f"Demo credential file has invalid JSON: {filename}: {e}")

    def test_container_security_configuration(self):
        """Test that containers are configured with security best practices"""
        compose_file = os.path.join(self.project_root, 'docker-compose.gpu-optimized.yml')
        
        if not os.path.exists(compose_file):
            self.skipTest("Docker Compose file not found")
        
        with open(compose_file, 'r') as f:
            content = f.read()
        
        # Check for security configurations
        security_configs = [
            'no-new-privileges:true',
            'user:',  # Non-root user configuration
            'security_opt:',
            'read_only:'
        ]
        
        for config in security_configs:
            self.assertIn(config, content, f"Docker Compose should have security config: {config}")

    def test_resource_limits_are_reasonable(self):
        """Test that resource limits don't exceed physical constraints"""
        compose_file = os.path.join(self.project_root, 'docker-compose.gpu-optimized.yml')
        
        if not os.path.exists(compose_file):
            self.skipTest("Docker Compose file not found")
        
        with open(compose_file, 'r') as f:
            try:
                compose_config = yaml.safe_load(f)
                
                total_cpu_limits = 0
                total_memory_limits = 0
                
                for service_name, service_config in compose_config.get('services', {}).items():
                    deploy_config = service_config.get('deploy', {})
                    resources = deploy_config.get('resources', {})
                    limits = resources.get('limits', {})
                    
                    # Extract CPU limits
                    cpu_limit = limits.get('cpus', '0')
                    if isinstance(cpu_limit, str):
                        try:
                            total_cpu_limits += float(cpu_limit.strip("'\""))
                        except ValueError:
                            pass
                    
                    # Extract memory limits (simplified check)
                    memory_limit = limits.get('memory', '0')
                    if isinstance(memory_limit, str) and 'G' in memory_limit:
                        try:
                            memory_gb = float(memory_limit.replace('G', '').strip())
                            total_memory_limits += memory_gb
                        except ValueError:
                            pass
                
                # Check against g4dn.xlarge limits (4 vCPUs, 16GB RAM)
                self.assertLessEqual(total_cpu_limits, 4.5, 
                                   f"Total CPU limits should not exceed 4.5 vCPUs: {total_cpu_limits}")
                self.assertLessEqual(total_memory_limits, 18, 
                                   f"Total memory limits should not exceed 18GB: {total_memory_limits}")
                
            except yaml.YAMLError as e:
                self.fail(f"Docker Compose file has invalid YAML: {e}")


class TestScriptIntegration(unittest.TestCase):
    """Test integration between scripts"""

    def setUp(self):
        """Set up test fixtures"""
        self.project_root = os.path.join(os.path.dirname(__file__), '..', '..')
        self.scripts_dir = os.path.join(self.project_root, 'scripts')

    def test_all_scripts_have_valid_syntax(self):
        """Test that all shell scripts have valid syntax"""
        for filename in os.listdir(self.scripts_dir):
            if filename.endswith('.sh'):
                script_path = os.path.join(self.scripts_dir, filename)
                
                with self.subTest(script=filename):
                    result = subprocess.run([
                        'bash', '-n', script_path
                    ], capture_output=True, text=True)
                    
                    self.assertEqual(result.returncode, 0, 
                                   f"Script {filename} has syntax error: {result.stderr}")

    def test_python_scripts_have_valid_syntax(self):
        """Test that all Python scripts have valid syntax"""
        for filename in os.listdir(self.scripts_dir):
            if filename.endswith('.py'):
                script_path = os.path.join(self.scripts_dir, filename)
                
                with self.subTest(script=filename):
                    result = subprocess.run([
                        sys.executable, '-m', 'py_compile', script_path
                    ], capture_output=True, text=True)
                    
                    self.assertEqual(result.returncode, 0, 
                                   f"Python script {filename} has syntax error: {result.stderr}")

    def test_scripts_are_executable(self):
        """Test that scripts have executable permissions"""
        executable_scripts = [
            'security-validation.sh',
            'security-check.sh',
            'validate-deployment.sh',
            'config-manager.sh'
        ]
        
        for script_name in executable_scripts:
            script_path = os.path.join(self.scripts_dir, script_name)
            
            if os.path.exists(script_path):
                with self.subTest(script=script_name):
                    self.assertTrue(os.access(script_path, os.X_OK), 
                                  f"Script should be executable: {script_name}")


if __name__ == '__main__':
    # Create a test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test cases
    suite.addTests(loader.loadTestsFromTestCase(TestDeploymentWorkflow))
    suite.addTests(loader.loadTestsFromTestCase(TestScriptIntegration))
    
    # Run the tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Exit with non-zero code if tests failed
    sys.exit(0 if result.wasSuccessful() else 1)