# n8n Workflows API Reference

> Complete API documentation for n8n workflow automation service

n8n is a powerful workflow automation tool that connects various services and APIs to create complex automation pipelines. This document covers all n8n API endpoints and integration patterns available in the AI Starter Kit.

## 🌟 Service Overview

| Property | Details |
|----------|---------|
| **Service** | n8n Workflow Automation |
| **Port** | 5678 |
| **Protocol** | HTTP/HTTPS |
| **Authentication** | Basic Auth / API Key |
| **Documentation** | Built-in API documentation at `/docs` |

## 🔐 Authentication

### Basic Authentication
Default authentication method for development:

```bash
# Username/password authentication
curl -u "username:password" http://your-ip:5678/api/v1/workflows
```

### API Key Authentication
Recommended for production use:

```bash
# API key in header
curl -H "X-N8N-API-KEY: your-api-key" http://your-ip:5678/api/v1/workflows

# API key as bearer token
curl -H "Authorization: Bearer your-api-key" http://your-ip:5678/api/v1/workflows
```

### Creating API Keys

1. **Access n8n Interface**: Navigate to `http://your-ip:5678`
2. **User Settings**: Click on user menu → Settings
3. **API Keys**: Navigate to API Keys section
4. **Generate Key**: Create new API key with appropriate permissions

## 📚 Core API Endpoints

### Workflows

#### List All Workflows
```bash
GET /api/v1/workflows
```

**Response:**
```json
{
  "data": [
    {
      "id": "1",
      "name": "My Workflow",
      "active": true,
      "createdAt": "2024-01-01T12:00:00Z",
      "updatedAt": "2024-01-01T12:00:00Z",
      "nodes": [...],
      "connections": {...}
    }
  ]
}
```

#### Get Specific Workflow
```bash
GET /api/v1/workflows/{id}
```

#### Create New Workflow
```bash
POST /api/v1/workflows
Content-Type: application/json

{
  "name": "New Workflow",
  "nodes": [...],
  "connections": {...}
}
```

#### Update Workflow
```bash
PUT /api/v1/workflows/{id}
Content-Type: application/json

{
  "name": "Updated Workflow",
  "nodes": [...],
  "connections": {...}
}
```

#### Delete Workflow
```bash
DELETE /api/v1/workflows/{id}
```

#### Activate/Deactivate Workflow
```bash
PATCH /api/v1/workflows/{id}/activate
PATCH /api/v1/workflows/{id}/deactivate
```

### Executions

#### Execute Workflow
```bash
POST /api/v1/workflows/{id}/execute
Content-Type: application/json

{
  "data": {
    "input": "your input data"
  }
}
```

**Response:**
```json
{
  "data": {
    "executionId": "execution-123",
    "startedAt": "2024-01-01T12:00:00Z",
    "status": "running"
  }
}
```

#### Get Execution Status
```bash
GET /api/v1/executions/{executionId}
```

#### List Executions
```bash
GET /api/v1/executions?workflowId={id}&limit=10&offset=0
```

#### Get Execution Results
```bash
GET /api/v1/executions/{executionId}/results
```

### Credentials

#### List Credentials
```bash
GET /api/v1/credentials
```

#### Create Credential
```bash
POST /api/v1/credentials
Content-Type: application/json

{
  "name": "My API Credential",
  "type": "httpBasicAuth",
  "data": {
    "user": "username",
    "password": "password"
  }
}
```

## 🔄 Workflow Management

### Workflow Structure

A complete workflow definition includes:

```json
{
  "name": "Example Workflow",
  "active": true,
  "nodes": [
    {
      "id": "node-1",
      "name": "Start",
      "type": "n8n-nodes-base.start",
      "typeVersion": 1,
      "position": [240, 300],
      "parameters": {}
    },
    {
      "id": "node-2", 
      "name": "HTTP Request",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 1,
      "position": [460, 300],
      "parameters": {
        "url": "https://api.example.com/data",
        "method": "GET"
      }
    }
  ],
  "connections": {
    "Start": {
      "main": [
        [
          {
            "node": "HTTP Request",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}
```

### Triggering Workflows

#### Webhook Triggers
```bash
# Setup webhook trigger in workflow
POST /webhook/{webhook-id}

# Example webhook URL
http://your-ip:5678/webhook/my-webhook-id
```

#### Manual Triggers
```bash
# Execute workflow manually
POST /api/v1/workflows/{id}/execute
```

#### Scheduled Triggers
Configure cron expressions in workflow nodes:
```json
{
  "type": "n8n-nodes-base.cron",
  "parameters": {
    "rule": {
      "interval": [
        {
          "field": "cronExpression",
          "expression": "0 9 * * 1-5"
        }
      ]
    }
  }
}
```

