# Makefile Commands Reference

> Complete reference for all Makefile automation commands

This document provides comprehensive documentation for all Makefile targets and automation commands available in GeuseMaker.

## 🎯 Quick Reference

### Most Used Commands
```bash
make help                               # Show all available commands
make setup                              # Initialize development environment
make deploy STACK_NAME=my-stack        # Deploy infrastructure
make status STACK_NAME=my-stack        # Check deployment status
make destroy STACK_NAME=my-stack       # Clean up resources
```

### Command Categories
- **Setup**: `setup`, `install-deps`, `dev-setup`
- **Testing**: `test`, `test-unit`, `test-integration`, `validate`
- **Deployment**: `deploy`, `deploy-spot`, `deploy-simple`, `destroy`
- **Operations**: `status`, `logs`, `backup`, `monitor`
- **Development**: `lint`, `format`, `docs`, `clean`

## 📚 Complete Command Reference

### 🏗️ Setup and Dependencies

#### `make help`
Display all available commands with descriptions.

**Usage:**
```bash
make help
```

**Output example:**
```
GeuseMaker - Available Commands:

backup               Create backup (requires STACK_NAME)
check-deps          Check if all dependencies are available
clean               Clean up temporary files and caches
deploy              Deploy infrastructure (requires STACK_NAME)
deploy-ondemand     Deploy with on-demand instances (requires STACK_NAME)
deploy-simple       Deploy simple development instance (requires STACK_NAME)
deploy-spot         Deploy with spot instances (requires STACK_NAME)
destroy             Destroy infrastructure (requires STACK_NAME)
dev-setup           Full development setup
docs                Generate documentation
format              Format all code
help                Show this help message
install-deps        Install required dependencies
lint                Run linting on all code
setup               Set up development environment
test                Run all tests
validate            Validate all configurations
```

#### `make setup`
Initialize the development environment with basic configuration.

**Usage:**
```bash
make setup
```

**What it does:**
- Makes all shell scripts executable (`chmod +x scripts/*.sh tools/*.sh`)
- Creates `.env` file from template if it doesn't exist
- Sets up basic directory structure
- Displays completion message

**Example output:**
```
Setting up development environment...
✅ Development environment setup complete
```

#### `make install-deps`
Install all required dependencies for development and deployment.

**Usage:**
```bash
make install-deps
```

**Dependencies installed:**
- AWS CLI
- Docker and Docker Compose
- Python dependencies
- Node.js dependencies (if applicable)
- Development tools

**Implementation:**
```bash
./tools/install-deps.sh
```

#### `make check-deps`
Verify all dependencies are installed and properly configured.

**Usage:**
```bash
make check-deps
```

**Checks performed:**
- AWS CLI installation and configuration
- Docker installation and service status
- Python environment and packages
- Required system tools

#### `make dev-setup`
Complete development environment setup combining multiple setup steps.

**Usage:**
```bash
make dev-setup
```

**Equivalent to:**
```bash
make setup
make install-deps
echo "🚀 Development environment ready!"
```

### 🧪 Testing and Validation

#### `make test`
Run the complete test suite including unit, integration, and security tests.

**Usage:**
```bash
make test
```

**Implementation:**
```bash
./tools/test-runner.sh
```

**Test categories included:**
- Unit tests
- Integration tests
- Security tests
- Configuration validation tests

#### `make test-unit`
Run unit tests only for faster development feedback.

**Usage:**
```bash
make test-unit
```

**Implementation:**
```bash
python -m pytest tests/unit/ -v
```

#### `make test-integration`
Run integration tests that verify service interactions.

**Usage:**
```bash
make test-integration
```

**Implementation:**
```bash
python -m pytest tests/integration/ -v
```

#### `make test-security`
Run security-focused tests and validations.

**Usage:**
```bash
make test-security
```

**Implementation:**
```bash
./tools/security-scan.sh
```

**Security tests include:**
- Credential scanning
- Configuration security audit
- Vulnerability assessments
- Permission validations

#### `make validate`
Validate all configurations without running full tests.

**Usage:**
```bash
make validate
```

**Implementation:**
```bash
./tools/validate-config.sh
```

**Validations performed:**
- AWS configuration
- Environment variables
- Service configurations
- Docker setup
- Network connectivity

