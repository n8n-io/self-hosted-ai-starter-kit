# Crawl4AI Service API Reference

> Complete API documentation for Crawl4AI web crawling and extraction service

Crawl4AI is an intelligent web crawling and content extraction service designed for AI applications. This document covers all available endpoints and integration patterns for the AI Starter Kit deployment.

## 🌟 Service Overview

| Property | Details |
|----------|---------|
| **Service** | Crawl4AI Web Crawler |
| **Port** | 11235 |
| **Protocol** | HTTP |
| **Authentication** | None (local access) |
| **Documentation** | [Crawl4AI GitHub](https://github.com/unclecode/crawl4ai) |

## 📚 Core API Endpoints

### Health and Status

#### Health Check
```bash
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "version": "0.2.0",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

#### Service Status
```bash
GET /status
```

**Response:**
```json
{
  "service": "crawl4ai",
  "status": "running",
  "active_sessions": 3,
  "total_crawls": 1247,
  "uptime": "2d 14h 32m"
}
```

### Web Crawling

#### Basic Crawl
```bash
POST /crawl
Content-Type: application/json

{
  "urls": ["https://example.com"],
  "extract_text": true,
  "extract_links": true,
  "extract_images": false
}
```

**Response:**
```json
{
  "success": true,
  "results": [
    {
      "url": "https://example.com",
      "status_code": 200,
      "title": "Example Domain",
      "text": "This domain is for use in illustrative examples...",
      "links": [
        {
          "url": "https://www.iana.org/domains/example",
          "text": "More information...",
          "type": "external"
        }
      ],
      "metadata": {
        "crawl_time": "2024-01-01T12:00:00Z",
        "content_length": 1256,
        "load_time": 1.234
      }
    }
  ]
}
```

#### Advanced Crawl Configuration
```bash
POST /crawl
Content-Type: application/json

{
  "urls": ["https://news.example.com"],
  "extract_text": true,
  "extract_links": true,
  "extract_images": true,
  "extract_metadata": true,
  "follow_links": false,
  "max_depth": 2,
  "delay": 1,
  "user_agent": "Crawl4AI Bot",
  "headers": {
    "Accept-Language": "en-US,en;q=0.9"
  },
  "selectors": {
    "title": "h1.article-title",
    "content": "div.article-content",
    "author": ".author-name",
    "date": ".publish-date"
  },
  "exclude_selectors": [".advertisement", ".sidebar"],
  "wait_for": "div.article-content",
  "screenshot": true,
  "format": "markdown"
}
```

**Advanced Response:**
```json
{
  "success": true,
  "results": [
    {
      "url": "https://news.example.com",
      "status_code": 200,
      "title": "Breaking News Article",
      "text": "# Breaking News Article\n\nThis is the main content...",
      "markdown": "# Breaking News Article\n\nThis is the main content...",
      "html": "<html>...</html>",
      "links": [...],
      "images": [
        {
          "src": "https://news.example.com/image.jpg",
          "alt": "News image",
          "width": 800,
          "height": 600
        }
      ],
      "extracted_data": {
        "title": "Breaking News Article",
        "content": "Main article content...",
        "author": "John Doe",
        "date": "2024-01-01"
      },
      "metadata": {
        "crawl_time": "2024-01-01T12:00:00Z",
        "content_length": 5678,
        "load_time": 2.456,
        "language": "en",
        "encoding": "utf-8"
      },
      "screenshot_base64": "iVBORw0KGgoAAAANSUhEUgAAA..."
    }
  ]
}
```

### Content Extraction

#### Extract Structured Data
```bash
POST /extract
Content-Type: application/json

{
  "url": "https://ecommerce.example.com/product/123",
  "schema": {
    "product_name": "h1.product-title",
    "price": ".price-current",
    "description": ".product-description",
    "images": "img.product-image@src",
    "reviews": {
      "selector": ".review",
      "fields": {
        "rating": ".rating@data-rating",
        "text": ".review-text",
        "author": ".review-author"
      }
    }
  }
}
```

**Response:**
```json
{
  "success": true,
  "url": "https://ecommerce.example.com/product/123",
  "extracted_data": {
    "product_name": "Amazing Product",
    "price": "$29.99",
    "description": "This is an amazing product that...",
    "images": [
      "https://ecommerce.example.com/images/product1.jpg",
      "https://ecommerce.example.com/images/product2.jpg"
    ],
    "reviews": [
      {
        "rating": "5",
        "text": "Great product!",
        "author": "Happy Customer"
      },
      {
        "rating": "4",
        "text": "Good value for money",
        "author": "Satisfied User"
      }
    ]
  }
}
```

#### Smart Content Extraction
```bash
POST /extract/smart
Content-Type: application/json

{
  "url": "https://blog.example.com/article",
  "content_type": "article",
  "extract_main_content": true,
  "clean_html": true,
  "extract_keywords": true,
  "extract_summary": true
}
```

**Response:**
```json
{
  "success": true,
  "url": "https://blog.example.com/article",
  "main_content": "The main article content without ads and navigation...",
  "title": "How to Build AI Applications",
  "author": "AI Expert",
  "publish_date": "2024-01-01",
  "keywords": ["AI", "machine learning", "applications", "development"],
  "summary": "This article explains the fundamentals of building AI applications...",
  "reading_time": "8 minutes",
  "word_count": 1500,
  "language": "en"
}
```

### Batch Operations

#### Batch Crawl
```bash
POST /crawl/batch
Content-Type: application/json

{
  "urls": [
    "https://example1.com",
    "https://example2.com", 
    "https://example3.com"
  ],
  "config": {
    "extract_text": true,
    "extract_links": false,
    "delay": 2,
    "timeout": 30
  },
  "concurrent": 3
}
```

#### Monitor Batch Job
```bash
GET /jobs/{job_id}
```

**Response:**
```json
{
  "job_id": "batch_123",
  "status": "running",
  "total_urls": 100,
  "completed": 45,
  "failed": 2,
  "remaining": 53,
  "start_time": "2024-01-01T12:00:00Z",
  "estimated_completion": "2024-01-01T12:15:00Z"
}
```

### Sitemap Crawling

#### Crawl from Sitemap
```bash
POST /crawl/sitemap
Content-Type: application/json

{
  "sitemap_url": "https://example.com/sitemap.xml",
  "max_urls": 100,
  "filter_patterns": ["*/blog/*", "*/news/*"],
  "exclude_patterns": ["*/admin/*", "*/private/*"],
  "config": {
    "extract_text": true,
    "extract_metadata": true,
    "delay": 1
  }
}
```

### RSS/Atom Feed Processing

#### Process RSS Feed
```bash
POST /feed
Content-Type: application/json

{
  "feed_url": "https://example.com/rss.xml",
  "max_items": 50,
  "crawl_full_content": true,
  "since": "2024-01-01T00:00:00Z"
}
```

**Response:**
```json
{
  "success": true,
  "feed_info": {
    "title": "Example News Feed",
    "description": "Latest news from Example.com",
    "last_updated": "2024-01-01T12:00:00Z"
  },
  "items": [
    {
      "title": "Breaking News",
      "link": "https://example.com/news/breaking",
      "description": "Short description...",
      "pub_date": "2024-01-01T11:00:00Z",
      "full_content": "Complete article content...",
      "author": "News Reporter",
      "categories": ["news", "breaking"]
    }
  ]
}
```

## 🔧 Advanced Features

### JavaScript Rendering

#### Render Dynamic Content
```bash
POST /crawl/render
Content-Type: application/json

{
  "url": "https://spa.example.com",
  "wait_for_selector": "div.loaded-content",
  "wait_timeout": 10000,
  "execute_script": "window.scrollTo(0, document.body.scrollHeight);",
  "screenshot": true,
  "extract_text": true
}
```

### Form Handling

#### Submit Forms
```bash
POST /crawl/form
Content-Type: application/json

{
  "url": "https://example.com/search",
  "form_data": {
    "query": "artificial intelligence",
    "category": "technology"
  },
  "form_selector": "#search-form",
  "submit_button": "button[type=submit]",
  "wait_after_submit": 3000
}
```

### Session Management

#### Create Persistent Session
```bash
POST /session
Content-Type: application/json

{
  "cookies": [
    {
      "name": "session_id",
      "value": "abc123",
      "domain": ".example.com"
    }
  ],
  "headers": {
    "Authorization": "Bearer token123"
  },
  "proxy": "http://proxy.example.com:8080"
}
```

**Response:**
```json
{
  "session_id": "session_456",
  "expires_at": "2024-01-01T18:00:00Z"
}
```

#### Use Session for Crawling
```bash
POST /crawl
Content-Type: application/json

{
  "urls": ["https://protected.example.com"],
  "session_id": "session_456",
  "extract_text": true
}
```

## 🔄 Integration Examples

### Python Integration

```python
import requests
import json
from typing import List, Dict, Any, Optional

class Crawl4AIClient:
    def __init__(self, base_url: str = "http://localhost:11235"):
        self.base_url = base_url
        self.session = requests.Session()
    
    def health_check(self) -> Dict[str, Any]:
        """Check service health"""
        response = self.session.get(f"{self.base_url}/health")
        return response.json()
    
    def crawl_url(self, url: str, config: Optional[Dict] = None) -> Dict[str, Any]:
        """Crawl a single URL"""
        data = {"urls": [url]}
        if config:
            data.update(config)
        
        response = self.session.post(f"{self.base_url}/crawl", json=data)
        return response.json()
    
    def crawl_multiple(self, urls: List[str], config: Optional[Dict] = None) -> Dict[str, Any]:
        """Crawl multiple URLs"""
        data = {"urls": urls}
        if config:
            data.update(config)
        
        response = self.session.post(f"{self.base_url}/crawl", json=data)
        return response.json()
    
    def extract_structured_data(self, url: str, schema: Dict[str, Any]) -> Dict[str, Any]:
        """Extract structured data using CSS selectors"""
        data = {
            "url": url,
            "schema": schema
        }
        
        response = self.session.post(f"{self.base_url}/extract", json=data)
        return response.json()
    
    def smart_extract(self, url: str, content_type: str = "article") -> Dict[str, Any]:
        """Smart content extraction"""
        data = {
            "url": url,
            "content_type": content_type,
            "extract_main_content": True,
            "clean_html": True,
            "extract_keywords": True,
            "extract_summary": True
        }
        
        response = self.session.post(f"{self.base_url}/extract/smart", json=data)
        return response.json()
    
    def crawl_sitemap(self, sitemap_url: str, max_urls: int = 100) -> Dict[str, Any]:
        """Crawl URLs from sitemap"""
        data = {
            "sitemap_url": sitemap_url,
            "max_urls": max_urls,
            "config": {
                "extract_text": True,
                "extract_metadata": True
            }
        }
        
        response = self.session.post(f"{self.base_url}/crawl/sitemap", json=data)
        return response.json()
    
    def process_rss_feed(self, feed_url: str, max_items: int = 50) -> Dict[str, Any]:
        """Process RSS/Atom feed"""
        data = {
            "feed_url": feed_url,
            "max_items": max_items,
            "crawl_full_content": True
        }
        
        response = self.session.post(f"{self.base_url}/feed", json=data)
        return response.json()

# Usage examples
client = Crawl4AIClient()

# Basic crawl
result = client.crawl_url("https://example.com", {
    "extract_text": True,
    "extract_links": True,
    "format": "markdown"
})

print("Crawled content:", result['results'][0]['text'])

# Structured data extraction
schema = {
    "title": "h1",
    "price": ".price",
    "description": ".description",
    "images": "img@src"
}

product_data = client.extract_structured_data("https://shop.example.com/product", schema)
print("Product data:", product_data['extracted_data'])

# Smart article extraction
article = client.smart_extract("https://blog.example.com/article", "article")
print("Article summary:", article['summary'])
print("Keywords:", article['keywords'])
```

### JavaScript Integration

```javascript
class Crawl4AIClient {
    constructor(baseUrl = 'http://localhost:11235') {
        this.baseUrl = baseUrl;
    }

    async healthCheck() {
        const response = await fetch(`${this.baseUrl}/health`);
        return await response.json();
    }

    async crawlUrl(url, config = {}) {
        const data = { urls: [url], ...config };
        const response = await fetch(`${this.baseUrl}/crawl`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await response.json();
    }

    async extractData(url, schema) {
        const data = { url, schema };
        const response = await fetch(`${this.baseUrl}/extract`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await response.json();
    }

    async smartExtract(url, contentType = 'article') {
        const data = {
            url,
            content_type: contentType,
            extract_main_content: true,
            clean_html: true,
            extract_keywords: true,
            extract_summary: true
        };
        const response = await fetch(`${this.baseUrl}/extract/smart`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await response.json();
    }

    async batchCrawl(urls, config = {}) {
        const data = { urls, config, concurrent: 5 };
        const response = await fetch(`${this.baseUrl}/crawl/batch`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await response.json();
    }

    async processRSSFeed(feedUrl, maxItems = 50) {
        const data = {
            feed_url: feedUrl,
            max_items: maxItems,
            crawl_full_content: true
        };
        const response = await fetch(`${this.baseUrl}/feed`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await response.json();
    }
}

// Usage examples
const client = new Crawl4AIClient();

// Crawl and extract news articles
async function crawlNews() {
    const result = await client.crawlUrl('https://news.example.com', {
        extract_text: true,
        extract_links: true,
        selectors: {
            headline: 'h1.headline',
            summary: '.article-summary',
            content: '.article-body'
        },
        format: 'markdown'
    });
    
    console.log('News content:', result.results[0].extracted_data);
}

// Extract product information
async function extractProduct() {
    const schema = {
        name: 'h1.product-title',
        price: '.price-current',
        description: '.product-description',
        images: 'img.product-image@src',
        specs: {
            selector: '.spec-item',
            fields: {
                name: '.spec-name',
                value: '.spec-value'
            }
        }
    };
    
    const product = await client.extractData('https://shop.example.com/item', schema);
    console.log('Product info:', product.extracted_data);
}

// Process RSS feed for latest articles
async function processNewsFeed() {
    const feed = await client.processRSSFeed('https://news.example.com/rss', 20);
    
    for (const item of feed.items) {
        console.log(`Title: ${item.title}`);
        console.log(`Summary: ${item.description}`);
        console.log(`Full content: ${item.full_content}`);
        console.log('---');
    }
}
```

### AI Content Processing Pipeline

```python
import asyncio
from typing import List
import requests

class AIContentPipeline:
    def __init__(self, crawl4ai_url="http://localhost:11235", 
                 qdrant_url="http://localhost:6333",
                 ollama_url="http://localhost:11434"):
        self.crawl4ai = Crawl4AIClient(crawl4ai_url)
        self.qdrant_url = qdrant_url
        self.ollama_url = ollama_url
    
    def crawl_and_process_urls(self, urls: List[str], collection_name: str):
        """Complete pipeline: crawl -> extract -> embed -> store"""
        results = []
        
        for url in urls:
            try:
                # 1. Crawl content
                crawl_result = self.crawl4ai.smart_extract(url, "article")
                
                if not crawl_result.get('success'):
                    continue
                
                # 2. Generate embeddings
                text_content = crawl_result.get('main_content', '')
                embedding = self.generate_embedding(text_content)
                
                # 3. Store in vector database
                self.store_in_qdrant(
                    collection_name=collection_name,
                    doc_id=url,
                    text=text_content,
                    embedding=embedding,
                    metadata={
                        'url': url,
                        'title': crawl_result.get('title', ''),
                        'author': crawl_result.get('author', ''),
                        'keywords': crawl_result.get('keywords', []),
                        'summary': crawl_result.get('summary', ''),
                        'crawl_date': crawl_result.get('timestamp')
                    }
                )
                
                results.append({
                    'url': url,
                    'status': 'success',
                    'title': crawl_result.get('title'),
                    'word_count': crawl_result.get('word_count')
                })
                
            except Exception as e:
                results.append({
                    'url': url,
                    'status': 'failed',
                    'error': str(e)
                })
        
        return results
    
    def generate_embedding(self, text: str) -> List[float]:
        """Generate text embedding using Ollama"""
        response = requests.post(f"{self.ollama_url}/api/embeddings", json={
            "model": "nomic-embed-text",
            "prompt": text
        })
        
        if response.status_code == 200:
            return response.json()['embedding']
        else:
            raise Exception(f"Failed to generate embedding: {response.text}")
    
    def store_in_qdrant(self, collection_name: str, doc_id: str, text: str, 
                       embedding: List[float], metadata: dict):
        """Store document in Qdrant vector database"""
        point_data = {
            "points": [
                {
                    "id": doc_id,
                    "vector": embedding,
                    "payload": {
                        "text": text,
                        **metadata
                    }
                }
            ]
        }
        
        response = requests.put(
            f"{self.qdrant_url}/collections/{collection_name}/points",
            json=point_data
        )
        
        if response.status_code not in [200, 201]:
            raise Exception(f"Failed to store in Qdrant: {response.text}")
    
    def search_similar_content(self, query: str, collection_name: str, limit: int = 5):
        """Search for similar content in the vector database"""
        # Generate query embedding
        query_embedding = self.generate_embedding(query)
        
        # Search in Qdrant
        search_data = {
            "vector": query_embedding,
            "limit": limit,
            "with_payload": True,
            "score_threshold": 0.7
        }
        
        response = requests.post(
            f"{self.qdrant_url}/collections/{collection_name}/points/search",
            json=search_data
        )
        
        if response.status_code == 200:
            return response.json()['result']
        else:
            raise Exception(f"Search failed: {response.text}")

# Usage example
pipeline = AIContentPipeline()

# Crawl tech news and store in vector database
news_urls = [
    "https://techcrunch.com/2024/01/01/ai-breakthrough",
    "https://arstechnica.com/ai/2024/01/machine-learning-advance",
    "https://theverge.com/2024/1/1/artificial-intelligence-news"
]

# Process URLs and store content
results = pipeline.crawl_and_process_urls(news_urls, "tech_news")
print("Processing results:", results)

# Search for similar content
similar_articles = pipeline.search_similar_content(
    "artificial intelligence breakthroughs", 
    "tech_news"
)
print("Similar articles:", similar_articles)
```

## 📊 Performance and Optimization

### Rate Limiting and Throttling

```python
# Configure crawling delays and concurrency
config = {
    "delay": 2,                    # Delay between requests (seconds)
    "timeout": 30,                 # Request timeout (seconds)
    "concurrent": 3,               # Maximum concurrent requests
    "retry_attempts": 3,           # Number of retry attempts
    "retry_delay": 5,              # Delay between retries
    "respect_robots_txt": True     # Respect robots.txt
}
```

### Memory Management

```bash
# Monitor service memory usage
GET /stats

# Response includes memory metrics
{
  "memory_usage": "256MB",
  "active_sessions": 5,
  "cache_size": "128MB",
  "queue_length": 12
}
```

### Caching

```python
# Enable response caching
config = {
    "cache_enabled": True,
    "cache_ttl": 3600,             # Cache TTL in seconds
    "cache_key_headers": ["user-agent", "accept-language"]
}
```

## 🔍 Monitoring and Debugging

### Logging Configuration

```python
# Configure detailed logging
config = {
    "log_level": "DEBUG",
    "log_requests": True,
    "log_responses": False,        # Don't log full responses (large)
    "log_errors": True
}
```

### Health Monitoring

```python
def monitor_crawl4ai():
    """Monitor Crawl4AI service health"""
    try:
        response = requests.get("http://localhost:11235/health", timeout=5)
        
        if response.status_code == 200:
            health_data = response.json()
            return {
                "status": "healthy",
                "version": health_data.get("version"),
                "uptime": health_data.get("uptime")
            }
        else:
            return {"status": "unhealthy", "http_code": response.status_code}
            
    except requests.exceptions.RequestException as e:
        return {"status": "unreachable", "error": str(e)}

# Usage
health_status = monitor_crawl4ai()
print("Crawl4AI status:", health_status)
```

## 🚨 Error Handling and Best Practices

### Common Error Codes

| Code | Description | Solution |
|------|-------------|----------|
| 400 | Bad Request | Check request format and parameters |
| 403 | Forbidden | Target site blocking requests |
| 404 | Not Found | URL doesn't exist |
| 429 | Too Many Requests | Implement rate limiting |
| 500 | Internal Server Error | Check service logs |
| 502 | Bad Gateway | Target site temporarily unavailable |
| 503 | Service Unavailable | Crawl4AI service overloaded |

### Error Response Format

```json
{
  "success": false,
  "error": {
    "code": "CRAWL_FAILED",
    "message": "Failed to crawl URL: Connection timeout",
    "details": {
      "url": "https://example.com",
      "status_code": null,
      "timeout": 30
    }
  }
}
```

### Best Practices

**Respectful Crawling:**
- Respect robots.txt files
- Implement appropriate delays between requests
- Use reasonable User-Agent strings
- Monitor and limit concurrent connections

**Error Handling:**
- Implement retry logic with exponential backoff
- Handle different types of failures appropriately
- Log errors for debugging
- Set reasonable timeouts

**Performance:**
- Use batch operations for multiple URLs
- Cache responses when appropriate
- Monitor memory and CPU usage
- Configure appropriate concurrency limits

**Data Quality:**
- Validate extracted data
- Handle encoding issues
- Clean and normalize text content
- Implement data deduplication

**Security:**
- Validate and sanitize URLs
- Be cautious with dynamic content execution
- Implement proper session management
- Monitor for malicious content

---

[**← Back to API Overview**](README.md) | [**→ Monitoring API Reference**](monitoring.md)

---

**API Version:** Crawl4AI 0.2.x  
**Last Updated:** January 2025  
**Service Compatibility:** All AI Starter Kit deployments