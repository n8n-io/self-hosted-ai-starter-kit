.PHONY: help build up down restart logs clean dev prod test health

# Default target
help:
	@echo "Available commands:"
	@echo "  build    - Build all Docker images"
	@echo "  up       - Start all services"
	@echo "  down     - Stop all services"
	@echo "  restart  - Restart all services"
	@echo "  logs     - Show logs for all services"
	@echo "  clean    - Remove all containers, images, and volumes"
	@echo "  dev      - Start development environment"
	@echo "  prod     - Start production environment"
	@echo "  test     - Run health checks"
	@echo "  health   - Show service health status"

# Build all images with BuildKit
build:
	@echo "Building Docker images with BuildKit..."
	export DOCKER_BUILDKIT=1 && \
	export COMPOSE_DOCKER_CLI_BUILD=1 && \
	docker compose build --parallel --no-cache

# Start all services
up:
	@echo "Starting all services..."
	docker compose up -d

# Stop all services
down:
	@echo "Stopping all services..."
	docker compose down

# Restart all services
restart:
	@echo "Restarting all services..."
	docker compose restart

# Show logs for all services
logs:
	@echo "Showing logs for all services..."
	docker compose logs -f

# Clean up everything
clean:
	@echo "Cleaning up Docker resources..."
	docker compose down -v --remove-orphans
	docker system prune -f
	docker volume prune -f

# Development environment
dev:
	@echo "Starting development environment..."
	docker compose -f docker-compose.yml -f docker-compose.override.yml up -d

# Production environment
prod:
	@echo "Starting production environment..."
	docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Run health checks
test:
	@echo "Running health checks..."
	@echo "Checking n8n..."
	@curl -f http://localhost:5678/healthz || echo "n8n health check failed"
	@echo "Checking Ollama..."
	@curl -f http://localhost:11434/api/tags || echo "Ollama health check failed"
	@echo "Checking Qdrant..."
	@curl -f http://localhost:6333/healthz || echo "Qdrant health check failed"
	@echo "Checking PostgreSQL..."
	@docker compose exec -T postgres pg_isready -U postgres || echo "PostgreSQL health check failed"

# Show service health status
health:
	@echo "Service health status:"
	docker compose ps

# Show resource usage
resources:
	@echo "Resource usage:"
	docker stats --no-stream

# Backup n8n data
backup:
	@echo "Creating n8n backup..."
	mkdir -p ./backups
	docker compose exec n8n n8n export:workflow --all --output=/backup/workflows
	docker compose exec n8n n8n export:credentials --all --output=/backup/credentials
	@echo "Backup completed in ./backups/"

# Restore n8n data
restore:
	@echo "Restoring n8n data..."
	docker compose exec n8n n8n import:workflow --input=/backup/workflows
	docker compose exec n8n n8n import:credentials --input=/backup/credentials
	@echo "Restore completed"

# Update all images to latest
update:
	@echo "Updating all images to latest..."
	docker compose pull
	docker compose build --no-cache

# Show environment variables
env:
	@echo "Environment variables:"
	@cat .env 2>/dev/null || echo "No .env file found"

# Initialize the environment
init:
	@echo "Initializing environment..."
	@if [ ! -f .env ]; then \
		echo "Creating .env file from template..."; \
		cp .env.example .env 2>/dev/null || echo "# Add your environment variables here" > .env; \
	fi
	@echo "Environment initialized. Please edit .env file with your configuration."

# Show service logs for a specific service
logs-%:
	@echo "Showing logs for $*..."
	docker compose logs -f $*

# Execute command in a specific service
exec-%:
	@echo "Executing command in $*..."
	docker compose exec $* $(CMD)

# Scale a specific service
scale-%:
	@echo "Scaling $* to $(REPLICAS) instances..."
	docker compose up -d --scale $*=$(REPLICAS) 