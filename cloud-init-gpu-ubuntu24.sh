#!/bin/bash
set -euo pipefail  # Exit on error, unset variable usage, and pipe failures

# Enhanced Cloud-Init Script for NVIDIA GPU-Optimized AMI Ubuntu 24.04
# Optimized for g4dn.xlarge instances with NVIDIA T4 GPUs
# Includes: Spot Instance Management, EFS Integration, GPU Monitoring, Cost Optimization

# =============================================================================
# CONFIGURATION VARIABLES
# =============================================================================

REPO_URL="https://github.com/michael-pittman/001-starter-kit.git"
APP_DIR="/opt/001-starter-kit"
EFS_MOUNT_POINT="/mnt/efs"
EFS_PARAM_NAME="/aibuildkit/efs-id"
INSTANCE_TYPE="g4dn.xlarge"
REGION="us-east-1"
LOG_FILE="/var/log/gpu-deployment.log"

# SSM Parameters for environment variables
PARAM_NAMES=(
  "/aibuildkit/WEBHOOK_URL"
  "/aibuildkit/POSTGRES_DB"
  "/aibuildkit/POSTGRES_USER"
  "/aibuildkit/N8N_USER_MANAGEMENT_JWT_SECRET"
  "/aibuildkit/N8N_ENCRYPTION_KEY"
  "/aibuildkit/POSTGRES_PASSWORD"
  "/aibuildkit/ollama_api_key"
  "/aibuildkit/N8N_CORS_ALLOWED_ORIGINS"
  "/aibuildkit/N8N_CORS_ENABLE"
  "/aibuildkit/N8N_HOST"
  "/aibuildkit/N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE"
  "/aibuildkit/EFS_DNS"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to handle errors
error_exit() {
    log "ERROR: $1" >&2
    # Send notification to CloudWatch if possible
    aws logs put-log-events --region "$REGION" --log-group-name "/aws/ec2/gpu-deployment" \
        --log-stream-name "$(hostname)" --log-events timestamp=$(date +%s000),message="ERROR: $1" || true
    exit 1
}

# Function to detect instance metadata
get_instance_metadata() {
    # Get metadata with IMDSv2 token
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
    
    if [[ -n "$TOKEN" ]]; then
        INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
            -s "http://169.254.169.254/latest/meta-data/instance-id" 2>/dev/null || echo "unknown")
        INSTANCE_TYPE_DETECTED=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
            -s "http://169.254.169.254/latest/meta-data/instance-type" 2>/dev/null || echo "$INSTANCE_TYPE")
        AVAILABILITY_ZONE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
            -s "http://169.254.169.254/latest/meta-data/placement/availability-zone" 2>/dev/null || echo "unknown")
        PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
            -s "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || echo "unknown")
        INSTANCE_LIFECYCLE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
            -s "http://169.254.169.254/latest/meta-data/instance-life-cycle" 2>/dev/null || echo "on-demand")
        
        # Check if this is a spot instance
        if [[ "$INSTANCE_LIFECYCLE" == "spot" ]]; then
            IS_SPOT_INSTANCE="true"
        else
            IS_SPOT_INSTANCE="false"
        fi
    else
        log "WARNING: Could not retrieve instance metadata"
        INSTANCE_ID="unknown"
        INSTANCE_TYPE_DETECTED="$INSTANCE_TYPE"
        AVAILABILITY_ZONE="unknown"
        PUBLIC_IP="unknown"
        IS_SPOT_INSTANCE="false"
    fi
    
    export INSTANCE_ID INSTANCE_TYPE_DETECTED AVAILABILITY_ZONE PUBLIC_IP IS_SPOT_INSTANCE TOKEN
}

# =============================================================================
# SYSTEM INITIALIZATION
# =============================================================================

