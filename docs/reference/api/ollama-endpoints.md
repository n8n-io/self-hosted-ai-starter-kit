# Ollama API Reference

> Complete API documentation for Ollama Large Language Model service

Ollama provides a simple REST API for running large language models locally. This document covers all available endpoints and integration patterns for the AI Starter Kit deployment.

## 🌟 Service Overview

| Property | Details |
|----------|---------|
| **Service** | Ollama LLM Server |
| **Port** | 11434 |
| **Protocol** | HTTP |
| **Authentication** | None (local access) |
| **Documentation** | [Ollama API Docs](https://github.com/ollama/ollama/blob/main/docs/api.md) |

## 🚀 Core API Endpoints

### Generate Completions

#### Text Generation
```bash
POST /api/generate
Content-Type: application/json

{
  "model": "llama2",
  "prompt": "Why is the sky blue?",
  "stream": false
}
```

**Response:**
```json
{
  "model": "llama2",
  "created_at": "2024-01-01T12:00:00Z",
  "response": "The sky appears blue due to a phenomenon called Rayleigh scattering...",
  "done": true,
  "context": [1, 2, 3, ...],
  "total_duration": 5000000000,
  "load_duration": 1000000000,
  "prompt_eval_count": 26,
  "prompt_eval_duration": 2000000000,
  "eval_count": 298,
  "eval_duration": 2000000000
}
```

#### Streaming Generation
```bash
POST /api/generate
Content-Type: application/json

{
  "model": "llama2", 
  "prompt": "Tell me a story",
  "stream": true
}
```

**Streaming Response:**
```json
{"model":"llama2","created_at":"2024-01-01T12:00:00Z","response":"Once","done":false}
{"model":"llama2","created_at":"2024-01-01T12:00:00Z","response":" upon","done":false}
{"model":"llama2","created_at":"2024-01-01T12:00:00Z","response":" a","done":false}
...
{"model":"llama2","created_at":"2024-01-01T12:00:00Z","response":"","done":true,"context":[...],"total_duration":5000000000}
```

### Chat Completions

#### Chat Interface
```bash
POST /api/chat
Content-Type: application/json

{
  "model": "llama2",
  "messages": [
    {
      "role": "user",
      "content": "Hello, how are you?"
    }
  ],
  "stream": false
}
```

**Response:**
```json
{
  "model": "llama2",
  "created_at": "2024-01-01T12:00:00Z",
  "message": {
    "role": "assistant",
    "content": "Hello! I'm doing well, thank you for asking. How can I help you today?"
  },
  "done": true,
  "total_duration": 4000000000,
  "load_duration": 500000000,
  "prompt_eval_count": 15,
  "prompt_eval_duration": 1500000000,
  "eval_count": 25,
  "eval_duration": 2000000000
}
```

#### Multi-turn Conversation
```bash
POST /api/chat
Content-Type: application/json

{
  "model": "llama2",
  "messages": [
    {
      "role": "user", 
      "content": "What is 2+2?"
    },
    {
      "role": "assistant",
      "content": "2+2 equals 4."
    },
    {
      "role": "user",
      "content": "What about 2+3?"
    }
  ]
}
```

### Model Management

#### List Available Models
```bash
GET /api/tags
```

**Response:**
```json
{
  "models": [
    {
      "name": "llama2:latest",
      "modified_at": "2024-01-01T12:00:00Z",
      "size": 3825819519,
      "digest": "sha256:abc123...",
      "details": {
        "format": "gguf",
        "family": "llama",
        "families": ["llama"],
        "parameter_size": "7B",
        "quantization_level": "Q4_0"
      }
    },
    {
      "name": "codellama:7b",
      "modified_at": "2024-01-01T11:00:00Z", 
      "size": 3825819519,
      "digest": "sha256:def456...",
      "details": {
        "format": "gguf",
        "family": "llama",
        "families": ["llama"],
        "parameter_size": "7B",
        "quantization_level": "Q4_0"
      }
    }
  ]
}
```

#### Show Model Information
```bash
POST /api/show
Content-Type: application/json

{
  "name": "llama2"
}
```

**Response:**
```json
{
  "modelfile": "FROM llama2:latest\nPARAMETER temperature 0.7",
  "parameters": "temperature 0.7\nstop \"<|im_end|>\"\nstop \"<|im_start|>\"",
  "template": "{{ if .System }}{{ .System }}{{ end }}{{ if .Prompt }}{{ .Prompt }}{{ end }}",
  "details": {
    "format": "gguf",
    "family": "llama",
    "families": ["llama"],
    "parameter_size": "7B",
    "quantization_level": "Q4_0"
  }
}
```

#### Pull Model
```bash
POST /api/pull
Content-Type: application/json

{
  "name": "llama2"
}
```

**Streaming Response:**
```json
{"status":"pulling manifest"}
{"status":"downloading","digest":"sha256:abc123...","total":3825819519,"completed":1000000}
{"status":"downloading","digest":"sha256:abc123...","total":3825819519,"completed":2000000}
...
{"status":"success"}
```

#### Delete Model
```bash
DELETE /api/delete
Content-Type: application/json

{
  "name": "llama2"
}
```

### Embeddings

#### Generate Embeddings
```bash
POST /api/embeddings
Content-Type: application/json

{
  "model": "nomic-embed-text",
  "prompt": "The quick brown fox jumps over the lazy dog"
}
```

**Response:**
```json
{
  "embedding": [0.123, -0.456, 0.789, ...],
  "total_duration": 1000000000,
  "load_duration": 100000000,
  "prompt_eval_count": 10
}
```

## 🔧 Advanced Parameters

### Generation Parameters

```bash
POST /api/generate
Content-Type: application/json

{
  "model": "llama2",
  "prompt": "Explain quantum computing",
  "stream": false,
  "options": {
    "temperature": 0.7,
    "top_p": 0.9,
    "top_k": 40,
    "repeat_penalty": 1.1,
    "seed": 42,
    "num_predict": 500,
    "stop": ["</s>", "Human:"]
  }
}
```

### Parameter Descriptions

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `temperature` | float | 0.8 | Controls randomness (0.0 = deterministic, 2.0 = very random) |
| `top_p` | float | 0.9 | Nucleus sampling probability threshold |
| `top_k` | int | 40 | Limits tokens to top K most probable |
| `repeat_penalty` | float | 1.1 | Penalty for repeated tokens |
| `seed` | int | random | Random seed for reproducible outputs |
| `num_predict` | int | 128 | Maximum tokens to generate (-1 = unlimited) |
| `stop` | array | [] | Stop generation at these strings |
| `mirostat` | int | 0 | Mirostat sampling (0=disabled, 1=Mirostat, 2=Mirostat 2.0) |
| `mirostat_eta` | float | 0.1 | Mirostat learning rate |
| `mirostat_tau` | float | 5.0 | Mirostat target entropy |

### System Messages and Templates

```bash
POST /api/generate
Content-Type: application/json

{
  "model": "llama2",
  "prompt": "What is artificial intelligence?",
  "system": "You are a helpful AI assistant specializing in technology explanations. Provide clear, accurate, and educational responses.",
  "template": "System: {{ .System }}\n\nUser: {{ .Prompt }}\n\nAssistant:",
  "context": [1, 2, 3, ...],
  "options": {
    "temperature": 0.7
  }
}
```

## 🤖 Model-Specific Usage

### Code Generation Models

#### CodeLlama
```bash
POST /api/generate
Content-Type: application/json

{
  "model": "codellama:7b",
  "prompt": "Write a Python function to calculate fibonacci numbers",
  "options": {
    "temperature": 0.1,
    "stop": ["```"]
  }
}
```

#### Code Completion
```bash
POST /api/generate
Content-Type: application/json

