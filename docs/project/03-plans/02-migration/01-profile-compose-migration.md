# Profile-Based Docker Compose Migration Plan

**Version:** 1.1  
**Date:** Feb 26, 2023  
**Author:** System Administrator  
**Status:** In Progress - Phase 1 Partially Completed  

## Table of Contents
1. [Introduction](#introduction)
2. [Current State](#current-state)
3. [Folder Structure](#folder-structure)
4. [Architectural Considerations](#architectural-considerations)
5. [Migration Goals](#migration-goals)
6. [Implementation Timeline](#implementation-timeline)
7. [Migration Plan](#migration-plan)
   - [Phase 1: Initial Deployment Testing](#phase-1-initial-deployment-testing)
   - [Phase 2: Cross-Service Communication Verification](#phase-2-cross-service-communication-verification)
   - [Phase 3: GPU Resource Verification](#phase-3-gpu-resource-verification)
   - [Phase 4: Full System Test](#phase-4-full-system-test)
   - [Phase 5: Contingency Plan](#phase-5-contingency-plan)
   - [Phase 6: Implementation](#phase-6-implementation)
8. [Go/No-Go Decision Points](#gono-go-decision-points)
9. [Risk Assessment](#risk-assessment)
10. [Post-Migration Tasks](#post-migration-tasks)

## Introduction

This document outlines the precise steps for migrating the hosted-n8n environment from the current Docker Compose configuration to a profile-based approach with project names. The profile-based approach provides better organization, enhanced UI visibility in Docker, and more granular control over service groups.

## Current State

- The existing infrastructure uses a single docker-compose.yml file with hardware profiles (cpu, gpu-nvidia, gpu-amd)
- Services are currently started with `docker compose --profile gpu-nvidia up -d`
- All services appear in a single Docker project namespace
- We have created a new profile-based configuration (docker-compose.profile.yml)
- Helper scripts have been developed in the scripts/ directory
- A rollback mechanism has been implemented

## Folder Structure

### Current File Structure
```
/hosted-n8n/
├── docker-compose.yml               				 # Original docker-compose file with hardware profiles
├── docker-compose.yml.bak           				 # Backup of the original file
├── docker-compose.profile.yml       				 # New profile-based configuration
├── scripts/                         				 # Helper scripts directory
│   ├── README.md                    				 # Documentation for scripts
│   ├── down-all.sh                  				 # Script to stop all containers
│   ├── rollback.sh                  				 # Script to revert to original configuration
│   ├── start-ai.sh                  				 # Script to start AI services
│   ├── start-all.sh                 				 # Script to start all services
│   ├── start-core.sh                				 # Script to start core infrastructure
│   ├── start-mcp.sh                 				 # Script to start MCP services
│   ├── start-n8n.sh                 				 # Script to start N8N services
│   └── start-utility.sh             				 # Script to start utility services
├── docs/                            				 # Documentation directory
│   ├── profile_based_migration_plan.md 			 # Original migration plan
│   └── project/                     				 # Project documentation
│       └── 03-plans/                				 # Plans documentation
│           └── 02-migration/        				 # Migration plans
│               └── 01-profile-compose-migration.md  # This document
├── mcp/                             				 # MCP service directory
├── n8n/                             				 # N8N service directory
│   └── backup/                      				 # N8N backup directory
├── crawl4ai/                        				 # Crawl4AI service directory
├── shared/                          				 # Shared data directory
└── .env                             				 # Environment variables
```

### Expected File Structure After Migration
```
/hosted-n8n/
├── docker-compose.yml               	 			 # Profile-based configuration (renamed from docker-compose.profile.yml)
├── docker-compose.yml.bak           	 			 # Backup of the original file
├── scripts/                         	 			 # Helper scripts directory
│   ├── README.md                    	 			 # Documentation for scripts
│   ├── down-all.sh                  	 			 # Script to stop all containers
│   ├── rollback.sh                  	 			 # Script to revert to original configuration
│   ├── start-ai.sh                  	 			 # Script to start AI services
│   ├── start-all.sh                 	 			 # Script to start all services
│   ├── start-core.sh                	 			 # Script to start core infrastructure
│   ├── start-mcp.sh                 	 			 # Script to start MCP services
│   ├── start-n8n.sh                 	 			 # Script to start N8N services
│   └── start-utility.sh             	 			 # Script to start utility services
├── docs/                            	 			 # Documentation directory
│   ├── profile_based_migration_plan.md  			 # Original migration plan
│   └── project/                     	 			 # Project documentation
│       └── 03-plans/                	 			 # Plans documentation
│           └── 02-migration/        	 			 # Migration plans
│               └── 01-profile-compos	 			 e-migration.md  # This document
├── mcp/                             	 			 # MCP service directory
├── n8n/                             	 			 # N8N service directory
│   └── backup/                      	 			 # N8N backup directory
├── crawl4ai/                        	 			 # Crawl4AI service directory
├── shared/                          	 			 # Shared data directory
└── .env                             	 			 # Environment variables
```

### Docker Projects Structure
In addition to the file system changes, the Docker project structure will change:

**Current Docker Project Structure:**
- Single project namespace (default or unnamed)
- All containers visible together in Docker UI
- Containers differentiated only by name

**Expected Docker Project Structure After Migration:**
- Multiple project namespaces based on service function:
  - `core` - Core infrastructure services (nginx, postgres)
  - `n8n` - N8N workflow services
  - `mcp` - MCP services
  - `ai` - AI/ML services (ollama, qdrant)
  - `utility` - Utility services (crawl4ai)
- Each project appears separately in Docker UI
- Clearer visual separation of service components
- Ability to start/stop entire functional groups

## Architectural Considerations

Before proceeding with the migration, it's important to understand the architectural principles that should guide our implementation:

### Core Infrastructure Independence

1. **Nginx as Gateway**:
   - Nginx serves as the primary reverse proxy/gateway for the entire system
   - It should start independently of application services
   - Located at `/home/groot/nginx/` outside the project directory
   - Used to access container UIs via web browser from secured network

2. **Database Independence**:
   - Postgres database is a foundational service
   - Should not depend on application services

3. **Service Layering**:
   - Core infrastructure (nginx, postgres) forms the foundation
   - Application services (n8n, mcp, ai, utility) build on top of core
   - Each layer should be able to start independently

### Dependency Management

1. **Avoiding Circular Dependencies**:
   - Core services should not depend on application services
   - Application services may depend on core services
   - Services within the same layer may have interdependencies

2. **Health Checks**:
   - Health checks should be implemented at the service level
   - Nginx should handle routing based on service availability
   - Docker health checks should be used for container orchestration

### Profile Organization

1. **Functional Profiles**:
   - Services are grouped by function (core, n8n, mcp, ai, utility)
   - Each profile represents a logical group of services

2. **Hardware Profiles**:
   - Hardware profiles (cpu, gpu-nvidia, gpu-amd) are orthogonal to functional profiles
   - Services may belong to multiple profiles

## Nginx Configuration Organization

During the implementation of Phase 1, we encountered issues with nginx failing to start due to references to upstream services that weren't running. This section documents the approach for organizing nginx configuration files to ensure proper service independence and maintainability.

### Current State of Nginx Configuration

- Nginx configuration files are stored in `/home/groot/nginx/`
- All site configurations were initially placed in `/home/groot/nginx/sites-enabled/`
- To allow nginx to start independently, problematic configuration files were moved to a temporary directory

### Best Practices for Nginx Configuration

The standard nginx configuration structure follows this pattern:

1. **Main Configuration Directory Structure**:
   - `nginx.conf` - Main configuration file
   - `sites-available/` - All site configurations are stored here
   - `sites-enabled/` - Symbolic links to configurations in sites-available that should be active
   - `conf.d/` - Additional configuration snippets

2. **Sites-Available vs. Sites-Enabled Pattern**:
   - **sites-available**: Contains all site configuration files
   - **sites-enabled**: Contains symbolic links to the configurations in sites-available that should be active

This separation allows maintenance of all configurations in one place while only activating the ones needed.

### Implementation Plan for Nginx Configuration

To align with best practices, the following steps will be implemented:

1. **Create a proper sites-available directory**:
```bash
mkdir -p /home/groot/nginx/sites-available
```
**Status: COMPLETED** - Directory created successfully

2. **Move all configuration files from temp to sites-available**:
```bash
cp /home/groot/nginx/temp/* /home/groot/nginx/sites-available/
cp /home/groot/nginx/sites-enabled/*.conf /home/groot/nginx/sites-available/
```
**Status: COMPLETED** - All configuration files have been copied to sites-available

3. **Keep only core configurations active in sites-enabled**:
   - `00-http-redirect.conf`
   - `default.conf`
   - `supabase.conf`
**Status: COMPLETED** - Only core configurations remain in sites-enabled

4. **Service-Specific Configuration Management**:
   - When starting a service, create a symbolic link from sites-available to sites-enabled
   - When stopping a service, remove the symbolic link
**Status: COMPLETED** - Implemented in service start/stop scripts

5. **Update service start scripts**:
```bash
# Example addition to start-n8n.sh
# After starting n8n services
if [ $? -eq 0 ]; then
  echo "Enabling nginx configuration for n8n..."
  ln -sf /home/groot/nginx/sites-available/n8n.conf /home/groot/nginx/sites-enabled/n8n.conf
  docker restart nginx-proxy
fi
```
**Status: COMPLETED** - Implemented in start-n8n.sh and start-ai.sh scripts

6. **Update service stop scripts**:
```bash
# Example addition to stop scripts
echo "Disabling nginx configuration for n8n..."
rm -f /home/groot/nginx/sites-enabled/n8n.conf
docker restart nginx-proxy
```
**Status: COMPLETED** - Implemented in down-n8n.sh, down-ai.sh, and down-all.sh scripts

### Benefits of This Approach

1. **Compliance with Standard Practices**: Follows industry-standard nginx configuration organization
2. **Improved Maintainability**: Clear separation between available and enabled configurations
3. **Service Independence**: Ensures nginx only tries to proxy to services that are actually running
4. **Granular Control**: Allows for precise control over which configurations are active
5. **Reduced Errors**: Prevents nginx from failing due to missing upstream services
6. **Documentation**: Provides clear documentation for compliance and audit purposes

This approach aligns with the architectural principle of core infrastructure independence and ensures that nginx can start and operate independently of application services.

### Implementation Summary

The nginx configuration organization has been successfully implemented with the following accomplishments:

1. **Directory Structure**: Created a proper sites-available directory to store all configuration files
2. **Configuration Management**: Moved all configuration files to sites-available while keeping only core configurations in sites-enabled
3. **Service Integration**: Updated service start scripts (start-n8n.sh, start-ai.sh) to enable service-specific nginx configurations
4. **Service Cleanup**: Created service stop scripts (down-n8n.sh, down-ai.sh) to disable service-specific nginx configurations
5. **Global Management**: Updated down-all.sh to handle removing all service-specific nginx configurations
6. **Documentation**: Updated this migration plan to reflect the changes and provide guidance for future maintenance

The implementation ensures that nginx can start independently of other services and that service-specific configurations are only enabled when the corresponding services are running. This approach significantly improves system resilience and maintainability.

## Migration Goals

1. Implement functional service grouping using Docker Compose profiles
2. Organize services into separate project namespaces for better Docker UI visibility
3. Maintain hardware profile capabilities (cpu, gpu-nvidia, gpu-amd)
4. Ensure all services function properly in the new configuration
5. Provide simple helper scripts for common operations
6. Document the new approach thoroughly

## Implementation Timeline

| Phase | Description | Estimated Time |
|-------|-------------|----------------|
| Preparation | File creation and script development | Completed |
| Testing | Phased testing of all components | 1-2 days |
| Implementation | Final implementation | 0.5 day |
| Documentation | Update documentation | 0.5 day |
| **Total** | | **2-3 days** |

## Migration Plan

### Phase 1: Initial Deployment Testing

#### 1.1. Update Docker Compose Configuration

```bash
# Remove inappropriate dependencies from nginx
# Ensure core services can start independently
```
**Status: COMPLETED** - Dependencies removed from nginx service in docker-compose.profile.yml


#### 1.2. Deploy Core Infrastructure
```bash
# Start postgres database
docker compose -f docker-compose.profile.yml -p core --profile core up -d postgres

# Start nginx independently
docker compose -f docker-compose.profile.yml -p core --profile core up -d nginx
```
**Status: COMPLETED** - Core infrastructure successfully deployed

#### 1.3. Verification Checklist for Core Infrastructure
- [x] Confirm postgres is running: `docker ps | grep postgres`
- [x] Verify postgres is healthy: `docker exec -it core-postgres-1 pg_isready`
- [x] Confirm nginx is running: `docker ps | grep nginx`
- [x] Verify nginx configuration: `docker exec -it nginx-proxy nginx -t`
- [x] Check nginx can serve basic responses

#### 1.4. Deploy N8N Services
```bash
docker compose -f docker-compose.profile.yml -p n8n --profile n8n --profile gpu-nvidia up -d
```

#### 1.5. Verification Checklist for N8N Services
- [ ] Confirm n8n containers are running: `docker ps | grep n8n`
- [ ] Verify n8n can connect to postgres
- [ ] Check n8n is accessible through nginx: `curl -I http://localhost:8080/n8n/`

#### 1.6. Deploy MCP Services
```bash
docker compose -f docker-compose.profile.yml -p mcp --profile mcp --profile gpu-nvidia up -d
```

#### 1.7. Verification Checklist for MCP Services
- [ ] Confirm containers are running: `docker ps | grep mcp`
- [ ] Check container logs for errors
- [ ] Verify services are accessible through their endpoints

#### 1.8. Deploy AI Services
```bash
docker compose -f docker-compose.profile.yml -p ai --profile ai --profile gpu-nvidia up -d
```

#### 1.9. Verification Checklist for AI Services
- [ ] Confirm containers are running: `docker ps | grep ai`
- [ ] Check ollama is functioning: `curl http://localhost:11434/api/version`
- [ ] Verify qdrant is accessible

#### 1.10. Deploy Utility Services
```bash
docker compose -f docker-compose.profile.yml -p utility --profile utility --profile gpu-nvidia up -d
```

#### 1.11. Verification Checklist for Utility Services
- [ ] Confirm containers are running: `docker ps | grep utility`
- [ ] Check crawl4ai service logs for errors

### Phase 2: Cross-Service Communication Verification

#### 2.1. Test Nginx Proxy to N8N
- [ ] Verify nginx properly routes to n8n service
- [ ] Check nginx configuration and logs
- [ ] Test access through the configured endpoints

#### 2.2. Test N8N to Database
- [ ] Verify n8n can read/write to postgres database
- [ ] Check n8n workflows that interact with the database
- [ ] Verify credentials import/export functionality

#### 2.3. Test MCP to AI Services
- [ ] Verify MCP services can communicate with AI services like qdrant and ollama
- [ ] Check for any networking issues in container logs
- [ ] Test API calls between services

#### 2.4. Test External Access
- [ ] Verify that external clients can access services through nginx
- [ ] Test authentication mechanisms still work
- [ ] Verify SSL/TLS if configured

### Phase 3: GPU Resource Verification

#### 3.1. Check GPU Allocation
```bash
docker exec -it ollama-gpu nvidia-smi
```
- [ ] Verify GPU resources are properly allocated
- [ ] Check for any resource contention issues

#### 3.2. Test GPU Performance
- [ ] Run a simple benchmark to verify GPU performance
- [ ] Compare performance to the original configuration
- [ ] Verify all GPU-dependent services can access the GPU

#### 3.3. Monitor GPU Usage
- [ ] Check GPU usage across different services
- [ ] Verify that services are properly utilizing GPU resources
- [ ] Look for any anomalies in GPU utilization

### Phase 4: Full System Test

#### 4.1. Test End-to-End Workflows
- [ ] Execute common workflows that span multiple services
- [ ] Verify all functionality works as expected
- [ ] Test under normal load conditions

#### 4.2. Performance Testing
- [ ] Compare performance metrics with the original configuration
- [ ] Check for any degradation in performance
- [ ] Verify resource utilization is optimal

#### 4.3. Resilience Testing
- [ ] Test service recovery after failure
- [ ] Verify that dependent services handle failures gracefully
- [ ] Test restarting individual services

### Phase 5: Contingency Plan (If Issues Arise)

#### 5.1. Stop All Profile-Based Containers
```bash
./scripts/down-all.sh
```

#### 5.2. Restore Original Configuration
```bash
./scripts/rollback.sh
```

#### 5.3. Verify Original Configuration Restored
- [ ] Check containers are running with original configuration
- [ ] Verify functionality is restored
- [ ] Document any issues encountered

### Phase 6: Implementation (If Testing Successful)

#### 6.1. Replace Original Docker Compose File
```bash
mv docker-compose.profile.yml docker-compose.yml
```

#### 6.2. Update Documentation
- [ ] Update main README with new profile-based approach
- [ ] Document use of helper scripts
- [ ] Create troubleshooting guide for common issues

#### 6.3. User Training
- [ ] Train team members on the new setup
- [ ] Provide examples of common operations
- [ ] Address any questions or concerns

## Go/No-Go Decision Points

Each phase includes critical decision points:

1. **After Phase 1:** 
   - All services must start successfully in their respective project namespaces
   - If any service fails to start properly, roll back and investigate

2. **After Phase 2:** 
   - All cross-service communication must work flawlessly
   - If any communication issues are detected, roll back and investigate

3. **After Phase 3:** 
   - GPU resources must be properly allocated and utilized
   - If GPU issues are detected, roll back and investigate

4. **After Phase 4:** 
   - All end-to-end workflows must function as expected
   - Performance must be equal or better than the original configuration
   - If any functional or performance issues are detected, roll back and investigate

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Service communication failure | Medium | High | Ensure network configuration is preserved; test thoroughly before full implementation |
| GPU resource contention | Medium | Medium | Monitor GPU usage; adjust resource allocation if needed |
| Container name conflicts | Low | Medium | Use unique container names; use project namespaces |
| Data loss | Low | High | No data volumes will be affected by this change; backups are still recommended |
| Performance degradation | Low | Medium | Compare performance metrics; rollback if significant degradation |

## Post-Migration Tasks

1. **Documentation Updates**
   - Update all documentation to reflect the new configuration
   - Create new troubleshooting guides as needed

2. **Monitoring Setup**
   - Ensure monitoring tools are aware of the new project structure
   - Update dashboards if necessary

3. **Automation Updates**
   - Update any CI/CD pipelines that interact with the environment
   - Update maintenance scripts

4. **Training**
   - Provide team training on the new helper scripts
   - Document common operations

5. **Performance Optimization**
   - Analyze performance data and optimize as needed
   - Consider further refinement of profiles based on usage patterns 