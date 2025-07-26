# Spot Instance ALB and CloudFront Integration

This document describes the new Application Load Balancer (ALB) and CloudFront CDN integration for spot instances in the GeuseMaker deployment system.

## Overview

The deployment system now supports deploying spot instances with optional load balancing and CDN capabilities, providing cost-effective production-ready infrastructure with high availability and global performance.

## New Makefile Commands

### Basic Spot Instance with ALB
```bash
make deploy-spot-alb STACK_NAME=my-spot-alb-stack
```

**Features:**
- Spot instance deployment with cost optimization
- Application Load Balancer for high availability
- Health checks and automatic failover
- SSL termination capabilities
- Real-time provisioning logs

### Spot Instance with Full CDN
```bash
make deploy-spot-cdn STACK_NAME=my-spot-cdn-stack
```

**Features:**
- All ALB features plus CloudFront CDN
- Global content delivery network
- Automatic HTTPS with AWS Certificate Manager
- DDoS protection with AWS Shield Standard
- Optimized caching for AI workloads

### Production-Ready Spot Instance
```bash
make deploy-spot-production STACK_NAME=my-prod-stack
```

**Features:**
- All CDN features plus production optimizations
- Pinned image versions for stability
- Enhanced monitoring and alerting
- Production-grade security configurations
- Cost optimization with spot pricing

## Architecture

### Basic ALB Setup
```
Internet
   ↓
Application Load Balancer (Regional)
   ↓
Spot Instance (AI Services)
   ├── n8n (Port 5678 → ALB Port 80)
   ├── Ollama (Port 11434 → ALB Port 8080)
   ├── Qdrant (Port 6333 → ALB Port 8081)
   └── Crawl4AI (Port 11235 → ALB Port 8082)
```

### Full CDN Setup
```
Internet
   ↓
CloudFront CDN (Global)
   ↓
Application Load Balancer (Regional)
   ↓
Spot Instance (AI Services)
   ├── n8n (Port 5678 → ALB Port 80)
   ├── Ollama (Port 11434 → ALB Port 8080)
   ├── Qdrant (Port 6333 → ALB Port 8081)
   └── Crawl4AI (Port 11235 → ALB Port 8082)
```

## Service Port Mapping

| Service | Internal Port | ALB Port | Description |
|---------|---------------|----------|-------------|
| n8n | 5678 | 80 | Workflow automation interface |
| Ollama | 11434 | 8080 | LLM inference API |
| Qdrant | 6333 | 8081 | Vector database API |
| Crawl4AI | 11235 | 8082 | Web scraping API |

## Environment Variables

The new commands use the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SETUP_ALB` | `false` | Enable ALB setup for spot instances |
| `SETUP_CLOUDFRONT` | `false` | Enable CloudFront CDN setup |
| `USE_PINNED_IMAGES` | `false` | Use specific image versions for stability |
| `FORCE_YES` | `true` | Skip interactive confirmations |
| `FOLLOW_LOGS` | `true` | Show real-time provisioning logs |

## Cost Optimization

### Spot Instance Savings
- **Typical Savings**: 60-90% compared to on-demand instances
- **Instance Types**: g4dn.xlarge, g4dn.2xlarge, g5.xlarge
- **Price Monitoring**: Automatic spot price analysis
- **Failover Strategy**: Automatic fallback to on-demand if needed

### ALB Costs
- **Load Balancer**: ~$16.20/month (always running)
- **LCU Hours**: ~$0.008 per LCU-hour
- **Data Processing**: $0.008 per GB processed

### CloudFront Costs
- **Requests**: $0.0075 per 10,000 HTTP requests
- **Data Transfer**: $0.085 per GB (first 10TB)
- **Origin Requests**: Additional costs for cache misses

## Usage Examples

### Development Environment
```bash
# Basic spot instance for development
make deploy-spot STACK_NAME=dev-spot-stack

