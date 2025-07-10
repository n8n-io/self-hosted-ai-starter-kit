#!/usr/bin/env python3
"""
Crawl4AI LLM-based Extraction Examples
=====================================

This script demonstrates how to use Crawl4AI with various LLM providers
for intelligent web scraping and data extraction.

Prerequisites:
- Crawl4AI service running on port 11235
- API keys configured as environment variables
- Python packages: requests, asyncio, json

Usage:
    python scripts/crawl4ai-llm-examples.py
"""

import asyncio
import json
import os
import sys
from typing import Dict, List, Any
import requests
from datetime import datetime

# Configuration
CRAWL4AI_BASE_URL = "http://localhost:11235"
SAMPLE_URLS = {
    "news": "https://www.bbc.com/news",
    "ecommerce": "https://example-shop.com/products",
    "academic": "https://arxiv.org/abs/2301.00001",
    "blog": "https://blog.example.com/latest-post"
}

class Crawl4AIClient:
    """Client for interacting with Crawl4AI REST API"""
    
    def __init__(self, base_url: str = CRAWL4AI_BASE_URL):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({
            "Content-Type": "application/json",
            "User-Agent": "Crawl4AI-Example-Client/1.0"
        })
    
    def health_check(self) -> bool:
        """Check if Crawl4AI service is healthy"""
        try:
            response = self.session.get(f"{self.base_url}/health", timeout=10)
            return response.status_code == 200
        except Exception as e:
            print(f"Health check failed: {e}")
            return False
    
    def crawl_with_llm(self, url: str, extraction_config: Dict[str, Any]) -> Dict[str, Any]:
        """Perform crawling with LLM-based extraction"""
        payload = {
            "urls": [url],
            "crawler_config": {
                "type": "CrawlerRunConfig",
                "params": {
                    "extraction_strategy": extraction_config,
                    "cache_mode": "bypass"
                }
            },
            "browser_config": {
                "type": "BrowserConfig", 
                "params": {
                    "headless": True,
                    "user_agent": "Mozilla/5.0 (compatible; Crawl4AI/1.0)"
                }
            }
        }
        
        try:
            print(f"🕷️  Crawling: {url}")
            response = self.session.post(
                f"{self.base_url}/crawl",
                json=payload,
                timeout=300
            )
            
            if response.ok:
                result = response.json()
                print(f"✅ Extraction completed successfully")
                return result
            else:
                print(f"❌ Extraction failed: {response.status_code} - {response.text}")
                return {"success": False, "error": response.text}
                
        except Exception as e:
            print(f"❌ Request failed: {e}")
            return {"success": False, "error": str(e)}

def create_openai_extraction_config(schema: Dict[str, Any], instruction: str) -> Dict[str, Any]:
    """Create OpenAI-based extraction configuration"""
    return {
        "type": "LLMExtractionStrategy",
        "params": {
            "llm_config": {
                "type": "LlmConfig",
                "params": {
                    "provider": "openai/gpt-4o-mini",
                    "api_token": os.getenv("OPENAI_API_KEY")
                }
            },
            "schema": {
                "type": "dict",
                "value": schema
            },
            "extraction_type": "schema",
            "instruction": instruction,
            "chunk_token_threshold": 4000,
            "overlap_rate": 0.1,
            "apply_chunking": True,
            "input_format": "markdown",
            "extra_args": {
                "type": "dict",
                "value": {
                    "temperature": 0.1,
                    "max_tokens": 2000
                }
            }
        }
    }

def create_ollama_extraction_config(schema: Dict[str, Any], instruction: str, model: str = "deepseek-r1:8b-optimized") -> Dict[str, Any]:
    """Create Ollama-based extraction configuration"""
    return {
        "type": "LLMExtractionStrategy",
        "params": {
            "llm_config": {
                "type": "LlmConfig",
                "params": {
                    "provider": f"ollama/{model}",
                    "base_url": "http://localhost:11434"
                }
            },
            "schema": {
                "type": "dict",
                "value": schema
            },
            "extraction_type": "schema",
            "instruction": instruction,
            "chunk_token_threshold": 6000,
            "input_format": "html",
            "extra_args": {
                "type": "dict",
                "value": {
                    "temperature": 0.0,
                    "num_predict": 2048
                }
            }
        }
    }

