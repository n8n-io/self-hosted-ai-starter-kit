# Qdrant Vector Database API Reference

> Complete API documentation for Qdrant vector database service

Qdrant is a high-performance vector database designed for similarity search and AI applications. This document covers all Qdrant API endpoints and integration patterns available in the AI Starter Kit.

## 🌟 Service Overview

| Property | Details |
|----------|---------|
| **Service** | Qdrant Vector Database |
| **Port** | 6333 |
| **Protocol** | HTTP/HTTPS |
| **Authentication** | API Key (optional) |
| **Documentation** | [Qdrant API Docs](https://qdrant.tech/documentation/) |

## 🔐 Authentication

### API Key Authentication
Production deployments use API key authentication:

```bash
# API key in header
curl -H "api-key: your-api-key" http://your-ip:6333/collections

# Alternative header format
curl -H "Authorization: Bearer your-api-key" http://your-ip:6333/collections
```

### No Authentication
Development deployments may run without authentication:

```bash
# Direct access (development only)
curl http://your-ip:6333/collections
```

## 📚 Core API Endpoints

### Health and Status

#### Health Check
```bash
GET /health
```

**Response:**
```json
{
  "title": "qdrant - vector search engine",
  "version": "1.7.0"
}
```

#### Cluster Information
```bash
GET /cluster
```

**Response:**
```json
{
  "result": {
    "status": "enabled",
    "peer_id": 123456789,
    "peers": {
      "123456789": {
        "uri": "http://127.0.0.1:6333/"
      }
    },
    "raft_info": {
      "term": 1,
      "commit": 4,
      "pending_operations": 0,
      "leader": 123456789,
      "role": "Leader"
    }
  },
  "time": 0.001
}
```

### Collection Management

#### List Collections
```bash
GET /collections
```

**Response:**
```json
{
  "result": {
    "collections": [
      {
        "name": "my_collection",
        "status": "green",
        "optimizer_status": "ok",
        "vectors_count": 1000,
        "indexed_vectors_count": 1000,
        "points_count": 1000,
        "segments_count": 1,
        "config": {
          "params": {
            "vectors": {
              "size": 384,
              "distance": "Cosine"
            },
            "shard_number": 1,
            "replication_factor": 1
          }
        }
      }
    ]
  },
  "time": 0.002
}
```

#### Get Collection Info
```bash
GET /collections/{collection_name}
```

#### Create Collection
```bash
PUT /collections/{collection_name}
Content-Type: application/json

{
  "vectors": {
    "size": 384,
    "distance": "Cosine"
  },
  "shard_number": 1,
  "replication_factor": 1
}
```

**Advanced Collection Configuration:**
```bash
PUT /collections/advanced_collection
Content-Type: application/json

{
  "vectors": {
    "size": 768,
    "distance": "Dot",
    "hnsw_config": {
      "m": 16,
      "ef_construct": 100,
      "full_scan_threshold": 10000,
      "max_indexing_threads": 0
    },
    "quantization_config": {
      "scalar": {
        "type": "int8",
        "quantile": 0.99,
        "always_ram": true
      }
    }
  },
  "shard_number": 2,
  "replication_factor": 1,
  "write_consistency_factor": 1,
  "on_disk_payload": true,
  "hnsw_config": {
    "m": 16,
    "ef_construct": 100,
    "full_scan_threshold": 10000
  },
  "wal_config": {
    "wal_capacity_mb": 32,
    "wal_segments_ahead": 0
  },
  "optimizers_config": {
    "deleted_threshold": 0.2,
    "vacuum_min_vector_number": 1000,
    "default_segment_number": 0,
    "max_segment_size": 5000,
    "memmap_threshold": 50000,
    "indexing_threshold": 20000,
    "flush_interval_sec": 5,
    "max_optimization_threads": 1
  }
}
```

#### Update Collection
```bash
PATCH /collections/{collection_name}
Content-Type: application/json

{
  "optimizers_config": {
    "indexing_threshold": 30000
  }
}
```

#### Delete Collection
```bash
DELETE /collections/{collection_name}
```

### Points (Vectors) Management

#### Insert Points
```bash
PUT /collections/{collection_name}/points
Content-Type: application/json

{
  "points": [
    {
      "id": 1,
      "vector": [0.1, 0.2, 0.3, 0.4],
      "payload": {
        "title": "Document 1",
        "category": "science",
        "timestamp": "2024-01-01T12:00:00Z"
      }
    },
    {
      "id": 2,
      "vector": [0.5, 0.6, 0.7, 0.8],
      "payload": {
        "title": "Document 2", 
        "category": "technology",
        "timestamp": "2024-01-01T13:00:00Z"
      }
    }
  ]
}
```

#### Upsert Points
```bash
PUT /collections/{collection_name}/points?wait=true
Content-Type: application/json

{
  "points": [
    {
      "id": "unique-id-1",
      "vector": [0.1, 0.2, 0.3, 0.4],
      "payload": {
        "text": "This is a sample document",
        "metadata": {
          "source": "web",
          "processed": true
        }
      }
    }
  ]
}
```

#### Get Points
```bash
GET /collections/{collection_name}/points/{point_id}

# Multiple points
POST /collections/{collection_name}/points
Content-Type: application/json

{
  "ids": [1, 2, 3],
  "with_payload": true,
  "with_vector": true
}
```

#### Search Similar Points
```bash
POST /collections/{collection_name}/points/search
Content-Type: application/json

{
  "vector": [0.1, 0.2, 0.3, 0.4],
  "limit": 10,
  "with_payload": true,
  "with_vector": false,
  "score_threshold": 0.7
}
```

**Advanced Search with Filters:**
```bash
POST /collections/{collection_name}/points/search
Content-Type: application/json

{
  "vector": [0.1, 0.2, 0.3, 0.4],
  "limit": 5,
  "offset": 0,
  "with_payload": true,
  "with_vector": false,
  "filter": {
    "must": [
      {
        "key": "category",
        "match": {
          "value": "science"
        }
      }
    ],
    "should": [
      {
        "key": "timestamp", 
        "range": {
          "gte": "2024-01-01T00:00:00Z",
          "lt": "2024-12-31T23:59:59Z"
        }
      }
    ],
    "must_not": [
      {
        "key": "status",
        "match": {
          "value": "deleted"
        }
      }
    ]
  },
  "params": {
    "hnsw_ef": 128,
    "exact": false
  }
}
```

#### Batch Search
```bash
POST /collections/{collection_name}/points/search/batch
Content-Type: application/json

{
  "searches": [
    {
      "vector": [0.1, 0.2, 0.3, 0.4],
      "limit": 5,
      "with_payload": true
    },
    {
      "vector": [0.5, 0.6, 0.7, 0.8],
      "limit": 3,
      "with_payload": true,
      "filter": {
        "must": [
          {
            "key": "category",
            "match": {"value": "technology"}
          }
        ]
      }
    }
  ]
}
```

#### Scroll Through Points
```bash
POST /collections/{collection_name}/points/scroll
Content-Type: application/json

{
  "limit": 100,
  "with_payload": true,
  "with_vector": false,
  "filter": {
    "must": [
      {
        "key": "processed",
        "match": {"value": true}
      }
    ]
  }
}
```

#### Delete Points
```bash
POST /collections/{collection_name}/points/delete
Content-Type: application/json

{
  "points": [1, 2, 3]
}
```

**Delete with Filter:**
```bash
POST /collections/{collection_name}/points/delete
Content-Type: application/json

{
  "filter": {
    "must": [
      {
        "key": "status",
        "match": {"value": "expired"}
      }
    ]
  }
}
```

### Payload Management

#### Set Payload
```bash
POST /collections/{collection_name}/points/payload
Content-Type: application/json

{
  "payload": {
    "new_field": "new_value",
    "updated_field": "updated_value"
  },
  "points": [1, 2, 3]
}
```

#### Overwrite Payload
```bash
PUT /collections/{collection_name}/points/payload
Content-Type: application/json

{
  "payload": {
    "title": "New Title",
    "category": "updated"
  },
  "points": [1, 2, 3]
}
```

#### Delete Payload Keys
```bash
POST /collections/{collection_name}/points/payload/delete
Content-Type: application/json

{
  "keys": ["old_field", "deprecated_field"],
  "points": [1, 2, 3]
}
```

#### Clear Payload
```bash
POST /collections/{collection_name}/points/payload/clear
Content-Type: application/json

{
  "points": [1, 2, 3]
}
```

## 🔍 Advanced Features

### Filtering

#### Basic Filters
```json
{
  "filter": {
    "must": [
      {"key": "category", "match": {"value": "science"}},
      {"key": "year", "range": {"gte": 2020, "lt": 2025}}
    ],
    "should": [
      {"key": "language", "match": {"value": "en"}},
      {"key": "language", "match": {"value": "es"}}
    ],
    "must_not": [
      {"key": "status", "match": {"value": "deleted"}}
    ]
  }
}
```

#### Nested Object Filters
```json
{
  "filter": {
    "must": [
      {
        "nested": {
          "key": "metadata",
          "filter": {
            "must": [
              {"key": "author.name", "match": {"value": "John Doe"}},
              {"key": "publication.year", "range": {"gte": 2020}}
            ]
          }
        }
      }
    ]
  }
}
```

#### Geo Filters
```json
{
  "filter": {
    "must": [
      {
        "key": "location",
        "geo_bounding_box": {
          "top_left": {"lat": 52.5, "lon": 13.3},
          "bottom_right": {"lat": 52.4, "lon": 13.5}
        }
      }
    ]
  }
}
```

### Index Configuration

#### HNSW Parameters
```json
{
  "hnsw_config": {
    "m": 16,
    "ef_construct": 100,
    "full_scan_threshold": 10000,
    "max_indexing_threads": 0,
    "on_disk": false,
    "payload_m": 16
  }
}
```

#### Quantization
```json
{
  "quantization_config": {
    "scalar": {
      "type": "int8",
      "quantile": 0.99,
      "always_ram": true
    }
  }
}
```

### Clustering and Sharding

#### Create Collection with Multiple Shards
```bash
PUT /collections/large_collection
Content-Type: application/json

{
  "vectors": {
    "size": 768,
    "distance": "Cosine"
  },
  "shard_number": 4,
  "replication_factor": 2,
  "write_consistency_factor": 1
}
```

## 🔄 Integration Examples

### Python Integration

```python
import requests
import numpy as np
from typing import List, Dict, Any, Optional

class QdrantClient:
    def __init__(self, host: str = "localhost", port: int = 6333, api_key: Optional[str] = None):
        self.base_url = f"http://{host}:{port}"
        self.headers = {"Content-Type": "application/json"}
        if api_key:
            self.headers["api-key"] = api_key
    
    def create_collection(self, collection_name: str, vector_size: int, distance: str = "Cosine"):
        """Create a new collection"""
        data = {
            "vectors": {
                "size": vector_size,
                "distance": distance
            }
        }
        response = requests.put(
            f"{self.base_url}/collections/{collection_name}",
            json=data,
            headers=self.headers
        )
        return response.json()
    
    def upsert_points(self, collection_name: str, points: List[Dict[str, Any]]):
        """Insert or update points"""
        data = {"points": points}
        response = requests.put(
            f"{self.base_url}/collections/{collection_name}/points",
            json=data,
            headers=self.headers,
            params={"wait": "true"}
        )
        return response.json()
    
    def search(self, collection_name: str, vector: List[float], limit: int = 10, 
              filter_conditions: Optional[Dict] = None, score_threshold: Optional[float] = None):
        """Search for similar vectors"""
        data = {
            "vector": vector,
            "limit": limit,
            "with_payload": True,
            "with_vector": False
        }
        
        if filter_conditions:
            data["filter"] = filter_conditions
        
        if score_threshold:
            data["score_threshold"] = score_threshold
        
        response = requests.post(
            f"{self.base_url}/collections/{collection_name}/points/search",
            json=data,
            headers=self.headers
        )
        return response.json()
    
    def get_point(self, collection_name: str, point_id: Any):
        """Get a specific point by ID"""
        response = requests.get(
            f"{self.base_url}/collections/{collection_name}/points/{point_id}",
            headers=self.headers
        )
        return response.json()
    
    def delete_points(self, collection_name: str, point_ids: List[Any]):
        """Delete points by IDs"""
        data = {"points": point_ids}
        response = requests.post(
            f"{self.base_url}/collections/{collection_name}/points/delete",
            json=data,
            headers=self.headers
        )
        return response.json()
    
    def list_collections(self):
        """List all collections"""
        response = requests.get(f"{self.base_url}/collections", headers=self.headers)
        return response.json()

# Usage examples
client = QdrantClient(host="your-ip", port=6333, api_key="your-api-key")

# Create collection
client.create_collection("documents", vector_size=384, distance="Cosine")

# Upsert points
points = [
    {
        "id": 1,
        "vector": np.random.rand(384).tolist(),
        "payload": {
            "title": "First Document",
            "category": "science",
            "text": "This is the content of the first document"
        }
    },
    {
        "id": 2,
        "vector": np.random.rand(384).tolist(),
        "payload": {
            "title": "Second Document",
            "category": "technology",
            "text": "This is the content of the second document"
        }
    }
]

client.upsert_points("documents", points)

# Search
query_vector = np.random.rand(384).tolist()
results = client.search(
    "documents", 
    query_vector, 
    limit=5,
    filter_conditions={
        "must": [
            {"key": "category", "match": {"value": "science"}}
        ]
    }
)

print("Search results:", results)
```

### JavaScript Integration

```javascript
class QdrantClient {
    constructor(host = 'localhost', port = 6333, apiKey = null) {
        this.baseUrl = `http://${host}:${port}`;
        this.headers = { 'Content-Type': 'application/json' };
        if (apiKey) {
            this.headers['api-key'] = apiKey;
        }
    }

    async createCollection(collectionName, vectorSize, distance = 'Cosine') {
        const response = await fetch(`${this.baseUrl}/collections/${collectionName}`, {
            method: 'PUT',
            headers: this.headers,
            body: JSON.stringify({
                vectors: {
                    size: vectorSize,
                    distance: distance
                }
            })
        });
        return await response.json();
    }

    async upsertPoints(collectionName, points) {
        const response = await fetch(`${this.baseUrl}/collections/${collectionName}/points?wait=true`, {
            method: 'PUT',
            headers: this.headers,
            body: JSON.stringify({ points })
        });
        return await response.json();
    }

    async search(collectionName, vector, options = {}) {
        const {
            limit = 10,
            filter = null,
            scoreThreshold = null,
            withPayload = true,
            withVector = false
        } = options;

        const data = {
            vector,
            limit,
            with_payload: withPayload,
            with_vector: withVector
        };

        if (filter) data.filter = filter;
        if (scoreThreshold) data.score_threshold = scoreThreshold;

        const response = await fetch(`${this.baseUrl}/collections/${collectionName}/points/search`, {
            method: 'POST',
            headers: this.headers,
            body: JSON.stringify(data)
        });
        return await response.json();
    }

    async scrollPoints(collectionName, options = {}) {
        const {
            limit = 100,
            filter = null,
            withPayload = true,
            withVector = false,
            offset = null
        } = options;

        const data = {
            limit,
            with_payload: withPayload,
            with_vector: withVector
        };

        if (filter) data.filter = filter;
        if (offset) data.offset = offset;

        const response = await fetch(`${this.baseUrl}/collections/${collectionName}/points/scroll`, {
            method: 'POST',
            headers: this.headers,
            body: JSON.stringify(data)
        });
        return await response.json();
    }

    async deletePoints(collectionName, pointIds) {
        const response = await fetch(`${this.baseUrl}/collections/${collectionName}/points/delete`, {
            method: 'POST',
            headers: this.headers,
            body: JSON.stringify({ points: pointIds })
        });
        return await response.json();
    }

    async getCollectionInfo(collectionName) {
        const response = await fetch(`${this.baseUrl}/collections/${collectionName}`, {
            headers: this.headers
        });
        return await response.json();
    }
}

