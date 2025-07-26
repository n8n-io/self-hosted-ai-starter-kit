# Security Guide

This guide covers security best practices and configurations for the GeuseMaker deployment.

## Table of Contents

- [Overview](#overview)
- [Secrets Management](#secrets-management)
- [Network Security](#network-security)
- [Data Encryption](#data-encryption)
- [Access Control](#access-control)
- [Monitoring & Auditing](#monitoring--auditing)
- [Security Checklist](#security-checklist)

## Overview

GeuseMaker implements multiple layers of security:

1. **Secrets Management**: Docker secrets and AWS Secrets Manager
2. **Network Isolation**: VPC, security groups, and private subnets
3. **Encryption**: At-rest and in-transit encryption
4. **Access Control**: IAM roles, least privilege principles
5. **Monitoring**: CloudWatch, GuardDuty integration

## Secrets Management

### Initial Setup

Run the secrets setup script before first deployment:

```bash
./scripts/setup-secrets.sh setup
```

This creates:
- PostgreSQL password
- n8n encryption key
- n8n JWT secret
- Admin password

### Docker Secrets

Secrets are mounted as files, not environment variables:

```yaml
services:
  postgres:
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
    secrets:
      - postgres_password
```

### AWS Secrets Manager (Production)

For production deployments, use AWS Secrets Manager:

```bash
# Setup AWS secrets
./scripts/setup-secrets.sh aws-setup my-stack us-east-1

# Deploy with Secrets Manager
terraform apply -var="enable_secrets_manager=true"
```

### Rotating Secrets

```bash
# Backup current secrets
./scripts/setup-secrets.sh backup

# Regenerate all secrets
./scripts/setup-secrets.sh regenerate

# Update running services
docker-compose down
docker-compose up -d
```

## Network Security

### Security Groups

Default security group rules:

| Port | Service | Source | Description |
|------|---------|--------|-------------|
| 22 | SSH | Your IP | Management access |
| 5678 | n8n | Your IP | Workflow interface |
| 11434 | Ollama | Internal | LLM API |
| 6333 | Qdrant | Internal | Vector DB |
| 5432 | PostgreSQL | Internal | Database |

### Restricting Access

```bash
# Deploy with restricted access
./scripts/aws-deployment.sh \
  --stack-name my-stack \
  --allowed-cidr "203.0.113.0/24"
```

### Private Deployment

For internal-only access:

```hcl
# terraform.tfvars
enable_load_balancer = false
allowed_cidr_blocks = ["10.0.0.0/8"]
```

## Data Encryption

### Encryption at Rest

All data is encrypted at rest:

- **EFS**: KMS encryption with key rotation
- **EBS**: Encrypted root volumes
- **PostgreSQL**: Encrypted storage
- **Secrets**: Encrypted in AWS Secrets Manager

### Encryption in Transit

- **HTTPS**: SSL/TLS for web traffic
- **Database**: SSL connections enforced
- **Internal**: Service-to-service TLS

### KMS Key Management

```bash
# List KMS keys
aws kms list-keys --region us-east-1

# Rotate keys manually
aws kms enable-key-rotation --key-id <key-id>
```

## Access Control

### IAM Roles

The deployment creates minimal IAM roles:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "kms:Decrypt"
      ],
      "Resource": ["arn:aws:secretsmanager:*:*:secret:GeuseMaker/*"]
    }
  ]
}
```

### Service Accounts

Each service runs with minimal privileges:

- PostgreSQL: User ID 70 (postgres)
- n8n: User ID 1000
- No root access
- Read-only root filesystem where possible

### CORS Configuration

Update CORS for your domain:

```yaml
# docker-compose.yml
N8N_CORS_ALLOWED_ORIGINS: "https://your-domain.com"
```

## Monitoring & Auditing

### CloudWatch Logs

All services log to CloudWatch:

```bash
# View logs
aws logs tail /aws/GeuseMaker/my-stack --follow

# Search logs
aws logs filter-log-events \
  --log-group-name /aws/GeuseMaker/my-stack \
  --filter-pattern "ERROR"
```

### Security Alerts

Enable GuardDuty for threat detection:

```hcl
# terraform.tfvars
enable_guardduty = true
enable_flow_logs = true
```

### Audit Trail

CloudTrail captures all API calls:

- EC2 instance launches
- Security group changes
- Secret access
- KMS key usage

## Security Checklist

### Pre-Deployment

- [ ] Run security validation: `make security-check`
- [ ] Generate secrets: `./scripts/setup-secrets.sh setup`
- [ ] Review security groups
- [ ] Update CORS origins
- [ ] Set strong passwords

### Post-Deployment

- [ ] Verify encryption enabled
- [ ] Check security group rules
- [ ] Test access restrictions
- [ ] Review CloudWatch logs
- [ ] Enable monitoring alerts

### Ongoing Maintenance

- [ ] Rotate secrets quarterly
- [ ] Update dependencies monthly
- [ ] Review access logs weekly
- [ ] Patch systems promptly
- [ ] Conduct security audits

## Common Security Issues

### Issue: Exposed Secrets

**Symptom**: Secrets visible in logs or environment

**Solution**:
```bash
# Check for exposed secrets
docker-compose config | grep -i password

# Use file-based secrets
docker-compose down
./scripts/setup-secrets.sh regenerate
docker-compose up -d
```

### Issue: Open Security Groups

**Symptom**: Services accessible from internet

**Solution**:
```bash
# Review security groups
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*GeuseMaker*"

# Update to restrict access
terraform apply -var="allowed_cidr_blocks=[\"YOUR_IP/32\"]"
```

### Issue: Unencrypted Data

**Symptom**: Data stored without encryption

**Solution**:
```hcl
# Enable encryption in terraform.tfvars
enable_encryption_at_rest = true
enable_efs = true
```

## Security Tools

### Validation Script

```bash
# Run comprehensive security check
./scripts/security-validation.sh
```

### AWS Security Hub

Enable for centralized security findings:

```bash
aws securityhub enable-security-hub --region us-east-1
```

### Vulnerability Scanning

```bash
# Scan Docker images
docker scout cves local://
```

## Compliance

### Best Practices

- Follow AWS Well-Architected Framework
- Implement least privilege access
- Enable MFA for AWS accounts
- Use separate environments
- Regular security reviews

### Certifications

The deployment supports compliance with:

- SOC 2
- HIPAA (with additional configuration)
- PCI DSS (with additional controls)
- GDPR (data residency controls)

## Getting Help

- Security issues: security@your-domain.com
- Documentation: [Security Reference](../reference/security/)
- AWS Support: [AWS Security Center](https://aws.amazon.com/security/) 