initialize_system() {
    log "Initializing system for GPU-optimized deployment..."
    
    # Get instance metadata
    get_instance_metadata
    log "Instance ID: $INSTANCE_ID"
    log "Instance Type: $INSTANCE_TYPE_DETECTED"
    log "Availability Zone: $AVAILABILITY_ZONE"
    log "Is Spot Instance: $IS_SPOT_INSTANCE"
    
    # Update package manager and install essential packages
    log "Updating package manager and installing essential packages..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    # Install essential packages for Ubuntu 24.04
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl \
        wget \
        git \
        htop \
        vim \
        unzip \
        awscli \
        jq \
        python3 \
        python3-pip \
        build-essential \
        linux-headers-$(uname -r) \
        dkms \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        nfs-common \
        amazon-efs-utils \
        stress-ng \
        nvtop \
        iotop \
        sysstat \
        tree \
        net-tools
    
    # Set timezone and locale
    timedatectl set-timezone UTC
    locale-gen en_US.UTF-8
    
    log "System initialization completed"
}

# =============================================================================
# NVIDIA GPU SETUP
# =============================================================================

install_gpu_drivers_and_tools() {
    log "Setting up NVIDIA GPU drivers and tools for T4..."
    
    # Verify GPU detection
    if lspci | grep -i nvidia | grep -i "T4\|Tesla"; then
        log "NVIDIA T4 GPU detected"
    else
        log "WARNING: Expected T4 GPU not detected"
        lspci | grep -i nvidia || log "No NVIDIA GPU found"
    fi
    
    # Install NVIDIA drivers (Ubuntu 24.04 includes newer drivers)
    log "Installing NVIDIA drivers..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nvidia-driver-535 \
        nvidia-utils-535 \
        nvidia-compute-utils-535 \
        nvidia-dkms-535
    
    # Install CUDA toolkit
    log "Installing CUDA toolkit..."
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y cuda-toolkit-12-4
    
    # Set up CUDA environment
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/environment
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/environment
    echo 'export CUDA_HOME=/usr/local/cuda' >> /etc/environment
    
    # Install NVIDIA Container Toolkit for Docker GPU support
    log "Installing NVIDIA Container Toolkit..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit
    
    # Install GPU monitoring tools
    log "Installing GPU monitoring tools..."
    pip3 install --upgrade pip
    pip3 install nvidia-ml-py3 gpustat psutil
    
    # Install additional NVIDIA tools
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nvidia-cuda-toolkit \
        nvidia-cuda-dev \
        nvidia-profiler
    
    log "GPU drivers and tools installation completed"
}

# =============================================================================
# DOCKER SETUP WITH GPU SUPPORT
# =============================================================================

setup_docker_for_gpu() {
    log "Setting up Docker with GPU support..."
    
    # Install Docker using official Ubuntu repository
    log "Installing Docker Engine..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        apt-get remove -y $pkg || true
    done
    
    # Add Docker's official GPG key and repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker
    
    # Configure NVIDIA runtime for Docker
    log "Configuring NVIDIA Container Runtime..."
    nvidia-ctk runtime configure --runtime=docker
    
    # Create optimized Docker daemon configuration
    log "Creating optimized Docker daemon configuration..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    },
    "default-ulimits": {
        "memlock": {
            "Hard": -1,
            "Name": "memlock",
            "Soft": -1
        },
        "stack": {
            "Hard": 67108864,
            "Name": "stack",
            "Soft": 67108864
        }
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "5"
    },
    "features": {
        "buildkit": true
    },
    "experimental": true,
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 5,
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": false
}
EOF
    
    # Restart Docker with new configuration
    systemctl restart docker
    
    # Test NVIDIA GPU access through Docker
    log "Testing NVIDIA GPU access through Docker..."
    if docker run --rm --gpus all nvidia/cuda:12.4-base-ubuntu22.04 nvidia-smi; then
        log "✓ Docker GPU access verified successfully"
    else
        log "WARNING: Docker GPU access test failed"
    fi
    
    # Add ubuntu user to docker group
    usermod -aG docker ubuntu || true
    
    log "Docker with GPU support setup completed"
}

# =============================================================================
# PERFORMANCE OPTIMIZATIONS FOR g4dn.xlarge
# =============================================================================

