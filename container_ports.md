# Container Port Mappings and Configurations

## Core Services

### n8n
- **Container Name**: n8n
- **Image**: n8nio/n8n:latest
- **Exposed Ports**: 
  - 5678 (Internal)
  - 5679 (Internal - Task Broker)
- **Config Files**: 
  - `docker-compose.yml`
  - `nginx/sites-enabled/n8n.conf`

### Nginx
- **Container Name**: nginx-proxy
- **Image**: nginx:alpine
- **Exposed Ports**:
  - 8080:80
  - 8443:443
- **Config Files**:
  - `docker-compose.yml`
  - `nginx/sites-enabled/default.conf`
  - `nginx/sites-enabled/00-http-redirect.conf`

### PostgreSQL
- **Container Name**: postgres
- **Image**: postgres:16-alpine
- **Exposed Ports**:
  - 5432 (Internal)
- **Config Files**:
  - `docker-compose.yml`

### Qdrant
- **Container Name**: qdrant
- **Image**: qdrant/qdrant
- **Exposed Ports**:
  - 6333-6334 (Internal)
- **Config Files**:
  - `docker-compose.yml`
  - `nginx/sites-enabled/qdrant.conf`

## MCP Services

### MCP Memory
- **Container Name**: mcp-memory
- **Image**: mcp/memory:latest
- **Exposed Ports**:
  - 8081:8080 (External:Internal)
- **Config Files**:
  - `docker-compose.yml`
  - `nginx/sites-enabled/mcp.conf`
- **Dependencies**:
  - Qdrant (6333)
- **Nginx Configuration**:
  - Upstream: `mcp-memory:8080`
  - Location: `/memory/`
  - WebSocket support enabled
- **Volume Mounts**:
  - `./mcp/logs:/logs`
  - `./mcp/memory/data:/data`

### MCP Sequential Thinking
- **Container Name**: mcp-seqthinking
- **Image**: mcp/sequentialthinking:latest
- **Exposed Ports**:
  - 8082:8080 (External:Internal)
- **Config Files**:
  - `docker-compose.yml`
  - `nginx/sites-enabled/mcp.conf`
- **Nginx Configuration**:
  - Upstream: `mcp-seqthinking:8080`
  - Location: `/seqthinking/`
  - WebSocket support enabled

## AI Services

### Ollama
- **Container Name**: ollama (CPU/GPU variants)
- **Image**: ollama/ollama:latest
- **Exposed Ports**:
  - 11434 (Internal)
- **Config Files**:
  - `docker-compose.yml`
  - `nginx/sites-enabled/ollama.conf`

### Crawl4AI
- **Container Name**: crawl4ai
- **Image**: crawl4ai:latest
- **Exposed Ports**:
  - 11235:11235
- **Config Files**:
  - `docker-compose.yml`
  - `nginx/sites-enabled/crawl4ai.conf`

## Supabase Services

### Supabase Storage
- **Container Name**: supabase-storage
- **Image**: supabase/storage-api:v1.14.5
- **Exposed Ports**:
  - 5000 (Internal)
- **Config Files**:
  - `docker-compose.yml`
  - `nginx/sites-enabled/supabase.conf`

### Supabase Kong
- **Container Name**: supabase-kong
- **Image**: kong:2.8.1
- **Exposed Ports**:
  - 8000:8000
  - 8001 (Internal)
  - 8443:8443
  - 8444 (Internal)
- **Config Files**:
  - `docker-compose.yml`
  - `nginx/sites-enabled/supabase.conf`

### Supabase Pooler
- **Container Name**: supabase-pooler
- **Image**: supabase/supavisor:1.1.56
- **Exposed Ports**:
  - 5432:5432
  - 6543:6543
- **Config Files**:
  - `docker-compose.yml`

### Supabase Analytics
- **Container Name**: supabase-analytics
- **Image**: supabase/logflare:1.4.0
- **Exposed Ports**:
  - 4000:4000
- **Config Files**:
  - `docker-compose.yml`

## Port Conflicts and Dependencies

### Known Port Dependencies
- Nginx (8080) → n8n (5678)
- Nginx (8080) → MCP Memory (8080)
- Nginx (8080) → Qdrant (6333)
- n8n → Postgres (5432)
- n8n → Ollama (11434)
- Crawl4AI → Qdrant (6333)
- Crawl4AI → Ollama (11434)

### Potential Port Conflicts
1. **MCP Services Port Resolution**:
   - MCP Memory: 8081:8080 (External:Internal)
   - MCP Sequential Thinking: 8082:8080 (External:Internal)
   - Both services now have unique external ports
   - Internal port 8080 is consistent across services
   - Nginx reverse proxy handles routing via paths
   - No conflicts with Nginx's 8080 port

## Configuration Details

### Nginx Reverse Proxy Setup
- SSL enabled on port 443
- Server name: mcp.mulder.local
- Rate limiting enabled (api_limit zone with burst=10)
- Health check endpoint: `/health`
- Separate access and error logs for MCP services
- WebSocket support configured for both MCP services

### Network Architecture
- All services run on 'lab' network
- Internal communication uses Docker DNS resolution
- No direct host port mappings for MCP services
- Nginx handles all external access through reverse proxy

## Notes
- Internal ports are only accessible within the Docker network
- External ports are mapped to the host system
- Some services use internal Docker DNS resolution for communication
- Port conflicts should be resolved by either:
  1. Changing the external port mapping
  2. Using internal Docker networking only
  3. Updating nginx reverse proxy configuration 