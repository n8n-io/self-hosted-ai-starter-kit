#!/bin/bash

# Test Nginx configuration for Crawl4AI
echo "Testing Nginx configuration..."

# Test configuration syntax
docker exec core-nginx nginx -t

# Test SSL certificate paths
echo -e "\nTesting SSL certificate paths..."
docker exec core-nginx ls -l /etc/nginx/certs/nginx.crt /etc/nginx/certs/nginx.key

# Test log paths
echo -e "\nTesting log file paths..."
docker exec core-nginx ls -l /var/log/nginx/crawl4ai-*.log || echo "Log files will be created when service starts"

# Test proxy connection
echo -e "\nTesting proxy connection to Crawl4AI..."
docker exec core-nginx curl -s -o /dev/null -w "%{http_code}" http://crawl4ai:11235/health || echo "Service not running yet" 