optimize_gpu_instance() {
    log "Applying performance optimizations for g4dn.xlarge..."
    
    # CPU performance optimizations
    log "Optimizing CPU performance..."
    echo 'performance' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor || true
    
    # Memory optimizations
    log "Applying memory optimizations..."
    cat >> /etc/sysctl.conf << EOF

# Memory optimizations for g4dn.xlarge (16GB RAM)
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.overcommit_memory=1
vm.overcommit_ratio=80

# Network optimizations
net.core.rmem_default=262144
net.core.rmem_max=134217728
net.core.wmem_default=262144
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 65536 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.netdev_max_backlog=5000
net.ipv4.tcp_congestion_control=bbr

# File system optimizations
fs.file-max=2097152
fs.nr_open=1048576
EOF
    
    sysctl -p
    
    # I/O scheduler optimization for NVMe
    log "Optimizing I/O scheduler..."
    echo 'mq-deadline' > /sys/block/nvme0n1/queue/scheduler || true
    
    # GPU performance mode
    log "Setting GPU performance mode..."
    nvidia-smi -pm 1 || log "WARNING: Could not enable persistence mode"
    nvidia-smi -ac 5001,1590 || log "WARNING: Could not set memory/graphics clocks"
    
    # Create GPU optimization service
    cat > /etc/systemd/system/gpu-optimize.service << 'EOF'
[Unit]
Description=GPU Performance Optimization
After=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -ac 5001,1590
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable gpu-optimize.service
    
    log "Performance optimizations completed"
}

# =============================================================================
# SPOT INSTANCE MONITORING
# =============================================================================

setup_spot_monitoring() {
    log "Setting up spot instance termination monitoring..."
    
    # Create spot instance termination monitoring script
    cat > /usr/local/bin/spot-monitor.sh << 'EOF'
#!/bin/bash
# Enhanced spot instance termination monitoring with graceful shutdown

LOG_FILE="/var/log/spot-monitor.log"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_alert() {
    local message="$1"
    log "$message"
    
    # Send to CloudWatch if possible
    aws logs put-log-events --region us-east-1 --log-group-name "/aws/ec2/spot-termination" \
        --log-stream-name "$(hostname)" --log-events timestamp=$(date +%s000),message="$message" 2>/dev/null || true
    
    # Send to Slack if webhook is configured
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 Spot Instance Alert: $message\"}" \
            "$SLACK_WEBHOOK_URL" 2>/dev/null || true
    fi
}

# Function to gracefully shutdown services
graceful_shutdown() {
    log "Starting graceful shutdown process..."
    send_alert "Spot instance termination detected - starting graceful shutdown"
    
    # Stop Docker services gracefully
    if command -v docker &> /dev/null; then
        log "Stopping Docker containers..."
        docker ps -q | xargs -r docker stop -t 30
        docker system prune -f || true
    fi
    
    # Unmount EFS
    if mountpoint -q /mnt/efs; then
        log "Unmounting EFS..."
        umount -l /mnt/efs || true
    fi
    
    # Final system shutdown
    log "Initiating system shutdown..."
    shutdown -h +1 "Spot instance termination - shutting down in 1 minute"
}

# Main monitoring loop
log "Starting spot instance termination monitoring..."
while true; do
    # Get IMDSv2 token
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
    
    if [[ -n "$TOKEN" ]]; then
        # Check for spot termination notice
        TERMINATION_TIME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
            -s "http://169.254.169.254/latest/meta-data/spot/termination-time" 2>/dev/null || echo "")
        
        if [[ -n "$TERMINATION_TIME" && "$TERMINATION_TIME" != "Not Found" ]]; then
            send_alert "Spot instance termination notice received. Termination time: $TERMINATION_TIME"
            graceful_shutdown
            break
        fi
        
        # Check for spot instance interruption warning
        INSTANCE_ACTION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
            -s "http://169.254.169.254/latest/meta-data/spot/instance-action" 2>/dev/null || echo "")
        
        if [[ -n "$INSTANCE_ACTION" && "$INSTANCE_ACTION" != "Not Found" ]]; then
            send_alert "Spot instance action detected: $INSTANCE_ACTION"
            graceful_shutdown
            break
        fi
    fi
    
    sleep 5
done
EOF
    
    chmod +x /usr/local/bin/spot-monitor.sh
    
    # Create systemd service for spot monitoring
    cat > /etc/systemd/system/spot-monitor.service << 'EOF'
[Unit]
Description=Spot Instance Termination Monitor
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/spot-monitor.sh
Restart=always
RestartSec=10
KillMode=process
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable spot-monitor.service
    systemctl start spot-monitor.service
    
    log "Spot instance monitoring configured and started"
}