{
  "model": "codellama:7b-code",
  "prompt": "def quicksort(arr):\n    if len(arr) <= 1:\n        return arr\n    pivot = arr[len(arr) // 2]\n    ",
  "options": {
    "temperature": 0.2,
    "num_predict": 200
  }
}
```

### Embedding Models

#### Text Embeddings
```bash
POST /api/embeddings
Content-Type: application/json

{
  "model": "nomic-embed-text",
  "prompt": "Document content for semantic search"
}
```

#### Batch Embeddings
```bash
# Process multiple texts (requires multiple API calls)
for text in texts:
    POST /api/embeddings
    {
      "model": "nomic-embed-text", 
      "prompt": text
    }
```

### Multimodal Models

#### Vision Models (LLaVA)
```bash
POST /api/generate
Content-Type: application/json

{
  "model": "llava",
  "prompt": "What do you see in this image?",
  "images": ["base64_encoded_image_data"]
}
```

## 🔄 Integration Examples

### Python Integration

```python
import requests
import json

class OllamaClient:
    def __init__(self, base_url="http://localhost:11434"):
        self.base_url = base_url
    
    def generate(self, model, prompt, stream=False, **options):
        """Generate text completion"""
        data = {
            "model": model,
            "prompt": prompt,
            "stream": stream,
            "options": options
        }
        
        response = requests.post(
            f"{self.base_url}/api/generate",
            json=data,
            stream=stream
        )
        
        if stream:
            return self._handle_stream(response)
        else:
            return response.json()
    
    def chat(self, model, messages, stream=False, **options):
        """Chat completion"""
        data = {
            "model": model,
            "messages": messages,
            "stream": stream,
            "options": options
        }
        
        response = requests.post(
            f"{self.base_url}/api/chat",
            json=data,
            stream=stream
        )
        
        return response.json() if not stream else self._handle_stream(response)
    
    def embeddings(self, model, prompt):
        """Generate embeddings"""
        data = {"model": model, "prompt": prompt}
        response = requests.post(f"{self.base_url}/api/embeddings", json=data)
        return response.json()
    
    def list_models(self):
        """List available models"""
        response = requests.get(f"{self.base_url}/api/tags")
        return response.json()
    
    def _handle_stream(self, response):
        """Handle streaming responses"""
        for line in response.iter_lines():
            if line:
                yield json.loads(line.decode('utf-8'))

