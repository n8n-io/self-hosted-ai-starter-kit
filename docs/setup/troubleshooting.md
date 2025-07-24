# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the GeuseMaker deployment and operation.

## 🚨 Emergency Procedures

### Quick Health Check
```bash
# Check overall deployment status
make status STACK_NAME=your-stack

# Check service health
ssh -i your-key.pem ubuntu@your-ip 'cd GeuseMaker && ./health-check.sh'

# View recent logs
make logs STACK_NAME=your-stack
```

### Emergency Contacts
- **Critical Issues**: Check CloudWatch alarms
- **Security Incidents**: Review security logs immediately
- **Data Loss**: Activate backup recovery procedures

## 🔍 Common Issues

### Deployment Issues

#### Issue: AWS Credentials Not Found
**Symptoms:**
```
Error: AWS credentials are not configured or invalid
```

**Solutions:**
1. Configure AWS CLI:
   ```bash
   aws configure
   ```
2. Check credentials:
   ```bash
   aws sts get-caller-identity
   ```
3. Verify IAM permissions:
   ```bash
   aws iam get-user
   ```

#### Issue: Insufficient Permissions
**Symptoms:**
```
UnauthorizedOperation: You are not authorized to perform this operation
```

**Solutions:**
1. Review IAM policy requirements in [Security Model](../architecture/security-model.md)
2. Add required permissions:
   - EC2 full access
   - IAM role creation
   - CloudWatch logs
   - VPC management

#### Issue: Instance Launch Failure
**Symptoms:**
```
Failed to launch instance: InsufficientInstanceCapacity
```

**Solutions:**
1. Try different availability zones:
   ```bash
   ./scripts/aws-deployment-unified.sh -t spot --region us-west-2 STACK_NAME
   ```
2. Use different instance type:
   ```bash
   ./scripts/aws-deployment-unified.sh -i g4dn.large STACK_NAME
   ```
3. Switch to on-demand instances:
   ```bash
   ./scripts/aws-deployment-unified.sh -t ondemand STACK_NAME
   ```

#### Issue: Spot Instance Interruption
**Symptoms:**
```
Spot instance terminated due to price increase
```

**Solutions:**
1. Increase spot price bid:
   ```bash
   ./scripts/aws-deployment-unified.sh -p 1.00 STACK_NAME
   ```
2. Use spot fleets for better availability
3. Switch to on-demand for critical workloads

### Service Issues

#### Issue: n8n Not Accessible
**Symptoms:**
- Connection timeout to port 5678
- Service appears down

**Diagnostics:**
```bash
# Check if n8n container is running
ssh -i key.pem ubuntu@ip 'docker ps | grep n8n'

# Check n8n logs
ssh -i key.pem ubuntu@ip 'docker logs n8n'

# Check port connectivity
telnet your-ip 5678
```

**Solutions:**
1. Restart n8n service:
   ```bash
   ssh -i key.pem ubuntu@ip 'cd GeuseMaker && docker-compose restart n8n'
   ```
2. Check security group allows port 5678
3. Verify UFW firewall rules:
   ```bash
   ssh -i key.pem ubuntu@ip 'sudo ufw status'
   ```

#### Issue: Ollama Model Loading Fails
**Symptoms:**
```
Error: model not found or failed to load
```

**Diagnostics:**
```bash
# Check Ollama service
ssh -i key.pem ubuntu@ip 'curl http://localhost:11434/api/tags'

# Check GPU availability
ssh -i key.pem ubuntu@ip 'nvidia-smi'

# Check Ollama logs
ssh -i key.pem ubuntu@ip 'docker logs ollama'
```

**Solutions:**
1. Pull required models:
   ```bash
   ssh -i key.pem ubuntu@ip 'docker exec ollama ollama pull llama2'
   ```
2. Check GPU memory usage:
   ```bash
   ssh -i key.pem ubuntu@ip 'nvidia-smi'
   ```
3. Restart Ollama with more memory:
   ```bash
   # Edit docker-compose.yml to increase memory limits
   ```

#### Issue: Qdrant Database Connection Failed
**Symptoms:**
```
Failed to connect to Qdrant: Connection refused
```

**Diagnostics:**
```bash
# Check Qdrant status
ssh -i key.pem ubuntu@ip 'curl http://localhost:6333/health'

# Check Qdrant logs
ssh -i key.pem ubuntu@ip 'docker logs qdrant'

# Check disk space
ssh -i key.pem ubuntu@ip 'df -h'
```

**Solutions:**
1. Restart Qdrant:
   ```bash
   ssh -i key.pem ubuntu@ip 'cd GeuseMaker && docker-compose restart qdrant'
   ```
2. Check storage volume mounting
3. Verify collection configuration