# =============================================================================
# GPU MONITORING SETUP
# =============================================================================

setup_gpu_monitoring() {
    log "Setting up comprehensive GPU monitoring..."
    
    # Create GPU monitoring script
    cat > /usr/local/bin/gpu-monitor.py << 'EOF'
#!/usr/bin/env python3
"""
Enhanced GPU Monitoring for NVIDIA T4 on g4dn.xlarge
Monitors: GPU utilization, memory, temperature, power, processes
Outputs: CloudWatch metrics, JSON logs, performance recommendations
"""

import json
import time
import subprocess
import logging
import boto3
from datetime import datetime
import nvidia_ml_py3 as nvml
import psutil

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/gpu-monitoring.log'),
        logging.StreamHandler()
    ]
)

class GPUMonitor:
    def __init__(self):
        self.cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')
        nvml.nvmlInit()
        self.device_count = nvml.nvmlDeviceGetCount()
        logging.info(f"Initialized monitoring for {self.device_count} GPU(s)")
    
    def get_gpu_metrics(self):
        metrics = []
        for i in range(self.device_count):
            handle = nvml.nvmlDeviceGetHandleByIndex(i)
            
            # Basic info
            name = nvml.nvmlDeviceGetName(handle).decode('utf-8')
            
            # Memory info
            mem_info = nvml.nvmlDeviceGetMemoryInfo(handle)
            memory_total = mem_info.total / 1024**3  # GB
            memory_used = mem_info.used / 1024**3   # GB
            memory_free = mem_info.free / 1024**3   # GB
            memory_util = (memory_used / memory_total) * 100
            
            # Utilization
            util = nvml.nvmlDeviceGetUtilizationRates(handle)
            gpu_util = util.gpu
            memory_bandwidth_util = util.memory
            
            # Temperature
            temp = nvml.nvmlDeviceGetTemperature(handle, nvml.NVML_TEMPERATURE_GPU)
            
            # Power
            try:
                power_draw = nvml.nvmlDeviceGetPowerUsage(handle) / 1000.0  # Watts
                power_limit = nvml.nvmlDeviceGetPowerManagementLimitConstraints(handle)[1] / 1000.0
            except:
                power_draw = 0
                power_limit = 0
            
            # Clock speeds
            try:
                graphics_clock = nvml.nvmlDeviceGetClockInfo(handle, nvml.NVML_CLOCK_GRAPHICS)
                memory_clock = nvml.nvmlDeviceGetClockInfo(handle, nvml.NVML_CLOCK_MEM)
            except:
                graphics_clock = 0
                memory_clock = 0
            
            # Processes
            try:
                processes = nvml.nvmlDeviceGetComputeRunningProcesses(handle)
                process_count = len(processes)
            except:
                process_count = 0
            
            metrics.append({
                'device_id': i,
                'name': name,
                'memory_total_gb': round(memory_total, 2),
                'memory_used_gb': round(memory_used, 2),
                'memory_free_gb': round(memory_free, 2),
                'memory_utilization_percent': round(memory_util, 2),
                'gpu_utilization_percent': gpu_util,
                'memory_bandwidth_utilization_percent': memory_bandwidth_util,
                'temperature_celsius': temp,
                'power_draw_watts': round(power_draw, 2),
                'power_limit_watts': round(power_limit, 2),
                'graphics_clock_mhz': graphics_clock,
                'memory_clock_mhz': memory_clock,
                'process_count': process_count,
                'timestamp': datetime.utcnow().isoformat()
            })
        
        return metrics
    
    def send_cloudwatch_metrics(self, metrics):
        try:
            metric_data = []
            for gpu in metrics:
                device_id = gpu['device_id']
                metric_data.extend([
                    {
                        'MetricName': 'GPUUtilization',
                        'Dimensions': [{'Name': 'DeviceId', 'Value': str(device_id)}],
                        'Value': gpu['gpu_utilization_percent'],
                        'Unit': 'Percent'
                    },
                    {
                        'MetricName': 'GPUMemoryUtilization',
                        'Dimensions': [{'Name': 'DeviceId', 'Value': str(device_id)}],
                        'Value': gpu['memory_utilization_percent'],
                        'Unit': 'Percent'
                    },
                    {
                        'MetricName': 'GPUTemperature',
                        'Dimensions': [{'Name': 'DeviceId', 'Value': str(device_id)}],
                        'Value': gpu['temperature_celsius'],
                        'Unit': 'None'
                    },
                    {
                        'MetricName': 'GPUPowerDraw',
                        'Dimensions': [{'Name': 'DeviceId', 'Value': str(device_id)}],
                        'Value': gpu['power_draw_watts'],
                        'Unit': 'None'
                    }
                ])
            
            # Send metrics in batches of 20 (CloudWatch limit)
            for i in range(0, len(metric_data), 20):
                batch = metric_data[i:i+20]
                self.cloudwatch.put_metric_data(
                    Namespace='GPU/Monitoring',
                    MetricData=batch
                )
            
            logging.info("CloudWatch metrics sent successfully")
        except Exception as e:
            logging.error(f"Failed to send CloudWatch metrics: {e}")
    
    def analyze_performance(self, metrics):
        recommendations = []
        for gpu in metrics:
            gpu_util = gpu['gpu_utilization_percent']
            mem_util = gpu['memory_utilization_percent']
            temp = gpu['temperature_celsius']
            
            if gpu_util < 20:
                recommendations.append(f"GPU {gpu['device_id']}: Low utilization ({gpu_util}%) - consider increasing batch size or concurrent requests")
            elif gpu_util > 95:
                recommendations.append(f"GPU {gpu['device_id']}: High utilization ({gpu_util}%) - may cause performance bottlenecks")
            
            if mem_util > 90:
                recommendations.append(f"GPU {gpu['device_id']}: High memory usage ({mem_util}%) - consider reducing model size or batch size")
            
            if temp > 80:
                recommendations.append(f"GPU {gpu['device_id']}: High temperature ({temp}°C) - check cooling and workload")
        
        return recommendations
    
    def monitor_loop(self, interval=30):
        while True:
            try:
                metrics = self.get_gpu_metrics()
                
                # Log metrics to file
                with open('/var/log/gpu-metrics.json', 'a') as f:
                    json.dump({
                        'timestamp': datetime.utcnow().isoformat(),
                        'metrics': metrics
                    }, f)
                    f.write('\n')
                
                # Send to CloudWatch
                self.send_cloudwatch_metrics(metrics)
                
                # Performance analysis
                recommendations = self.analyze_performance(metrics)
                if recommendations:
                    logging.info("Performance recommendations:")
                    for rec in recommendations:
                        logging.info(f"  - {rec}")
                
                time.sleep(interval)
                
            except Exception as e:
                logging.error(f"Monitoring error: {e}")
                time.sleep(interval)

