# 🚀 AI Starter Kit - GPU-Optimized AWS Deployment

<div align="center">

![AI Starter Kit Demo](assets/n8n-demo.gif)

**Enterprise-grade AI workflow automation with 70% cost optimization**

[![AWS](https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![n8n](https://img.shields.io/badge/n8n-FF6B5B?style=for-the-badge&logo=n8n&logoColor=white)](https://n8n.io/)
[![Ollama](https://img.shields.io/badge/Ollama-FF6C37?style=for-the-badge&logo=ollama&logoColor=white)](https://ollama.ai/)

*Deploy production-ready AI workflows with GPU acceleration, vector search, and intelligent cost optimization*

</div>

---

## 🎯 What You Get

### 🤖 **AI-Powered Workflows**
- **n8n** - Visual workflow automation with AI agents
- **Ollama** - Local LLM inference (DeepSeek-R1:8B, Qwen2.5-VL:7B)
- **Qdrant** - High-performance vector database
- **Crawl4AI** - Intelligent web scraping with LLM extraction

### 💰 **Cost Optimization**
- **70-75% cost savings** with AWS Spot instances
- **Auto-scaling** based on GPU utilization
- **Real-time pricing** via AWS Pricing API
- **Intelligent resource allocation** for g4dn.xlarge

### 🚀 **Production Features**
- **EFS persistence** - Data survives spot interruptions
- **CloudFront CDN** - Global content delivery
- **Auto-scaling groups** - High availability
- **Graceful spot termination** - 2-minute warning handling

---

## 📊 Architecture Overview

```mermaid
graph TB
    subgraph "AWS Cloud"
        CF[CloudFront CDN]
        ALB[Application Load Balancer]
        ASG[Auto Scaling Group]
        EFS[Elastic File System]
    end
    
    subgraph "GPU Instance (g4dn.xlarge)"
        subgraph "Docker Containers"
            N8N[n8n Workflows]
            OLLAMA[Ollama LLMs]
            QDRANT[Qdrant Vector DB]
            CRAWL4AI[Crawl4AI Scraper]
            POSTGRES[PostgreSQL]
        end
        
        GPU[NVIDIA T4 GPU]
        MONITOR[Cost Monitor]
    end
    
    CF --> ALB
    ALB --> ASG
    ASG --> GPU Instance
    GPU Instance --> EFS
    OLLAMA --> GPU
    MONITOR --> ASG
```

---

## 🛠️ Quick Start

### Prerequisites
- ✅ AWS CLI configured with appropriate permissions
- ✅ Docker and Docker Compose installed
- ✅ AWS account with GPU instance quota

### 1️⃣ **Configure Secrets**
Store your API keys in AWS Systems Manager:

```bash
# Set up SSM parameters
aws ssm put-parameter --name "/aibuildkit/OPENAI_API_KEY" --value "your-key" --type SecureString
aws ssm put-parameter --name "/aibuildkit/n8n/ENCRYPTION_KEY" --value "your-key" --type SecureString
aws ssm put-parameter --name "/aibuildkit/POSTGRES_PASSWORD" --value "your-password" --type SecureString
```

### 2️⃣ **Deploy to AWS**
```bash
# Deploy with default settings (us-east-1, g4dn.xlarge)
./scripts/aws-deployment.sh

# Or customize deployment
./scripts/aws-deployment.sh \
  --region us-west-2 \
  --instance-type g4dn.2xlarge \
  --max-spot-price 1.00
```

### 3️⃣ **Access Your Services**
After deployment, configure DNS CNAME records:
- **n8n Workflows**: `https://n8n.geuse.io`
- **Qdrant Vector DB**: `https://qdrant.geuse.io`
- **Direct Access**: `http://YOUR-IP:5678` (n8n)

---

## 💡 Local Development

For local testing and development, use the CPU profile:

```bash
# Start services locally (CPU-only)
docker compose --profile cpu up

# Services will be available at:
# - n8n: http://localhost:5678
# - Ollama: http://localhost:11434
# - Qdrant: http://localhost:6333
# - Crawl4AI: http://localhost:11235
```

---

## 📈 Cost Analysis

| Component | On-Demand | Spot Instance | Savings |
|-----------|-----------|---------------|---------|
| **g4dn.xlarge** | $1.19/hr | $0.25-0.45/hr | 67-75% |
| **Daily Cost** | $28.56 | $6-10.80 | 70-75% |
| **Monthly Cost** | $856.80 | $180-324 | 70-75% |

### 🎯 **Cost Optimization Features**
- ✅ **Spot Instance Management** - Automatic bidding and interruption handling
- ✅ **Auto-scaling** - Scale based on GPU utilization (20-80% thresholds)
- ✅ **Real-time Pricing** - AWS Pricing API integration
- ✅ **Resource Optimization** - Balanced CPU/memory allocation
- ✅ **Storage Optimization** - EFS with auto-scaling throughput

---

## 🔧 Configuration

### Environment Variables
```bash
# Required SSM Parameters
/aibuildkit/OPENAI_API_KEY          # OpenAI API key
/aibuildkit/n8n/ENCRYPTION_KEY      # n8n encryption key
/aibuildkit/POSTGRES_PASSWORD       # Database password
/aibuildkit/WEBHOOK_URL             # Webhook base URL

# Optional Parameters
/aibuildkit/n8n/CORS_ENABLE         # CORS settings
/aibuildkit/n8n/CORS_ALLOWED_ORIGINS # Allowed origins
```

### Resource Allocation (g4dn.xlarge)
```yaml
# CPU Allocation (4 vCPUs total)
- postgres: 1.5 vCPUs (37.5%)
- n8n: 1.0 vCPUs (25%)
- ollama: 2.5 vCPUs (62.5%) - Primary compute
- qdrant: 1.5 vCPUs (37.5%)
- monitoring: 0.5 vCPUs (12.5%)

# Memory Allocation (16GB total)
- ollama: 10GB (62.5%) - Primary memory user
- postgres: 3GB (18.75%)
- qdrant: 3GB (18.75%)
- monitoring: 512MB (3.2%)

# GPU Memory (T4 16GB)
- ollama: 14.4GB (90%)
- system reserve: 1.6GB (10%)
```

---

## 🚨 Spot Instance Management

### Interruption Handling
- **2-minute warning** from AWS before termination
- **Graceful shutdown** of AI workloads
- **Automatic backup** to EFS
- **ASG scaling** to replace terminated instances

### Availability Strategy
- **Multi-AZ deployment** across availability zones
- **Mixed instance types** (g4dn.xlarge, g5.xlarge, g4ad.xlarge)
- **Auto-scaling groups** with health checks
- **CloudFront CDN** for global availability

---

## 📊 Monitoring & Analytics

### GPU Monitoring
```bash
# Real-time GPU metrics
curl http://YOUR-IP:6333/healthz  # Qdrant health
curl http://YOUR-IP:11434/api/tags  # Ollama models
curl http://YOUR-IP:5678/healthz  # n8n health
```

### Cost Optimization Reports
```bash
# Generate cost report
python3 scripts/cost-optimization.py --action report

# Monitor optimization
tail -f /var/log/cost-optimization.log
```

### CloudWatch Metrics
- **GPU Utilization** - Auto-scaling trigger
- **Cost per Hour** - Real-time cost tracking
- **Instance Health** - Availability monitoring
- **Workload Efficiency** - Performance analytics

---

## 🧹 Cleanup

### Automated Cleanup
```bash
# The deployment script includes cleanup on error
# Manual cleanup via AWS console:
# 1. Terminate EC2 instances
# 2. Delete Auto Scaling Groups
# 3. Remove EFS file systems
# 4. Delete CloudFront distributions
# 5. Clean up IAM roles and policies
```

---

## 🆘 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| **Spot instance not launching** | Check spot price limits and availability |
| **GPU not detected** | Verify NVIDIA drivers and Docker GPU runtime |
| **EFS mount failures** | Check security groups and VPC configuration |
| **High costs** | Review auto-scaling policies and spot pricing |

### Debug Commands
```bash
# Check service status
docker compose -f docker-compose.gpu-optimized.yml ps

# View logs
docker compose -f docker-compose.gpu-optimized.yml logs ollama

# Monitor GPU usage
nvidia-smi

# Check cost optimization
python3 scripts/cost-optimization.py --action report
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with ❤️ for cost-effective AI deployment**

[![GitHub stars](https://img.shields.io/github/stars/michael-pittman/001-starter-kit?style=social)](https://github.com/michael-pittman/001-starter-kit)
[![GitHub forks](https://img.shields.io/github/forks/michael-pittman/001-starter-kit?style=social)](https://github.com/michael-pittman/001-starter-kit)

</div> 