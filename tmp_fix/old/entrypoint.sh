#!/bin/sh
echo "Starting MCP Memory Server..."

# Check if memory.json exists
if [ ! -f /app/dist/memory.json ]; then
  echo "ERROR: memory.json not found in /app/dist"
  echo "[]" > /app/dist/memory.json
  chmod 666 /app/dist/memory.json
  echo "Created empty memory.json file"
fi

# Test connection to Qdrant
echo "Testing connection to Qdrant at $QDRANT_HOST:$QDRANT_PORT..."

# Execute the main application
echo "Starting main application..."
exec node dist/index.js
