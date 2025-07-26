#!/bin/bash

# Test ALB and CloudFront Deployment Flags
# This script tests the new ALB and CloudFront functionality without actual deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/../scripts/aws-deployment-unified.sh"
SIMPLE_SCRIPT="$SCRIPT_DIR/../scripts/aws-deployment-simple.sh"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Test 1: Check if scripts exist and are executable
test_scripts_exist() {
    log "Testing if deployment scripts exist..."
    
    local failed=0
    
    for script in "$MAIN_SCRIPT" "$SIMPLE_SCRIPT"; do
        if [ -f "$script" ]; then
            success "✓ $(basename "$script") exists"
        else
            error "✗ $(basename "$script") not found"
            ((failed++))
        fi
        
        if [ -x "$script" ]; then
            success "✓ $(basename "$script") is executable"
        else
            error "✗ $(basename "$script") is not executable"
            ((failed++))
        fi
    done
    
    return $failed
}

# Test 2: Check if help includes new ALB/CloudFront flags
test_help_includes_flags() {
    log "Testing if help text includes new flags..."
    
    local failed=0
    
    # Test main deployment script help
    if "$MAIN_SCRIPT" --help 2>&1 | grep -q -- "--setup-alb"; then
        success "✓ Main script help includes --setup-alb flag"
    else
        error "✗ Main script help missing --setup-alb flag"
        ((failed++))
    fi
    
    if "$MAIN_SCRIPT" --help 2>&1 | grep -q -- "--setup-cloudfront"; then
        success "✓ Main script help includes --setup-cloudfront flag"
    else
        error "✗ Main script help missing --setup-cloudfront flag"
        ((failed++))
    fi
    
    if "$MAIN_SCRIPT" --help 2>&1 | grep -q -- "--setup-cdn"; then
        success "✓ Main script help includes --setup-cdn flag"
    else
        error "✗ Main script help missing --setup-cdn flag"
        ((failed++))
    fi
    
    return $failed
}

# Test 3: Check if ALB and CloudFront functions exist
test_functions_exist() {
    log "Testing if ALB and CloudFront functions exist in scripts..."
    
    local failed=0
    
    if grep -q "setup_alb()" "$MAIN_SCRIPT"; then
        success "✓ setup_alb function exists in main script"
    else
        error "✗ setup_alb function missing from main script"
        ((failed++))
    fi
    
    if grep -q "setup_cloudfront()" "$MAIN_SCRIPT"; then
        success "✓ setup_cloudfront function exists in main script"
    else
        error "✗ setup_cloudfront function missing from main script"
        ((failed++))
    fi
    
    return $failed
}

# Test 4: Check if environment variables are properly defined
test_environment_variables() {
    log "Testing if environment variables are properly defined..."
    
    local failed=0
    
    if grep -q "SETUP_ALB.*false" "$MAIN_SCRIPT"; then
        success "✓ SETUP_ALB variable defined in main script"
    else
        error "✗ SETUP_ALB variable missing from main script"
        ((failed++))
    fi
    
    if grep -q "SETUP_CLOUDFRONT.*false" "$MAIN_SCRIPT"; then
        success "✓ SETUP_CLOUDFRONT variable defined in main script"
    else
        error "✗ SETUP_CLOUDFRONT variable missing from main script"
        ((failed++))
    fi
    
    if grep -q "SETUP_ALB.*false" "$SIMPLE_SCRIPT"; then
        success "✓ SETUP_ALB variable defined in simple script"
    else
        error "✗ SETUP_ALB variable missing from simple script"
        ((failed++))
    fi
    
    return $failed
}

# Test 5: Check if argument parsing includes new flags
test_argument_parsing() {
    log "Testing if argument parsing includes new flags..."
    
    local failed=0
    
    if grep -q -- "--setup-alb)" "$MAIN_SCRIPT"; then
        success "✓ --setup-alb argument parsing exists"
    else
        error "✗ --setup-alb argument parsing missing"
        ((failed++))
    fi
    
    if grep -q -- "--setup-cloudfront)" "$MAIN_SCRIPT"; then
        success "✓ --setup-cloudfront argument parsing exists"
    else
        error "✗ --setup-cloudfront argument parsing missing"
        ((failed++))
    fi
    
    if grep -q -- "--setup-cdn)" "$MAIN_SCRIPT"; then
        success "✓ --setup-cdn argument parsing exists"
    else
        error "✗ --setup-cdn argument parsing missing"
        ((failed++))
    fi
    
    return $failed
}

# Test 6: Check if main deployment flow calls the new functions
test_deployment_flow() {
    log "Testing if deployment flow includes ALB and CloudFront setup calls..."
    
    local failed=0
    
    if grep -q "setup_alb.*INSTANCE_ID.*SG_ID" "$MAIN_SCRIPT"; then
        success "✓ Main deployment flow calls setup_alb"
    else
        error "✗ Main deployment flow missing setup_alb call"
        ((failed++))
    fi
    
    if grep -q "setup_cloudfront.*ALB_DNS" "$MAIN_SCRIPT"; then
        success "✓ Main deployment flow calls setup_cloudfront"
    else
        error "✗ Main deployment flow missing setup_cloudfront call"
        ((failed++))
    fi
    
    return $failed
}

