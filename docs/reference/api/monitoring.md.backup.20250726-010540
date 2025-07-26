# Monitoring API Reference

> Complete API documentation for monitoring, metrics, and health check endpoints

GeuseMaker includes comprehensive monitoring capabilities through CloudWatch, custom health checks, and service-specific metrics endpoints. This document covers all monitoring APIs and integration patterns.

## 🌟 Monitoring Overview

| Component | Purpose | Port | Protocol | Documentation |
|-----------|---------|------|----------|---------------|
| **Health Checks** | Service availability | Various | HTTP | This document |
| **CloudWatch** | AWS-native monitoring | N/A | AWS API | [AWS CloudWatch API](https://docs.aws.amazon.com/cloudwatch/) |
| **Custom Metrics** | Application metrics | 9090 | HTTP | This document |
| **Log Aggregation** | Centralized logging | N/A | CloudWatch Logs | This document |

## 📊 Health Check Endpoints

### System Health Check

#### Overall System Health
```bash
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "version": "2.0.0",
  "uptime": "2d 14h 32m",
  "services": {
    "n8n": "healthy",
    "ollama": "healthy", 
    "qdrant": "healthy",
    "crawl4ai": "healthy"
  },
  "system": {
    "cpu_usage": 45.2,
    "memory_usage": 67.8,
    "disk_usage": 34.1,
    "load_average": [1.2, 1.5, 1.8]
  }
}
```

#### Detailed Health Report
```bash
GET /health/detailed
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "services": {
    "n8n": {
      "status": "healthy",
      "response_time": 45,
      "last_check": "2024-01-01T12:00:00Z",
      "version": "1.15.0",
      "active_workflows": 5,
      "total_executions": 1247
    },
    "ollama": {
      "status": "healthy",
      "response_time": 120,
      "last_check": "2024-01-01T12:00:00Z",
      "version": "0.1.15",
      "loaded_models": ["llama2", "codellama"],
      "gpu_memory_usage": 4096,
      "total_memory": 8192
    },
    "qdrant": {
      "status": "healthy",
      "response_time": 15,
      "last_check": "2024-01-01T12:00:00Z",
      "version": "1.7.0",
      "collections": 3,
      "total_points": 125000,
      "cluster_status": "green"
    },
    "crawl4ai": {
      "status": "healthy",
      "response_time": 89,
      "last_check": "2024-01-01T12:00:00Z",
      "version": "0.2.0",
      "active_sessions": 2,
      "total_crawls": 456
    }
  },
  "infrastructure": {
    "instance_id": "i-1234567890abcdef0",
    "instance_type": "g4dn.xlarge",
    "availability_zone": "us-east-1a",
    "vpc_id": "vpc-12345678",
    "security_groups": ["sg-12345678"]
  }
}
```

### Service-Specific Health Checks

#### n8n Health Check
```bash
GET /health/n8n
```

#### Ollama Health Check
```bash
GET /health/ollama
```

#### Qdrant Health Check
```bash
GET /health/qdrant
```

#### Crawl4AI Health Check  
```bash
GET /health/crawl4ai
```

### Readiness and Liveness Probes

#### Readiness Check
```bash
GET /ready
```

**Response:**
```json
{
  "ready": true,
  "services_ready": 4,
  "services_total": 4,
  "boot_time": "45s"
}
```

#### Liveness Check
```bash
GET /live
```

**Response:**
```json
{
  "alive": true,
  "last_heartbeat": "2024-01-01T12:00:00Z"
}
```

## 📈 Metrics Endpoints

### System Metrics

#### CPU and Memory Metrics
```bash
GET /metrics/system
```

**Response:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "cpu": {
    "usage_percent": 45.2,
    "load_average": {
      "1min": 1.2,
      "5min": 1.5, 
      "15min": 1.8
    },
    "cores": 4
  },
  "memory": {
    "total_mb": 16384,
    "used_mb": 11108,
    "free_mb": 5276,
    "usage_percent": 67.8,
    "swap_used_mb": 256
  },
  "disk": {
    "total_gb": 100,
    "used_gb": 34,
    "free_gb": 66,
    "usage_percent": 34.1,
    "io_read_mb": 1024,
    "io_write_mb": 512
  }
}
```

#### Network Metrics
```bash
GET /metrics/network
```

**Response:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "interfaces": {
    "eth0": {
      "bytes_in": 1073741824,
      "bytes_out": 536870912,
      "packets_in": 1000000,
      "packets_out": 800000,
      "errors_in": 0,
      "errors_out": 0
    }
  },
  "connections": {
    "tcp_established": 25,
    "tcp_listen": 8,
    "tcp_time_wait": 12
  }
}
```

