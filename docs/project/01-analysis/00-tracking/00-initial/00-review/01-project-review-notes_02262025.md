# Migration Review Notes - February 26, 2025

## Overview
This document contains observations from reviewing the profile-based Docker Compose migration project. Notes are organized by component/container.

## Docker Compose Configuration
### Original Configuration (docker-compose.yml)
- Uses hardware-based profiles only: "cpu", "gpu-nvidia", "gpu-amd"
- Defines common service configurations using YAML anchors (x-n8n, x-ollama, x-init-ollama)
- Uses external network "hosted-n8n_lab" for service communication
- **Critical Issue**: Nginx depends on multiple application services:
  - depends_on for mcp-memory (service_healthy)
  - depends_on for mcp-seqthinking (service_healthy)
  - depends_on for n8n (service_healthy)
  - depends_on for qdrant (service_started)
- Container names are explicitly defined for most services (e.g., container_name: nginx-proxy)
- Postgres has a healthcheck configured but no explicit profiles
- N8N services depend on postgres with health check condition
- No clear separation between infrastructure services and application services
- **Historical Context**: Nginx proxy was originally part of the n8n deployment, not a separate core service

### Profile-Based Configuration (docker-compose.profile.yml)
- Adds functional profiles in addition to hardware profiles: "core", "n8n", "mcp", "ai", "utility"
- **Key Improvement**: Removes the dependency of nginx on application services
- Assigns appropriate profiles to each service:
  - nginx: ["core", "mcp", "n8n", "ai", "cpu", "gpu-nvidia", "gpu-amd"]
  - postgres: ["core", "n8n", "mcp", "cpu", "gpu-nvidia", "gpu-amd"]
  - n8n services: ["n8n", "cpu", "gpu-nvidia", "gpu-amd"]
  - qdrant: ["ai", "mcp", "cpu", "gpu-nvidia", "gpu-amd"]
  - ollama: ["ai", "cpu"] or ["ai", "gpu-nvidia"]
- Each service maintains its explicit container name
- Services still use the same external network "hosted-n8n_lab"
- Volume configurations and YAML anchors remain consistent with original
- Designed to be started with project names (e.g., `-p core`, `-p n8n`) for better organization
- **Important**: Docker is running in rootless mode - containers don't have root access
- **Architectural Shift**: Nginx is now designated as a core infrastructure service that should operate independently

### MCP Services Configuration
- MCP services assigned to "mcp" profile with hardware profiles
- mcp-memory:
  - Depends on qdrant
  - Has healthcheck for node process
  - Compatible with all hardware profiles (cpu, gpu-nvidia, gpu-amd)
  - Configuration has been completely separated from original combined config
- mcp-seqthinking:
  - Depends on ollama-gpu
  - Has healthcheck for python process
  - Only compatible with "gpu-nvidia" profile
  - Uses official image mcp/sequentialthinking:latest
  - Still needs some configuration updates for complete separation
- In sites-available, `mcp.conf` was initially a combined config for both MCP tools
- Separation is in progress with `mcp-memory.conf` completed

### Utility Services Configuration
- crawl4ai assigned to "utility" profile with "gpu-nvidia" hardware profile
- Depends on qdrant and ollama-gpu
- Requires GPU resources for Nvidia
- Exposes port 11235

## Core Infrastructure
### Nginx
- Configuration stored in /home/groot/nginx/ and mounted to container at /etc/nginx/
- Uses sites-available and sites-enabled directories for configuration management
- Currently has the following configuration files in sites-available:
  - 00-http-redirect.conf, default.conf, n8n.conf, mcp.conf, qdrant.conf, ollama.conf, etc.
- In sites-enabled, only core configurations are enabled by default:
  - 00-http-redirect.conf, default.conf, supabase.conf
