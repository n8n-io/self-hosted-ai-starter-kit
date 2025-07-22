# Quick Start Guide

> Get your AI infrastructure running in 5 minutes

This guide will help you deploy a working AI infrastructure platform as quickly as possible. For detailed explanations, see the [Complete Deployment Guide](../guides/deployment/).

## ⚡ Prerequisites Check

Before starting, ensure you have:

- ✅ **AWS Account** with admin permissions
- ✅ **AWS CLI** installed and configured (`aws configure`)
- ✅ **Docker** installed and running
- ✅ **Git** for cloning the repository

**Quick verification:**
```bash
aws sts get-caller-identity  # Should show your AWS account
docker --version             # Should show Docker version
```

[**→ Detailed Prerequisites Guide**](prerequisites.md)

## 🚀 5-Minute Deployment

### Step 1: Clone and Setup (1 minute)

```bash
# Clone the repository
git clone <repository-url>
cd ai-starter-kit

# Initialize development environment
make setup
```

### Step 2: Choose Your Deployment (30 seconds)

Pick the deployment type that fits your needs:

| Type | Best For | Cost/Month | Setup Time |
|------|----------|------------|------------|
| **Simple** | Learning, Development | ~$30 | 5 min |
| **Spot** | Cost-Optimized Development | ~$50-100 | 10 min |
| **On-Demand** | Production, Reliability | ~$200-500 | 15 min |

### Step 3: Deploy Your Stack (3-10 minutes)

Choose one deployment command:

#### Option A: Simple Deployment (Recommended for beginners)
```bash
make deploy-simple STACK_NAME=my-dev-stack
```

#### Option B: Spot Deployment (Cost-optimized)
```bash
make deploy-spot STACK_NAME=my-spot-stack
```

#### Option C: On-Demand Deployment (Production-ready)
```bash
make deploy-ondemand STACK_NAME=my-prod-stack
```

### Step 4: Access Your Services (30 seconds)

Once deployment completes, you'll see output like:

```
🎉 Deployment completed successfully!

Access URLs:
- n8n Workflow Automation: http://YOUR-IP:5678
- Ollama LLM API: http://YOUR-IP:11434
- Qdrant Vector Database: http://YOUR-IP:6333
- Crawl4AI Service: http://YOUR-IP:11235

SSH Access: ssh -i my-dev-stack-key.pem ubuntu@YOUR-IP
```

## 🎯 What You Just Deployed

Your AI infrastructure now includes:

### 🔧 **Core AI Services**
- **n8n**: Visual workflow automation for AI pipelines
- **Ollama**: Local LLM serving with GPU acceleration
- **Qdrant**: High-performance vector database
- **Crawl4AI**: Intelligent web crawling and extraction
- **PostgreSQL**: Persistent data storage

### 📊 **Monitoring & Operations**
- **CloudWatch**: AWS-native monitoring and logging
- **Health Checks**: Automated service validation
- **Resource Monitoring**: CPU, memory, and GPU tracking

### 🔐 **Security Features**
- **Encrypted Storage**: EBS and EFS encryption
- **Network Security**: Security groups with minimal ports
- **IAM Roles**: Least-privilege access controls
- **Automated Updates**: Security patch management

## 🎨 First Steps After Deployment

### 1. Create Your First Workflow (5 minutes)

1. **Access n8n**: Open `http://YOUR-IP:5678` in your browser
2. **Set up authentication**: Create admin credentials when prompted
3. **Import example workflow**: 
   ```bash
   # Copy example workflows to your instance
   scp -i your-key.pem -r n8n/demo-data/workflows/ ubuntu@YOUR-IP:~/ai-starter-kit/
   ```
4. **Test the workflow**: Run a simple automation

[**→ Complete Workflow Tutorial**](../examples/basic/workflow-creation.md)

### 2. Test LLM Integration (3 minutes)

```bash
# Test Ollama API
curl http://YOUR-IP:11434/api/generate -d '{
  "model": "llama2",
  "prompt": "Why is the sky blue?",
  "stream": false
}'
```

[**→ LLM Integration Guide**](../examples/basic/llm-integration.md)

### 3. Explore Vector Database (5 minutes)

```bash
# Test Qdrant API
curl -X GET http://YOUR-IP:6333/collections
```

[**→ Vector Database Tutorial**](../examples/basic/vector-database.md)

## 🔍 Verify Everything Works

Run the health check to ensure all services are operating correctly:

