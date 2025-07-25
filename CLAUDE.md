# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Reference

### Essential Commands
```bash
# Setup and validate environment
make setup                          # Complete setup with security
make test                          # Run all tests before deployment
make lint                          # Check code quality

# Development workflow  
make deploy-simple STACK_NAME=test  # Quick dev deployment
make health-check STACK_NAME=test   # Verify services
make destroy STACK_NAME=test        # Clean up resources

# Testing without AWS costs
./scripts/simple-demo.sh            # Test intelligent selection
./tools/test-runner.sh unit         # Run specific test category
```

### File Patterns & Architecture
- **Shared Libraries**: `/lib/*.sh` - Common functions sourced by all scripts
  - Always source `aws-deployment-common.sh` and `error-handling.sh`
- **Deployment Scripts**: `/scripts/aws-deployment-*.sh` - Main deployment orchestrators  
- **Testing**: `/tests/` (Python pytest) + `/tools/test-runner.sh` (comprehensive runner)
- **Configuration**: `/config/` - Environment-specific settings and versions

## Project Overview

This is an AI-powered starter kit for GPU-optimized AWS deployment featuring intelligent infrastructure automation, cost optimization, and enterprise-grade AI workflows. The project is designed for deploying production-ready AI workloads on AWS with 70% cost savings through intelligent spot instance management and cross-region analysis.

## Core Architecture

- **Infrastructure**: AWS-native deployment with EFS persistence, CloudFront CDN, Auto Scaling Groups
- **AI Stack**: n8n workflows + Ollama (local LLM inference) + Qdrant (vector database) + Crawl4AI (web scraping)
- **Deployment**: Multi-architecture support (Intel x86_64 and ARM64 Graviton2) with intelligent GPU selection
- **Cost Optimization**: Real-time pricing analysis, spot instance management, and resource rightsizing

## Security Features

### Security Validation
```bash
# Run comprehensive security audit
./scripts/security-check.sh

# Setup and validate secrets
make setup-secrets                    # Setup all required secrets
make security-check                   # Run security validation
make security-validate               # Complete security setup and validation
make rotate-secrets                  # Rotate all secrets

# Validate specific configurations
source scripts/security-validation.sh
validate_aws_region us-east-1
validate_instance_type g4dn.xlarge
validate_stack_name my-stack
```

### Credential Management
- Demo credential files include security warnings
- All secrets use 256-bit entropy generation
- CORS and trusted hosts configured with specific domains
- Enhanced .gitignore protects sensitive files

## Development Commands

### Critical Development Workflow
**ALWAYS follow this pattern when making changes:**
1. `make setup` - Initialize environment (security configurations)
2. `make test` - **MANDATORY** before any deployment
3. `make lint` - Validate code quality 
4. `./scripts/simple-demo.sh` - Test deployment logic without AWS costs
5. `make deploy-simple STACK_NAME=test` - Deploy to test environment
6. `make health-check STACK_NAME=test` - Validate deployment
7. `make destroy STACK_NAME=test` - Clean up test resources

### Makefile-Driven Development
The project uses Make for standardized development workflows:

```bash
# Essential development setup
make setup                    # Set up development environment
make dev-setup               # Full setup with dependencies
make help                    # Show all available commands

# Development workflow
make validate                # Validate all configurations
make test                   # Run all tests
make lint                   # Run linting on all code
make clean                  # Clean temporary files

# Deployment commands (require STACK_NAME)
make deploy STACK_NAME=my-stack              # Deploy with validation
make deploy-spot STACK_NAME=my-stack         # Deploy spot instances
make deploy-simple STACK_NAME=my-stack       # Deploy development environment
make status STACK_NAME=my-stack              # Check deployment status
make destroy STACK_NAME=my-stack             # Destroy infrastructure

# Testing
make test-unit              # Run unit tests only
make test-integration       # Run integration tests only
make test-security          # Run security tests

# Utilities
make cost-estimate STACK_NAME=my-stack HOURS=24  # Estimate costs
make docs                   # Generate documentation

# Parameter Store and troubleshooting
./scripts/setup-parameter-store.sh setup         # Setup Parameter Store
./scripts/fix-deployment-issues.sh STACK REGION  # Fix deployment issues
```

