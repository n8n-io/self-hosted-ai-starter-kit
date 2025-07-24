# Management Commands Reference

> Complete reference for operations, monitoring, and maintenance CLI commands

This document covers all management and operational commands for maintaining, monitoring, and operating GeuseMaker deployments.

## 🎯 Quick Management Commands

### Status and Monitoring
```bash
make status STACK_NAME=my-stack          # Check deployment status
make logs STACK_NAME=my-stack            # View application logs
make monitor                             # Open monitoring dashboard
```

### Maintenance Operations
```bash
make backup STACK_NAME=my-stack          # Create system backup
make validate                            # Validate configurations
make security-scan                       # Run security checks
```

### Resource Management
```bash
make destroy STACK_NAME=my-stack         # Clean up all resources
make cost-estimate STACK_NAME=my-stack   # Estimate costs
```

## 📊 Status and Health Monitoring

### Deployment Status Commands

#### Check Overall Status
```bash
make status STACK_NAME=my-stack
```
**Output includes:**
- EC2 instance status and health
- Service availability (n8n, Ollama, Qdrant, Crawl4AI)
- Resource utilization (CPU, memory, disk)
- Network connectivity
- Security group configurations

#### Detailed Status Script
```bash
./tools/check-status.sh my-stack [--verbose]
```

**Options:**
- `--verbose`: Detailed output with metrics
- `--json`: JSON-formatted output
- `--services-only`: Only check service health
- `--resources-only`: Only check resource usage

**Example output:**
```
🚀 GeuseMaker Status Report
Stack: my-stack
Region: us-east-1

✅ Instance Status
   Instance ID: i-1234567890abcdef0
   Instance Type: g4dn.xlarge
   State: running
   Uptime: 2d 14h 32m

✅ Service Health
   n8n: healthy (port 5678)
   Ollama: healthy (port 11434)
   Qdrant: healthy (port 6333)
   Crawl4AI: healthy (port 11235)

📊 Resource Usage
   CPU: 45.2% (4 cores)
   Memory: 67.8% (16GB total)
   Disk: 34.1% (100GB total)
   GPU: 65.4% (NVIDIA T4)
```

### Health Check Commands

#### Service Health Checks
```bash
# Check all services
./tools/health-check.sh my-stack

# Check specific service
./tools/health-check.sh my-stack --service ollama

# Continuous monitoring
./tools/health-check.sh my-stack --watch --interval 30
```

#### System Health Validation
```bash
# Comprehensive health check
./scripts/validate-deployment.sh my-stack

# Quick health check
curl http://INSTANCE_IP:5678/healthz     # n8n health
curl http://INSTANCE_IP:11434/api/tags   # Ollama health
curl http://INSTANCE_IP:6333/health      # Qdrant health
curl http://INSTANCE_IP:11235/health     # Crawl4AI health
```

## 📋 Log Management

### Application Logs

#### View Real-Time Logs
```bash
make logs STACK_NAME=my-stack
```

#### Log Viewer Script
```bash
./tools/view-logs.sh my-stack [OPTIONS]
```

**Options:**
- `--service SERVICE`: Specific service logs (n8n, ollama, qdrant, crawl4ai)
- `--follow`: Follow log output (like tail -f)
- `--lines N`: Show last N lines
- `--since TIME`: Show logs since specific time
- `--level LEVEL`: Filter by log level (error, warn, info, debug)

**Examples:**
```bash
# Follow all application logs
./tools/view-logs.sh my-stack --follow

# View Ollama logs only
./tools/view-logs.sh my-stack --service ollama --lines 100

# View error logs from last hour
./tools/view-logs.sh my-stack --level error --since "1 hour ago"

# View logs since specific time
./tools/view-logs.sh my-stack --since "2024-01-01 12:00:00"
```

### System Logs

#### Instance System Logs
```bash
# SSH into instance and view logs
ssh -i my-stack-key.pem ubuntu@INSTANCE_IP

# System logs
sudo journalctl -f                    # All system logs
sudo journalctl -u docker            # Docker service logs
sudo journalctl -u cloud-init        # Cloud-init logs

# Application-specific logs
cd GeuseMaker
docker-compose logs -f               # All service logs
docker-compose logs -f ollama        # Specific service logs
```

#### CloudWatch Logs
```bash
# List log groups
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/GeuseMaker"

# View CloudWatch logs
aws logs tail "/aws/GeuseMaker/my-stack" --follow

# Query CloudWatch Insights
aws logs start-query \
  --log-group-name "/aws/GeuseMaker/my-stack" \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/'
```

## 🔧 Maintenance Operations

### System Updates

#### Update System Packages
```bash
# SSH into instance
ssh -i my-stack-key.pem ubuntu@INSTANCE_IP

# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Docker images
cd GeuseMaker
docker-compose pull
docker-compose up -d
```

