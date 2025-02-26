# MCP Nginx Configuration Audit

## Overview
This document outlines the configuration misalignments and security concerns found in the MCP (Memory and Sequential Thinking) services' nginx configuration compared to other working services in the environment.

## Configuration Misalignments

### 1. Server Block Structure
**Current:**
```nginx
server_name mcp.mulder.local mcp-memory.mulder.local mcp-seqthinking.mulder.local;
```
**Working Pattern:**
```nginx
server_name ollama.mulder.local;
```
**Fix:**
- Split into separate server blocks for each subdomain
- Each service should have its own dedicated configuration
- Follows the single responsibility principle

### 2. Upstream Configuration
**Current:**
```nginx
upstream mcp-memory {
    server mcp-memory:8080;
    keepalive 32;
}
```
**Working Pattern:**
```nginx
upstream ollama {
    server ollama:11434;
}
```
**Fix:**
- Remove keepalive directive
- Simplify upstream configuration
- Align with working services pattern

### 3. Proxy Configuration Method
**Current:**
```nginx
location /memory/ {
    proxy_pass http://mcp-memory/;
    include /etc/nginx/snippets/proxy-params.conf;
}
```
**Working Pattern:**
```nginx
location / {
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    # ... (explicit settings)
    proxy_pass http://ollama;
}
```
**Fix:**
- Define proxy settings explicitly in location block
- Remove dependency on included proxy-params.conf
- Ensures configuration clarity and maintainability

### 4. SSL Parameters Include
**Current:**
```nginx
include /etc/nginx/snippets/ssl-params.conf;
```
**Working Pattern:**
```nginx
# include /etc/nginx/snippets/ssl-params.conf;  # Commented out
```
**Fix:**
- Comment out ssl-params.conf include
- Rely on global SSL configuration from nginx.conf
- Prevents potential parameter conflicts

### 5. Location Block Structure
**Current:**
```nginx
location /memory/ {
    proxy_pass http://mcp-memory/;
}
```
**Working Pattern:**
```nginx
location / {
    if ($frontend_allowed = 0) {
        return 403;
    }
    proxy_pass http://ollama;
}
```
**Fix:**
- Add access control checks
- Use root location block pattern
- Implement consistent security checks

### 6. Timeouts and Buffer Settings
**Current:**
- No specific timeout settings

**Working Pattern:**
```nginx
proxy_connect_timeout 300s;
proxy_send_timeout 300s;
proxy_read_timeout 300s;
client_max_body_size 50M;
```
**Fix:**
- Add appropriate timeout settings
- Configure buffer sizes based on service needs
- Align with service requirements

## Security Findings

### 1. Certificate and SANs Configuration
**Issue:**
- MCP domains not explicitly listed in openssl.conf
- Relying on wildcard certificate

**Fix:**
```conf
[alt_names]
DNS.1 = mulder.local
# ... existing entries ...
DNS.11 = mcp-memory.mulder.local
DNS.12 = mcp-seqthinking.mulder.local
```

### 2. Network Access Control
**Issue:**
- Not utilizing `$frontend_allowed` variable
- Missing backend network restrictions

**Fix:**
```nginx
location / {
    if ($frontend_allowed = 0) {
        return 403;
    }
    if ($backend_allowed = 0) {
        return 403;
    }
    # ... rest of configuration
}
```

### 3. SSL Configuration Duplication
**Issue:**
- Multiple SSL parameter definitions
- Potential conflicts in settings

**Fix:**
- Remove ssl-params.conf include
- Rely on global SSL configuration
- Document any service-specific SSL requirements

### 4. Rate Limiting
**Issue:**
- Using generic api_limit zone
- Multiple endpoints need different limits

**Fix:**
```nginx
# In nginx.conf
limit_req_zone $binary_remote_addr zone=mcp_memory_limit:10m rate=15r/s;
limit_req_zone $binary_remote_addr zone=mcp_seqthinking_limit:10m rate=10r/s;

# In server block
location /memory/ {
    limit_req zone=mcp_memory_limit burst=10 nodelay;
}
```

### 5. Security Headers
**Issue:**
- Duplicate header definitions
- Potential conflicts

**Fix:**
- Remove security-headers.conf include
- Use global headers from nginx.conf
- Add only service-specific headers in location blocks

