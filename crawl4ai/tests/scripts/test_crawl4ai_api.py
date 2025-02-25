#!/usr/bin/env python3

import requests
import time
import json
import sys
import urllib3
import logging
from typing import Dict, Any, Optional
from urllib.parse import urljoin

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Disable SSL verification warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class Crawl4AiTester:
    def __init__(self, base_url: str = "https://crawl4ai.mulder.local:8443", api_token: Optional[str] = None):
        self.base_url = base_url
        self.headers = {"Authorization": f"Bearer {api_token}"} if api_token else {}
        logger.info(f"Initialized tester with base URL: {self.base_url}")
        
    def _make_request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        """Make HTTP request with error handling"""
        url = urljoin(self.base_url, endpoint)
        try:
            response = requests.request(
                method=method,
                url=url,
                headers=self.headers,
                verify=False,
                **kwargs
            )
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            logger.error(f"Request failed: {str(e)}")
            raise
        
    def test_health(self) -> bool:
        """Test the health endpoint"""
        try:
            logger.info("Testing health endpoint...")
            response = self._make_request("GET", "/health")
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Health check failed: {str(e)}")
            return False

    def test_crawl(self, url: str = "https://example.com") -> Dict[str, Any]:
        """Test a basic crawl operation"""
        try:
            logger.info(f"Starting crawl test for URL: {url}")
            payload = {
                "urls": url,
                "priority": 10,
                "crawler_params": {
                    "headless": True,
                    "page_timeout": 30000,
                    "process_images": True,
                    "extract_embeddings": True,
                    "batch_size": 32
                }
            }
            
            # Submit crawl job
            logger.info("Submitting crawl job...")
            response = self._make_request("POST", "/crawl", json=payload)
            task_id = response.json()["task_id"]
            logger.info(f"Crawl job submitted. Task ID: {task_id}")
            
            # Poll for result
            start_time = time.time()
            while True:
                if time.time() - start_time > 300:  # 5 minute timeout
                    logger.error("Task timed out after 5 minutes")
                    return {"success": False, "error": "Task timeout"}
                
                logger.debug(f"Checking status for task {task_id}...")
                status_response = self._make_request("GET", f"/task/{task_id}")
                status = status_response.json()
                
                if status["status"] == "completed":
                    logger.info(f"Task {task_id} completed successfully")
                    return {"success": True, "result": status}
                elif status["status"] == "failed":
                    logger.error(f"Task {task_id} failed: {status.get('error', 'Unknown error')}")
                    return {"success": False, "error": status.get("error", "Unknown error")}
                
                logger.debug(f"Task {task_id} still processing, waiting...")
                time.sleep(2)
                
        except Exception as e:
            logger.error(f"Crawl test failed: {str(e)}")
            return {"success": False, "error": str(e)}

def main():
    try:
        # Initialize tester
        api_token = None  # Set this if API token is configured
        tester = Crawl4AiTester(api_token=api_token)
        
        # Test health endpoint
        if tester.test_health():
            logger.info("✅ Health check passed")
        else:
            logger.error("❌ Health check failed")
            sys.exit(1)
        
        # Test basic crawl
        logger.info("\nStarting basic crawl test...")
        result = tester.test_crawl()
        if result["success"]:
            logger.info("✅ Crawl test passed")
            logger.info(f"Content length: {len(str(result['result']))}")
        else:
            logger.error(f"❌ Crawl test failed: {result['error']}")
            sys.exit(1)
            
    except KeyboardInterrupt:
        logger.info("\nTest interrupted by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Test failed with unexpected error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main() 