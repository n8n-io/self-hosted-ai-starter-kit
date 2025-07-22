# Development Tools Reference

> Complete reference for development, testing, and debugging CLI tools

This document covers all development-focused commands, testing utilities, and debugging tools for the AI Starter Kit development workflow.

## 🎯 Quick Development Commands

### Environment Setup
```bash
make setup                              # Initialize development environment
make dev-setup                          # Complete development setup
make install-deps                       # Install all dependencies
```

### Testing and Validation
```bash
make test                               # Run all tests
make validate                           # Validate configurations
make lint                               # Run code linting
```

### Development Workflow
```bash
make clean                              # Clean temporary files
make format                             # Format code
make docs                               # Generate documentation
```

## 🛠️ Development Environment Setup

### Initial Setup Commands

#### Environment Initialization
```bash
make setup
```
**What it does:**
- Makes all scripts executable
- Creates `.env` file if it doesn't exist
- Sets up basic development structure
- Validates basic requirements

#### Complete Development Setup
```bash
make dev-setup
```
**Equivalent to:**
```bash
make setup
make install-deps
make validate
```

#### Dependency Installation
```bash
make install-deps
```

**Uses script:**
```bash
./tools/install-deps.sh [OPTIONS]
```

**Installation options:**
- `--check-only`: Check dependencies without installing
- `--category CATEGORY`: Install specific category (aws, docker, python, node)
- `--update`: Update existing dependencies
- `--verbose`: Verbose installation output

**Example usage:**
```bash
# Check what's missing
./tools/install-deps.sh --check-only

# Install AWS tools only
./tools/install-deps.sh --category aws

# Update all dependencies
./tools/install-deps.sh --update
```

### Environment Validation

#### Check Dependencies
```bash
make check-deps
```

#### Configuration Validation
```bash
make validate
```

**Uses script:**
```bash
./tools/validate-config.sh [OPTIONS]
```

**Validation options:**
- `--config CONFIG`: Validate specific configuration (aws, docker, env)
- `--strict`: Strict validation mode
- `--fix`: Attempt to fix issues automatically
- `--report`: Generate validation report

**Example usage:**
```bash
# Validate AWS configuration only
./tools/validate-config.sh --config aws

# Strict validation with auto-fix
./tools/validate-config.sh --strict --fix

# Generate validation report
./tools/validate-config.sh --report > validation-report.txt
```

## 🧪 Testing Framework

### Test Execution Commands

#### Run All Tests
```bash
make test
```

**Uses script:**
```bash
./tools/test-runner.sh [OPTIONS]
```

#### Specific Test Categories
```bash
make test-unit                          # Unit tests only
make test-integration                   # Integration tests only
make test-security                      # Security tests only
```

#### Test Runner Script Options
```bash
./tools/test-runner.sh [OPTIONS]
```

**Test options:**
- `--category CATEGORY`: Test category (unit, integration, security, performance)
- `--service SERVICE`: Test specific service (n8n, ollama, qdrant, crawl4ai)
- `--coverage`: Generate coverage report
- `--parallel`: Run tests in parallel
- `--verbose`: Verbose test output
- `--fail-fast`: Stop on first failure
- `--report FORMAT`: Report format (junit, html, json)

**Example usage:**
```bash
# Run unit tests with coverage
./tools/test-runner.sh --category unit --coverage

# Run integration tests for specific service
./tools/test-runner.sh --category integration --service ollama

# Run all tests in parallel with HTML report
./tools/test-runner.sh --parallel --report html

# Run security tests with verbose output
./tools/test-runner.sh --category security --verbose
```

### Test Categories

#### Unit Tests
```bash
# Python unit tests
python -m pytest tests/unit/ -v

# JavaScript unit tests (if applicable)
npm test

# Shell script unit tests
./tools/test-runner.sh --category unit
```

#### Integration Tests
```bash
# Service integration tests
./tools/test-runner.sh --category integration

# API integration tests
python -m pytest tests/integration/api/ -v

# Deployment integration tests
./tools/test-runner.sh --category integration --service deployment
```

#### Security Tests
```bash
# Security validation
./tools/test-runner.sh --category security

# Vulnerability scanning
./tools/security-scan.sh

# Configuration security audit
./scripts/security-validation.sh
```

#### Performance Tests
```bash
# Performance benchmarks
./tools/test-runner.sh --category performance

# Load testing
./tools/load-test.sh --service ollama --concurrent 10 --duration 60s

# Resource usage tests
./tools/test-runner.sh --category performance --resource-monitoring
```

