# 🔍 Docker Compose v2.38.2 Validation Guide

[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2.38.2-blue.svg)](https://docs.docker.com/compose/)
[![Validation](https://img.shields.io/badge/Status-Ready%20for%20Testing-yellow.svg)]()

A comprehensive validation guide to test the Docker Compose v2.38.2 optimizations and ensure your Enhanced AI Starter Kit deployment is working correctly.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Validation](#quick-validation)
- [Comprehensive Testing](#comprehensive-testing)
- [Performance Validation](#performance-validation)
- [Troubleshooting](#troubleshooting)
- [Success Criteria](#success-criteria)

## 🔧 Prerequisites

Before running validation tests, ensure you have:

### Required Software

| Component | Minimum Version | Recommended Version | Check Command |
|-----------|----------------|-------------------|---------------|
| Docker Engine | 24.0.0 | 25.0.0+ | `docker --version` |
| Docker Compose | 2.38.2 | 2.38.2+ | `docker compose version` |
| curl | Any | Latest | `curl --version` |
| jq | 1.6+ | Latest | `jq --version` |

### Environment Setup

```bash
# 1. Verify Docker installation
docker --version
docker compose version

# 2. Check Docker daemon is running
docker ps

# 3. Verify you're in the project directory
ls -la | grep docker-compose.yml
```

## ⚡ Quick Validation

Run these commands to quickly validate your setup:

### 1. Configuration Validation

```bash
# Validate main configuration
echo "🔍 Validating main Docker Compose configuration..."
docker compose config --quiet && echo "✅ Main config valid" || echo "❌ Main config has errors"

# Validate GPU configuration
echo "🔍 Validating GPU-optimized configuration..."
docker compose -f docker-compose.gpu-optimized.yml config --quiet && echo "✅ GPU config valid" || echo "❌ GPU config has errors"

# Validate production configuration
echo "🔍 Validating production configuration..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml config --quiet && echo "✅ Production config valid" || echo "❌ Production config has errors"
```

### 2. Environment Check

```bash
# Check environment file
echo "🔍 Checking environment configuration..."
if [ -f .env ]; then
    echo "✅ .env file exists"
    echo "📋 Environment variables:"
    grep -E "^[A-Z_]+" .env | head -5
else
    echo "❌ .env file missing - run 'make init' first"
fi
```

### 3. Docker Compose Features Test

```bash
# Test modern Compose Specification features
echo "🔍 Testing Docker Compose v2.38.2 features..."

# Check for version field (should not exist)
if grep -q "^version:" docker-compose.yml; then
    echo "❌ Legacy version field found - should be removed"
else
    echo "✅ Modern Compose Specification (no version field)"
fi

# Check for modern syntax
if grep -q "pull_policy:" docker-compose.yml; then
    echo "✅ Modern pull_policy syntax found"
fi

if grep -q "start_period:" docker-compose.yml; then
    echo "✅ Enhanced health check syntax found"
fi
```

## 🧪 Comprehensive Testing

### Step 1: Makefile Commands Validation

```bash
echo "🔍 Testing Makefile commands..."

# Test help command
make help

# Test configuration validation
make validate

# Test configuration display
make config | head -20
```

### Step 2: Service Deployment Test

```bash
echo "🚀 Testing service deployment..."

# Initialize environment
make init

# Start services (choose one based on your environment)

# Option A: Local development
make dev

# Option B: Production environment
# make prod

# Option C: GPU-optimized (if you have GPU)
# make gpu-up
```

### Step 3: Service Health Validation

```bash
echo "🔍 Testing service health..."

# Wait for services to start
sleep 30

# Run comprehensive health checks
make test

# Check individual services
echo "Testing individual service endpoints..."

# n8n
curl -f https://n8n.geuse.io/healthz && echo "✅ n8n healthy" || echo "❌ n8n unhealthy"

# Ollama
curl -f http://localhost:11434/api/tags && echo "✅ Ollama healthy" || echo "❌ Ollama unhealthy"

# Qdrant
curl -f http://localhost:6333/healthz && echo "✅ Qdrant healthy" || echo "❌ Qdrant unhealthy"

# Crawl4AI
curl -f http://localhost:11235/health && echo "✅ Crawl4AI healthy" || echo "❌ Crawl4AI unhealthy"

# PostgreSQL
docker compose exec -T postgres pg_isready -U ${POSTGRES_USER:-n8n} && echo "✅ PostgreSQL healthy" || echo "❌ PostgreSQL unhealthy"
```

### Step 4: AI Models Validation

```bash
echo "🤖 Testing AI models setup..."

# Setup models
make setup-models

# Test model availability
echo "Checking available models..."
curl -s http://localhost:11434/api/tags | jq -r '.models[].name' || echo "Models list unavailable"

# Test basic inference
echo "Testing basic inference..."
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-r1:8b","prompt":"Hello","stream":false}' | \
  jq -r '.response' || echo "Inference test failed"
```

### Step 5: Crawl4AI Integration Test

```bash
echo "🕷️ Testing Crawl4AI integration..."

# Test basic crawling
curl -X POST http://localhost:11235/crawl \
  -H "Content-Type: application/json" \
  -d '{"urls": ["https://httpbin.org/json"]}' | \
  jq -r '.results[0].extracted_content' || echo "Crawl4AI test failed"

# Test LLM extraction (if Ollama is running)
curl -X POST http://localhost:11235/crawl \
  -H "Content-Type: application/json" \
  -d '{
    "urls": ["https://httpbin.org/json"],
    "crawler_config": {
      "extraction_strategy": {
        "type": "LLMExtractionStrategy",
        "llm_config": {
          "provider": "ollama/deepseek-r1:8b",
          "base_url": "http://ollama:11434"
        },
        "instruction": "Extract any JSON data"
      }
    }
  }' | jq -r '.results[0].extracted_content' || echo "LLM extraction test failed"
```

## 📊 Performance Validation

### Resource Usage Test

```bash
echo "📊 Testing resource usage..."

# Check resource allocation
make resources

# Test resource limits
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Check if services respect resource limits
echo "Checking resource limit compliance..."
docker compose exec ollama cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "Memory limits not visible (normal in some environments)"
```

### Network Performance Test

```bash
echo "🌐 Testing network performance..."

# Test inter-service communication
docker compose exec n8n ping -c 3 ollama
docker compose exec n8n ping -c 3 postgres
docker compose exec crawl4ai ping -c 3 ollama

# Test external connectivity
docker compose exec ollama ping -c 3 google.com
```

### Startup Performance Test

```bash
echo "⚡ Testing startup performance..."

# Measure startup time
echo "Restarting services to measure startup time..."
START_TIME=$(date +%s)

make down
make up

# Wait for all services to be healthy
timeout=300  # 5 minutes
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if make test >/dev/null 2>&1; then
        END_TIME=$(date +%s)
        STARTUP_TIME=$((END_TIME - START_TIME))
        echo "✅ All services healthy after ${STARTUP_TIME} seconds"
        break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
done

if [ $elapsed -ge $timeout ]; then
    echo "❌ Services did not become healthy within ${timeout} seconds"
fi
```

## 🛠️ Troubleshooting

### Common Issues and Solutions

#### Issue 1: Configuration Validation Errors

```bash
# Problem: docker compose config shows errors
# Solution: Check for syntax issues

# Debug configuration
docker compose config 2>&1 | head -20

# Check for common issues
echo "Checking for common configuration issues..."
grep -n "version:" docker-compose.yml && echo "⚠️  Remove version field"
grep -n "mem_limit:" docker-compose.yml && echo "⚠️  Use deploy.resources.limits.memory instead"
```

#### Issue 2: Service Health Check Failures

```bash
# Problem: Services showing as unhealthy
# Solution: Check service logs

# Check service status
docker compose ps

# Check logs for specific service
docker compose logs ollama | tail -20
docker compose logs n8n | tail -20

# Check if ports are accessible
netstat -tuln | grep -E ":(5678|11434|6333|11235|5432)"
```

#### Issue 3: GPU Support Issues

```bash
# Problem: GPU not accessible in containers
# Solution: Verify GPU setup

# Check NVIDIA drivers
nvidia-smi || echo "NVIDIA drivers not available"

# Check Docker GPU support
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi || echo "Docker GPU support not available"

# Verify GPU configuration in compose
docker compose -f docker-compose.gpu-optimized.yml config | grep -A 10 "nvidia"
```

#### Issue 4: Performance Issues

```bash
# Problem: High resource usage or slow performance
# Solution: Check resource allocation

# Monitor resource usage
docker stats --no-stream

# Check for resource constraints
docker compose logs | grep -i "memory\|cpu\|resource"

# Verify resource limits
docker compose config | grep -A 5 "resources:"
```

### Debug Commands

```bash
# Comprehensive debug information
echo "🐛 Collecting debug information..."

echo "=== Docker Version ==="
docker --version
docker compose version

echo "=== System Resources ==="
free -h
df -h

echo "=== Service Status ==="
docker compose ps

echo "=== Service Logs (Last 10 lines) ==="
for service in postgres n8n ollama qdrant crawl4ai; do
    echo "--- $service ---"
    docker compose logs --tail 10 $service 2>/dev/null || echo "Service $service not running"
done

echo "=== Network Information ==="
docker network ls
docker compose config | grep -A 10 "networks:"

echo "=== Volume Information ==="
docker volume ls
docker compose config | grep -A 10 "volumes:"
```

## ✅ Success Criteria

Your deployment is considered successful when all these criteria are met:

### ✅ Configuration Validation

- [ ] Main `docker-compose.yml` validates without errors
- [ ] GPU configuration validates without errors
- [ ] Production configuration validates without errors
- [ ] No legacy `version` field in compose files
- [ ] Modern Compose Specification syntax used

### ✅ Service Health

- [ ] All 5 core services start successfully
- [ ] All health checks pass
- [ ] Services restart automatically on failure
- [ ] Inter-service communication works
- [ ] External connectivity available

### ✅ Feature Validation

- [ ] AI models download and load successfully
- [ ] Crawl4AI can perform basic web scraping
- [ ] LLM extraction works with local Ollama
- [ ] n8n workflow editor accessible
- [ ] Qdrant vector database functional

### ✅ Performance

- [ ] Services start within 5 minutes
- [ ] Resource usage within expected limits
- [ ] No memory or CPU exhaustion
- [ ] Network latency acceptable (<100ms inter-service)

### ✅ Docker Compose v2.38.2 Features

- [ ] Enhanced health checks working
- [ ] Resource reservations effective
- [ ] Dependency conditions respected
- [ ] Restart policies functioning
- [ ] Logging configuration active

## 🎯 Validation Report Template

Use this template to document your validation results:

```markdown
# Validation Report - Enhanced AI Starter Kit

**Date**: [DATE]
**Environment**: [Local/Cloud/GPU]
**Docker Version**: [VERSION]
**Docker Compose Version**: [VERSION]

## Configuration Validation
- [ ] Main configuration: ✅/❌
- [ ] GPU configuration: ✅/❌
- [ ] Production configuration: ✅/❌

## Service Health
- [ ] PostgreSQL: ✅/❌
- [ ] n8n: ✅/❌
- [ ] Ollama: ✅/❌
- [ ] Qdrant: ✅/❌
- [ ] Crawl4AI: ✅/❌

## Performance Metrics
- Startup time: [X] seconds
- Memory usage: [X]% of limits
- CPU usage: [X]% of limits
- Network latency: [X]ms

## Issues Found
[List any issues and resolutions]

## Overall Status
- [ ] ✅ Deployment successful
- [ ] ⚠️ Deployment successful with minor issues
- [ ] ❌ Deployment failed

## Notes
[Additional observations or recommendations]
```

---

🎉 **Congratulations!** If all validation criteria are met, your Enhanced AI Starter Kit is successfully optimized for Docker Compose v2.38.2 and ready for production use.

For ongoing monitoring and maintenance, see the comprehensive guides:
- [README.md](README.md) - Complete overview
- [DEPLOYMENT_STRATEGY.md](DEPLOYMENT_STRATEGY.md) - Deployment options  
- [DOCKER_OPTIMIZATION.md](DOCKER_OPTIMIZATION.md) - Advanced optimizations 