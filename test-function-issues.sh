#!/bin/bash

# Test script to validate problematic functions: get_comprehensive_spot_pricing and launch_spot_instance
# This script will test the functions in isolation to identify issues

set -e

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test logging functions
test_log() { echo -e "${BLUE}[TEST] $1${NC}" >&2; }
test_error() { echo -e "${RED}[TEST ERROR] $1${NC}" >&2; }
test_success() { echo -e "${GREEN}[TEST SUCCESS] $1${NC}" >&2; }
test_warning() { echo -e "${YELLOW}[TEST WARNING] $1${NC}" >&2; }

echo "=============================================="
echo "🧪 Testing Problematic Functions"
echo "=============================================="

# Set up test environment
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

# Source the main script to get function definitions
test_log "Loading functions from aws-deployment.sh..."
if [[ ! -f "scripts/aws-deployment.sh" ]]; then
    test_error "aws-deployment.sh not found in scripts/ directory"
    exit 1
fi

# Extract and test functions in isolation
source scripts/aws-deployment.sh 2>/dev/null || {
    test_error "Failed to source aws-deployment.sh"
    exit 1
}

test_success "Functions loaded successfully"

echo ""
echo "=============================================="
echo "🧪 Testing get_comprehensive_spot_pricing"
echo "=============================================="

test_get_comprehensive_spot_pricing() {
    test_log "Testing get_comprehensive_spot_pricing function..."
    
    # Test with valid inputs
    local test_instance_types="g4dn.xlarge g5g.xlarge"
    local test_region="us-east-1"
    
    test_log "Testing with instance types: $test_instance_types"
    test_log "Testing with region: $test_region"
    
    # Check if function exists
    if ! declare -f get_comprehensive_spot_pricing >/dev/null; then
        test_error "get_comprehensive_spot_pricing function not found"
        return 1
    fi
    
    # Test function execution
    local result
    if result=$(get_comprehensive_spot_pricing "$test_instance_types" "$test_region" 2>&1); then
        test_success "Function executed without errors"
        
        # Check if result is valid JSON
        if echo "$result" | jq empty 2>/dev/null; then
            test_success "Function returned valid JSON"
            test_log "Sample result:"
            echo "$result" | jq -r '.[0:2] | .[] | "  \(.instance_type) in \(.az): $\(.price)/hour"' 2>/dev/null || {
                test_warning "Could not parse result format"
                echo "$result" | head -5
            }
        else
            test_error "Function returned invalid JSON"
            test_log "Raw output:"
            echo "$result" | head -10
            return 1
        fi
    else
        test_error "Function execution failed"
        test_log "Error output:"
        echo "$result"
        return 1
    fi
}

test_launch_spot_instance() {
    test_log "Testing launch_spot_instance function structure..."
    
    # Check if function exists
    if ! declare -f launch_spot_instance >/dev/null; then
        test_error "launch_spot_instance function not found"
        return 1
    fi
    
    test_success "launch_spot_instance function found"
    
    # Test parameter validation (without actually launching)
    test_log "Testing parameter validation..."
    
    # Mock required variables for testing
    export INSTANCE_TYPE="g4dn.xlarge"
    export MAX_SPOT_PRICE="1.00"
    export AWS_REGION="us-east-1"
    
    # Check function dependencies
    local missing_deps=()
    
    for func in "select_optimal_configuration" "get_gpu_config" "verify_ami_availability" "create_optimized_user_data"; do
        if ! declare -f "$func" >/dev/null; then
            missing_deps+=("$func")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        test_warning "Missing dependency functions: ${missing_deps[*]}"
    else
        test_success "All dependency functions found"
    fi
    
    # Test with empty parameters (should fail gracefully)
    test_log "Testing with empty parameters..."
    if launch_spot_instance "" "" "false" 2>/dev/null; then
        test_warning "Function didn't fail with empty parameters (might be an issue)"
    else
        test_success "Function properly validates empty parameters"
    fi
}

echo ""
echo "=============================================="
echo "🧪 Testing launch_spot_instance"
echo "=============================================="

# Run tests
test_comprehensive_pricing_result=0
test_launch_instance_result=0

if test_get_comprehensive_spot_pricing; then
    test_comprehensive_pricing_result=1
fi

if test_launch_spot_instance; then
    test_launch_instance_result=1
fi

echo ""
echo "=============================================="
echo "🧪 Analyzing Potential Issues"
echo "=============================================="

analyze_issues() {
    test_log "Analyzing common function issues..."
    
    # Check for common AWS CLI issues
    test_log "Checking AWS CLI command patterns..."
    
    # Check get_comprehensive_spot_pricing for issues
    grep -n "aws ec2 describe-spot-price-history" scripts/aws-deployment.sh | while read -r line; do
        test_log "Found AWS CLI command: $line"
    done
    
    # Check for jq usage issues
    test_log "Checking jq command patterns..."
    grep -n "jq.*group_by" scripts/aws-deployment.sh | while read -r line; do
        test_warning "Complex jq command found: $line"
    done
    
    # Check for variable expansion issues
    test_log "Checking variable expansion patterns..."
    grep -n '\$[A-Z_]*[^"]' scripts/aws-deployment.sh | head -5 | while read -r line; do
        test_warning "Potential unquoted variable: $line"
    done
}

analyze_issues

echo ""
echo "=============================================="
echo "🧪 Test Results Summary"
echo "=============================================="

if [[ $test_comprehensive_pricing_result -eq 1 ]]; then
    test_success "get_comprehensive_spot_pricing: PASSED"
else
    test_error "get_comprehensive_spot_pricing: FAILED"
fi

if [[ $test_launch_instance_result -eq 1 ]]; then
    test_success "launch_spot_instance: PASSED"
else
    test_error "launch_spot_instance: FAILED"
fi

echo ""
test_log "Test completed. Check output above for specific issues."