# Add load balancing for testing
make deploy-spot-alb STACK_NAME=dev-spot-alb-stack
```

### Staging Environment
```bash
# Full CDN setup for performance testing
make deploy-spot-cdn STACK_NAME=staging-spot-cdn-stack
```

### Production Environment
```bash
# Production-ready deployment
make deploy-spot-production STACK_NAME=prod-spot-stack
```

### Cost-Optimized Production
```bash
# Custom spot price limit
SPOT_PRICE=0.50 make deploy-spot-production STACK_NAME=budget-prod-stack
```

## Service URLs After Deployment

### Direct Instance Access (Default)
```
n8n:      http://YOUR-IP:5678
Ollama:   http://YOUR-IP:11434
Qdrant:   http://YOUR-IP:6333
Crawl4AI: http://YOUR-IP:11235
```

### Through ALB (with deploy-spot-alb)
```
n8n:      http://ALB-DNS-NAME
Ollama:   http://ALB-DNS-NAME:8080
Qdrant:   http://ALB-DNS-NAME:8081
Crawl4AI: http://ALB-DNS-NAME:8082
```

### Through CloudFront (with deploy-spot-cdn)
```
All Services: https://CLOUDFRONT-DOMAIN-NAME
n8n:          https://CLOUDFRONT-DOMAIN-NAME
Ollama:       https://CLOUDFRONT-DOMAIN-NAME:8080
Qdrant:       https://CLOUDFRONT-DOMAIN-NAME:8081
Crawl4AI:     https://CLOUDFRONT-DOMAIN-NAME:8082
```

## Configuration Details

### ALB Health Checks
- **Protocol**: HTTP
- **Path**: `/` (service-specific health endpoints)
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Healthy Threshold**: 2 consecutive successes
- **Unhealthy Threshold**: 3 consecutive failures

### CloudFront Settings
- **Price Class**: 100 (US, Canada, Europe)
- **Viewer Protocol**: Redirect HTTP to HTTPS
- **TTL**: Minimum 0, Default 0, Maximum 1 year
- **Origin Protocol**: HTTP only (internal)
- **Query String Forwarding**: Enabled
- **Header Forwarding**: All headers

### Spot Instance Configuration
- **Instance Types**: GPU-optimized (g4dn, g5 series)
- **AMI**: Latest NVIDIA Deep Learning AMI
- **Storage**: EBS gp3 with optimized performance
- **Monitoring**: Enhanced CloudWatch monitoring
- **Security**: IAM roles and security groups

## Requirements

### ALB Requirements
- **Minimum AZs**: 2 availability zones required
- **VPC**: Must have at least 2 subnets
- **Security Groups**: Properly configured for HTTP/HTTPS traffic
- **Instance**: Must be running and healthy

### CloudFront Requirements
- **ALB**: Must be created first
- **DNS**: ALB must have valid DNS name
- **Region**: CloudFront is global but origins are regional

### Spot Instance Requirements
- **AWS Region**: Must support spot instances
- **Instance Type**: Must be available for spot requests
- **Quotas**: Sufficient spot instance quota
- **IAM Permissions**: Spot instance and ELB permissions

## Monitoring and Health Checks

### CloudWatch Alarms
- **High CPU Utilization**: >80% for 5 minutes
- **High Memory Usage**: >85% for 5 minutes
- **ALB Response Time**: >5 seconds average
- **ALB Error Rate**: >5% error rate
- **Spot Instance Interruption**: Immediate notification

### Health Check Endpoints
- **n8n**: `http://instance:5678/healthz`
- **Ollama**: `http://instance:11434/api/tags`
- **Qdrant**: `http://instance:6333/health`
- **Crawl4AI**: `http://instance:11235/health`

## Troubleshooting

### Spot Instance Issues

#### "Spot instance request failed"
```bash
# Check spot instance availability
aws ec2 describe-spot-price-history \
    --instance-types g4dn.xlarge \
    --product-description "Linux/UNIX" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)

# Check spot instance quotas
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-85EED4F2
```

#### "Spot instance interrupted"
- Check spot price history for your instance type
- Consider using a higher max price
- Monitor spot instance interruption notifications
- Use spot instance advisor for availability

### ALB Issues

