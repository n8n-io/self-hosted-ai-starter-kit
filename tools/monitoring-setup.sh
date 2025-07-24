#!/bin/bash
# =============================================================================
# Monitoring and Observability Setup
# Sets up comprehensive monitoring for GeuseMaker
# =============================================================================

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$PROJECT_ROOT/lib/aws-deployment-common.sh" ]; then
    source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
fi

if [ -f "$PROJECT_ROOT/lib/error-handling.sh" ]; then
    source "$PROJECT_ROOT/lib/error-handling.sh"
    init_error_handling "resilient"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly MONITORING_DIR="$PROJECT_ROOT/monitoring"
readonly GRAFANA_DIR="$MONITORING_DIR/grafana"
readonly PROMETHEUS_DIR="$MONITORING_DIR/prometheus"
readonly ALERTMANAGER_DIR="$MONITORING_DIR/alertmanager"

# =============================================================================
# PROMETHEUS SETUP
# =============================================================================

setup_prometheus() {
    log "Setting up Prometheus monitoring..."
    
    mkdir -p "$PROMETHEUS_DIR/config" "$PROMETHEUS_DIR/data"
    
    # Create Prometheus configuration
    cat > "$PROMETHEUS_DIR/config/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter (system metrics)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  # Docker containers
  - job_name: 'docker'
    static_configs:
      - targets: ['docker-exporter:9323']

  # GPU metrics (if available)
  - job_name: 'nvidia-gpu'
    static_configs:
      - targets: ['nvidia-exporter:9445']
    scrape_interval: 5s

  # Application metrics
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama:11434']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'qdrant'
    static_configs:
      - targets: ['qdrant:6333']
    metrics_path: /metrics
    scrape_interval: 30s

  # Custom application metrics
  - job_name: 'GeuseMaker'
    static_configs:
      - targets: ['metrics-exporter:8080']
    scrape_interval: 15s
EOF

    # Create alert rules
    cat > "$PROMETHEUS_DIR/config/alert_rules.yml" << 'EOF'
groups:
  - name: GeuseMaker-alerts
    rules:
      # System alerts
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for more than 5 minutes"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 90% for more than 5 minutes"

      - alert: DiskSpaceRunningLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space running low"
          description: "Available disk space is below 10%"

      # GPU alerts
      - alert: GPUHighTemperature
        expr: nvidia_gpu_temperature_celsius > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "GPU temperature high"
          description: "GPU temperature is above 80°C"

      - alert: GPUHighMemoryUsage
        expr: (nvidia_gpu_memory_used_bytes / nvidia_gpu_memory_total_bytes) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "GPU memory usage high"
          description: "GPU memory usage is above 90%"

      # Service alerts
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service is down"
          description: "{{ $labels.job }} service is not responding"

      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is above 10% for {{ $labels.job }}"

      # Application-specific alerts
      - alert: N8NWorkflowFailures
        expr: rate(n8n_workflow_executions_total{status="failed"}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High n8n workflow failure rate"
          description: "n8n workflow failure rate is above 10%"

      - alert: QdrantIndexingLag
        expr: qdrant_indexing_lag_seconds > 300
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Qdrant indexing lag detected"
          description: "Qdrant indexing is lagging by more than 5 minutes"
EOF

    success "Prometheus configuration created"
}

# =============================================================================
# GRAFANA SETUP
# =============================================================================

setup_grafana() {
    log "Setting up Grafana dashboards..."
    
    mkdir -p "$GRAFANA_DIR/config" "$GRAFANA_DIR/dashboards" "$GRAFANA_DIR/provisioning/datasources" "$GRAFANA_DIR/provisioning/dashboards"
    
    # Create Grafana configuration
    cat > "$GRAFANA_DIR/config/grafana.ini" << 'EOF'
[server]
http_port = 3000
domain = localhost

[security]
admin_user = admin
admin_password = ${GRAFANA_ADMIN_PASSWORD:-admin123}

[users]
allow_sign_up = false

[auth.anonymous]
enabled = false

[dashboards]
default_home_dashboard_path = /var/lib/grafana/dashboards/GeuseMaker-overview.json

[log]
mode = console
level = info
EOF

    # Create datasource provisioning
    cat > "$GRAFANA_DIR/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF

    # Create dashboard provisioning
    cat > "$GRAFANA_DIR/provisioning/dashboards/dashboards.yml" << 'EOF'
apiVersion: 1

providers:
  - name: 'GeuseMaker'
    orgId: 1
    folder: 'GeuseMaker'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards
EOF

    # Create main dashboard
    create_main_dashboard
    
    # Create service-specific dashboards
    create_system_dashboard
    create_gpu_dashboard
    create_application_dashboard
    
    success "Grafana configuration created"
}

create_main_dashboard() {
    cat > "$GRAFANA_DIR/dashboards/GeuseMaker-overview.json" << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "GeuseMaker Overview",
    "tags": ["GeuseMaker"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "System Overview",
        "type": "stat",
        "targets": [
          {
            "expr": "up",
            "legendFormat": "{{job}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "green", "value": 1}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU Usage %"
          }
        ],
        "yAxes": [
          {"max": 100, "min": 0, "unit": "percent"}
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "5s"
  }
}
EOF
}

create_system_dashboard() {
    cat > "$GRAFANA_DIR/dashboards/system-metrics.json" << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "System Metrics",
    "tags": ["GeuseMaker", "system"],
    "panels": [
      {
        "id": 1,
        "title": "CPU Usage by Core",
        "type": "graph",
        "targets": [
          {
            "expr": "100 - (avg by(cpu) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU {{cpu}}"
          }
        ]
      },
      {
        "id": 2,
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes",
            "legendFormat": "Used Memory"
          },
          {
            "expr": "node_memory_MemAvailable_bytes",
            "legendFormat": "Available Memory"
          }
        ]
      },
      {
        "id": 3,
        "title": "Disk I/O",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(node_disk_read_bytes_total[5m])",
            "legendFormat": "Read {{device}}"
          },
          {
            "expr": "rate(node_disk_written_bytes_total[5m])",
            "legendFormat": "Write {{device}}"
          }
        ]
      }
    ]
  }
}
EOF
}

