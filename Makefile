# AI Starter Kit Makefile
# Build automation and development tools

.PHONY: help setup clean test lint deploy destroy validate docs

# Default target
help: ## Show this help message
	@echo "AI Starter Kit - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# SETUP AND DEPENDENCIES
# =============================================================================

setup: ## Set up development environment
	@echo "Setting up development environment..."
	@chmod +x scripts/*.sh
	@chmod +x tools/*.sh 2>/dev/null || true
	@if [ ! -f .env ]; then cp .env.example .env 2>/dev/null || echo "# Local environment variables" > .env; fi
	@echo "✅ Development environment setup complete"

install-deps: ## Install required dependencies
	@echo "Installing dependencies..."
	@./tools/install-deps.sh
	@echo "✅ Dependencies installed"

check-deps: ## Check if all dependencies are available
	@echo "Checking dependencies..."
	@./scripts/security-validation.sh
	@echo "✅ Dependencies check complete"

# =============================================================================
# DEVELOPMENT
# =============================================================================

dev-setup: setup install-deps ## Full development setup
	@echo "🚀 Development environment ready!"

validate: ## Validate all configurations
	@echo "Validating configurations..."
	@./tools/validate-config.sh
	@echo "✅ Configuration validation complete"

lint: ## Run linting on all code
	@echo "Running linters..."
	@./tools/lint.sh
	@echo "✅ Linting complete"

format: ## Format all code
	@echo "Formatting code..."
	@./tools/format.sh
	@echo "✅ Code formatting complete"

# =============================================================================
# TESTING
# =============================================================================

test: ## Run all tests
	@echo "Running tests..."
	@./tools/test-runner.sh
	@echo "✅ Tests complete"

test-unit: ## Run unit tests only
	@echo "Running unit tests..."
	@python -m pytest tests/unit/ -v

test-integration: ## Run integration tests only
	@echo "Running integration tests..."
	@python -m pytest tests/integration/ -v

test-security: ## Run security tests
	@echo "Running security tests..."
	@./tools/security-scan.sh

# =============================================================================
# DEPLOYMENT
# =============================================================================

plan: ## Show deployment plan
	@echo "Showing deployment plan..."
	@./scripts/aws-deployment-unified.sh --validate-only $(STACK_NAME)

deploy: validate ## Deploy infrastructure (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required. Use: make deploy STACK_NAME=my-stack"; exit 1; fi
	@echo "Deploying stack: $(STACK_NAME)"
	@./scripts/aws-deployment-unified.sh $(STACK_NAME)

deploy-spot: validate ## Deploy with spot instances (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./scripts/aws-deployment-unified.sh -t spot $(STACK_NAME)

deploy-ondemand: validate ## Deploy with on-demand instances (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./scripts/aws-deployment-unified.sh -t ondemand $(STACK_NAME)

deploy-simple: validate ## Deploy simple development instance (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./scripts/aws-deployment-unified.sh -t simple $(STACK_NAME)

destroy: ## Destroy infrastructure (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@echo "⚠️  WARNING: This will destroy all resources for $(STACK_NAME)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	@./scripts/aws-deployment-unified.sh --cleanup $(STACK_NAME)

# =============================================================================
# TERRAFORM (ALTERNATIVE DEPLOYMENT)
# =============================================================================

tf-init: ## Initialize Terraform
	@cd terraform && terraform init

tf-plan: ## Show Terraform plan (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@cd terraform && terraform plan -var="stack_name=$(STACK_NAME)"

tf-apply: ## Apply Terraform configuration (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@cd terraform && terraform apply -var="stack_name=$(STACK_NAME)"

tf-destroy: ## Destroy Terraform resources (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@cd terraform && terraform destroy -var="stack_name=$(STACK_NAME)"

# =============================================================================
# MONITORING AND OPERATIONS
# =============================================================================

status: ## Check deployment status (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./tools/check-status.sh $(STACK_NAME)

logs: ## View application logs (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./tools/view-logs.sh $(STACK_NAME)

monitor: ## Open monitoring dashboard
	@./tools/open-monitoring.sh

backup: ## Create backup (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./tools/backup.sh $(STACK_NAME)

# =============================================================================
# DOCUMENTATION
# =============================================================================

docs: ## Generate documentation
	@echo "Generating documentation..."
	@./tools/generate-docs.sh
	@echo "✅ Documentation generated in docs/"

docs-serve: ## Serve documentation locally
	@echo "Starting documentation server..."
	@cd docs && python -m http.server 8080

# =============================================================================
# UTILITIES
# =============================================================================

clean: ## Clean up temporary files and caches
	@echo "Cleaning up..."
	@rm -rf .pytest_cache/
	@rm -rf __pycache__/
	@rm -f *.log
	@rm -f *.tmp
	@find . -name "*.pyc" -delete
	@find . -name "*.pyo" -delete
	@echo "✅ Cleanup complete"

cost-estimate: ## Estimate deployment costs (requires STACK_NAME and HOURS)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@python scripts/cost-optimization.py estimate $(STACK_NAME) $(HOURS)

security-scan: ## Run comprehensive security scan
	@echo "Running security scan..."
	@./tools/security-scan.sh
	@echo "✅ Security scan complete"

update-deps: ## Update dependencies
	@echo "Updating dependencies..."
	@./tools/update-deps.sh
	@echo "✅ Dependencies updated"

# =============================================================================
# EXAMPLES AND QUICK START
# =============================================================================

example-dev: ## Deploy example development environment
	@$(MAKE) deploy-simple STACK_NAME=ai-dev-$(shell whoami)

example-prod: ## Deploy example production environment
	@$(MAKE) deploy-ondemand STACK_NAME=ai-prod-$(shell date +%Y%m%d)

quick-start: ## Quick start guide
	@echo "🚀 AI Starter Kit Quick Start"
	@echo ""
	@echo "1. Setup:           make setup"
	@echo "2. Install deps:    make install-deps"  
	@echo "3. Deploy dev:      make deploy-simple STACK_NAME=my-dev-stack"
	@echo "4. Check status:    make status STACK_NAME=my-dev-stack"
	@echo "5. View logs:       make logs STACK_NAME=my-dev-stack"
	@echo "6. Cleanup:         make destroy STACK_NAME=my-dev-stack"
	@echo ""
	@echo "For more commands:  make help"