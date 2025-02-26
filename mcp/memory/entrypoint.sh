#!/bin/sh
echo "Starting MCP Memory Server..."
# Create a symbolic link from /data/memory.json to /app/dist/memory.json
mkdir -p /app/dist
if [ ! -f /data/memory.json ]; then
  echo "Creating empty memory.json in /data"
  echo "[]" > /data/memory.json
  chmod 666 /data/memory.json
fi
echo "Linking /data/memory.json to /app/dist/memory.json"
ln -sf /data/memory.json /app/dist/memory.json
# Test connection to Qdrant
echo "Testing connection to Qdrant at $QDRANT_HOST:$QDRANT_PORT..."
# Keep the container running with an empty input stream
echo "Starting application with continuous input..."
exec tail -f /dev/null | node dist/index.js