### 🚀 Deployment Commands

#### `make deploy`
Smart deployment with automatic instance type selection and optimization.

**Usage:**
```bash
make deploy STACK_NAME=my-stack
```

**Required parameters:**
- `STACK_NAME`: Unique identifier for your deployment

**Optional parameters:**
- `INSTANCE_TYPE`: Override automatic instance selection
- `AWS_REGION`: Override default region

**Implementation:**
```bash
./scripts/aws-deployment-unified.sh $(STACK_NAME)
```

**Features:**
- Automatic instance type selection based on quotas
- Cost optimization
- Health checks during deployment
- Rollback capability on failure

**Example:**
```bash
make deploy STACK_NAME=production-ai
```

#### `make deploy-spot`
Deploy using spot instances for cost optimization.

**Usage:**
```bash
make deploy-spot STACK_NAME=my-stack
```

**Features:**
- 60-90% cost savings compared to on-demand
- Automatic spot price optimization
- Spot interruption handling
- GPU-enabled instances (g4dn.xlarge by default)

**Implementation:**
```bash
./scripts/aws-deployment-unified.sh -t spot $(STACK_NAME)
```

**Example:**
```bash
make deploy-spot STACK_NAME=development-ai
```

#### `make deploy-ondemand`
Deploy using reliable on-demand instances for production.

**Usage:**
```bash
make deploy-ondemand STACK_NAME=my-stack
```

**Features:**
- High availability and reliability
- Predictable pricing
- Full monitoring and alerting
- Production-grade configuration

**Implementation:**
```bash
./scripts/aws-deployment-unified.sh -t ondemand $(STACK_NAME)
```

**Example:**
```bash
make deploy-ondemand STACK_NAME=production-stable
```

#### `make deploy-simple`
Deploy minimal development environment for quick testing.

**Usage:**
```bash
make deploy-simple STACK_NAME=my-stack
```

**Features:**
- t3.medium instance (cost-effective)
- Basic AI services without GPU
- Quick 5-minute setup
- Ideal for learning and development

**Implementation:**
```bash
./scripts/aws-deployment-unified.sh -t simple $(STACK_NAME)
```

**Example:**
```bash
make deploy-simple STACK_NAME=dev-test
```

#### `make destroy`
Clean up all resources for a deployment.

**Usage:**
```bash
make destroy STACK_NAME=my-stack
```

**Safety features:**
- Interactive confirmation prompt
- Lists resources to be deleted
- Backup recommendations before deletion

**Implementation:**
```bash
echo "⚠️  WARNING: This will destroy all resources for $(STACK_NAME)"
read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
./scripts/aws-deployment-unified.sh --cleanup $(STACK_NAME)
```

**Example:**
```bash
make destroy STACK_NAME=old-deployment
```

### 📊 Terraform Commands

#### `make tf-init`
Initialize Terraform working directory.

**Usage:**
```bash
make tf-init
```

**Implementation:**
```bash
cd terraform && terraform init
```

**What it does:**
- Downloads required providers
- Initializes backend configuration
- Prepares working directory for Terraform operations

#### `make tf-plan`
Show Terraform deployment plan without applying changes.

**Usage:**
```bash
make tf-plan STACK_NAME=my-stack
```

**Implementation:**
```bash
cd terraform && terraform plan -var="stack_name=$(STACK_NAME)"
```

**Output includes:**
- Resources to be created, modified, or destroyed
- Configuration validation results
- Cost estimation (if configured)

#### `make tf-apply`
Apply Terraform configuration to create/update infrastructure.

**Usage:**
```bash
make tf-apply STACK_NAME=my-stack
```

**Implementation:**
```bash
cd terraform && terraform apply -var="stack_name=$(STACK_NAME)"
```

#### `make tf-destroy`
Destroy Terraform-managed infrastructure.

**Usage:**
```bash
make tf-destroy STACK_NAME=my-stack
```

**Implementation:**
```bash
cd terraform && terraform destroy -var="stack_name=$(STACK_NAME)"
```

### 📊 Monitoring and Operations

#### `make status`
Check the status of a deployed stack.

**Usage:**
```bash
make status STACK_NAME=my-stack
```