if __name__ == "__main__":
    monitor = GPUMonitor()
    monitor.monitor_loop()
EOF
    
    chmod +x /usr/local/bin/gpu-monitor.py
    
    # Create systemd service for GPU monitoring
    cat > /etc/systemd/system/gpu-monitor.service << 'EOF'
[Unit]
Description=GPU Monitoring Service
After=docker.service
Wants=docker.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gpu-monitor.py
Restart=always
RestartSec=30
Environment=PYTHONPATH=/usr/local/lib/python3.12/site-packages

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable gpu-monitor.service
    systemctl start gpu-monitor.service
    
    log "GPU monitoring setup completed"
}

# =============================================================================
# EFS INTEGRATION
# =============================================================================

setup_efs_integration() {
    log "Setting up enhanced EFS integration..."
    
    # Retrieve EFS ID from SSM Parameter Store
    EFS_ID=$(aws ssm get-parameter --region "$REGION" --name "$EFS_PARAM_NAME" \
        --query "Parameter.Value" --output text 2>/dev/null || echo "")
    
    if [[ -z "$EFS_ID" ]]; then
        log "WARNING: No EFS ID provided in SSM parameter $EFS_PARAM_NAME. Using local storage."
        mkdir -p "$EFS_MOUNT_POINT"
        echo "EFS_DNS=localhost" >> "$APP_DIR/.env" || true
        return 0
    fi
    
    log "EFS ID: $EFS_ID"
    
    # Create mount point
    mkdir -p "$EFS_MOUNT_POINT"
    
    # Install EFS utilities
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y amazon-efs-utils
    
    # Configure EFS mount with optimized settings
    EFS_DNS="${EFS_ID}.efs.${REGION}.amazonaws.com"
    log "EFS DNS: $EFS_DNS"
    
    # Create optimized fstab entry
    cat >> /etc/fstab << EOF
${EFS_DNS}:/ ${EFS_MOUNT_POINT} efs defaults,_netdev,fsc,regional,accesspoint=fsap-12345678,iam 0 0
EOF
    
    # Mount EFS with retries
    for i in {1..5}; do
        if mount -a; then
            log "EFS mounted successfully"
            break
        else
            log "EFS mount attempt $i failed, retrying in 10 seconds..."
            sleep 10
        fi
    done
    
    # Verify mount
    if mountpoint -q "$EFS_MOUNT_POINT"; then
        log "✓ EFS mounted at $EFS_MOUNT_POINT"
        
        # Set up directory structure
        log "Creating EFS directory structure..."
        mkdir -p "$EFS_MOUNT_POINT"/{n8n,postgres,ollama,qdrant,monitoring,backups,shared}
        
        # Set proper permissions
        chown -R 1000:1000 "$EFS_MOUNT_POINT/n8n"
        chown -R 999:999 "$EFS_MOUNT_POINT/postgres"
        chown -R 0:0 "$EFS_MOUNT_POINT/ollama"
        chown -R 0:0 "$EFS_MOUNT_POINT/qdrant"
        chown -R 0:0 "$EFS_MOUNT_POINT/monitoring"
        chown -R 0:0 "$EFS_MOUNT_POINT/backups"
        chown -R 0:0 "$EFS_MOUNT_POINT/shared"
        
        # Set permissions
        chmod -R 755 "$EFS_MOUNT_POINT"
        
        log "EFS directory structure created"
    else
        error_exit "Failed to mount EFS"
    fi
}