// Usage examples
const client = new QdrantClient('your-ip', 6333, 'your-api-key');

// Create collection and add points
async function setupCollection() {
    // Create collection
    await client.createCollection('my_collection', 384);

    // Add points
    const points = [
        {
            id: 'doc_1',
            vector: Array.from({length: 384}, () => Math.random()),
            payload: {
                title: 'Sample Document',
                category: 'research',
                content: 'This is a sample document for testing'
            }
        }
    ];

    await client.upsertPoints('my_collection', points);
}

// Search and display results
async function searchDocuments(queryVector) {
    const results = await client.search('my_collection', queryVector, {
        limit: 10,
        filter: {
            must: [
                { key: 'category', match: { value: 'research' } }
            ]
        },
        scoreThreshold: 0.7
    });

    console.log('Search results:', results.result);
    return results.result;
}
```

### RAG (Retrieval-Augmented Generation) Example

```python
import requests
import numpy as np
from sentence_transformers import SentenceTransformer

class RAGPipeline:
    def __init__(self, qdrant_host="localhost", qdrant_port=6333, ollama_host="localhost", ollama_port=11434):
        self.qdrant_client = QdrantClient(qdrant_host, qdrant_port)
        self.ollama_url = f"http://{ollama_host}:{ollama_port}"
        self.encoder = SentenceTransformer('all-MiniLM-L6-v2')
        
    def add_documents(self, collection_name: str, documents: List[Dict[str, str]]):
        """Add documents to the vector database"""
        points = []
        for i, doc in enumerate(documents):
            # Generate embedding
            embedding = self.encoder.encode(doc['text']).tolist()
            
            points.append({
                "id": doc.get('id', i),
                "vector": embedding,
                "payload": {
                    "text": doc['text'],
                    "title": doc.get('title', f"Document {i}"),
                    "source": doc.get('source', 'unknown')
                }
            })
        
        return self.qdrant_client.upsert_points(collection_name, points)
    
    def search_documents(self, collection_name: str, query: str, limit: int = 5):
        """Search for relevant documents"""
        # Generate query embedding
        query_embedding = self.encoder.encode(query).tolist()
        
        # Search in Qdrant
        results = self.qdrant_client.search(
            collection_name, 
            query_embedding, 
            limit=limit,
            score_threshold=0.5
        )
        
        return results.get('result', [])
    
    def generate_answer(self, query: str, context_docs: List[Dict]):
        """Generate answer using Ollama with context"""
        # Prepare context
        context = "\n\n".join([
            f"Document {i+1}: {doc['payload']['text']}" 
            for i, doc in enumerate(context_docs)
        ])
        
        # Create prompt
        prompt = f"""Based on the following context, answer the question.

Context:
{context}

Question: {query}

Answer:"""
        
        # Call Ollama
        response = requests.post(f"{self.ollama_url}/api/generate", json={
            "model": "llama2",
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.7}
        })
        
        if response.status_code == 200:
            return response.json()['response']
        else:
            return "Error generating response"
    
    def query(self, collection_name: str, question: str):
        """Complete RAG query pipeline"""
        # 1. Search for relevant documents
        relevant_docs = self.search_documents(collection_name, question)
        
        if not relevant_docs:
            return "No relevant documents found."
        
        # 2. Generate answer with context
        answer = self.generate_answer(question, relevant_docs)
        
        return {
            "answer": answer,
            "sources": [doc['payload']['title'] for doc in relevant_docs],
            "relevance_scores": [doc['score'] for doc in relevant_docs]
        }

