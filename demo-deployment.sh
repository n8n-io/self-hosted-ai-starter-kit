#!/bin/bash

# =============================================================================
# AI Starter Kit - Deployment Demonstration
# =============================================================================
# This script demonstrates the deployment automation capabilities
# Choose between local development and cloud deployment
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

show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 _____ _____   _____ _             _            _   _ _ _   
|  _  |     | |   __| |_ ___ ___ _| |_ ___ ___  | | | |_| |_ 
|     |-   -| |__   |  _| .'|  _|  _| -_|  _|  | |_| | |  _|
|__|__|_____| |_____|_| |__,|_| |_| |___|_|    |___|_|_|_|  
                                                           
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Automated Deployment Demonstration${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo ""
}

show_deployment_options() {
    header "🚀 Deployment Options"
    echo ""
    echo "This AI Starter Kit supports multiple deployment strategies:"
    echo ""
    echo -e "${GREEN}1. Local Development${NC}"
    echo "   ✅ Free to use (your hardware)"
    echo "   ✅ Perfect for testing and development"
    echo "   ✅ CPU-only AI models (slower but functional)"
    echo "   ⚠️  Limited by your system resources"
    echo ""
    echo -e "${GREEN}2. Cloud Deployment (AWS)${NC}"
    echo "   ✅ GPU-accelerated AI models (g4dn.xlarge with T4 GPU)"
    echo "   ✅ 70% cost savings with spot instances"
    echo "   ✅ Auto-scaling and cost optimization"
    echo "   ✅ EFS persistent storage"
    echo "   💰 ~$18-30/day (spot) vs $60-100/day (on-demand)"
    echo ""
}

show_whats_included() {
    header "📦 What's Included"
    echo ""
    echo "Your deployment will include:"
    echo ""
    echo -e "${CYAN}🧠 AI Services:${NC}"
    echo "   • Ollama: Local AI models (DeepSeek-R1, Qwen2.5-VL, Llama3.2)"
    echo "   • Qdrant: Vector database for semantic search"
    echo "   • Crawl4AI: Intelligent web scraping with LLM extraction"
    echo ""
    echo -e "${CYAN}🔄 Automation Platform:${NC}"
    echo "   • n8n: Visual workflow automation"
    echo "   • PostgreSQL: Robust database backend"
    echo "   • Demo workflows and templates"
    echo ""
    echo -e "${CYAN}📊 Monitoring & Optimization:${NC}"
    echo "   • GPU utilization monitoring"
    echo "   • Automatic cost optimization"
    echo "   • Health checks and alerting"
    echo "   • Performance metrics"
    echo ""
}

show_automation_scripts() {
    header "🛠️  Available Automation Scripts"
    echo ""
    echo "The following scripts are ready to use:"
    echo ""
    echo -e "${GREEN}Setup & Environment:${NC}"
    echo "   ./scripts/setup-environment.sh     - Initial environment setup"
    echo "   ./quick-start.sh                   - Quick local development start"
    echo ""
    echo -e "${GREEN}Cloud Deployment:${NC}"
    echo "   ./scripts/aws-deployment.sh        - Full AWS cloud deployment"
    echo "   ./scripts/validate-deployment.sh   - Deployment validation"
    echo ""
    echo -e "${GREEN}Management:${NC}"
    echo "   make help                          - Show all available commands"
    echo "   make setup-models                  - Download AI models"
    echo "   make health                        - Check service health"
    echo "   make status                        - Show system status"
    echo ""
}

