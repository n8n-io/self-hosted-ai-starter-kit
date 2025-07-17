🚀 AI Starter Kit

📋 Overview
This is a GPU-optimized AI starter kit for deploying AI workflows on AWS using n8n, Ollama, Qdrant, and Crawl4AI. It supports models like DeepSeek-R1:8B, Qwen2.5-VL:7B, and more.

🔧 Prerequisites
- AWS CLI configured
- Docker and Docker Compose
- AWS account with necessary permissions

🚀 Deployment
1. Configure environment variables in SSM (see below).
2. Run `./scripts/aws-deployment.sh` with optional flags (e.g., --region us-west-2).

⚙️ Configuration
Store secrets in AWS SSM under /faibulkit/ prefix:
- /faibulkit/n8n/ENCRYPTION_KEY
- /faibulkit/OPENAI_API_KEY
- etc.

Update docker-compose.gpu-optimized.yml for custom settings.

🔗 Usage
After setting up DNS CNAME records pointing to the CloudFront distribution domain (output by the script), access services via:
- n8n: https://n8n.geuse.io
- Qdrant: https://qdrant.geuse.io

Note: Configure your DNS provider to point these subdomains to the CloudFront domain (e.g., xxxxx.cloudfront.net). Direct IP access is still available but not recommended for production.

📊 Monitoring
GPU monitoring via gpu-monitor service. Metrics in /shared/gpu_metrics.json.

🧹 Cleanup
Run the script with cleanup logic or manually delete resources via AWS console.

❗ Troubleshooting
- Check logs: docker-compose logs
- Verify SSM params
- Ensure GPU drivers are installed 