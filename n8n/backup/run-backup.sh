#!/bin/sh

# Ensure we're using the rootless Docker socket
export DOCKER_HOST="unix:///run/user/1000/docker.sock"

# Ensure backup directory exists with correct permissions
mkdir -p $(dirname "$0")/auto-backups
chmod 777 $(dirname "$0")/auto-backups

# Ensure the node user can write to the backup directory inside the container
docker exec n8n mkdir -p /backup/auto-backups

# Run backup script inside the n8n container as the node user
docker exec -u node n8n sh /backup/backup.sh

# Check the result
latest_backup=$(find $(dirname "$0")/auto-backups -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
if [ -f "$latest_backup/.backup_verified" ]; then
    echo "Backup completed and verified successfully"
    echo "Backup location: $latest_backup"
    
    # Show what was backed up
    echo "\nBackup contents:"
    ls -l "$latest_backup"
else
    echo "Backup failed or could not be verified"
    exit 1
fi 