def example_1_news_article_analysis():
    """Example 1: News Article Analysis with OpenAI"""
    print("\n" + "="*60)
    print("📰 EXAMPLE 1: News Article Analysis")
    print("="*60)
    
    schema = {
        "type": "object",
        "properties": {
            "headline": {"type": "string"},
            "summary": {"type": "string", "description": "3-sentence summary"},
            "main_topics": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Key topics covered"
            },
            "sentiment": {
                "type": "object",
                "properties": {
                    "overall": {"type": "string", "enum": ["positive", "negative", "neutral"]},
                    "confidence": {"type": "number", "minimum": 0, "maximum": 1}
                }
            },
            "key_facts": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "fact": {"type": "string"},
                        "importance": {"type": "string", "enum": ["high", "medium", "low"]}
                    }
                }
            }
        }
    }
    
    instruction = """
    Analyze this news article thoroughly. Extract:
    1. The main headline
    2. A concise 3-sentence summary
    3. Key topics discussed
    4. Overall sentiment with confidence score
    5. Important facts with their significance level
    
    Focus on accuracy and provide structured data.
    """
    
    if not os.getenv("OPENAI_API_KEY"):
        print("❌ OPENAI_API_KEY not found. Skipping OpenAI example.")
        return
    
    client = Crawl4AIClient()
    config = create_openai_extraction_config(schema, instruction)
    
    # Use a real news URL or a sample
    test_url = "https://www.bbc.com/news"
    result = client.crawl_with_llm(test_url, config)
    
    if result.get("success"):
        try:
            extracted_data = json.loads(result["results"][0]["extracted_content"])
            print("\n📊 Extracted News Analysis:")
            print(json.dumps(extracted_data, indent=2))
        except (KeyError, json.JSONDecodeError) as e:
            print(f"❌ Failed to parse extracted data: {e}")
    else:
        print(f"❌ Extraction failed: {result.get('error', 'Unknown error')}")

def example_2_ecommerce_products():
    """Example 2: E-commerce Product Extraction with Local Ollama"""
    print("\n" + "="*60)
    print("🛒 EXAMPLE 2: E-commerce Product Extraction")
    print("="*60)
    
    schema = {
        "type": "object",
        "properties": {
            "products": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "price": {"type": "string"},
                        "description": {"type": "string"},
                        "rating": {"type": "number"},
                        "availability": {"type": "string"},
                        "features": {
                            "type": "array",
                            "items": {"type": "string"}
                        }
                    }
                }
            },
            "page_info": {
                "type": "object",
                "properties": {
                    "total_products": {"type": "integer"},
                    "category": {"type": "string"},
                    "filters_available": {
                        "type": "array",
                        "items": {"type": "string"}
                    }
                }
            }
        }
    }
    
    instruction = """
    Extract all product information from this e-commerce page:
    1. Product details: name, price, description, rating, availability
    2. Key features for each product
    3. Overall page information: total products, category, available filters
    
    Be thorough and accurate with pricing and availability data.
    """
    
    client = Crawl4AIClient()
    config = create_ollama_extraction_config(schema, instruction)
    
    # Use a sample e-commerce URL
    test_url = "https://www.amazon.com/s?k=laptops"
    result = client.crawl_with_llm(test_url, config)
    
    if result.get("success"):
        try:
            extracted_data = json.loads(result["results"][0]["extracted_content"])
            print("\n🛍️ Extracted Product Data:")
            print(json.dumps(extracted_data, indent=2))
            
            # Summary statistics
            if "products" in extracted_data:
                print(f"\n📈 Summary: Found {len(extracted_data['products'])} products")
        except (KeyError, json.JSONDecodeError) as e:
            print(f"❌ Failed to parse extracted data: {e}")
    else:
        print(f"❌ Extraction failed: {result.get('error', 'Unknown error')}")

def example_3_knowledge_graph():
    """Example 3: Knowledge Graph Extraction"""
    print("\n" + "="*60)
    print("🕸️ EXAMPLE 3: Knowledge Graph Extraction")
    print("="*60)
    
    schema = {
        "type": "object",
        "properties": {
            "entities": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "type": {
                            "type": "string",
                            "enum": ["person", "organization", "location", "event", "concept", "product"]
                        },
                        "description": {"type": "string"},
                        "importance": {"type": "string", "enum": ["high", "medium", "low"]}
                    }
                }
            },
            "relationships": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "source": {"type": "string"},
                        "target": {"type": "string"},
                        "relationship": {"type": "string"},
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1}
                    }
                }
            }
        }
    }
    
    instruction = """
    Create a knowledge graph from this content by extracting:
    1. Entities: people, organizations, locations, events, concepts, products
    2. Relationships between entities with confidence scores
    3. Importance level for each entity
    
    Focus on meaningful connections and accurate entity classification.
    """
    
    if not os.getenv("OPENAI_API_KEY"):
        print("❌ OPENAI_API_KEY not found. Skipping knowledge graph example.")
        return
    
    client = Crawl4AIClient()
    config = create_openai_extraction_config(schema, instruction)
    
    # Use a content-rich URL
    test_url = "https://en.wikipedia.org/wiki/Artificial_intelligence"
    result = client.crawl_with_llm(test_url, config)
    
    if result.get("success"):
        try:
            extracted_data = json.loads(result["results"][0]["extracted_content"])
            print("\n🕸️ Knowledge Graph:")
            print(json.dumps(extracted_data, indent=2))
            
            # Summary
            entities = extracted_data.get("entities", [])
            relationships = extracted_data.get("relationships", [])
            print(f"\n📊 Graph Summary: {len(entities)} entities, {len(relationships)} relationships")
        except (KeyError, json.JSONDecodeError) as e:
            print(f"❌ Failed to parse extracted data: {e}")
    else:
        print(f"❌ Extraction failed: {result.get('error', 'Unknown error')}")

