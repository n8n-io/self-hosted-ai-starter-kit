# Crawl4AI Integration Guide

This guide explains how to use Crawl4AI with LLM-based extraction strategies in the GPU-optimized deployment stack.

## 🌟 Overview

Crawl4AI is an advanced web scraping framework that combines traditional scraping with AI-powered data extraction. This integration provides:

- **LLM-based extraction** using OpenAI, Anthropic, local Ollama models, and more
- **Schema-driven extraction** with Pydantic model support
- **Chunking and parallel processing** for large content
- **Multiple extraction strategies** (CSS, XPath, Regex, LLM, Clustering)
- **RESTful API** with streaming support
- **Model Context Protocol (MCP)** integration

## 🚀 Quick Start

### 1. Start the Services

```bash
# Start the entire stack including Crawl4AI
docker-compose -f docker-compose.gpu-optimized.yml up -d

# Or start just Crawl4AI with dependencies
docker-compose up postgres crawl4ai
```

### 2. Verify Health

```bash
# Check Crawl4AI health
curl http://localhost:11235/health

# Check available endpoints
curl http://localhost:11235/schema
```

### 3. Access Playground

Open your browser to http://localhost:11235/playground for an interactive interface to test configurations.

## 🔧 Configuration

### Environment Variables

Add these to your `.env` file:

```bash
# LLM API Keys for external providers
OPENAI_API_KEY=sk-your-openai-key
ANTHROPIC_API_KEY=sk-ant-your-anthropic-key
DEEPSEEK_API_KEY=sk-your-deepseek-key
GROQ_API_KEY=gsk_your-groq-key

# Optional: Additional providers
TOGETHER_API_KEY=your-together-key
MISTRAL_API_KEY=your-mistral-key
GEMINI_API_TOKEN=your-gemini-token
```

### Ollama Integration

Local models are automatically available through the Ollama service:

- **DeepSeek-R1:8B** - Reasoning and problem-solving
- **Qwen2.5-VL:7B** - Vision-language understanding  
- **Arctic-Embed** - Embedding generation

Access via: `http://ollama:11434` (internal) or `http://localhost:11434` (external)

## 📖 Usage Examples

### Python SDK

```python
import asyncio
import json
from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, LLMConfig
from crawl4ai.extraction_strategy import LLMExtractionStrategy

async def extract_news_article():
    # Configure extraction strategy
    llm_strategy = LLMExtractionStrategy(
        llm_config=LLMConfig(
            provider="openai/gpt-4o-mini",
            api_token="your-api-key"
        ),
        schema={
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "summary": {"type": "string"},
                "author": {"type": "string"},
                "published_date": {"type": "string"}
            }
        },
        extraction_type="schema",
        instruction="Extract article metadata and create a summary."
    )
    
    # Configure crawler
    crawl_config = CrawlerRunConfig(
        extraction_strategy=llm_strategy,
        cache_mode="bypass"
    )
    
    # Execute crawling
    async with AsyncWebCrawler() as crawler:
        result = await crawler.arun(
            url="https://example.com/news/article",
            config=crawl_config
        )
        
        if result.success:
            data = json.loads(result.extracted_content)
            print(json.dumps(data, indent=2))

asyncio.run(extract_news_article())
```

### REST API

```python
import requests

# Configuration for REST API call
payload = {
    "urls": ["https://example.com/products"],
    "crawler_config": {
        "type": "CrawlerRunConfig",
        "params": {
            "extraction_strategy": {
                "type": "LLMExtractionStrategy",
                "params": {
                    "llm_config": {
                        "type": "LlmConfig",
                        "params": {
                            "provider": "ollama/deepseek-r1:8b-optimized",
                            "base_url": "http://ollama:11434"
                        }
                    },
                    "schema": {
                        "type": "dict",
                        "value": {
                            "type": "object",
                            "properties": {
                                "products": {
                                    "type": "array",
                                    "items": {
                                        "type": "object",
                                        "properties": {
                                            "name": {"type": "string"},
                                            "price": {"type": "string"},
                                            "description": {"type": "string"}
                                        }
                                    }
                                }
                            }
                        }
                    },
                    "extraction_type": "schema",
                    "instruction": "Extract all products with names, prices, and descriptions."
                }
            }
        }
    }
}

# Send request
response = requests.post(
    "http://localhost:11235/crawl",
    json=payload,
    headers={"Content-Type": "application/json"}
)

if response.ok:
    result = response.json()
    print(json.dumps(result, indent=2))
```

