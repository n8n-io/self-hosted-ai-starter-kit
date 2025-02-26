#!/bin/sh

# Ensure we're running as the node user
if [ "$(id -u)" != "1000" ]; then
    echo "This script must be run as the node user (uid 1000)"
    exit 1
fi

# Create timestamp
timestamp=$(date +%Y%m%d_%H%M%S)

# Create backup directories
mkdir -p /backup/auto-backups/$timestamp

# Export all workflows
n8n export:workflow --all --output=/backup/auto-backups/$timestamp/workflows.json

# Export all credentials
n8n export:credentials --all --output=/backup/auto-backups/$timestamp/credentials.json

# Create a full backup of the .n8n directory
cd /home/node && tar czf /backup/auto-backups/$timestamp/n8n_full_backup.tar.gz .n8n/

# Keep only the last 7 days of backups (only if we have write permissions)
if [ -w "/backup/auto-backups" ]; then
    find /backup/auto-backups -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
fi

echo "Backup completed at $timestamp"

# Verify the backup
echo "Verifying backup..."
if [ -f "/backup/auto-backups/$timestamp/workflows.json" ] && \
   [ -f "/backup/auto-backups/$timestamp/credentials.json" ] && \
   [ -f "/backup/auto-backups/$timestamp/n8n_full_backup.tar.gz" ]; then
    echo "✓ Backup verified successfully"
    # Create a verification file that can be checked from outside the container
    touch "/backup/auto-backups/$timestamp/.backup_verified"
else
    echo "❌ Backup verification failed"
    exit 1
fi 