# 🚀 Enhanced AI Starter Kit - Quick Start

[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2.38.2-blue.svg)](https://docs.docker.com/compose/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![AWS](https://img.shields.io/badge/AWS-g4dn.xlarge-orange.svg)](https://aws.amazon.com/ec2/instance-types/g4/)

> **🎯 Get started in 5 minutes** | **📚 [Complete Guide](COMPREHENSIVE_GUIDE.md)** | **🔧 [Advanced Configuration](COMPREHENSIVE_GUIDE.md#configuration-guide)**

An advanced AI-powered automation platform optimized for NVIDIA GPU workloads, featuring comprehensive cost optimization, intelligent web scraping, and workflow automation capabilities.

## 🚀 Quick Start

### 📋 Prerequisites

| Tool | Version | Required |
|------|---------|----------|
| Docker | ≥ 20.10 | ✅ |
| Docker Compose | ≥ 2.38.2 | ✅ |
| Git | ≥ 2.0 | ✅ |
| NVIDIA Drivers | ≥ 535.x | For GPU support |

### 🏃‍♂️ 5-Minute Setup

1. **Clone & Setup**
   ```bash
   git clone <repository-url>
   cd 001-starter-kit
   cp .env.example .env
   ```

2. **Choose Your Deployment**
   ```bash
   # 🏠 Local Development (CPU-only)
   docker compose up -d
   
   # 🚀 GPU-Optimized Local
   docker compose -f docker-compose.gpu-optimized.yml up -d
   
   # ☁️ Cloud Production
   export EFS_DNS="fs-xxxxxxxxx.efs.us-east-1.amazonaws.com"
   docker compose -f docker-compose.gpu-optimized.yml up -d
   ```

3. **Access Services**
   - **n8n**: http://localhost:5678
   - **Crawl4AI**: http://localhost:11235
   - **Qdrant**: http://localhost:6333/dashboard

## 🎯 What's Included

### Core Services

| Service | Purpose | Port | GPU Support |
|---------|---------|------|-------------|
| **n8n** | Workflow automation and AI agent orchestration | 5678 | ✅ |
| **Ollama** | Local AI model inference with GPU acceleration | 11434 | ✅ |
| **Crawl4AI** | Advanced web scraping with LLM-based extraction | 11235 | ✅ |
| **PostgreSQL** | Database with performance optimizations | 5432 | ❌ |
| **Qdrant** | Vector database for semantic search and RAG | 6333 | ❌ |

### AI Models

- **🧠 DeepSeek-R1:8B** - Advanced reasoning and coding
- **👁️ Qwen2.5-VL:7B** - Vision-language multimodal tasks
- **🔍 Snowflake-Arctic-Embed2:568M** - High-performance embeddings

## 🔧 Docker Compose v2.38.2 Optimizations

This setup leverages the latest Docker Compose features:

- ✅ **Modern Compose Specification** - No version field required
- ✅ **Enhanced Health Checks** - Improved dependency management with `start_interval`
- ✅ **Resource Optimization** - Advanced placement preferences and resource limits
- ✅ **Network Optimization** - Enhanced bridge networking with custom MTU
- ✅ **EFS Integration** - High-performance persistent storage with `_netdev` option
- ✅ **GPU Optimization** - NVIDIA GPU support with proper device mapping

### Key Improvements

```yaml
# Enhanced health checks with v2.38.2
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
  start_interval: 5s  # NEW in v2.38.2

# Resource optimization
deploy:
  resources:
    limits:
      memory: 4G
      cpus: '2.0'
  placement:
    preferences:
      - spread: node.labels.zone  # NEW in v2.38.2
```

## 📚 Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| **[README.md](README.md)** | Quick start guide | All users |
| **[COMPREHENSIVE_GUIDE.md](COMPREHENSIVE_GUIDE.md)** | Complete documentation | Detailed setup |
| **[DEPLOYMENT_STRATEGY.md](DEPLOYMENT_STRATEGY.md)** | Deployment strategies | Operations |
| **[DOCKER_OPTIMIZATION.md](DOCKER_OPTIMIZATION.md)** | Docker optimizations | DevOps |

## 🎯 Deployment Strategies

### 🏠 Local Development
```bash
docker compose up -d
```
**Perfect for**: Learning, prototyping, small projects
**Resources**: 8GB+ RAM, 20GB+ storage
**Cost**: Free

### ☁️ Cloud Production
```bash
docker compose -f docker-compose.gpu-optimized.yml up -d
```
**Perfect for**: Production workloads, high-performance AI
**Resources**: g4dn.xlarge (T4 GPU, 16GB RAM)
**Cost**: ~$150-300/month (70% savings with spot instances)

### 🔄 Hybrid Development
```bash
export OLLAMA_BASE_URL="https://your-gpu-instance.com:11434"
docker compose up -d
```
**Perfect for**: Development with cloud resources
**Cost**: Pay-per-use

## 🌟 Key Features

- **💰 Cost Optimization**: Up to 70% savings with advanced spot instance strategies
- **🚀 GPU Acceleration**: NVIDIA T4 GPU support with driver automation
- **📈 Auto Scaling**: Intelligent scaling based on GPU utilization
- **📊 Monitoring**: Real-time performance monitoring with CloudWatch
- **💾 Persistent Storage**: High-performance EFS with intelligent tiering
- **🔒 Security**: Encrypted storage, secure networking, and IAM best practices

## 🧪 Test Your Setup

```bash
# Test Crawl4AI
curl -X POST "http://localhost:11235/crawl" \
  -H "Content-Type: application/json" \
  -d '{"urls": ["https://example.com"]}'

# Test n8n
curl -X GET "http://localhost:5678/healthz"

# Test Ollama
curl -X POST "http://localhost:11434/api/generate" \
  -d '{"model": "deepseek-r1:8b", "prompt": "Hello world"}'
```

## 🔧 Configuration

### Essential Environment Variables

```bash
# Required
POSTGRES_PASSWORD=your-secure-password
N8N_ENCRYPTION_KEY=your-32-character-encryption-key
N8N_USER_MANAGEMENT_JWT_SECRET=your-jwt-secret

# Optional LLM API Keys
OPENAI_API_KEY=your-openai-api-key
ANTHROPIC_API_KEY=your-anthropic-api-key
DEEPSEEK_API_KEY=your-deepseek-api-key

# Cloud deployment
EFS_DNS=fs-xxxxxxxxx.efs.us-east-1.amazonaws.com
```

## 💡 Quick Tips

- **🔥 First Time?** Start with local development: `docker compose up -d`
- **⚡ Need GPU?** Use GPU-optimized: `docker compose -f docker-compose.gpu-optimized.yml up -d`
- **☁️ Cloud Deploy?** Set `EFS_DNS` and use GPU-optimized config
- **📊 Monitor?** Use `docker stats` and `nvidia-smi` for resource monitoring
- **🐛 Issues?** Check logs with `docker compose logs -f`

## 🆘 Common Issues

| Issue | Solution |
|-------|----------|
| **GPU not detected** | Check `nvidia-smi` and Docker GPU support |
| **Memory issues** | Use GPU-optimized config or increase Docker memory |
| **Service not starting** | Check logs: `docker compose logs service-name` |
| **Network issues** | Verify firewall and port availability |

## 📚 Learn More

- **📖 [Complete Documentation](COMPREHENSIVE_GUIDE.md)** - Comprehensive setup guide
- **🚀 [Deployment Strategies](COMPREHENSIVE_GUIDE.md#deployment-strategies)** - Detailed deployment options
- **⚙️ [Configuration Guide](COMPREHENSIVE_GUIDE.md#configuration-guide)** - Advanced configuration
- **📊 [Monitoring & Operations](COMPREHENSIVE_GUIDE.md#monitoring--operations)** - Production monitoring
- **💰 [Cost Optimization](COMPREHENSIVE_GUIDE.md#cost-optimization)** - Cost-saving strategies
- **🔧 [Troubleshooting](COMPREHENSIVE_GUIDE.md#troubleshooting)** - Common issues and solutions

## 🤝 Support

- **📖 Issues**: [GitHub Issues](https://github.com/your-repo/issues)
- **💬 Community**: [Discord Server](https://discord.gg/your-server)
- **📧 Email**: support@your-domain.com

## 📄 License

MIT License - see the [LICENSE](LICENSE) file for details.

---

**🚀 Ready to get started?** Run `docker compose up -d` and visit http://localhost:5678

**📚 Need more details?** Check out the [Complete Guide](COMPREHENSIVE_GUIDE.md)
