#!/bin/bash
# start-all.sh - Start all services with hardware profile
#
# Usage: ./start-all.sh [nvidia|amd|cpu]
# Default: cpu
#
# This script starts all services using the appropriate hardware profile
# in a project named "hosted-n8n" for better Docker UI organization.

# Determine hardware configuration
if [ "$1" == "nvidia" ]; then
  HW_PROFILE="gpu-nvidia"
elif [ "$1" == "amd" ]; then
  HW_PROFILE="gpu-amd"
else
  HW_PROFILE="cpu"
fi

echo "Starting all services with $HW_PROFILE profile..."
docker compose -p hosted-n8n --profile core --profile n8n --profile mcp --profile ai --profile utility --profile $HW_PROFILE up -d
echo "All services started successfully with $HW_PROFILE profile." 