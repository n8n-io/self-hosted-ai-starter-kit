#!/usr/bin/env python3
"""
Unit tests for security validation functionality
Tests the security validation library and related functions
"""

import unittest
import subprocess
import sys
import os
from unittest.mock import patch, mock_open, MagicMock

# Add the scripts directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))

class TestSecurityValidation(unittest.TestCase):
    """Test cases for security validation functions"""

    def setUp(self):
        """Set up test fixtures"""
        self.script_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'scripts')
        self.security_script = os.path.join(self.script_dir, 'security-validation.sh')

    def test_validate_aws_region_valid(self):
        """Test AWS region validation with valid regions"""
        valid_regions = ['us-east-1', 'us-west-2', 'eu-west-1']
        
        for region in valid_regions:
            with self.subTest(region=region):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && validate_aws_region "{region}"'
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, f"Valid region {region} should pass validation")

    def test_validate_aws_region_invalid(self):
        """Test AWS region validation with invalid regions"""
        invalid_regions = ['invalid-region', 'us-invalid-1', '']
        
        for region in invalid_regions:
            with self.subTest(region=region):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && validate_aws_region "{region}"'
                ], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, f"Invalid region {region} should fail validation")

    def test_validate_instance_type_valid(self):
        """Test instance type validation with valid types"""
        valid_types = ['g4dn.xlarge', 'g5g.2xlarge', 'auto']
        
        for instance_type in valid_types:
            with self.subTest(instance_type=instance_type):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && validate_instance_type "{instance_type}"'
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, f"Valid instance type {instance_type} should pass validation")

    def test_validate_instance_type_invalid(self):
        """Test instance type validation with invalid types"""
        invalid_types = ['t2.micro', 'invalid-type', '']
        
        for instance_type in invalid_types:
            with self.subTest(instance_type=instance_type):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && validate_instance_type "{instance_type}"'
                ], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, f"Invalid instance type {instance_type} should fail validation")

    def test_validate_spot_price_valid(self):
        """Test spot price validation with valid prices"""
        valid_prices = ['0.10', '1.50', '5.00', '10.0']
        
        for price in valid_prices:
            with self.subTest(price=price):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && validate_spot_price "{price}"'
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, f"Valid price {price} should pass validation")

    def test_validate_spot_price_invalid(self):
        """Test spot price validation with invalid prices"""
        invalid_prices = ['0.05', '100.00', 'invalid', '-1.0', '']
        
        for price in invalid_prices:
            with self.subTest(price=price):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && validate_spot_price "{price}"'
                ], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, f"Invalid price {price} should fail validation")

    def test_validate_stack_name_valid(self):
        """Test stack name validation with valid names"""
        valid_names = ['ai-starter-kit', 'mystack123', 'test-stack-1']
        
        for name in valid_names:
            with self.subTest(name=name):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && validate_stack_name "{name}"'
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, f"Valid stack name {name} should pass validation")

    def test_validate_stack_name_invalid(self):
        """Test stack name validation with invalid names"""
        invalid_names = ['invalid_name', 'stack with spaces', 'x', 'a' * 65, '']
        
        for name in invalid_names:
            with self.subTest(name=name):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && validate_stack_name "{name}"'
                ], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, f"Invalid stack name {name} should fail validation")

    def test_generate_secure_password(self):
        """Test secure password generation"""
        result = subprocess.run([
            'bash', '-c', 
            f'source {self.security_script} && generate_secure_password 256'
        ], capture_output=True, text=True)
        
        self.assertEqual(result.returncode, 0, "Password generation should succeed")
        password = result.stdout.strip()
        self.assertEqual(len(password), 64, "256-bit password should be 64 hex characters")
        self.assertTrue(all(c in '0123456789abcdef' for c in password.lower()), 
                       "Password should be valid hex")

    def test_validate_password_strength(self):
        """Test password strength validation"""
        # Test strong password
        strong_password = 'a' * 32  # 32 char hex string
        result = subprocess.run([
            'bash', '-c', 
            f'source {self.security_script} && validate_password_strength "{strong_password}" 24'
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, "Strong password should pass validation")
        
        # Test weak password
        weak_password = 'abc'  # Too short
        result = subprocess.run([
            'bash', '-c', 
            f'source {self.security_script} && validate_password_strength "{weak_password}" 24'
        ], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, "Weak password should fail validation")

    def test_sanitize_path(self):
        """Test path sanitization"""
        test_cases = [
            ('normal/path', 'normal/path'),
            ('../../../etc/passwd', 'etc/passwd'),
            ('/absolute/path', 'absolute/path'),
            ('path/with/../traversal', 'path/with/traversal'),
        ]
        
        for input_path, expected in test_cases:
            with self.subTest(input_path=input_path):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && sanitize_path "{input_path}"'
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, "Path sanitization should succeed")
                sanitized = result.stdout.strip()
                self.assertEqual(sanitized, expected, f"Path {input_path} should be sanitized to {expected}")

    def test_escape_shell_arg(self):
        """Test shell argument escaping"""
        dangerous_args = [
            "normal_arg",
            "arg with spaces",
            "arg;with;semicolons",
            "arg$(command)substitution",
            "arg`with`backticks"
        ]
        
        for arg in dangerous_args:
            with self.subTest(arg=arg):
                result = subprocess.run([
                    'bash', '-c', 
                    f'source {self.security_script} && escape_shell_arg "{arg}"'
                ], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, "Argument escaping should succeed")
                escaped = result.stdout.strip()
                self.assertIsNotNone(escaped, "Escaped argument should not be empty")

    def test_security_script_syntax(self):
        """Test that the security validation script has valid syntax"""
        result = subprocess.run([
            'bash', '-n', self.security_script
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, f"Security script should have valid syntax: {result.stderr}")


class TestCostOptimization(unittest.TestCase):
    """Test cases for cost optimization functionality"""

    def setUp(self):
        """Set up test fixtures"""
        self.cost_script = os.path.join(os.path.dirname(__file__), '..', '..', 'scripts', 'cost-optimization.py')

    def test_cost_script_syntax(self):
        """Test that the cost optimization script has valid Python syntax"""
        if not os.path.exists(self.cost_script):
            self.skipTest("Cost optimization script not found")
        
        result = subprocess.run([
            sys.executable, '-m', 'py_compile', self.cost_script
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, f"Cost script should have valid syntax: {result.stderr}")

    def test_no_shell_injection_vulnerabilities(self):
        """Test that the cost optimization script doesn't have shell injection vulnerabilities"""
        if not os.path.exists(self.cost_script):
            self.skipTest("Cost optimization script not found")
        
        with open(self.cost_script, 'r') as f:
            content = f.read()
        
        # Check for dangerous patterns
        dangerous_patterns = [
            'shell=True',
            'os.system(',
            'subprocess.call(',
            'subprocess.check_call(',
            'subprocess.run(' + '.*shell=True'
        ]
        
        for pattern in dangerous_patterns:
            self.assertNotIn(pattern, content, 
                           f"Cost script should not contain dangerous pattern: {pattern}")


if __name__ == '__main__':
    # Create a test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test cases
    suite.addTests(loader.loadTestsFromTestCase(TestSecurityValidation))
    suite.addTests(loader.loadTestsFromTestCase(TestCostOptimization))
    
    # Run the tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Exit with non-zero code if tests failed
    sys.exit(0 if result.wasSuccessful() else 1)