### Local Development
```bash
# Start CPU-only local development environment
docker compose --profile cpu up

# Start GPU-optimized environment (requires GPU)
docker compose -f docker-compose.gpu-optimized.yml up
```

### AWS Deployment Commands
```bash
# Intelligent deployment with auto-selection
./scripts/aws-deployment.sh

# Cross-region analysis for optimal pricing
./scripts/aws-deployment.sh --cross-region

# Budget-constrained deployment
./scripts/aws-deployment.sh --max-spot-price 1.50

# Simple on-demand deployment
./scripts/aws-deployment-simple.sh

# Full on-demand deployment
./scripts/aws-deployment-ondemand.sh

# Test deployment logic without creating resources
./scripts/test-intelligent-selection.sh --comprehensive

# Check AWS quotas before deployment
./scripts/check-quotas.sh

# Simple demo of intelligent selection
./scripts/simple-demo.sh
```

### Cost Management
```bash
# Generate cost optimization report
python3 scripts/cost-optimization.py --action report

# Monitor optimization in real-time
tail -f /var/log/cost-optimization.log
```

### Testing Strategy & Commands

**Test Categories (via ./tools/test-runner.sh):**
- `unit` - Python unit tests with pytest (tests/unit/)
- `integration` - Component interaction tests (tests/integration/)  
- `security` - Vulnerability scans (bandit, safety, trivy)
- `performance` - Benchmarks and performance analysis
- `deployment` - Script validation and Terraform checks
- `smoke` - Quick validation tests for CI/CD

```bash
# Primary test commands
make test                                  # Run all tests (uses test-runner.sh)
./tools/test-runner.sh unit security      # Run specific categories
./tools/test-runner.sh --report           # Generate HTML test report
./tools/test-runner.sh --coverage unit    # Run with coverage reports

# Testing without AWS costs (IMPORTANT)
./scripts/simple-demo.sh                  # Test intelligent selection logic
./scripts/test-intelligent-selection.sh --comprehensive  # Cross-region analysis
./scripts/test-intelligent-selection.sh --budget 1.50    # Budget-constrained testing

# Deployment validation
./scripts/validate-deployment.sh                         # Basic validation
./scripts/validate-deployment.sh -v -t 300              # Verbose with timeout
make health-check STACK_NAME=my-stack                   # Service health checks
make health-check-advanced STACK_NAME=my-stack          # Comprehensive diagnostics

# Infrastructure testing  
./tests/test-docker-config.sh      # Docker configuration validation
./tests/test-image-config.sh       # Container image validation
./tests/test-alb-cloudfront.sh     # ALB/CloudFront functionality
```

## Architecture Patterns

### Code Organization & Patterns

**When editing ANY deployment script, you MUST understand this pattern:**

#### Shared Library System
All deployment scripts follow this standardized sourcing pattern:
```bash
# ALWAYS start deployment scripts with this pattern
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Required libraries - source these in order
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"  # Logging, prerequisites
source "$PROJECT_ROOT/lib/error-handling.sh"        # Error handling, cleanup
```

#### Library Functions Reference
- **aws-deployment-common.sh**: 
  - Logging: `log()`, `error()`, `success()`, `warning()`, `info()`
  - Prerequisites: `check_common_prerequisites()`
  - Progress tracking: `step()`, `progress()`
- **error-handling.sh**: Centralized error handling and cleanup functions  
- **spot-instance.sh**: Spot instance management and pricing optimization
- **aws-config.sh**: Configuration defaults and environment management
- **ondemand-instance.sh**: On-demand instance specific operations
- **simple-instance.sh**: Simple deployment specific functions

### Unified Deployment Strategy
The `aws-deployment-unified.sh` script serves as the main orchestrator supporting multiple deployment types:
- **Spot**: Cost-optimized with intelligent spot instance selection
- **On-demand**: Reliable instances with guaranteed availability  
- **Simple**: Quick development deployments

### Testing-First Development
Test deployment logic without AWS costs using validation scripts:
- `./scripts/simple-demo.sh` - Basic intelligent selection demo
- `./scripts/test-intelligent-selection.sh` - Comprehensive testing with cross-region analysis
- `./tests/test-alb-cloudfront.sh` - ALB/CloudFront functionality validation
- **Python Test Framework**: pytest-based unit and integration tests in `/tests/`
- **Configuration Testing**: Docker and image validation scripts
- **Security Testing**: Automated security validation with `/tests/unit/test_security_validation.py`

