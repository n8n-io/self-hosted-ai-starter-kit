# ALB and CloudFront Setup Guide

This document explains the new Application Load Balancer (ALB) and CloudFront CDN setup functionality added to the AI Starter Kit deployment system.

## Overview

The deployment system now supports optional ALB and CloudFront setup through command-line flags, allowing you to:

- **Scale your applications** with load balancing across multiple availability zones
- **Improve performance** with global CloudFront CDN distribution
- **Enhance security** with SSL termination and DDoS protection
- **Enable high availability** with health checks and automatic failover

## Quick Start

### Deploy with ALB Only
```bash
./scripts/aws-deployment.sh --setup-alb
```

### Deploy with CloudFront Only (requires ALB)
```bash
./scripts/aws-deployment.sh --setup-alb --setup-cloudfront
```

### Deploy with Both (Convenience Flag)
```bash
./scripts/aws-deployment.sh --setup-cdn
```

### Full Production Setup
```bash
./scripts/aws-deployment.sh --setup-cdn --cross-region
```

## Command Line Options

### New Flags

| Flag | Description | Dependencies |
|------|-------------|--------------|
| `--setup-alb` | Setup Application Load Balancer | Requires 2+ AZs |
| `--setup-cloudfront` | Setup CloudFront CDN distribution | Requires ALB |
| `--setup-cdn` | Setup both ALB and CloudFront | Convenience flag |

### Environment Variables

```bash
# Control ALB setup
export SETUP_ALB=true

# Control CloudFront setup  
export SETUP_CLOUDFRONT=true

# Run deployment
./scripts/aws-deployment.sh
```

## What Gets Created

### Application Load Balancer (ALB)
When `--setup-alb` is enabled, the system creates:

- **Load Balancer**: Internet-facing ALB with SSL termination capabilities
- **Target Groups**: Separate target groups for each service with health checks
- **Listeners**: HTTP listeners on different ports for service separation
- **Health Checks**: Automated health monitoring for all services

#### Service Port Mapping
- **n8n**: Port 80 (main workflow interface)
- **Ollama**: Port 8080 (LLM inference API)
- **Qdrant**: Port 8081 (vector database API)
- **Crawl4AI**: Port 8082 (web scraping API)

### CloudFront Distribution
When `--setup-cloudfront` is enabled, the system creates:

- **CDN Distribution**: Global content delivery network
- **SSL Certificate**: Automatic HTTPS with AWS Certificate Manager
- **Cache Behaviors**: Optimized caching rules for AI workloads
- **Origin Configuration**: ALB as the origin server

## Architecture Overview

```
Internet
   ↓
CloudFront CDN (Global)
   ↓
Application Load Balancer (Regional)
   ↓
EC2 Instance (AI Services)
   ├── n8n (Port 5678 → ALB Port 80)
   ├── Ollama (Port 11434 → ALB Port 8080)
   ├── Qdrant (Port 6333 → ALB Port 8081)
   └── Crawl4AI (Port 11235 → ALB Port 8082)
```

## Usage Examples

### Development Environment
```bash
# Basic deployment without load balancing
./scripts/aws-deployment.sh

# Add load balancing for testing
./scripts/aws-deployment.sh --setup-alb
```

### Staging Environment
```bash
# Full CDN setup for performance testing
./scripts/aws-deployment.sh --setup-cdn
```

### Production Environment
```bash
# Production deployment with best region selection
./scripts/aws-deployment.sh --setup-cdn --cross-region --use-pinned-images

# Production deployment with specific instance type
./scripts/aws-deployment.sh --setup-cdn --instance-type g4dn.2xlarge
```

### Cost-Optimized Production
```bash
# Production with budget constraints
./scripts/aws-deployment.sh --setup-cdn --max-spot-price 1.50
```

## Service URLs After Deployment

### Direct Instance Access (Default)
```
n8n:      http://YOUR-IP:5678
Ollama:   http://YOUR-IP:11434
Qdrant:   http://YOUR-IP:6333
Crawl4AI: http://YOUR-IP:11235
```

### Through ALB (with --setup-alb)
```
n8n:      http://ALB-DNS-NAME
Ollama:   http://ALB-DNS-NAME:8080
Qdrant:   http://ALB-DNS-NAME:8081
Crawl4AI: http://ALB-DNS-NAME:8082
```