## 🤖 AI Service Integration

### Ollama LLM Integration

Example workflow node for LLM processing:

```json
{
  "name": "Ollama LLM",
  "type": "n8n-nodes-base.httpRequest",
  "parameters": {
    "url": "http://localhost:11434/api/generate",
    "method": "POST",
    "body": {
      "model": "llama2",
      "prompt": "={{ $json.input_text }}",
      "stream": false
    },
    "options": {
      "timeout": 30000
    }
  }
}
```

### Qdrant Vector Database Integration

```json
{
  "name": "Qdrant Search",
  "type": "n8n-nodes-base.httpRequest", 
  "parameters": {
    "url": "http://localhost:6333/collections/my_collection/points/search",
    "method": "POST",
    "headers": {
      "api-key": "={{ $credentials.qdrant.apiKey }}"
    },
    "body": {
      "vector": "={{ $json.embedding }}",
      "limit": 5,
      "with_payload": true
    }
  }
}
```

### Crawl4AI Integration

```json
{
  "name": "Web Scraping",
  "type": "n8n-nodes-base.httpRequest",
  "parameters": {
    "url": "http://localhost:11235/crawl",
    "method": "POST", 
    "body": {
      "urls": ["{{ $json.target_url }}"],
      "extract_text": true,
      "extract_links": true
    }
  }
}
```

## 📊 Advanced Features

### Error Handling

Configure error handling in workflows:

```json
{
  "settings": {
    "continueOnFail": true,
    "retryOnFail": true,
    "maxTries": 3
  },
  "onError": "continueRegularOutput"
}
```

### Data Transformation

Use expressions for data manipulation:

```javascript
// In node parameters
{
  "transformed_data": "={{ $json.raw_data.map(item => ({
    id: item.id,
    name: item.name.toUpperCase(),
    processed_at: new Date().toISOString()
  })) }}"
}
```

### Conditional Logic

Implement conditional routing:

```json
{
  "name": "IF Node",
  "type": "n8n-nodes-base.if",
  "parameters": {
    "conditions": {
      "string": [
        {
          "value1": "={{ $json.status }}",
          "operation": "equal",
          "value2": "success"
        }
      ]
    }
  }
}
```

## 🔄 Workflow Examples

### Example 1: AI Content Processing Pipeline

```bash
# Create content processing workflow
curl -X POST http://your-ip:5678/api/v1/workflows \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "AI Content Pipeline",
    "nodes": [
      {
        "id": "webhook",
        "name": "Webhook Trigger",
        "type": "n8n-nodes-base.webhook",
        "parameters": {
          "httpMethod": "POST",
          "path": "content-process"
        }
      },
      {
        "id": "crawl",
        "name": "Extract Content",
        "type": "n8n-nodes-base.httpRequest",
        "parameters": {
          "url": "http://localhost:11235/crawl",
          "method": "POST",
          "body": {
            "urls": ["{{ $json.url }}"],
            "extract_text": true
          }
        }
      },
      {
        "id": "llm",
        "name": "Analyze Content",
        "type": "n8n-nodes-base.httpRequest", 
        "parameters": {
          "url": "http://localhost:11434/api/generate",
          "method": "POST",
          "body": {
            "model": "llama2",
            "prompt": "Summarize this content: {{ $json.text }}",
            "stream": false
          }
        }
      }
    ],
    "connections": {
      "Webhook Trigger": {
        "main": [
          [{"node": "Extract Content", "type": "main", "index": 0}]
        ]
      },
      "Extract Content": {
        "main": [
          [{"node": "Analyze Content", "type": "main", "index": 0}]
        ]
      }
    }
  }'
```

### Example 2: Scheduled Data Processing

```bash
# Create scheduled workflow
curl -X POST http://your-ip:5678/api/v1/workflows \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Daily Data Processing",
    "active": true,
    "nodes": [
      {
        "id": "schedule",
        "name": "Daily Trigger",
        "type": "n8n-nodes-base.cron",
        "parameters": {
          "rule": {
            "interval": [
              {
                "field": "cronExpression", 
                "expression": "0 9 * * *"
              }
            ]
          }
        }
      },
      {
        "id": "fetch", 
        "name": "Fetch Data",
        "type": "n8n-nodes-base.httpRequest",
        "parameters": {
          "url": "https://api.example.com/daily-data",
          "method": "GET"
        }
      },
      {
        "id": "store",
        "name": "Store in Vector DB",
        "type": "n8n-nodes-base.httpRequest",
        "parameters": {
          "url": "http://localhost:6333/collections/daily_data/points",
          "method": "POST",
          "body": {
            "points": "={{ $json.data.map((item, index) => ({
              id: index,
              vector: item.embedding,
              payload: item
            })) }}"
          }
        }
      }
    ]
  }'
```

