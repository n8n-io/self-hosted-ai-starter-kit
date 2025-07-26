# Docker Compose Installation Fix

## Problem
The deployment was failing with the error:
```
Error: Neither 'docker compose' nor 'docker-compose' command found
```

This occurred because Docker Compose was not installed on the EC2 instance, and the deployment scripts were trying to use `docker-compose` without ensuring it was available.

## Solution Overview
Implemented a comprehensive Docker Compose installation and detection system that:

1. **Detects existing installations** (both modern plugin and legacy binary)
2. **Installs Docker Compose** if missing using multiple fallback methods
3. **Uses the modern plugin format** (`docker compose`) when possible
4. **Provides backward compatibility** with legacy `docker-compose` command
5. **Works across different distributions** (Ubuntu/Debian and Amazon Linux/RHEL)

## Files Modified

### 1. `deploy-app.sh`
**Location**: Root directory
**Changes**: Added comprehensive Docker Compose installation logic

**Key Features**:
- **Installation Detection**: Checks for both `docker compose` plugin and `docker-compose` binary
- **Distribution Detection**: Automatically detects Ubuntu/Debian vs Amazon Linux/RHEL
- **Multiple Installation Methods**:
  1. Package manager (`apt-get install docker-compose-plugin`)
  2. Manual plugin installation from GitHub releases
  3. Legacy binary fallback
- **Error Handling**: Graceful fallback with clear error messages
- **Command Selection**: Dynamically selects the best available command

**Code Structure**:
```bash
install_docker_compose() {
    # Check existing installations
    # Detect distribution
    # Try package manager installation
    # Fallback to manual installation
    # Final fallback to legacy binary
}
```

### 2. `scripts/aws-deployment-unified.sh`
**Location**: `scripts/aws-deployment-unified.sh` (lines ~2957-3033)
**Changes**: Updated the dynamically generated deployment script

**Key Changes**:
- Added the same Docker Compose installation logic to the dynamically created `deploy-app.sh`
- Updated the Docker Compose command to use the detected command variable
- Changed from hardcoded `docker-compose` to `$DOCKER_COMPOSE_CMD`

**Before**:
```bash
sudo -E docker-compose -f docker-compose.gpu-optimized.yml up -d
```

**After**:
```bash
sudo -E $DOCKER_COMPOSE_CMD -f docker-compose.gpu-optimized.yml up -d
```

### 3. `lib/aws-deployment-common.sh`
**Location**: `lib/aws-deployment-common.sh` (lines ~1400-1500)
**Status**: Already had Docker Compose installation in user data script

**Existing Features**:
- Docker Compose installation during instance initialization
- Cross-platform compatibility (Ubuntu/Amazon Linux)
- Error handling and fallback mechanisms

## Installation Methods

### Method 1: Package Manager (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install -y docker-compose-plugin
```

### Method 2: Manual Plugin Installation
```bash
# Get latest version
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Install as plugin
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```

### Method 3: Legacy Binary Fallback
```bash
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

## Command Detection Logic

The system uses a priority-based approach:

1. **Primary**: `docker compose` (modern plugin)
2. **Secondary**: `docker-compose` (legacy binary)
3. **Fallback**: Installation if neither is available

```bash
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif docker-compose --version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    # Install Docker Compose
fi
```

## Testing

### Test Script
Created `scripts/test-docker-compose-installation.sh` to verify the installation logic:

**Test Coverage**:
- Command detection
- Installation process
- Configuration validation
- Cross-platform compatibility

**Usage**:
```bash
./scripts/test-docker-compose-installation.sh
```

### Manual Testing
```bash
# Test command detection
docker compose version
docker-compose --version

# Test installation
./deploy-app.sh

# Test configuration validation
docker compose -f docker-compose.gpu-optimized.yml config
```

## Benefits

### 1. **Reliability**
- Multiple installation methods ensure success across different environments
- Graceful fallback prevents deployment failures
- Comprehensive error handling

### 2. **Modern Standards**
- Prefers the modern `docker compose` plugin format
- Maintains backward compatibility with legacy `docker-compose`
- Follows Docker's recommended practices

### 3. **Cross-Platform Support**
- Works on Ubuntu/Debian systems
- Works on Amazon Linux/RHEL systems
- Handles different architectures (x86_64, aarch64, arm64)

### 4. **Maintainability**
- Centralized installation logic
- Clear error messages for troubleshooting
- Consistent command usage across scripts

## Deployment Flow

1. **Instance Launch**: User data script installs Docker Compose
2. **Application Deployment**: `deploy-app.sh` verifies/installs Docker Compose
3. **Service Startup**: Uses detected Docker Compose command to start services

## Error Recovery

If Docker Compose installation fails:

1. **Package Manager Failure**: Falls back to manual installation
2. **Network Issues**: Uses fallback version (v2.24.5)
3. **Plugin Installation Failure**: Falls back to legacy binary
4. **All Methods Fail**: Clear error message and deployment stops

## Future Improvements

1. **Version Pinning**: Consider pinning to specific Docker Compose versions for stability
2. **Caching**: Cache downloaded binaries to reduce network dependencies
3. **Health Checks**: Add periodic verification of Docker Compose functionality
4. **Logging**: Enhanced logging for installation troubleshooting

## Related Files

- `deploy-app.sh` - Main deployment script with installation logic
- `scripts/aws-deployment-unified.sh` - AWS deployment automation
- `lib/aws-deployment-common.sh` - Shared deployment functions
- `scripts/simple-update-images.sh` - Image update script (already had detection)
- `scripts/test-docker-compose-installation.sh` - Test script for verification

## Verification

To verify the fix works:

1. **Local Testing**:
   ```bash
   ./scripts/test-docker-compose-installation.sh
   ```

2. **Deployment Testing**:
   ```bash
   ./scripts/aws-deployment-unified.sh
   ```

3. **Manual Verification**:
   ```bash
   # SSH to instance
   ssh -i key.pem ubuntu@instance-ip
   
   # Check Docker Compose
   docker compose version
   # or
   docker-compose --version
   ```

The fix ensures that Docker Compose is always available when needed, preventing deployment failures and providing a robust, cross-platform solution. 