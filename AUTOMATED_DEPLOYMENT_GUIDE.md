# 🚀 Automated Deployment Guide

This guide will walk you through deploying the AI-Powered Starter Kit using the automated deployment scripts. Choose between local development or cloud deployment on AWS with GPU optimization.

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Local Deployment](#local-deployment)
- [Cloud Deployment (AWS)](#cloud-deployment-aws)
- [Post-Deployment Setup](#post-deployment-setup)
- [Monitoring & Management](#monitoring--management)
- [Troubleshooting](#troubleshooting)
- [Cost Optimization](#cost-optimization)

## 🚀 Quick Start

### Option 1: Local Development (Recommended for testing)

```bash
# 1. Setup environment
./scripts/setup-environment.sh

# 2. Quick start
./quick-start.sh

# 3. Download AI models (after services start)
make setup-models
```

### Option 2: Cloud Deployment (Production-ready with GPU)

```bash
# 1. Setup environment
./scripts/setup-environment.sh

# 2. Configure AWS credentials
aws configure

# 3. Deploy to cloud
./scripts/aws-deployment.sh

# Wait 10-15 minutes for complete deployment
```

## ✅ Prerequisites

### Required Tools

- **Docker** (v20.10+) and **Docker Compose** (v2.0+)
- **Git** for cloning repositories
- **curl** for API testing
- **AWS CLI** (for cloud deployment only)

### System Requirements

**Local Development:**
- 8GB+ RAM (16GB recommended)
- 20GB+ free disk space
- Linux/macOS/Windows with WSL2

**Cloud Deployment:**
- AWS account with appropriate permissions
- AWS CLI configured with access keys
- Understanding of AWS billing and spot instances

### Installation Commands

```bash
# Docker (Ubuntu/Debian)
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Configure AWS
aws configure
```

## 🏠 Local Deployment

### Step 1: Environment Setup

```bash
# Run the automated setup
./scripts/setup-environment.sh
```

This script will:
- ✅ Check all prerequisites
- ✅ Create `.env` file with secure defaults
- ✅ Generate encryption keys and passwords
- ✅ Set up directory structure
- ✅ Create quick-start scripts

### Step 2: Start Services

```bash
# Quick start (recommended)
./quick-start.sh

# OR use Make commands
make dev-quick

# OR use Docker Compose directly
docker compose up -d
```

### Step 3: Download AI Models

```bash
# Download essential AI models
make setup-models

# This downloads:
# - DeepSeek-R1:8B (reasoning)
# - Qwen2.5-VL:7B (vision-language)
# - Llama3.2:3B (general purpose)
# - Embedding models
```

### Step 4: Validate Deployment

```bash
# Run comprehensive validation
./scripts/validate-deployment.sh

# Quick validation
./scripts/validate-deployment.sh --quick

# Check service status
make health
```

### Local Service URLs

After deployment, access your services at:

- **n8n Workflow Editor**: http://localhost:5678
- **Crawl4AI Web Scraper**: http://localhost:11235  
- **Qdrant Vector Database**: http://localhost:6333
- **Ollama AI Models**: http://localhost:11434
- **PostgreSQL Database**: localhost:5432

## ☁️ Cloud Deployment (AWS)

### Step 1: AWS Preparation

```bash
# Configure AWS credentials
aws configure

# Set your preferred region (optional)
export AWS_REGION=us-east-1

# Verify credentials
aws sts get-caller-identity
```

### Step 2: Run Automated Deployment

```bash
# Deploy with default settings (g4dn.xlarge, spot instances)
./scripts/aws-deployment.sh

# Deploy with custom settings
./scripts/aws-deployment.sh \
  --region us-west-2 \
  --instance-type g4dn.2xlarge \
  --max-spot-price 1.00
```

### What the Script Does

The automated deployment script will:

1. **🔑 Infrastructure Setup**
   - Create SSH key pair
   - Set up security groups
   - Create IAM roles and policies
   - Configure EFS (Elastic File System)

2. **🖥️ Instance Management**  
   - Launch spot instances (70% cost savings)
   - Install Docker, NVIDIA drivers, GPU support
   - Configure monitoring and logging
   - Set up automatic scaling

3. **🚀 Application Deployment**
   - Deploy GPU-optimized Docker Compose stack
   - Mount EFS for persistent storage
   - Configure all services with optimal settings
   - Enable monitoring and cost optimization

4. **✅ Validation**
   - Test all service endpoints
   - Validate GPU functionality
   - Check model availability
   - Generate health report

### Deployment Output

After successful deployment, you'll see:

```
=================================
   AI STARTER KIT DEPLOYED!    
=================================

Instance Information:
  Instance ID: i-0123456789abcdef0
  Public IP: 54.123.45.67
  Instance Type: g4dn.xlarge
  EFS DNS: fs-abc12345.efs.us-east-1.amazonaws.com

Service URLs:
  n8n Workflow Editor:     http://54.123.45.67:5678
  Crawl4AI Web Scraper:    http://54.123.45.67:11235
  Qdrant Vector Database:  http://54.123.45.67:6333
  Ollama AI Models:        http://54.123.45.67:11434

SSH Access:
  ssh -i ai-starter-kit-key.pem ubuntu@54.123.45.67

Cost Optimization:
  - Spot instance saves ~70% vs on-demand
  - Expected cost: ~$18-30/day (vs $60-100/day on-demand)
```

### Step 3: Cloud Validation

```bash
# Validate cloud deployment (use your instance IP)
./scripts/validate-deployment.sh \
  --deployment-type cloud \
  --public-ip YOUR_INSTANCE_IP \
  --wait --timeout 600
```

## 🔧 Post-Deployment Setup

### 1. Configure API Keys (Optional)

Edit your `.env` file to add API keys for enhanced features:

```bash
# For local deployment
nano .env

# For cloud deployment  
ssh -i ai-starter-kit-key.pem ubuntu@YOUR_IP
nano /home/ubuntu/ai-starter-kit/.env
```

Add your API keys:
```env
OPENAI_API_KEY=sk-your-openai-key
ANTHROPIC_API_KEY=sk-ant-your-anthropic-key
DEEPSEEK_API_KEY=your-deepseek-key
GROQ_API_KEY=your-groq-key
```

Restart services after updating:
```bash
# Local
docker compose restart

# Cloud
ssh -i ai-starter-kit-key.pem ubuntu@YOUR_IP \
  "cd ai-starter-kit && docker compose restart"
```

### 2. Import n8n Workflows

1. Access n8n at your deployment URL
2. Create an account or log in
3. Import demo workflows from `n8n/demo-data/workflows/`
4. Configure credentials in n8n UI

### 3. Test AI Model Integration

```bash
# Test Ollama models
curl -X POST "http://YOUR_HOST:11434/api/generate" \
  -H "Content-Type: application/json" \
  -d '{"model": "deepseek-r1:8b", "prompt": "Hello AI!", "stream": false}'

# Test Crawl4AI web scraping
curl -X POST "http://YOUR_HOST:11235/crawl" \
  -H "Content-Type: application/json" \
  -d '{"urls": ["https://example.com"], "extraction_strategy": "llm"}'
```

## 📊 Monitoring & Management

### Built-in Monitoring

The deployment includes comprehensive monitoring:

- **GPU Utilization**: Real-time NVIDIA GPU monitoring
- **Cost Optimization**: Automatic spot instance management
- **Health Checks**: Service availability monitoring
- **Resource Usage**: CPU, memory, disk tracking
- **Auto-scaling**: Based on GPU utilization thresholds

### Management Commands

```bash
# Check overall status
make status

# View service logs
make logs

# Restart specific service
docker compose restart [service]

# Update to latest images
make update

# Backup n8n data
make backup

# Generate cost report (cloud deployment)
ssh -i ai-starter-kit-key.pem ubuntu@YOUR_IP \
  "python3 cost-optimization.py --action report"
```

### Accessing Logs

```bash
# Local deployment
docker compose logs -f [service]

# Cloud deployment
ssh -i ai-starter-kit-key.pem ubuntu@YOUR_IP
cd ai-starter-kit
docker compose logs -f [service]
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Services Not Starting

```bash
# Check Docker status
docker info

# Check available resources
docker system df
free -h

# Restart with fresh containers
docker compose down && docker compose up -d
```

#### 2. GPU Not Detected (Cloud)

```bash
# SSH into instance
ssh -i ai-starter-kit-key.pem ubuntu@YOUR_IP

# Check NVIDIA drivers
nvidia-smi

# Check Docker GPU support
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi

# Restart Docker daemon
sudo systemctl restart docker
```

#### 3. Models Not Downloading

```bash
# Check Ollama service
curl http://YOUR_HOST:11434/api/tags

# Manual model download
docker compose exec ollama ollama pull llama3.2:3b

# Check disk space
df -h
```

#### 4. Network Issues (Cloud)

```bash
# Check security groups in AWS Console
# Ensure these ports are open:
# - 22 (SSH)
# - 5678 (n8n)
# - 11434 (Ollama)
# - 11235 (Crawl4AI)
# - 6333 (Qdrant)

# Test port connectivity
nc -zv YOUR_IP 5678
```

#### 5. High Memory Usage

```bash
# Reduce resource usage in .env:
OLLAMA_MAX_LOADED_MODELS=1
CRAWL4AI_BROWSER_POOL_SIZE=1

# Restart services
docker compose restart
```

### Getting Help

1. **Run Validation**: `./scripts/validate-deployment.sh`
2. **Check Logs**: `docker compose logs [service]`
3. **Review Documentation**: This guide and `README.md`
4. **AWS Issues**: Check CloudWatch logs and AWS Console

## 💰 Cost Optimization

### Automatic Cost Management

The cloud deployment includes built-in cost optimization:

- **Spot Instances**: 70% savings vs on-demand pricing
- **Auto-scaling**: Scale down during low utilization
- **Resource Monitoring**: Track GPU and CPU usage
- **Cost Alerts**: Notifications when spending exceeds thresholds
- **Idle Detection**: Automatic termination of unused instances

### Manual Cost Controls

```bash
# Stop instances when not in use
aws ec2 stop-instances --instance-ids i-your-instance-id

# Terminate instances (WARNING: destroys data not on EFS)
aws ec2 terminate-instances --instance-ids i-your-instance-id

# Monitor costs
aws ce get-dimension-values --dimension SERVICE --time-period Start=2024-01-01,End=2024-01-31

# Set billing alerts in AWS Console
```

### Cost Estimates

**Local Development**: Free (uses your hardware)

**Cloud Deployment (g4dn.xlarge)**:
- **Spot Instance**: ~$0.30-0.50/hour ($7-12/day)
- **On-Demand**: ~$1.19/hour (~$29/day)
- **Storage (EFS)**: ~$0.30/GB/month
- **Data Transfer**: Varies by usage

**Estimated Monthly Costs**:
- Development/Testing: $50-150/month
- Production (24/7): $200-400/month
- Spot instances can reduce costs by 70%

## 🎯 Next Steps

### For Development
1. Explore n8n workflow templates in `n8n/demo-data/workflows/`
2. Test Crawl4AI with different websites
3. Experiment with AI models in Ollama
4. Build custom workflows combining all services

### For Production
1. Set up proper backups and monitoring
2. Configure SSL/TLS certificates  
3. Implement proper security controls
4. Set up CI/CD pipelines for updates
5. Consider multi-region deployment

### Learning Resources
- **n8n Documentation**: https://docs.n8n.io
- **Crawl4AI Guide**: `crawl4ai/CRAWL4AI_INTEGRATION.md`
- **Ollama Models**: https://ollama.ai/library
- **AWS Best Practices**: AWS Well-Architected Framework

---

## 🆘 Emergency Procedures

### Quick Recovery Commands

```bash
# Stop all services (local)
docker compose down

# Emergency stop (cloud)
aws ec2 stop-instances --instance-ids $(aws ec2 describe-instances --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' --output text)

# Clean restart (local)
docker compose down -v && docker compose up -d

# Re-run deployment (cloud)
./scripts/aws-deployment.sh
```

### Data Recovery

```bash
# Backup before changes (local)
docker compose exec postgres pg_dump -U n8n n8n > backup.sql

# Access EFS data (cloud)
ssh -i ai-starter-kit-key.pem ubuntu@YOUR_IP
ls /mnt/efs/
```

This deployment automation provides a production-ready AI infrastructure with comprehensive monitoring, cost optimization, and easy management. The scripts handle all the complexity while giving you full control over your deployment.

**Happy building! 🚀** 