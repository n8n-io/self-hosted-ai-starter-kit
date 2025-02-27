#!/bin/bash
# start-n8n.sh - Start N8N workflow services
#
# This script starts N8N services with the "n8n" profile
# in a project named "n8n" for better Docker UI organization.

# Check if core services are running
if ! docker ps | grep -q "core-nginx-1"; then
  echo "Core nginx is not running. Starting core infrastructure..."
  ./scripts/start-core.sh
fi

echo "Starting N8N services..."

# Determine hardware configuration
if [ "$1" == "nvidia" ]; then
  HW_PROFILE="gpu-nvidia"
elif [ "$1" == "amd" ]; then
  HW_PROFILE="gpu-amd"
else
  HW_PROFILE="cpu"
fi

# Start N8N services with hardware profile, explicitly listing services to avoid nginx
docker compose -f docker-compose.profile.yml -p n8n --profile n8n --profile $HW_PROFILE up -d --no-deps n8n n8n-import

# Check if N8N services started successfully
if [ $? -eq 0 ]; then
  echo "Enabling nginx configuration for n8n..."
  # Create symbolic link for n8n.conf in sites-enabled
  sudo ln -sf /home/groot/nginx/sites-available/n8n.conf /home/groot/nginx/sites-enabled/n8n.conf
  # Restart core nginx to apply the configuration
  if docker ps | grep -q "core-nginx-1"; then
    echo "Restarting core nginx to apply configuration..."
    docker restart core-nginx-1
    echo "Nginx configuration for n8n enabled and core nginx restarted."
  else
    echo "Warning: core-nginx-1 container not found. Configuration enabled but nginx not restarted."
  fi
else
  echo "Failed to start N8N services. Nginx configuration not enabled."
fi

echo "N8N services started with $HW_PROFILE profile."
echo "You can verify their status with: docker ps | grep n8n" 