# =============================================================================
# POST-DEPLOYMENT SETUP
# =============================================================================

post_deployment_setup() {
    log "Running post-deployment setup..."
    
    # Create performance monitoring dashboard script
    cat > /usr/local/bin/performance-dashboard.sh << 'EOF'
#!/bin/bash
echo "=== GPU Performance Dashboard ==="
echo "Generated at: $(date)"
echo ""

echo "=== GPU Status ==="
nvidia-smi

echo ""
echo "=== System Resources ==="
echo "CPU Usage: $(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage "%"}')"
echo "Memory Usage: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
echo "Disk Usage: $(df -h / | tail -1 | awk '{print $5}')"

echo ""
echo "=== Docker Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== EFS Mount Status ==="
if mountpoint -q /mnt/efs; then
    echo "✓ EFS mounted successfully"
    df -h /mnt/efs
else
    echo "✗ EFS not mounted"
fi

echo ""
echo "=== Spot Instance Status ==="
if systemctl is-active --quiet spot-monitor.service; then
    echo "✓ Spot monitoring active"
else
    echo "✗ Spot monitoring inactive"
fi
EOF
    
    chmod +x /usr/local/bin/performance-dashboard.sh
    
    # Create startup completion marker
    touch /var/log/gpu-deployment-complete
    
    # Send completion notification
    aws logs put-log-events --region "$REGION" --log-group-name "/aws/ec2/gpu-deployment" \
        --log-stream-name "$(hostname)" \
        --log-events timestamp=$(date +%s000),message="GPU deployment completed successfully on $INSTANCE_TYPE_DETECTED" || true
    
    # Set up system optimization on boot
    cat > /etc/systemd/system/gpu-startup-optimization.service << 'EOF'
[Unit]
Description=GPU Startup Optimization
After=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -ac 5001,1590
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable gpu-startup-optimization.service
    
    log "Post-deployment setup completed"
}

# =============================================================================
# APPLICATION DEPLOYMENT
# =============================================================================

