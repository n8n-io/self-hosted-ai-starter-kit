#!/bin/bash

# Script to check if a Docker network exists and create it if it doesn't
# Usage: ./network.sh <network_name> [driver]
# Arguments:
#   network_name: Name of the Docker network (required)
#   driver: Network driver type (optional, defaults to 'bridge')

set -e

# Check if network name is provided
if [ -z "$1" ]; then
    echo "Error: Network name is required"
    echo "Usage: $0 <network_name> [driver]"
    exit 1
fi

NETWORK_NAME="$1"
NETWORK_DRIVER="${2:-bridge}"

# Check if the network exists
if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    echo "Network '${NETWORK_NAME}' already exists"
else
    echo "Network '${NETWORK_NAME}' does not exist. Creating with driver '${NETWORK_DRIVER}'..."
    docker network create --driver "${NETWORK_DRIVER}" "${NETWORK_NAME}"
    echo "Network '${NETWORK_NAME}' created successfully"
fi