### Development Workflow
The recommended development workflow follows this pattern:
1. **Setup**: `make setup` - Initialize environment with security configurations
2. **Development**: Edit code and configurations
3. **Testing**: `make test` - Run comprehensive test suite before deployment
4. **Validation**: `./scripts/simple-demo.sh` - Test deployment logic without AWS costs
5. **Deployment**: `make deploy-simple STACK_NAME=test` - Deploy to development environment
6. **Verification**: `make health-check STACK_NAME=test` - Validate deployment health
7. **Cleanup**: `make destroy STACK_NAME=test` - Clean up test resources

### Terraform Infrastructure as Code
Alternative to shell scripts for infrastructure management:

```bash
# Terraform workflow
make tf-init                         # Initialize Terraform
make tf-plan STACK_NAME=my-stack     # Show infrastructure plan  
make tf-apply STACK_NAME=my-stack    # Apply infrastructure
make tf-destroy STACK_NAME=my-stack  # Destroy infrastructure
```

The Terraform configuration (`terraform/main.tf`) provides:
- **Comprehensive Infrastructure**: VPC, security groups, IAM roles, EFS, ALB
- **Multi-deployment Support**: Spot instances, on-demand instances
- **Advanced Features**: CloudWatch monitoring, Secrets Manager integration
- **Security**: Encrypted EBS/EFS, KMS key management, least-privilege IAM

## Key Components

### Deployment Scripts
- `aws-deployment-unified.sh`: **Main orchestrator** supporting spot/ondemand/simple deployment types
- `aws-deployment.sh`: Intelligent deployment with auto-selection and cross-region analysis
- `aws-deployment-simple.sh`: Simple on-demand deployment
- `aws-deployment-ondemand.sh`: Full on-demand deployment with guaranteed instances
- `test-intelligent-selection.sh`: Test deployment logic without creating AWS resources

#### Unified Deployment Usage
```bash
# The main deployment script with full flexibility
./scripts/aws-deployment-unified.sh [OPTIONS] STACK_NAME

# Key options:
-t, --type TYPE         # spot|ondemand|simple (default: spot)
-e, --environment ENV   # development|staging|production
-b, --budget-tier TIER  # low|medium|high
--validate-only         # Validate without deploying
--cleanup              # Clean up existing resources
```

### Docker Configuration
- `docker-compose.gpu-optimized.yml`: Production GPU configuration with advanced optimizations
- **Resource Management**: Precisely tuned for g4dn.xlarge (85% CPU/memory utilization target)
- **Security**: Docker secrets integration, encrypted storage, non-root containers
- **Performance**: Connection pooling, GPU memory optimization, health checks
- **Monitoring**: GPU monitoring, health checks, comprehensive logging

### AI Services Integration
- **n8n**: Visual workflow automation platform with AI agent orchestration
- **Ollama**: Local LLM inference (DeepSeek-R1:8B, Qwen2.5-VL:7B models)
- **Qdrant**: High-performance vector database for embeddings
- **Crawl4AI**: Intelligent web scraping with LLM-based extraction

### Database Schema
- PostgreSQL with comprehensive agent registry and task queue system
- Supports multi-agent workforce coordination with member awareness
- Includes workflow execution tracking and performance metrics

## Intelligent Deployment Features

### Auto-Selection Algorithm
The deployment system automatically selects optimal configurations based on:
- Real-time spot pricing across multiple regions and availability zones
- Price/performance ratios for different instance types
- AMI availability and compatibility
- Budget constraints and cost optimization goals

### Multi-Architecture Support
- **Intel x86_64**: g4dn.xlarge, g4dn.2xlarge (NVIDIA T4 GPU)
- **ARM64 Graviton2**: g5g.xlarge, g5g.2xlarge (NVIDIA T4G GPU)
- Automatic architecture detection and optimization

### Cost Optimization
- Real-time spot pricing analysis via AWS Pricing API
- 70-75% cost savings with intelligent spot instance management
- Auto-scaling based on GPU utilization
- Cross-region analysis for optimal pricing

## Development Guidelines & Rules

