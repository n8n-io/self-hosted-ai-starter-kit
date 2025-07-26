#!/bin/bash
# =============================================================================
# Dependency Installation Script
# Installs required tools and dependencies for GeuseMaker
# =============================================================================

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]; then
    source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
fi

# =============================================================================
# DEPENDENCY DEFINITIONS (bash 3.x compatible - no associative arrays)
# =============================================================================

# Required dependencies list (bash 3.x compatible)
REQUIRED_DEPS="aws docker docker-compose terraform jq bc curl git make python3 pip3"

# Optional dependencies list (bash 3.x compatible)
OPTIONAL_DEPS_LIST="yq helm kubectl shellcheck hadolint trivy gh"

# Function to get description for dependency (bash 3.x compatible)
get_dep_description() {
    local dep="$1"
    case "$dep" in
        "aws") echo "AWS CLI for cloud deployment" ;;
        "docker") echo "Docker for containerization" ;;
        "docker-compose") echo "Docker Compose for multi-container applications" ;;
        "terraform") echo "Infrastructure as Code tool" ;;
        "jq") echo "JSON processor for AWS CLI output" ;;
        "bc") echo "Calculator for cost estimates" ;;
        "curl") echo "HTTP client for API testing" ;;
        "git") echo "Version control system" ;;
        "make") echo "Build automation tool" ;;
        "python3") echo "Python runtime for scripts" ;;
        "pip3") echo "Python package manager" ;;
        "yq") echo "YAML processor for configuration files" ;;
        "helm") echo "Kubernetes package manager" ;;
        "kubectl") echo "Kubernetes CLI" ;;
        "shellcheck") echo "Shell script linter" ;;
        "hadolint") echo "Dockerfile linter" ;;
        "trivy") echo "Security scanner" ;;
        "gh") echo "GitHub CLI" ;;
        *) echo "Unknown dependency" ;;
    esac
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            echo "ubuntu"
        elif command -v yum >/dev/null 2>&1; then
            echo "centos"
        elif command -v apk >/dev/null 2>&1; then
            echo "alpine"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

install_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        log "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

install_dep_macos() {
    local dep="$1"
    local description="$2"
    
    case "$dep" in
        "aws")
            if ! command -v aws >/dev/null 2>&1; then
                log "Installing AWS CLI..."
                brew install awscli
            fi
            ;;
        "docker")
            if ! command -v docker >/dev/null 2>&1; then
                log "Installing Docker..."
                brew install --cask docker
                info "Please start Docker Desktop manually"
            fi
            ;;
        "docker-compose")
            if ! command -v docker-compose >/dev/null 2>&1; then
                log "Installing Docker Compose..."
                brew install docker-compose
            fi
            ;;
        "terraform")
            if ! command -v terraform >/dev/null 2>&1; then
                log "Installing Terraform..."
                brew install terraform
            fi
            ;;
        *)
            if ! command -v "$dep" >/dev/null 2>&1; then
                log "Installing $dep..."
                brew install "$dep" || warning "Failed to install $dep via brew"
            fi
            ;;
    esac
}

install_dep_ubuntu() {
    local dep="$1"
    local description="$2"
    
    case "$dep" in
        "aws")
            if ! command -v aws >/dev/null 2>&1; then
                log "Installing AWS CLI..."
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                unzip awscliv2.zip
                sudo ./aws/install
                rm -rf aws awscliv2.zip
            fi
            ;;
        "docker")
            if ! command -v docker >/dev/null 2>&1; then
                log "Installing Docker..."
                curl -fsSL https://get.docker.com -o get-docker.sh
                sh get-docker.sh
                sudo usermod -aG docker "$USER"
                rm get-docker.sh
                info "Please log out and back in for Docker group permissions"
            fi
            ;;
        "docker-compose")
            if ! command -v docker-compose >/dev/null 2>&1; then
                log "Installing Docker Compose..."
                sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                sudo chmod +x /usr/local/bin/docker-compose
            fi
            ;;
        "terraform")
            if ! command -v terraform >/dev/null 2>&1; then
                log "Installing Terraform..."
                wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
                echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                sudo apt update && sudo apt install terraform
            fi
            ;;
        "jq"|"bc"|"curl"|"git"|"make")
            if ! command -v "$dep" >/dev/null 2>&1; then
                log "Installing $dep..."
                sudo apt-get update && sudo apt-get install -y "$dep"
            fi
            ;;
        "python3")
            if ! command -v python3 >/dev/null 2>&1; then
                log "Installing Python 3..."
                sudo apt-get update && sudo apt-get install -y python3 python3-pip
            fi
            ;;
        "pip3")
            if ! command -v pip3 >/dev/null 2>&1; then
                log "Installing pip3..."
                sudo apt-get update && sudo apt-get install -y python3-pip
            fi
            ;;
    esac
}