create_gpu_dashboard() {
    cat > "$GRAFANA_DIR/dashboards/gpu-metrics.json" << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "GPU Metrics",
    "tags": ["GeuseMaker", "gpu"],
    "panels": [
      {
        "id": 1,
        "title": "GPU Utilization",
        "type": "graph",
        "targets": [
          {
            "expr": "nvidia_gpu_utilization_gpu",
            "legendFormat": "GPU {{gpu}}"
          }
        ]
      },
      {
        "id": 2,
        "title": "GPU Memory",
        "type": "graph",
        "targets": [
          {
            "expr": "nvidia_gpu_memory_used_bytes",
            "legendFormat": "Used {{gpu}}"
          },
          {
            "expr": "nvidia_gpu_memory_total_bytes",
            "legendFormat": "Total {{gpu}}"
          }
        ]
      },
      {
        "id": 3,
        "title": "GPU Temperature",
        "type": "graph",
        "targets": [
          {
            "expr": "nvidia_gpu_temperature_celsius",
            "legendFormat": "GPU {{gpu}} Temp"
          }
        ]
      }
    ]
  }
}
EOF
}

create_application_dashboard() {
    cat > "$GRAFANA_DIR/dashboards/application-metrics.json" << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Application Metrics",
    "tags": ["GeuseMaker", "applications"],
    "panels": [
      {
        "id": 1,
        "title": "Service Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=~\"n8n|ollama|qdrant|crawl4ai\"}",
            "legendFormat": "{{job}}"
          }
        ]
      },
      {
        "id": 2,
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{job}} Requests/sec"
          }
        ]
      },
      {
        "id": 3,
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "{{job}} 95th percentile"
          }
        ]
      }
    ]
  }
}
EOF
}

# =============================================================================
# ALERTMANAGER SETUP
# =============================================================================

setup_alertmanager() {
    log "Setting up Alertmanager..."
    
    mkdir -p "$ALERTMANAGER_DIR/config" "$ALERTMANAGER_DIR/data"
    
    cat > "$ALERTMANAGER_DIR/config/alertmanager.yml" << 'EOF'
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@GeuseMaker.local'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_URL}'
        channel: '#alerts'
        title: 'GeuseMaker Alert'
        text: 'Alert: {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
    
    email_configs:
      - to: '${ALERT_EMAIL}'
        subject: 'GeuseMaker Alert: {{ .GroupLabels.alertname }}'
        body: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          {{ end }}

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

    success "Alertmanager configuration created"
}

# =============================================================================
# DOCKER COMPOSE FOR MONITORING
# =============================================================================

create_monitoring_compose() {
    log "Creating monitoring Docker Compose configuration..."
    
    cat > "$MONITORING_DIR/docker-compose.monitoring.yml" << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v2.40.0
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/config:/etc/prometheus
      - ./prometheus/data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    restart: unless-stopped
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:9.3.0
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - ./grafana/config/grafana.ini:/etc/grafana/grafana.ini
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin123}
    restart: unless-stopped
    networks:
      - monitoring
    depends_on:
      - prometheus

  alertmanager:
    image: prom/alertmanager:v0.25.0
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/config:/etc/alertmanager
      - ./alertmanager/data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
      - '--web.external-url=http://localhost:9093'
    restart: unless-stopped
    networks:
      - monitoring

  node-exporter:
    image: prom/node-exporter:v1.5.0
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    restart: unless-stopped
    networks:
      - monitoring

  nvidia-exporter:
    image: nvidia/dcgm-exporter:3.1.8-3.1.5-ubuntu20.04
    container_name: nvidia-exporter
    ports:
      - "9445:9445"
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    restart: unless-stopped
    networks:
      - monitoring
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

