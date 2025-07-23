# Docker Image Version Management

This document explains how to manage Docker image versions in the AI Starter Kit deployment system.

## Overview

The deployment system now supports flexible Docker image version management with these key features:

- **Latest by Default**: All services use `latest` tags by default for automatic updates
- **Configurable Overrides**: Specify custom versions in configuration files
- **Deployment Options**: Control image versions through command-line flags
- **Environment Support**: Different configurations for dev/staging/production

## Quick Start

### Use Latest Images (Default)
```bash
# All these commands use latest images by default
./scripts/aws-deployment.sh
./scripts/aws-deployment-simple.sh
./scripts/simple-update-images.sh update
```

### Use Pinned/Stable Images
```bash
# For production deployments with stable versions
./scripts/aws-deployment.sh --use-pinned-images
./scripts/aws-deployment-simple.sh  # Set USE_LATEST_IMAGES=false in env
```

### Update Local Docker Compose File
```bash
# Update to latest versions
./scripts/simple-update-images.sh update

# Show current versions
./scripts/simple-update-images.sh show

# Validate configuration
./scripts/simple-update-images.sh validate
```

## Configuration System

### Image Version Configuration File

Located at `config/image-versions.yml`, this file defines:

```yaml
services:
  postgres:
    image: "postgres"
    default: "latest"
    fallback: "16.1-alpine3.19"
    description: "PostgreSQL database server"

  n8n:
    image: "n8nio/n8n"
    default: "latest"
    fallback: "1.19.4"
    description: "n8n workflow automation platform"

  # ... other services
```

### Environment-Specific Overrides

```yaml
environments:
  production:
    # Pin specific versions in production
    postgres:
      image: "postgres:16.1-alpine3.19"
    n8n:
      image: "n8nio/n8n:1.19.4"
    
  development:
    # Use latest in development
    use_latest_by_default: true
```

## Command Line Options

### AWS Deployment Scripts

```bash
# Use latest images (default)
./scripts/aws-deployment.sh

# Use pinned/stable versions
./scripts/aws-deployment.sh --use-pinned-images

# Cross-region deployment with pinned images
./scripts/aws-deployment.sh --cross-region --use-pinned-images
```

### Environment Variables

```bash
# Control image versions via environment
export USE_LATEST_IMAGES=false
./scripts/aws-deployment.sh

# Or inline
USE_LATEST_IMAGES=true ./scripts/aws-deployment.sh
```

## Image Update Script

The `scripts/simple-update-images.sh` script provides several operations:

### Update Images
```bash
# Update all images to latest
./scripts/simple-update-images.sh update

# Update with specific environment
./scripts/simple-update-images.sh update production false
```

### Show Current Versions
```bash
./scripts/simple-update-images.sh show
```

Output:
```
Current image versions:
  Line 103: postgres:latest
  Line 184: n8nio/n8n:latest
  Line 266: qdrant/qdrant:latest
  ...
```

### Validate Configuration
```bash
./scripts/simple-update-images.sh validate
```

## Current Image Versions

After running the update script, these services use latest tags by default:

| Service | Image | Default Tag | Pinned Fallback |
|---------|-------|-------------|----------------|
| PostgreSQL | `postgres` | `latest` | `16.1-alpine3.19` |
| n8n | `n8nio/n8n` | `latest` | `1.19.4` |
| Qdrant | `qdrant/qdrant` | `latest` | `v1.7.3` |
| Ollama | `ollama/ollama` | `latest` | `0.1.17` |
| Crawl4AI | `unclecode/crawl4ai` | `latest` | `0.7.0-r1` |
| Curl | `curlimages/curl` | `latest` | `8.5.0` |
| CUDA | `nvidia/cuda` | `12.4.1-devel-ubuntu22.04` | (pinned) |

> **Note**: CUDA is kept pinned to a specific version for GPU compatibility.

## Backup and Recovery

### Automatic Backups
Every time you update images, the system creates automatic backups:
```
docker-compose.gpu-optimized.yml.backup-20250123-143022
```

### Manual Restore
```bash
# Restore from most recent backup
cp docker-compose.gpu-optimized.yml.backup-* docker-compose.gpu-optimized.yml

# Or use a specific backup
cp docker-compose.gpu-optimized.yml.backup-20250123-143022 docker-compose.gpu-optimized.yml
```

## Testing

Run the test suite to verify the configuration system:

```bash
./test-image-config.sh
```

This validates:
- Script availability and permissions
- Docker Compose configuration validity
- Current image versions
- Backup functionality
- Environment variable integration

## Best Practices

### Development
- ✅ Use latest images for newest features
- ✅ Update regularly with `./scripts/simple-update-images.sh update`
- ✅ Test deployments frequently

### Staging
- ✅ Use latest images for testing
- ✅ Pin versions after successful testing
- ✅ Document known-good version combinations

### Production
- ✅ Use pinned versions: `--use-pinned-images`
- ✅ Test version updates in staging first
- ✅ Maintain fallback configurations
- ✅ Keep backup of working configurations

### Security
- ✅ Monitor for security updates in base images
- ✅ Use specific tags for critical services
- ✅ Regularly update pinned versions after testing
- ✅ Subscribe to security advisories for base images

## Troubleshooting

### Image Pull Failures
```bash
# Test image availability
docker pull postgres:latest
docker pull n8nio/n8n:latest

# Check Docker Hub status
curl -s https://status.docker.com/
```

### Configuration Issues
```bash
# Validate Docker Compose syntax
./scripts/simple-update-images.sh validate

# Show current configuration
./scripts/simple-update-images.sh show
```

### Rollback to Previous Versions
```bash
# List available backups
ls -la docker-compose.gpu-optimized.yml.backup-*

# Restore from backup
cp docker-compose.gpu-optimized.yml.backup-20250123-143022 docker-compose.gpu-optimized.yml
```

### Environment Variable Issues
```bash
# Check current environment
env | grep USE_LATEST_IMAGES

# Debug deployment script
bash -x ./scripts/aws-deployment.sh --use-pinned-images
```

## Migration Guide

### From Fixed Versions to Latest
If you're upgrading from a previous version with fixed image tags:

1. **Backup current configuration**:
   ```bash
   cp docker-compose.gpu-optimized.yml docker-compose.gpu-optimized.yml.manual-backup
   ```

2. **Update to latest**:
   ```bash
   ./scripts/simple-update-images.sh update
   ```

3. **Test locally** (if possible):
   ```bash
   docker-compose -f docker-compose.gpu-optimized.yml config
   ```

4. **Deploy gradually**:
   ```bash
   # Test in development first
   ./scripts/aws-deployment.sh
   
   # Then use pinned versions in production
   ./scripts/aws-deployment.sh --use-pinned-images
   ```

### Custom Image Versions
To use completely custom versions, edit `config/image-versions.yml`:

```yaml
services:
  postgres:
    image: "postgres:15.3-alpine"  # Custom version
    default: "15.3-alpine"
    fallback: "16.1-alpine3.19"
```

Then update:
```bash
./scripts/simple-update-images.sh update production false
```