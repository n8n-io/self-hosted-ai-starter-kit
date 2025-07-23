#!/bin/bash

# Test Docker Compose Configuration
# This script tests the Docker configuration without EFS dependencies

set -euo pipefail

echo "=== Testing Docker Compose Configuration ==="

# Create a test .env file without EFS dependencies
cat > .env.test << EOF
# PostgreSQL Configuration
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=test_password_123

# n8n Configuration
N8N_ENCRYPTION_KEY=test_encryption_key_123456789
N8N_USER_MANAGEMENT_JWT_SECRET=test_jwt_secret_123456789
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost:5678

# n8n Security Settings
N8N_CORS_ENABLE=true
N8N_CORS_ALLOWED_ORIGINS=http://localhost:5678
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

# AWS Configuration (test values)
INSTANCE_ID=test-instance
INSTANCE_TYPE=g4dn.xlarge
AWS_DEFAULT_REGION=us-east-1

# API Keys (empty for testing)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
MISTRAL_API_KEY=
GEMINI_API_TOKEN=

# EFS Configuration (empty for local testing)
EFS_DNS=
EOF

# Create a modified docker-compose file for local testing (without EFS)
cp docker-compose.gpu-optimized.yml docker-compose.test.yml

# Replace EFS volumes with local volumes for testing
sed -i '' 's/type: "nfs"/type: "local"/g' docker-compose.test.yml
sed -i '' 's/o: "addr=\${EFS_DNS}.*"/device: ""/' docker-compose.test.yml
sed -i '' 's/device: ".*"/driver_opts: {}/' docker-compose.test.yml

echo "✅ Test configuration created"
echo ""
echo "To test the configuration:"
echo "1. Run: docker-compose --env-file .env.test -f docker-compose.test.yml config"
echo "2. Run: docker-compose --env-file .env.test -f docker-compose.test.yml up -d postgres"
echo "3. Run: docker-compose --env-file .env.test -f docker-compose.test.yml logs postgres"
echo ""
echo "To clean up test files:"
echo "rm .env.test docker-compose.test.yml"