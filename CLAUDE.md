# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

### Testing and Validation
```bash
# Test intelligent selection without AWS deployment
./scripts/simple-demo.sh

# Comprehensive testing with cross-region analysis
./scripts/test-intelligent-selection.sh --comprehensive

# Test specific scenarios
./scripts/test-intelligent-selection.sh --cross-region
./scripts/test-intelligent-selection.sh --budget 1.50

# Validate deployment after launch
./scripts/validate-deployment.sh

# Validate deployment with verbose output
./scripts/validate-deployment.sh -v -t 300

# Advanced health checks
make health-check STACK_NAME=my-stack
make health-check-advanced STACK_NAME=my-stack
```

## Architecture Patterns

### Shared Library Architecture
The project uses a modular architecture with shared libraries in `/lib/`:

- **aws-deployment-common.sh**: Common AWS operations, logging, and error handling
- **spot-instance.sh**: Spot instance management and pricing optimization
- Deployment scripts source these libraries for consistent behavior across all deployment types

### Unified Deployment Strategy
The `aws-deployment-unified.sh` script serves as the main orchestrator supporting multiple deployment types:
- **Spot**: Cost-optimized with intelligent spot instance selection
- **On-demand**: Reliable instances with guaranteed availability  
- **Simple**: Quick development deployments

### Testing-First Development
Test deployment logic without AWS costs using validation scripts:
- `./scripts/simple-demo.sh` - Basic intelligent selection demo
- `./scripts/test-intelligent-selection.sh` - Comprehensive testing with cross-region analysis
- `./test-alb-cloudfront.sh` - ALB/CloudFront functionality validation

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

## Cursor Rules Integration

The project includes sophisticated Cursor IDE rules for AWS development:

### AWS Architecture Principles (`.cursor/rules/aws.mdc`)
- Well-Architected Framework implementation
- Service selection decision matrices
- Scale-adaptive recommendations (startup/midsize/enterprise)
- Infrastructure as Code best practices
- Security-first patterns with cost optimization

### n8n MCP Integration (`.cursor/rules/n8n-mcp.mdc`)
- Workflow validation and testing patterns
- AI tool integration guidelines
- Pre and post-deployment validation strategies
- Incremental update patterns for efficiency

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

### CPU Allocation (4 vCPUs total)
- postgres: 1.5 vCPUs (37.5%)
- n8n: 1.0 vCPUs (25%)
- ollama: 2.5 vCPUs (62.5%) - Primary compute
- qdrant: 1.5 vCPUs (37.5%)
- monitoring: 0.5 vCPUs (12.5%)

### Memory Allocation (16GB total)
- ollama: 10GB (62.5%) - Primary memory user
- postgres: 3GB (18.75%)
- qdrant: 3GB (18.75%)
- monitoring: 512MB (3.2%)

### GPU Memory (T4 16GB)
- ollama: 14.4GB (90%)
- system reserve: 1.6GB (10%)

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

## Important Notes

- This project requires AWS credentials and appropriate permissions
- GPU instances require adequate AWS quotas in your target region
- The system is optimized for cost efficiency while maintaining performance
- Always validate configurations before deployment to production
- Use the test scripts to verify deployment logic without incurring AWS costs