## 🔍 Code Quality Tools

### Linting and Formatting

#### Code Linting
```bash
make lint
```

**Uses script:**
```bash
./tools/lint.sh [OPTIONS]
```

**Linting options:**
- `--language LANG`: Lint specific language (bash, python, yaml, json)
- `--fix`: Auto-fix issues where possible
- `--strict`: Strict linting mode
- `--report`: Generate linting report

**Example usage:**
```bash
# Lint all code
./tools/lint.sh

# Lint and auto-fix Python code
./tools/lint.sh --language python --fix

# Strict linting with report
./tools/lint.sh --strict --report > lint-report.txt
```

#### Code Formatting
```bash
make format
```

**Uses script:**
```bash
./tools/format.sh [OPTIONS]
```

**Formatting options:**
- `--language LANG`: Format specific language
- `--check`: Check formatting without applying changes
- `--diff`: Show formatting differences

### Static Analysis

#### Security Analysis
```bash
# Security linting
./tools/security-lint.sh

# Credential scanning
./tools/scan-credentials.sh

# Dependency vulnerability check
./tools/check-vulnerabilities.sh
```

#### Code Quality Metrics
```bash
# Code complexity analysis
./tools/analyze-complexity.sh

# Documentation coverage
./tools/check-doc-coverage.sh

# Test coverage analysis
./tools/analyze-coverage.sh
```

## 🐛 Debugging Tools

### Local Development

#### Local Service Testing
```bash
# Start services locally for development
docker-compose -f docker-compose.dev.yml up -d

# Run specific service for debugging
docker-compose -f docker-compose.dev.yml up ollama

# Check local service logs
docker-compose -f docker-compose.dev.yml logs -f
```

#### Debug Mode Deployment
```bash
# Deploy with debug mode enabled
DEBUG=true make deploy-simple STACK_NAME=debug-stack

# Deploy with verbose logging
LOG_LEVEL=debug make deploy-simple STACK_NAME=verbose-stack
```

### Remote Debugging

#### Debug Remote Services
```bash
# Debug specific service on remote instance
./tools/debug-service.sh my-stack --service ollama

# Check service logs with debug info
./tools/debug-logs.sh my-stack --service ollama --level debug

# Interactive debugging session
./tools/debug-interactive.sh my-stack
```

#### Performance Debugging
```bash
# Profile service performance
./tools/profile-service.sh my-stack --service ollama --duration 60s

# Memory usage analysis
./tools/analyze-memory.sh my-stack

# CPU usage analysis
./tools/analyze-cpu.sh my-stack
```

### Log Analysis

#### Log Collection
```bash
# Collect all logs for analysis
./tools/collect-logs.sh my-stack --output logs-$(date +%Y%m%d).tar.gz

# Collect logs with system info
./tools/collect-debug-info.sh my-stack
```

#### Log Analysis Tools
```bash
# Analyze error patterns
./tools/analyze-errors.sh logs-file.log

# Performance log analysis
./tools/analyze-performance-logs.sh logs-file.log

# Generate log summary
./tools/summarize-logs.sh logs-file.log --period 24h
```

## 🔧 Development Utilities

### Configuration Management

#### Environment Configuration
```bash
# Generate environment template
./tools/generate-env-template.sh > .env.template

# Validate environment configuration
./tools/validate-env.sh .env

# Merge environment configurations
./tools/merge-env.sh .env.local .env.production > .env.merged
```

#### Service Configuration
```bash
# Generate service configuration
./tools/generate-service-config.sh --service ollama --environment dev

# Validate service configuration
./tools/validate-service-config.sh --service ollama config/ollama.yaml

# Update service configuration
./tools/update-service-config.sh my-stack --service ollama --config new-config.yaml
```

### Development Scripts

#### Script Generation
```bash
# Generate deployment script for environment
./tools/generate-deploy-script.sh --environment staging > deploy-staging.sh

# Generate test script for service
./tools/generate-test-script.sh --service ollama > test-ollama.sh

# Generate monitoring script
./tools/generate-monitor-script.sh my-stack > monitor-my-stack.sh
```

#### Development Helpers
```bash
# Quick development environment reset
./tools/dev-reset.sh

# Development environment status
./tools/dev-status.sh

# Development environment cleanup
./tools/dev-cleanup.sh
```

## 📚 Documentation Tools