### Service Metrics

#### n8n Metrics
```bash
GET /metrics/n8n
```

**Response:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "workflows": {
    "total": 15,
    "active": 12,
    "paused": 3
  },
  "executions": {
    "total": 5247,
    "success": 5100,
    "failed": 147,
    "running": 5,
    "last_24h": 156
  },
  "performance": {
    "avg_execution_time": 2.5,
    "max_execution_time": 45.6,
    "queue_length": 3
  }
}
```

#### Ollama Metrics
```bash
GET /metrics/ollama
```

**Response:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "models": {
    "loaded": ["llama2", "codellama", "nomic-embed-text"],
    "total_size_mb": 4096
  },
  "requests": {
    "total": 2847,
    "last_24h": 234,
    "avg_response_time": 1.8,
    "max_response_time": 15.2
  },
  "gpu": {
    "memory_used_mb": 4096,
    "memory_total_mb": 8192,
    "utilization_percent": 65.4,
    "temperature": 68
  }
}
```

#### Qdrant Metrics
```bash
GET /metrics/qdrant
```

**Response:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "collections": {
    "total": 5,
    "total_points": 125000,
    "total_vectors": 125000,
    "indexed_vectors": 125000
  },
  "storage": {
    "disk_usage_mb": 2048,
    "memory_usage_mb": 1024
  },
  "operations": {
    "searches_total": 5678,
    "searches_last_24h": 456,
    "avg_search_time_ms": 15.2,
    "insertions_total": 125000,
    "insertions_last_24h": 1200
  }
}
```

#### Crawl4AI Metrics
```bash
GET /metrics/crawl4ai
```

**Response:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "crawls": {
    "total": 3456,
    "success": 3234,
    "failed": 222,
    "last_24h": 189
  },
  "performance": {
    "avg_crawl_time_ms": 2500,
    "max_crawl_time_ms": 15000,
    "active_sessions": 3,
    "queue_length": 7
  },
  "cache": {
    "size_mb": 128,
    "hit_rate": 0.75,
    "entries": 1247
  }
}
```

### Custom Application Metrics

#### Business Metrics
```bash
GET /metrics/application
```

**Response:**
```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "user_activity": {
    "active_users": 25,
    "total_sessions": 156,
    "avg_session_duration": 1800
  },
  "ai_operations": {
    "llm_requests": 2847,
    "vector_searches": 5678,
    "workflow_executions": 1247,
    "web_crawls": 456
  },
  "error_rates": {
    "total_errors": 23,
    "error_rate_percent": 0.8,
    "critical_errors": 2
  }
}
```

## 🔍 Log Management

### Log Aggregation Endpoints

#### Recent Logs
```bash
GET /logs?service=n8n&level=error&limit=100
```

**Response:**
```json
{
  "logs": [
    {
      "timestamp": "2024-01-01T12:00:00Z",
      "level": "error",
      "service": "n8n",
      "message": "Workflow execution failed",
      "details": {
        "workflow_id": "123",
        "execution_id": "456",
        "error": "Connection timeout"
      }
    }
  ],
  "total": 100,
  "has_more": true
}
```

#### Log Search
```bash
POST /logs/search
Content-Type: application/json

{
  "query": "error OR failed",
  "services": ["n8n", "ollama"],
  "start_time": "2024-01-01T00:00:00Z",
  "end_time": "2024-01-01T23:59:59Z",
  "limit": 500
}
```

### CloudWatch Integration

#### Send Custom Metrics to CloudWatch
```bash
POST /cloudwatch/metrics
Content-Type: application/json

{
  "namespace": "GeuseMaker/Custom",
  "metrics": [
    {
      "metric_name": "WorkflowExecutions",
      "value": 156,
      "unit": "Count",
      "dimensions": {
        "InstanceId": "i-1234567890abcdef0",
        "Environment": "production"
      }
    }
  ]
}
```

#### Query CloudWatch Metrics
```bash
GET /cloudwatch/metrics?metric=CPUUtilization&start=2024-01-01T00:00:00Z&end=2024-01-01T23:59:59Z
```

## 🚨 Alerting Integration

### Alert Configuration