**Information displayed:**
- EC2 instance status
- Service health (n8n, Ollama, Qdrant, Crawl4AI)
- Resource utilization
- Network connectivity
- Recent deployment activity

**Implementation:**
```bash
./tools/check-status.sh $(STACK_NAME)
```

#### `make logs`
View real-time application logs from a deployment.

**Usage:**
```bash
make logs STACK_NAME=my-stack
```

**Features:**
- Real-time log streaming
- Multi-service log aggregation
- Color-coded output by service
- Error highlighting

**Implementation:**
```bash
./tools/view-logs.sh $(STACK_NAME)
```

#### `make monitor`
Open monitoring dashboard for deployed services.

**Usage:**
```bash
make monitor
```

**Features:**
- Opens CloudWatch dashboard
- Service health overview
- Performance metrics
- Alert status

**Implementation:**
```bash
./tools/open-monitoring.sh
```

#### `make backup`
Create a backup of the deployed system.

**Usage:**
```bash
make backup STACK_NAME=my-stack
```

**Backup includes:**
- Service configurations
- Data volumes
- User data and workflows
- System state information

**Implementation:**
```bash
./tools/backup.sh $(STACK_NAME)
```

### 🛠️ Development Tools

#### `make lint`
Run code linting on all source files.

**Usage:**
```bash
make lint
```

**Languages supported:**
- Shell scripts (shellcheck)
- Python (flake8, pylint)
- YAML (yamllint)
- JSON (jsonlint)

**Implementation:**
```bash
./tools/lint.sh
```

#### `make format`
Automatically format code according to style guidelines.

**Usage:**
```bash
make format
```

**Formatters used:**
- Shell scripts (shfmt)
- Python (black, autopep8)
- YAML (prettier)
- JSON (prettier)

**Implementation:**
```bash
./tools/format.sh
```

#### `make docs`
Generate project documentation.

**Usage:**
```bash
make docs
```

**Generated documentation:**
- API documentation
- CLI reference
- Configuration guides
- Architecture documentation

**Implementation:**
```bash
./tools/generate-docs.sh
```

#### `make docs-serve`
Start local documentation server for development.

**Usage:**
```bash
make docs-serve
```

**Features:**
- Local HTTP server on port 8080
- Live reloading during development
- Full documentation navigation

**Implementation:**
```bash
cd docs && python -m http.server 8080
```

#### `make clean`
Clean up temporary files and caches.

**Usage:**
```bash
make clean
```

**Cleaned items:**
- Python cache files (`__pycache__`, `.pyc`, `.pyo`)
- Test cache (`.pytest_cache`)
- Log files (`*.log`)
- Temporary files (`*.tmp`)

**Implementation:**
```bash
rm -rf .pytest_cache/
rm -rf __pycache__/
rm -f *.log
rm -f *.tmp
find . -name "*.pyc" -delete
find . -name "*.pyo" -delete
```

### 💰 Cost Management

#### `make cost-estimate`
Estimate costs for a deployment over a specified time period.

**Usage:**
```bash
make cost-estimate STACK_NAME=my-stack HOURS=24
```

**Parameters:**
- `STACK_NAME`: Deployment to estimate
- `HOURS`: Time period in hours

**Implementation:**
```bash
python scripts/cost-optimization.py estimate $(STACK_NAME) $(HOURS)
```

**Output includes:**
- Instance costs
- Storage costs
- Network costs
- Total estimated cost

### 🔒 Security Commands

#### `make security-scan`
Run comprehensive security scan on the project.

**Usage:**
```bash
make security-scan
```

**Security checks:**
- Credential scanning
- Vulnerability assessment
- Configuration audit
- Dependency security analysis

**Implementation:**
```bash
./tools/security-scan.sh
```

#### `make update-deps`
Update all project dependencies to latest versions.

**Usage:**
```bash
make update-deps
```

**Updates:**
- Python packages
- Node.js packages
- System packages
- Docker images

**Implementation:**
```bash
./tools/update-deps.sh
```

### 🚀 Example Workflows

#### `make example-dev`
Deploy example development environment with auto-generated name.

**Usage:**
```bash
make example-dev
```

**Implementation:**
```bash
$(MAKE) deploy-simple STACK_NAME=GeuseMaker-dev-$(shell whoami)
```