### Performance Issues

#### Issue: High CPU Usage
**Symptoms:**
- System feels slow
- High CPU usage in CloudWatch

**Diagnostics:**
```bash
# Check current CPU usage
ssh -i key.pem ubuntu@ip 'top'

# Check per-service CPU usage
ssh -i key.pem ubuntu@ip 'docker stats'

# Review CloudWatch metrics
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization
```

**Solutions:**
1. Scale up instance size:
   ```bash
   # Deploy with larger instance
   ./scripts/aws-deployment-unified.sh -i g4dn.2xlarge STACK_NAME
   ```
2. Optimize container resource limits
3. Review and optimize workflows

#### Issue: High Memory Usage
**Symptoms:**
- Out of memory errors
- System becomes unresponsive

**Diagnostics:**
```bash
# Check memory usage
ssh -i key.pem ubuntu@ip 'free -h'

# Check per-container memory
ssh -i key.pem ubuntu@ip 'docker stats --no-stream'

# Check for memory leaks
ssh -i key.pem ubuntu@ip 'ps aux --sort=-%mem | head'
```

**Solutions:**
1. Increase instance memory
2. Adjust container memory limits
3. Implement memory monitoring alerts
4. Add swap space if needed (temporary solution)

#### Issue: Disk Space Full
**Symptoms:**
```
No space left on device
```

**Diagnostics:**
```bash
# Check disk usage
ssh -i key.pem ubuntu@ip 'df -h'

# Find large files
ssh -i key.pem ubuntu@ip 'du -h /home/ubuntu/GeuseMaker | sort -rh | head -10'

# Check Docker space usage
ssh -i key.pem ubuntu@ip 'docker system df'
```

**Solutions:**
1. Clean up Docker resources:
   ```bash
   ssh -i key.pem ubuntu@ip 'docker system prune -a'
   ```
2. Remove old log files:
   ```bash
   ssh -i key.pem ubuntu@ip 'sudo journalctl --vacuum-time=7d'
   ```
3. Increase EBS volume size
4. Set up log rotation

### Network Issues

#### Issue: Cannot SSH to Instance
**Symptoms:**
- SSH connection timeout
- Permission denied

**Diagnostics:**
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids sg-xxxxxxxx

# Check instance status
aws ec2 describe-instances --instance-ids i-xxxxxxxx

# Test connectivity
nc -zv your-ip 22
```

**Solutions:**
1. Verify key file permissions:
   ```bash
   chmod 600 your-key.pem
   ```
2. Check security group allows SSH (port 22)
3. Use Session Manager as alternative:
   ```bash
   aws ssm start-session --target i-xxxxxxxx
   ```

#### Issue: Services Not Reachable Externally
**Symptoms:**
- Services work locally but not from internet
- Connection timeouts from external clients

**Diagnostics:**
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids sg-xxxxxxxx

# Test local connectivity
ssh -i key.pem ubuntu@ip 'curl http://localhost:5678'

# Check UFW status
ssh -i key.pem ubuntu@ip 'sudo ufw status numbered'
```

**Solutions:**
1. Update security group rules
2. Configure UFW firewall correctly
3. Check VPC routing tables
4. Verify public IP assignment

## 🔧 Advanced Troubleshooting

### Debug Mode Deployment
```bash
# Deploy with debug logging
DEBUG=true ./scripts/aws-deployment-unified.sh STACK_NAME

# Access debug information
ssh -i key.pem ubuntu@ip 'tail -f /var/log/user-data.log'
```

### Log Analysis

#### System Logs
```bash
# CloudWatch logs
aws logs tail /aws/GeuseMaker/STACK_NAME --follow

# System logs
ssh -i key.pem ubuntu@ip 'sudo journalctl -f'

# Docker logs
ssh -i key.pem ubuntu@ip 'docker-compose logs -f'
```

#### Application Logs
```bash
# n8n logs
ssh -i key.pem ubuntu@ip 'docker logs n8n --tail 100'

# Ollama logs
ssh -i key.pem ubuntu@ip 'docker logs ollama --tail 100'

# Qdrant logs
ssh -i key.pem ubuntu@ip 'docker logs qdrant --tail 100'
```

### Performance Profiling

#### GPU Monitoring
```bash
# Check GPU utilization
ssh -i key.pem ubuntu@ip 'nvidia-smi -l 1'

# GPU memory usage
ssh -i key.pem ubuntu@ip 'nvidia-smi --query-gpu=memory.used,memory.total --format=csv'
```

#### Container Resource Usage
```bash
# Real-time container stats
ssh -i key.pem ubuntu@ip 'docker stats'

# Container resource limits
ssh -i key.pem ubuntu@ip 'docker inspect container_name | grep -A 10 "Resources"'
```

