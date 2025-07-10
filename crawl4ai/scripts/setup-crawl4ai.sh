#!/bin/bash

# Crawl4AI Container Setup Script
# This script runs during container initialization to configure Crawl4AI

set -euo pipefail

echo "=== Crawl4AI Container Setup Starting ==="

# Environment setup
export CRAWL4AI_CONFIG_DIR="/app/config"
export CRAWL4AI_CACHE_DIR="/app/cache"
export CRAWL4AI_STORAGE_DIR="/app/storage"

# Create necessary directories
mkdir -p "$CRAWL4AI_CONFIG_DIR" "$CRAWL4AI_CACHE_DIR" "$CRAWL4AI_STORAGE_DIR"

# Copy configuration if it exists
if [ -f "/app/crawl4ai-example-config.yml" ]; then
    cp /app/crawl4ai-example-config.yml "$CRAWL4AI_CONFIG_DIR/config.yml"
    echo "✅ Configuration file copied"
fi

# Wait for dependent services
echo "🔄 Waiting for dependent services..."

# Wait for Ollama (if configured)
if [ "${OLLAMA_BASE_URL:-}" ]; then
    echo "Waiting for Ollama at $OLLAMA_BASE_URL..."
    until curl -s "$OLLAMA_BASE_URL/api/tags" > /dev/null 2>&1; do
        echo "Ollama not ready, waiting 5 seconds..."
        sleep 5
    done
    echo "✅ Ollama is ready"
fi

# Wait for PostgreSQL (if configured)
if [ "${DATABASE_URL:-}" ]; then
    echo "Waiting for PostgreSQL..."
    until pg_isready -h "${POSTGRES_HOST:-postgres}" -p "${POSTGRES_PORT:-5432}" > /dev/null 2>&1; do
        echo "PostgreSQL not ready, waiting 3 seconds..."
        sleep 3
    done
    echo "✅ PostgreSQL is ready"
fi

# Initialize Crawl4AI
echo "🚀 Initializing Crawl4AI..."

# Set default LLM provider based on environment
if [ "${OLLAMA_BASE_URL:-}" ]; then
    export DEFAULT_PROVIDER="ollama"
    export LLM_BASE_URL="$OLLAMA_BASE_URL"
elif [ "${OPENAI_API_KEY:-}" ]; then
    export DEFAULT_PROVIDER="openai"
elif [ "${ANTHROPIC_API_KEY:-}" ]; then
    export DEFAULT_PROVIDER="anthropic"
else
    echo "⚠️  No LLM provider configured, using basic extraction only"
    export DEFAULT_PROVIDER="none"
fi

echo "📝 Using LLM provider: $DEFAULT_PROVIDER"

# Pre-warm models if using Ollama
if [ "$DEFAULT_PROVIDER" = "ollama" ] && [ "${OLLAMA_BASE_URL:-}" ]; then
    echo "🔥 Pre-warming Ollama models..."
    
    # List of models to pre-warm
    MODELS=("deepseek-r1:8b" "qwen2.5-vl:7b" "snowflake-arctic-embed2:568m")
    
    for model in "${MODELS[@]}"; do
        echo "Pre-warming model: $model"
        curl -s -X POST "$OLLAMA_BASE_URL/api/generate" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$model\",\"prompt\":\"Hello\",\"stream\":false}" > /dev/null || true
    done
    echo "✅ Model pre-warming completed"
fi

# Create health check script
cat > /app/health-check.sh << 'EOF'
#!/bin/bash
# Crawl4AI Health Check

# Check if the main service is responding
if ! curl -s -f http://localhost:11235/health > /dev/null; then
    echo "❌ Crawl4AI service not responding"
    exit 1
fi

# Check LLM provider connectivity
if [ "${DEFAULT_PROVIDER:-}" = "ollama" ] && [ "${OLLAMA_BASE_URL:-}" ]; then
    if ! curl -s "$OLLAMA_BASE_URL/api/tags" > /dev/null; then
        echo "❌ Ollama not accessible"
        exit 1
    fi
fi

echo "✅ All health checks passed"
exit 0
EOF

chmod +x /app/health-check.sh

# Start monitoring in background
if [ "${ENABLE_MONITORING:-true}" = "true" ]; then
    echo "📊 Starting performance monitoring..."
    python3 -c "
import psutil
import time
import json
import os
from datetime import datetime

def log_metrics():
    while True:
        metrics = {
            'timestamp': datetime.now().isoformat(),
            'cpu_percent': psutil.cpu_percent(),
            'memory_percent': psutil.virtual_memory().percent,
            'disk_usage': psutil.disk_usage('/').percent
        }
        
        with open('/app/storage/metrics.jsonl', 'a') as f:
            f.write(json.dumps(metrics) + '\n')
        
        time.sleep(60)

if __name__ == '__main__':
    log_metrics()
" &
    echo "✅ Monitoring started"
fi

echo "=== Crawl4AI Container Setup Complete ==="
echo "🌐 Service will be available at http://localhost:11235"
echo "🎮 Playground available at http://localhost:11235/playground"
echo "📚 API docs at http://localhost:11235/docs" 