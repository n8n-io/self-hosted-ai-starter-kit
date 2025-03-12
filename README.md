# AI Starter Kit Deployment Guide

This repository contains an AI Starter Kit that can be deployed on AWS EC2 instances with either CPU (for testing) or GPU (for production) configurations.

## Architecture

- **Services**: n8n, Ollama, PostgreSQL, Qdrant
- **Persistent Storage**: AWS EFS for all data
- **Deployment Types**: CPU for testing, GPU for production
- **Access**: HTTPS with self-signed certificates

## Deployment Instructions

### Prerequisites

1. Set up AWS SSM Parameters:
   - `/aibuildkit/POSTGRES_PASSWORD` - PostgreSQL root password
   - `/aibuildkit/N8N_ENCRYPTION_KEY` - n8n encryption key
   - `/aibuildkit/N8N_USER_MANAGEMENT_JWT_SECRET` - n8n JWT secret

2. Create an EFS file system
   - Note the file system ID for configuration

### Launch Templates

#### Testing Environment (CPU)

1. Create a launch template with:
   - Amazon Linux 2 AMI
   - Instance type: t3.medium or similar CPU-only instance
   - User data: Use the cloud-init.yml file from this repository
   - IAM role with permissions to:
     - Access EFS
     - Read SSM parameters
   - Security groups allowing:
     - SSH (port 22)
     - HTTPS (port 443)
     - n8n (port 5678)
     - NFS (for EFS)

2. Launch an instance from the template

#### Production Environment (GPU)

1. Create a launch template with:
   - Amazon Linux 2 AMI with NVIDIA drivers
   - Instance type: g4dn.xlarge or similar GPU instance
   - User data: Use the cloud-init.yml file from this repository
   - Request as a Spot instance for cost savings
   - IAM role with permissions to:
     - Access EFS
     - Read SSM parameters
   - Security groups allowing:
     - SSH (port 22)
     - HTTPS (port 443)
     - n8n (port 5678)
     - NFS (for EFS)

2. Launch a Spot instance from the template

### Accessing the Services

Once the instance is running:
- n8n: https://[instance-public-ip]:5678
- Ollama: Available internally on port 11434

## Troubleshooting

### Logs
- sudo tail -f /var/log/cloud-init-output.log

### EFS Mounting Issues
- Check that the security groups allow NFS traffic (port 2049)
- Verify the instance has permissions to mount the EFS
- Check CloudWatch logs for mount errors

### Docker Service Issues
- SSH into the instance and check Docker logs:
  ```
  docker ps
  docker logs [container_name]
  ```

### Spot Instance Termination
- The system includes automatic handling of spot instance terminations
- Data is persisted on EFS, so no data loss occurs

## Customization

To customize the deployment:
1. Edit `.env` for environment variable changes
2. Edit `docker-compose.yml` for service configuration changes
3. Edit `cloud-init.yml` for instance setup changes
