#!/bin/bash
# down-n8n.sh - Stop N8N workflow services
#
# This script stops N8N services and removes their nginx configuration.

echo "Stopping N8N services..."

# Stop N8N services
docker compose -p n8n down

# Check if services were stopped successfully
if [ $? -eq 0 ]; then
  echo "Disabling nginx configuration for n8n..."
  # Remove symbolic link for n8n.conf in sites-enabled
  sudo rm -f /home/groot/nginx/sites-enabled/n8n.conf
  # Restart nginx to apply the configuration
  docker restart nginx-proxy
  echo "Nginx configuration for n8n disabled and nginx restarted."
else
  echo "Failed to stop N8N services. Nginx configuration not disabled."
fi

echo "N8N services stopped."
echo "You can verify with: docker ps | grep n8n" 