### Cursor IDE Integration
The project includes sophisticated development rules:

#### AWS Architecture Principles (`.cursor/rules/aws.mdc`)
- Well-Architected Framework implementation (6 pillars)
- Service selection decision matrices by scale (startup/midsize/enterprise)
- Infrastructure as Code patterns for CDK, Terraform, CloudFormation
- Security-first patterns with cost optimization
- Multi-environment deployment strategies with proper validation

#### n8n Workflow Development (`.cursor/rules/n8n-mcp.mdc`)
- **MANDATORY Validation Pattern**: Always validate before building workflows
  1. `validate_node_minimal()` - Check required fields
  2. `validate_node_operation()` - Full configuration validation  
  3. `validate_workflow()` - Complete workflow validation
- AI tool integration guidelines (ANY node can be an AI tool)
- Pre and post-deployment validation strategies
- Incremental update patterns for efficiency (80-90% token savings with diffs)

## Environment Configuration

### Required AWS SSM Parameters
```bash
/aibuildkit/OPENAI_API_KEY          # OpenAI API key
/aibuildkit/n8n/ENCRYPTION_KEY      # n8n encryption key
/aibuildkit/POSTGRES_PASSWORD       # Database password
/aibuildkit/WEBHOOK_URL             # Webhook base URL
```

### Optional Parameters
```bash
/aibuildkit/n8n/CORS_ENABLE         # CORS settings
/aibuildkit/n8n/CORS_ALLOWED_ORIGINS # Allowed origins
/aibuildkit/n8n/COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE # Enable community packages
/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET # JWT secret
```

## Service Endpoints (After Deployment)

- **n8n Workflows**: `https://n8n.geuse.io` or `http://YOUR-IP:5678`
- **Qdrant Vector DB**: `https://qdrant.geuse.io` or `http://YOUR-IP:6333`
- **Ollama LLM**: `http://YOUR-IP:11434`
- **Crawl4AI**: `http://YOUR-IP:11235`

## Resource Allocation (g4dn.xlarge)

### CPU Allocation (4 vCPUs total, targeting 85% utilization)
- ollama: 2.0 vCPUs (50%) - Primary compute user
- postgres: 0.4 vCPUs (10%)
- n8n: 0.4 vCPUs (10%)
- qdrant: 0.4 vCPUs (10%)
- crawl4ai: 0.4 vCPUs (10%)
- monitoring: 0.3 vCPUs (7.5%)

### Memory Allocation (16GB total)
- ollama: 6GB (37.5%) - Primary memory user
- postgres: 2GB (12.5%)
- qdrant: 2GB (12.5%)
- n8n: 1.5GB (9.4%)
- crawl4ai: 1.5GB (9.4%)
- system reserve: ~2.5GB (15.6%)

### GPU Memory (T4 16GB)
- ollama: ~13.6GB (85% utilization)
- system reserve: ~2.4GB (15%)

## Troubleshooting

### Critical Deployment Issues

#### Disk Space Exhaustion
**Symptoms**: "no space left on device" during Docker image pulls
```bash
# Quick fix - run the deployment fix script
scp scripts/fix-deployment-issues.sh ubuntu@YOUR-IP:/tmp/
ssh -i your-key.pem ubuntu@YOUR-IP "sudo /tmp/fix-deployment-issues.sh STACK-NAME"

# Manual disk cleanup
ssh -i your-key.pem ubuntu@YOUR-IP
sudo docker system prune -af --volumes
sudo apt-get clean && sudo apt-get autoremove -y
df -h  # Check available space
```

#### EFS Not Mounting
**Symptoms**: "EFS_DNS variable is not set" warnings
```bash
# Setup EFS and Parameter Store integration
./scripts/setup-parameter-store.sh setup --region YOUR-REGION
./scripts/fix-deployment-issues.sh STACK-NAME YOUR-REGION

# Verify EFS mounting
ssh -i your-key.pem ubuntu@YOUR-IP "df -h | grep efs"
```

#### Missing Environment Variables
**Symptoms**: Variables defaulting to blank strings
```bash
# Setup Parameter Store first
./scripts/setup-parameter-store.sh setup

# Add your API keys (example)
aws ssm put-parameter --name '/aibuildkit/OPENAI_API_KEY' \
    --value 'your-actual-key' --type SecureString --overwrite

# Validate parameters
./scripts/setup-parameter-store.sh validate
```

