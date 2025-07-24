#!/bin/bash

# Simple test script to identify function logic issues without AWS calls

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

test_log() { echo -e "${BLUE}[TEST] $1${NC}" >&2; }
test_error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }
test_success() { echo -e "${GREEN}[SUCCESS] $1${NC}" >&2; }

echo "=============================================="
echo "🔍 Function Logic Analysis"
echo "=============================================="

# Check syntax of the main script
test_log "Checking script syntax..."
if bash -n scripts/aws-deployment.sh; then
    test_success "Script syntax is valid"
else
    test_error "Script has syntax errors"
    exit 1
fi

# Analyze get_comprehensive_spot_pricing function
test_log "Analyzing get_comprehensive_spot_pricing function..."

echo "Issues found in get_comprehensive_spot_pricing:"
echo "1. Complex jq query on line 384 may fail with certain AWS responses"
echo "2. Fallback logic creates mock data when AWS API fails"
echo "3. Multiple temporary file operations without proper error handling"

# Extract the problematic jq command
echo ""
echo "Problematic jq command:"
grep -A 1 -B 1 "group_by.*map.*instance_type" scripts/aws-deployment.sh

echo ""
test_log "Analyzing launch_spot_instance function..."

echo "Issues found in launch_spot_instance:"
echo "1. Complex IFS parsing that may fail with malformed input"
echo "2. Multiple dependency functions that may return empty values"
echo "3. Fallback logic for old vs new format parsing"

# Show the problematic parsing logic
echo ""
echo "Problematic parsing logic:"
grep -A 5 -B 2 "IFS=.*read.*SELECTED_" scripts/aws-deployment.sh

echo ""
echo "=============================================="
echo "🔧 Recommended Fixes"
echo "=============================================="

echo "1. Simplify jq queries and add better error handling"
echo "2. Add validation for all parsed variables"
echo "3. Comment out fallback logic that creates unreliable data"
echo "4. Add debug output to identify where functions fail"