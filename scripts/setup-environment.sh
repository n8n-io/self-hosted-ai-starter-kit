#!/bin/bash

# =============================================================================
# AI Starter Kit - Environment Setup Script
# =============================================================================
# Prepares the local environment and validates prerequisites for deployment
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_local_environment() {
    log "Setting up local environment for AI Starter Kit..."
    
    # Create .env file if it doesn't exist
    if [[ ! -f .env ]]; then
        log "Creating .env file from template..."
        
        cat > .env << 'EOF'
# =============================================================================
# AI Starter Kit Environment Configuration
# =============================================================================

# Database Configuration
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=change-this-secure-password

# n8n Configuration
N8N_ENCRYPTION_KEY=generate-with-openssl-rand-hex-32
N8N_USER_MANAGEMENT_JWT_SECRET=generate-with-openssl-rand-hex-32
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=*
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

# Webhook Configuration
WEBHOOK_URL=http://localhost:5678

# AI API Keys (Optional - for enhanced features)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
MISTRAL_API_KEY=
GEMINI_API_TOKEN=

# AWS Configuration (for cloud deployment)
AWS_DEFAULT_REGION=us-east-1
INSTANCE_TYPE=g4dn.xlarge
MAX_SPOT_PRICE=0.75

# EFS Configuration (will be populated during deployment)
EFS_DNS=

# Instance Information (will be populated during deployment)
INSTANCE_ID=
GPU_TYPE=nvidia-t4
DEPLOYMENT_MODE=local

# Ollama Configuration
OLLAMA_HOST=ollama
OLLAMA_PORT=11434
OLLAMA_BASE_URL=http://ollama:11434

# Performance Optimization
CRAWL4AI_MAX_CONCURRENT_SESSIONS=4
CRAWL4AI_BROWSER_POOL_SIZE=2
OLLAMA_MAX_LOADED_MODELS=3
OLLAMA_GPU_MEMORY_FRACTION=0.90
EOF

        success "Created .env file - please update with your configuration"
    else
        info ".env file already exists"
    fi
    
    # Generate secure passwords and keys if needed
    if grep -q "change-this-secure-password" .env; then
        log "Generating secure passwords and encryption keys..."
        
        POSTGRES_PASSWORD=$(openssl rand -hex 16)
        N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
        N8N_JWT_SECRET=$(openssl rand -hex 32)
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s/change-this-secure-password/$POSTGRES_PASSWORD/g" .env
            sed -i '' "s/generate-with-openssl-rand-hex-32/$N8N_ENCRYPTION_KEY/1" .env
            sed -i '' "s/generate-with-openssl-rand-hex-32/$N8N_JWT_SECRET/2" .env
        else
            # Linux
            sed -i "s/change-this-secure-password/$POSTGRES_PASSWORD/g" .env
            sed -i "s/generate-with-openssl-rand-hex-32/$N8N_ENCRYPTION_KEY/1" .env
            sed -i "s/generate-with-openssl-rand-hex-32/$N8N_JWT_SECRET/2" .env
        fi
        
        success "Generated secure passwords and encryption keys"
    fi
    
    # Create necessary directories
    log "Creating directory structure..."
    mkdir -p {n8n/{backup,demo-data/{credentials,workflows}},ollama/models,crawl4ai/{configs,scripts},scripts,shared}
    
    success "Directory structure created"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check essential tools
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_tools+=("docker-compose")
    fi
    
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    # Check for cloud deployment tools
    if ! command -v aws &> /dev/null; then
        warning "AWS CLI not found - required for cloud deployment"
        info "Install with: curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install"
    fi
    
    if ! command -v jq &> /dev/null; then
        warning "jq not found - will be installed automatically during deployment"
    fi
    
    # Report missing tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools and run this script again."
        echo ""
        echo "Installation guides:"
        echo "  Docker: https://docs.docker.com/get-docker/"
        echo "  Docker Compose: https://docs.docker.com/compose/install/"
        echo "  Git: https://git-scm.com/downloads"
        echo "  AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    success "All prerequisites are installed"
}