demonstrate_local_deployment() {
    header "🏠 Local Deployment Demonstration"
    echo ""
    echo "Let me show you how to deploy locally..."
    echo ""
    
    echo "Step 1: Environment Setup"
    echo "Command: ./scripts/setup-environment.sh"
    echo "This will:"
    echo "  ✓ Check prerequisites (Docker, Git, etc.)"
    echo "  ✓ Create .env file with secure defaults"
    echo "  ✓ Generate encryption keys and passwords"
    echo "  ✓ Set up directory structure"
    echo ""
    
    echo "Step 2: Start Services"
    echo "Command: ./quick-start.sh"
    echo "This will:"
    echo "  ✓ Start all Docker containers"
    echo "  ✓ Wait for services to be ready"
    echo "  ✓ Show service URLs and status"
    echo ""
    
    echo "Step 3: Download AI Models (optional)"
    echo "Command: make setup-models"
    echo "This will:"
    echo "  ✓ Download DeepSeek-R1:8B for reasoning"
    echo "  ✓ Download Qwen2.5-VL:7B for vision tasks"
    echo "  ✓ Download Llama3.2:3B for general use"
    echo "  ✓ Download embedding models"
    echo ""
    
    echo "Step 4: Validate Deployment"
    echo "Command: ./scripts/validate-deployment.sh"
    echo "This will:"
    echo "  ✓ Test all service endpoints"
    echo "  ✓ Check AI model availability"
    echo "  ✓ Validate database connectivity"
    echo "  ✓ Generate comprehensive health report"
    echo ""
    
    read -p "Would you like to run the local deployment now? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        log "Starting local deployment demonstration..."
        
        # Check if setup has been run
        if [[ ! -f .env ]]; then
            log "Running environment setup..."
            ./scripts/setup-environment.sh
        else
            info ".env file already exists, skipping setup"
        fi
        
        log "Starting services with quick-start script..."
        if [[ -f quick-start.sh ]]; then
            ./quick-start.sh
        else
            warning "quick-start.sh not found, using make command instead"
            make up
        fi
        
        success "Local deployment completed!"
        echo ""
        echo "🎉 Your AI Starter Kit is now running locally!"
        echo ""
        echo "Access your services at:"
        echo "  n8n Workflow Editor:    http://localhost:5678"
        echo "  Crawl4AI Web Scraper:   http://localhost:11235"
        echo "  Qdrant Vector Database: http://localhost:6333"
        echo "  Ollama AI Models:       http://localhost:11434"
        echo ""
    else
        info "Skipping local deployment"
    fi
}

demonstrate_cloud_deployment() {
    header "☁️ Cloud Deployment Demonstration"
    echo ""
    echo "Cloud deployment provides GPU acceleration and production-ready infrastructure."
    echo ""
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        warning "AWS CLI not installed. Cloud deployment requires AWS CLI."
        echo ""
        echo "Install with:"
        echo "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
        echo "  unzip awscliv2.zip && sudo ./aws/install"
        echo "  aws configure"
        echo ""
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        warning "AWS credentials not configured."
        echo ""
        echo "Configure with: aws configure"
        echo "You'll need:"
        echo "  • AWS Access Key ID"
        echo "  • AWS Secret Access Key"
        echo "  • Default region (e.g., us-east-1)"
        echo ""
        return 1
    fi
    
    # Show AWS account info
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    CURRENT_REGION=$(aws configure get region || echo "us-east-1")
    info "AWS Account: $ACCOUNT_ID"
    info "Region: $CURRENT_REGION"
    echo ""
    
    echo "Cloud deployment will:"
    echo ""
    echo "🔧 Infrastructure Setup:"
    echo "  ✓ Create SSH key pair"
    echo "  ✓ Set up security groups"
    echo "  ✓ Create IAM roles and policies"
    echo "  ✓ Configure EFS (Elastic File System)"
    echo ""
    echo "🖥️ Instance Management:"
    echo "  ✓ Launch g4dn.xlarge spot instance (T4 GPU)"
    echo "  ✓ Install Docker, NVIDIA drivers, GPU support"
    echo "  ✓ Configure monitoring and logging"
    echo ""
    echo "🚀 Application Deployment:"
    echo "  ✓ Deploy GPU-optimized Docker Compose stack"
    echo "  ✓ Mount EFS for persistent storage"
    echo "  ✓ Configure all services with optimal settings"
    echo "  ✓ Enable cost optimization and monitoring"
    echo ""
    echo "💰 Expected Costs:"
    echo "  • Spot instance: ~$0.30-0.50/hour ($7-12/day)"
    echo "  • On-demand backup: ~$1.19/hour (~$29/day)"
    echo "  • Storage (EFS): ~$0.30/GB/month"
    echo "  • Estimated monthly: $200-400 (with spot savings)"
    echo ""
    
    warning "IMPORTANT: This will create real AWS resources that incur costs!"
    echo ""
    
    read -p "Do you want to proceed with cloud deployment? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        log "Starting cloud deployment..."
        
        # Run environment setup first
        if [[ ! -f .env ]]; then
            log "Running environment setup..."
            ./scripts/setup-environment.sh
        fi
        
        log "Launching AWS deployment script..."
        echo ""
        echo "This will take 10-15 minutes to complete..."
        echo ""
        
        # Run the deployment script
        ./scripts/aws-deployment.sh
        
        success "Cloud deployment completed!"
    else
        info "Skipping cloud deployment"
        echo ""
        echo "To deploy later, run:"
        echo "  ./scripts/aws-deployment.sh"
    fi
}