- n8n.conf is symlinked when n8n services are started
- **Current Issue**: The nginx container (nginx-proxy) is in a restart loop
- Configuration for application services are maintained through symlinks managed by scripts
- **Key Requirement**: Nginx should be 100% agnostic to other containers and operate independently
- Current upstream directives create dependencies that violate this independence principle
- **Historical Evolution**: Originally deployed as part of n8n, now separated as a core function with no dependencies
- Legacy configuration elements still reflect the previous tight integration with application services

### Postgres
- Runs in core namespace as core-postgres-1
- Currently reported as healthy
- Used by multiple services through shared network

## Application Services
### N8N Services
- Currently running as n8n container in unhealthy state
- Uses n8n_storage volume for persistence
- Connects to postgres database via postgres hostname
- Nginx configuration (n8n.conf) uses upstream directive to route to n8n:5678
- Includes backup server configuration and maintenance page for graceful failure handling

### MCP Services
- Not currently running based on docker ps output
- Required to be started with start-mcp.sh script
- Depends on qdrant and/or ollama services

### AI Services
#### Ollama
- Not currently running based on docker ps output
- Has configuration for CPU, NVIDIA GPU, and AMD GPU hardware profiles
- Includes initialization containers to pull models

#### Qdrant
- Not currently running based on docker ps output
- Used by mcp-memory and crawl4ai services

### Utility Services
#### Crawl4AI
- Not currently running based on docker ps output
- Requires GPU resources (NVIDIA)
- Depends on qdrant and ollama-gpu

## Helper Scripts
### start-core.sh
- Starts core infrastructure services with "core" profile
- Starts postgres first: `docker compose -f docker-compose.profile.yml -p core --profile core up -d postgres`
- Waits 3 seconds for postgres to initialize
- Starts nginx independently: `docker compose -f docker-compose.profile.yml -p core --profile core up -d nginx`
- Uses project name "core" for better Docker UI organization
- No dependencies or service health checks are enforced in the script
- Does not manage nginx configuration files

### start-n8n.sh
- Checks if core services are running and starts them if not
- Determines hardware profile based on input argument (defaults to "cpu")
- Starts n8n services with explicit service names to avoid starting nginx:
  - `docker compose -f docker-compose.profile.yml -p n8n --profile n8n --profile $HW_PROFILE up -d --no-deps n8n n8n-import`
- Uses `--no-deps` flag to prevent starting dependencies
- Creates symbolic link for n8n.conf in nginx sites-enabled directory:
  - `sudo ln -sf /home/groot/nginx/sites-available/n8n.conf /home/groot/nginx/sites-enabled/n8n.conf`
- Restarts core nginx container to apply configuration:
  - `docker restart core-nginx-1`
- Only enables nginx configuration if n8n services start successfully
- **Potential Issue**: Uses `sudo` for creating symbolic links, which might cause permission issues, especially in rootless Docker environment

### start-ai.sh
- Accepts hardware profile argument (nvidia, amd, cpu) defaulting to CPU
- Starts all AI services together with appropriate profile:
  - `docker compose -p ai --profile ai --profile $HW_PROFILE up -d`
- Creates symbolic links for ollama.conf and qdrant.conf in nginx sites-enabled
- Restarts nginx to apply configuration
- Only enables nginx configurations if AI services start successfully

### down-n8n.sh
- Stops n8n services using project name: `docker compose -p n8n down`
- Removes n8n.conf symbolic link from sites-enabled
- Restarts nginx to apply configuration changes
- Uses sudo to remove symbolic links

### down-ai.sh
- Stops AI services using project name: `docker compose -p ai down`
- Removes ollama.conf and qdrant.conf symbolic links from sites-enabled
- Restarts nginx to apply configuration changes
- Uses sudo to remove symbolic links

### down-all.sh
- Stops all containers across all projects:
  - core, n8n, mcp, ai, utility, hosted-n8n
- Removes all service-specific nginx configurations from sites-enabled
- Keeps only core configurations: 00-http-redirect.conf, default.conf, supabase.conf
- Restarts nginx to apply configuration changes

