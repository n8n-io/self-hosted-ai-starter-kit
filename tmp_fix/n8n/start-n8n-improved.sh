#!/bin/bash
# Improved start-n8n.sh script without sudo commands
# This script works in a rootless Docker environment

set -e

# Default to GPU-NVIDIA profile if not specified
HW_PROFILE="${1:-gpu-nvidia}"
echo "Starting n8n services with hardware profile: $HW_PROFILE"

# Validate hardware profile
if [[ ! "$HW_PROFILE" =~ ^(cpu|gpu-nvidia|gpu-amd)$ ]]; then
  echo "Error: Invalid hardware profile. Must be one of: cpu, gpu-nvidia, gpu-amd"
  exit 1
fi

# Check if core services are running
if ! docker ps | grep -q "core-postgres-1"; then
  echo "Core services aren't running. Starting core infrastructure first..."
  ./home/groot/Github/hosted-n8n/tmp_fix/n8n/start-core-improved.sh
  sleep 3
fi

# Start n8n services with --no-deps to prevent starting dependencies
echo "Starting n8n services..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p n8n --profile n8n --profile $HW_PROFILE up -d --no-deps n8n n8n-import

# Check if n8n started successfully
if docker ps | grep -q "n8n" && ! docker ps | grep -q "n8n.*Unhealthy"; then
  echo "N8N services started successfully!"
  
  # Copy the n8n.conf file (without sudo)
  echo "Copying n8n nginx configuration..."
  cp -f /home/groot/Github/hosted-n8n/tmp_fix/n8n/n8n.conf /home/groot/nginx/sites-available/n8n.conf
  
  # Create symlink (without sudo)
  echo "Creating symlink for n8n.conf..."
  ln -sf /home/groot/nginx/sites-available/n8n.conf /home/groot/nginx/sites-enabled/n8n.conf
  
  # Restart nginx container
  echo "Restarting nginx to apply new configuration..."
  docker restart core-nginx
  
  echo "N8N deployment completed successfully."
else
  echo "Warning: N8N services may have issues starting. Check logs with: docker logs n8n"
  echo "Not enabling nginx configuration for n8n since services are not healthy."
fi 