#!/bin/bash

# =============================================================================
# Deployment Validation Script
# =============================================================================
# Validates successful deployment of the AI starter kit
# Performs comprehensive health checks and functional tests
# =============================================================================

set -euo pipefail

# Load security validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/security-validation.sh" ]]; then
    source "$SCRIPT_DIR/security-validation.sh"
else
    echo "Warning: Security validation library not found"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TIMEOUT=${TIMEOUT:-60}
RETRY_INTERVAL=${RETRY_INTERVAL:-5}
VERBOSE=${VERBOSE:-false}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}" >&2
}

error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

# Wait for service to be available
wait_for_service() {
    local service_name="$1"
    local url="$2"
    local max_attempts=$((TIMEOUT / RETRY_INTERVAL))
    local attempt=0
    
    log "Waiting for $service_name to be available at $url"
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f -s "$url" >/dev/null 2>&1; then
            success "$service_name is available"
            return 0
        fi
        
        ((attempt++))
        if [[ $VERBOSE == "true" ]]; then
            log "Attempt $attempt/$max_attempts failed, retrying in ${RETRY_INTERVAL}s..."
        fi
        sleep $RETRY_INTERVAL
    done
    
    error "$service_name failed to become available within ${TIMEOUT}s"
    return 1
}

# Validate PostgreSQL service
validate_postgres() {
    log "Validating PostgreSQL service..."
    
    # Check if container is running
    if ! docker ps | grep -q "postgres-gpu"; then
        error "PostgreSQL container is not running"
        return 1
    fi
    
    # Check database connectivity
    if docker exec postgres-gpu pg_isready -h localhost >/dev/null 2>&1; then
        success "PostgreSQL is accepting connections"
    else
        error "PostgreSQL is not accepting connections"
        return 1
    fi
    
    # Test actual database query
    if docker exec postgres-gpu psql -U n8n -d n8n -c "SELECT 1;" >/dev/null 2>&1; then
        success "PostgreSQL database queries working"
    else
        error "PostgreSQL database queries failing"
        return 1
    fi
    
    return 0
}

# Validate n8n service
validate_n8n() {
    log "Validating n8n service..."
    
    # Check if container is running
    if ! docker ps | grep -q "n8n-gpu"; then
        error "n8n container is not running"
        return 1
    fi
    
    # Wait for n8n to be available
    if ! wait_for_service "n8n" "http://localhost:5678/healthz"; then
        return 1
    fi
    
    # Test n8n API
    if curl -f -s "http://localhost:5678/api/v1/workflows" >/dev/null 2>&1; then
        success "n8n API is responding"
    else
        warning "n8n API may not be fully initialized"
    fi
    
    # Check n8n database connection
    local response
    response=$(curl -s "http://localhost:5678/healthz" 2>/dev/null || echo "")
    if [[ -n "$response" ]]; then
        success "n8n health endpoint responding"
    else
        error "n8n health endpoint not responding"
        return 1
    fi
    
    return 0
}

# Validate Ollama service
validate_ollama() {
    log "Validating Ollama service..."
    
    # Check if container is running
    if ! docker ps | grep -q "ollama-gpu"; then
        error "Ollama container is not running"
        return 1
    fi
    
    # Wait for Ollama to be available
    if ! wait_for_service "Ollama" "http://localhost:11434/api/tags"; then
        return 1
    fi
    
    # Test Ollama API
    local models
    models=$(curl -s "http://localhost:11434/api/tags" 2>/dev/null | jq -r '.models[]?.name // empty' 2>/dev/null || echo "")
    if [[ -n "$models" ]]; then
        success "Ollama models available: $(echo "$models" | tr '\n' ' ')"
    else
        warning "No Ollama models found - may still be downloading"
    fi
    
    # Test GPU access
    if docker exec ollama-gpu nvidia-smi >/dev/null 2>&1; then
        success "Ollama has GPU access"
    else
        error "Ollama does not have GPU access"
        return 1
    fi
    
    return 0
}

