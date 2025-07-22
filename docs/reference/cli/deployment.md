# Deployment Commands Reference

> Complete reference for all deployment-related CLI commands and scripts

This document covers all deployment commands, options, and usage patterns for the AI Starter Kit infrastructure deployment.

## 🚀 Quick Deployment Commands

### Makefile Deployment Commands

#### Basic Deployment
```bash
make deploy STACK_NAME=my-stack
```
Intelligent deployment with automatic instance type selection based on quotas and availability.

#### Deployment Types
```bash
make deploy-simple STACK_NAME=dev-stack      # Development: t3.medium instance
make deploy-spot STACK_NAME=cost-stack       # Cost-optimized: g4dn.xlarge spot
make deploy-ondemand STACK_NAME=prod-stack   # Production: g4dn.xlarge on-demand
```

#### Terraform Deployment
```bash
make tf-init                                  # Initialize Terraform
make tf-plan STACK_NAME=my-stack             # Show deployment plan
make tf-apply STACK_NAME=my-stack            # Apply configuration
```

## 📋 Deployment Script Reference

### aws-deployment-unified.sh

The main deployment script with comprehensive features and options.

#### Basic Usage
```bash
./scripts/aws-deployment-unified.sh [OPTIONS] STACK_NAME
```

#### Command Options

| Option | Description | Example |
|--------|-------------|---------|
| `-t, --type TYPE` | Deployment type (simple\|spot\|ondemand) | `-t spot` |
| `-r, --region REGION` | AWS region | `-r us-west-2` |
| `-i, --instance-type TYPE` | EC2 instance type | `-i g4dn.2xlarge` |
| `-k, --key-name NAME` | SSH key pair name | `-k my-keypair` |
| `-s, --subnet-id ID` | Subnet ID for deployment | `-s subnet-12345` |
| `-g, --security-group ID` | Security group ID | `-g sg-12345` |
| `--spot-price PRICE` | Maximum spot price | `--spot-price 0.50` |
| `--user-data FILE` | Custom user data script | `--user-data custom.sh` |
| `--tags KEY=VALUE` | Additional resource tags | `--tags Environment=prod` |
| `--validate-only` | Validate configuration without deploying | `--validate-only` |
| `--cleanup` | Remove all resources | `--cleanup` |
| `--dry-run` | Show what would be done | `--dry-run` |
| `-v, --verbose` | Verbose output | `-v` |
| `-h, --help` | Show help message | `-h` |

#### Usage Examples

**Simple Development Deployment:**
```bash
./scripts/aws-deployment-unified.sh -t simple dev-stack
```

**Cost-Optimized Spot Deployment:**
```bash
./scripts/aws-deployment-unified.sh -t spot -i g4dn.xlarge --spot-price 0.30 cost-stack
```

**Production On-Demand Deployment:**
```bash
./scripts/aws-deployment-unified.sh -t ondemand -r us-east-1 -i g4dn.2xlarge prod-stack
```

**Custom Configuration:**
```bash
./scripts/aws-deployment-unified.sh \
  -t spot \
  -r eu-west-1 \
  -i g4dn.xlarge \
  -k my-eu-key \
  --spot-price 0.40 \
  --tags Environment=staging,Team=ai \
  staging-stack
```

**Validation Only:**
```bash
./scripts/aws-deployment-unified.sh --validate-only my-stack
```

**Cleanup Resources:**
```bash
./scripts/aws-deployment-unified.sh --cleanup my-stack
```

### Deployment Type Scripts

#### aws-deployment-simple.sh
Basic development deployment with minimal resources:
```bash
./scripts/aws-deployment-simple.sh STACK_NAME [KEY_NAME]
```

**Features:**
- t3.medium instance (2 vCPU, 4GB RAM)
- Basic AI services (n8n, Ollama with CPU)
- Minimal cost (~$30/month)
- Quick setup (5 minutes)

#### aws-deployment-ondemand.sh
Production-ready deployment with reliable instances:
```bash
./scripts/aws-deployment-ondemand.sh STACK_NAME [INSTANCE_TYPE] [KEY_NAME]
```

**Features:**
- g4dn.xlarge or larger instance (GPU-enabled)
- Full AI stack with monitoring
- High availability and reliability
- Production-grade configuration

### Environment Configuration

