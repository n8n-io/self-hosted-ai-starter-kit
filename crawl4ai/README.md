# Crawl4AI Service

GPU-accelerated web crawling and content processing service with FastAPI.

## Overview

Crawl4AI is a high-performance web crawling service that leverages GPU acceleration for content processing and embedding generation. It uses NVIDIA CUDA for hardware acceleration and provides a RESTful API interface.

## Features

- GPU-accelerated content processing
- Web crawling with Playwright
- Text embeddings using Sentence Transformers
- RESTful API with FastAPI
- Docker containerization with NVIDIA GPU support

## Directory Structure

```
crawl4ai/
├── app/
│   ├── __init__.py
│   └── server.py
├── tests/
│   ├── config/
│   └── scripts/
├── Dockerfile
├── requirements.txt
└── README.md
```

## Requirements

- NVIDIA GPU with CUDA support
- Docker with NVIDIA Container Toolkit
- Docker Compose

## API Endpoints

- `GET /health` - Health check endpoint
- `POST /crawl` - Start a new crawling task
- `GET /task/{task_id}` - Get task status

## Environment Variables

- `QDRANT_HOST` - Qdrant vector database host
- `QDRANT_PORT` - Qdrant port (default: 6333)
- `OLLAMA_HOST` - Ollama LLM service host
- `OLLAMA_PORT` - Ollama port (default: 11434)

## Development

1. Build the container:
```bash
docker compose build crawl4ai
```

2. Start the service:
```bash
docker compose --profile gpu-nvidia up -d crawl4ai
```

3. Run tests:
```bash
cd tests/scripts
python -m pytest
```

## License

MIT License 