# Usage examples
client = OllamaClient()

# Simple generation
result = client.generate("llama2", "What is machine learning?")
print(result['response'])

# Chat conversation
messages = [
    {"role": "user", "content": "Hello!"},
    {"role": "assistant", "content": "Hi there! How can I help you?"},
    {"role": "user", "content": "What's the weather like?"}
]
chat_result = client.chat("llama2", messages)
print(chat_result['message']['content'])

# Generate embeddings
embedding = client.embeddings("nomic-embed-text", "Sample text for embedding")
print(f"Embedding dimension: {len(embedding['embedding'])}")
```

### JavaScript Integration

```javascript
class OllamaClient {
    constructor(baseUrl = 'http://localhost:11434') {
        this.baseUrl = baseUrl;
    }

    async generate(model, prompt, options = {}) {
        const response = await fetch(`${this.baseUrl}/api/generate`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model,
                prompt,
                stream: false,
                ...options
            })
        });
        return await response.json();
    }

    async *generateStream(model, prompt, options = {}) {
        const response = await fetch(`${this.baseUrl}/api/generate`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model,
                prompt,
                stream: true,
                ...options
            })
        });

        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            
            const chunk = decoder.decode(value);
            const lines = chunk.split('\n').filter(line => line.trim());
            
            for (const line of lines) {
                try {
                    yield JSON.parse(line);
                } catch (e) {
                    console.error('Failed to parse JSON:', line);
                }
            }
        }
    }

    async chat(model, messages, options = {}) {
        const response = await fetch(`${this.baseUrl}/api/chat`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model,
                messages,
                stream: false,
                ...options
            })
        });
        return await response.json();
    }

    async embeddings(model, prompt) {
        const response = await fetch(`${this.baseUrl}/api/embeddings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ model, prompt })
        });
        return await response.json();
    }

    async listModels() {
        const response = await fetch(`${this.baseUrl}/api/tags`);
        return await response.json();
    }
}

// Usage examples
const client = new OllamaClient();

// Simple generation
async function simpleGeneration() {
    const result = await client.generate('llama2', 'Explain photosynthesis');
    console.log(result.response);
}

// Streaming generation
async function streamingGeneration() {
    console.log('Streaming response:');
    for await (const chunk of client.generateStream('llama2', 'Tell me a story')) {
        if (!chunk.done) {
            process.stdout.write(chunk.response);
        }
    }
    console.log('\nDone!');
}

// Chat interface
async function chatExample() {
    const messages = [
        { role: 'user', content: 'What is quantum computing?' }
    ];
    
    const response = await client.chat('llama2', messages);
    console.log('Assistant:', response.message.content);
}
```

### cURL Examples

#### Basic Text Generation
```bash
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "prompt": "Explain the theory of relativity in simple terms",
    "stream": false,
    "options": {
      "temperature": 0.7,
      "num_predict": 300
    }
  }'
```

#### Code Generation
```bash
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "codellama",
    "prompt": "Write a Python function to reverse a string",
    "stream": false,
    "options": {
      "temperature": 0.1
    }
  }'
```

#### Embeddings Generation
```bash
curl -X POST http://localhost:11434/api/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-embed-text",
    "prompt": "This is a sample text for embedding generation"
  }'
```

## 📊 Performance Optimization

### Model Selection

| Model | Size | Use Case | Performance | Memory |
|-------|------|----------|-------------|---------|
| `llama2:7b` | ~4GB | General conversation | Good | 8GB+ |
| `llama2:13b` | ~7GB | Better reasoning | Better | 16GB+ |
| `codellama:7b` | ~4GB | Code generation | Good | 8GB+ |
| `mistral:7b` | ~4GB | Fast responses | Fast | 8GB+ |
| `nomic-embed-text` | ~270MB | Embeddings | Very fast | 2GB+ |

### GPU Acceleration

Ollama automatically uses GPU when available:

```bash
# Check GPU usage
nvidia-smi

# Monitor GPU utilization during inference
watch -n 1 nvidia-smi
```

### Memory Management

```bash
# Set memory limit for model loading
OLLAMA_MAX_LOADED_MODELS=1 ollama serve

# Set GPU memory fraction
OLLAMA_GPU_MEMORY_FRACTION=0.8 ollama serve
```

### Batch Processing

```python
import asyncio
import aiohttp

async def process_batch(prompts, model="llama2"):
    """Process multiple prompts concurrently"""
    async with aiohttp.ClientSession() as session:
        tasks = []
        for prompt in prompts:
            task = generate_async(session, model, prompt)
            tasks.append(task)
        
        results = await asyncio.gather(*tasks)
        return results

async def generate_async(session, model, prompt):
    """Async generation function"""
    data = {
        "model": model,
        "prompt": prompt,
        "stream": False
    }
    
    async with session.post("http://localhost:11434/api/generate", json=data) as response:
        return await response.json()

# Usage
prompts = [
    "What is AI?",
    "Explain machine learning", 
    "Define neural networks"
]

results = asyncio.run(process_batch(prompts))
```

## 🔍 Monitoring and Health Checks

### Health Check Endpoint

```bash
# Basic connectivity test
curl -f http://localhost:11434/api/tags || echo "Ollama is not responding"

# Test with simple generation
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "prompt": "Hello",
    "stream": false,
    "options": {"num_predict": 1}
  }'
```

### Performance Metrics

```python
import time
import requests

def benchmark_model(model, prompt, iterations=5):
    """Benchmark model performance"""
    times = []
    
    for i in range(iterations):
        start_time = time.time()
        
        response = requests.post("http://localhost:11434/api/generate", json={
            "model": model,
            "prompt": prompt,
            "stream": False
        })
        
        end_time = time.time()
        times.append(end_time - start_time)
        
        if response.status_code == 200:
            result = response.json()
            print(f"Iteration {i+1}: {end_time - start_time:.2f}s, "
                  f"Tokens: {result.get('eval_count', 0)}")
    
    avg_time = sum(times) / len(times)
    print(f"Average response time: {avg_time:.2f}s")
    return avg_time

# Benchmark different models
benchmark_model("llama2", "What is artificial intelligence?")
```

## 🚨 Error Handling

### Common Errors

| Error Code | Description | Solution |
|------------|-------------|----------|
| 404 | Model not found | Pull the model: `ollama pull model_name` |
| 500 | Out of memory | Use smaller model or increase system memory |
| 503 | Service unavailable | Restart Ollama service |
| Connection refused | Ollama not running | Start Ollama: `ollama serve` |

### Error Response Format

```json
{
  "error": "model 'nonexistent' not found, try pulling it first"
}
```

### Retry Logic

```python
import time
import requests
from typing import Optional

def generate_with_retry(
    model: str, 
    prompt: str, 
    max_retries: int = 3, 
    backoff_factor: float = 2.0
) -> Optional[dict]:
    """Generate with exponential backoff retry"""
    
    for attempt in range(max_retries):
        try:
            response = requests.post(
                "http://localhost:11434/api/generate",
                json={"model": model, "prompt": prompt, "stream": False},
                timeout=30
            )
            
            if response.status_code == 200:
                return response.json()
            elif response.status_code == 404:
                print(f"Model {model} not found. Trying to pull...")
                pull_model(model)
                continue
            else:
                print(f"HTTP {response.status_code}: {response.text}")
                
        except requests.exceptions.RequestException as e:
            print(f"Attempt {attempt + 1} failed: {e}")
            
        if attempt < max_retries - 1:
            sleep_time = backoff_factor ** attempt
            print(f"Retrying in {sleep_time} seconds...")
            time.sleep(sleep_time)
    
    return None

def pull_model(model: str) -> bool:
    """Pull model if not available"""
    try:
        response = requests.post(
            "http://localhost:11434/api/pull",
            json={"name": model}
        )
        return response.status_code == 200
    except:
        return False
```

## 📚 Best Practices

### Model Management
- Keep frequently used models pulled locally
- Monitor disk space (models can be large)
- Use appropriate model sizes for your hardware
- Regular cleanup of unused models

### Performance Optimization
- Use GPU acceleration when available
- Adjust temperature and other parameters for your use case
- Implement proper error handling and retries
- Monitor memory usage and response times

### Integration Patterns
- Use streaming for long responses
- Implement timeouts for API calls
- Cache responses when appropriate
- Use batch processing for multiple requests

### Security Considerations
- Ollama runs without authentication by default
- Use reverse proxy for external access
- Implement rate limiting for production use
- Monitor resource usage and costs

---

[**← Back to API Overview**](README.md) | [**→ Qdrant API Reference**](qdrant-collections.md)

---

**API Version:** Ollama 0.1.x  
**Last Updated:** January 2025  
**Service Compatibility:** All AI Starter Kit deployments