validate_docker() {
    log "Validating Docker configuration..."
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check Docker Compose version
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version --short)
        info "Using Docker Compose v2: $COMPOSE_VERSION"
    elif docker-compose --version &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)
        info "Using Docker Compose v1: $COMPOSE_VERSION"
        warning "Consider upgrading to Docker Compose v2 for better performance"
    fi
    
    # Test Docker functionality
    if docker run --rm hello-world &> /dev/null; then
        success "Docker is working correctly"
    else
        error "Docker test failed. Please check your Docker installation."
        exit 1
    fi
}

validate_aws_credentials() {
    if command -v aws &> /dev/null; then
        log "Validating AWS credentials..."
        
        if aws sts get-caller-identity &> /dev/null; then
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
            success "AWS credentials are valid"
            info "Account ID: $ACCOUNT_ID"
            info "User/Role: $USER_ARN"
        else
            warning "AWS credentials not configured or invalid"
            info "Run 'aws configure' to set up your credentials for cloud deployment"
        fi
    else
        warning "AWS CLI not installed - skipping credential validation"
    fi
}

check_system_resources() {
    log "Checking system resources..."
    
    # Check available memory
    if command -v free &> /dev/null; then
        TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
        if [[ $TOTAL_MEM -lt 8 ]]; then
            warning "System has ${TOTAL_MEM}GB RAM. Recommended minimum: 8GB for local development"
        else
            success "System memory: ${TOTAL_MEM}GB"
        fi
    fi
    
    # Check available disk space
    AVAILABLE_SPACE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $AVAILABLE_SPACE -lt 20 ]]; then
        warning "Available disk space: ${AVAILABLE_SPACE}GB. Recommended minimum: 20GB"
    else
        success "Available disk space: ${AVAILABLE_SPACE}GB"
    fi
    
    # Check for GPU (optional)
    if command -v nvidia-smi &> /dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits)
        success "GPU detected: $GPU_INFO"
        info "Local GPU will be used for AI model acceleration"
    else
        info "No GPU detected - will use CPU-only mode for local development"
        info "For GPU acceleration, deploy to cloud with g4dn.xlarge instances"
    fi
}

create_quick_start_script() {
    log "Creating quick start script..."
    
    cat > quick-start.sh << 'EOF'
#!/bin/bash

# AI Starter Kit Quick Start Script

set -euo pipefail

echo "🚀 AI Starter Kit Quick Start"
echo "=============================="
echo ""

# Check if .env exists
if [[ ! -f .env ]]; then
    echo "❌ .env file not found. Please run setup-environment.sh first."
    exit 1
fi

echo "Starting local development environment..."

# Start services
if docker compose version &> /dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi

echo ""
echo "⏳ Waiting for services to start..."
sleep 30

# Check service health
echo ""
echo "🔍 Checking service health..."

check_service() {
    local url="$1"
    local name="$2"
    
    if curl -f -s "$url" > /dev/null 2>&1; then
        echo "✅ $name is healthy"
    else
        echo "⚠️  $name is starting up (this is normal)"
    fi
}

check_service "http://localhost:5678/healthz" "n8n"
check_service "http://localhost:11434/api/tags" "Ollama"
check_service "http://localhost:6333/healthz" "Qdrant"
check_service "http://localhost:5432" "PostgreSQL"

echo ""
echo "🎉 AI Starter Kit is starting up!"
echo ""
echo "📋 Service URLs:"
echo "   n8n Workflow Editor:    http://localhost:5678"
echo "   Ollama AI Models:       http://localhost:11434"
echo "   Qdrant Vector DB:       http://localhost:6333"
echo "   PostgreSQL Database:    localhost:5432"
echo ""
echo "💡 Next steps:"
echo "   1. Wait 2-3 minutes for all services to fully start"
echo "   2. Open n8n at http://localhost:5678"
echo "   3. Download AI models: make setup-models"
echo "   4. Check logs: docker compose logs -f"
echo ""
echo "☁️  For cloud deployment:"
echo "   ./scripts/aws-deployment.sh"
echo ""
EOF

    chmod +x quick-start.sh
    success "Created quick-start.sh script"
}