#### Create Alert Rule
```bash
POST /alerts/rules
Content-Type: application/json

{
  "name": "High CPU Usage",
  "condition": {
    "metric": "cpu.usage_percent",
    "operator": ">",
    "threshold": 80,
    "duration": "5m"
  },
  "severity": "warning",
  "notifications": [
    {
      "type": "webhook",
      "url": "https://hooks.slack.com/services/...",
      "message": "High CPU usage detected: {{value}}%"
    }
  ]
}
```

#### List Active Alerts
```bash
GET /alerts/active
```

**Response:**
```json
{
  "alerts": [
    {
      "id": "alert_123",
      "name": "High Memory Usage",
      "severity": "critical",
      "status": "firing",
      "started_at": "2024-01-01T11:45:00Z",
      "value": 92.5,
      "threshold": 90
    }
  ]
}
```

### Webhook Notifications

#### Alert Webhook Format
```json
{
  "alert_id": "alert_123",
  "alert_name": "High CPU Usage",
  "severity": "warning",
  "status": "firing",
  "timestamp": "2024-01-01T12:00:00Z",
  "instance": "i-1234567890abcdef0",
  "metric": "cpu.usage_percent",
  "current_value": 85.2,
  "threshold": 80,
  "duration": "7m",
  "runbook_url": "https://docs.example.com/runbooks/high-cpu"
}
```

## 🔄 Integration Examples

### Python Monitoring Client

```python
import requests
import time
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

class MonitoringClient:
    def __init__(self, base_url: str = "http://localhost:9090"):
        self.base_url = base_url
        self.session = requests.Session()
    
    def get_system_health(self) -> Dict[str, Any]:
        """Get overall system health status"""
        response = self.session.get(f"{self.base_url}/health")
        return response.json()
    
    def get_detailed_health(self) -> Dict[str, Any]:
        """Get detailed health information for all services"""
        response = self.session.get(f"{self.base_url}/health/detailed")
        return response.json()
    
    def get_service_health(self, service: str) -> Dict[str, Any]:
        """Get health status for a specific service"""
        response = self.session.get(f"{self.base_url}/health/{service}")
        return response.json()
    
    def get_system_metrics(self) -> Dict[str, Any]:
        """Get system resource metrics"""
        response = self.session.get(f"{self.base_url}/metrics/system")
        return response.json()
    
    def get_service_metrics(self, service: str) -> Dict[str, Any]:
        """Get metrics for a specific service"""
        response = self.session.get(f"{self.base_url}/metrics/{service}")
        return response.json()
    
    def send_custom_metric(self, metric_name: str, value: float, 
                          dimensions: Optional[Dict[str, str]] = None):
        """Send custom metric to CloudWatch"""
        data = {
            "namespace": "GeuseMaker/Custom",
            "metrics": [
                {
                    "metric_name": metric_name,
                    "value": value,
                    "unit": "Count",
                    "dimensions": dimensions or {}
                }
            ]
        }
        
        response = self.session.post(f"{self.base_url}/cloudwatch/metrics", json=data)
        return response.json()
    
    def search_logs(self, query: str, services: List[str] = None, 
                   start_time: datetime = None, limit: int = 100) -> Dict[str, Any]:
        """Search logs with specified criteria"""
        data = {
            "query": query,
            "limit": limit
        }
        
        if services:
            data["services"] = services
        
        if start_time:
            data["start_time"] = start_time.isoformat()
        
        response = self.session.post(f"{self.base_url}/logs/search", json=data)
        return response.json()
    
    def create_alert_rule(self, name: str, metric: str, operator: str,
                         threshold: float, duration: str = "5m") -> Dict[str, Any]:
        """Create a new alert rule"""
        data = {
            "name": name,
            "condition": {
                "metric": metric,
                "operator": operator,
                "threshold": threshold,
                "duration": duration
            },
            "severity": "warning"
        }
        
        response = self.session.post(f"{self.base_url}/alerts/rules", json=data)
        return response.json()
    
    def get_active_alerts(self) -> List[Dict[str, Any]]:
        """Get list of currently active alerts"""
        response = self.session.get(f"{self.base_url}/alerts/active")
        return response.json().get("alerts", [])

# Usage examples
monitor = MonitoringClient()

# Check overall system health
health = monitor.get_system_health()
print(f"System status: {health['status']}")

# Monitor specific service
ollama_health = monitor.get_service_health("ollama")
print(f"Ollama status: {ollama_health['status']}")

# Get system metrics
metrics = monitor.get_system_metrics()
print(f"CPU usage: {metrics['cpu']['usage_percent']}%")
print(f"Memory usage: {metrics['memory']['usage_percent']}%")

# Send custom metric
monitor.send_custom_metric("UserLogins", 45, {"Environment": "production"})

# Search for errors in logs
errors = monitor.search_logs("error OR failed", ["n8n", "ollama"], limit=50)
print(f"Found {len(errors['logs'])} error logs")

# Create alert for high memory usage
alert = monitor.create_alert_rule(
    "High Memory Alert",
    "memory.usage_percent", 
    ">", 
    85.0, 
    "10m"
)
print(f"Created alert: {alert}")
```