### Common Issues
- **Spot instance not launching**: Check spot price limits and availability
- **InvalidAMIID.Malformed errors**: Use `--cross-region` for better region selection
- **GPU not detected**: Verify NVIDIA drivers and Docker GPU runtime
- **Services failing to start**: Check disk space and environment variables first

### Debug Commands
```bash
# Test intelligent selection (no AWS required)
./scripts/simple-demo.sh

# Fix deployment issues on running instance  
./scripts/fix-deployment-issues.sh STACK-NAME REGION

# Check service status
docker compose -f docker-compose.gpu-optimized.yml ps

# View logs
docker compose -f docker-compose.gpu-optimized.yml logs ollama

# Monitor GPU usage
nvidia-smi

# Check disk usage
df -h
du -sh /var/lib/docker

# Verify AWS resources
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"

# Parameter Store management
./scripts/setup-parameter-store.sh list
./scripts/setup-parameter-store.sh validate
```

## Testing Framework

### Test-First Development Approach
**CRITICAL: Always run tests before any deployment or changes**

#### Test Architecture
The project uses a layered testing strategy:
1. **Python Tests** (pytest) - `/tests/unit/` and `/tests/integration/`
2. **Shell Script Tests** - Infrastructure validation scripts in `/tests/`
3. **Comprehensive Test Runner** - `./tools/test-runner.sh` orchestrates all categories

#### Test Categories & Usage
```bash
# Primary workflow - run before ANY deployment
make test                                    # Run all tests via test-runner.sh

# Granular testing by category
./tools/test-runner.sh unit                  # Python unit tests (pytest)
./tools/test-runner.sh integration          # Component interaction tests  
./tools/test-runner.sh security             # Vulnerability scans (bandit, safety, trivy)
./tools/test-runner.sh performance          # Benchmarks and analysis
./tools/test-runner.sh deployment           # Script validation and Terraform checks
./tools/test-runner.sh smoke                # Quick validation for CI/CD

# Advanced test runner options
./tools/test-runner.sh unit security --report     # Multiple categories with HTML report
./tools/test-runner.sh --coverage unit            # Coverage analysis
./tools/test-runner.sh --environment staging      # Environment-specific testing
```

#### Test Reports & Outputs
- **Location**: `./test-reports/` directory
- **Key Files**: 
  - `test-summary.html` - Human-readable comprehensive report
  - `test-results.json` - Machine-readable results for CI/CD
  - `coverage/` directory - Code coverage analysis
- **Security Scans**: Individual JSON/text reports for each tool

#### Infrastructure Testing (No AWS Costs)
```bash
# IMPORTANT: Test deployment logic without creating AWS resources
./scripts/simple-demo.sh                    # Basic intelligent selection demo
./scripts/test-intelligent-selection.sh --comprehensive  # Full testing suite

# Configuration validation
./tests/test-docker-config.sh              # Docker Compose validation
./tests/test-image-config.sh               # Container image validation  
./tests/test-alb-cloudfront.sh             # ALB/CloudFront functionality
```

## Critical Development Guidelines

### Before Making ANY Changes
1. **MUST** run `make test` before deployment - this is non-negotiable
2. **MUST** use `./scripts/simple-demo.sh` to test deployment logic without AWS costs
3. **MUST** follow the shared library sourcing pattern for any new deployment scripts
4. **MUST** run `make security-check` before production deployments

### Key Requirements & Constraints  
- AWS credentials and appropriate permissions required for deployments
- GPU instances require adequate AWS quotas in target regions
- Always validate configurations before production deployment
- **Cost Efficiency Focus**: System optimized for 70% cost savings through intelligent spot management
- **Test-First**: Never skip testing - use test scripts to verify logic without AWS costs

### File Location Reference for Quick Navigation
```bash
# Key files for development
/lib/                          # Shared functions - ALWAYS source these
/scripts/aws-deployment-*.sh   # Main deployment orchestrators
/tools/test-runner.sh          # Comprehensive test orchestration
/tests/                        # Python pytest + shell validation scripts
/config/                       # Environment and version configurations
/.cursor/rules/                # IDE development guidelines
```