## 🛠️ Recovery Procedures

### Service Recovery

#### Complete Service Restart
```bash
# Stop all services
ssh -i key.pem ubuntu@ip 'cd GeuseMaker && docker-compose down'

# Clean up containers and networks
ssh -i key.pem ubuntu@ip 'docker system prune -f'

# Restart all services
ssh -i key.pem ubuntu@ip 'cd GeuseMaker && docker-compose up -d'
```

#### Individual Service Recovery
```bash
# Restart specific service
ssh -i key.pem ubuntu@ip 'cd GeuseMaker && docker-compose restart n8n'

# Rebuild service from scratch
ssh -i key.pem ubuntu@ip 'cd GeuseMaker && docker-compose up -d --force-recreate n8n'
```

### Data Recovery

#### Database Recovery
```bash
# Check database connectivity
ssh -i key.pem ubuntu@ip 'docker exec postgres psql -U n8n -d n8n -c "SELECT version();"'

# Restore from backup
ssh -i key.pem ubuntu@ip 'docker exec postgres pg_restore -U n8n -d n8n /backup/backup.sql'
```

#### Configuration Recovery
```bash
# Restore configuration from backup
ssh -i key.pem ubuntu@ip 'cp /backup/environment.env config/environment.env'

# Regenerate configuration
ssh -i key.pem ubuntu@ip 'cd GeuseMaker && ./scripts/config-manager.sh generate production'
```

### Infrastructure Recovery

#### Complete Stack Recreation
```bash
# Destroy current stack
./scripts/aws-deployment-unified.sh --cleanup STACK_NAME

# Redeploy with backups
./scripts/aws-deployment-unified.sh STACK_NAME

# Restore data from backup
./tools/restore-backup.sh STACK_NAME backup-id
```

## 🔍 Diagnostic Commands

### Quick Diagnostic Script
Create this script for rapid troubleshooting:

```bash
#!/bin/bash
# quick-diagnostic.sh
set -e

INSTANCE_IP="$1"
KEY_FILE="$2"

if [ -z "$INSTANCE_IP" ] || [ -z "$KEY_FILE" ]; then
    echo "Usage: $0 <instance-ip> <key-file>"
    exit 1
fi

SSH_CMD="ssh -i $KEY_FILE ubuntu@$INSTANCE_IP"

echo "=== GeuseMaker Diagnostics ==="
echo "Instance: $INSTANCE_IP"
echo "Time: $(date)"
echo

echo "=== System Status ==="
$SSH_CMD 'uptime && free -h && df -h'
echo

echo "=== Docker Status ==="
$SSH_CMD 'docker info && docker ps'
echo

echo "=== Service Health ==="
$SSH_CMD 'cd GeuseMaker && ./health-check.sh'
echo

echo "=== Recent Errors ==="
$SSH_CMD 'journalctl --since "10 minutes ago" --priority=err'
echo

echo "=== Resource Usage ==="
$SSH_CMD 'docker stats --no-stream'
echo

echo "Diagnostics complete."
```

### Log Aggregation
```bash
# Collect all logs for analysis
ssh -i key.pem ubuntu@ip << 'EOF'
cd /tmp
mkdir GeuseMaker-logs
cp /var/log/user-data.log GeuseMaker-logs/
journalctl --since "1 hour ago" > GeuseMaker-logs/system.log
docker logs n8n > GeuseMaker-logs/n8n.log 2>&1
docker logs ollama > GeuseMaker-logs/ollama.log 2>&1
docker logs qdrant > GeuseMaker-logs/qdrant.log 2>&1
tar czf GeuseMaker-logs.tar.gz GeuseMaker-logs/
EOF

# Download logs for analysis
scp -i key.pem ubuntu@ip:/tmp/GeuseMaker-logs.tar.gz .
```

## 📞 Getting Additional Help

### Before Contacting Support
1. ✅ Run quick diagnostics
2. ✅ Check recent logs
3. ✅ Verify configuration
4. ✅ Test basic connectivity
5. ✅ Document error messages

### Information to Provide
- Stack name and deployment type
- AWS region and instance type
- Error messages (exact text)
- Recent changes made
- Steps to reproduce the issue
- Diagnostic command outputs

### Self-Service Resources
1. Review [API Documentation](../api/)
2. Check [Architecture Documentation](../architecture/)
3. Search existing GitHub issues
4. Review CloudWatch metrics and logs

### Emergency Procedures
For critical production issues:
1. Enable debug logging
2. Take snapshots of critical data
3. Document current state
4. Implement immediate workarounds
5. Plan systematic resolution

Remember: Always test solutions in a development environment before applying to production systems.