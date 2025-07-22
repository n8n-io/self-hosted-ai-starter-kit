# CLI Reference Overview

> Complete command-line interface reference for the AI Starter Kit

The AI Starter Kit provides comprehensive command-line tools for deployment, management, and operations. This reference covers all available commands, scripts, and automation tools.

## 🎯 Quick Reference

| Category | Purpose | Main Commands |
|----------|---------|---------------|
| **Setup** | Environment preparation | `make setup`, `make install-deps` |
| **Deployment** | Infrastructure deployment | `make deploy`, `make deploy-spot`, `make deploy-simple` |
| **Management** | Operations and maintenance | `make status`, `make logs`, `make backup` |
| **Development** | Development tools | `make test`, `make lint`, `make validate` |
| **Terraform** | Infrastructure as Code | `make tf-init`, `make tf-plan`, `make tf-apply` |

## 📚 Available CLI Tools

### Core Automation (Makefile)
The primary interface for all operations:
```bash
make help                    # Show all available commands
make setup                   # Initialize development environment
make deploy STACK_NAME=name  # Deploy infrastructure
make status STACK_NAME=name  # Check deployment status
```

### Deployment Scripts
Direct deployment tools for different scenarios:
```bash
./scripts/aws-deployment-unified.sh     # Unified deployment script
./scripts/aws-deployment-simple.sh     # Simple development deployment
./scripts/aws-deployment-ondemand.sh   # Production on-demand deployment
```

### Management Tools
Operations and maintenance utilities:
```bash
./tools/validate-config.sh      # Configuration validation
./tools/test-runner.sh          # Comprehensive testing
./tools/monitoring-setup.sh     # Monitoring configuration
./tools/install-deps.sh         # Dependency installation
```

### Development Utilities
Development and debugging tools:
```bash
./scripts/security-validation.sh   # Security checks
./scripts/validate-deployment.sh   # Deployment validation
./scripts/config-manager.sh        # Configuration management
```

## 🚀 Getting Started

### Prerequisites Check
```bash
# Check all dependencies
make check-deps

# Install missing dependencies
make install-deps

# Validate AWS configuration
./tools/validate-config.sh
```

### Basic Workflow
```bash
# 1. Setup environment
make setup

# 2. Deploy development stack
make deploy-simple STACK_NAME=my-dev-stack

# 3. Check status
make status STACK_NAME=my-dev-stack

# 4. View logs
make logs STACK_NAME=my-dev-stack

# 5. Cleanup when done
make destroy STACK_NAME=my-dev-stack
```

## 📖 Detailed Command Reference

### Setup and Dependencies
- [**Setup Commands**](setup.md) - Environment initialization and dependency management
- [**Validation Tools**](validation.md) - Configuration and security validation

### Deployment
- [**Deployment Commands**](deployment.md) - All deployment methods and options
- [**Terraform Commands**](terraform.md) - Infrastructure as Code operations

### Management and Operations  
- [**Management Commands**](management.md) - Status checking, logging, and maintenance
- [**Monitoring Tools**](monitoring.md) - Health checks and observability setup

### Development
- [**Development Tools**](development.md) - Testing, linting, and debugging utilities
- [**Makefile Reference**](makefile.md) - Complete Makefile command documentation

## 🔧 Advanced Usage

### Environment Variables
```bash
# Required for deployment
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1
export STACK_NAME=your-stack-name

# Optional configuration
export INSTANCE_TYPE=g4dn.xlarge
export DEPLOYMENT_TYPE=spot
export DEBUG=true
```

### Configuration Files
```bash
# Main configuration
.env                    # Local environment variables
config/environment.env  # Service configuration

# AWS configuration
~/.aws/credentials     # AWS credentials
~/.aws/config          # AWS CLI configuration
```

### Custom Deployments
```bash
# Custom instance type
INSTANCE_TYPE=g4dn.2xlarge make deploy-spot STACK_NAME=large-stack

# Custom region
AWS_REGION=eu-west-1 make deploy STACK_NAME=eu-stack

# Debug mode
DEBUG=true make deploy-simple STACK_NAME=debug-stack
```

## 🔍 Command Categories

### 🏗️ **Infrastructure Management**
Commands for deploying and managing cloud infrastructure:

| Command | Purpose | Required Args | Optional Args |
|---------|---------|---------------|---------------|
| `make deploy` | Smart deployment with instance selection | `STACK_NAME` | `INSTANCE_TYPE`, `REGION` |
| `make deploy-spot` | Cost-optimized spot instance deployment | `STACK_NAME` | `INSTANCE_TYPE` |
| `make deploy-ondemand` | Reliable on-demand deployment | `STACK_NAME` | `INSTANCE_TYPE` |
| `make deploy-simple` | Simple development deployment | `STACK_NAME` | - |
| `make destroy` | Clean up all resources | `STACK_NAME` | - |

### 📊 **Monitoring and Status**
Commands for checking system health and status:

| Command | Purpose | Required Args | Output |
|---------|---------|---------------|---------|
| `make status` | Check deployment status | `STACK_NAME` | Instance status, service health |
| `make logs` | View application logs | `STACK_NAME` | Real-time log stream |
| `make monitor` | Open monitoring dashboard | - | Monitoring URL |
| `make backup` | Create system backup | `STACK_NAME` | Backup confirmation |

### 🧪 **Testing and Validation**
Commands for testing and validation:

