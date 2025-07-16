#!/bin/bash
set -euo pipefail

# Enhanced GPU Monitoring Setup for NVIDIA T4 on g4dn.xlarge
# Features: CloudWatch integration, performance optimization, SNS alerts, Grafana dashboards
# Optimized for AI workloads with real-time monitoring and cost tracking

# =============================================================================
# CONFIGURATION VARIABLES
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MONITORING_DIR="/opt/gpu-monitoring"
LOG_FILE="/var/log/gpu-monitoring-setup.log"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Monitoring configuration
CLOUDWATCH_NAMESPACE="GPU/AI-Starter-Kit"
SNS_TOPIC_NAME="ai-starter-kit-gpu-alerts"
DASHBOARD_NAME="AI-Starter-Kit-GPU-Performance"

# Performance thresholds
GPU_TEMP_WARNING=75
GPU_TEMP_CRITICAL=85
GPU_UTIL_HIGH=90
GPU_MEMORY_HIGH=90
POWER_USAGE_HIGH=85

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1" >&2
    exit 1
}

check_dependencies() {
    log "Checking dependencies..."
    
    # Check for NVIDIA drivers
    if ! command -v nvidia-smi &> /dev/null; then
        error_exit "nvidia-smi not found. Install NVIDIA drivers first."
    fi
    
    # Check for Python and pip
    if ! command -v python3 &> /dev/null; then
        error_exit "Python3 not found"
    fi
    
    # Check for AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI not found"
    fi
    
    log "✅ All dependencies satisfied"
}

# =============================================================================
# GPU MONITORING INSTALLATION
# =============================================================================

install_monitoring_dependencies() {
    log "Installing GPU monitoring dependencies..."
    
    # Install Python packages
    pip3 install --upgrade \
        nvidia-ml-py3 \
        boto3 \
        psutil \
        requests \
        prometheus-client \
        flask \
        numpy \
        pandas \
        matplotlib \
        seaborn
    
    # Install additional monitoring tools
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nvtop \
        htop \
        iotop \
        sysstat \
        curl \
        jq
    
    log "✅ Dependencies installed"
}

create_monitoring_scripts() {
    log "Creating GPU monitoring scripts..."
    
    mkdir -p "$MONITORING_DIR"
    
    # Create main GPU monitoring script
    cat > "$MONITORING_DIR/gpu_monitor.py" << 'EOF'
#!/usr/bin/env python3
"""
Enhanced GPU Monitoring for AI Starter Kit
Features: CloudWatch metrics, performance optimization, alerting
"""

import json
import time
import logging
import boto3
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import nvidia_ml_py3 as nvml
import psutil
import requests
import subprocess
import threading
from collections import deque
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/gpu-monitoring.log'),
        logging.StreamHandler()
    ]
)