### rollback.sh
- Restores original docker-compose.yml from backup
- Stops all containers from all project namespaces
- Starts services with original configuration
- Provides rollback capability if migration fails

## Issues and Observations
1. **Nginx Restart Loop**:
   - Current nginx container (nginx-proxy) is stuck in restart loop
   - Likely caused by upstream configuration attempting to access unavailable services
   - n8n container is running but in unhealthy state
   - Violates the requirement for nginx to be 100% agnostic to other containers
   - Legacy configuration from when nginx was part of n8n still creates implicit dependencies

2. **Nginx Configuration Structure**:
   - The n8n.conf file includes upstream directive pointing to n8n:5678
   - Contains backup server configuration (127.0.0.1:1) but may still fail during startup
   - Has maintenance page configuration but not effectively handling service unavailability
   - Current design creates tight coupling between nginx and application services

3. **Symbolic Link Management**:
   - Helper scripts manage symbolic links with sudo
   - Each application service has its own script to manage its nginx configuration
   - Restarting nginx after configuration changes is manual through scripts
   - Rootless Docker environment complicates permission management

4. **Container Naming Conflicts**:
   - Core postgres (core-postgres-1) and n8n service exist in different project namespaces
   - Environment variables still reference "postgres" as hostname, which might cause resolution issues across namespaces

5. **Service Dependency Management**:
   - --no-deps flag used to prevent unnecessary dependencies when starting n8n
   - Services might not be fully ready when nginx is configured to use them
   - No health check verification before adding nginx configurations

6. **Rootless Container Issues**:
   - Running in rootless Docker mode limits container permissions
   - Sudo commands in scripts may cause permission issues when managing nginx configuration
   - Symbolic links created with sudo might not be properly recognized in rootless environment

7. **MCP Service Configuration Split**:
   - The mcp.conf file was intended for both MCP services but is being split
   - mcp-memory configuration has been separated
   - mcp-seqthinking still needs complete configuration separation

8. **Legacy Configuration Issues**:
   - Nginx was originally part of the n8n deployment
   - Configuration still reflects this tight coupling
   - Configuration files need complete review to ensure they match the new architectural goal of service independence

## Next Steps
1. **Fix Nginx Configuration for Service Independence**:
   - Redesign upstream directives to make nginx truly agnostic to other services
   - Implement proper conditional configuration or fallback mechanisms
   - Ensure maintenance pages work effectively when upstream services are unavailable
   - Consider using try_files or error_page directives more effectively
   - Completely remove legacy dependencies from original n8n integration

2. **Address Nginx Restart Loop**:
   - Debug current issue with nginx restart loop focusing on upstream references
   - Improve error logging and handling in nginx configuration
   - Consider modifying the start-core.sh script to use more robust startup checks
   - Ensure nginx can start and operate without any dependency on application services

3. **Improve Service Discovery**:
   - Ensure consistent hostname resolution across different project namespaces
   - Verify environment variables correctly reference services in different namespaces
   - Test cross-service communication thoroughly
   - Consider more explicit container addressing with project namespaces

4. **Enhance Helper Scripts for Rootless Environment**:
   - Review sudo commands and find alternatives compatible with rootless Docker
   - Add health checks before creating symbolic links
   - Improve error handling and reporting in scripts
   - Consider using Docker-native methods for configuration management

5. **Complete MCP Configuration Separation**:
   - Finish the separation of mcp-seqthinking configuration
   - Test both MCP services with separate configurations
   - Update scripts to handle the separate configurations properly

6. **Testing Plan**:
   - Test each service group (core, n8n, mcp, ai, utility) independently
   - Verify cross-service communication
   - Test startup and shutdown sequences
   - Validate rollback procedure

7. **Documentation Updates**:
   - Document new configuration approach
   - Update runbooks and troubleshooting guides
   - Create diagrams showing the new architecture
   - Include notes about rootless Docker operation and its implications
