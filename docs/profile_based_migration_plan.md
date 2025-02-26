# Migration Plan: Profile-Based Docker Organization

This document outlines a step-by-step plan to implement the recommended Profile-Based Docker organization approach with project names for the hosted-n8n environment.

## Current State Analysis

The current docker-compose.yml is already using profiles for hardware configurations (cpu, gpu-nvidia, gpu-amd), but can be enhanced to leverage functional grouping and project names for better organization.

## Migration Goals

1. Organize services into logical functional groups using profiles
2. Use project names for UI organization
3. Create helper scripts for common operations
4. Document the new approach

## Implementation Timeline

| Phase | Description | Estimated Time |
|-------|-------------|----------------|
| 1 | Planning and Current Configuration Analysis | 1 day |
| 2 | Docker Compose Reorganization | 1-2 days |
| 3 | Script Creation | 1 day |
| 4 | Testing | 1-2 days |
| 5 | Documentation | 1 day |
| **Total** | | **5-7 days** |

## Detailed Implementation Plan

### Phase 1: Planning and Analysis

1. **Identify Functional Groups**
   - Review all services in docker-compose.yml
   - Categorize into logical groups:
     - Core Infrastructure (nginx, postgres)
     - N8N Services (n8n, n8n-import)
     - MCP Services (mcp-memory, mcp-seqthinking)
     - AI/ML Services (ollama, qdrant)
     - Utility Services (crawl4ai)

2. **Plan Profile Strategy**
   - Maintain existing hardware profiles (cpu, gpu-nvidia, gpu-amd)
   - Add functional profiles (core, n8n, mcp, ai, utility)
   - Determine which services need multiple profiles

### Phase 2: Docker Compose Reorganization

1. **Update docker-compose.yml**

```yaml
# Example structure to implement
services:
  # Core Infrastructure
  nginx:
    image: nginx:alpine
    profiles: ["core", "mcp", "n8n", "ai"]
    # existing configuration...

  postgres:
    image: postgres:16-alpine
    profiles: ["core", "n8n", "mcp", "ai"]
    # existing configuration...

  # N8N Services
  n8n-import:
    <<: *service-n8n
    profiles: ["n8n"]
    # existing configuration...

  n8n:
    <<: *service-n8n
    profiles: ["n8n"]
    # existing configuration...

  # MCP Services
  mcp-memory:
    build: ./mcp/memory
    profiles: ["mcp", "cpu", "gpu-nvidia", "gpu-amd"]
    # existing configuration...

  mcp-seqthinking:
    image: mcp/sequentialthinking:latest
    profiles: ["mcp", "gpu-nvidia"]
    # existing configuration...

  # AI/ML Services
  qdrant:
    image: qdrant/qdrant
    profiles: ["ai", "cpu", "gpu-nvidia", "gpu-amd"]
    # existing configuration...

  ollama-cpu:
    profiles: ["ai", "cpu"]
    <<: *service-ollama
    # existing configuration...

  ollama-gpu:
    profiles: ["ai", "gpu-nvidia"]
    <<: *service-ollama
    # existing configuration...

  ollama-gpu-amd:
    profiles: ["ai", "gpu-amd"]
    <<: *service-ollama
    # existing configuration...

  # Utility Services
  crawl4ai:
    build:
      context: ./crawl4ai
      dockerfile: Dockerfile
    profiles: ["utility", "gpu-nvidia"]
    # existing configuration...
```

2. **Test Basic Configuration**
   - Verify that all services can start with their new profiles
   - Ensure dependencies are correctly set up

### Phase 3: Script Creation

1. **Directory Structure Setup**
```
/hosted-n8n/
└── scripts/
    ├── start-core.sh
    ├── start-n8n.sh
    ├── start-mcp.sh
    ├── start-ai.sh
    ├── start-all.sh
    ├── start-utility.sh
    └── down-all.sh
```

2. **Create Helper Scripts**

Create each script file with the appropriate commands:

**start-core.sh**
```bash
#!/bin/bash
# Start core infrastructure services
docker compose -p core --profile core up -d
echo "Core infrastructure services started"
```

**start-n8n.sh**
```bash
#!/bin/bash
# Start N8N services with core dependencies
docker compose -p n8n --profile n8n --profile core up -d
echo "N8N services started"
```

**start-mcp.sh**
```bash
#!/bin/bash
# Determine hardware configuration
if [ "$1" == "nvidia" ]; then
  HW_PROFILE="gpu-nvidia"
elif [ "$1" == "amd" ]; then
  HW_PROFILE="gpu-amd"
else
  HW_PROFILE="cpu"
fi

# Start MCP services with hardware profile
docker compose -p mcp --profile mcp --profile $HW_PROFILE up -d
echo "MCP services started with $HW_PROFILE profile"
```

**start-ai.sh**
```bash
#!/bin/bash
# Determine hardware configuration
if [ "$1" == "nvidia" ]; then
  HW_PROFILE="gpu-nvidia"
elif [ "$1" == "amd" ]; then
  HW_PROFILE="gpu-amd"
else
  HW_PROFILE="cpu"
fi

# Start AI services with hardware profile
docker compose -p ai --profile ai --profile $HW_PROFILE up -d
echo "AI services started with $HW_PROFILE profile"
```

**start-utility.sh**
```bash
#!/bin/bash
# Start utility services
docker compose -p utility --profile utility up -d
echo "Utility services started"
```

**start-all.sh**
```bash
#!/bin/bash
# Determine hardware configuration
if [ "$1" == "nvidia" ]; then
  HW_PROFILE="gpu-nvidia"
elif [ "$1" == "amd" ]; then
  HW_PROFILE="gpu-amd"
else
  HW_PROFILE="cpu"
fi

# Start all services with hardware profile
docker compose -p hosted-n8n --profile core --profile n8n --profile mcp --profile ai --profile utility --profile $HW_PROFILE up -d
echo "All services started with $HW_PROFILE profile"
```

**down-all.sh**
```bash
#!/bin/bash
# Stop all containers across all projects
docker compose -p core down
docker compose -p n8n down
docker compose -p mcp down
docker compose -p ai down
docker compose -p utility down
docker compose -p hosted-n8n down
echo "All services stopped"
```

3. **Make Scripts Executable**
```bash
chmod +x scripts/*.sh
```

### Phase 4: Testing

1. **Test Each Component**
   - Test starting/stopping core services
   - Test starting/stopping n8n services
   - Test starting/stopping mcp services with different hardware profiles
   - Test starting/stopping ai services with different hardware profiles
   - Test utility services

2. **Test Integrated Functionality**
   - Verify that services started with different project names can communicate
   - Verify that health checks work properly
   - Test failure scenarios and recovery

3. **Performance Validation**
   - Verify resource usage is as expected
   - Ensure startup/shutdown times are reasonable

### Phase 5: Documentation

1. **Update Documentation**
   - Create a README.md in the scripts directory
   - Update the main project documentation
   - Document the profile strategy

2. **Create Usage Examples**
   - Document common usage patterns
   - Provide troubleshooting tips

## Expected Outcomes

After implementation, the docker-compose.yml file will be better organized with:

- Clear service grouping through profiles
- Better organization in Docker UI through project names
- Simplified operation through helper scripts

The new setup will provide:
- Flexibility to run different hardware configurations
- Cleaner organization in Docker UI
- Easier management of service groups
- Better documentation for the team

## Rollback Plan

If issues arise, a rollback plan can be implemented:

1. Keep a backup of the original docker-compose.yml file
2. Create a rollback script to restore the original configuration
3. Document steps to manually revert to the previous setup 