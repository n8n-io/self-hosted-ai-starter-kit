#!/bin/bash
# start-core.sh - Start core infrastructure services
#
# This script starts core infrastructure services with the "core" profile
# in a project named "core" for better Docker UI organization.

echo "Starting core infrastructure services..."

# Start postgres database
echo "Starting postgres database..."
docker compose -f ../docker-compose.profile.yml -p core --profile core up -d postgres
echo "Postgres database started."

# Give postgres a moment to initialize
sleep 3

# Start nginx independently
echo "Starting nginx reverse proxy..."
docker compose -f ../docker-compose.profile.yml -p core --profile core up -d nginx
echo "Nginx reverse proxy started."

echo "Core infrastructure services started successfully."
echo "You can verify their status with: docker ps | grep core" 