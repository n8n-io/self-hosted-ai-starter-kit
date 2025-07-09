#!/usr/bin/env python3
"""
Enhanced Agentic Multi-Agent Workforce - Qdrant Vector Store Configuration
This script sets up the Qdrant collections for the workforce system.
"""

import json
import requests
from typing import Dict, List, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Qdrant configuration
QDRANT_HOST = "localhost"
QDRANT_PORT = 6333
QDRANT_URL = f"http://{QDRANT_HOST}:{QDRANT_PORT}"

class QdrantCollectionManager:
    """Manager for Qdrant collections supporting the agentic workforce."""
    
    def __init__(self, base_url: str = QDRANT_URL):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({"Content-Type": "application/json"})
    
    def create_collection(self, collection_name: str, config: Dict[str, Any]) -> bool:
        """Create a Qdrant collection with the specified configuration."""
        try:
            # Check if collection already exists
            response = self.session.get(f"{self.base_url}/collections/{collection_name}")
            if response.status_code == 200:
                logger.info(f"Collection {collection_name} already exists")
                return True
            
            # Create the collection
            response = self.session.put(
                f"{self.base_url}/collections/{collection_name}",
                json=config
            )
            
            if response.status_code in [200, 201]:
                logger.info(f"Successfully created collection: {collection_name}")
                return True
            else:
                logger.error(f"Failed to create collection {collection_name}: {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Error creating collection {collection_name}: {str(e)}")
            return False
    
    def create_index(self, collection_name: str, field_name: str, field_type: str) -> bool:
        """Create an index on a payload field."""
        try:
            config = {
                "field_name": field_name,
                "field_schema": field_type
            }
            
            response = self.session.put(
                f"{self.base_url}/collections/{collection_name}/index",
                json=config
            )
            
            if response.status_code in [200, 201]:
                logger.info(f"Successfully created index on {field_name} for {collection_name}")
                return True
            else:
                logger.error(f"Failed to create index: {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Error creating index: {str(e)}")
            return False

