#!/bin/bash
# down-ai.sh - Stop AI/ML services
#
# This script stops AI/ML services (ollama, qdrant) and removes their nginx configurations.

echo "Stopping AI services..."

# Stop AI services
docker compose -p ai down

# Check if services were stopped successfully
if [ $? -eq 0 ]; then
  echo "Disabling nginx configuration for AI services..."
  # Remove symbolic links for ollama.conf and qdrant.conf in sites-enabled
  sudo rm -f /home/groot/nginx/sites-enabled/ollama.conf
  sudo rm -f /home/groot/nginx/sites-enabled/qdrant.conf
  # Restart nginx to apply the configuration
  docker restart nginx-proxy
  echo "Nginx configuration for AI services disabled and nginx restarted."
else
  echo "Failed to stop AI services. Nginx configuration not disabled."
fi

echo "AI services stopped."
echo "You can verify with: docker ps | grep ai" 