### Using Local Ollama Models

```python
# Use local DeepSeek-R1 for reasoning tasks
llm_config = LLMConfig(
    provider="ollama/deepseek-r1:8b-optimized",
    base_url="http://localhost:11434"
)

# Use local Qwen2.5-VL for vision-language tasks
llm_config = LLMConfig(
    provider="ollama/qwen2.5:7b-vl-optimized", 
    base_url="http://localhost:11434"
)

# Use embedding model for similarity search
llm_config = LLMConfig(
    provider="ollama/arctic-embed:optimized",
    base_url="http://localhost:11434"
)
```

## 🎯 Extraction Strategies

### 1. LLM-based Extraction

Most powerful but potentially costly. Best for:
- Complex, unstructured content
- Semantic understanding required
- Content summarization
- Knowledge graph extraction

```python
strategy = LLMExtractionStrategy(
    llm_config=LLMConfig(provider="openai/gpt-4o-mini"),
    schema=your_pydantic_schema,
    instruction="Extract key information...",
    chunk_token_threshold=4000,
    overlap_rate=0.1
)
```

### 2. CSS/XPath Extraction

Fast and reliable for structured content:

```python
from crawl4ai.extraction_strategy import JsonCssExtractionStrategy

strategy = JsonCssExtractionStrategy({
    "name": "Product List",
    "baseSelector": ".product-item",
    "fields": [
        {"name": "title", "selector": "h2", "type": "text"},
        {"name": "price", "selector": ".price", "type": "text"}
    ]
})
```

### 3. Regex Extraction

For specific patterns and common data types:

```python
from crawl4ai.extraction_strategy import RegexExtractionStrategy

# Built-in patterns
strategy = RegexExtractionStrategy(
    pattern=RegexExtractionStrategy.Email | RegexExtractionStrategy.PhoneUS
)

# Custom patterns
strategy = RegexExtractionStrategy(
    custom={"price": r"\$\d+\.\d{2}"}
)
```

## 🔗 API Endpoints

### Core Endpoints

- `POST /crawl` - Single or batch crawling
- `POST /crawl/stream` - Streaming results
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics
- `GET /schema` - API schema

### Specialized Endpoints

- `POST /html` - Extract preprocessed HTML
- `POST /screenshot` - Capture screenshots
- `POST /pdf` - Generate PDFs
- `POST /execute_js` - Run JavaScript

### MCP Integration

- `GET /mcp/sse` - Server-Sent Events endpoint
- `WS /mcp/ws` - WebSocket endpoint

Connect with Claude Code:
```bash
claude mcp add --transport sse c4ai-sse http://localhost:11235/mcp/sse
```

## 📊 Performance Optimization

### GPU Instance Configuration

The GPU-optimized deployment is configured for g4dn.xlarge instances:

```yaml
# Resource allocation
deploy:
  resources:
    limits:
      memory: 4G      # 25% of 16GB RAM
      cpus: '2.0'     # 50% of 4 vCPUs
    reservations:
      memory: 2G
      cpus: '1.0'
```

### Best Practices

1. **Use Local Models**: Reduce latency and costs with Ollama
2. **Enable Chunking**: For large documents (>4000 tokens)
3. **Cache Results**: Set appropriate cache modes
4. **Optimize Schemas**: Well-defined schemas improve accuracy
5. **Monitor Resources**: Use `/metrics` endpoint

### Chunking Configuration

```python
strategy = LLMExtractionStrategy(
    chunk_token_threshold=6000,  # Larger chunks for local models
    overlap_rate=0.15,           # 15% overlap for context continuity
    apply_chunking=True
)
```

## 🔧 Advanced Features

### Custom Extraction Workflows

```python
# Multi-stage extraction
async def advanced_extraction(url):
    # Stage 1: Structure extraction with CSS
    css_result = await crawler.arun(url, css_strategy)
    
    # Stage 2: Content analysis with LLM
    llm_result = await crawler.arun(url, llm_strategy)
    
    # Stage 3: Combine and validate
    return combine_results(css_result, llm_result)
```