#### Automated Update Script
```bash
./tools/update-system.sh my-stack [OPTIONS]
```

**Options:**
- `--packages-only`: Update system packages only
- `--docker-only`: Update Docker images only
- `--restart-services`: Restart services after update
- `--backup-first`: Create backup before updating

### Service Management

#### Restart Services
```bash
# Restart all services
./tools/restart-services.sh my-stack

# Restart specific service
./tools/restart-services.sh my-stack --service ollama

# Graceful restart (wait for connections to finish)
./tools/restart-services.sh my-stack --graceful
```

#### Service Configuration Updates
```bash
# Update service configuration
./tools/update-config.sh my-stack --service ollama --config /path/to/new/config

# Reload configuration without restart
./tools/reload-config.sh my-stack --service n8n
```

### Resource Management

#### Disk Space Management
```bash
# Check disk usage
./tools/check-disk-usage.sh my-stack

# Clean up disk space
./tools/cleanup-disk.sh my-stack [OPTIONS]
```

**Cleanup options:**
- `--docker-cleanup`: Remove unused Docker images and containers
- `--log-cleanup`: Rotate and compress old logs
- `--temp-cleanup`: Remove temporary files
- `--backup-cleanup`: Remove old backup files

#### Memory Management
```bash
# Check memory usage
./tools/check-memory.sh my-stack

# Clear memory caches (if needed)
./tools/clear-caches.sh my-stack
```

## 💾 Backup and Recovery

### Backup Operations

#### Create Backup
```bash
make backup STACK_NAME=my-stack
```

#### Backup Script
```bash
./tools/backup.sh my-stack [OPTIONS]
```

**Backup options:**
- `--type TYPE`: Backup type (full, incremental, data-only)
- `--destination DEST`: Backup destination (s3, local, efs)
- `--encrypt`: Encrypt backup files
- `--compress`: Compress backup files

**Examples:**
```bash
# Full backup to S3
./tools/backup.sh my-stack --type full --destination s3://my-backups/

# Data-only backup
./tools/backup.sh my-stack --type data-only --encrypt --compress

# Quick local backup
./tools/backup.sh my-stack --destination /backup/local/
```

#### Automated Backup Schedule
```bash
# Setup automated backups
./tools/setup-backup-schedule.sh my-stack [OPTIONS]
```

**Schedule options:**
- `--daily`: Daily backups at specified time
- `--weekly`: Weekly backups on specified day
- `--retention DAYS`: Backup retention period
- `--notify EMAIL`: Email notifications

### Recovery Operations

#### Restore from Backup
```bash
./tools/restore.sh my-stack --backup-id BACKUP_ID [OPTIONS]
```

**Restore options:**
- `--data-only`: Restore data only (preserve configuration)
- `--config-only`: Restore configuration only
- `--point-in-time TIME`: Restore to specific point in time
- `--verify`: Verify restore integrity

#### Disaster Recovery
```bash
# Complete disaster recovery
./tools/disaster-recovery.sh my-stack --backup-id BACKUP_ID

# Recovery validation
./tools/validate-recovery.sh my-stack
```

## 🔍 Performance Monitoring

### Performance Metrics

#### System Performance
```bash
# Real-time performance monitoring
./tools/monitor-performance.sh my-stack [OPTIONS]
```

**Monitoring options:**
- `--interval SECONDS`: Update interval (default: 10)
- `--duration MINUTES`: Monitoring duration
- `--output FORMAT`: Output format (console, json, csv)
- `--alerts`: Enable performance alerts

#### Service Performance
```bash
# Monitor specific service performance
./tools/monitor-service.sh my-stack --service ollama

# GPU monitoring (for GPU instances)
./tools/monitor-gpu.sh my-stack

# Network monitoring
./tools/monitor-network.sh my-stack
```

### Performance Optimization

#### Automatic Performance Tuning
```bash
# Run performance optimization
./tools/optimize-performance.sh my-stack [OPTIONS]
```

**Optimization options:**
- `--cpu-optimize`: Optimize CPU usage
- `--memory-optimize`: Optimize memory usage
- `--gpu-optimize`: Optimize GPU usage (if available)
- `--disk-optimize`: Optimize disk I/O

#### Performance Reports
```bash
# Generate performance report
./tools/generate-performance-report.sh my-stack --period 24h

# Compare performance between periods
./tools/compare-performance.sh my-stack --before "2024-01-01" --after "2024-01-02"
```

## 🔒 Security Management

### Security Scanning

#### Comprehensive Security Scan
```bash
make security-scan
```

#### Security Validation Script
```bash
./tools/security-scan.sh my-stack [OPTIONS]
```

