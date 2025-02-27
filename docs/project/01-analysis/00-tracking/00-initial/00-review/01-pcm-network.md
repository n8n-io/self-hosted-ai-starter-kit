# Profile-Based Compose Migration: Network Configuration Summary

**Version:** 1.0  
**Date:** February 26, 2025  
**Author:** System Administrator  
**Status:** Initial Documentation  

## Overview

This document provides a comprehensive summary of the network configuration relevant to the profile-based Docker Compose migration. Understanding the network topology is critical for ensuring proper service communication across different project namespaces and resolving the current nginx restart loop issue.

## Network Types

The system operates across three distinct network types:

### 1. Secure Private Network (External)

- **Purpose**: Primary production network where both server and clients reside
- **Security**: Secured and isolated from public internet
- **Access Control**: Restricted to authorized systems only
- **Usage**: Clients access the hosted services through this network
- **IP Range**: 10.1.10.0/24
- **Key Systems**:
  - Server: 10.1.10.111 (hosting Docker services)
  - Client systems: Various IP addresses in the same subnet

### 2. Local Server Network

- **Purpose**: Server's internal networking stack
- **Components**: Includes localhost/loopback interfaces and physical network interfaces
- **Hostname Resolution**: Uses /etc/hosts for local name resolution
- **IP Addresses**:
  - Loopback: 127.0.0.1
  - Physical interface: Same as Secure Private Network (10.1.10.111)

### 3. Docker Networks

- **Primary Network**: `hosted-n8n_lab` (external network)
  - **Type**: User-defined bridge network
  - **Created**: External to Docker Compose
  - **Purpose**: Shared communication channel for all services
  - **Scope**: Used by all service groups across multiple project namespaces

- **Default Project Networks**:
  - Created automatically with Docker Compose project names
  - Isolated by default, but services connect to the shared external network
  - Project-specific networks:
    - `core_default`
    - `n8n_default`
    - `mcp_default`
    - `ai_default`
    - `utility_default`

## Host File Configuration

The server uses Subject Alternative Name (SAN) entries in its host file to support proper name resolution for services. This is especially important for SSL/TLS certificate validation and cross-service communication.

### Current Host File Configuration

```
# localhost
127.0.0.1 localhost
127.0.1.1 hosted-n8n

# Docker Services - External Access
10.1.10.111 n8n.internal.example.com
10.1.10.111 mcp.internal.example.com
10.1.10.111 qdrant.internal.example.com
10.1.10.111 ollama.internal.example.com

# Service Cross-Communication
# The following entries support service discovery across project namespaces
10.1.10.111 postgres
10.1.10.111 n8n
10.1.10.111 mcp-memory
10.1.10.111 mcp-seqthinking
10.1.10.111 qdrant
10.1.10.111 ollama
```

### SAN Configuration in SSL Certificates

For SSL/TLS certificates used by nginx, the following Subject Alternative Names should be included:

```
DNS:n8n.internal.example.com
DNS:mcp.internal.example.com
DNS:qdrant.internal.example.com
DNS:ollama.internal.example.com
DNS:localhost
IP:10.1.10.111
IP:127.0.0.1
```

## Network Challenges in Profile-Based Migration

The transition to a profile-based approach with separate project namespaces introduces several network-related challenges:

### 1. Service Discovery Across Projects

**Issue**: Services deployed in different project namespaces have different DNS names within Docker networks.

**Examples**:
- Original configuration: Service "postgres" accessible as "postgres"
- New configuration: Service "postgres" in core project accessible as "core-postgres-1"

**Resolution**:
- Ensure consistent hostname resolution using the external network
- Consider using the SAN entries in the host file for reliable cross-project communication
- Update service configurations to use consistent hostnames

### 2. Nginx Proxy Routing

**Issue**: Nginx proxy must be able to route to services regardless of which project namespace they're in.

**Current Configuration**:
- Upstream directives in nginx configuration reference service names directly (e.g., `upstream n8n { server n8n:5678; }`)
- This causes failures when the service isn't running or the name doesn't resolve

**Improved Approach**:
- Use project-aware hostnames in nginx configuration
- Implement failover mechanisms for all upstream definitions
- Consider using the server's actual IP address and port mappings for more direct routing

### 3. Container Naming and Service Resolution

**Issue**: Container names include project prefixes which may break existing hostname references.

**Examples**:
- Original: `nginx-proxy`, `postgres`, `n8n`
- New: `core-nginx-1`, `core-postgres-1`, `n8n-n8n-1`

**Resolution**:
- Ensure environment variables consistently use the correct hostnames
- Update hostname references in application configurations
- Leverage the host file SAN entries for consistent addressing

## Correct Syntax for Different Network Types

### 1. External Network Declaration in Docker Compose

```yaml
networks:
  lab:
    external: true
    name: hosted-n8n_lab
```

### 2. Service Network Configuration

```yaml
services:
  nginx:
    networks:
      - lab
    # Other configuration...
    
  postgres:
    networks:
      - lab
    # Other configuration...
```

### 3. Nginx Upstream Configuration with Project Awareness

```nginx
# For n8n in n8n project namespace
upstream n8n_backend {
    # Try project-namespaced name first
    server n8n-n8n-1:5678 max_fails=3 fail_timeout=5s;
    # Fallback to hostname defined in host file
    server n8n:5678 backup;
    # Final fallback for maintenance page
    server 127.0.0.1:81 backup;
}
```

### 4. Environment Variable Consistency

Ensure environment variables maintain consistency by mapping to hostnames that will resolve correctly:

```yaml
services:
  n8n:
    environment:
      - DB_POSTGRESDB_HOST=postgres
      # NOT core-postgres-1
    # Other configuration...
```

## Network Verification Tasks

As part of the migration, the following network-related verification tasks should be completed:

1. **DNS Resolution**:
   - Verify service discovery works across project namespaces
   - Test hostname resolution from different containers
   - Confirm SAN entries are correctly resolving

2. **Nginx Routing**:
   - Validate upstream routing to services in different project namespaces
   - Test failover mechanisms when services are unavailable
   - Verify SSL/TLS certificate validation with SANs

3. **Cross-Service Communication**:
   - Verify services can communicate across project boundaries
   - Test database connections from applications
   - Validate API calls between services

## Conclusion

The network configuration is a critical aspect of the profile-based Docker Compose migration. By understanding the three network types (secure private network, local server network, and Docker networks) and implementing the correct syntax for each, we can ensure seamless communication between services across different project namespaces.

The SAN configuration in the host file provides a consistent addressing mechanism that can help bridge the gap between the original configuration and the profile-based approach. By leveraging these SAN entries and implementing robust failover mechanisms in nginx, we can achieve the goal of making nginx completely agnostic to other services while maintaining proper routing capabilities.