| Command | Purpose | Scope | Output |
|---------|---------|--------|--------|
| `make test` | Run all tests | Full test suite | Test results summary |
| `make test-unit` | Unit tests only | Individual components | Unit test results |
| `make test-integration` | Integration tests | Service interactions | Integration results |
| `make test-security` | Security tests | Security validations | Security scan results |
| `make validate` | Configuration validation | All configurations | Validation report |

### 🛠️ **Development Tools**
Commands for development and maintenance:

| Command | Purpose | Scope | Features |
|---------|---------|--------|----------|
| `make dev-setup` | Complete development setup | Full environment | Dependencies, validation, setup |
| `make lint` | Code linting | All source code | Style and quality checks |
| `make format` | Code formatting | All source code | Auto-formatting |
| `make clean` | Cleanup temporary files | Project directory | Cache and temp file removal |

## 📋 Script Reference

### Core Scripts

#### aws-deployment-unified.sh
Main deployment script with intelligent instance selection:
```bash
# Basic usage
./scripts/aws-deployment-unified.sh my-stack-name

# With options
./scripts/aws-deployment-unified.sh -t spot -r us-west-2 my-stack-name

# Validation only
./scripts/aws-deployment-unified.sh --validate-only my-stack-name

# Cleanup
./scripts/aws-deployment-unified.sh --cleanup my-stack-name
```

#### validate-config.sh
Configuration validation utility:
```bash
# Validate all configurations
./tools/validate-config.sh

# Validate specific configuration
./tools/validate-config.sh --config aws

# Verbose output
./tools/validate-config.sh --verbose
```

#### test-runner.sh
Comprehensive testing framework:
```bash
# Run all tests
./tools/test-runner.sh

# Run specific test category
./tools/test-runner.sh --category unit
./tools/test-runner.sh --category integration
./tools/test-runner.sh --category security

# Run with coverage
./tools/test-runner.sh --coverage
```

### Utility Scripts

#### install-deps.sh
Dependency installation and verification:
```bash
# Install all dependencies
./tools/install-deps.sh

# Check dependencies only
./tools/install-deps.sh --check-only

# Install specific category
./tools/install-deps.sh --category aws
./tools/install-deps.sh --category docker
```

#### security-validation.sh
Security checks and validation:
```bash
# Run all security checks
./scripts/security-validation.sh

# Check specific area
./scripts/security-validation.sh --check credentials
./scripts/security-validation.sh --check network
./scripts/security-validation.sh --check permissions
```

## 🔗 Integration with Other Tools

### AWS CLI Integration
```bash
# The scripts automatically use AWS CLI
aws configure                    # Configure AWS credentials
aws sts get-caller-identity     # Verify AWS access

# Scripts respect AWS CLI configuration
AWS_PROFILE=production make deploy STACK_NAME=prod-stack
```

### Docker Integration
```bash
# Docker is used for local development
docker-compose up -d            # Start services locally
docker-compose logs -f          # View service logs
docker-compose down             # Stop services
```

### Terraform Integration
```bash
# Alternative deployment using Terraform
make tf-init                    # Initialize Terraform
make tf-plan STACK_NAME=name    # Show deployment plan  
make tf-apply STACK_NAME=name   # Apply configuration
make tf-destroy STACK_NAME=name # Destroy resources
```

## 🚨 Error Handling and Troubleshooting

### Common Issues

**Permission Errors:**
```bash
# Fix script permissions
chmod +x scripts/*.sh
chmod +x tools/*.sh

# Or use make setup
make setup
```

**AWS Configuration Issues:**
```bash
# Check AWS configuration
aws sts get-caller-identity

# Reconfigure AWS CLI
aws configure

# Validate configuration
./tools/validate-config.sh --config aws
```

**Dependency Issues:**
```bash
# Check dependencies
make check-deps

# Install missing dependencies
make install-deps

# Manual dependency check
./tools/install-deps.sh --check-only
```

### Debug Mode
Enable debug output for troubleshooting:
```bash
# Enable debug for all commands
export DEBUG=true

# Debug specific deployment
DEBUG=true make deploy-simple STACK_NAME=debug-stack

# Debug script execution
DEBUG=true ./scripts/aws-deployment-unified.sh my-stack
```

### Log Locations
```bash
# Application logs
~/.ai-starter-kit/logs/

# Deployment logs  
/tmp/ai-starter-kit-deploy.log

# CloudWatch logs
# Available through AWS Console or CLI
aws logs describe-log-groups --log-group-name-prefix "/aws/ai-starter-kit"
```

## 📚 Additional Resources

### Documentation Links
- [**Deployment Guide**](../../guides/deployment/) - Detailed deployment procedures
- [**Configuration Guide**](../../guides/configuration/) - Configuration options and settings
- [**Troubleshooting Guide**](../../guides/troubleshooting/) - Problem resolution

### External Tools
- [**AWS CLI Documentation**](https://docs.aws.amazon.com/cli/) - AWS command-line interface
- [**Terraform Documentation**](https://www.terraform.io/docs/) - Infrastructure as Code
- [**Docker Documentation**](https://docs.docker.com/) - Container platform

### Quick Help
```bash
# Show help for any command
make help
./scripts/aws-deployment-unified.sh --help
./tools/test-runner.sh --help

# Get command-specific help
make deploy --help 2>/dev/null || echo "Use: make deploy STACK_NAME=name"
```

---

[**← Back to Documentation Hub**](../../README.md) | [**→ Deployment Commands**](deployment.md)

---

**CLI Version:** 2.0  
**Last Updated:** January 2025  
**Compatibility:** All AI Starter Kit deployments