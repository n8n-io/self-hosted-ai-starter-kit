#!/bin/sh

# Ensure we're using the rootless Docker socket
export DOCKER_HOST="unix:///run/user/1000/docker.sock"
export XDG_RUNTIME_DIR="/run/user/1000"

# Get the absolute path to the backup script
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
BACKUP_SCRIPT="$SCRIPT_DIR/run-backup.sh"

# Function to run backup with debouncing
last_backup=0
MIN_BACKUP_INTERVAL=150  # 2.5 minutes in seconds

run_backup_debounced() {
    current_time=$(date +%s)
    time_since_last=$((current_time - last_backup))
    
    if [ $time_since_last -ge $MIN_BACKUP_INTERVAL ]; then
        echo "[$(date)] Changes detected, running backup..."
        $BACKUP_SCRIPT
        last_backup=$current_time
    else
        echo "[$(date)] Changes detected, but waiting for debounce period (${MIN_BACKUP_INTERVAL}s)..."
    fi
}

cleanup() {
    echo "Cleaning up..."
    docker rm -f n8n-watcher >/dev/null 2>&1 || true
}

# Set up cleanup on script exit
trap cleanup EXIT INT TERM

echo "Starting n8n file watcher..."
echo "Monitoring n8n data directory for changes..."

# Remove any existing watcher container
cleanup

# Get the network name from the n8n container
NETWORK=$(docker inspect n8n --format '{{range $net,$v := .NetworkSettings.Networks}}{{$net}}{{end}}' 2>/dev/null || echo "hosted-n8n_lab")

# Create and start a watcher container
docker run --rm \
    --name n8n-watcher \
    --network "$NETWORK" \
    --volumes-from n8n \
    alpine:latest \
    sh -c '
        apk add --no-cache inotify-tools
        echo "Watcher initialized and monitoring /home/node/.n8n"
        while true; do
            inotifywait -r -e modify,create,delete,move /home/node/.n8n 2>/dev/null || {
                echo "inotifywait failed, sleeping before retry..."
                sleep 5
                continue
            }
            echo "CHANGE_DETECTED"
        done
    ' | while read line; do
    if [ "$line" = "CHANGE_DETECTED" ]; then
        run_backup_debounced
    fi
done

# Keep the script running
wait 