**Result:**
- Creates deployment named `GeuseMaker-dev-username`
- Uses current username in stack name
- Deploys simple development configuration

#### `make example-prod`
Deploy example production environment with date-based naming.

**Usage:**
```bash
make example-prod
```

**Implementation:**
```bash
$(MAKE) deploy-ondemand STACK_NAME=GeuseMaker-prod-$(shell date +%Y%m%d)
```

**Result:**
- Creates deployment named `GeuseMaker-prod-YYYYMMDD`
- Uses current date in stack name
- Deploys production-grade configuration

#### `make quick-start`
Display quick start guide with common commands.

**Usage:**
```bash
make quick-start
```

**Output:**
```
🚀 GeuseMaker Quick Start

1. Setup:           make setup
2. Install deps:    make install-deps
3. Deploy dev:      make deploy-simple STACK_NAME=my-dev-stack
4. Check status:    make status STACK_NAME=my-dev-stack
5. View logs:       make logs STACK_NAME=my-dev-stack
6. Cleanup:         make destroy STACK_NAME=my-dev-stack

For more commands:  make help
```

## 🔧 Advanced Usage

### Environment Variable Support

Most commands support environment variable overrides:

```bash
# Set AWS profile and region
export AWS_PROFILE=production
export AWS_REGION=us-west-2

# Deploy with environment variables
make deploy STACK_NAME=prod-stack

# Override instance type
export INSTANCE_TYPE=g4dn.2xlarge
make deploy-spot STACK_NAME=large-stack

# Enable debug mode
export DEBUG=true
make deploy-simple STACK_NAME=debug-stack
```

### Command Chaining

You can chain multiple commands for complex workflows:

```bash
# Complete development workflow
make setup && make install-deps && make validate && make test

# Deploy and monitor
make deploy STACK_NAME=my-stack && make status STACK_NAME=my-stack

# Test and deploy if tests pass
make test && make deploy STACK_NAME=tested-stack
```

### Parallel Execution

Some operations can be run in parallel:

```bash
# Run tests in background while setting up environment
make test &
make setup
wait

# Monitor multiple stacks (in separate terminals)
make logs STACK_NAME=stack1 &
make logs STACK_NAME=stack2 &
```

## 🚨 Error Handling

### Common Error Scenarios

#### Missing Required Parameters
```bash
# This will fail with helpful error message
make deploy
# Error: ❌ Error: STACK_NAME is required. Use: make deploy STACK_NAME=my-stack
```

#### AWS Configuration Issues
```bash
# Check AWS configuration first
make check-deps

# Fix configuration, then retry
aws configure
make deploy STACK_NAME=my-stack
```

#### Dependency Issues
```bash
# Install missing dependencies
make install-deps

# Validate installation
make check-deps
```

### Debugging Make Commands

Enable verbose output for debugging:

```bash
# Show detailed command execution
make -n deploy STACK_NAME=my-stack  # Dry run
make -d deploy STACK_NAME=my-stack  # Debug output

# Enable debug mode in scripts
DEBUG=true make deploy STACK_NAME=my-stack
```

## 📋 Best Practices

### Naming Conventions
- Use descriptive stack names: `GeuseMaker-production-2024`, `dev-john-testing`
- Include environment: `staging-api-v2`, `prod-web-frontend`
- Use lowercase and hyphens: `my-GeuseMaker-stack` not `MyGeuseMakerStack`

### Development Workflow
1. `make setup` - First time setup
2. `make validate` - Before making changes
3. `make test` - After making changes
4. `make deploy-simple STACK_NAME=dev-test` - Test deployment
5. `make status STACK_NAME=dev-test` - Verify deployment
6. `make destroy STACK_NAME=dev-test` - Cleanup when done

### Production Workflow
1. `make test` - Ensure all tests pass
2. `make security-scan` - Security validation
3. `make deploy-ondemand STACK_NAME=prod-v1` - Production deployment
4. `make backup STACK_NAME=prod-v1` - Create backup
5. `make monitor` - Monitor deployment

---

[**← Back to CLI Overview**](README.md)

---

**Last Updated:** January 2025  
**Make Version:** Compatible with GNU Make 3.81+  
**Platform Compatibility:** macOS, Linux, Windows (WSL)