### Monitoring Dashboard Integration

```javascript
class MonitoringDashboard {
    constructor(baseUrl = 'http://localhost:9090') {
        this.baseUrl = baseUrl;
        this.updateInterval = 30000; // 30 seconds
        this.charts = {};
    }

    async init() {
        await this.setupDashboard();
        this.startAutoUpdate();
    }

    async setupDashboard() {
        // Initialize dashboard components
        await this.loadSystemHealth();
        await this.loadServiceMetrics();
        await this.loadSystemMetrics();
        await this.loadActiveAlerts();
    }

    async loadSystemHealth() {
        try {
            const response = await fetch(`${this.baseUrl}/health/detailed`);
            const health = await response.json();
            this.updateHealthStatus(health);
        } catch (error) {
            console.error('Failed to load system health:', error);
        }
    }

    async loadServiceMetrics() {
        const services = ['n8n', 'ollama', 'qdrant', 'crawl4ai'];
        
        for (const service of services) {
            try {
                const response = await fetch(`${this.baseUrl}/metrics/${service}`);
                const metrics = await response.json();
                this.updateServiceMetrics(service, metrics);
            } catch (error) {
                console.error(`Failed to load ${service} metrics:`, error);
            }
        }
    }

    async loadSystemMetrics() {
        try {
            const response = await fetch(`${this.baseUrl}/metrics/system`);
            const metrics = await response.json();
            this.updateSystemCharts(metrics);
        } catch (error) {
            console.error('Failed to load system metrics:', error);
        }
    }

    async loadActiveAlerts() {
        try {
            const response = await fetch(`${this.baseUrl}/alerts/active`);
            const alerts = await response.json();
            this.updateAlertsPanel(alerts.alerts);
        } catch (error) {
            console.error('Failed to load alerts:', error);
        }
    }

    updateHealthStatus(health) {
        // Update health status indicators
        const statusElement = document.getElementById('system-status');
        statusElement.className = `status ${health.status}`;
        statusElement.textContent = health.status.toUpperCase();

        // Update service status indicators
        Object.entries(health.services).forEach(([service, data]) => {
            const element = document.getElementById(`${service}-status`);
            if (element) {
                element.className = `service-status ${data.status}`;
                element.textContent = data.status;
            }
        });
    }

    updateServiceMetrics(service, metrics) {
        // Update service-specific metrics display
        const container = document.getElementById(`${service}-metrics`);
        if (container) {
            container.innerHTML = this.formatServiceMetrics(service, metrics);
        }
    }

    updateSystemCharts(metrics) {
        // Update CPU chart
        if (this.charts.cpu) {
            this.charts.cpu.data.datasets[0].data.push(metrics.cpu.usage_percent);
            this.charts.cpu.data.labels.push(new Date().toLocaleTimeString());
            
            // Keep only last 20 data points
            if (this.charts.cpu.data.datasets[0].data.length > 20) {
                this.charts.cpu.data.datasets[0].data.shift();
                this.charts.cpu.data.labels.shift();
            }
            
            this.charts.cpu.update();
        }

        // Update memory chart
        if (this.charts.memory) {
            this.charts.memory.data.datasets[0].data.push(metrics.memory.usage_percent);
            this.charts.memory.data.labels.push(new Date().toLocaleTimeString());
            
            if (this.charts.memory.data.datasets[0].data.length > 20) {
                this.charts.memory.data.datasets[0].data.shift();
                this.charts.memory.data.labels.shift();
            }
            
            this.charts.memory.update();
        }
    }

    updateAlertsPanel(alerts) {
        const alertsContainer = document.getElementById('alerts-panel');
        
        if (alerts.length === 0) {
            alertsContainer.innerHTML = '<div class="no-alerts">No active alerts</div>';
            return;
        }

        const alertsHtml = alerts.map(alert => `
            <div class="alert alert-${alert.severity}">
                <div class="alert-title">${alert.name}</div>
                <div class="alert-details">
                    <span class="alert-value">${alert.value}</span>
                    <span class="alert-threshold">Threshold: ${alert.threshold}</span>
                    <span class="alert-duration">Duration: ${this.formatDuration(alert.started_at)}</span>
                </div>
            </div>
        `).join('');

        alertsContainer.innerHTML = alertsHtml;
    }

    formatServiceMetrics(service, metrics) {
        // Format service metrics for display
        switch (service) {
            case 'ollama':
                return `
                    <div class="metric">
                        <label>GPU Usage:</label>
                        <span>${metrics.gpu?.utilization_percent || 0}%</span>
                    </div>
                    <div class="metric">
                        <label>Models Loaded:</label>
                        <span>${metrics.models?.loaded?.length || 0}</span>
                    </div>
                    <div class="metric">
                        <label>Requests (24h):</label>
                        <span>${metrics.requests?.last_24h || 0}</span>
                    </div>
                `;
            
            case 'qdrant':
                return `
                    <div class="metric">
                        <label>Collections:</label>
                        <span>${metrics.collections?.total || 0}</span>
                    </div>
                    <div class="metric">
                        <label>Total Points:</label>
                        <span>${metrics.collections?.total_points || 0}</span>
                    </div>
                    <div class="metric">
                        <label>Searches (24h):</label>
                        <span>${metrics.operations?.searches_last_24h || 0}</span>
                    </div>
                `;
            
            default:
                return '<div class="metric">Metrics not available</div>';
        }
    }

    formatDuration(startTime) {
        const now = new Date();
        const start = new Date(startTime);
        const diff = Math.floor((now - start) / 1000 / 60); // minutes
        
        if (diff < 60) {
            return `${diff}m`;
        } else {
            const hours = Math.floor(diff / 60);
            const minutes = diff % 60;
            return `${hours}h ${minutes}m`;
        }
    }

    startAutoUpdate() {
        setInterval(() => {
            this.loadSystemHealth();
            this.loadServiceMetrics();
            this.loadSystemMetrics();
            this.loadActiveAlerts();
        }, this.updateInterval);
    }
}

// Initialize dashboard
const dashboard = new MonitoringDashboard();
dashboard.init();
```