**Security scan options:**
- `--vulnerability-scan`: Check for known vulnerabilities
- `--config-audit`: Audit security configurations
- `--network-scan`: Scan network security
- `--compliance-check`: Check compliance requirements

#### Security Updates
```bash
# Apply security updates
./tools/apply-security-updates.sh my-stack

# Check for security advisories
./tools/check-security-advisories.sh my-stack
```

### Access Management

#### SSH Key Management
```bash
# Rotate SSH keys
./tools/rotate-ssh-keys.sh my-stack --new-key /path/to/new/key.pem

# Add SSH key for user
./tools/add-ssh-key.sh my-stack --user username --key-file /path/to/key.pub

# Remove SSH key
./tools/remove-ssh-key.sh my-stack --user username
```

#### Certificate Management
```bash
# Update SSL certificates
./tools/update-certificates.sh my-stack

# Check certificate expiration
./tools/check-certificate-expiry.sh my-stack
```

## 💰 Cost Management

### Cost Monitoring

#### Cost Estimation
```bash
make cost-estimate STACK_NAME=my-stack HOURS=24
```

#### Detailed Cost Analysis
```bash
./tools/cost-analysis.sh my-stack [OPTIONS]
```

**Cost analysis options:**
- `--period PERIOD`: Analysis period (1d, 7d, 30d)
- `--breakdown`: Show cost breakdown by service
- `--compare`: Compare with previous period
- `--forecast`: Show cost forecast

### Cost Optimization

#### Resource Optimization
```bash
# Analyze resource usage for cost optimization
./tools/optimize-costs.sh my-stack [OPTIONS]
```

**Optimization options:**
- `--right-size`: Recommend right-sized instances
- `--spot-analysis`: Analyze spot instance opportunities
- `--reserved-analysis`: Analyze reserved instance opportunities
- `--schedule-optimization`: Optimize instance scheduling

#### Instance Management
```bash
# Stop instance (preserve data)
./tools/stop-instance.sh my-stack

# Start stopped instance
./tools/start-instance.sh my-stack

# Schedule instance start/stop
./tools/schedule-instance.sh my-stack --start "09:00" --stop "18:00"
```

## 🚨 Troubleshooting and Diagnostics

### Diagnostic Tools

#### System Diagnostics
```bash
# Run comprehensive diagnostics
./tools/run-diagnostics.sh my-stack

# Quick diagnostic check
./tools/quick-diagnostic.sh my-stack

# Service-specific diagnostics
./tools/diagnose-service.sh my-stack --service ollama
```

#### Network Diagnostics
```bash
# Check network connectivity
./tools/check-connectivity.sh my-stack

# Test service endpoints
./tools/test-endpoints.sh my-stack

# Check DNS resolution
./tools/check-dns.sh my-stack
```

### Issue Resolution

#### Common Issue Fixes
```bash
# Fix common service issues
./tools/fix-common-issues.sh my-stack

# Restart hung services
./tools/restart-hung-services.sh my-stack

# Clear service locks
./tools/clear-service-locks.sh my-stack
```

#### Emergency Recovery
```bash
# Emergency service restart
./tools/emergency-restart.sh my-stack

# Force service recovery
./tools/force-recovery.sh my-stack

# Emergency backup before recovery
./tools/emergency-backup.sh my-stack
```

## 📞 Remote Management

### SSH Management

#### Connect to Instance
```bash
# Connect with key file
ssh -i my-stack-key.pem ubuntu@INSTANCE_IP

# Connect through bastion (if configured)
ssh -i bastion-key.pem -J ubuntu@BASTION_IP ubuntu@INSTANCE_IP

# Connect with session manager
aws ssm start-session --target i-1234567890abcdef0
```

#### Remote Command Execution
```bash
# Execute remote commands
./tools/remote-execute.sh my-stack "docker ps"

# Upload and execute script
./tools/remote-script.sh my-stack /path/to/local/script.sh

# Batch remote commands
./tools/batch-remote.sh my-stack commands.txt
```

### File Management

#### File Transfer
```bash
# Upload files to instance
scp -i my-stack-key.pem file.txt ubuntu@INSTANCE_IP:~/

# Download files from instance
scp -i my-stack-key.pem ubuntu@INSTANCE_IP:~/logs.txt ./

# Sync directories
rsync -avz -e "ssh -i my-stack-key.pem" ./local-dir/ ubuntu@INSTANCE_IP:~/remote-dir/
```

#### Configuration Management
```bash
# Upload configuration files
./tools/upload-config.sh my-stack --file config.yaml --destination /etc/app/

# Download configuration files
./tools/download-config.sh my-stack --file /etc/app/config.yaml --destination ./
```

---

[**← Back to CLI Overview**](README.md) | [**→ Development Tools**](development.md)

---

**Last Updated:** January 2025  
**Compatibility:** All deployment types and management scenarios