#### Setting Deployment Variables
```bash
# Required environment variables
export AWS_REGION=us-east-1
export AWS_PROFILE=default
export STACK_NAME=my-stack

# Optional configuration
export INSTANCE_TYPE=g4dn.xlarge
export DEPLOYMENT_TYPE=spot
export SSH_KEY_NAME=my-keypair
export MAX_SPOT_PRICE=0.50
export SUBNET_ID=subnet-12345678
export SECURITY_GROUP_ID=sg-12345678

# Debug and logging
export DEBUG=true
export LOG_LEVEL=info
export LOG_FILE=/tmp/deployment.log
```

#### Configuration Files
```bash
# Local environment configuration
.env                    # Local variables (not committed)
.env.example           # Example configuration template

# Service configuration
config/environment.env  # Service-specific settings
config/aws.env         # AWS-specific configuration
```

## 🔧 Advanced Deployment Options

### Custom Instance Configuration

#### GPU Instance Types
```bash
# NVIDIA T4 GPU instances
make deploy-spot STACK_NAME=gpu-stack INSTANCE_TYPE=g4dn.xlarge
make deploy-spot STACK_NAME=gpu-large INSTANCE_TYPE=g4dn.2xlarge

# NVIDIA A10G GPU instances (newer, more powerful)
make deploy-spot STACK_NAME=a10g-stack INSTANCE_TYPE=g5.xlarge
```

#### CPU-Only Instances
```bash
# Development instances
make deploy-simple STACK_NAME=cpu-dev INSTANCE_TYPE=t3.medium
make deploy-simple STACK_NAME=cpu-large INSTANCE_TYPE=t3.large

# Compute-optimized instances
make deploy-ondemand STACK_NAME=compute INSTANCE_TYPE=c5.2xlarge
```

### Multi-Region Deployment

#### Deploy to Different Regions
```bash
# US East (Virginia) - lowest cost
AWS_REGION=us-east-1 make deploy-spot STACK_NAME=us-east-stack

# US West (Oregon) - good for West Coast
AWS_REGION=us-west-2 make deploy-spot STACK_NAME=us-west-stack

# Europe (Ireland) - GDPR compliance
AWS_REGION=eu-west-1 make deploy-spot STACK_NAME=eu-stack

# Asia Pacific (Singapore)
AWS_REGION=ap-southeast-1 make deploy-spot STACK_NAME=apac-stack
```

#### Cross-Region Considerations
```bash
# Check available instance types in region
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --region us-west-2 \
  --filters Name=instance-type,Values=g4dn.xlarge

# Check spot pricing
aws ec2 describe-spot-price-history \
  --instance-types g4dn.xlarge \
  --region us-west-2 \
  --max-items 5
```

### Spot Instance Configuration

#### Optimal Spot Pricing
```bash
# Check current spot prices
./scripts/check-spot-prices.sh g4dn.xlarge us-east-1

# Deploy with custom spot price
./scripts/aws-deployment-unified.sh \
  -t spot \
  -i g4dn.xlarge \
  --spot-price 0.25 \
  spot-stack
```

#### Spot Fleet Configuration
```bash
# Multiple instance types for better availability
./scripts/aws-deployment-unified.sh \
  -t spot \
  --instance-types g4dn.xlarge,g4dn.2xlarge,g5.xlarge \
  --spot-price 0.50 \
  fleet-stack
```

### Network Configuration

#### Custom VPC Deployment
```bash
# Use existing VPC and subnet
./scripts/aws-deployment-unified.sh \
  -t spot \
  --vpc-id vpc-12345678 \
  --subnet-id subnet-87654321 \
  --security-group sg-abcdef12 \
  vpc-stack
```

#### Security Group Configuration
```bash
# Create custom security group
aws ec2 create-security-group \
  --group-name ai-starter-kit-custom \
  --description "Custom AI Starter Kit security group"

# Add SSH access
aws ec2 authorize-security-group-ingress \
  --group-id sg-12345678 \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# Add service ports
aws ec2 authorize-security-group-ingress \
  --group-id sg-12345678 \
  --protocol tcp \
  --port 5678 \
  --cidr 0.0.0.0/0  # n8n

# Use in deployment
./scripts/aws-deployment-unified.sh \
  -g sg-12345678 \
  custom-stack
```

## 📊 Deployment Monitoring