### Automated Health Checks

```python
import schedule
import time
import smtplib
from email.mime.text import MIMEText
from datetime import datetime

class HealthChecker:
    def __init__(self, monitoring_client, alert_config):
        self.monitor = monitoring_client
        self.alert_config = alert_config
        self.last_alert_times = {}
        
    def run_health_checks(self):
        """Run comprehensive health checks"""
        print(f"Running health checks at {datetime.now()}")
        
        # Check system health
        self.check_system_health()
        
        # Check individual services
        services = ['n8n', 'ollama', 'qdrant', 'crawl4ai']
        for service in services:
            self.check_service_health(service)
        
        # Check system resources
        self.check_system_resources()
        
    def check_system_health(self):
        """Check overall system health"""
        try:
            health = self.monitor.get_system_health()
            
            if health['status'] != 'healthy':
                self.send_alert(
                    'System Health Alert',
                    f"System status is {health['status']}",
                    'critical'
                )
        except Exception as e:
            self.send_alert(
                'Health Check Failed',
                f"Failed to check system health: {str(e)}",
                'critical'
            )
    
    def check_service_health(self, service):
        """Check individual service health"""
        try:
            health = self.monitor.get_service_health(service)
            
            if health['status'] != 'healthy':
                self.send_alert(
                    f'{service.upper()} Service Alert',
                    f"{service} service status is {health['status']}",
                    'warning'
                )
                
        except Exception as e:
            self.send_alert(
                f'{service.upper()} Check Failed',
                f"Failed to check {service} health: {str(e)}",
                'warning'
            )
    
    def check_system_resources(self):
        """Check system resource usage"""
        try:
            metrics = self.monitor.get_system_metrics()
            
            # Check CPU usage
            cpu_usage = metrics['cpu']['usage_percent']
            if cpu_usage > self.alert_config['cpu_threshold']:
                self.send_alert(
                    'High CPU Usage',
                    f"CPU usage is {cpu_usage}% (threshold: {self.alert_config['cpu_threshold']}%)",
                    'warning'
                )
            
            # Check memory usage
            memory_usage = metrics['memory']['usage_percent']
            if memory_usage > self.alert_config['memory_threshold']:
                self.send_alert(
                    'High Memory Usage',
                    f"Memory usage is {memory_usage}% (threshold: {self.alert_config['memory_threshold']}%)",
                    'warning'
                )
            
            # Check disk usage
            disk_usage = metrics['disk']['usage_percent']
            if disk_usage > self.alert_config['disk_threshold']:
                self.send_alert(
                    'High Disk Usage',
                    f"Disk usage is {disk_usage}% (threshold: {self.alert_config['disk_threshold']}%)",
                    'warning'
                )
                
        except Exception as e:
            self.send_alert(
                'Resource Check Failed',
                f"Failed to check system resources: {str(e)}",
                'critical'
            )
    
    def send_alert(self, subject, message, severity):
        """Send alert notification with rate limiting"""
        alert_key = f"{subject}_{severity}"
        current_time = time.time()
        
        # Rate limiting: don't send same alert more than once per hour
        if alert_key in self.last_alert_times:
            time_diff = current_time - self.last_alert_times[alert_key]
            if time_diff < 3600:  # 1 hour
                return
        
        self.last_alert_times[alert_key] = current_time
        
        # Send email alert
        if self.alert_config.get('email'):
            self.send_email_alert(subject, message, severity)
        
        # Send webhook alert
        if self.alert_config.get('webhook'):
            self.send_webhook_alert(subject, message, severity)
        
        print(f"ALERT [{severity}]: {subject} - {message}")
    
    def send_email_alert(self, subject, message, severity):
        """Send email alert"""
        try:
            msg = MIMEText(f"Severity: {severity}\n\n{message}")
            msg['Subject'] = f"[GeuseMaker] {subject}"
            msg['From'] = self.alert_config['email']['from']
            msg['To'] = self.alert_config['email']['to']
            
            with smtplib.SMTP(self.alert_config['email']['smtp_server']) as server:
                server.sendmail(
                    self.alert_config['email']['from'],
                    self.alert_config['email']['to'],
                    msg.as_string()
                )
        except Exception as e:
            print(f"Failed to send email alert: {e}")
    
    def send_webhook_alert(self, subject, message, severity):
        """Send webhook alert (e.g., to Slack)"""
        try:
            import requests
            
            webhook_data = {
                "text": f"[{severity.upper()}] {subject}",
                "attachments": [
                    {
                        "color": "danger" if severity == "critical" else "warning",
                        "text": message,
                        "timestamp": int(time.time())
                    }
                ]
            }
            
            requests.post(self.alert_config['webhook']['url'], json=webhook_data)
        except Exception as e:
            print(f"Failed to send webhook alert: {e}")

# Configuration
monitor = MonitoringClient()
alert_config = {
    'cpu_threshold': 80,
    'memory_threshold': 85,
    'disk_threshold': 90,
    'email': {
        'smtp_server': 'localhost',
        'from': 'alerts@example.com',
        'to': 'admin@example.com'
    },
    'webhook': {
        'url': 'https://hooks.slack.com/services/...'
    }
}

# Setup health checker
health_checker = HealthChecker(monitor, alert_config)

# Schedule health checks
schedule.every(5).minutes.do(health_checker.run_health_checks)

# Run scheduler
while True:
    schedule.run_pending()
    time.sleep(60)
```

## 📊 Performance Monitoring Best Practices

### Metric Collection Strategy
- Collect metrics at appropriate intervals (not too frequent to avoid overhead)
- Use appropriate aggregation methods (average, max, percentiles)
- Implement proper data retention policies
- Monitor key business metrics alongside technical metrics

### Alert Configuration
- Set meaningful thresholds based on historical data
- Implement alert escalation and de-escalation
- Avoid alert fatigue with proper filtering and grouping
- Include actionable information in alerts

### Dashboard Design
- Focus on key metrics and KPIs
- Use appropriate visualizations for different data types
- Implement drill-down capabilities
- Ensure dashboards load quickly

### Log Management
- Structure logs consistently across services
- Include appropriate context and correlation IDs
- Implement log rotation and archival
- Use centralized logging for better observability

---

[**← Back to API Overview**](README.md)

---

**Last Updated:** January 2025  
**Service Compatibility:** All GeuseMaker deployments  
**Dependencies:** CloudWatch, Custom health check services