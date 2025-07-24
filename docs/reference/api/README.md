# API Reference Overview

> Complete API documentation for all GeuseMaker services

The GeuseMaker provides multiple APIs for different AI and automation services. This section provides comprehensive documentation for integrating with all available services.

## 🌟 Available Services

| Service | Purpose | API Type | Port | Documentation |
|---------|---------|----------|------|---------------|
| **n8n** | Workflow automation | REST API | 5678 | [n8n API Reference](n8n-workflows.md) |
| **Ollama** | Large Language Models | REST API | 11434 | [Ollama API Reference](ollama-endpoints.md) |
| **Qdrant** | Vector Database | REST API | 6333 | [Qdrant API Reference](qdrant-collections.md) |
| **Crawl4AI** | Web Crawling | REST API | 11235 | [Crawl4AI API Reference](crawl4ai-service.md) |
| **Monitoring** | Metrics & Health | REST API | Various | [Monitoring API Reference](monitoring.md) |

## 🚀 Quick API Examples

### Basic Health Check
Test all services with a simple health check:

```bash
# Check all services
curl http://your-ip:5678/healthz    # n8n
curl http://your-ip:11434/api/tags  # Ollama
curl http://your-ip:6333/health     # Qdrant
curl http://your-ip:11235/health    # Crawl4AI
```

### Simple LLM Query
```bash
curl -X POST http://your-ip:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "prompt": "What is artificial intelligence?",
    "stream": false
  }'
```

### Vector Search
```bash
curl -X POST http://your-ip:6333/collections/my_collection/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, 0.4],
    "limit": 5
  }'
```

## 🔐 Authentication

### Service Authentication

| Service | Authentication Method | Default Config |
|---------|----------------------|----------------|
| **n8n** | Basic Auth / API Key | Basic Auth enabled |
| **Ollama** | None (local) | Open access |
| **Qdrant** | API Key (optional) | API key configured |
| **Crawl4AI** | None (local) | Open access |

### Environment-Specific Authentication

**Development:**
- Most services use basic authentication or no authentication
- API keys are optional for local development

**Production:**
- All services should use API key authentication
- Consider implementing reverse proxy with additional security
- Use HTTPS for all external access

## 📊 API Response Formats

All APIs return JSON responses with consistent error handling:

### Success Response Format
```json
{
  "status": "success",
  "data": {
    // Service-specific response data
  },
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### Error Response Format
```json
{
  "status": "error",
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {
      // Additional error context
    }
  },
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### Common HTTP Status Codes

| Code | Meaning | When Used |
|------|---------|-----------|
| 200 | OK | Request successful |
| 201 | Created | Resource created successfully |
| 400 | Bad Request | Invalid request parameters |
| 401 | Unauthorized | Authentication required |
| 403 | Forbidden | Access denied |
| 404 | Not Found | Resource not found |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |

## 🔄 API Integration Patterns

### Synchronous Processing
For immediate response requirements:

```javascript
// Example: Simple LLM query
const response = await fetch('http://your-ip:11434/api/generate', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    model: 'llama2',
    prompt: 'Your question here',
    stream: false
  })
});

const result = await response.json();
console.log(result.response);
```

### Asynchronous Processing
For long-running operations:

```javascript
// Example: n8n workflow execution
const execution = await fetch('http://your-ip:5678/api/v1/workflows/123/execute', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer your-api-key',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ inputData: {...} })
});

// Poll for completion
const executionId = execution.executionId;
// Check status periodically...
```

### Streaming Responses
For real-time data:

```javascript
// Example: Streaming LLM responses
const response = await fetch('http://your-ip:11434/api/generate', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    model: 'llama2',
    prompt: 'Your question here',
    stream: true
  })
});

const reader = response.body.getReader();
// Process streaming chunks...
```

## 🛠️ SDKs and Client Libraries

### Official SDKs

**JavaScript/TypeScript:**
```bash
npm install @n8n/client ollama-js qdrant-js
```

**Python:**
```bash
pip install n8n-client ollama qdrant-client requests
```

### Example Integration Code

**Python Integration:**
```python
import requests
from qdrant_client import QdrantClient
import ollama

# Initialize clients
qdrant = QdrantClient(host="your-ip", port=6333)
ollama_client = ollama.Client(host="http://your-ip:11434")

# Example: RAG pipeline
def rag_query(question, collection_name):
    # 1. Generate embedding for question
    embedding = ollama_client.embeddings(model="nomic-embed-text", prompt=question)
    
    # 2. Search similar documents
    results = qdrant.search(
        collection_name=collection_name,
        query_vector=embedding['embedding'],
        limit=5
    )
    
    # 3. Generate response with context
    context = "\n".join([r.payload['text'] for r in results])
    response = ollama_client.generate(
        model="llama2",
        prompt=f"Context: {context}\n\nQuestion: {question}\n\nAnswer:"
    )
    
    return response['response']
```

**Node.js Integration:**
```javascript
const axios = require('axios');
const { QdrantClient } = require('@qdrant/js-client-rest');

const baseURL = 'http://your-ip';
const qdrant = new QdrantClient({ host: 'your-ip', port: 6333 });

async function executeWorkflow(workflowId, inputData) {
  try {
    const response = await axios.post(
      `${baseURL}:5678/api/v1/workflows/${workflowId}/execute`,
      { inputData },
      {
        headers: {
          'Authorization': 'Bearer your-api-key',
          'Content-Type': 'application/json'
        }
      }
    );
    return response.data;
  } catch (error) {
    console.error('Workflow execution failed:', error.response.data);
    throw error;
  }
}
```