### 6. WebSocket Security
**Issue:**
- Potential conflict with global upgrade mapping
- Inconsistent WebSocket configuration

**Fix:**
```nginx
location /memory/ {
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    # ... rest of configuration
}
```

### 7. Docker Network Security
**Issue:**
- Not utilizing backend network restrictions
- Missing network segmentation

**Fix:**
- Define MCP services in backend network (172.20.1.0/24)
- Implement proper network segmentation
- Update docker-compose.yml network configuration

### 8. Logging Configuration
**Issue:**
- Basic logging configuration
- Missing service-specific fields

**Fix:**
```nginx
log_format mcp_json escape=json '{'
    '"timestamp": "$time_iso8601",'
    '"service": "mcp",'
    '"component": "$uri",'
    # ... standard fields ...
    '"response_time": "$upstream_response_time"'
'}';

access_log /var/log/nginx/mcp-access.log mcp_json;
```

### 9. Client Body Size Limits
**Issue:**
- Using global limit
- No service-specific limits

**Fix:**
```nginx
# Add in location blocks based on service needs
location /memory/ {
    client_max_body_size 20M;
    # ... rest of configuration
}
```

### 10. Proxy Cache Settings
**Issue:**
- Not utilizing available caching
- Missing service-specific cache configuration

**Fix:**
```nginx
# Add where caching is appropriate
location /memory/ {
    proxy_cache assets_cache;
    proxy_cache_valid 200 60m;
    proxy_cache_use_stale error timeout;
    # ... rest of configuration
}
```

## Implementation Priority
1. Network Security (Access Control, Docker Network)
2. SSL/TLS Configuration
3. Server Block Structure
4. Rate Limiting
5. Proxy and Location Configuration
6. Logging and Monitoring
7. Performance Optimizations (Caching, Timeouts)

## Additional Recommendations
1. Implement health checks for both services
2. Add monitoring endpoints
3. Consider implementing circuit breakers
4. Document service-specific requirements
5. Create backup configurations
6. Implement proper error handling 

## Implementation Progress

| Configuration Item | Memory Status | Sequential Status | Notes |
|-------------------|---------------|-------------------|--------|
| 1. Server Block Structure | ✅ Complete | 🔄 Pending | Each MCP service needs its own .conf file |
| 2. Upstream Configuration | ⏭️ Skipped | ⏭️ Skipped | As per user request, skipping upstream changes |
| 3. Proxy Configuration Method | ✅ Complete | 🔄 Pending | Explicit proxy settings in location block |
| 4. SSL Parameters | ✅ Complete | 🔄 Pending | Use global SSL config, keep cert paths |
| 5. Location Block Structure | ✅ Complete | 🔄 Pending | Include access controls and root location |
| 6. Timeouts and Buffer Settings | ✅ Complete | 🔄 Pending | 300s timeouts for long operations |
| **Security Findings** | | | |
| 1. Certificate and SANs Configuration | ✅ Complete | 🔄 Pending | Added explicit SAN entry for mcp-memory |
| 2. Network Access Control | ✅ Complete | 🔄 Pending | Dual-layer frontend/backend access control |
| 3. SSL Configuration Duplication | ✅ Complete | 🔄 Pending | Use global SSL configuration only |
| 4. Rate Limiting | ✅ Complete | 🔄 Pending | Each service needs its own limit zone |
| 5. Security Headers | ✅ Complete | 🔄 Pending | Use security-headers.conf include |
| 6. WebSocket Security | ✅ Complete | 🔄 Pending | Proper upgrade and connection handling |
| 7. Docker Network Security | ✅ Complete | 🔄 Pending | Added to mcp_backend network with proper segmentation |
| 8. Logging Configuration | ✅ Complete | 🔄 Pending | Using unified_json format |
| 9. Client Body Size Limits | ✅ Complete | 🔄 Pending | Set appropriate size per service |
| 10. Proxy Cache Settings | ✅ Complete | 🔄 Pending | Configure based on service needs |

### Global Tasks
These tasks affect all MCP containers and should be completed once:
- Certificate and SANs Configuration (✅ Memory Complete)
- Docker Network Security (✅ Memory Complete)

Legend:
- ✅ Complete
- 🔄 Pending
- ⏭️ Skipped
- ❌ Failed/Issues 