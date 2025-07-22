# AI Starter Kit

> Enterprise-ready AI infrastructure platform with automated deployment, monitoring, and scaling capabilities.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Supported-blue.svg)](https://www.docker.com/)
[![Terraform](https://img.shields.io/badge/Terraform-Ready-purple.svg)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Optimized-orange.svg)](https://aws.amazon.com/)

## 🚀 Quick Start

Get your AI infrastructure running in 5 minutes:

```bash
# Clone and setup
git clone <repository-url> && cd ai-starter-kit
make setup

# Deploy development environment
make deploy-simple STACK_NAME=my-dev-stack

# Access your AI services
# n8n: http://your-ip:5678 (workflow automation)
# Ollama: http://your-ip:11434 (LLM API)
# Qdrant: http://your-ip:6333 (vector database)
```

[**→ Detailed Quick Start Guide**](docs/getting-started/quick-start.md)

## 📚 Documentation Hub

### 🎯 **Getting Started**
- [**Prerequisites & Setup**](docs/getting-started/prerequisites.md) - Required tools and configuration
- [**Quick Start Guide**](docs/getting-started/quick-start.md) - 5-minute deployment walkthrough  
- [**First Deployment**](docs/getting-started/first-deployment.md) - Complete deployment tutorial

### 📖 **User Guides**
- [**Deployment Guide**](docs/guides/deployment/) - All deployment methods and options
- [**Configuration Guide**](docs/guides/configuration/) - Service configuration and customization
- [**Troubleshooting Guide**](docs/guides/troubleshooting/) - Common issues and solutions

### 🔧 **Reference Documentation**
- [**API Reference**](docs/reference/api/) - Complete API documentation for all services
- [**CLI Reference**](docs/reference/cli/) - Command-line tools and scripts
- [**Configuration Reference**](docs/reference/configuration/) - All configuration options

### 🏗️ **Architecture & Design**
- [**System Architecture**](docs/architecture/overview.md) - Overall system design and components
- [**Security Model**](docs/architecture/security.md) - Security design and best practices
- [**Scaling Strategy**](docs/architecture/scaling.md) - Performance and scaling guidance

### 💡 **Examples & Tutorials**
- [**Basic Examples**](docs/examples/basic/) - Simple use cases and tutorials
- [**Advanced Examples**](docs/examples/advanced/) - Complex AI pipelines and integrations
- [**Integration Patterns**](docs/examples/integrations/) - Third-party service integrations

### ⚙️ **Operations**
- [**Monitoring & Alerting**](docs/operations/monitoring.md) - System monitoring and observability
- [**Backup & Recovery**](docs/operations/backup.md) - Data protection and disaster recovery
- [**Cost Optimization**](docs/operations/cost-optimization.md) - Cost management strategies

## 🌟 Core Features

| Feature | Description | Documentation |
|---------|-------------|---------------|
| **Multi-Deployment** | Spot, On-demand, Simple deployment options | [Deployment Guide](docs/guides/deployment/) |
| **Infrastructure as Code** | Terraform and shell script automation | [IaC Guide](docs/guides/deployment/terraform.md) |
| **AI Services** | n8n, Ollama, Qdrant, Crawl4AI pre-configured | [API Reference](docs/reference/api/) |
| **Monitoring Stack** | Prometheus, Grafana, AlertManager | [Monitoring Guide](docs/operations/monitoring.md) |
| **Cost Optimization** | Intelligent instance selection and scaling | [Cost Guide](docs/operations/cost-optimization.md) |
| **Security Hardening** | Encrypted storage, IAM, network security | [Security Model](docs/architecture/security.md) |

## 🛠️ Available Commands

| Command | Description |
|---------|-------------|
| `make setup` | Initialize development environment |
| `make deploy STACK_NAME=name` | Deploy with intelligent instance selection |
| `make deploy-spot STACK_NAME=name` | Deploy cost-optimized spot instances |
| `make deploy-ondemand STACK_NAME=name` | Deploy reliable on-demand instances |
| `make test` | Run comprehensive test suite |
| `make status STACK_NAME=name` | Check deployment status |
| `make destroy STACK_NAME=name` | Clean up all resources |

[**→ Complete CLI Reference**](docs/reference/cli/)

## 🔧 System Requirements

| Component | Minimum | Recommended | Purpose |
|-----------|---------|-------------|---------|
| **AWS Account** | Basic permissions | Admin access | Cloud infrastructure |
| **Local Machine** | 4GB RAM, 10GB disk | 8GB RAM, 50GB disk | Development tools |
| **Network** | Internet access | Stable broadband | Service deployment |

**Supported Platforms:** macOS, Linux, Windows (WSL)

[**→ Detailed Prerequisites**](docs/getting-started/prerequisites.md)

## 🎯 Deployment Types

### Simple Deployment
Perfect for development and learning:
- Single t3.medium instance
- Basic AI services (n8n, Ollama)
- Cost: ~$30/month
- Setup time: 5 minutes

### Spot Deployment  
Cost-optimized for development:
- GPU-enabled g4dn.xlarge spot instances
- Full AI stack with monitoring
- Cost: ~$50-100/month (60-90% savings)
- Setup time: 10 minutes

### On-Demand Deployment
Production-ready with high availability:
- Load-balanced, auto-scaling
- Full monitoring and alerting
- Cost: ~$200-500/month
- Setup time: 15 minutes

[**→ Detailed Deployment Comparison**](docs/guides/deployment/comparison.md)

## 🚨 Support & Community

### Getting Help
1. **Check Documentation**: Start with our comprehensive guides
2. **Review Troubleshooting**: Common issues and solutions
3. **Search Issues**: GitHub issues for known problems
4. **Ask Questions**: Create new issue with details

### Contributing
We welcome contributions! See our [**Contributing Guide**](docs/contributing.md) for:
- Code contribution guidelines
- Documentation improvements
- Bug reporting procedures
- Feature request process

### Community Resources
- **Documentation**: Complete guides and API references
- **Examples**: Real-world usage patterns and tutorials  
- **Best Practices**: Proven deployment and scaling strategies
- **Security Guidelines**: Comprehensive security implementation

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🔗 Quick Navigation

| Category | Links |
|----------|--------|
| **Start Here** | [Quick Start](docs/getting-started/quick-start.md) • [Prerequisites](docs/getting-started/prerequisites.md) • [First Deployment](docs/getting-started/first-deployment.md) |
| **Deploy** | [Deployment Guide](docs/guides/deployment/) • [Terraform](docs/guides/deployment/terraform.md) • [Configuration](docs/guides/configuration/) |
| **Use** | [API Reference](docs/reference/api/) • [Examples](docs/examples/) • [CLI Tools](docs/reference/cli/) |
| **Operate** | [Monitoring](docs/operations/monitoring.md) • [Troubleshooting](docs/guides/troubleshooting/) • [Cost Optimization](docs/operations/cost-optimization.md) |
| **Learn** | [Architecture](docs/architecture/) • [Security](docs/architecture/security.md) • [Scaling](docs/architecture/scaling.md) |

**[📚 Complete Documentation Index](docs/README.md)**