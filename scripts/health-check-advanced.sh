#!/bin/bash
# =============================================================================
# Advanced Health Check Script for GeuseMaker
# Performs comprehensive application-level health checks
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
LOG_FILE="/var/log/GeuseMaker-health.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
OVERALL_HEALTH=true
HEALTH_REPORT=""

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Health check result formatter
check_result() {
    local service="$1"
    local status="$2"
    local details="$3"
    
    if [ "$status" = "healthy" ]; then
        log "${GREEN}✅ $service: HEALTHY${NC} - $details"
        HEALTH_REPORT+="✅ $service: HEALTHY - $details\n"
    else
        log "${RED}❌ $service: UNHEALTHY${NC} - $details"
        HEALTH_REPORT+="❌ $service: UNHEALTHY - $details\n"
        OVERALL_HEALTH=false
    fi
}

# =============================================================================
# SERVICE HEALTH CHECKS
# =============================================================================

log "\n[$TIMESTAMP] Starting comprehensive health check..."

# PostgreSQL Database Check
check_postgres() {
    local service="PostgreSQL Database"
    
    if docker exec postgres pg_isready -U n8n >/dev/null 2>&1; then
        # Advanced check: Can we actually query?
        if docker exec postgres psql -U n8n -d n8n -c "SELECT 1" >/dev/null 2>&1; then
            # Check connection count
            local connections=$(docker exec postgres psql -U n8n -d n8n -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'" 2>/dev/null | tr -d ' ')
            check_result "$service" "healthy" "Active connections: $connections"
        else
            check_result "$service" "unhealthy" "Database is up but queries failing"
        fi
    else
        check_result "$service" "unhealthy" "Database is not responding"
    fi
}

# n8n Workflow Engine Check
check_n8n() {
    local service="n8n Workflow Engine"
    
    if curl -sf http://localhost:5678/healthz >/dev/null 2>&1; then
        # Check if we can access the API
        if curl -sf http://localhost:5678/api/v1/info >/dev/null 2>&1; then
            # Get workflow count if possible
            local workflow_count=$(curl -s http://localhost:5678/api/v1/workflows 2>/dev/null | jq '.data | length' 2>/dev/null || echo "unknown")
            check_result "$service" "healthy" "API responsive, Workflows: $workflow_count"
        else
            check_result "$service" "healthy" "Basic health OK, API not accessible (auth required)"
        fi
    else
        check_result "$service" "unhealthy" "Service not responding on port 5678"
    fi
}

# Ollama LLM Service Check
check_ollama() {
    local service="Ollama LLM Service"
    
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        # Check loaded models
        local models=$(curl -s http://localhost:11434/api/tags 2>/dev/null | jq -r '.models[].name' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        if [ -n "$models" ]; then
            check_result "$service" "healthy" "Models loaded: $models"
        else
            check_result "$service" "healthy" "Service running, no models loaded yet"
        fi
        
        # Check GPU availability
        if docker exec ollama nvidia-smi >/dev/null 2>&1; then
            local gpu_memory=$(docker exec ollama nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | head -1)
            HEALTH_REPORT+="  └─ GPU Status: $gpu_memory MB used\n"
        fi
    else
        check_result "$service" "unhealthy" "Service not responding on port 11434"
    fi
}

# Qdrant Vector Database Check
check_qdrant() {
    local service="Qdrant Vector Database"
    
    if curl -sf http://localhost:6333/readyz >/dev/null 2>&1; then
        # Check collections
        local collections=$(curl -s http://localhost:6333/collections 2>/dev/null | jq -r '.result.collections[].name' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        if [ -n "$collections" ]; then
            check_result "$service" "healthy" "Collections: $collections"
        else
            check_result "$service" "healthy" "Service running, no collections created yet"
        fi
    else
        check_result "$service" "unhealthy" "Service not responding on port 6333"
    fi
}

# Crawl4AI Service Check
check_crawl4ai() {
    local service="Crawl4AI Service"
    
    if curl -sf http://localhost:11235/health >/dev/null 2>&1; then
        # Check if the service is ready
        local status=$(curl -s http://localhost:11235/health 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")
        if [ "$status" = "healthy" ] || [ "$status" = "ok" ]; then
            check_result "$service" "healthy" "API responsive and ready"
        else
            check_result "$service" "healthy" "Service running, status: $status"
        fi
    else
        check_result "$service" "unhealthy" "Service not responding on port 11235"
    fi
}

# GPU Monitor Check
check_gpu_monitor() {
    local service="GPU Monitor"
    
    if docker ps --format "{{.Names}}" | grep -q "gpu-monitor"; then
        if docker exec gpu-monitor nvidia-smi >/dev/null 2>&1; then
            check_result "$service" "healthy" "Monitoring GPU metrics"
        else
            check_result "$service" "unhealthy" "Container running but GPU access failed"
        fi
    else
        check_result "$service" "unhealthy" "Container not running"
    fi
}

# =============================================================================
# SYSTEM RESOURCE CHECKS
# =============================================================================

check_system_resources() {
    log "\n${YELLOW}System Resource Status:${NC}"
    
    # CPU Usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    log "  CPU Usage: ${cpu_usage}%"
    
    # Memory Usage
    local mem_info=$(free -m | awk 'NR==2{printf "%.1f", $3*100/$2}')
    log "  Memory Usage: ${mem_info}%"
    
    # Disk Usage
    local disk_usage=$(df -h / | awk 'NR==2{print $5}')
    log "  Disk Usage: ${disk_usage}"
    
    # Docker Status
    local container_count=$(docker ps -q | wc -l)
    local image_count=$(docker images -q | wc -l)
    log "  Docker: ${container_count} containers running, ${image_count} images"
}

# =============================================================================
# NETWORK CONNECTIVITY CHECKS
# =============================================================================

check_network() {
    log "\n${YELLOW}Network Connectivity:${NC}"
    
    # Check internal connectivity between services
    if docker exec n8n ping -c 1 postgres >/dev/null 2>&1; then
        log "  ✅ Internal network: Connected"
    else
        log "  ❌ Internal network: Connection issues"
        OVERALL_HEALTH=false
    fi
    
    # Check external connectivity
    if curl -sf https://www.google.com >/dev/null 2>&1; then
        log "  ✅ External network: Connected"
    else
        log "  ❌ External network: No internet connection"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Run all health checks
check_postgres
check_n8n
check_ollama
check_qdrant
check_crawl4ai
check_gpu_monitor
check_system_resources
check_network

# =============================================================================
# SUMMARY REPORT
# =============================================================================

log "\n${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
log "${YELLOW}Health Check Summary:${NC}"
log "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

if [ "$OVERALL_HEALTH" = true ]; then
    log "${GREEN}🎉 All services are healthy!${NC}"
    
    # Send success metric to CloudWatch (if configured)
    if command -v aws >/dev/null 2>&1; then
        aws cloudwatch put-metric-data \
            --namespace "GeuseMaker" \
            --metric-name "HealthCheckStatus" \
            --value 1 \
            --dimensions Service=Overall \
            2>/dev/null || true
    fi
    
    exit 0
else
    log "${RED}⚠️  Some services are unhealthy!${NC}"
    log "\nDetailed Report:"
    echo -e "$HEALTH_REPORT"
    
    # Send failure metric to CloudWatch (if configured)
    if command -v aws >/dev/null 2>&1; then
        aws cloudwatch put-metric-data \
            --namespace "GeuseMaker" \
            --metric-name "HealthCheckStatus" \
            --value 0 \
            --dimensions Service=Overall \
            2>/dev/null || true
    fi
    
    exit 1
fi 