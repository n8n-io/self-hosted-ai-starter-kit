# Docker Compose Scripts

This directory contains helper scripts for managing the hosted-n8n project's Docker services using a profile-based approach with project names for better organization.

## Script Overview

| Script | Description | Usage |
|--------|-------------|-------|
| `start-core.sh` | Starts core infrastructure services | `./start-core.sh` |
| `start-n8n.sh` | Starts N8N services and dependencies | `./start-n8n.sh` |
| `start-mcp.sh` | Starts MCP services with hardware profile | `./start-mcp.sh [nvidia\|amd\|cpu]` |
| `start-ai.sh` | Starts AI/ML services with hardware profile | `./start-ai.sh [nvidia\|amd\|cpu]` |
| `start-utility.sh` | Starts utility services | `./start-utility.sh` |
| `start-all.sh` | Starts all services with hardware profile | `./start-all.sh [nvidia\|amd\|cpu]` |
| `down-n8n.sh` | Stops N8N services and removes nginx config | `./down-n8n.sh` |
| `down-ai.sh` | Stops AI services and removes nginx config | `./down-ai.sh` |
| `down-all.sh` | Stops all services and removes nginx configs | `./down-all.sh` |

## Common Usage Patterns

### Starting the Full Stack (Nvidia GPU)

```bash
./start-all.sh nvidia
```

### Starting Minimal Services (CPU only)

```bash
./start-core.sh
./start-n8n.sh
```

### Starting MCP Services with GPU

```bash
./start-core.sh  # Start core infrastructure
./start-ai.sh nvidia  # Start AI services with NVIDIA GPU
./start-mcp.sh nvidia  # Start MCP services with NVIDIA GPU
```

## Container Organization

These scripts organize the Docker containers into logical projects:

1. **core** - Core infrastructure (nginx, postgres)
2. **n8n** - N8N workflow automation services
3. **mcp** - Memory and sequential thinking services
4. **ai** - AI services (ollama, qdrant)
5. **utility** - Utility services like crawl4ai

## Hardware Profiles

Three hardware profiles are supported:

1. **cpu** - CPU-only mode 
2. **gpu-nvidia** - NVIDIA GPU mode
3. **gpu-amd** - AMD GPU mode

## Nginx Configuration Management

The scripts now include automatic management of nginx configuration files:

1. **Start Scripts** - When services are started, their corresponding nginx configuration is enabled by creating symbolic links in `/home/groot/nginx/sites-enabled/`.

2. **Stop Scripts** - When services are stopped, their nginx configuration is disabled by removing the symbolic links.

3. **Core Services** - Core nginx configurations (`00-http-redirect.conf`, `default.conf`, `supabase.conf`) are always kept enabled.

This approach ensures that nginx only tries to proxy to services that are actually running, preventing startup failures due to missing upstream services.

## Notes

- The scripts use project names (`-p` flag) for better organization in Docker UI
- Services are grouped by functional profiles for flexibility
- Hardware-specific profiles determine which versions of services are started
- All scripts assume they are run from the project root directory 