### Integration with n8n Workflows

The Crawl4AI service integrates seamlessly with n8n:

1. Use HTTP Request nodes to call Crawl4AI endpoints
2. Process extracted data with n8n's data transformation nodes
3. Store results in PostgreSQL or vector database (Qdrant)
4. Set up automated workflows with triggers

### Error Handling

```python
try:
    result = await crawler.arun(url, config)
    if result.success:
        data = json.loads(result.extracted_content)
        # Process data
    else:
        print(f"Extraction failed: {result.error_message}")
except Exception as e:
    print(f"Request failed: {e}")
```

## 📈 Monitoring

### Health Checks

```bash
# Service health
curl http://localhost:11235/health

# Detailed metrics
curl http://localhost:11235/metrics
```

### Logs

```bash
# View Crawl4AI logs
docker-compose logs -f crawl4ai

# Monitor resource usage
docker stats crawl4ai-gpu
```

### Performance Metrics

The service exposes Prometheus metrics at `/metrics`:
- Request latency
- Success/failure rates
- Resource utilization
- Queue depths

## 🔒 Security

### API Security

```python
# Enable JWT authentication (if configured)
headers = {"Authorization": f"Bearer {token}"}
response = requests.post(url, json=payload, headers=headers)
```

### Rate Limiting

Default configuration allows 2000 requests/minute for GPU instances.

### Data Privacy

- Use local Ollama models for sensitive content
- Configure trusted hosts appropriately
- Validate and sanitize extracted data

## 🧪 Testing

Run the included example script:

```bash
# Install dependencies
pip install requests

# Run examples
python scripts/crawl4ai-llm-examples.py

# Health check only
python scripts/crawl4ai-llm-examples.py --health
```

## 🐛 Troubleshooting

### Common Issues

1. **Service not responding**
   ```bash
   docker-compose ps crawl4ai
   docker-compose logs crawl4ai
   ```

2. **High memory usage**
   - Reduce `chunk_token_threshold`
   - Enable garbage collection
   - Monitor with `docker stats`

3. **Slow extraction**
   - Use local Ollama models
   - Enable parallel processing
   - Optimize schemas

4. **Invalid JSON responses**
   - Lower temperature (0.0-0.1)
   - Provide clearer instructions
   - Add validation examples

### Support

- 📖 [Crawl4AI Documentation](https://docs.crawl4ai.com/)
- 🐛 [GitHub Issues](https://github.com/unclecode/crawl4ai/issues)
- 💬 [Community Discord](https://discord.gg/crawl4ai)

## 🔄 Updates

The Crawl4AI service uses the latest stable image. To update:

```bash
# Pull latest image
docker-compose pull crawl4ai

# Restart service
docker-compose up -d crawl4ai
```

## 📋 Configuration Reference

### Complete Environment Variables

```bash
# LLM Provider Keys
OPENAI_API_KEY=sk-your-key
ANTHROPIC_API_KEY=sk-ant-your-key
DEEPSEEK_API_KEY=sk-your-key
GROQ_API_KEY=gsk-your-key
TOGETHER_API_KEY=your-key
MISTRAL_API_KEY=your-key
GEMINI_API_TOKEN=your-token

# Service Configuration
CRAWL4AI_HOST=0.0.0.0
CRAWL4AI_PORT=11235
CRAWL4AI_TIMEOUT_KEEP_ALIVE=600
CRAWL4AI_MEMORY_THRESHOLD_PERCENT=90.0
CRAWL4AI_RATE_LIMITING_ENABLED=true
CRAWL4AI_DEFAULT_LIMIT=2000/minute

# Ollama Integration
OLLAMA_HOST=ollama:11434
OLLAMA_API_BASE=http://ollama:11434

# Security
CRAWL4AI_SECURITY_ENABLED=false
CRAWL4AI_JWT_ENABLED=false
CRAWL4AI_TRUSTED_HOSTS=["*"]

# Monitoring
CRAWL4AI_PROMETHEUS_ENABLED=true
CRAWL4AI_LOG_LEVEL=INFO
```

---

**Happy Crawling! 🕷️** 