# Usage
rag = RAGPipeline()

# Setup collection
rag.qdrant_client.create_collection("knowledge_base", 384)

# Add documents
documents = [
    {
        "id": 1,
        "title": "AI Fundamentals",
        "text": "Artificial Intelligence is a branch of computer science that aims to create intelligent machines capable of thinking and learning like humans.",
        "source": "textbook"
    },
    {
        "id": 2,
        "title": "Machine Learning Basics",
        "text": "Machine Learning is a subset of AI that enables computers to learn and improve from experience without being explicitly programmed.",
        "source": "research_paper"
    }
]

rag.add_documents("knowledge_base", documents)

# Query the system
result = rag.query("knowledge_base", "What is artificial intelligence?")
print("Answer:", result["answer"])
print("Sources:", result["sources"])
```

## 📊 Performance Optimization

### Index Optimization

```json
{
  "hnsw_config": {
    "m": 16,              // Number of bi-directional links for each node
    "ef_construct": 100,  // Size of the dynamic candidate list for construction
    "full_scan_threshold": 10000,  // Minimal size for index usage
    "max_indexing_threads": 0      // 0 = auto-detect CPU cores
  }
}
```

### Memory Optimization

```json
{
  "vectors": {
    "size": 768,
    "distance": "Cosine",
    "on_disk": true  // Store vectors on disk to save RAM
  },
  "optimizers_config": {
    "memmap_threshold": 50000,  // Use memory mapping for large segments
    "max_segment_size": 5000    // Limit segment size
  }
}
```

### Query Optimization

```bash
# Use appropriate ef parameter for search accuracy vs speed trade-off
POST /collections/my_collection/points/search
{
  "vector": [...],
  "limit": 10,
  "params": {
    "hnsw_ef": 64,    // Higher = more accurate, slower
    "exact": false    // Use approximate search for speed
  }
}
```

## 🔍 Monitoring and Maintenance

### Collection Statistics

```bash
# Get detailed collection information
GET /collections/{collection_name}

