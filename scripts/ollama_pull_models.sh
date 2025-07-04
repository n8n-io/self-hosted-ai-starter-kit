#!/bin/sh

# Wait a few seconds to ensure the Ollama service is up and ready
sleep 3

# Pull the LLaMA 3.2 model
ollama pull llama3.2

# Pull the Qwen 2.5 model (7B variant, quantized to Q4_K_M)
ollama pull qwen2.5:7b-instruct-q4_K_M

# Pull the Nomic embed model for text embeddings
ollama pull nomic-embed-text

# Pull the Mistral model (latest version)
ollama pull mistral:latest

# Pull the DeepSeek R1 model (latest version)
ollama pull deepseek-r1:latest

# Pull the Gemma 3 model (latest version)
ollama pull gemma3:latest