install_python_deps() {
    log "Installing Python dependencies..."
    
    if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
        pip3 install -r "$PROJECT_ROOT/requirements.txt"
    else
        # Install basic Python dependencies
        pip3 install --user boto3 requests pyyaml pytest pytest-cov black flake8
    fi
}

install_optional_deps() {
    local os_type="$1"
    
    info "Installing optional dependencies..."
    
    for dep in $OPTIONAL_DEPS_LIST; do
        local description
        description=$(get_dep_description "$dep")
        
        if command -v "$dep" >/dev/null 2>&1; then
            success "$dep is already installed"
            continue
        fi
        
        case "$os_type" in
            "macos")
                case "$dep" in
                    "yq"|"helm"|"kubectl"|"shellcheck"|"hadolint"|"trivy"|"gh")
                        brew install "$dep" || warning "Failed to install optional dependency: $dep"
                        ;;
                esac
                ;;
            "ubuntu")
                case "$dep" in
                    "yq")
                        wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
                        sudo mv /tmp/yq /usr/local/bin/yq
                        sudo chmod +x /usr/local/bin/yq
                        ;;
                    "shellcheck")
                        sudo apt-get install -y shellcheck
                        ;;
                    "gh")
                        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                        sudo apt update && sudo apt install gh
                        ;;
                    *)
                        warning "Optional dependency $dep not available for $os_type"
                        ;;
                esac
                ;;
        esac
    done
}

# =============================================================================
# MAIN INSTALLATION PROCESS
# =============================================================================

main() {
    local os_type
    os_type=$(detect_os)
    local install_optional=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --optional)
                install_optional=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--optional] [--help]"
                echo ""
                echo "Options:"
                echo "  --optional    Install optional dependencies"
                echo "  --help        Show this help message"
                exit 0
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    log "Starting dependency installation for $os_type..."
    
    # Install package manager for macOS
    if [ "$os_type" = "macos" ]; then
        install_homebrew
    fi
    
    # Install required dependencies
    log "Installing required dependencies..."
    for dep in $REQUIRED_DEPS; do
        local description
        description=$(get_dep_description "$dep")
        
        if command -v "$dep" >/dev/null 2>&1; then
            success "$dep is already installed"
            continue
        fi
        
        info "Installing $dep ($description)..."
        
        case "$os_type" in
            "macos")
                install_dep_macos "$dep" "$description"
                ;;
            "ubuntu")
                install_dep_ubuntu "$dep" "$description"
                ;;
            *)
                warning "Automatic installation not supported for $os_type. Please install $dep manually."
                ;;
        esac
    done
    
    # Install Python dependencies
    install_python_deps
    
    # Install optional dependencies if requested
    if [ "$install_optional" = "true" ]; then
        install_optional_deps "$os_type"
    fi
    
    # Verify installations
    log "Verifying installations..."
    local failed_deps=""
    
    for dep in $REQUIRED_DEPS; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            failed_deps="$failed_deps $dep"
        fi
    done
    
    if [ -z "$failed_deps" ]; then
        success "All required dependencies installed successfully!"
        
        # Additional setup steps
        info "Additional setup recommendations:"
        info "1. Configure AWS CLI: aws configure"
        info "2. Verify Docker: docker --version"
        info "3. Test Terraform: terraform --version"
        
        if [ "$os_type" = "ubuntu" ] && id -nG "$USER" | grep -qw "docker"; then
            warning "Please log out and back in for Docker group permissions to take effect"
        fi
        
    else
        warning "Some dependencies failed to install:$failed_deps"
        warning "Please install them manually or run with sudo if needed"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"