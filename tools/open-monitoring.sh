#!/bin/bash
# Open monitoring dashboard in browser
set -e

echo "🔍 Opening monitoring dashboard..."

# Get current AWS region
AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

# CloudWatch dashboard URL
CLOUDWATCH_URL="https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:"

echo "📊 CloudWatch Dashboard: $CLOUDWATCH_URL"

# Try to open in browser (cross-platform)
if command -v open >/dev/null 2>&1; then
    # macOS
    open "$CLOUDWATCH_URL"
elif command -v xdg-open >/dev/null 2>&1; then
    # Linux
    xdg-open "$CLOUDWATCH_URL"
elif command -v start >/dev/null 2>&1; then
    # Windows
    start "$CLOUDWATCH_URL"
else
    echo "⚠️  Please open this URL manually: $CLOUDWATCH_URL"
fi

echo "✅ Monitoring dashboard opened"