### Real-Time Deployment Status
```bash
# Monitor deployment progress
make status STACK_NAME=my-stack

# Watch deployment logs
tail -f /tmp/ai-starter-kit-deploy.log

# Check CloudFormation status
aws cloudformation describe-stacks \
  --stack-name ai-starter-kit-my-stack
```

### Health Checks During Deployment
```bash
# Automated health checks
./tools/validate-deployment.sh my-stack

# Manual service checks
ssh -i my-stack-key.pem ubuntu@INSTANCE_IP 'docker ps'
ssh -i my-stack-key.pem ubuntu@INSTANCE_IP 'docker-compose logs'
```

### Deployment Validation
```bash
# Validate before deployment
./scripts/aws-deployment-unified.sh --validate-only my-stack

# Check AWS quotas
./scripts/check-quotas.sh

# Verify prerequisites
make check-deps
```

## 🚨 Deployment Troubleshooting

### Common Deployment Issues

#### Insufficient Quotas
```bash
# Check EC2 quotas
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A  # Running On-Demand instances

# Request quota increase
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --desired-value 10
```

#### Spot Instance Interruption
```bash
# Check spot interruption status
aws ec2 describe-spot-instance-requests \
  --filters Name=state,Values=active

# Handle interruption
./scripts/aws-deployment-unified.sh \
  --handle-interruption \
  my-stack
```

#### Network Connectivity Issues
```bash
# Test connectivity
ping INSTANCE_IP
telnet INSTANCE_IP 22
telnet INSTANCE_IP 5678

# Check security groups
aws ec2 describe-security-groups \
  --group-ids sg-12345678
```

### Debug Mode Deployment
```bash
# Enable debug output
DEBUG=true make deploy-spot STACK_NAME=debug-stack

# Verbose script execution
./scripts/aws-deployment-unified.sh -v -t spot debug-stack

# Step-by-step deployment
./scripts/aws-deployment-unified.sh --interactive my-stack
```

### Recovery and Rollback
```bash
# Rollback failed deployment
./scripts/aws-deployment-unified.sh --rollback my-stack

# Clean up failed resources
./scripts/aws-deployment-unified.sh --cleanup --force my-stack

# Retry deployment
./scripts/aws-deployment-unified.sh --retry my-stack
```

## 💰 Cost Optimization

### Cost-Effective Deployment Strategies
```bash
# Spot instances for development
make deploy-spot STACK_NAME=dev-stack

# Smaller instances for testing
make deploy-simple STACK_NAME=test-stack INSTANCE_TYPE=t3.small

# Auto-scaling configuration
./scripts/aws-deployment-unified.sh \
  --auto-scaling \
  --min-instances 1 \
  --max-instances 3 \
  scaling-stack
```

### Cost Monitoring
```bash
# Estimate deployment costs
make cost-estimate STACK_NAME=my-stack HOURS=24

# Monitor actual costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-02 \
  --granularity DAILY \
  --metrics BlendedCost
```

### Resource Cleanup
```bash
# Stop instances (preserve data)
./scripts/aws-deployment-unified.sh --stop my-stack

# Start stopped instances
./scripts/aws-deployment-unified.sh --start my-stack

# Complete cleanup
make destroy STACK_NAME=my-stack
```

## 🔒 Security Considerations

### Secure Deployment Practices
```bash
# Use specific security groups
./scripts/aws-deployment-unified.sh \
  -g sg-restrictive \
  --tags Security=high \
  secure-stack

# Enable encryption
./scripts/aws-deployment-unified.sh \
  --encrypt-ebs \
  --encrypt-efs \
  encrypted-stack
```

### Access Control
```bash
# Restrict SSH access
aws ec2 authorize-security-group-ingress \
  --group-id sg-12345678 \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32  # Your specific IP only

# Use IAM roles
./scripts/aws-deployment-unified.sh \
  --iam-role arn:aws:iam::account:role/AI-Starter-Kit-Role \
  iam-stack
```

### Credential Management
```bash
# Use AWS IAM roles (recommended)
aws sts assume-role \
  --role-arn arn:aws:iam::account:role/DeploymentRole \
  --role-session-name ai-starter-kit-deployment

# Rotate SSH keys
aws ec2 create-key-pair \
  --key-name new-keypair \
  --query 'KeyMaterial' \
  --output text > new-keypair.pem
```

---

[**← Back to CLI Overview**](README.md) | [**→ Management Commands**](management.md)

---

**Last Updated:** January 2025  
**Compatibility:** All deployment types and regions