### Through CloudFront (with --setup-cdn)
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

## Troubleshooting

### ALB Issues

#### "Need at least 2 subnets for ALB"
```bash
# Check available subnets
aws ec2 describe-subnets --filters "Name=state,Values=available"

# Verify VPC configuration
aws ec2 describe-vpcs
```

#### "Failed to create Application Load Balancer"
- Check AWS quotas for ALBs in your region
- Verify IAM permissions for ELB operations
- Ensure security groups allow HTTP traffic

### CloudFront Issues

#### "No ALB DNS name provided"
- Ensure ALB was created successfully first
- Check that `--setup-alb` or `--setup-cdn` is used
- Verify ALB creation didn't fail silently

#### "CloudFront distribution creation failed"
- Check AWS quotas for CloudFront distributions
- Verify IAM permissions for CloudFront operations
- Ensure ALB is accessible from internet

### Performance Issues

#### Slow ALB Response
- Check target group health status
- Verify instance is not overloaded
- Review ALB access logs

#### CloudFront Cache Misses
- Review cache behaviors and TTL settings
- Check origin response headers
- Monitor CloudFront metrics

## Monitoring and Logging

### ALB Monitoring
```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn YOUR-TG-ARN

# View ALB metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=app/YOUR-ALB-NAME \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

### CloudFront Monitoring
```bash
# Check distribution status
aws cloudfront get-distribution --id YOUR-DISTRIBUTION-ID

# View CloudFront metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=YOUR-DISTRIBUTION-ID \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

## Cost Considerations

### ALB Costs
- **Load Balancer**: ~$16.20/month (always running)
- **LCU Hours**: ~$0.008 per LCU-hour
- **Data Processing**: $0.008 per GB processed

### CloudFront Costs
- **Requests**: $0.0075 per 10,000 HTTP requests
- **Data Transfer**: $0.085 per GB (first 10TB)
- **Origin Requests**: Additional costs for cache misses

### Cost Optimization Tips
1. **Use appropriate cache TTLs** to reduce origin requests
2. **Enable compression** to reduce data transfer costs
3. **Monitor usage** with CloudWatch metrics
4. **Consider regional deployments** if global CDN isn't needed

## Security Considerations

### ALB Security
- ALB provides SSL termination and DDoS protection
- Security groups control access to ALB
- Target groups only accept traffic from ALB
- Health checks verify service availability

### CloudFront Security
- Automatic SSL/TLS encryption for all content
- Geographic restrictions can be configured
- AWS Shield Standard DDoS protection included
- Web Application Firewall (WAF) can be added

## Best Practices

### Development
- Use ALB for load testing multiple instances
- Test health check endpoints before production
- Monitor ALB target group health

### Production
- Always use `--setup-cdn` for production workloads
- Enable detailed monitoring and alerting
- Implement proper health check endpoints
- Use specific image versions with `--use-pinned-images`
- Consider multiple AZ deployment for high availability

### Cost Management
- Monitor ALB and CloudFront usage regularly
- Set up billing alerts for unexpected costs
- Use appropriate cache settings for your workload
- Consider regional vs global distribution needs

## Migration Guide

### From Direct Instance to ALB
1. Deploy with ALB: `./scripts/aws-deployment.sh --setup-alb`
2. Update application URLs to use ALB DNS name
3. Test all services through ALB
4. Update any hardcoded instance IP addresses

### From ALB to ALB + CloudFront
1. Redeploy with CDN: `./scripts/aws-deployment.sh --setup-cdn`
2. Update DNS records to point to CloudFront
3. Test caching behavior
4. Monitor cache hit ratios

## Support and Resources

### AWS Documentation
- [Application Load Balancer User Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/)

### AI Starter Kit Resources
- Main deployment script: `scripts/aws-deployment.sh`
- Simple deployment: `scripts/aws-deployment-simple.sh`
- Test script: `test-alb-cloudfront.sh`

### Getting Help
For issues with ALB/CloudFront setup:
1. Check the deployment logs for error messages
2. Verify AWS permissions and quotas
3. Test connectivity to services directly
4. Review AWS CloudFormation events if using infrastructure as code