# Response includes performance metrics
{
  "result": {
    "status": "green",
    "optimizer_status": "ok",
    "vectors_count": 1000000,
    "indexed_vectors_count": 1000000,
    "points_count": 1000000,
    "segments_count": 4,
    "config": {...},
    "payload_schema": {...}
  }
}
```

### Health Monitoring

```python
def check_qdrant_health(client):
    """Check Qdrant cluster health"""
    try:
        # Basic health check
        response = requests.get(f"{client.base_url}/health")
        if response.status_code != 200:
            return {"status": "unhealthy", "reason": "Health endpoint failed"}
        
        # Check collections
        collections = client.list_collections()
        if "result" not in collections:
            return {"status": "unhealthy", "reason": "Cannot list collections"}
        
        # Check individual collection health
        unhealthy_collections = []
        for collection in collections["result"]["collections"]:
            if collection["status"] != "green":
                unhealthy_collections.append(collection["name"])
        
        if unhealthy_collections:
            return {
                "status": "degraded", 
                "unhealthy_collections": unhealthy_collections
            }
        
        return {"status": "healthy"}
        
    except Exception as e:
        return {"status": "unhealthy", "reason": str(e)}
```

### Backup and Recovery

```bash
# Create snapshot
POST /collections/{collection_name}/snapshots

