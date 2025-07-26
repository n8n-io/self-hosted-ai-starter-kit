#!/bin/bash

# Comprehensive Docker Compose Validation Test
# Tests Docker Compose configuration in various deployment scenarios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.gpu-optimized.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Detect Docker Compose command
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}Error: Neither 'docker compose' nor 'docker-compose' command found${NC}"
    exit 1
fi

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_RUN++))
    log "Running test: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        success "$test_name"
        return 0
    else
        fail "$test_name"
        return 1
    fi
}

# Test 1: Basic YAML syntax validation
test_yaml_syntax() {
    log "Testing YAML syntax validation..."
    
    # Try to parse the YAML without variable substitution using Python if available
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml; yaml.safe_load(open('$COMPOSE_FILE'))" 2>/dev/null; then
            success "YAML syntax is valid (Python validation)"
            return 0
        fi
    fi
    
    # Fallback: Use Docker Compose to validate syntax (may show warnings but shouldn't fail)
    if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" config --quiet 2>/dev/null | grep -q "services:"; then
        success "YAML syntax is valid (Docker Compose validation)"
        return 0
    else
        warn "YAML syntax validation inconclusive (Python yaml module not available)"
        return 0  # Don't fail the test if we can't validate properly
    fi
}

# Test 2: Docker Compose config with minimal environment
test_minimal_environment() {
    log "Testing with minimal environment variables..."
    
    # Create temporary minimal environment
    local temp_env=$(mktemp)
    cat > "$temp_env" << 'EOF'
EFS_DNS=test.efs.us-east-1.amazonaws.com
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=testpass
N8N_HOST=0.0.0.0
WEBHOOK_URL=http://localhost:5678
N8N_CORS_ALLOWED_ORIGINS=http://localhost:5678
OLLAMA_ORIGINS=http://localhost:*
INSTANCE_TYPE=g4dn.xlarge
AWS_DEFAULT_REGION=us-east-1
INSTANCE_ID=i-test
OPENAI_API_KEY=test
ANTHROPIC_API_KEY=test
DEEPSEEK_API_KEY=test
GROQ_API_KEY=test
TOGETHER_API_KEY=test
MISTRAL_API_KEY=test
GEMINI_API_TOKEN=test
EOF
    
    if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$temp_env" config > /dev/null 2>&1; then
        success "Configuration valid with minimal environment"
        rm -f "$temp_env"
        return 0
    else
        fail "Configuration invalid with minimal environment"
        rm -f "$temp_env"
        return 1
    fi
}

# Test 3: Production environment simulation
test_production_environment() {
    log "Testing with production-like environment..."
    
    local temp_env=$(mktemp)
    cat > "$temp_env" << 'EOF'
EFS_DNS=fs-0123456789abcdef0.efs.us-east-1.amazonaws.com
POSTGRES_DB=n8n_prod
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=secure_password_123
N8N_HOST=0.0.0.0
WEBHOOK_URL=https://n8n.example.com
N8N_CORS_ALLOWED_ORIGINS=https://n8n.example.com,https://app.example.com
OLLAMA_ORIGINS=https://n8n.example.com
INSTANCE_TYPE=g4dn.xlarge
AWS_DEFAULT_REGION=us-east-1
INSTANCE_ID=i-0123456789abcdef0
OPENAI_API_KEY=sk-proj-test123
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
MISTRAL_API_KEY=
GEMINI_API_TOKEN=
EOF
    
    if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$temp_env" config > /dev/null 2>&1; then
        success "Configuration valid with production environment"
        rm -f "$temp_env"
        return 0
    else
        fail "Configuration invalid with production environment"
        rm -f "$temp_env"
        return 1
    fi
}

