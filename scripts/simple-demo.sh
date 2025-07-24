#!/bin/bash

# =============================================================================
# GeuseMaker - Simple Intelligent Selection Demo  
# =============================================================================
# Compatible with older bash versions (works on macOS default bash 3.2)
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

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
🤖 INTELLIGENT GPU SELECTION DEMO 🚀
====================================
This demo shows how the refactored AWS deployment script
intelligently selects optimal GPU configurations based on:
- Real-time spot pricing analysis
- Price/performance ratios
- Multi-architecture support (Intel x86_64 & ARM64)
- Budget constraints and availability
EOF
    echo -e "${NC}"
    echo ""
}

show_configurations() {
    log "📋 Available GPU Configurations:"
    echo ""
    echo -e "${CYAN}Instance Types Supported:${NC}"
    echo ""
    echo -e "${YELLOW}G4DN Instances (Intel Xeon + NVIDIA T4):${NC}"
    echo -e "  📦 g4dn.xlarge:  4 vCPUs, 16GB RAM, 1x T4  - Primary AMI: ami-0489c31b03f0be3d6"
    echo -e "  📦 g4dn.2xlarge: 8 vCPUs, 32GB RAM, 1x T4  - Primary AMI: ami-0489c31b03f0be3d6"
    echo ""
    echo -e "${YELLOW}G5G Instances (ARM Graviton2 + NVIDIA T4G):${NC}"
    echo -e "  📦 g5g.xlarge:   4 vCPUs, 8GB RAM,  1x T4G - Primary AMI: ami-0126d561b2bb55618"
    echo -e "  📦 g5g.2xlarge:  8 vCPUs, 16GB RAM, 1x T4G - Primary AMI: ami-0126d561b2bb55618"
    echo ""
    echo -e "${BLUE}Each configuration has primary + secondary AMI fallbacks${NC}"
    echo ""
}

show_pricing_analysis() {
    log "💰 Spot Pricing Analysis (Sample Current Prices):"
    echo ""
    echo -e "${CYAN}Current Market Pricing:${NC}"
    echo "┌─────────────────┬─────────────┬─────────────┬─────────────────┐"
    echo "│ Instance Type   │ Spot Price  │ Perf Score  │ Price/Perf Ratio│"
    echo "├─────────────────┼─────────────┼─────────────┼─────────────────┤"
    echo "│ g4dn.xlarge     │ \$0.45/hr   │ 70/100      │ 155.6           │"
    echo "│ g4dn.2xlarge    │ \$0.89/hr   │ 85/100      │ 95.5            │"
    echo "│ g5g.xlarge      │ \$0.38/hr   │ 65/100      │ 171.1 🎯 BEST   │"
    echo "│ g5g.2xlarge     │ \$0.75/hr   │ 80/100      │ 106.7           │"
    echo "└─────────────────┴─────────────┴─────────────┴─────────────────┘"
    echo ""
    echo -e "${GREEN}🎯 OPTIMAL SELECTION: g5g.xlarge${NC}"
    echo -e "  ${CYAN}Reason:${NC} Best price/performance ratio (171.1)"
    echo -e "  ${CYAN}Architecture:${NC} ARM64 Graviton2 (up to 40% better price/performance)"
    echo -e "  ${CYAN}GPU:${NC} NVIDIA T4G Tensor Core"
    echo -e "  ${CYAN}Cost:${NC} \$0.38/hour (\$9.12/day for 24 hours)"
    echo ""
}

show_selection_process() {
    log "🧠 Intelligent Selection Process:"
    echo ""
    
    info "Step 1: Instance type availability check..."
    echo "  ✓ Scanning all availability zones in region"
    echo "  ✓ Verifying g4dn.xlarge, g4dn.2xlarge, g5g.xlarge, g5g.2xlarge"
    echo ""
    
    info "Step 2: AMI availability verification..."
    echo "  ✓ Checking primary AMIs: ami-0489c31b03f0be3d6, ami-0126d561b2bb55618"
    echo "  ✓ Checking secondary AMIs: ami-00b530caaf8eee2c5, ami-04ba92cdace8a636f"
    echo ""
    
    info "Step 3: Real-time spot pricing retrieval..."
    echo "  ✓ Fetching current spot prices across all AZs"
    echo "  ✓ Analyzing price trends and availability"
    echo ""
    
    info "Step 4: Cost-performance matrix calculation..."
    echo "  ✓ Computing price/performance ratios"
    echo "  ✓ Applying budget constraints (max: \$2.00/hour)"
    echo "  ✓ Factoring in architecture benefits"
    echo ""
    
    success "✓ Optimal configuration determined: g5g.xlarge with ARM64 architecture"
    echo ""
}

