# GeuseMaker

> Enterprise-ready AI infrastructure platform with automated deployment, monitoring, and scaling capabilities.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Supported-blue.svg)](https://www.docker.com/)
[![Terraform](https://img.shields.io/badge/Terraform-Ready-purple.svg)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Optimized-orange.svg)](https://aws.amazon.com/)

## 🚀 Quick Start

Get your AI infrastructure running in 5 minutes:

```bash
# Clone and setup
git clone <repository-url> && cd GeuseMaker
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
- [**Security Guide**](docs/security-guide.md) - Security implementation and best practices

### 📖 **User Guides**
- [**Deployment Guide**](docs/reference/cli/deployment.md) - All deployment methods and options
- [**Configuration Guide**](docs/reference/configuration/) - Service configuration and customization (directory structure)
- [**Troubleshooting Guide**](docs/setup/troubleshooting.md) - Common issues and solutions

### 🔧 **Reference Documentation**
- [**API Reference**](docs/reference/api/) - Complete API documentation for all services
- [**CLI Reference**](docs/reference/cli/) - Command-line tools and scripts
- [**Configuration Reference**](docs/reference/cli/makefile.md) - Build and configuration commands

### 🏗️ **Architecture & Design**
- [**ALB CloudFront Setup**](docs/alb-cloudfront-setup.md) - Load balancer and CDN configuration
- [**Security Guide**](docs/security-guide.md) - Security design and best practices
- [**Docker Image Management**](docs/docker-image-management.md) - Container management strategies

### 💡 **Examples & Tutorials**
- [**Basic Examples**](docs/examples/basic/) - Example directory for simple use cases
- [**Advanced Examples**](docs/examples/advanced/) - Example directory for complex AI pipelines
- [**Integration Patterns**](docs/examples/integrations/) - Example directory for third-party integrations

### ⚙️ **Operations**
- [**Monitoring**](docs/reference/api/monitoring.md) - System monitoring and observability
- [**Backup & Recovery**](docs/setup/troubleshooting.md) - Data protection and disaster recovery procedures

## 🌟 Core Features

| Feature | Description | Documentation |
|---------|-------------|---------------|
| **Multi-Deployment** | Spot, On-demand, Simple deployment options | [Deployment Guide](docs/reference/cli/deployment.md) |
| **Infrastructure as Code** | Terraform and shell script automation | [Terraform Config](terraform/main.tf) |
| **AI Services** | n8n, Ollama, Qdrant, Crawl4AI pre-configured | [API Reference](docs/reference/api/) |
| **Monitoring Stack** | Docker logging and health checks | [Monitoring Guide](docs/reference/api/monitoring.md) |
| **Cost Optimization** | Intelligent instance selection and scaling | [AWS Cost Explorer](https://console.aws.amazon.com/cost-explorer/) |
| **Security Hardening** | Input sanitization, encrypted storage, IAM, advanced health checks | [Security Guide](docs/security-guide.md) |

## 🛠️ Available Commands

| Command | Description |
|---------|-------------|
| `make setup` | Complete initial setup with security |
| `make deploy STACK_NAME=name` | Deploy infrastructure (requires STACK_NAME) |
| `make deploy-spot STACK_NAME=name` | Deploy with spot instances (requires STACK_NAME) |
| `make deploy-ondemand STACK_NAME=name` | Deploy with on-demand instances (requires STACK_NAME) |
| `make deploy-simple STACK_NAME=name` | Deploy simple development instance (requires STACK_NAME) |
| `make health-check STACK_NAME=name` | Basic health check of services (requires STACK_NAME) |
| `make health-check-advanced STACK_NAME=name` | Comprehensive health diagnostics (requires deployed instance) |
| `make test` | Run all tests |
| `make status STACK_NAME=name` | Check deployment status (requires STACK_NAME) |
| `make destroy STACK_NAME=name` | Destroy infrastructure (requires STACK_NAME) |

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

[**→ Complete CLI Reference**](docs/reference/cli/)

## 🚨 Support & Community

### Getting Help
1. **Check Documentation**: Start with our comprehensive guides
2. **Review Troubleshooting**: Common issues and solutions
3. **Search Issues**: GitHub issues for known problems
4. **Ask Questions**: Create new issue with details

### Contributing
We welcome contributions! See our documentation for:
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
| **Start Here** | [Quick Start](docs/getting-started/quick-start.md) • [Prerequisites](docs/getting-started/prerequisites.md) • [Security Guide](docs/security-guide.md) |
| **Deploy** | [Deployment Guide](docs/reference/cli/deployment.md) • [Terraform](terraform/main.tf) • [CLI Reference](docs/reference/cli/) |
| **Use** | [API Reference](docs/reference/api/) • [Examples](docs/examples/) • [CLI Tools](docs/reference/cli/) |
| **Operate** | [Monitoring](docs/reference/api/monitoring.md) • [Troubleshooting](docs/setup/troubleshooting.md) • [ALB CloudFront](docs/alb-cloudfront-setup.md) |
| **Learn** | [Docker Management](docs/docker-image-management.md) • [Security Guide](docs/security-guide.md) • [API Reference](docs/reference/api/) |

**[📚 Complete Documentation Index](docs/README.md)**