## 🔍 Monitoring and Debugging

### Workflow Execution Monitoring

```bash
# Get execution statistics
curl -H "Authorization: Bearer your-api-key" \
  "http://your-ip:5678/api/v1/executions?workflowId=1&limit=100"

# Get failed executions
curl -H "Authorization: Bearer your-api-key" \
  "http://your-ip:5678/api/v1/executions?status=error&limit=50"
```

### Debugging Workflows

```bash
# Get detailed execution data
curl -H "Authorization: Bearer your-api-key" \
  "http://your-ip:5678/api/v1/executions/{executionId}/debug"

# Get execution logs
curl -H "Authorization: Bearer your-api-key" \
  "http://your-ip:5678/api/v1/executions/{executionId}/logs"
```

### Performance Monitoring

```bash
# Get workflow performance metrics
curl -H "Authorization: Bearer your-api-key" \
  "http://your-ip:5678/api/v1/workflows/{id}/metrics?period=24h"
```

## 🛠️ Administration

### User Management

```bash
# List users
GET /api/v1/users

# Create user
POST /api/v1/users
{
  "email": "user@example.com",
  "firstName": "John",
  "lastName": "Doe",
  "password": "securepassword"
}

# Update user permissions
PATCH /api/v1/users/{id}/role
{
  "role": "admin"
}
```

### Settings Management

```bash
# Get instance settings
GET /api/v1/settings

# Update settings
PATCH /api/v1/settings
{
  "security.basicAuth.active": true,
  "endpoints.webhook.url": "https://your-domain.com"
}
```

## 🚨 Error Handling and Best Practices

### Common Error Codes

| Code | Message | Solution |
|------|---------|----------|
| 400 | Invalid workflow structure | Validate workflow JSON schema |
| 401 | Authentication failed | Check API key or credentials |
| 403 | Insufficient permissions | Verify user role and permissions |
| 404 | Workflow not found | Confirm workflow ID exists |
| 429 | Rate limit exceeded | Implement request throttling |
| 500 | Internal server error | Check n8n logs and service health |

### Best Practices

**Workflow Design:**
- Use meaningful node names and descriptions
- Implement error handling for all external API calls
- Add timeouts for long-running operations
- Use variables for reusable values

**Security:**
- Use credentials storage for sensitive data
- Enable authentication in production
- Restrict webhook access as needed
- Regular credential rotation

**Performance:**
- Limit concurrent executions for resource-intensive workflows
- Use appropriate timeouts
- Monitor execution times and optimize slow nodes
- Consider workflow complexity and execution frequency

**Monitoring:**
- Set up execution monitoring
- Configure error alerting
- Log important execution data
- Regular backup of workflow definitions

## 📚 Integration Patterns

### RESTful API Integration

```json
{
  "name": "REST API Call",
  "type": "n8n-nodes-base.httpRequest",
  "parameters": {
    "url": "https://api.example.com/endpoint",
    "method": "POST",
    "authentication": "predefinedCredentialType",
    "nodeCredentialType": "httpBasicAuth",
    "body": {
      "data": "={{ $json.inputData }}"
    },
    "options": {
      "timeout": 10000,
      "retry": {
        "enabled": true,
        "maxRetries": 3
      }
    }
  }
}
```

### Database Integration

```json
{
  "name": "Database Query",
  "type": "n8n-nodes-base.postgres",
  "parameters": {
    "operation": "executeQuery",
    "query": "SELECT * FROM users WHERE created_at > $1",
    "additionalFields": {
      "queryParameters": "={{ [$json.since_date] }}"
    }
  }
}
```

### File Processing

```json
{
  "name": "Process File",
  "type": "n8n-nodes-base.readBinaryFile",
  "parameters": {
    "filePath": "={{ $json.file_path }}"
  }
}
```

## 📞 Support and Resources

### Built-in Documentation
- **API Docs**: `http://your-ip:5678/docs` - Interactive API documentation
- **Node Reference**: Available in n8n editor interface
- **Workflow Templates**: Built-in template gallery

### External Resources
- [**n8n Official Documentation**](https://docs.n8n.io/)
- [**Community Forum**](https://community.n8n.io/)
- [**GitHub Repository**](https://github.com/n8n-io/n8n)

### Troubleshooting
- [**Common Issues Guide**](../../guides/troubleshooting/n8n-issues.md)
- [**Performance Tuning**](../../guides/configuration/n8n-performance.md)
- [**Security Configuration**](../../guides/configuration/n8n-security.md)

---

[**← Back to API Overview**](README.md) | [**→ Ollama API Reference**](ollama-endpoints.md)

---

**API Version:** n8n 1.x  
**Last Updated:** January 2025  
**Service Compatibility:** All AI Starter Kit deployments