show_architecture_benefits() {
    log "🏗️ Multi-Architecture Intelligence:"
    echo ""
    
    echo -e "${BLUE}Intel x86_64 Benefits (G4DN):${NC}"
    echo -e "  ${GREEN}✓${NC} Universal software compatibility"
    echo -e "  ${GREEN}✓${NC} Mature ML ecosystem"
    echo -e "  ${GREEN}✓${NC} Proven NVIDIA T4 performance"
    echo -e "  ${GREEN}✓${NC} Wide framework support"
    echo ""
    
    echo -e "${BLUE}ARM64 Graviton2 Benefits (G5G):${NC}"
    echo -e "  ${GREEN}✓${NC} Up to 40% better price-performance"
    echo -e "  ${GREEN}✓${NC} Lower power consumption"
    echo -e "  ${GREEN}✓${NC} AWS-optimized silicon"
    echo -e "  ${GREEN}✓${NC} NVIDIA T4G tensor cores"
    echo -e "  ${YELLOW}⚠${NC} May require ARM64-compatible containers"
    echo ""
    
    echo -e "${PURPLE}Smart Selection:${NC} The algorithm automatically chooses the best"
    echo -e "architecture based on current pricing and availability!"
    echo ""
}

show_deployment_features() {
    log "🚀 Enhanced Deployment Capabilities:"
    echo ""
    
    echo -e "${GREEN}Cost Optimization:${NC}"
    echo -e "  💰 Real-time spot pricing analysis"
    echo -e "  💰 Multi-AZ price comparison"
    echo -e "  💰 Budget constraint enforcement"
    echo -e "  💰 Price/performance ratio optimization"
    echo ""
    
    echo -e "${GREEN}Intelligence Features:${NC}"
    echo -e "  🤖 Automatic AMI selection (primary/secondary fallbacks)"
    echo -e "  🤖 Instance type availability checking"
    echo -e "  🤖 Architecture-aware deployments"
    echo -e "  🤖 Performance scoring and ranking"
    echo ""
    
    echo -e "${GREEN}Multi-Architecture Support:${NC}"
    echo -e "  🏗️ Intel x86_64 and ARM64 Graviton2"
    echo -e "  🏗️ Architecture-specific user data generation"
    echo -e "  🏗️ Optimized GPU driver installation"
    echo -e "  🏗️ Container runtime configuration"
    echo ""
}

show_usage_examples() {
    log "🎯 Usage Examples:"
    echo ""
    
    echo -e "${CYAN}Intelligent Auto-Selection (Recommended):${NC}"
    echo -e "  ${YELLOW}./scripts/aws-deployment.sh${NC}"
    echo -e "  → Automatically selects best price/performance configuration"
    echo ""
    
    echo -e "${CYAN}Custom Budget Constraint:${NC}"
    echo -e "  ${YELLOW}./scripts/aws-deployment.sh --max-spot-price 1.50${NC}"
    echo -e "  → Limits selection to configurations under \$1.50/hour"
    echo ""
    
    echo -e "${CYAN}Force Specific Instance Type:${NC}"
    echo -e "  ${YELLOW}./scripts/aws-deployment.sh --instance-type g4dn.xlarge${NC}"
    echo -e "  → Uses Intel x86_64 with automatic AMI selection"
    echo ""
    
    echo -e "${CYAN}Force ARM Architecture:${NC}"
    echo -e "  ${YELLOW}./scripts/aws-deployment.sh --instance-type g5g.2xlarge${NC}"
    echo -e "  → Uses ARM64 Graviton2 with automatic AMI selection"
    echo ""
    
    echo -e "${CYAN}Different Region:${NC}"
    echo -e "  ${YELLOW}./scripts/aws-deployment.sh --region us-west-2${NC}"
    echo -e "  → Analyzes pricing and availability in us-west-2"
    echo ""
}

main() {
    show_banner
    show_configurations
    show_pricing_analysis
    show_selection_process
    show_architecture_benefits
    show_deployment_features
    show_usage_examples
    
    echo -e "${PURPLE}🎉 Demo Complete!${NC}"
    echo ""
    echo -e "${GREEN}The refactored deployment script now intelligently:${NC}"
    echo -e "  ✅ Analyzes real-time pricing across multiple instance types"
    echo -e "  ✅ Selects optimal AMIs with primary/secondary fallbacks" 
    echo -e "  ✅ Supports both Intel x86_64 and ARM64 architectures"
    echo -e "  ✅ Optimizes for best price/performance within budget"
    echo -e "  ✅ Handles multi-AZ deployment with cost optimization"
    echo ""
    echo -e "${BLUE}Ready to deploy your AI infrastructure with intelligence! 🚀${NC}"
    echo ""
}

main "$@" 