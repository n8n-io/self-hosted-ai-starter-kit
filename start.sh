#!/bin/bash

# Enhanced N8N Self-Hosted AI Starter Kit
# Build and run script

set -e

echo "Building enhanced N8N starter kit..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please create one based on .env.example"
    exit 1
fi

# Source environment variables
source .env

# Check required environment variables
if [ -z "$NGROK_AUTHTOKEN" ]; then
    echo "Warning: NGROK_AUTHTOKEN not set. HTTPS access via ngrok will not work."
fi

if [ -z "$NGROK_DOMAIN" ]; then
    echo "Warning: NGROK_DOMAIN not set. Using default ngrok domain."
fi

# Build the custom n8n image
echo "Building custom n8n image with enhanced tools..."
docker-compose build n8n

# Choose profile based on GPU availability
if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA GPU detected, using gpu-nvidia profile"
    PROFILE="gpu-nvidia"
elif command -v rocm-smi &> /dev/null; then
    echo "AMD GPU detected, using gpu-amd profile"
    PROFILE="gpu-amd"
else
    echo "No GPU detected, using CPU profile"
    PROFILE="cpu"
fi

# Start the services
echo "Starting services with profile: $PROFILE"
docker-compose --profile $PROFILE up -d

echo "Services started successfully!"
echo ""
echo "Access points:"
echo "- N8N Web Interface: http://localhost:5678"
if [ -n "$NGROK_DOMAIN" ]; then
    echo "- N8N HTTPS (via ngrok): https://$NGROK_DOMAIN"
fi
echo "- Ngrok Dashboard: http://localhost:4040"
echo "- PostgreSQL: localhost:5432"
echo "- Qdrant: http://localhost:6333"
echo "- Ollama: http://localhost:11434"
echo ""
echo "To stop all services: docker-compose down"
echo "To view logs: docker-compose logs -f"