#### "Need at least 2 subnets for ALB"
```bash
# Check available subnets
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available"

# Verify VPC configuration
aws ec2 describe-vpcs --vpc-ids $VPC_ID
```

#### "Failed to create Application Load Balancer"
- Check AWS quotas for ALBs in your region
- Verify IAM permissions for ELB operations
- Ensure security groups allow HTTP traffic

### CloudFront Issues

#### "No ALB DNS name provided"
- Ensure ALB was created successfully first
- Check that `SETUP_ALB=true` is set
- Verify ALB creation didn't fail silently

#### "CloudFront distribution creation failed"
- Check AWS quotas for CloudFront distributions
- Verify IAM permissions for CloudFront operations
- Ensure ALB is accessible from internet

## Best Practices

### Cost Optimization
1. **Monitor spot prices** regularly and adjust max price
2. **Use appropriate instance types** for your workload
3. **Enable CloudFront caching** to reduce origin requests
4. **Set up billing alerts** for unexpected costs
5. **Use spot instance advisor** for availability insights

### Performance Optimization
1. **Choose optimal regions** for your users
2. **Configure appropriate cache TTLs** for your content
3. **Monitor ALB target group health** regularly
4. **Use CloudFront edge locations** strategically
5. **Optimize application response times**

### Security Best Practices
1. **Use security groups** to restrict access
2. **Enable CloudFront security features** (WAF, Shield)
3. **Monitor CloudTrail logs** for suspicious activity
4. **Regularly update AMIs** and application versions
5. **Use IAM roles** instead of access keys

### High Availability
1. **Deploy across multiple AZs** when possible
2. **Set up proper health checks** for all services
3. **Monitor spot instance interruption** notifications
4. **Have fallback strategies** for spot instance failures
5. **Use CloudFront for global availability**

## Migration Guide

### From Direct Spot Instance to ALB
1. Deploy with ALB: `make deploy-spot-alb STACK_NAME=my-stack`
2. Update application URLs to use ALB DNS name
3. Test all services through ALB
4. Update any hardcoded instance IP addresses

### From ALB to ALB + CloudFront
1. Redeploy with CDN: `make deploy-spot-cdn STACK_NAME=my-stack`
2. Update DNS records to point to CloudFront
3. Test caching behavior
4. Monitor cache hit ratios

### From On-Demand to Spot Instance
1. Deploy spot instance: `make deploy-spot STACK_NAME=my-stack`
2. Test application functionality
3. Monitor spot instance stability
4. Consider ALB/CloudFront for production

## Support and Resources

### AWS Documentation
- [Spot Instances User Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- [Application Load Balancer User Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/)

### GeuseMaker Resources
- Main deployment script: `scripts/aws-deployment-unified.sh`
- Spot instance library: `lib/spot-instance.sh`
- Test script: `test-spot-alb-commands.sh`

### Getting Help
For issues with spot instance ALB/CloudFront setup:
1. Check the deployment logs for error messages
2. Verify AWS permissions and quotas
3. Test connectivity to services directly
4. Review AWS CloudFormation events if using infrastructure as code
5. Check spot instance advisor for availability

## Example Workflows

### Development Workflow
```bash
# 1. Deploy basic spot instance
make deploy-spot STACK_NAME=dev-$(date +%Y%m%d)

# 2. Test application functionality
make health-check STACK_NAME=dev-$(date +%Y%m%d)

# 3. Add load balancing for testing
make deploy-spot-alb STACK_NAME=dev-alb-$(date +%Y%m%d)

# 4. Clean up when done
make destroy STACK_NAME=dev-$(date +%Y%m%d)
```

### Production Workflow
```bash
# 1. Deploy production-ready stack
make deploy-spot-production STACK_NAME=prod-$(date +%Y%m%d)

# 2. Verify all services are healthy
make health-check-advanced STACK_NAME=prod-$(date +%Y%m%d)

# 3. Monitor performance and costs
make monitor

# 4. Update when needed
make deploy-spot-production STACK_NAME=prod-$(date +%Y%m%d)
```

This comprehensive integration provides cost-effective, production-ready infrastructure with high availability and global performance for AI workloads. 