# N8N Credentials Directory

⚠️ **SECURITY WARNING**: This directory should contain your actual n8n credentials for production use.

## Setup Instructions

1. **For Development**: Copy the template files and replace with your actual credentials
2. **For Production**: Use environment variables or AWS SSM Parameter Store

## Credential Templates

### Qdrant API Credential Template
```json
{
  "name": "Qdrant Vector Database",
  "type": "qdrantApi",
  "data": {
    "url": "http://localhost:6333",
    "apiKey": "your-qdrant-api-key-here"
  }
}
```

### Ollama API Credential Template
```json
{
  "name": "Local Ollama Service",
  "type": "ollamaApi", 
  "data": {
    "baseUrl": "http://localhost:11434",
    "apiKey": ""
  }
}
```

## Security Best Practices

- **Never commit actual credentials to version control**
- **Use environment variables for sensitive data**
- **Rotate credentials regularly**
- **Use AWS SSM Parameter Store for production deployments**
- **Enable audit logging for credential access**

## File Naming Convention

- Use descriptive names: `qdrant-production.json`, `ollama-dev.json`
- Follow the pattern: `{service}-{environment}.json`
- Ensure files are added to `.gitignore`