# Validate Qdrant service
validate_qdrant() {
    log "Validating Qdrant service..."
    
    # Check if container is running
    if ! docker ps | grep -q "qdrant-gpu"; then
        error "Qdrant container is not running"
        return 1
    fi
    
    # Wait for Qdrant to be available
    if ! wait_for_service "Qdrant" "http://localhost:6333/healthz"; then
        return 1
    fi
    
    # Test Qdrant API
    if curl -f -s "http://localhost:6333/collections" >/dev/null 2>&1; then
        success "Qdrant API is responding"
    else
        error "Qdrant API not responding"
        return 1
    fi
    
    # Check Qdrant version
    local version
    version=$(curl -s "http://localhost:6333/" 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
    if [[ "$version" != "unknown" ]]; then
        success "Qdrant version: $version"
    else
        warning "Could not determine Qdrant version"
    fi
    
    return 0
}

# Validate Crawl4AI service
validate_crawl4ai() {
    log "Validating Crawl4AI service..."
    
    # Check if container is running
    if ! docker ps | grep -q "crawl4ai-gpu"; then
        error "Crawl4AI container is not running"
        return 1
    fi
    
    # Wait for Crawl4AI to be available
    if ! wait_for_service "Crawl4AI" "http://localhost:11235/health"; then
        return 1
    fi
    
    # Test Crawl4AI API
    if curl -f -s "http://localhost:11235/docs" >/dev/null 2>&1; then
        success "Crawl4AI API documentation accessible"
    else
        warning "Crawl4AI API documentation not accessible"
    fi
    
    return 0
}

# Validate monitoring services
validate_monitoring() {
    log "Validating monitoring services..."
    
    # Check GPU monitoring
    if docker ps | grep -q "gpu-monitor"; then
        success "GPU monitoring container is running"
        
        # Check if metrics are being generated
        if [[ -f "/shared/gpu_metrics.json" ]] || docker exec gpu-monitor test -f /shared/gpu_metrics.json 2>/dev/null; then
            success "GPU metrics are being generated"
        else
            warning "GPU metrics file not found"
        fi
    else
        warning "GPU monitoring container not running"
    fi
    
    # Check health check service
    if docker ps | grep -q "health-check"; then
        success "Health check service is running"
    else
        warning "Health check service not running"
    fi
    
    return 0
}

# Validate EFS persistence (if applicable)
validate_persistence() {
    log "Validating data persistence..."
    
    # Check if EFS volumes are mounted
    local efs_volumes=("n8n_storage" "postgres_storage" "ollama_storage" "qdrant_storage")
    local mounted_volumes=0
    
    for volume in "${efs_volumes[@]}"; do
        if docker volume ls | grep -q "$volume"; then
            ((mounted_volumes++))
        fi
    done
    
    if [[ $mounted_volumes -eq ${#efs_volumes[@]} ]]; then
        success "All EFS volumes are mounted"
    else
        warning "Only $mounted_volumes/${#efs_volumes[@]} EFS volumes are mounted"
    fi
    
    # Check if data is being persisted
    if docker exec n8n-gpu test -d /home/node/.n8n 2>/dev/null; then
        success "n8n data directory exists"
    else
        warning "n8n data directory not found"
    fi
    
    if docker exec postgres-gpu test -d /var/lib/postgresql/data 2>/dev/null; then
        success "PostgreSQL data directory exists"
    else
        warning "PostgreSQL data directory not found"
    fi
    
    return 0
}

# Validate networking
validate_networking() {
    log "Validating networking..."
    
    # Check if ai_network exists
    if docker network ls | grep -q "ai_network"; then
        success "AI network exists"
    else
        error "AI network not found"
        return 1
    fi
    
    # Test inter-service communication
    if docker exec n8n-gpu curl -f -s http://postgres:5432 >/dev/null 2>&1; then
        success "n8n can reach PostgreSQL"
    else
        warning "n8n cannot reach PostgreSQL"
    fi
    
    if docker exec n8n-gpu curl -f -s http://ollama:11434/api/tags >/dev/null 2>&1; then
        success "n8n can reach Ollama"
    else
        warning "n8n cannot reach Ollama"
    fi
    
    if docker exec n8n-gpu curl -f -s http://qdrant:6333/healthz >/dev/null 2>&1; then
        success "n8n can reach Qdrant"
    else
        warning "n8n cannot reach Qdrant"
    fi
    
    return 0
}

# Run functional tests
run_functional_tests() {
    log "Running functional tests..."
    
    # Test simple workflow creation in n8n (if possible)
    local test_workflow='{
        "name": "Validation Test Workflow",
        "nodes": [
            {
                "id": "1",
                "name": "Start",
                "type": "n8n-nodes-base.start",
                "position": [240, 300],
                "parameters": {}
            }
        ],
        "connections": {}
    }'
    
    # Test Ollama model loading (simple test)
    if curl -s -X POST "http://localhost:11434/api/generate" \
       -H "Content-Type: application/json" \
       -d '{"model": "llama2", "prompt": "test", "stream": false}' 2>/dev/null | grep -q "response"; then
        success "Ollama model inference test passed"
    else
        warning "Ollama model inference test failed (models may still be loading)"
    fi
    
    # Test Qdrant collection creation
    if curl -s -X PUT "http://localhost:6333/collections/test-collection" \
       -H "Content-Type: application/json" \
       -d '{"vectors": {"size": 384, "distance": "Cosine"}}' 2>/dev/null | grep -q "result"; then
        success "Qdrant collection creation test passed"
        
        # Clean up test collection
        curl -s -X DELETE "http://localhost:6333/collections/test-collection" >/dev/null 2>&1
    else
        warning "Qdrant collection creation test failed"
    fi
    
    return 0
}

# =============================================================================
# MAIN VALIDATION
# =============================================================================

main() {
    echo -e "${BLUE}=== GeuseMaker Deployment Validation ===${NC}"
    echo "Validating deployment health and functionality..."
    echo
    
    local total_errors=0
    local start_time
    start_time=$(date +%s)
    
    # Run all validation functions
    validate_postgres || ((total_errors++))
    echo
    
    validate_n8n || ((total_errors++))
    echo
    
    validate_ollama || ((total_errors++))
    echo
    
    validate_qdrant || ((total_errors++))
    echo
    
    validate_crawl4ai || ((total_errors++))
    echo
    
    validate_monitoring
    echo
    
    validate_persistence
    echo
    
    validate_networking || ((total_errors++))
    echo
    
    run_functional_tests
    echo
    
    # Final summary
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "${BLUE}=== Deployment Validation Summary ===${NC}"
    echo "Validation completed in ${duration}s"
    
    if [[ $total_errors -eq 0 ]]; then
        success "Deployment validation passed! All services are healthy."
        echo
        echo "Service endpoints:"
        echo "  n8n:      http://localhost:5678"
        echo "  Ollama:   http://localhost:11434"
        echo "  Qdrant:   http://localhost:6333"
        echo "  Crawl4AI: http://localhost:11235"
        echo
        exit 0
    else
        error "Deployment validation failed with $total_errors critical errors"
        echo "Review the issues above and check service logs:"
        echo "  docker compose -f docker-compose.gpu-optimized.yml logs [service-name]"
        echo
        exit 1
    fi
}

# Display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate AI starter kit deployment health and functionality.

OPTIONS:
    -t, --timeout SECONDS    Maximum time to wait for services (default: 60)
    -i, --interval SECONDS   Retry interval for service checks (default: 5)
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message

EXAMPLES:
    $0                      # Run with default settings
    $0 -v -t 120           # Verbose mode, 2-minute timeout
    $0 --timeout 300       # 5-minute timeout for slow systems

EXIT CODES:
    0    All validations passed
    1    Some validations failed
    2    Critical errors detected

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -i|--interval)
            RETRY_INTERVAL="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi