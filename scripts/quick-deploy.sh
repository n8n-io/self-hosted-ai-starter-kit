#!/bin/bash
# =============================================================================
# Quick Deployment Script with Extended Timeouts for GPU Instances
# Optimized for instances with comprehensive user data scripts
# =============================================================================

set -euo pipefail

# Load shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

source "$LIB_DIR/error-handling.sh"
source "$LIB_DIR/aws-deployment-common.sh"
source "$LIB_DIR/aws-config.sh"

# Load the new centralized configuration management system
if [ -f "$LIB_DIR/config-management.sh" ]; then
    source "$LIB_DIR/config-management.sh"
    CONFIG_MANAGEMENT_AVAILABLE=true
else
    CONFIG_MANAGEMENT_AVAILABLE=false
    warning "Centralized configuration management not available, using legacy mode"
fi

# Configuration
DEPLOYMENT_TYPE="${1:-spot}"
STACK_NAME="${2:-$(date +%s)}"
BUDGET_TIER="${3:-medium}"

# Override SSH timeout settings for GPU instances
export SSH_MAX_ATTEMPTS=90  # 90 attempts instead of 60
export SSH_SLEEP_INTERVAL=20  # 20 seconds instead of 15

echo "🚀 Quick Deployment with Extended Timeouts"
echo "=========================================="
echo "Deployment Type: $DEPLOYMENT_TYPE"
echo "Stack Name: $STACK_NAME"
echo "Budget Tier: $BUDGET_TIER"
echo "SSH Timeout: $((SSH_MAX_ATTEMPTS * SSH_SLEEP_INTERVAL / 60)) minutes"
echo ""

# Run the main deployment script with our custom settings
"$PROJECT_ROOT/scripts/aws-deployment-unified.sh" \
    --deployment-type "$DEPLOYMENT_TYPE" \
    --stack-name "$STACK_NAME" \
    --budget-tier "$BUDGET_TIER" \
    --no-cleanup-on-failure

echo ""
echo "✅ Quick deployment completed!"
echo "💡 If you encounter SSH timeout issues, the instance may still be usable."
echo "🔍 Run './scripts/check-instance-status.sh $STACK_NAME' to check instance status." 