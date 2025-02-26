#!/bin/bash
# down-all.sh - Stop all Docker services
#
# This script stops all running containers across all projects
# and removes the containers, networks, and volumes.

echo "Stopping all containers..."
docker compose -p core down
docker compose -p n8n down
docker compose -p mcp down
docker compose -p ai down
docker compose -p utility down
docker compose -p hosted-n8n down

echo "Removing all service-specific nginx configurations..."
# Keep only core configurations in sites-enabled
sudo find /home/groot/nginx/sites-enabled/ -type f -not -name "00-http-redirect.conf" -not -name "default.conf" -not -name "supabase.conf" -exec rm -f {} \;
# Restart nginx to apply the configuration
docker restart nginx-proxy
echo "All service-specific nginx configurations removed and nginx restarted."

echo "All services stopped successfully." 