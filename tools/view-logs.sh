#!/bin/bash
# View application logs for deployed stack
set -e

STACK_NAME="${1:-}"
if [ -z "$STACK_NAME" ]; then
    echo "Usage: $0 <STACK_NAME>"
    exit 1
fi

echo "Viewing logs for stack: $STACK_NAME"

# Get instance IP from stack
INSTANCE_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${STACK_NAME}-instance" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || echo "")

if [ -z "$INSTANCE_IP" ] || [ "$INSTANCE_IP" = "None" ]; then
    echo "❌ No running instance found for stack: $STACK_NAME"
    exit 1
fi

echo "📋 Connecting to instance: $INSTANCE_IP"

# SSH into instance and show docker logs
KEY_PATH="$HOME/.ssh/${STACK_NAME}-keypair.pem"
if [ ! -f "$KEY_PATH" ]; then
    KEY_PATH="$HOME/.ssh/id_rsa"
fi

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@"$INSTANCE_IP" \
    "docker compose -f docker-compose.gpu-optimized.yml logs --tail=50 --follow"