#!/bin/bash
# start-utility.sh - Start utility services
#
# This script starts all utility services (crawl4ai, etc.) 
# in a project named "utility" for better Docker UI organization.

echo "Starting utility services..."
docker compose -p utility --profile utility up -d
echo "Utility services started successfully." 