```bash
# Check deployment status
make status STACK_NAME=your-stack-name

# SSH into instance and run health check
ssh -i your-key.pem ubuntu@YOUR-IP 'cd ai-starter-kit && ./health-check.sh'
```

Expected output:
```
✅ n8n (port 5678) is healthy
✅ ollama (port 11434) is healthy  
✅ qdrant (port 6333) is healthy
✅ crawl4ai (port 11235) is healthy
🎉 All services are healthy
```

## 🛠️ Common Quick Fixes

### Service Not Responding?
```bash
# Restart all services
ssh -i your-key.pem ubuntu@YOUR-IP 'cd ai-starter-kit && docker-compose restart'
```

### Need to Change Configuration?
```bash
# SSH into instance
ssh -i your-key.pem ubuntu@YOUR-IP

# Edit configuration
cd ai-starter-kit
nano config/environment.env

# Restart services to apply changes
docker-compose restart
```

### Want to Add More Models?
```bash
# SSH into instance and add models
ssh -i your-key.pem ubuntu@YOUR-IP 'docker exec ollama ollama pull codellama'
```

## 📈 Monitoring Your Deployment

### View Logs
```bash
# View deployment logs
make logs STACK_NAME=your-stack-name

# View service logs on instance
ssh -i your-key.pem ubuntu@YOUR-IP 'cd ai-starter-kit && docker-compose logs -f'
```

### Check Resource Usage
```bash
# Monitor resource usage
ssh -i your-key.pem ubuntu@YOUR-IP 'docker stats'

# Check GPU usage (for GPU instances)
ssh -i your-key.pem ubuntu@YOUR-IP 'nvidia-smi'
```

### CloudWatch Monitoring
- Open AWS CloudWatch in your browser
- Navigate to "Log groups" → `/aws/ai-starter-kit/your-stack-name`
- View real-time logs and metrics

## 💰 Cost Management

### Monitor Costs
```bash
# Get cost estimate
make cost-estimate STACK_NAME=your-stack-name HOURS=24
```

### Optimize Costs
- **Stop when not needed**: `make destroy STACK_NAME=your-stack-name`
- **Use spot instances**: Switch to spot deployment for development
- **Right-size instances**: Use smaller instances for lighter workloads

[**→ Complete Cost Optimization Guide**](../operations/cost-optimization.md)

## 🔄 Next Steps

Now that your AI infrastructure is running:

### 🎓 **Learn More**
- [**Complete Deployment Guide**](../guides/deployment/) - Understand all deployment options
- [**Configuration Guide**](../guides/configuration/) - Customize your setup
- [**API Reference**](../reference/api/) - Integrate with your applications

### 🛠️ **Build Something**
- [**Basic Examples**](../examples/basic/) - Simple AI workflows and integrations
- [**Advanced Examples**](../examples/advanced/) - Complex AI pipelines
- [**Integration Examples**](../examples/integrations/) - Connect with external services

### ⚙️ **Production Readiness**
- [**Monitoring Setup**](../operations/monitoring.md) - Comprehensive observability
- [**Security Hardening**](../architecture/security.md) - Production security practices
- [**Backup Strategies**](../operations/backup.md) - Data protection

## 🚨 Need Help?

### Quick Support
- **Common Issues**: [Troubleshooting Guide](../guides/troubleshooting/)
- **Configuration Problems**: [Configuration Reference](../reference/configuration/)
- **API Questions**: [API Documentation](../reference/api/)

### Community Support
- **GitHub Issues**: Report bugs or request features
- **Documentation**: Complete guides and references
- **Examples**: Working code samples and tutorials

---

## ✅ Quick Start Checklist

- [ ] Prerequisites verified (AWS CLI, Docker, Git)
- [ ] Repository cloned and setup completed
- [ ] Stack deployed successfully
- [ ] All services responding to health checks
- [ ] n8n accessible in browser
- [ ] First workflow created or imported
- [ ] LLM API tested
- [ ] Vector database accessible
- [ ] Monitoring configured
- [ ] Cost tracking enabled

**🎉 Congratulations!** You now have a fully functional AI infrastructure platform.

[**← Back to Documentation Hub**](../README.md) | [**→ Complete Deployment Guide**](../guides/deployment/)

---

**Estimated Total Time:** 5-15 minutes  
**Difficulty:** Beginner  
**Requirements:** AWS account, basic command-line knowledge