def example_4_content_summarization():
    """Example 4: Advanced Content Summarization"""
    print("\n" + "="*60)
    print("📝 EXAMPLE 4: Content Summarization and Analysis")
    print("="*60)
    
    schema = {
        "type": "object",
        "properties": {
            "title": {"type": "string"},
            "executive_summary": {"type": "string", "description": "High-level overview in 2-3 sentences"},
            "detailed_summary": {"type": "string", "description": "Comprehensive summary in 1-2 paragraphs"},
            "key_points": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Main takeaways"
            },
            "topics": {
                "type": "array",
                "items": {"type": "string"}
            },
            "complexity_level": {
                "type": "string",
                "enum": ["beginner", "intermediate", "advanced", "expert"]
            },
            "estimated_read_time": {"type": "string"},
            "target_audience": {"type": "string"}
        }
    }
    
    instruction = """
    Analyze and summarize this content comprehensively:
    1. Extract the title
    2. Provide both executive and detailed summaries
    3. List key takeaways
    4. Identify main topics
    5. Assess complexity level and target audience
    6. Estimate reading time
    
    Make summaries clear and actionable.
    """
    
    client = Crawl4AIClient()
    
    # Try local model first, fallback to OpenAI
    if client.health_check():
        config = create_ollama_extraction_config(schema, instruction, "deepseek-r1:8b-optimized")
        model_used = "Local Ollama (DeepSeek-R1)"
    elif os.getenv("OPENAI_API_KEY"):
        config = create_openai_extraction_config(schema, instruction)
        model_used = "OpenAI GPT-4o-mini"
    else:
        print("❌ No LLM provider available. Please configure OPENAI_API_KEY or start Ollama.")
        return
    
    print(f"🤖 Using: {model_used}")
    
    # Use a content-rich blog or article
    test_url = "https://blog.openai.com"
    result = client.crawl_with_llm(test_url, config)
    
    if result.get("success"):
        try:
            extracted_data = json.loads(result["results"][0]["extracted_content"])
            print("\n📋 Content Analysis:")
            print(json.dumps(extracted_data, indent=2))
        except (KeyError, json.JSONDecodeError) as e:
            print(f"❌ Failed to parse extracted data: {e}")
    else:
        print(f"❌ Extraction failed: {result.get('error', 'Unknown error')}")

def run_examples():
    """Run all examples with error handling"""
    print("🚀 Crawl4AI LLM-based Extraction Examples")
    print("=" * 60)
    print(f"📅 Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Check if Crawl4AI service is running
    client = Crawl4AIClient()
    if not client.health_check():
        print("❌ Crawl4AI service is not running at http://localhost:11235")
        print("💡 Please start the Crawl4AI service using docker-compose:")
        print("   docker-compose up crawl4ai")
        sys.exit(1)
    
    print("✅ Crawl4AI service is healthy")
    
    # Check available LLM providers
    available_providers = []
    if os.getenv("OPENAI_API_KEY"):
        available_providers.append("OpenAI")
    if client.health_check():  # Assuming Ollama is available if Crawl4AI is running
        available_providers.append("Local Ollama")
    
    if not available_providers:
        print("⚠️ No LLM providers configured. Some examples may be skipped.")
    else:
        print(f"🤖 Available LLM providers: {', '.join(available_providers)}")
    
    # Run examples
    examples = [
        ("News Analysis", example_1_news_article_analysis),
        ("E-commerce Products", example_2_ecommerce_products),
        ("Knowledge Graph", example_3_knowledge_graph),
        ("Content Summarization", example_4_content_summarization)
    ]
    
    results = {}
    
    for name, example_func in examples:
        try:
            print(f"\n🔄 Running: {name}")
            example_func()
            results[name] = "✅ Success"
        except KeyboardInterrupt:
            print(f"\n⏹️ Stopped by user")
            break
        except Exception as e:
            print(f"\n❌ {name} failed: {e}")
            results[name] = f"❌ Failed: {e}"
    
    # Summary
    print("\n" + "="*60)
    print("📊 EXECUTION SUMMARY")
    print("="*60)
    for name, status in results.items():
        print(f"{status} {name}")
    
    print(f"\n📅 Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

def main():
    """Main function"""
    if len(sys.argv) > 1:
        if sys.argv[1] == "--health":
            client = Crawl4AIClient()
            if client.health_check():
                print("✅ Crawl4AI service is healthy")
                sys.exit(0)
            else:
                print("❌ Crawl4AI service is not responding")
                sys.exit(1)
        elif sys.argv[1] == "--help":
            print(__doc__)
            sys.exit(0)
    
    run_examples()

if __name__ == "__main__":
    main() 