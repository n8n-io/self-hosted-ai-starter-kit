#!/bin/bash
# Create backup of deployed infrastructure
set -e

STACK_NAME="${1:-}"
if [ -z "$STACK_NAME" ]; then
    echo "Usage: $0 <STACK_NAME>"
    exit 1
fi

echo "🔄 Creating backup for stack: $STACK_NAME"

# Create backup directory
BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)-${STACK_NAME}"
mkdir -p "$BACKUP_DIR"

# Export CloudFormation stack (if exists)
echo "📋 Exporting CloudFormation stack..."
aws cloudformation describe-stacks --stack-name "$STACK_NAME" > "$BACKUP_DIR/cloudformation-stack.json" 2>/dev/null || echo "No CloudFormation stack found"

# Export EC2 instance details
echo "🖥️  Exporting EC2 instance details..."
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${STACK_NAME}-instance" \
    > "$BACKUP_DIR/ec2-instances.json" 2>/dev/null || echo "No EC2 instances found"

# Export security groups
echo "🔒 Exporting security groups..."
aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=${STACK_NAME}-*" \
    > "$BACKUP_DIR/security-groups.json" 2>/dev/null || echo "No security groups found"

# Export key pairs
echo "🔑 Exporting key pair info..."
aws ec2 describe-key-pairs \
    --key-names "${STACK_NAME}-keypair" \
    > "$BACKUP_DIR/key-pairs.json" 2>/dev/null || echo "No key pairs found"

# Create backup summary
cat > "$BACKUP_DIR/backup-info.txt" << EOF
Backup created: $(date)
Stack name: $STACK_NAME
Backup directory: $BACKUP_DIR
AWS Region: $(aws configure get region 2>/dev/null || echo "default")
EOF

echo "✅ Backup created in: $BACKUP_DIR"
echo "📄 Backup contents:"
ls -la "$BACKUP_DIR"