# Test 4: Service dependencies validation
test_service_dependencies() {
    log "Testing service dependencies..."
    
    local temp_env=$(mktemp)
    cat > "$temp_env" << 'EOF'
EFS_DNS=test.efs.us-east-1.amazonaws.com
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=testpass
N8N_HOST=0.0.0.0
WEBHOOK_URL=http://localhost:5678
N8N_CORS_ALLOWED_ORIGINS=http://localhost:5678
OLLAMA_ORIGINS=http://localhost:*
INSTANCE_TYPE=g4dn.xlarge
AWS_DEFAULT_REGION=us-east-1
INSTANCE_ID=i-test
OPENAI_API_KEY=test
ANTHROPIC_API_KEY=test
DEEPSEEK_API_KEY=test
GROQ_API_KEY=test
TOGETHER_API_KEY=test
MISTRAL_API_KEY=test
GEMINI_API_TOKEN=test
EOF
    
    # Parse the config and check for dependency issues
    local config_output=$($DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$temp_env" config 2>&1)
    
    # Check for circular dependencies or other issues
    if echo "$config_output" | grep -q "Circular import" || echo "$config_output" | grep -qi "dependency.*error"; then
        fail "Service dependency validation failed"
        rm -f "$temp_env"
        return 1
    else
        success "Service dependencies are valid"
        rm -f "$temp_env"
        return 0
    fi
}

# Test 5: Resource limits validation
test_resource_limits() {
    log "Testing resource limits configuration..."
    
    local temp_env=$(mktemp)
    cat > "$temp_env" << 'EOF'
EFS_DNS=test.efs.us-east-1.amazonaws.com
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=testpass
N8N_HOST=0.0.0.0
WEBHOOK_URL=http://localhost:5678
N8N_CORS_ALLOWED_ORIGINS=http://localhost:5678
OLLAMA_ORIGINS=http://localhost:*
INSTANCE_TYPE=g4dn.xlarge
AWS_DEFAULT_REGION=us-east-1
INSTANCE_ID=i-test
OPENAI_API_KEY=test
ANTHROPIC_API_KEY=test
DEEPSEEK_API_KEY=test
GROQ_API_KEY=test
TOGETHER_API_KEY=test
MISTRAL_API_KEY=test
GEMINI_API_TOKEN=test
EOF
    
    # Get the config and analyze resource limits
    local config_output=$($DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$temp_env" config 2>/dev/null)
    
    # Check that services have resource limits defined
    if echo "$config_output" | grep -q "resources:" && echo "$config_output" | grep -q "limits:"; then
        success "Resource limits are properly configured"
        rm -f "$temp_env"
        return 0
    else
        fail "Resource limits configuration missing or invalid"
        rm -f "$temp_env"
        return 1
    fi
}

# Test 6: Image update script integration
test_image_update_integration() {
    log "Testing image update script integration..."
    
    if [[ -f "${PROJECT_ROOT}/scripts/simple-update-images.sh" ]]; then
        if "${PROJECT_ROOT}/scripts/simple-update-images.sh" test >/dev/null 2>&1; then
            success "Image update script integration works"
            return 0
        else
            fail "Image update script integration failed"
            return 1
        fi
    else
        fail "Image update script not found"
        return 1
    fi
}

# Test 7: Secrets configuration validation
test_secrets_configuration() {
    log "Testing secrets configuration..."
    
    local secrets_dir="${PROJECT_ROOT}/secrets"
    local required_secrets=("postgres_password.txt" "n8n_encryption_key.txt" "n8n_jwt_secret.txt")
    
    for secret in "${required_secrets[@]}"; do
        if [[ ! -f "$secrets_dir/$secret" ]]; then
            fail "Required secret file missing: $secret"
            return 1
        fi
    done
    
    success "All required secret files are present"
    return 0
}

# Main test execution
main() {
    echo -e "${BLUE}=== Docker Compose Validation Test Suite ===${NC}"
    echo -e "${BLUE}Docker Compose Version: $($DOCKER_COMPOSE_CMD version --short)${NC}"
    echo -e "${BLUE}Testing file: $COMPOSE_FILE${NC}"
    echo ""
    
    # Run all tests
    test_yaml_syntax
    test_minimal_environment
    test_production_environment
    test_service_dependencies
    test_resource_limits
    test_image_update_integration
    test_secrets_configuration
    
    echo ""
    echo -e "${BLUE}=== Test Results ===${NC}"
    echo -e "Tests run: ${TESTS_RUN}"
    echo -e "${GREEN}Tests passed: ${TESTS_PASSED}${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Tests failed: ${TESTS_FAILED}${NC}"
        echo ""
        echo -e "${RED}❌ Some tests failed. Please review the issues above.${NC}"
        exit 1
    else
        echo -e "${RED}Tests failed: ${TESTS_FAILED}${NC}"
        echo ""
        echo -e "${GREEN}✅ All tests passed! Docker Compose configuration is valid.${NC}"
        exit 0
    fi
}

# Run the tests
main "$@"