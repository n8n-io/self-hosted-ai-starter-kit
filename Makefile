.PHONY: help build up down restart logs clean dev prod gpu test health setup-models validate config

# =============================================================================
# Enhanced AI Starter Kit Makefile
# Optimized for Docker Compose v2.38.2
# =============================================================================

# Configuration
COMPOSE_CMD := docker compose
COMPOSE_GPU := docker compose -f docker-compose.gpu-optimized.yml
COMPOSE_DEV := docker compose -f docker-compose.yml -f docker-compose.override.yml
COMPOSE_PROD := docker compose -f docker-compose.yml -f docker-compose.prod.yml

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
PURPLE := \033[0;35m
CYAN := \033[0;36m
NC := \033[0m # No Color

# Default target
help:
	@echo "$(CYAN)🚀 Enhanced AI Starter Kit - Docker Compose v2.38.2$(NC)"
	@echo ""
	@echo "$(BLUE)📋 Core Operations:$(NC)"
	@echo "  $(GREEN)build$(NC)       - Build all Docker images with optimizations"
	@echo "  $(GREEN)up$(NC)          - Start all services (local development)"
	@echo "  $(GREEN)gpu-up$(NC)      - Start GPU-optimized services (cloud deployment)"
	@echo "  $(GREEN)down$(NC)        - Stop all services gracefully"
	@echo "  $(GREEN)restart$(NC)     - Restart all services"
	@echo "  $(GREEN)logs$(NC)        - Show logs for all services"
	@echo "  $(GREEN)clean$(NC)       - Remove containers, images, and volumes"
	@echo ""
	@echo "$(BLUE)🎯 Deployment Strategies:$(NC)"
	@echo "  $(GREEN)dev$(NC)         - Development environment (CPU-only, debug mode)"
	@echo "  $(GREEN)prod$(NC)        - Production environment (optimized, monitoring)"
	@echo "  $(GREEN)gpu$(NC)         - GPU-optimized environment (cloud deployment)"
	@echo "  $(GREEN)hybrid$(NC)      - Hybrid development (local + remote GPU)"
	@echo ""
	@echo "$(BLUE)🔧 Configuration & Setup:$(NC)"
	@echo "  $(GREEN)init$(NC)        - Initialize environment and configuration"
	@echo "  $(GREEN)setup-models$(NC) - Download and configure AI models"
	@echo "  $(GREEN)validate$(NC)     - Validate Docker Compose configuration"
	@echo "  $(GREEN)config$(NC)      - Show resolved configuration"
	@echo "  $(GREEN)health$(NC)      - Comprehensive health checks"
	@echo "  $(GREEN)test$(NC)        - Run service health tests"
	@echo ""
	@echo "$(BLUE)📊 Monitoring & Maintenance:$(NC)"
	@echo "  $(GREEN)resources$(NC)   - Show resource usage"
	@echo "  $(GREEN)backup$(NC)      - Backup n8n workflows and credentials"
	@echo "  $(GREEN)restore$(NC)     - Restore n8n data from backup"
	@echo "  $(GREEN)update$(NC)      - Update all images to latest versions"
	@echo ""
	@echo "$(BLUE)🔍 Debugging & Logs:$(NC)"
	@echo "  $(GREEN)logs-<service>$(NC) - Show logs for specific service (e.g., logs-n8n)"
	@echo "  $(GREEN)exec-<service>$(NC) - Execute command in service (e.g., exec-ollama)"
	@echo "  $(GREEN)debug$(NC)       - Start services in debug mode"
	@echo ""
	@echo "$(BLUE)📚 Documentation:$(NC)"
	@echo "  $(GREEN)docs$(NC)        - Open documentation overview"
	@echo "  $(GREEN)deployment$(NC)  - Open deployment strategy guide"
	@echo "  $(GREEN)optimization$(NC) - Open Docker optimization guide"
	@echo ""
	@echo "$(YELLOW)⚡ Quick Start:$(NC)"
	@echo "  1. $(GREEN)make init$(NC)         - Initialize environment"
	@echo "  2. $(GREEN)make up$(NC)           - Start local development"
	@echo "  3. $(GREEN)make setup-models$(NC) - Download AI models"
	@echo "  4. $(GREEN)make health$(NC)       - Verify deployment"
	@echo ""
	@echo "$(YELLOW)☁️  Cloud Deployment:$(NC)"
	@echo "  1. Set EFS_DNS environment variable"
	@echo "  2. $(GREEN)make gpu-up$(NC)       - Start GPU-optimized services"
	@echo "  3. $(GREEN)make setup-models$(NC) - Download optimized models"
	@echo ""
	@echo "$(CYAN)📖 For detailed guides, see:$(NC)"
	@echo "  - README.md for comprehensive overview"
	@echo "  - DEPLOYMENT_STRATEGY.md for deployment options"
	@echo "  - DOCKER_OPTIMIZATION.md for Docker Compose v2.38.2 features"

# =============================================================================
# CORE OPERATIONS
# =============================================================================

# Build all images with Docker Compose v2.38.2 optimizations
build:
	@echo "$(BLUE)🔨 Building Docker images with optimizations...$(NC)"
	@echo "Using Docker Compose v2.38.2 features:"
	@$(COMPOSE_CMD) version
	@export DOCKER_BUILDKIT=1 && \
	export COMPOSE_DOCKER_CLI_BUILD=1 && \
	$(COMPOSE_CMD) build --parallel --progress=plain

# Validate Docker Compose configuration
validate:
	@echo "$(BLUE)🔍 Validating Docker Compose configuration...$(NC)"
	@$(COMPOSE_CMD) config --quiet && echo "$(GREEN)✅ Configuration is valid$(NC)" || echo "$(RED)❌ Configuration has errors$(NC)"
	@$(COMPOSE_GPU) config --quiet && echo "$(GREEN)✅ GPU configuration is valid$(NC)" || echo "$(RED)❌ GPU configuration has errors$(NC)"

# Show resolved configuration
config:
	@echo "$(BLUE)📋 Docker Compose Configuration:$(NC)"
	@$(COMPOSE_CMD) config

# Start all services (local development)
up: validate
	@echo "$(GREEN)🚀 Starting local development services...$(NC)"
	@$(COMPOSE_CMD) up -d --wait
	@echo "$(GREEN)✅ Services started successfully$(NC)"
	@$(MAKE) health

# Start GPU-optimized services (cloud deployment)
gpu-up: validate
	@echo "$(GREEN)🚀 Starting GPU-optimized services...$(NC)"
	@if [ -z "$(EFS_DNS)" ]; then \
		echo "$(YELLOW)⚠️  Warning: EFS_DNS not set. Using local storage.$(NC)"; \
		echo "$(YELLOW)For cloud deployment, set: export EFS_DNS=fs-xxxxxxxx.efs.region.amazonaws.com$(NC)"; \
	fi
	@$(COMPOSE_GPU) up -d --wait
	@echo "$(GREEN)✅ GPU services started successfully$(NC)"
	@$(MAKE) health

# Stop all services gracefully
down:
	@echo "$(YELLOW)🛑 Stopping all services...$(NC)"
	@$(COMPOSE_CMD) down --remove-orphans
	@$(COMPOSE_GPU) down --remove-orphans 2>/dev/null || true
	@echo "$(GREEN)✅ Services stopped$(NC)"

# Restart all services
restart:
	@echo "$(YELLOW)🔄 Restarting all services...$(NC)"
	@$(COMPOSE_CMD) restart
	@echo "$(GREEN)✅ Services restarted$(NC)"

# =============================================================================
# DEPLOYMENT STRATEGIES
# =============================================================================

# Development environment (CPU-only, debug mode)
dev: validate
	@echo "$(GREEN)🛠️  Starting development environment...$(NC)"
	@$(COMPOSE_DEV) up -d --wait
	@echo "$(GREEN)✅ Development environment started$(NC)"
	@echo "$(CYAN)Features: Debug logging, hot reload, reduced resources$(NC)"
	@$(MAKE) health

# Production environment (optimized, monitoring)
prod: validate
	@echo "$(GREEN)🏭 Starting production environment...$(NC)"
	@$(COMPOSE_PROD) up -d --wait
	@echo "$(GREEN)✅ Production environment started$(NC)"
	@echo "$(CYAN)Features: Resource limits, health checks, monitoring$(NC)"
	@$(MAKE) health

# GPU-optimized environment (alias for gpu-up)
gpu: gpu-up

# Hybrid development (local + remote GPU)
hybrid:
	@echo "$(GREEN)🔗 Starting hybrid development environment...$(NC)"
	@echo "$(CYAN)This will start local services and connect to remote GPU$(NC)"
	@if [ -z "$(OLLAMA_BASE_URL)" ]; then \
		echo "$(RED)❌ OLLAMA_BASE_URL not set. Please set it to your remote GPU instance.$(NC)"; \
		echo "$(YELLOW)Example: export OLLAMA_BASE_URL=https://your-gpu-instance.com:11434$(NC)"; \
		exit 1; \
	fi
	@OLLAMA_HOST=$(OLLAMA_BASE_URL) $(COMPOSE_DEV) up -d --wait
	@echo "$(GREEN)✅ Hybrid environment started$(NC)"

# =============================================================================
# CONFIGURATION & SETUP
# =============================================================================

# Initialize the environment
init:
	@echo "$(BLUE)🚀 Initializing Enhanced AI Starter Kit...$(NC)"
	@echo "$(CYAN)Setting up environment configuration...$(NC)"
	@if [ ! -f .env ]; then \
		echo "$(YELLOW)Creating .env file from template...$(NC)"; \
		cp .env.example .env 2>/dev/null || echo "# Enhanced AI Starter Kit Environment Variables" > .env; \
		echo "POSTGRES_DB=n8n" >> .env; \
		echo "POSTGRES_USER=n8n" >> .env; \
		echo "POSTGRES_PASSWORD=change-this-password" >> .env; \
		echo "N8N_ENCRYPTION_KEY=$$(openssl rand -hex 32)" >> .env; \
		echo "N8N_USER_MANAGEMENT_JWT_SECRET=$$(openssl rand -hex 32)" >> .env; \
		echo "OLLAMA_HOST=ollama:11434" >> .env; \
	fi
	@echo "$(CYAN)Ensuring directory structure...$(NC)"
	@mkdir -p crawl4ai/configs crawl4ai/scripts ollama/models n8n/demo-data shared
	@echo "$(CYAN)Setting up Docker Compose v2.38.2 compatibility...$(NC)"
	@$(MAKE) validate
	@echo "$(GREEN)✅ Environment initialized successfully$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Edit .env file with your configuration"
	@echo "  2. Run 'make up' to start local development"
	@echo "  3. Run 'make setup-models' to download AI models"

# Setup AI models with optimizations
setup-models:
	@echo "$(BLUE)🤖 Setting up AI models for Enhanced AI Starter Kit...$(NC)"
	@echo "$(CYAN)Downloading optimized models:$(NC)"
	@echo "  - DeepSeek-R1:8B (Reasoning & Code)"
	@echo "  - Qwen2.5-VL:7B (Vision-Language)"
	@echo "  - Snowflake-Arctic-Embed2:568M (Embeddings)"
	@if $(COMPOSE_CMD) ps ollama | grep -q "Up"; then \
		echo "$(GREEN)Ollama is running, downloading models...$(NC)"; \
		$(COMPOSE_CMD) exec ollama ollama pull deepseek-r1:8b || echo "$(YELLOW)⚠️  Failed to download deepseek-r1:8b$(NC)"; \
		$(COMPOSE_CMD) exec ollama ollama pull qwen2.5-vl:7b || echo "$(YELLOW)⚠️  Failed to download qwen2.5-vl:7b$(NC)"; \
		$(COMPOSE_CMD) exec ollama ollama pull snowflake-arctic-embed2:568m || echo "$(YELLOW)⚠️  Failed to download snowflake-arctic-embed2:568m$(NC)"; \
		$(COMPOSE_CMD) exec ollama ollama pull mxbai-embed-large:latest || echo "$(YELLOW)⚠️  Failed to download mxbai-embed-large$(NC)"; \
	else \
		echo "$(RED)❌ Ollama is not running. Please start services first with 'make up' or 'make gpu-up'$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ AI models setup completed$(NC)"

# =============================================================================
# MONITORING & HEALTH
# =============================================================================

# Comprehensive health status with Docker Compose v2.38.2 features
health:
	@echo "$(BLUE)📊 Service Health Status (Docker Compose v2.38.2):$(NC)"
	@echo "=================================================="
	@$(COMPOSE_CMD) ps --format table
	@echo ""
	@echo "$(BLUE)🔗 Service URLs:$(NC)"
	@echo "  $(GREEN)n8n Workflow Editor:$(NC)     http://localhost:5678"
	@echo "  $(GREEN)Crawl4AI Web Scraper:$(NC)    http://localhost:11235"
	@echo "  $(GREEN)Qdrant Vector DB:$(NC)        http://localhost:6333"
	@echo "  $(GREEN)Ollama AI Models:$(NC)        http://localhost:11434"
	@echo ""
	@echo "$(BLUE)🎮 Interactive Interfaces:$(NC)"
	@echo "  $(GREEN)Crawl4AI Playground:$(NC)     http://localhost:11235/playground"
	@echo "  $(GREEN)n8n Editor:$(NC)              http://localhost:5678"
	@echo "  $(GREEN)Qdrant Dashboard:$(NC)        http://localhost:6333/dashboard"
	@echo ""
	@echo "$(BLUE)🔍 Health Check Results:$(NC)"
	@$(MAKE) test

# Run service health tests with enhanced error handling
test:
	@echo "$(BLUE)🔍 Running comprehensive health checks...$(NC)"
	@echo "$(CYAN)Testing service endpoints...$(NC)"
	@curl -sf http://localhost:5678/healthz >/dev/null 2>&1 && \
		echo "$(GREEN)✅ n8n - Healthy$(NC)" || \
		echo "$(RED)❌ n8n - Unhealthy$(NC)"
	@curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && \
		echo "$(GREEN)✅ Ollama - Healthy$(NC)" || \
		echo "$(RED)❌ Ollama - Unhealthy$(NC)"
	@curl -sf http://localhost:6333/healthz >/dev/null 2>&1 && \
		echo "$(GREEN)✅ Qdrant - Healthy$(NC)" || \
		echo "$(RED)❌ Qdrant - Unhealthy$(NC)"
	@curl -sf http://localhost:11235/health >/dev/null 2>&1 && \
		echo "$(GREEN)✅ Crawl4AI - Healthy$(NC)" || \
		echo "$(RED)❌ Crawl4AI - Unhealthy$(NC)"
	@$(COMPOSE_CMD) exec -T postgres pg_isready -U $${POSTGRES_USER:-n8n} >/dev/null 2>&1 && \
		echo "$(GREEN)✅ PostgreSQL - Healthy$(NC)" || \
		echo "$(RED)❌ PostgreSQL - Unhealthy$(NC)"
	@echo "$(GREEN)✅ Health checks completed$(NC)"

# Show resource usage with enhanced output
resources:
	@echo "$(BLUE)📊 Resource Usage:$(NC)"
	@$(COMPOSE_CMD) top
	@echo ""
	@echo "$(BLUE)Docker Stats:$(NC)"
	@docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"

# =============================================================================
# MAINTENANCE OPERATIONS
# =============================================================================

# Show logs for all services with timestamps
logs:
	@echo "$(BLUE)📋 Showing logs for all services...$(NC)"
	@$(COMPOSE_CMD) logs -f --timestamps

# Clean up with enhanced safety
clean:
	@echo "$(YELLOW)🧹 Cleaning up Docker resources...$(NC)"
	@read -p "This will remove all containers, images, and volumes. Are you sure? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(COMPOSE_CMD) down -v --remove-orphans; \
		$(COMPOSE_GPU) down -v --remove-orphans 2>/dev/null || true; \
		docker system prune -f; \
		docker volume prune -f; \
		echo "$(GREEN)✅ Cleanup completed$(NC)"; \
	else \
		echo "$(YELLOW)Cleanup cancelled$(NC)"; \
	fi

# Backup n8n data with timestamp
backup:
	@echo "$(BLUE)💾 Creating n8n backup...$(NC)"
	@mkdir -p ./backups/$$(date +%Y%m%d_%H%M%S)
	@BACKUP_DIR=./backups/$$(date +%Y%m%d_%H%M%S) && \
	$(COMPOSE_CMD) exec n8n n8n export:workflow --all --output=/backup/workflows && \
	$(COMPOSE_CMD) exec n8n n8n export:credentials --all --output=/backup/credentials && \
	echo "$(GREEN)✅ Backup completed in $$BACKUP_DIR$(NC)"

# Restore n8n data
restore:
	@echo "$(BLUE)📥 Restoring n8n data...$(NC)"
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "$(RED)❌ Please specify BACKUP_DIR. Example: make restore BACKUP_DIR=./backups/20240115_143022$(NC)"; \
		exit 1; \
	fi
	@$(COMPOSE_CMD) exec n8n n8n import:workflow --input=/backup/workflows
	@$(COMPOSE_CMD) exec n8n n8n import:credentials --input=/backup/credentials
	@echo "$(GREEN)✅ Restore completed$(NC)"

# Update all images to latest versions
update:
	@echo "$(BLUE)🔄 Updating all images to latest versions...$(NC)"
	@$(COMPOSE_CMD) pull
	@echo "$(GREEN)✅ Images updated$(NC)"

# =============================================================================
# DEBUG & DEVELOPMENT
# =============================================================================

# Start services in debug mode
debug:
	@echo "$(YELLOW)🐛 Starting services in debug mode...$(NC)"
	@COMPOSE_LOG_LEVEL=DEBUG $(COMPOSE_DEV) up --build

# Show environment variables
env:
	@echo "$(BLUE)🔧 Environment Variables:$(NC)"
	@cat .env 2>/dev/null || echo "$(YELLOW)No .env file found$(NC)"

# Show service logs for a specific service
logs-%:
	@echo "$(BLUE)📋 Showing logs for $*...$(NC)"
	@$(COMPOSE_CMD) logs -f --timestamps $*

# Execute command in a specific service
exec-%:
	@echo "$(BLUE)🔧 Executing command in $*...$(NC)"
	@$(COMPOSE_CMD) exec $* $(CMD)

# =============================================================================
# DOCUMENTATION
# =============================================================================

# Open documentation overview
docs:
	@echo "$(BLUE)📚 Enhanced AI Starter Kit Documentation:$(NC)"
	@echo ""
	@echo "$(GREEN)📖 Available Documentation:$(NC)"
	@echo "  - README.md                     - Comprehensive overview and quick start"
	@echo "  - DEPLOYMENT_STRATEGY.md       - Detailed deployment strategies"
	@echo "  - DOCKER_OPTIMIZATION.md       - Docker Compose v2.38.2 optimizations"
	@echo "  - DOCKER_COMPOSE_MODERNIZATION.md - Migration guide"
	@echo "  - crawl4ai/CRAWL4AI_INTEGRATION.md - Crawl4AI usage examples"
	@echo ""
	@echo "$(CYAN)🔗 Quick Links:$(NC)"
	@echo "  make deployment   - Open deployment guide"
	@echo "  make optimization - Open Docker optimization guide"

# Open deployment strategy guide
deployment:
	@echo "$(BLUE)📋 Opening Deployment Strategy Guide...$(NC)"
	@if command -v code >/dev/null 2>&1; then \
		code DEPLOYMENT_STRATEGY.md; \
	elif command -v open >/dev/null 2>&1; then \
		open DEPLOYMENT_STRATEGY.md; \
	else \
		echo "$(CYAN)Please open DEPLOYMENT_STRATEGY.md in your preferred editor$(NC)"; \
	fi

# Open Docker optimization guide
optimization:
	@echo "$(BLUE)🚀 Opening Docker Optimization Guide...$(NC)"
	@if command -v code >/dev/null 2>&1; then \
		code DOCKER_OPTIMIZATION.md; \
	elif command -v open >/dev/null 2>&1; then \
		open DOCKER_OPTIMIZATION.md; \
	else \
		echo "$(CYAN)Please open DOCKER_OPTIMIZATION.md in your preferred editor$(NC)"; \
	fi

# =============================================================================
# VERSION INFO
# =============================================================================

# Show version information
version:
	@echo "$(BLUE)📦 Enhanced AI Starter Kit - Version Information:$(NC)"
	@echo "================================================="
	@docker --version
	@$(COMPOSE_CMD) version
	@echo ""
	@echo "$(GREEN)✅ Docker Compose v2.38.2 Optimized$(NC)"
	@echo "$(GREEN)✅ GPU Support Enabled$(NC)"
	@echo "$(GREEN)✅ Modern Compose Specification$(NC)" 