def get_collection_configs() -> Dict[str, Dict[str, Any]]:
    """
    Define all collection configurations for the agentic workforce.
    
    Collections support the 5 principles:
    1. Member Awareness - knowledge_base, agent_capabilities
    2. Member Autonomy - agent_learnings, decision_history
    3. Member Solidarity - shared_memory, collaboration_patterns
    4. Member Expandability - scalable_workflows, dynamic_capabilities
    5. Member Resiliency - error_patterns, recovery_procedures
    """
    return {
        # MEMBER AWARENESS & SOLIDARITY
        "knowledge_base": {
            "vectors": {
                "size": 1536,  # OpenAI embedding dimension
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 2,
                "max_segment_size": 20000,
                "memmap_threshold": 20000,
                "indexing_threshold": 20000,
                "flush_interval_sec": 5,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True,
            "hnsw_config": {
                "m": 16,
                "ef_construct": 100,
                "full_scan_threshold": 10000,
                "max_indexing_threads": 0,
                "on_disk": False
            }
        },
        
        # MEMBER AWARENESS
        "agent_capabilities": {
            "vectors": {
                "size": 768,  # Smaller dimension for capability vectors
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 1,
                "max_segment_size": 10000,
                "memmap_threshold": 10000,
                "indexing_threshold": 10000,
                "flush_interval_sec": 5,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # MEMBER AUTONOMY
        "agent_learnings": {
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 2,
                "max_segment_size": 15000,
                "memmap_threshold": 15000,
                "indexing_threshold": 15000,
                "flush_interval_sec": 10,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # MEMBER SOLIDARITY
        "shared_memory": {
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 3,
                "max_segment_size": 25000,
                "memmap_threshold": 25000,
                "indexing_threshold": 25000,
                "flush_interval_sec": 5,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # MEMBER SOLIDARITY
        "collaboration_patterns": {
            "vectors": {
                "size": 512,  # Smaller for pattern recognition
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 1,
                "max_segment_size": 5000,
                "memmap_threshold": 5000,
                "indexing_threshold": 5000,
                "flush_interval_sec": 15,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # MEMBER EXPANDABILITY
        "scalable_workflows": {
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 2,
                "max_segment_size": 10000,
                "memmap_threshold": 10000,
                "indexing_threshold": 10000,
                "flush_interval_sec": 10,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # MEMBER RESILIENCY
        "error_patterns": {
            "vectors": {
                "size": 768,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 1,
                "max_segment_size": 5000,
                "memmap_threshold": 5000,
                "indexing_threshold": 5000,
                "flush_interval_sec": 30,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # MEMBER RESILIENCY
        "recovery_procedures": {
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 1,
                "max_segment_size": 3000,
                "memmap_threshold": 3000,
                "indexing_threshold": 3000,
                "flush_interval_sec": 30,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # HISTORICAL ANALYSIS (The Archivist)
        "historical_context": {
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 3,
                "max_segment_size": 30000,
                "memmap_threshold": 30000,
                "indexing_threshold": 30000,
                "flush_interval_sec": 5,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # SENTIMENT ANALYSIS (The Voice)
        "sentiment_data": {
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 2,
                "max_segment_size": 20000,
                "memmap_threshold": 20000,
                "indexing_threshold": 20000,
                "flush_interval_sec": 10,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        },
        
        # COMMUNICATION TEMPLATES (The Pen)
        "communication_templates": {
            "vectors": {
                "size": 1536,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 1,
                "max_segment_size": 5000,
                "memmap_threshold": 5000,
                "indexing_threshold": 5000,
                "flush_interval_sec": 30,
                "max_optimization_threads": 1
            },
            "replication_factor": 1,
            "write_consistency_factor": 1,
            "on_disk_payload": True
        }
    }

def get_payload_indexes() -> Dict[str, List[Dict[str, str]]]:
    """Define payload field indexes for efficient querying."""
    return {
        "knowledge_base": [
            {"field_name": "agent_id", "field_type": "keyword"},
            {"field_name": "category", "field_type": "keyword"},
            {"field_name": "tags", "field_type": "keyword"},
            {"field_name": "timestamp", "field_type": "datetime"},
            {"field_name": "confidence_score", "field_type": "float"},
            {"field_name": "workflow_id", "field_type": "keyword"},
            {"field_name": "execution_id", "field_type": "keyword"}
        ],
        "agent_capabilities": [
            {"field_name": "agent_id", "field_type": "keyword"},
            {"field_name": "capability_type", "field_type": "keyword"},
            {"field_name": "authority_level", "field_type": "integer"},
            {"field_name": "specialization", "field_type": "keyword"},
            {"field_name": "performance_score", "field_type": "float"}
        ],
        "agent_learnings": [
            {"field_name": "agent_id", "field_type": "keyword"},
            {"field_name": "learning_type", "field_type": "keyword"},
            {"field_name": "success_rate", "field_type": "float"},
            {"field_name": "timestamp", "field_type": "datetime"},
            {"field_name": "context", "field_type": "keyword"}
        ],
        "shared_memory": [
            {"field_name": "session_id", "field_type": "keyword"},
            {"field_name": "agent_id", "field_type": "keyword"},
            {"field_name": "message_type", "field_type": "keyword"},
            {"field_name": "timestamp", "field_type": "datetime"},
            {"field_name": "importance", "field_type": "float"}
        ],
        "collaboration_patterns": [
            {"field_name": "agent_pair", "field_type": "keyword"},
            {"field_name": "pattern_type", "field_type": "keyword"},
            {"field_name": "success_rate", "field_type": "float"},
            {"field_name": "frequency", "field_type": "integer"},
            {"field_name": "context", "field_type": "keyword"}
        ],
        "scalable_workflows": [
            {"field_name": "workflow_type", "field_type": "keyword"},
            {"field_name": "scalability_factor", "field_type": "float"},
            {"field_name": "agent_count", "field_type": "integer"},
            {"field_name": "complexity", "field_type": "keyword"},
            {"field_name": "success_rate", "field_type": "float"}
        ],
        "error_patterns": [
            {"field_name": "error_type", "field_type": "keyword"},
            {"field_name": "agent_id", "field_type": "keyword"},
            {"field_name": "frequency", "field_type": "integer"},
            {"field_name": "severity", "field_type": "keyword"},
            {"field_name": "timestamp", "field_type": "datetime"}
        ],
        "recovery_procedures": [
            {"field_name": "error_type", "field_type": "keyword"},
            {"field_name": "procedure_type", "field_type": "keyword"},
            {"field_name": "success_rate", "field_type": "float"},
            {"field_name": "complexity", "field_type": "keyword"},
            {"field_name": "agents_involved", "field_type": "keyword"}
        ],
        "historical_context": [
            {"field_name": "time_period", "field_type": "keyword"},
            {"field_name": "context_type", "field_type": "keyword"},
            {"field_name": "relevance_score", "field_type": "float"},
            {"field_name": "source", "field_type": "keyword"},
            {"field_name": "tags", "field_type": "keyword"}
        ],
        "sentiment_data": [
            {"field_name": "sentiment_type", "field_type": "keyword"},
            {"field_name": "polarity", "field_type": "float"},
            {"field_name": "confidence", "field_type": "float"},
            {"field_name": "source", "field_type": "keyword"},
            {"field_name": "timestamp", "field_type": "datetime"}
        ],
        "communication_templates": [
            {"field_name": "template_type", "field_type": "keyword"},
            {"field_name": "audience", "field_type": "keyword"},
            {"field_name": "effectiveness", "field_type": "float"},
            {"field_name": "usage_count", "field_type": "integer"},
            {"field_name": "agent_id", "field_type": "keyword"}
        ]
    }

def main():
    """Main function to set up all Qdrant collections."""
    manager = QdrantCollectionManager()
    
    # Get configurations
    collections = get_collection_configs()
    indexes = get_payload_indexes()
    
    logger.info("Starting Qdrant collection setup for Enhanced Agentic Workforce...")
    
    success_count = 0
    total_count = len(collections)
    
    # Create collections
    for collection_name, config in collections.items():
        logger.info(f"Creating collection: {collection_name}")
        if manager.create_collection(collection_name, config):
            success_count += 1
            
            # Create payload indexes
            if collection_name in indexes:
                logger.info(f"Creating indexes for {collection_name}")
                for index_config in indexes[collection_name]:
                    manager.create_index(
                        collection_name,
                        index_config["field_name"],
                        index_config["field_type"]
                    )
    
    logger.info(f"Setup complete: {success_count}/{total_count} collections created successfully")
    
    # Verify collections
    logger.info("Verifying created collections...")
    try:
        response = requests.get(f"{QDRANT_URL}/collections")
        if response.status_code == 200:
            collections_info = response.json()
            logger.info(f"Active collections: {len(collections_info['result']['collections'])}")
            for collection in collections_info['result']['collections']:
                logger.info(f"  - {collection['name']}: {collection['status']}")
        else:
            logger.error(f"Failed to verify collections: {response.text}")
    except Exception as e:
        logger.error(f"Error verifying collections: {str(e)}")

if __name__ == "__main__":
    main() 