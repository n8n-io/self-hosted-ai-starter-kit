#!/usr/bin/env python3

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Dict, Any, List, Optional
import torch
from transformers import AutoTokenizer, AutoModel
from concurrent.futures import ThreadPoolExecutor
import asyncio
import logging
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app with proper metadata
app = FastAPI(
    title="Crawl4AI API",
    description="GPU-accelerated web crawling and content processing API",
    version="1.0.0"
)

class CrawlerParams(BaseModel):
    headless: bool = True
    page_timeout: int = 30000
    process_images: bool = True
    extract_embeddings: bool = True
    batch_size: int = 32

class CrawlRequest(BaseModel):
    urls: str
    priority: int = 10
    crawler_params: Optional[CrawlerParams] = CrawlerParams()

class TaskStatus(BaseModel):
    task_id: str
    status: str
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None

# Store tasks in memory (replace with proper database in production)
tasks = {}

class GPUProcessor:
    def __init__(self):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        logger.info(f"Using device: {self.device}")
        
        # Load models
        self.tokenizer = AutoTokenizer.from_pretrained("sentence-transformers/all-MiniLM-L6-v2")
        self.model = AutoModel.from_pretrained("sentence-transformers/all-MiniLM-L6-v2").to(self.device)
        
    def process_content(self, text: str) -> torch.Tensor:
        """Process content using GPU acceleration"""
        inputs = self.tokenizer(text, padding=True, truncation=True, return_tensors="pt")
        inputs = {k: v.to(self.device) for k, v in inputs.items()}
        
        with torch.no_grad():
            outputs = self.model(**inputs)
            embeddings = outputs.last_hidden_state.mean(dim=1)
        
        return embeddings

# Initialize GPU processor
processor = GPUProcessor()

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}

@app.post("/crawl")
async def start_crawl(request: CrawlRequest):
    """Start a new crawl task"""
    task_id = f"task_{len(tasks) + 1}"
    
    # Simulate crawling with GPU processing
    async def process_task():
        try:
            # Simulate crawling
            await asyncio.sleep(2)
            
            # Process content with GPU
            sample_content = [
                "This is a test content for GPU processing.",
                "Another piece of content to process."
            ]
            
            with ThreadPoolExecutor() as executor:
                embeddings = list(executor.map(processor.process_content, sample_content))
            
            tasks[task_id] = {
                "status": "completed",
                "result": {
                    "content": sample_content,
                    "embeddings": [e.cpu().numpy().tolist() for e in embeddings]
                }
            }
        except Exception as e:
            logger.error(f"Task failed: {str(e)}")
            tasks[task_id] = {
                "status": "failed",
                "error": str(e)
            }
    
    # Start task processing
    tasks[task_id] = {"status": "processing"}
    asyncio.create_task(process_task())
    
    return {"task_id": task_id}

@app.get("/task/{task_id}")
async def get_task_status(task_id: str):
    """Get task status"""
    if task_id not in tasks:
        raise HTTPException(status_code=404, detail="Task not found")
    return tasks[task_id] 