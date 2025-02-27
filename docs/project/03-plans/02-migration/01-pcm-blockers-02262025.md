# Profile-Based Docker Compose Migration: Blockers and Findings
**Date:** February 26, 2025  
**Author:** System Administrator  
**Status:** In Progress - Troubleshooting  

## Current Blockers

### 1. Nginx Container Restart Loop

The nginx container (`nginx-proxy`) is stuck in a restart loop, preventing proper operation of the system. This is a critical blocker for the migration as nginx serves as the primary gateway for all services.

#### Symptoms:
- Container status shows "restarting"
- Health checks pass but container exits shortly after starting
- Logs show errors related to missing upstream services

#### Root Causes:
1. **Missing Configuration Files**: The container is looking for configuration files in `/etc/nginx/sites-enabled/n8n.conf` but can't find them despite the symbolic link existing on the host system.
2. **Volume Mount Issues**: The `/home/groot/nginx` directory is mounted as read-only to `/etc/nginx` in the container, but the container may not be seeing the updated symbolic links.
3. **Upstream Service References**: Configuration files reference upstream services that may not be running (crawl4ai, mcp-memory, n8n, qdrant, ollama).

### 2. Container Naming Conflicts

There appear to be conflicts between containers started with different project names but using the same container names.

#### Symptoms:
- Multiple postgres containers running (core-postgres-1 and n8n-postgres-1)
- Containers reference each other by hostname but may connect to the wrong instance

#### Root Causes:
1. **Inconsistent Container Naming**: Some services use explicit container names while others use Docker Compose generated names.
2. **Network Isolation**: Services in different projects may not be able to communicate properly.

### 3. N8N Service Health Issues

The n8n container is running but marked as unhealthy, which may indicate configuration or connectivity problems.

#### Symptoms:
- Container status shows "unhealthy"
- Service may not be accessible through nginx

#### Root Causes:
1. **Database Connection Issues**: N8N may not be able to connect to the correct postgres instance.
2. **Nginx Configuration**: The nginx configuration for n8n may not be properly set up or enabled.

## Detailed Findings

### Nginx Configuration Analysis

1. **Host Configuration Structure**:
   - Configuration files are properly organized in `/home/groot/nginx/sites-available/`
   - Symbolic links exist in `/home/groot/nginx/sites-enabled/`
   - The main nginx.conf includes the sites-enabled directory

2. **Container Mount Issues**:
   - The nginx container mounts `/home/groot/nginx:/etc/nginx:ro` as read-only
   - Changes to symbolic links on the host may not be immediately reflected in the container
   - The container may need to be restarted after symbolic link changes

3. **Configuration File Content**:
   - The n8n.conf file references an upstream server at `n8n:5678`
   - Other configuration files reference services that may not be running

### Docker Network Analysis

1. **Network Configuration**:
   - Services are configured to use the `hosted-n8n_lab` external network
   - The nginx container is part of this network
   - Services in different projects should be able to communicate if on the same network

2. **Container Naming**:
   - Some services use explicit container names (e.g., `container_name: n8n`)
   - Others rely on Docker Compose generated names (e.g., `core-postgres-1`)
   - This inconsistency may cause service discovery issues

### Service Startup Sequence

1. **Current Sequence**:
   - Core services (postgres, nginx) are started first
   - N8N services are started with the `--no-deps` flag to avoid starting nginx again
   - Nginx configuration for n8n is enabled via symbolic link
   - Nginx container is restarted to apply the configuration

2. **Issues with Sequence**:
   - Restarting nginx may cause it to enter a restart loop if configurations reference unavailable services
   - The `--no-deps` flag may prevent necessary dependencies from starting

## Recommended Solutions

### Short-term Fixes

1. **Fix Nginx Configuration**:
   - Modify all configuration files in sites-available to use conditional upstream blocks
   - Implement health checks in nginx configurations to handle unavailable upstream services
   - Consider using Docker DNS resolution for service discovery

2. **Container Naming Standardization**:
   - Ensure consistent container naming across all services
   - Update references to use the standardized names

3. **Improve Start Scripts**:
   - Modify scripts to check if services are already running before attempting to start them
   - Add more robust error handling and status checking

### Long-term Solutions

1. **Implement Service Discovery**:
   - Consider using a service discovery mechanism (e.g., Consul, etcd)
   - Dynamically generate nginx configurations based on running services

2. **Container Orchestration**:
   - Evaluate more sophisticated container orchestration solutions (e.g., Kubernetes)
   - Implement proper health checks and readiness probes

3. **Configuration Management**:
   - Implement a configuration management system for nginx
   - Generate configurations dynamically based on the current state of the system

## Next Steps

1. Fix the nginx configuration to handle missing upstream services gracefully
2. Standardize container naming and service discovery approach
3. Update start scripts to be more robust and handle existing services
4. Test each service group independently before attempting to run the full stack
5. Document the updated approach and any changes to the migration plan 