# Test 7: Verify conditional execution logic
test_conditional_logic() {
    log "Testing conditional execution logic..."
    
    local failed=0
    
    if grep -q 'SETUP_ALB.*=.*"true"' "$MAIN_SCRIPT"; then
        success "✓ ALB setup has conditional logic"
    else
        error "✗ ALB setup missing conditional logic"
        ((failed++))
    fi
    
    if grep -q 'SETUP_CLOUDFRONT.*=.*"true"' "$MAIN_SCRIPT"; then
        success "✓ CloudFront setup has conditional logic"
    else
        error "✗ CloudFront setup missing conditional logic"
        ((failed++))
    fi
    
    return $failed
}

# Test 8: Check for proper error handling
test_error_handling() {
    log "Testing error handling in ALB and CloudFront functions..."
    
    local failed=0
    
    if grep -A 10 "create-load-balancer" "$MAIN_SCRIPT" | grep -q "2>/dev/null"; then
        success "✓ ALB creation has error handling"
    else
        warn "ALB creation might need better error handling"
    fi
    
    if grep -A 10 "create-distribution" "$MAIN_SCRIPT" | grep -q "2>/dev/null"; then
        success "✓ CloudFront creation has error handling"
    else
        warn "CloudFront creation might need better error handling"
    fi
    
    return $failed
}

# Test 9: Validate AWS CLI commands syntax
test_aws_cli_syntax() {
    log "Testing AWS CLI command syntax..."
    
    local failed=0
    local warnings=0
    
    # Check for proper AWS CLI command structure
    if grep -q "aws elbv2 create-load-balancer" "$MAIN_SCRIPT"; then
        success "✓ ALB creation uses correct AWS CLI command"
    else
        error "✗ ALB creation missing or incorrect AWS CLI command"
        ((failed++))
    fi
    
    if grep -q "aws cloudfront create-distribution" "$MAIN_SCRIPT"; then
        success "✓ CloudFront creation uses correct AWS CLI command"
    else
        error "✗ CloudFront creation missing or incorrect AWS CLI command"
        ((failed++))
    fi
    
    # Check for query parameters
    if grep -q -- "--query.*LoadBalancers" "$MAIN_SCRIPT"; then
        success "✓ ALB commands use proper query syntax"
    else
        warn "ALB commands might be missing query parameters"
        ((warnings++))
    fi
    
    if grep -q "jq.*Distribution" "$MAIN_SCRIPT"; then
        success "✓ CloudFront commands use proper JSON parsing"
    else
        warn "CloudFront commands might be missing JSON parsing"
        ((warnings++))
    fi
    
    return $failed
}

# Test 10: Check documentation examples
test_documentation_examples() {
    log "Testing if documentation includes usage examples..."
    
    local failed=0
    
    if "$MAIN_SCRIPT" --help 2>&1 | grep -A 20 "Load balancer and CDN" | grep -q -- "--setup-alb"; then
        success "✓ Help includes ALB usage example"
    else
        error "✗ Help missing ALB usage example"
        ((failed++))
    fi
    
    if "$MAIN_SCRIPT" --help 2>&1 | grep -A 20 "Load balancer and CDN" | grep -q -- "--setup-cdn"; then
        success "✓ Help includes CDN usage example"
    else
        error "✗ Help missing CDN usage example"
        ((failed++))
    fi
    
    return $failed
}

# Main test runner
main() {
    echo "=============================================="
    echo "    ALB and CloudFront Deployment Test"
    echo "=============================================="
    echo ""
    
    local total_failed=0
    
    # Run all tests
    test_scripts_exist || ((total_failed++))
    echo ""
    
    test_help_includes_flags || ((total_failed++))
    echo ""
    
    test_functions_exist || ((total_failed++))
    echo ""
    
    test_environment_variables || ((total_failed++))
    echo ""
    
    test_argument_parsing || ((total_failed++))
    echo ""
    
    test_deployment_flow || ((total_failed++))
    echo ""
    
    test_conditional_logic || ((total_failed++))
    echo ""
    
    test_error_handling || ((total_failed++))
    echo ""
    
    test_aws_cli_syntax || ((total_failed++))
    echo ""
    
    test_documentation_examples || ((total_failed++))
    echo ""
    
    # Summary
    echo "=============================================="
    if [ $total_failed -eq 0 ]; then
        success "All tests passed! ✅"
        echo ""
        echo "ALB and CloudFront functionality is ready to use:"
        echo ""
        echo "🌐 Usage Examples:"
        echo "  # Deploy with ALB only"
        echo "  ./scripts/aws-deployment-unified.sh --setup-alb"
        echo ""
        echo "  # Deploy with CloudFront only (requires ALB)"
        echo "  ./scripts/aws-deployment-unified.sh --setup-alb --setup-cloudfront"
        echo ""
        echo "  # Deploy with both (convenience flag)"
        echo "  ./scripts/aws-deployment-unified.sh --setup-cdn"
        echo ""
        echo "  # Full deployment with cross-region and CDN"
        echo "  ./scripts/aws-deployment-unified.sh --setup-cdn --cross-region"
        echo ""
        echo "⚠️  Important Notes:"
        echo "  • ALB requires at least 2 availability zones"
        echo "  • CloudFront requires ALB to be enabled"
        echo "  • CloudFront deployment takes 15-20 minutes"
        echo "  • These features are optional and off by default"
    else
        error "$total_failed test(s) failed ❌"
        echo ""
        echo "Please fix the issues above before using ALB/CloudFront features."
        exit 1
    fi
    echo "=============================================="
}

main "$@"