volumes:
  grafana-data:

networks:
  monitoring:
    driver: bridge
EOF

    success "Monitoring Docker Compose configuration created"
}

# =============================================================================
# SETUP SCRIPTS
# =============================================================================

create_monitoring_scripts() {
    log "Creating monitoring management scripts..."
    
    # Start monitoring script
    cat > "$MONITORING_DIR/start-monitoring.sh" << 'EOF'
#!/bin/bash
set -e

echo "Starting GeuseMaker monitoring stack..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running"
    exit 1
fi

# Start monitoring services
docker-compose -f docker-compose.monitoring.yml up -d

echo "Monitoring services started:"
echo "- Prometheus: http://localhost:9090"
echo "- Grafana: http://localhost:3000 (admin/admin123)"
echo "- Alertmanager: http://localhost:9093"

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 30

# Check service health
echo "Checking service health..."
for service in prometheus:9090 grafana:3000 alertmanager:9093; do
    host=${service%:*}
    port=${service#*:}
    if curl -s --connect-timeout 5 "http://localhost:$port" >/dev/null; then
        echo "✅ $host is healthy"
    else
        echo "❌ $host is not responding"
    fi
done

echo "Monitoring setup complete!"
EOF

    # Stop monitoring script
    cat > "$MONITORING_DIR/stop-monitoring.sh" << 'EOF'
#!/bin/bash
set -e

echo "Stopping GeuseMaker monitoring stack..."

docker-compose -f docker-compose.monitoring.yml down

echo "Monitoring services stopped"
EOF

    # Monitoring status script
    cat > "$MONITORING_DIR/monitoring-status.sh" << 'EOF'
#!/bin/bash
set -e

echo "GeuseMaker Monitoring Status"
echo "================================"

# Check Docker services
echo "Docker Services:"
docker-compose -f docker-compose.monitoring.yml ps

echo ""
echo "Service Health:"
services=("prometheus:9090" "grafana:3000" "alertmanager:9093" "node-exporter:9100")

for service in "${services[@]}"; do
    host=${service%:*}
    port=${service#*:}
    if curl -s --connect-timeout 5 "http://localhost:$port" >/dev/null; then
        echo "✅ $host (port $port) - Healthy"
    else
        echo "❌ $host (port $port) - Unhealthy"
    fi
done

echo ""
echo "Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
EOF

    chmod +x "$MONITORING_DIR"/*.sh
    
    success "Monitoring management scripts created"
}

# =============================================================================
# MAIN SETUP FUNCTION
# =============================================================================

main() {
    local setup_type="all"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --prometheus-only)
                setup_type="prometheus"
                shift
                ;;
            --grafana-only)
                setup_type="grafana"
                shift
                ;;
            --alertmanager-only)
                setup_type="alertmanager"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--prometheus-only|--grafana-only|--alertmanager-only]"
                echo ""
                echo "Sets up monitoring and observability stack for GeuseMaker"
                echo ""
                echo "Options:"
                echo "  --prometheus-only    Setup only Prometheus"
                echo "  --grafana-only      Setup only Grafana"
                echo "  --alertmanager-only Setup only Alertmanager"
                echo "  --help              Show this help"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    log "Setting up monitoring and observability stack..."
    
    # Create monitoring directory structure
    mkdir -p "$MONITORING_DIR"
    
    case "$setup_type" in
        "prometheus")
            setup_prometheus
            ;;
        "grafana")
            setup_grafana
            ;;
        "alertmanager")
            setup_alertmanager
            ;;
        "all")
            setup_prometheus
            setup_grafana
            setup_alertmanager
            create_monitoring_compose
            create_monitoring_scripts
            ;;
    esac
    
    success "Monitoring setup completed!"
    
    info "Next steps:"
    info "1. Configure environment variables (SLACK_WEBHOOK_URL, ALERT_EMAIL, etc.)"
    info "2. Start monitoring: cd monitoring && ./start-monitoring.sh"
    info "3. Access Grafana: http://localhost:3000 (admin/admin123)"
    info "4. Access Prometheus: http://localhost:9090"
    info "5. Configure alerts: http://localhost:9093"
}

# Run main function
main "$@"