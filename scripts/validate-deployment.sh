#!/bin/bash

# =============================================================================
# AI Starter Kit - Deployment Validation Script
# =============================================================================
# Comprehensive validation of deployed services with troubleshooting guidance
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-local}"
TIMEOUT_SECONDS=300
CHECK_INTERVAL=10

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

header() {
    echo -e "${PURPLE}$1${NC}"
}

# =============================================================================
# SERVICE VALIDATION FUNCTIONS
# =============================================================================

check_docker_services() {
    header "🐳 Checking Docker Services"
    echo "================================"
    
    # Check if docker compose is running
    if docker compose ps &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif docker-compose ps &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        error "No Docker Compose services found"
        return 1
    fi
    
    echo "Services Status:"
    $COMPOSE_CMD ps --format table
    echo ""
    
    # Check individual service health
    local services=("postgres" "n8n" "qdrant" "ollama" "crawl4ai")
    local healthy_count=0
    
    for service in "${services[@]}"; do
        if $COMPOSE_CMD ps "$service" | grep -q "Up"; then
            success "$service is running"
            ((healthy_count++))
        else
            error "$service is not running"
            info "Try: $COMPOSE_CMD logs $service"
        fi
    done
    
    if [[ $healthy_count -eq ${#services[@]} ]]; then
        success "All Docker services are running"
        return 0
    else
        warning "$healthy_count/${#services[@]} services are running"
        return 1
    fi
}

check_service_endpoints() {
    header "🔍 Checking Service Endpoints"
    echo "================================"
    
    # Determine host based on deployment type
    if [[ "$DEPLOYMENT_TYPE" == "cloud" ]]; then
        if [[ -n "${PUBLIC_IP:-}" ]]; then
            HOST="$PUBLIC_IP"
        else
            HOST="localhost"
            warning "PUBLIC_IP not set, using localhost"
        fi
    else
        HOST="localhost"
    fi
    
    # Define endpoints to check
    local endpoints=(
        "http://$HOST:5678/healthz:n8n:Workflow automation platform"
        "http://$HOST:11434/api/tags:Ollama:AI model server"
        "http://$HOST:6333/healthz:Qdrant:Vector database"
        "http://$HOST:11235/health:Crawl4AI:Web scraping service"
    )
    
    local healthy_endpoints=0
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r url service description <<< "$endpoint_info"
        
        log "Testing $service ($description)..."
        
        if curl -f -s --connect-timeout 10 "$url" > /dev/null 2>&1; then
            success "$service is healthy at $url"
            ((healthy_endpoints++))
        else
            error "$service is not responding at $url"
            info "Check service logs and ensure ports are accessible"
        fi
    done
    
    echo ""
    if [[ $healthy_endpoints -eq ${#endpoints[@]} ]]; then
        success "All service endpoints are healthy"
        return 0
    else
        warning "$healthy_endpoints/${#endpoints[@]} endpoints are healthy"
        return 1
    fi
}

check_ai_models() {
    header "🤖 Checking AI Models"
    echo "================================"
    
    local host="${PUBLIC_IP:-localhost}"
    local ollama_url="http://$host:11434"
    
    log "Checking Ollama model availability..."
    
    # Get list of available models
    if ! curl -f -s "$ollama_url/api/tags" > /tmp/ollama_models.json 2>/dev/null; then
        error "Cannot connect to Ollama service"
        return 1
    fi
    
    local model_count=$(jq '.models | length' /tmp/ollama_models.json 2>/dev/null || echo "0")
    
    if [[ "$model_count" -gt 0 ]]; then
        success "Found $model_count AI models"
        echo "Available models:"
        jq -r '.models[] | "  - \(.name) (\(.size/1000000000 | floor)GB)"' /tmp/ollama_models.json 2>/dev/null || echo "  (Error parsing model list)"
    else
        warning "No AI models found"
        info "Run 'make setup-models' to download AI models"
    fi
    
    # Test model inference
    log "Testing model inference..."
    
    local test_response=$(curl -s -X POST "$ollama_url/api/generate" \
        -H "Content-Type: application/json" \
        -d '{"model": "llama3.2:3b", "prompt": "Hello", "stream": false}' 2>/dev/null || echo "")
    
    if [[ -n "$test_response" ]] && echo "$test_response" | jq -e '.response' > /dev/null 2>&1; then
        success "AI model inference is working"
    else
        warning "AI model inference test failed or no compatible models available"
        info "Models may still be downloading. Check: curl $ollama_url/api/ps"
    fi
    
    rm -f /tmp/ollama_models.json
    echo ""
}

check_database_connectivity() {
    header "💾 Checking Database Connectivity"
    echo "================================"
    
    # Check PostgreSQL connectivity
    log "Testing PostgreSQL connection..."
    
    if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-n8n}" > /dev/null 2>&1; then
        success "PostgreSQL is accepting connections"
        
        # Check database existence
        if docker compose exec -T postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -c '\l' > /dev/null 2>&1; then
            success "n8n database is accessible"
        else
            warning "n8n database might not be properly initialized"
        fi
    else
        error "PostgreSQL is not accepting connections"
        info "Check PostgreSQL logs: docker compose logs postgres"
    fi
    
    # Check Qdrant
    log "Testing Qdrant vector database..."
    
    local host="${PUBLIC_IP:-localhost}"
    if curl -f -s "http://$host:6333/collections" > /dev/null 2>&1; then
        success "Qdrant vector database is accessible"
        
        # Get collection info
        local collections=$(curl -s "http://$host:6333/collections" | jq '.result.collections | length' 2>/dev/null || echo "0")
        info "Qdrant has $collections collections"
    else
        error "Qdrant vector database is not accessible"
        info "Check Qdrant logs: docker compose logs qdrant"
    fi
    
    echo ""
}

check_gpu_utilization() {
    if [[ "$DEPLOYMENT_TYPE" != "cloud" ]]; then
        return 0
    fi
    
    header "🎮 Checking GPU Utilization"
    echo "================================"
    
    # Check if nvidia-smi is available
    if command -v nvidia-smi &> /dev/null; then
        log "GPU Information:"
        nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu,temperature.gpu \
            --format=csv,noheader,nounits | while IFS=, read name memory_total memory_used gpu_util temp; do
            echo "  GPU: $name"
            echo "  Memory: ${memory_used}MB / ${memory_total}MB"
            echo "  Utilization: ${gpu_util}%"
            echo "  Temperature: ${temp}°C"
        done
        
        success "GPU monitoring is available"
    else
        warning "nvidia-smi not available - GPU monitoring disabled"
        info "This is normal for local development without GPU"
    fi
    
    echo ""
}

check_storage_mounts() {
    if [[ "$DEPLOYMENT_TYPE" != "cloud" ]]; then
        return 0
    fi
    
    header "💿 Checking Storage Mounts"
    echo "================================"
    
    # Check EFS mount (cloud deployment)
    if [[ -n "${EFS_DNS:-}" ]]; then
        log "Checking EFS mount..."
        
        if mount | grep -q "/mnt/efs"; then
            success "EFS is mounted"
            
            # Check EFS accessibility
            if timeout 10 ls /mnt/efs > /dev/null 2>&1; then
                success "EFS is accessible"
            else
                error "EFS mount is not accessible"
                info "Check EFS security groups and network connectivity"
            fi
        else
            error "EFS is not mounted"
            info "Mount EFS with: sudo mount -t nfs4 $EFS_DNS:/ /mnt/efs"
        fi
    fi
    
    # Check Docker volumes
    log "Checking Docker volumes..."
    
    local volumes=$(docker volume ls --format table | grep -c ai || echo "0")
    info "Found $volumes AI-related Docker volumes"
    
    echo ""
}

check_performance_metrics() {
    header "📊 Performance Metrics"
    echo "================================"
    
    # System resources
    log "System Resource Usage:"
    
    # Memory usage
    if command -v free &> /dev/null; then
        local memory_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2 " (" int($3/$2*100) "%)"}')
        echo "  Memory: $memory_info"
    fi
    
    # Disk usage
    local disk_info=$(df -h . | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    echo "  Disk: $disk_info"
    
    # CPU load
    if command -v uptime &> /dev/null; then
        local load_avg=$(uptime | awk -F'load average:' '{print $2}')
        echo "  Load Average:$load_avg"
    fi
    
    # Docker stats
    log "Docker Container Resource Usage:"
    timeout 5 docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || \
        warning "Could not get Docker stats"
    
    echo ""
}

check_networking() {
    header "🌐 Network Connectivity"
    echo "================================"
    
    local host="${PUBLIC_IP:-localhost}"
    
    # Check internal Docker networking
    log "Testing internal Docker networking..."
    
    # Test n8n to postgres connection
    if docker compose exec -T n8n nc -z postgres 5432 2>/dev/null; then
        success "n8n can connect to PostgreSQL"
    else
        error "n8n cannot connect to PostgreSQL"
    fi
    
    # Test n8n to ollama connection
    if docker compose exec -T n8n nc -z ollama 11434 2>/dev/null; then
        success "n8n can connect to Ollama"
    else
        error "n8n cannot connect to Ollama"
    fi
    
    # Test external connectivity (cloud deployment)
    if [[ "$DEPLOYMENT_TYPE" == "cloud" ]]; then
        log "Testing external connectivity..."
        
        local external_ports=("5678" "11434" "6333" "11235")
        for port in "${external_ports[@]}"; do
            if nc -z "$host" "$port" 2>/dev/null; then
                success "Port $port is accessible externally"
            else
                warning "Port $port is not accessible externally"
                info "Check security group rules for port $port"
            fi
        done
    fi
    
    echo ""
}

generate_troubleshooting_guide() {
    header "🔧 Troubleshooting Guide"
    echo "================================"
    
    echo "Common issues and solutions:"
    echo ""
    
    echo "1. Services not starting:"
    echo "   - Check logs: docker compose logs [service]"
    echo "   - Restart services: docker compose restart"
    echo "   - Check resources: docker system df"
    echo ""
    
    echo "2. Port conflicts:"
    echo "   - Check if ports are in use: netstat -tulpn | grep [port]"
    echo "   - Stop conflicting services or change ports in .env"
    echo ""
    
    echo "3. GPU not detected (cloud deployment):"
    echo "   - Check NVIDIA drivers: nvidia-smi"
    echo "   - Restart Docker: sudo systemctl restart docker"
    echo "   - Check Docker GPU support: docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi"
    echo ""
    
    echo "4. Models not downloading:"
    echo "   - Check internet connectivity from container"
    echo "   - Check disk space: df -h"
    echo "   - Manual download: docker compose exec ollama ollama pull llama3.2:3b"
    echo ""
    
    echo "5. High memory usage:"
    echo "   - Reduce concurrent models: set OLLAMA_MAX_LOADED_MODELS=1"
    echo "   - Reduce browser pool: set CRAWL4AI_BROWSER_POOL_SIZE=1"
    echo "   - Check for memory leaks: docker stats"
    echo ""
    
    echo "6. Network connectivity issues:"
    echo "   - Check security groups (cloud deployment)"
    echo "   - Verify firewall rules"
    echo "   - Test internal networking: docker compose exec service ping other-service"
    echo ""
}

# =============================================================================
# MAIN VALIDATION FLOW
# =============================================================================

run_comprehensive_validation() {
    local overall_health=0
    
    echo -e "${CYAN}"
    cat << 'EOF'
 _____ _____   _             _   _     _       _   _           
|  _  |     | |   _ ___ _   |_| _| |___| |_ _  |_| |_ ___ ___   
|     |-   -| |  | | .'|  | | | . | .'|  _|_||_| | | | .'|   |  
|__|__|_____| |_____|__,|_| |_|___|___|_| |_||_|_|___|__,|_|_|
                                                             
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Deployment Validation Report${NC}"
    echo -e "${BLUE}Generated: $(date)${NC}"
    echo ""
    
    # Run all validation checks
    log "Starting comprehensive validation..."
    echo ""
    
    check_docker_services || ((overall_health++))
    check_service_endpoints || ((overall_health++))
    check_ai_models || ((overall_health++))
    check_database_connectivity || ((overall_health++))
    check_gpu_utilization || ((overall_health++))
    check_storage_mounts || ((overall_health++))
    check_performance_metrics
    check_networking || ((overall_health++))
    
    # Generate summary
    header "📋 Validation Summary"
    echo "================================"
    
    if [[ $overall_health -eq 0 ]]; then
        success "🎉 All systems are operational!"
        echo ""
        echo "Your AI Starter Kit deployment is ready to use:"
        
        local host="${PUBLIC_IP:-localhost}"
        echo ""
        echo "🔗 Service URLs:"
        echo "   n8n Workflow Editor:    http://$host:5678"
        echo "   Crawl4AI Web Scraper:   http://$host:11235"
        echo "   Qdrant Vector Database: http://$host:6333"
        echo "   Ollama AI Models:       http://$host:11434"
        
    elif [[ $overall_health -le 2 ]]; then
        warning "⚠️  Minor issues detected, but system is mostly functional"
        echo ""
        echo "Consider addressing the warnings above for optimal performance."
        
    else
        error "❌ Multiple issues detected that may affect functionality"
        echo ""
        echo "Please address the errors above before using the system."
        generate_troubleshooting_guide
    fi
    
    echo ""
    echo "💡 Additional resources:"
    echo "   - Check logs: docker compose logs -f"
    echo "   - Service health: make health"
    echo "   - Performance: make resources"
    echo "   - Documentation: open README.md"
    echo ""
}

wait_for_services() {
    local timeout="$1"
    local start_time=$(date +%s)
    
    log "Waiting for services to be ready (timeout: ${timeout}s)..."
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            warning "Timeout reached after ${timeout}s"
            break
        fi
        
        # Quick health check
        local healthy=0
        local total=4
        
        local host="${PUBLIC_IP:-localhost}"
        curl -f -s "http://$host:5678/healthz" > /dev/null 2>&1 && ((healthy++))
        curl -f -s "http://$host:11434/api/tags" > /dev/null 2>&1 && ((healthy++))
        curl -f -s "http://$host:6333/healthz" > /dev/null 2>&1 && ((healthy++))
        curl -f -s "http://$host:11235/health" > /dev/null 2>&1 && ((healthy++))
        
        if [[ $healthy -eq $total ]]; then
            success "All services are ready! (${elapsed}s elapsed)"
            return 0
        fi
        
        info "Services ready: $healthy/$total (${elapsed}s elapsed)"
        sleep $CHECK_INTERVAL
    done
    
    warning "Not all services became ready within timeout"
    return 1
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_usage() {
    echo "AI Starter Kit Deployment Validation"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --deployment-type TYPE  Deployment type: local|cloud (default: local)"
    echo "  --public-ip IP          Public IP for cloud deployment"
    echo "  --timeout SECONDS       Timeout for service readiness (default: 300)"
    echo "  --wait                  Wait for services to be ready before validation"
    echo "  --quick                 Run quick validation (essential checks only)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Validate local deployment"
    echo "  $0 --deployment-type cloud \\        # Validate cloud deployment"
    echo "     --public-ip 1.2.3.4"
    echo "  $0 --wait --timeout 600              # Wait up to 10 minutes for services"
    echo "  $0 --quick                           # Quick validation"
}

# Parse command line arguments
WAIT_FOR_SERVICES=false
QUICK_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment-type)
            DEPLOYMENT_TYPE="$2"
            shift 2
            ;;
        --public-ip)
            PUBLIC_IP="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --wait)
            WAIT_FOR_SERVICES=true
            shift
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    # Wait for services if requested
    if [[ "$WAIT_FOR_SERVICES" == true ]]; then
        wait_for_services "$TIMEOUT_SECONDS"
    fi
    
    # Run validation
    if [[ "$QUICK_MODE" == true ]]; then
        check_docker_services
        check_service_endpoints
        success "Quick validation completed"
    else
        run_comprehensive_validation
    fi
}

main "$@" 