#!/bin/bash
# start-mcp.sh - Start MCP services with hardware profile
#
# Usage: ./start-mcp.sh [nvidia|amd|cpu]
# Default: cpu
#
# This script starts all MCP services using the appropriate hardware profile
# in a project named "mcp" for better Docker UI organization.

# Determine hardware configuration
if [ "$1" == "nvidia" ]; then
  HW_PROFILE="gpu-nvidia"
elif [ "$1" == "amd" ]; then
  HW_PROFILE="gpu-amd"
else
  HW_PROFILE="cpu"
fi

echo "Starting MCP services with $HW_PROFILE profile..."
docker compose -p mcp --profile mcp --profile $HW_PROFILE up -d
echo "MCP services started successfully with $HW_PROFILE profile." 