deploy_application() {
    log "Deploying AI Starter Kit application..."
    
    # Clone repository
    log "Cloning repository..."
    mkdir -p "$(dirname "$APP_DIR")"
    if [[ -d "$APP_DIR" ]]; then
        rm -rf "$APP_DIR"
    fi
    git clone "$REPO_URL" "$APP_DIR" || error_exit "Repository clone failed"
    
    # Set up AWS configuration
    log "Setting up AWS configuration..."
    export AWS_DEFAULT_REGION="$REGION"
    aws configure set default.region "$REGION"
    
    # Retrieve environment variables from SSM
    log "Retrieving environment variables from SSM Parameter Store..."
    rm -f "$APP_DIR/.env"
    for param in "${PARAM_NAMES[@]}"; do
        VALUE=$(aws ssm get-parameter --region "$REGION" --name "$param" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "")
        if [[ -n "$VALUE" ]]; then
            KEY=$(basename "$param")
            echo "$KEY=$VALUE" >> "$APP_DIR/.env"
            log "Retrieved parameter: $KEY"
        else
            log "WARNING: Failed to retrieve parameter $param"
        fi
    done
    
    # Add GPU-specific environment variables
    cat >> "$APP_DIR/.env" << EOF
# GPU Configuration
NVIDIA_VISIBLE_DEVICES=all
NVIDIA_DRIVER_CAPABILITIES=all
CUDA_VISIBLE_DEVICES=all
CUDA_DEVICE_ORDER=PCI_BUS_ID

# Instance Information
INSTANCE_ID=$INSTANCE_ID
INSTANCE_TYPE=$INSTANCE_TYPE_DETECTED
AVAILABILITY_ZONE=$AVAILABILITY_ZONE
IS_SPOT_INSTANCE=$IS_SPOT_INSTANCE

# Performance Optimization
OLLAMA_GPU_MEMORY_FRACTION=0.9
OLLAMA_CONCURRENT_REQUESTS=4
OLLAMA_NUM_PARALLEL=4
OLLAMA_FLASH_ATTENTION=1
OLLAMA_KEEP_ALIVE=24h
OLLAMA_MAX_LOADED_MODELS=3
OLLAMA_MAX_QUEUE=128

# EFS Configuration
EFS_MOUNT_POINT=$EFS_MOUNT_POINT
EFS_DNS=$EFS_DNS

# T4 Specific Optimizations
GPU_COMPUTE_CAPABILITY=7.5
GPU_MEMORY_GB=16
CUDA_VERSION=12.4
EOF
    
    # Set proper ownership
    chown -R ubuntu:ubuntu "$APP_DIR"
    
    # Start services using the GPU-optimized compose file
    log "Starting GPU-optimized services..."
    cd "$APP_DIR"
    
    # Use the GPU-optimized docker compose file
    if [[ -f "docker-compose.gpu-optimized.yml" ]]; then
        docker compose -f docker-compose.yml -f docker-compose.gpu-optimized.yml up -d
    elif [[ -f "docker-compose.gpu.yml" ]]; then
        docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
    else
        log "WARNING: No GPU-optimized compose file found, using standard compose"
        docker compose up -d
    fi
    
    # Wait for services to be healthy
    log "Waiting for services to be healthy..."
    sleep 60
    
    # Verify services
    log "Verifying service status..."
    docker compose ps
    
    log "Application deployment completed"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log "=== Starting Enhanced GPU-Optimized Deployment ==="
    log "Target: NVIDIA GPU-Optimized AMI Ubuntu 24.04 on g4dn.xlarge"
    
    # Execute deployment steps
    initialize_system
    install_gpu_drivers_and_tools
    setup_docker_for_gpu
    optimize_gpu_instance
    setup_gpu_monitoring
    setup_efs_integration
    
    # Set up spot instance monitoring if this is a spot instance
    if [[ "$IS_SPOT_INSTANCE" == "true" ]]; then
        setup_spot_monitoring
    fi
    
    deploy_application
    post_deployment_setup
    
    log "=== Enhanced GPU-Optimized Deployment Completed Successfully ==="
    log "Services Available:"
    log "  - n8n: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5678"
    log "  - Ollama: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):11434"
    log "  - Qdrant: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):6333"
    log "  - GPU Monitoring: Check CloudWatch GPU/Monitoring namespace"
    log ""
    log "Quick Commands:"
    log "  - View GPU status: nvidia-smi"
    log "  - Performance dashboard: /usr/local/bin/performance-dashboard.sh"
    log "  - GPU monitoring logs: tail -f /var/log/gpu-monitoring.log"
    log "  - Service status: docker compose ps"
}

# Execute main function
main "$@" 