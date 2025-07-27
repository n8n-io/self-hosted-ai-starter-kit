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
                # Verify download integrity
                local aws_cli_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
                local aws_cli_sig_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig"
                
                curl -fsSL "$aws_cli_url" -o "awscliv2.zip"
                
                # Try to verify signature if gpg is available
                if command -v gpg >/dev/null 2>&1; then
                    if curl -fsSL "$aws_cli_sig_url" -o "awscliv2.zip.sig" 2>/dev/null; then
                        warning "Signature verification available but skipped (requires AWS public key setup)"
                        rm -f "awscliv2.zip.sig"
                    fi
                fi
                
                # Verify basic file integrity
                if [ ! -s "awscliv2.zip" ]; then
                    error "Downloaded AWS CLI file is empty or corrupt"
                    rm -f "awscliv2.zip"
                    return 1
                fi
                
                unzip awscliv2.zip
                sudo ./aws/install
                rm -rf aws awscliv2.zip
            fi
            ;;
        "docker")
            if ! command -v docker >/dev/null 2>&1; then
                log "Installing Docker..."
                # Download Docker installation script with verification
                local docker_script_url="https://get.docker.com"
                curl -fsSL "$docker_script_url" -o get-docker.sh
                
                # Basic verification of the script
                if [ ! -s "get-docker.sh" ]; then
                    error "Downloaded Docker script is empty or corrupt"
                    rm -f "get-docker.sh"
                    return 1
                fi
                
                # Check if script looks like a valid shell script
                if ! head -n1 "get-docker.sh" | grep -q "#!/"; then
                    error "Downloaded Docker script does not appear to be a valid shell script"
                    rm -f "get-docker.sh"
                    return 1
                fi
                
                sh get-docker.sh
                sudo usermod -aG docker "$USER"
                rm get-docker.sh
                info "Please log out and back in for Docker group permissions"
            fi
            ;;
        "docker-compose")
            if ! command -v docker-compose >/dev/null 2>&1; then
                log "Installing Docker Compose..."
                local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
                local temp_compose="/tmp/docker-compose-temp"
                
                # Download to temp location first
                if curl -L "$compose_url" -o "$temp_compose"; then
                    # Verify the binary is executable
                    if [ -s "$temp_compose" ] && file "$temp_compose" | grep -q "executable"; then
                        sudo mv "$temp_compose" /usr/local/bin/docker-compose
                        sudo chmod +x /usr/local/bin/docker-compose
                    else
                        error "Downloaded Docker Compose binary appears to be invalid"
                        rm -f "$temp_compose"
                        return 1
                    fi
                else
                    error "Failed to download Docker Compose"
                    return 1
                fi
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
                # Wait for any ongoing apt operations and update package cache
                sudo apt-get update -qq || {
                    warning "Failed to update package cache, trying without update"
                }
                if ! sudo apt-get install -y "$dep"; then
                    error "Failed to install $dep via apt"
                    return 1
                fi
            fi
            ;;
        "python3")
            if ! command -v python3 >/dev/null 2>&1; then
                log "Installing Python 3..."
                sudo apt-get update -qq || true
                if ! sudo apt-get install -y python3 python3-pip python3-venv; then
                    error "Failed to install Python 3"
                    return 1
                fi
            fi
            ;;
        "pip3")
            if ! command -v pip3 >/dev/null 2>&1; then
                log "Installing pip3..."
                sudo apt-get update -qq || true
                if ! sudo apt-get install -y python3-pip; then
                    # Try alternative installation method
                    if command -v python3 >/dev/null 2>&1; then
                        log "Trying to install pip via ensurepip..."
                        python3 -m ensurepip --upgrade || {
                            error "Failed to install pip3 via all methods"
                            return 1
                        }
                    else
                        error "Failed to install pip3 and python3 is not available"
                        return 1
                    fi
                fi
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

# Enhanced installation functions with multiple fallback methods
install_yq_ubuntu() {
    log "Installing yq YAML processor..."
    
    # Method 1: Try official repository (Ubuntu 20.04+)
    if command -v apt-add-repository >/dev/null 2>&1; then
        if sudo apt-add-repository ppa:rmescandon/yq -y 2>/dev/null && \
           sudo apt-get update -qq 2>/dev/null && \
           sudo apt-get install -y yq 2>/dev/null; then
            success "yq installed via official repository"
            return 0
        fi
    fi
    
    # Method 2: Direct download from GitHub releases
    local yq_version
    yq_version=$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest | grep '"tag_name":' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/' 2>/dev/null)
    if [ -z "$yq_version" ]; then
        yq_version="v4.35.2"  # Fallback version
    fi
    
    local yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_linux_amd64"
    local temp_yq="/tmp/yq_temp"
    
    if curl -fsSL "$yq_url" -o "$temp_yq" && [ -s "$temp_yq" ]; then
        # Verify it's an executable
        if file "$temp_yq" | grep -q "executable"; then
            sudo mv "$temp_yq" /usr/local/bin/yq
            sudo chmod +x /usr/local/bin/yq
            success "yq installed via direct download"
            return 0
        else
            rm -f "$temp_yq"
        fi
    fi
    
    # Method 3: Try pip installation
    if command -v pip3 >/dev/null 2>&1; then
        if pip3 install --user yq 2>/dev/null; then
            success "yq installed via pip3"
            return 0
        fi
    fi
    
    error "Failed to install yq via all methods"
    return 1
}

install_github_cli_ubuntu() {
    log "Installing GitHub CLI..."
    
    # Method 1: Official GitHub repository
    if curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null; then
        if echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null; then
            if sudo apt-get update -qq && sudo apt-get install -y gh; then
                success "GitHub CLI installed via official repository"
                return 0
            fi
        fi
    fi
    
    # Method 2: Snap package
    if command -v snap >/dev/null 2>&1; then
        if sudo snap install gh; then
            success "GitHub CLI installed via snap"
            return 0
        fi
    fi
    
    error "Failed to install GitHub CLI via all methods"
    return 1
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
                        # Try multiple installation methods for yq
                        if ! install_yq_ubuntu; then
                            warning "Failed to install yq via all methods"
                        fi
                        ;;
                    "shellcheck")
                        # Install shellcheck with repository fallback
                        if ! sudo apt-get update -qq && sudo apt-get install -y shellcheck; then
                            warning "Failed to install shellcheck via apt, trying snap"
                            sudo snap install shellcheck || warning "Failed to install shellcheck"
                        fi
                        ;;
                    "gh")
                        # Install GitHub CLI with proper error handling
                        if ! install_github_cli_ubuntu; then
                            warning "Failed to install GitHub CLI"
                        fi
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