# List snapshots
GET /collections/{collection_name}/snapshots

# Download snapshot
GET /collections/{collection_name}/snapshots/{snapshot_name}

# Restore from snapshot
PUT /collections/{collection_name}/snapshots/upload
```

## 🚨 Error Handling and Best Practices

### Common Error Codes

| Code | Description | Solution |
|------|-------------|----------|
| 400 | Bad Request | Check request format and parameters |
| 404 | Collection/Point Not Found | Verify collection/point exists |
| 409 | Conflict | Collection already exists or operation conflict |
| 422 | Unprocessable Entity | Invalid vector dimension or data format |
| 500 | Internal Server Error | Check Qdrant logs and system resources |

### Best Practices

**Collection Design:**
- Choose appropriate vector dimensions (balance accuracy vs. performance)
- Use consistent distance metrics for your use case
- Plan shard distribution for large collections
- Enable quantization for memory efficiency

**Indexing:**
- Tune HNSW parameters based on your data and query patterns
- Use appropriate `ef_construct` values (higher = better quality, slower indexing)
- Consider `on_disk` storage for large collections

**Querying:**
- Use filters to reduce search space
- Implement appropriate score thresholds
- Batch queries when possible for better throughput
- Use scrolling for large result sets

**Performance:**
- Monitor memory usage and adjust configuration accordingly
- Use appropriate hardware (SSD for storage, sufficient RAM)
- Consider replication for high availability
- Regular maintenance and optimization

**Security:**
- Enable API key authentication in production
- Use HTTPS for external access
- Implement proper network security
- Regular backup of critical collections

---

[**← Back to API Overview**](README.md) | [**→ Crawl4AI API Reference**](crawl4ai-service.md)

---

**API Version:** Qdrant 1.7.x  
**Last Updated:** January 2025  
**Service Compatibility:** All AI Starter Kit deployments