#!/bin/bash
# Improved start-core.sh script with better error handling
# This script ensures nginx can start independently of other services

set -e

echo "Starting core infrastructure services..."

# Ensure sites-enabled directory exists and is properly set up
echo "Setting up nginx configuration directories..."
mkdir -p /home/groot/nginx/html
mkdir -p /home/groot/nginx/sites-enabled

# Create a simple maintenance page if it doesn't exist
if [ ! -f "/home/groot/nginx/html/maintenance.html" ]; then
  echo "Creating maintenance page..."
  cat > /home/groot/nginx/html/maintenance.html << EOF
<!DOCTYPE html>
<html>
<head>
  <title>Service Maintenance</title>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 650px; margin: 0 auto; padding: 20px; }
    h1 { color: #e74c3c; }
    .container { background: #f9f9f9; border: 1px solid #ddd; padding: 20px; border-radius: 5px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Service Currently Unavailable</h1>
    <p>The requested service is currently unavailable or in maintenance mode. Please try again later.</p>
    <p>If this issue persists, please contact your system administrator.</p>
  </div>
</body>
</html>
EOF
fi

# Start with a minimal configuration to ensure nginx can start
echo "Setting up minimal nginx configuration..."
cp -f /home/groot/Github/hosted-n8n/tmp_fix/n8n/minimal.conf /home/groot/nginx/sites-enabled/default.conf

# Remove any potentially problematic configuration files
echo "Removing potentially problematic nginx configuration files..."
for config in n8n.conf mcp.conf qdrant.conf ollama.conf; do
  if [ -f "/home/groot/nginx/sites-enabled/$config" ]; then
    echo "Removing $config from sites-enabled..."
    rm -f "/home/groot/nginx/sites-enabled/$config"
  fi
done

# Start postgres first
echo "Starting postgres..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p core --profile core up -d postgres

# Wait for postgres to initialize
echo "Waiting for postgres to initialize..."
sleep 3

# Check if postgres is healthy
echo "Checking postgres health..."
if docker exec -it core-postgres-1 pg_isready -q; then
  echo "Postgres is healthy!"
else
  echo "Warning: Postgres may not be fully initialized yet"
fi

# Start nginx independently with minimal configuration
echo "Starting nginx with minimal configuration..."
docker compose -f /home/groot/Github/hosted-n8n/docker-compose.profile.yml -p core --profile core up -d core-nginx

# Check if nginx started successfully
echo "Checking nginx status..."
sleep 3
if docker ps | grep -q "core-nginx" && ! docker ps | grep -q "core-nginx.*Restarting"; then
  echo "Nginx started successfully!"
else
  echo "Warning: Nginx may have issues starting. Check logs with: docker logs core-nginx"
fi

echo "Core infrastructure startup completed." 