### Documentation Generation

#### Generate Documentation
```bash
make docs
```

**Uses script:**
```bash
./tools/generate-docs.sh [OPTIONS]
```

**Documentation options:**
- `--type TYPE`: Documentation type (api, cli, user)
- `--format FORMAT`: Output format (markdown, html, pdf)
- `--output DIR`: Output directory
- `--serve`: Start documentation server

#### Serve Documentation Locally
```bash
make docs-serve
```

**Equivalent to:**
```bash
cd docs && python -m http.server 8080
```

### Documentation Validation

#### Check Documentation Links
```bash
# Validate all documentation links
./tools/check-doc-links.sh

# Check specific documentation file
./tools/check-doc-links.sh docs/reference/api/README.md

# Generate link report
./tools/check-doc-links.sh --report > link-report.txt
```

#### Documentation Coverage
```bash
# Check documentation coverage
./tools/check-doc-coverage.sh

# Generate documentation metrics
./tools/doc-metrics.sh > doc-metrics.json
```

## 🔄 Continuous Integration Support

### CI/CD Integration

#### GitHub Actions Support
```bash
# Validate GitHub Actions workflows
./tools/validate-github-actions.sh

# Test CI/CD pipeline locally
./tools/test-ci-pipeline.sh

# Generate CI/CD configuration
./tools/generate-ci-config.sh --platform github > .github/workflows/ci.yml
```

#### Pre-commit Hooks
```bash
# Install pre-commit hooks
./tools/install-pre-commit.sh

# Run pre-commit checks manually
./tools/run-pre-commit.sh

# Update pre-commit hooks
./tools/update-pre-commit.sh
```

### Automation Scripts

#### Automated Testing
```bash
# Run automated test suite
./tools/automated-test-suite.sh

# Scheduled testing
./tools/schedule-tests.sh --daily --time "02:00"

# Regression testing
./tools/regression-test.sh --baseline v1.0.0 --current v1.1.0
```

#### Build Automation
```bash
# Automated build process
./tools/automated-build.sh

# Build validation
./tools/validate-build.sh

# Build artifact management
./tools/manage-artifacts.sh --action cleanup --age 30d
```

## 🛡️ Security Development

### Secure Development Practices

#### Security Validation
```bash
# Pre-deployment security check
./tools/pre-deploy-security.sh my-stack

# Code security analysis
./tools/analyze-code-security.sh

# Configuration security validation
./tools/validate-security-config.sh
```

#### Credential Management
```bash
# Scan for exposed credentials
./tools/scan-credentials.sh

# Validate credential usage
./tools/validate-credentials.sh

# Generate secure configuration template
./tools/generate-secure-config.sh > secure-config.template
```

### Security Testing

#### Penetration Testing
```bash
# Basic security testing
./tools/basic-security-test.sh my-stack

# Network security testing
./tools/test-network-security.sh my-stack

# Service security testing
./tools/test-service-security.sh my-stack --service ollama
```

#### Vulnerability Assessment
```bash
# Dependency vulnerability scan
./tools/scan-dependencies.sh

# Container vulnerability scan
./tools/scan-containers.sh

# Infrastructure vulnerability assessment
./tools/assess-infrastructure.sh my-stack
```

## 🔧 Troubleshooting Development Issues

### Common Development Issues

#### Environment Issues
```bash
# Fix common environment issues
./tools/fix-env-issues.sh

# Reset development environment
./tools/reset-dev-env.sh

# Diagnose environment problems
./tools/diagnose-env.sh
```

#### Dependency Issues
```bash
# Fix dependency conflicts
./tools/fix-dependencies.sh

# Update dependencies
./tools/update-dependencies.sh

# Clean dependency cache
./tools/clean-dep-cache.sh
```

### Debug Information Collection

#### System Information
```bash
# Collect development environment info
./tools/collect-dev-info.sh > dev-info.txt

# Generate debug report
./tools/generate-debug-report.sh > debug-report.json

# System compatibility check
./tools/check-compatibility.sh
```

#### Issue Reporting
```bash
# Generate issue report
./tools/generate-issue-report.sh --issue-type bug > bug-report.md

# Collect logs for issue
./tools/collect-issue-logs.sh --issue-id 123 > issue-123-logs.tar.gz
```

---

[**← Back to CLI Overview**](README.md) | [**→ Makefile Commands**](makefile.md)

---

**Last Updated:** January 2025  
**Compatibility:** All development environments and workflows