## 📈 Rate Limits and Performance

### Default Rate Limits

| Service | Requests/Minute | Concurrent Requests | Notes |
|---------|----------------|-------------------|-------|
| **n8n** | 100 | 10 | Per workflow |
| **Ollama** | 60 | 3 | GPU memory dependent |
| **Qdrant** | 1000 | 50 | Memory dependent |
| **Crawl4AI** | 30 | 5 | Respect target site limits |

### Performance Optimization

**LLM Performance:**
- Use smaller models for faster responses
- Implement response caching for repeated queries
- Consider model quantization for memory efficiency

**Vector Database Performance:**
- Use appropriate indexing for your use case
- Batch operations when possible
- Monitor memory usage

**Workflow Performance:**
- Optimize workflow design for efficiency
- Use appropriate trigger types
- Monitor execution times

## 🔍 Monitoring and Debugging

### API Health Monitoring

```bash
# Health check script
#!/bin/bash
services=("n8n:5678/healthz" "ollama:11434/api/tags" "qdrant:6333/health" "crawl4ai:11235/health")

for service in "${services[@]}"; do
  if curl -f -s http://your-ip:$service > /dev/null; then
    echo "✅ ${service%:*} is healthy"
  else
    echo "❌ ${service%:*} is unhealthy"
  fi
done
```

### Request Logging

Enable request logging for debugging:

```javascript
// Add request interceptor
axios.interceptors.request.use(request => {
  console.log('Starting Request:', request.url, request.data);
  return request;
});

axios.interceptors.response.use(
  response => {
    console.log('Response:', response.status, response.data);
    return response;
  },
  error => {
    console.error('Error:', error.response?.status, error.response?.data);
    return Promise.reject(error);
  }
);
```

### Performance Monitoring

```python
import time
import functools

def monitor_api_call(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start_time = time.time()
        try:
            result = func(*args, **kwargs)
            duration = time.time() - start_time
            print(f"✅ {func.__name__} completed in {duration:.2f}s")
            return result
        except Exception as e:
            duration = time.time() - start_time
            print(f"❌ {func.__name__} failed after {duration:.2f}s: {e}")
            raise
    return wrapper

@monitor_api_call
def call_ollama_api(prompt):
    # Your API call here
    pass
```

## 🚨 Error Handling Best Practices

### Retry Logic
```python
import time
import random
from typing import Callable, Any

def retry_with_backoff(
    func: Callable, 
    max_retries: int = 3, 
    base_delay: float = 1.0,
    max_delay: float = 60.0
) -> Any:
    """Retry function with exponential backoff"""
    for attempt in range(max_retries):
        try:
            return func()
        except Exception as e:
            if attempt == max_retries - 1:
                raise e
            
            delay = min(base_delay * (2 ** attempt) + random.uniform(0, 1), max_delay)
            print(f"Attempt {attempt + 1} failed, retrying in {delay:.2f}s...")
            time.sleep(delay)
```

### Circuit Breaker Pattern
```python
class CircuitBreaker:
    def __init__(self, failure_threshold=5, timeout=60):
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.failure_count = 0
        self.last_failure_time = None
        self.state = 'closed'  # closed, open, half-open
    
    def call(self, func, *args, **kwargs):
        if self.state == 'open':
            if time.time() - self.last_failure_time > self.timeout:
                self.state = 'half-open'
            else:
                raise Exception("Circuit breaker is open")
        
        try:
            result = func(*args, **kwargs)
            self.reset()
            return result
        except Exception as e:
            self.record_failure()
            raise e
    
    def record_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        if self.failure_count >= self.failure_threshold:
            self.state = 'open'
    
    def reset(self):
        self.failure_count = 0
        self.state = 'closed'
```

## 📚 Next Steps

### Service-Specific Documentation
- [**n8n Workflows API**](n8n-workflows.md) - Workflow automation and management
- [**Ollama API**](ollama-endpoints.md) - Large Language Model operations
- [**Qdrant API**](qdrant-collections.md) - Vector database operations  
- [**Crawl4AI API**](crawl4ai-service.md) - Web crawling and extraction
- [**Monitoring APIs**](monitoring.md) - System monitoring and metrics

### Integration Examples
- [**Basic Integration Examples**](../../examples/basic/) - Simple API usage patterns
- [**Advanced Integration Examples**](../../examples/advanced/) - Complex integration patterns
- [**Third-Party Integrations**](../../examples/integrations/) - External service connections

### Development Resources
- [**CLI Reference**](../cli/) - Command-line tools and automation
- [**Configuration Reference**](../configuration/) - Service configuration options
- [**Troubleshooting Guide**](../../guides/troubleshooting/) - Common API issues and solutions

---

[**← Back to Documentation Hub**](../../README.md) | [**→ n8n API Reference**](n8n-workflows.md)

---

**API Version:** 2.0  
**Last Updated:** January 2025  
**Service Compatibility:** All GeuseMaker deployments