# Enhanced N8N Self-Hosted AI Starter Kit

This is an enhanced version of the n8n self-hosted AI starter kit with additional features for production use.

## Features Added

### 1. HTTPS Access via Ngrok
- Secure HTTPS access to n8n using ngrok tunneling
- Configurable domain support
- Webhook URL automatically configured

### 2. External PostgreSQL Access
- PostgreSQL exposed on port 5432 for external connections
- Useful for database management tools and backups

### 3. Enhanced N8N Container
The n8n container now includes:
- **dotenv-vault**: For secure environment variable management
- **GitHub CLI (gh)**: For Git operations and GitHub integration
- **Docker & Docker Compose**: For container management from within n8n
- **Auto-update service**: Automatically pulls latest n8n images and updates

### 4. Flexible Import System
- Supports custom import paths via `N8N_CUSTOM_IMPORT_PATH` environment variable
- Falls back to demo data if custom path is not specified
- Bind mount to backup directory: `/mnt/c/users/smart/.n8n/storage/volumes/projects/e8ZY6SWt84kxXzMl/backup`

### 5. Auto-Update Service
- Periodically checks for and applies n8n updates
- Configurable via `AUTO_UPDATE_ENABLED` and `AUTO_UPDATE_INTERVAL`
- Zero-downtime updates using docker-compose

## Configuration

### Environment Variables

Add the following to your `.env` file:

```bash
# Ngrok configuration for HTTPS access
NGROK_AUTHTOKEN=your_ngrok_auth_token
NGROK_DOMAIN=your_custom_domain.ngrok.io

# Custom import path for workflows and credentials (optional)
N8N_CUSTOM_IMPORT_PATH=/mnt/c/users/smart/.n8n/storage/volumes/projects/e8ZY6SWt84kxXzMl/backup

# Auto-update configuration
AUTO_UPDATE_ENABLED=true
AUTO_UPDATE_INTERVAL=24h
```

### Ngrok Setup

1. Sign up for ngrok account at https://ngrok.com
2. Get your auth token from the dashboard
3. (Optional) Set up a custom domain
4. Add the auth token and domain to your `.env` file

## Usage

### Quick Start

```bash
# Make the start script executable
chmod +x start.sh

# Run the enhanced stack
./start.sh
```

### Manual Start

```bash
# Build the custom n8n image
docker-compose build

# Start with appropriate GPU profile
docker-compose --profile cpu up -d          # For CPU-only
docker-compose --profile gpu-nvidia up -d   # For NVIDIA GPU
docker-compose --profile gpu-amd up -d      # For AMD GPU
```

## Access Points

- **N8N Web Interface**: http://localhost:5678
- **N8N HTTPS (via ngrok)**: https://your-domain.ngrok.io
- **Ngrok Dashboard**: http://localhost:4040
- **PostgreSQL**: localhost:5432
- **Qdrant Vector Database**: http://localhost:6333
- **Ollama API**: http://localhost:11434

## Services

### Core Services
- **postgres**: PostgreSQL database (exposed externally)
- **n8n**: Main n8n instance with enhanced tools
- **ngrok**: HTTPS tunnel service
- **qdrant**: Vector database for AI operations
- **ollama-***: Local LLM service (CPU/GPU variants)

### Utility Services
- **n8n-import**: Enhanced import service with flexible data sources
- **n8n-updater**: Automatic update service
- **ollama-pull-***: Initial model download services

## Docker Volumes

- `n8n_storage`: N8N application data
- `postgres_storage`: PostgreSQL data
- `ollama_storage`: Ollama models and data
- `qdrant_storage`: Qdrant vector database storage

## Bind Mounts

- `/mnt/c/users/smart/.n8n/storage/volumes/projects/e8ZY6SWt84kxXzMl/backup`: Custom backup directory
- `/var/run/docker.sock`: Docker socket for container management
- `./shared`: Shared data directory

## Security Notes

- The n8n container has access to the Docker socket for self-management
- GitHub token is configured for CLI operations
- Use ngrok auth tokens securely
- Consider firewall rules for exposed PostgreSQL port

## Troubleshooting

### Check Service Status
```bash
docker-compose ps
```

### View Logs
```bash
docker-compose logs -f n8n
docker-compose logs -f ngrok
```

### Restart Services
```bash
docker-compose restart n8n
```

### Manual Update
```bash
docker-compose pull n8n
docker-compose up -d n8n
```