show_next_steps() {
    header "🎯 Next Steps"
    echo ""
    echo "After deployment, you can:"
    echo ""
    echo -e "${GREEN}🔬 Explore the Platform:${NC}"
    echo "  • Open n8n and import demo workflows"
    echo "  • Test Crawl4AI web scraping capabilities"
    echo "  • Experiment with AI models in Ollama"
    echo "  • Build vector databases with Qdrant"
    echo ""
    echo -e "${GREEN}📚 Learn More:${NC}"
    echo "  • Read AUTOMATED_DEPLOYMENT_GUIDE.md for detailed instructions"
    echo "  • Check DEPLOYMENT_STRATEGY.md for advanced configurations"
    echo "  • Explore n8n/demo-data/workflows/ for example workflows"
    echo ""
    echo -e "${GREEN}🛠️ Customize:${NC}"
    echo "  • Add your API keys to .env for enhanced features"
    echo "  • Configure custom AI models in Ollama"
    echo "  • Build custom n8n workflows"
    echo "  • Set up monitoring and alerting"
    echo ""
    echo -e "${GREEN}⚙️ Manage:${NC}"
    echo "  • Use 'make health' to check system status"
    echo "  • Use 'make logs' to view service logs"
    echo "  • Use './scripts/validate-deployment.sh' for health checks"
    echo "  • Monitor costs with AWS CloudWatch (cloud deployment)"
    echo ""
}

show_documentation() {
    header "📚 Available Documentation"
    echo ""
    echo "Comprehensive guides are available:"
    echo ""
    echo -e "${CYAN}Primary Guides:${NC}"
    echo "  📖 AUTOMATED_DEPLOYMENT_GUIDE.md  - Step-by-step deployment instructions"
    echo "  🏗️  DEPLOYMENT_STRATEGY.md        - Detailed deployment strategies"
    echo "  🐳 DOCKER_OPTIMIZATION.md        - Docker Compose optimizations"
    echo "  📋 README.md                     - Project overview and quick start"
    echo ""
    echo -e "${CYAN}Specialized Guides:${NC}"
    echo "  🕷️  crawl4ai/CRAWL4AI_INTEGRATION.md - Web scraping with AI"
    echo "  ✅ VALIDATION_GUIDE.md           - Deployment validation"
    echo "  📊 COMPREHENSIVE_GUIDE.md        - Complete feature overview"
    echo ""
    echo -e "${CYAN}Configuration Files:${NC}"
    echo "  🔧 Makefile                      - Automation commands"
    echo "  🌍 .env                          - Environment configuration"
    echo "  🐳 docker-compose*.yml           - Service definitions"
    echo ""
}

main() {
    show_banner
    
    while true; do
        echo ""
        header "What would you like to do?"
        echo ""
        echo "1) Show deployment options and what's included"
        echo "2) Demonstrate local deployment"
        echo "3) Demonstrate cloud deployment (AWS)"
        echo "4) Show available automation scripts"
        echo "5) View documentation overview"
        echo "6) Exit"
        echo ""
        
        read -p "Choose an option (1-6): " choice
        echo ""
        
        case $choice in
            1)
                show_deployment_options
                show_whats_included
                ;;
            2)
                demonstrate_local_deployment
                ;;
            3)
                demonstrate_cloud_deployment
                ;;
            4)
                show_automation_scripts
                ;;
            5)
                show_documentation
                ;;
            6)
                success "Thank you for exploring the AI Starter Kit!"
                echo ""
                echo "To get started:"
                echo "  Local:  ./scripts/setup-environment.sh && ./quick-start.sh"
                echo "  Cloud:  ./scripts/aws-deployment.sh"
                echo ""
                echo "Happy building! 🚀"
                exit 0
                ;;
            *)
                warning "Invalid option. Please choose 1-6."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Show next steps if not running interactively
if [[ "${1:-}" == "--show-next-steps" ]]; then
    show_next_steps
    exit 0
fi

# Run main menu if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 