create_local_makefile_extension() {
    log "Creating Makefile extensions..."
    
    cat > Makefile.local << 'EOF'
# Local development extensions for AI Starter Kit Makefile

.PHONY: setup dev-quick cloud-deploy status

# Setup local environment
setup:
	@echo "🔧 Setting up AI Starter Kit environment..."
	@./scripts/setup-environment.sh
	@echo "✅ Environment setup completed!"

# Quick development start
dev-quick:
	@echo "🚀 Quick start for development..."
	@./quick-start.sh

# Deploy to AWS cloud
cloud-deploy:
	@echo "☁️  Deploying to AWS cloud..."
	@./scripts/aws-deployment.sh

# Show comprehensive status
status:
	@echo "📊 AI Starter Kit Status"
	@echo "======================="
	@echo ""
	@echo "🐳 Docker Services:"
	@if docker compose ps 2>/dev/null; then \
		docker compose ps; \
	elif docker-compose ps 2>/dev/null; then \
		docker-compose ps; \
	else \
		echo "No services running"; \
	fi
	@echo ""
	@echo "💾 System Resources:"
	@echo "Memory: $$(free -h | awk '/^Mem:/{print $$3 "/" $$2}')"
	@echo "Disk: $$(df -h . | awk 'NR==2 {print $$3 "/" $$2 " (" $$5 " used)"}')"
	@if command -v nvidia-smi >/dev/null 2>&1; then \
		echo "GPU: $$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | awk '{print $$1"% GPU, "$$2"/"$$3" MB VRAM"}')"; \
	fi
	@echo ""
EOF
    
    # Add include to main Makefile if not already present
    if [[ -f Makefile ]] && ! grep -q "include Makefile.local" Makefile; then
        echo "" >> Makefile
        echo "# Include local development extensions" >> Makefile
        echo "-include Makefile.local" >> Makefile
        success "Added local extensions to Makefile"
    fi
}

display_summary() {
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}  ENVIRONMENT SETUP COMPLETE!   ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${BLUE}📁 Files Created:${NC}"
    echo -e "   .env                 - Environment configuration"
    echo -e "   quick-start.sh       - Quick development start"
    echo -e "   Makefile.local       - Local development commands"
    echo ""
    echo -e "${BLUE}🚀 Quick Start Options:${NC}"
    echo ""
    echo -e "${GREEN}Local Development:${NC}"
    echo -e "   ./quick-start.sh     - Start local development environment"
    echo -e "   make dev-quick       - Alternative quick start"
    echo -e "   make up              - Standard docker compose start"
    echo ""
    echo -e "${GREEN}Cloud Deployment:${NC}"
    echo -e "   ./scripts/aws-deployment.sh  - Deploy to AWS with GPU optimization"
    echo -e "   make cloud-deploy             - Alternative cloud deployment"
    echo ""
    echo -e "${BLUE}📚 Additional Commands:${NC}"
    echo -e "   make help            - Show all available commands"
    echo -e "   make setup-models    - Download AI models after startup"
    echo -e "   make health          - Check service health"
    echo -e "   make status          - Show comprehensive status"
    echo ""
    echo -e "${YELLOW}💡 Next Steps:${NC}"
    echo -e "   1. Review and update .env file with your configuration"
    echo -e "   2. Choose your deployment method (local or cloud)"
    echo -e "   3. Run the appropriate start command"
    echo ""
    echo -e "${YELLOW}🔑 API Keys (Optional):${NC}"
    echo -e "   Add API keys to .env for enhanced AI features:"
    echo -e "   - OpenAI, Anthropic, DeepSeek, Groq, etc."
    echo ""
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo -e "${CYAN}"
    cat << 'EOF'
 _____ _____   _____ _             _            _   _ _ _   
|  _  |     | |   __| |_ ___ ___ _| |_ ___ ___  | | | |_| |_ 
|     |-   -| |__   |  _| .'|  _|  _| -_|  _|  | |_| | |  _|
|__|__|_____| |_____|_| |__,|_| |_| |___|_|    |___|_|_|_|  
                                                           
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Environment Setup${NC}"
    echo ""
    
    check_prerequisites
    validate_docker
    validate_aws_credentials
    check_system_resources
    setup_local_environment
    create_quick_start_script
    create_local_makefile_extension
    
    display_summary
    
    success "Environment setup completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "AI Starter Kit Environment Setup"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "This script sets up the local environment for the AI Starter Kit."
            echo "It creates configuration files, validates prerequisites, and"
            echo "prepares the system for both local and cloud deployment."
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@" 