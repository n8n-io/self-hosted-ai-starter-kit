#!/bin/bash
# start-ai.sh - Start AI/ML services with hardware profile
#
# Usage: ./start-ai.sh [nvidia|amd|cpu]
# Default: cpu
#
# This script starts all AI/ML services (ollama, qdrant) using the appropriate 
# hardware profile in a project named "ai" for better Docker UI organization.

# Determine hardware configuration
if [ "$1" == "nvidia" ]; then
  HW_PROFILE="gpu-nvidia"
elif [ "$1" == "amd" ]; then
  HW_PROFILE="gpu-amd"
else
  HW_PROFILE="cpu"
fi

echo "Starting AI services with $HW_PROFILE profile..."
docker compose -p ai --profile ai --profile $HW_PROFILE up -d

# Check if AI services started successfully
if [ $? -eq 0 ]; then
  echo "Enabling nginx configuration for AI services..."
  # Create symbolic links for ollama.conf and qdrant.conf in sites-enabled
  sudo ln -sf /home/groot/nginx/sites-available/ollama.conf /home/groot/nginx/sites-enabled/ollama.conf
  sudo ln -sf /home/groot/nginx/sites-available/qdrant.conf /home/groot/nginx/sites-enabled/qdrant.conf
  # Restart nginx to apply the configuration
  docker restart core-nginx
  echo "Nginx configuration for AI services enabled and nginx restarted."
else
  echo "Failed to start AI services. Nginx configuration not enabled."
fi

echo "AI services started successfully with $HW_PROFILE profile." 