class EnhancedGPUMonitor:
    def __init__(self, region='us-east-1'):
        self.region = region
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.sns = boto3.client('sns', region_name=region)
        
        # Initialize NVIDIA ML
        nvml.nvmlInit()
        self.device_count = nvml.nvmlDeviceGetCount()
        
        # Performance tracking
        self.metrics_history = deque(maxlen=1000)
        self.alert_cooldown = {}
        
        # Configuration
        self.namespace = "GPU/AI-Starter-Kit"
        self.instance_id = self._get_instance_id()
        self.sns_topic_arn = self._get_sns_topic_arn()
        
        # Thresholds
        self.thresholds = {
            'temperature_warning': 75,
            'temperature_critical': 85,
            'utilization_high': 90,
            'memory_high': 90,
            'power_high': 85
        }
        
        logging.info(f"Initialized GPU monitor for {self.device_count} GPU(s)")
    
    def _get_instance_id(self):
        try:
            response = requests.get(
                'http://169.254.169.254/latest/meta-data/instance-id',
                timeout=5
            )
            return response.text
        except:
            return 'unknown'
    
    def _get_sns_topic_arn(self):
        try:
            response = self.sns.list_topics()
            for topic in response['Topics']:
                if 'ai-starter-kit-gpu-alerts' in topic['TopicArn']:
                    return topic['TopicArn']
        except:
            pass
        return None
    
    def get_comprehensive_metrics(self):
        """Collect comprehensive GPU and system metrics"""
        metrics = {
            'timestamp': datetime.utcnow().isoformat(),
            'instance_id': self.instance_id,
            'gpus': [],
            'system': self._get_system_metrics(),
            'processes': self._get_gpu_processes()
        }
        
        for i in range(self.device_count):
            handle = nvml.nvmlDeviceGetHandleByIndex(i)
            gpu_metrics = self._get_gpu_metrics(handle, i)
            metrics['gpus'].append(gpu_metrics)
        
        return metrics
    
    def _get_gpu_metrics(self, handle, device_id):
        """Get detailed metrics for a single GPU"""
        # Basic info
        name = nvml.nvmlDeviceGetName(handle).decode('utf-8')
        
        # Memory info
        mem_info = nvml.nvmlDeviceGetMemoryInfo(handle)
        memory_total = mem_info.total / 1024**3  # GB
        memory_used = mem_info.used / 1024**3
        memory_free = mem_info.free / 1024**3
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
            power_util = (power_draw / power_limit) * 100
        except:
            power_draw = 0
            power_limit = 0
            power_util = 0
        
        # Clock speeds
        try:
            graphics_clock = nvml.nvmlDeviceGetClockInfo(handle, nvml.NVML_CLOCK_GRAPHICS)
            memory_clock = nvml.nvmlDeviceGetClockInfo(handle, nvml.NVML_CLOCK_MEM)
        except:
            graphics_clock = 0
            memory_clock = 0
        
        # Performance state
        try:
            perf_state = nvml.nvmlDeviceGetPerformanceState(handle)
        except:
            perf_state = 0
        
        # Fan speed
        try:
            fan_speed = nvml.nvmlDeviceGetFanSpeed(handle)
        except:
            fan_speed = 0
        
        # Processes
        try:
            processes = nvml.nvmlDeviceGetComputeRunningProcesses(handle)
            process_count = len(processes)
            total_process_memory = sum(p.usedGpuMemory for p in processes) / 1024**3
        except:
            process_count = 0
            total_process_memory = 0
        
        return {
            'device_id': device_id,
            'name': name,
            'memory': {
                'total_gb': round(memory_total, 2),
                'used_gb': round(memory_used, 2),
                'free_gb': round(memory_free, 2),
                'utilization_percent': round(memory_util, 2)
            },
            'utilization': {
                'gpu_percent': gpu_util,
                'memory_bandwidth_percent': memory_bandwidth_util
            },
            'thermal': {
                'temperature_celsius': temp,
                'fan_speed_percent': fan_speed
            },
            'power': {
                'draw_watts': round(power_draw, 2),
                'limit_watts': round(power_limit, 2),
                'utilization_percent': round(power_util, 2)
            },
            'clocks': {
                'graphics_mhz': graphics_clock,
                'memory_mhz': memory_clock
            },
            'performance_state': perf_state,
            'processes': {
                'count': process_count,
                'memory_gb': round(total_process_memory, 2)
            }
        }
    
    def _get_system_metrics(self):
        """Get system-wide metrics"""
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        return {
            'cpu_utilization_percent': cpu_percent,
            'memory': {
                'total_gb': round(memory.total / 1024**3, 2),
                'used_gb': round(memory.used / 1024**3, 2),
                'utilization_percent': memory.percent
            },
            'disk': {
                'total_gb': round(disk.total / 1024**3, 2),
                'used_gb': round(disk.used / 1024**3, 2),
                'utilization_percent': round((disk.used / disk.total) * 100, 2)
            }
        }
    
    def _get_gpu_processes(self):
        """Get detailed GPU process information"""
        processes = []
        
        for i in range(self.device_count):
            try:
                handle = nvml.nvmlDeviceGetHandleByIndex(i)
                gpu_processes = nvml.nvmlDeviceGetComputeRunningProcesses(handle)
                
                for proc in gpu_processes:
                    try:
                        process_info = psutil.Process(proc.pid)
                        processes.append({
                            'gpu_id': i,
                            'pid': proc.pid,
                            'name': process_info.name(),
                            'gpu_memory_mb': proc.usedGpuMemory / 1024**2,
                            'cpu_percent': process_info.cpu_percent(),
                            'memory_percent': process_info.memory_percent(),
                            'create_time': process_info.create_time()
                        })
                    except:
                        continue
            except:
                continue
        
        return processes
    
    def send_to_cloudwatch(self, metrics):
        """Send metrics to CloudWatch"""
        metric_data = []
        
        for gpu in metrics['gpus']:
            device_id = gpu['device_id']
            
            # GPU utilization metrics
            metric_data.extend([
                {
                    'MetricName': 'GPUUtilization',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': self.instance_id},
                        {'Name': 'GPUId', 'Value': str(device_id)}
                    ],
                    'Value': gpu['utilization']['gpu_percent'],
                    'Unit': 'Percent',
                    'Timestamp': metrics['timestamp']
                },
                {
                    'MetricName': 'GPUMemoryUtilization',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': self.instance_id},
                        {'Name': 'GPUId', 'Value': str(device_id)}
                    ],
                    'Value': gpu['memory']['utilization_percent'],
                    'Unit': 'Percent',
                    'Timestamp': metrics['timestamp']
                },
                {
                    'MetricName': 'GPUTemperature',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': self.instance_id},
                        {'Name': 'GPUId', 'Value': str(device_id)}
                    ],
                    'Value': gpu['thermal']['temperature_celsius'],
                    'Unit': 'None',
                    'Timestamp': metrics['timestamp']
                },
                {
                    'MetricName': 'GPUPowerDraw',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': self.instance_id},
                        {'Name': 'GPUId', 'Value': str(device_id)}
                    ],
                    'Value': gpu['power']['draw_watts'],
                    'Unit': 'None',
                    'Timestamp': metrics['timestamp']
                }
            ])
        
        # System metrics
        metric_data.extend([
            {
                'MetricName': 'CPUUtilization',
                'Dimensions': [{'Name': 'InstanceId', 'Value': self.instance_id}],
                'Value': metrics['system']['cpu_utilization_percent'],
                'Unit': 'Percent',
                'Timestamp': metrics['timestamp']
            },
            {
                'MetricName': 'MemoryUtilization',
                'Dimensions': [{'Name': 'InstanceId', 'Value': self.instance_id}],
                'Value': metrics['system']['memory']['utilization_percent'],
                'Unit': 'Percent',
                'Timestamp': metrics['timestamp']
            }
        ])
        
        # Send to CloudWatch in batches
        batch_size = 20
        for i in range(0, len(metric_data), batch_size):
            batch = metric_data[i:i + batch_size]
            try:
                self.cloudwatch.put_metric_data(
                    Namespace=self.namespace,
                    MetricData=batch
                )
                logging.debug(f"Sent {len(batch)} metrics to CloudWatch")
            except Exception as e:
                logging.error(f"Failed to send metrics to CloudWatch: {e}")
    
    def check_alerts(self, metrics):
        """Check for alert conditions"""
        alerts = []
        
        for gpu in metrics['gpus']:
            device_id = gpu['device_id']
            
            # Temperature alerts
            temp = gpu['thermal']['temperature_celsius']
            if temp >= self.thresholds['temperature_critical']:
                alerts.append({
                    'level': 'CRITICAL',
                    'message': f"GPU {device_id} temperature critical: {temp}°C",
                    'metric': 'temperature',
                    'value': temp,
                    'threshold': self.thresholds['temperature_critical']
                })
            elif temp >= self.thresholds['temperature_warning']:
                alerts.append({
                    'level': 'WARNING',
                    'message': f"GPU {device_id} temperature high: {temp}°C",
                    'metric': 'temperature',
                    'value': temp,
                    'threshold': self.thresholds['temperature_warning']
                })
            
            # Utilization alerts
            gpu_util = gpu['utilization']['gpu_percent']
            if gpu_util >= self.thresholds['utilization_high']:
                alerts.append({
                    'level': 'INFO',
                    'message': f"GPU {device_id} high utilization: {gpu_util}%",
                    'metric': 'utilization',
                    'value': gpu_util,
                    'threshold': self.thresholds['utilization_high']
                })
            
            # Memory alerts
            mem_util = gpu['memory']['utilization_percent']
            if mem_util >= self.thresholds['memory_high']:
                alerts.append({
                    'level': 'WARNING',
                    'message': f"GPU {device_id} high memory usage: {mem_util}%",
                    'metric': 'memory',
                    'value': mem_util,
                    'threshold': self.thresholds['memory_high']
                })
        
        return alerts
    
    def send_alerts(self, alerts):
        """Send alerts via SNS"""
        if not self.sns_topic_arn or not alerts:
            return
        
        for alert in alerts:
            alert_key = f"{alert['metric']}_{alert['level']}"
            current_time = time.time()
            
            # Check cooldown (5 minutes for warnings, 15 minutes for info)
            cooldown_period = 300 if alert['level'] in ['CRITICAL', 'WARNING'] else 900
            
            if alert_key in self.alert_cooldown:
                if current_time - self.alert_cooldown[alert_key] < cooldown_period:
                    continue
            
            # Send alert
            try:
                message = {
                    'alert_level': alert['level'],
                    'instance_id': self.instance_id,
                    'timestamp': datetime.utcnow().isoformat(),
                    'message': alert['message'],
                    'metric_value': alert['value'],
                    'threshold': alert['threshold']
                }
                
                self.sns.publish(
                    TopicArn=self.sns_topic_arn,
                    Subject=f"GPU Alert - {alert['level']}",
                    Message=json.dumps(message, indent=2)
                )
                
                self.alert_cooldown[alert_key] = current_time
                logging.info(f"Sent {alert['level']} alert: {alert['message']}")
                
            except Exception as e:
                logging.error(f"Failed to send alert: {e}")
    
    def start_monitoring(self, interval=30):
        """Start continuous monitoring"""
        logging.info(f"Starting GPU monitoring with {interval}s interval")
        
        while True:
            try:
                # Collect metrics
                metrics = self.get_comprehensive_metrics()
                self.metrics_history.append(metrics)
                
                # Send to CloudWatch
                self.send_to_cloudwatch(metrics)
                
                # Check for alerts
                alerts = self.check_alerts(metrics)
                if alerts:
                    self.send_alerts(alerts)
                
                # Log summary
                if metrics['gpus']:
                    gpu_temps = [gpu['thermal']['temperature_celsius'] for gpu in metrics['gpus']]
                    gpu_utils = [gpu['utilization']['gpu_percent'] for gpu in metrics['gpus']]
                    gpu_memory = [gpu['memory']['utilization_percent'] for gpu in metrics['gpus']]
                    
                    logging.info(
                        f"GPU Status - Temp: {gpu_temps}°C, "
                        f"Util: {gpu_utils}%, Mem: {gpu_memory}%"
                    )
                
                time.sleep(interval)
                
            except KeyboardInterrupt:
                logging.info("Monitoring stopped by user")
                break
            except Exception as e:
                logging.error(f"Monitoring error: {e}")
                time.sleep(interval)

