#!/bin/bash
# rollback.sh - Revert to original Docker configuration
#
# This script will restore the original docker-compose.yml file
# and remove any profiles-based configuration.

echo "Rolling back to original configuration..."

# Check if backup exists
if [ -f docker-compose.yml.bak ]; then
    echo "Restoring from backup docker-compose.yml.bak..."
    cp docker-compose.yml.bak docker-compose.yml
    echo "Original docker-compose.yml restored."
else
    echo "Error: Backup file docker-compose.yml.bak not found."
    echo "Manual recovery may be necessary."
    exit 1
fi

# Stop all containers from all project namespaces
echo "Stopping all running containers..."
docker compose -p core down 2>/dev/null || true
docker compose -p n8n down 2>/dev/null || true
docker compose -p mcp down 2>/dev/null || true
docker compose -p ai down 2>/dev/null || true
docker compose -p utility down 2>/dev/null || true
docker compose -p hosted-n8n down 2>/dev/null || true

# Start with original configuration
echo "Starting services with original configuration..."
docker compose up -d

echo "Rollback completed. System restored to original configuration."
echo "Note: You may need to manually restart specific services or profiles if needed." 