if __name__ == "__main__":
    monitor = EnhancedGPUMonitor()
    monitor.start_monitoring()
EOF

    chmod +x "$MONITORING_DIR/gpu_monitor.py"
    log "✅ Main monitoring script created"
}

create_performance_dashboard() {
    log "Creating performance dashboard script..."
    
    cat > "$MONITORING_DIR/performance_dashboard.py" << 'EOF'
#!/usr/bin/env python3
"""
GPU Performance Dashboard Generator
Creates real-time performance visualizations
"""

import json
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import boto3
import seaborn as sns
from flask import Flask, render_template_string, jsonify
import threading
import time

class GPUPerformanceDashboard:
    def __init__(self, region='us-east-1'):
        self.region = region
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.namespace = "GPU/AI-Starter-Kit"
        
        # Flask app for web dashboard
        self.app = Flask(__name__)
        self.setup_routes()
        
        # Data storage
        self.latest_metrics = {}
        self.historical_data = []
        
    def setup_routes(self):
        @self.app.route('/')
        def dashboard():
            return render_template_string(DASHBOARD_TEMPLATE)
        
        @self.app.route('/api/metrics')
        def api_metrics():
            return jsonify(self.latest_metrics)
        
        @self.app.route('/api/historical')
        def api_historical():
            return jsonify(self.historical_data[-100:])  # Last 100 data points
    
    def get_cloudwatch_metrics(self, hours=1):
        """Fetch metrics from CloudWatch"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        
        metrics_queries = [
            {
                'name': 'GPUUtilization',
                'metric': 'GPUUtilization',
                'stat': 'Average'
            },
            {
                'name': 'GPUTemperature',
                'metric': 'GPUTemperature',
                'stat': 'Average'
            },
            {
                'name': 'GPUMemoryUtilization',
                'metric': 'GPUMemoryUtilization',
                'stat': 'Average'
            },
            {
                'name': 'GPUPowerDraw',
                'metric': 'GPUPowerDraw',
                'stat': 'Average'
            }
        ]
        
        data = {}
        
        for query in metrics_queries:
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace=self.namespace,
                    MetricName=query['metric'],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,  # 5 minutes
                    Statistics=[query['stat']]
                )
                
                data[query['name']] = [
                    {
                        'timestamp': point['Timestamp'].isoformat(),
                        'value': point[query['stat']]
                    }
                    for point in sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
                ]
            except Exception as e:
                print(f"Error fetching {query['name']}: {e}")
                data[query['name']] = []
        
        return data
    
    def update_metrics(self):
        """Update metrics periodically"""
        while True:
            try:
                self.latest_metrics = self.get_cloudwatch_metrics(hours=1)
                self.historical_data.append({
                    'timestamp': datetime.utcnow().isoformat(),
                    'metrics': self.latest_metrics
                })
                
                # Keep only last 24 hours of data
                if len(self.historical_data) > 288:  # 24 hours * 12 (5-min intervals)
                    self.historical_data = self.historical_data[-288:]
                    
            except Exception as e:
                print(f"Error updating metrics: {e}")
            
            time.sleep(300)  # Update every 5 minutes
    
    def start_dashboard(self, host='0.0.0.0', port=3000):
        """Start the web dashboard"""
        # Start metrics update thread
        metrics_thread = threading.Thread(target=self.update_metrics, daemon=True)
        metrics_thread.start()
        
        # Start Flask app
        print(f"Starting dashboard on http://{host}:{port}")
        self.app.run(host=host, port=port, debug=False)

# HTML template for dashboard
DASHBOARD_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>GPU Performance Dashboard</title>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .metric-card { 
            display: inline-block; 
            margin: 10px; 
            padding: 20px; 
            border: 1px solid #ddd; 
            border-radius: 5px; 
            min-width: 200px; 
        }
        .metric-value { font-size: 2em; font-weight: bold; }
        .metric-label { color: #666; }
        .chart-container { width: 100%; height: 400px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>GPU Performance Dashboard</h1>
    
    <div id="metrics-summary"></div>
    
    <div class="chart-container">
        <div id="gpu-utilization-chart"></div>
    </div>
    
    <div class="chart-container">
        <div id="gpu-temperature-chart"></div>
    </div>
    
    <div class="chart-container">
        <div id="gpu-memory-chart"></div>
    </div>
    
    <script>
        function updateDashboard() {
            fetch('/api/metrics')
                .then(response => response.json())
                .then(data => {
                    updateMetricsSummary(data);
                    updateCharts(data);
                })
                .catch(error => console.error('Error:', error));
        }
        
        function updateMetricsSummary(data) {
            const summary = document.getElementById('metrics-summary');
            let html = '';
            
            // Calculate latest values
            const latest = {
                utilization: getLatestValue(data.GPUUtilization),
                temperature: getLatestValue(data.GPUTemperature),
                memory: getLatestValue(data.GPUMemoryUtilization),
                power: getLatestValue(data.GPUPowerDraw)
            };
            
            html += createMetricCard('GPU Utilization', latest.utilization, '%');
            html += createMetricCard('Temperature', latest.temperature, '°C');
            html += createMetricCard('Memory Usage', latest.memory, '%');
            html += createMetricCard('Power Draw', latest.power, 'W');
            
            summary.innerHTML = html;
        }
        
        function createMetricCard(label, value, unit) {
            return `
                <div class="metric-card">
                    <div class="metric-label">${label}</div>
                    <div class="metric-value">${value !== null ? value.toFixed(1) : 'N/A'}${unit}</div>
                </div>
            `;
        }
        
        function getLatestValue(dataArray) {
            if (!dataArray || dataArray.length === 0) return null;
            return dataArray[dataArray.length - 1].value;
        }
        
        function updateCharts(data) {
            // GPU Utilization Chart
            if (data.GPUUtilization) {
                const utilizationTrace = {
                    x: data.GPUUtilization.map(d => d.timestamp),
                    y: data.GPUUtilization.map(d => d.value),
                    type: 'scatter',
                    mode: 'lines',
                    name: 'GPU Utilization',
                    line: { color: '#1f77b4' }
                };
                
                Plotly.newPlot('gpu-utilization-chart', [utilizationTrace], {
                    title: 'GPU Utilization (%)',
                    xaxis: { title: 'Time' },
                    yaxis: { title: 'Utilization (%)' }
                });
            }
            
            // Temperature Chart
            if (data.GPUTemperature) {
                const tempTrace = {
                    x: data.GPUTemperature.map(d => d.timestamp),
                    y: data.GPUTemperature.map(d => d.value),
                    type: 'scatter',
                    mode: 'lines',
                    name: 'GPU Temperature',
                    line: { color: '#ff7f0e' }
                };
                
                Plotly.newPlot('gpu-temperature-chart', [tempTrace], {
                    title: 'GPU Temperature (°C)',
                    xaxis: { title: 'Time' },
                    yaxis: { title: 'Temperature (°C)' }
                });
            }
            
            // Memory Chart
            if (data.GPUMemoryUtilization) {
                const memoryTrace = {
                    x: data.GPUMemoryUtilization.map(d => d.timestamp),
                    y: data.GPUMemoryUtilization.map(d => d.value),
                    type: 'scatter',
                    mode: 'lines',
                    name: 'GPU Memory',
                    line: { color: '#2ca02c' }
                };
                
                Plotly.newPlot('gpu-memory-chart', [memoryTrace], {
                    title: 'GPU Memory Utilization (%)',
                    xaxis: { title: 'Time' },
                    yaxis: { title: 'Memory Usage (%)' }
                });
            }
        }
        
        // Update every 30 seconds
        updateDashboard();
        setInterval(updateDashboard, 30000);
    </script>
</body>
</html>
'''

if __name__ == "__main__":
    dashboard = GPUPerformanceDashboard()
    dashboard.start_dashboard()
EOF

    chmod +x "$MONITORING_DIR/performance_dashboard.py"
    log "✅ Performance dashboard created"
}

# =============================================================================
# CLOUDWATCH AND SNS SETUP
# =============================================================================

setup_cloudwatch_alerts() {
    log "Setting up CloudWatch alarms..."
    
    # Create SNS topic for alerts
    SNS_TOPIC_ARN=$(aws sns create-topic --region "$REGION" --name "$SNS_TOPIC_NAME" --query 'TopicArn' --output text)
    log "Created SNS topic: $SNS_TOPIC_ARN"
    
    # Create CloudWatch alarms
    local alarms=(
        "GPU-High-Temperature|GPUTemperature|GreaterThanThreshold|80|2|300"
        "GPU-High-Utilization|GPUUtilization|GreaterThanThreshold|90|3|300"
        "GPU-High-Memory|GPUMemoryUtilization|GreaterThanThreshold|90|2|300"
        "GPU-High-Power|GPUPowerDraw|GreaterThanThreshold|200|2|300"
    )
    
    for alarm_config in "${alarms[@]}"; do
        IFS='|' read -r alarm_name metric_name comparison threshold periods period <<< "$alarm_config"
        
        aws cloudwatch put-metric-alarm \
            --region "$REGION" \
            --alarm-name "$alarm_name" \
            --alarm-description "GPU monitoring alarm for $metric_name" \
            --metric-name "$metric_name" \
            --namespace "$CLOUDWATCH_NAMESPACE" \
            --statistic Average \
            --period "$period" \
            --threshold "$threshold" \
            --comparison-operator "$comparison" \
            --evaluation-periods "$periods" \
            --alarm-actions "$SNS_TOPIC_ARN" \
            --treat-missing-data notBreaching
        
        log "Created alarm: $alarm_name"
    done
}

create_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    local dashboard_body=$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CLOUDWATCH_NAMESPACE", "GPUUtilization" ],
                    [ ".", "GPUMemoryUtilization" ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$REGION",
                "title": "GPU Utilization",
                "period": 300
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CLOUDWATCH_NAMESPACE", "GPUTemperature" ]
                ],
                "view": "timeSeries",
                "region": "$REGION",
                "title": "GPU Temperature",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "$CLOUDWATCH_NAMESPACE", "GPUPowerDraw" ]
                ],
                "view": "timeSeries",
                "region": "$REGION",
                "title": "GPU Power Draw",
                "period": 300
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/EC2", "CPUUtilization" ],
                    [ "$CLOUDWATCH_NAMESPACE", "MemoryUtilization" ]
                ],
                "view": "timeSeries",
                "region": "$REGION",
                "title": "System Resources",
                "period": 300
            }
        }
    ]
}
EOF
    )
    
    aws cloudwatch put-dashboard \
        --region "$REGION" \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body "$dashboard_body"
    
    log "✅ CloudWatch dashboard created: $DASHBOARD_NAME"
}

# =============================================================================
# SYSTEMD SERVICE SETUP
# =============================================================================

create_systemd_services() {
    log "Creating systemd services..."
    
    # GPU Monitor service
    cat > /etc/systemd/system/gpu-monitor.service << EOF
[Unit]
Description=Enhanced GPU Monitor for AI Starter Kit
After=network.target nvidia-persistenced.service
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $MONITORING_DIR/gpu_monitor.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Performance Dashboard service
    cat > /etc/systemd/system/gpu-dashboard.service << EOF
[Unit]
Description=GPU Performance Dashboard
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $MONITORING_DIR/performance_dashboard.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start services
    systemctl daemon-reload
    systemctl enable gpu-monitor.service
    systemctl enable gpu-dashboard.service
    systemctl start gpu-monitor.service
    systemctl start gpu-dashboard.service
    
    log "✅ Systemd services created and started"
}

# =============================================================================
# PERFORMANCE TESTING UTILITIES
# =============================================================================

create_performance_tools() {
    log "Creating performance testing tools..."
    
    cat > "$MONITORING_DIR/gpu_stress_test.py" << 'EOF'
#!/usr/bin/env python3
"""
GPU Stress Test for Performance Validation
"""

import numpy as np
import time
import argparse
from nvidia_ml_py3 import *

def gpu_stress_test(duration_minutes=5, memory_fraction=0.8):
    """Run GPU stress test"""
    print(f"Starting GPU stress test for {duration_minutes} minutes...")
    
    nvmlInit()
    device_count = nvmlDeviceGetCount()
    
    if device_count == 0:
        print("No NVIDIA GPUs found")
        return
    
    # Get GPU memory info
    handle = nvmlDeviceGetHandleByIndex(0)
    mem_info = nvmlDeviceGetMemoryInfo(handle)
    available_memory = int(mem_info.total * memory_fraction)
    
    print(f"Using {available_memory / 1024**3:.1f}GB of {mem_info.total / 1024**3:.1f}GB GPU memory")
    
    try:
        import cupy as cp
        
        # Allocate GPU memory
        array_size = available_memory // 8  # 8 bytes per float64
        gpu_array = cp.random.random((int(np.sqrt(array_size)), int(np.sqrt(array_size))), dtype=cp.float64)
        
        end_time = time.time() + (duration_minutes * 60)
        
        while time.time() < end_time:
            # Matrix operations to stress GPU
            result = cp.matmul(gpu_array, gpu_array.T)
            result = cp.sin(result)
            result = cp.cos(result)
            
            # Print progress every 30 seconds
            remaining = int(end_time - time.time())
            if remaining % 30 == 0:
                temp = nvmlDeviceGetTemperature(handle, NVML_TEMPERATURE_GPU)
                util = nvmlDeviceGetUtilizationRates(handle)
                print(f"Time remaining: {remaining}s, GPU: {util.gpu}%, Temp: {temp}°C")
        
        print("Stress test completed successfully")
        
    except ImportError:
        print("CuPy not available, using CPU-based stress test")
        # Fallback to CPU-based test
        for i in range(duration_minutes * 60):
            np.random.random((1000, 1000)) @ np.random.random((1000, 1000))
            time.sleep(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='GPU Stress Test')
    parser.add_argument('--duration', type=int, default=5, help='Test duration in minutes')
    parser.add_argument('--memory', type=float, default=0.8, help='Memory fraction to use')
    args = parser.parse_args()
    
    gpu_stress_test(args.duration, args.memory)
EOF

    chmod +x "$MONITORING_DIR/gpu_stress_test.py"
    
    # Create quick status script
    cat > /usr/local/bin/gpu-status << 'EOF'
#!/bin/bash
echo "=== GPU Status ==="
nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits
echo ""
echo "=== GPU Processes ==="
nvidia-smi --query-compute-apps=pid,process_name,gpu_instance_id,used_memory --format=csv,noheader,nounits
echo ""
echo "=== Monitoring Services ==="
systemctl status gpu-monitor.service --no-pager -l
systemctl status gpu-dashboard.service --no-pager -l
EOF

    chmod +x /usr/local/bin/gpu-status
    
    log "✅ Performance tools created"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log "=== Starting Enhanced GPU Monitoring Setup ==="
    
    # Pre-flight checks
    check_dependencies
    
    # Install monitoring components
    install_monitoring_dependencies
    create_monitoring_scripts
    create_performance_dashboard
    
    # Set up cloud monitoring
    setup_cloudwatch_alerts
    create_cloudwatch_dashboard
    
    # Create systemd services
    create_systemd_services
    
    # Performance testing tools
    create_performance_tools
    
    log "=== GPU Monitoring Setup Complete ==="
    log ""
    log "Services:"
    log "  • GPU Monitor: systemctl status gpu-monitor"
    log "  • Performance Dashboard: http://localhost:3000"
    log "  • CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards:name=$DASHBOARD_NAME"
    log ""
    log "Commands:"
    log "  • Check GPU status: gpu-status"
    log "  • Run stress test: python3 $MONITORING_DIR/gpu_stress_test.py"
    log "  • View logs: journalctl -u gpu-monitor -f"
    log ""
    log "Monitoring is now active with CloudWatch integration and alerting"
}

# Execute main function
main "$@" 