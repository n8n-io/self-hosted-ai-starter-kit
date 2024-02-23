# n8n Demo setup

This repo helps quickly bootstrap an n8n demo environment using docker-compose.

### Requirements
- [Docker compose](https://docs.docker.com/compose/)
- **Optionally** an Nvidia GPU for faster inference on Ollama and Infinity

### Setup
- Clone this repo
- **Optionally** edit the credentials in the `.env` file
- If you have an Nvidia GPU, run `docker compose --profile gpu-nvidia up`
- Otherwise to run inference services on your CPU, run `docker compose --profile cpu up`
- Wait a couple of minutes for all the containers to become healthy.

### Included service endpoints
- [n8n](http://localhost:5678/)
- [Ollama](http://localhost:11434/)
- [Qdrant](http://localhost:6333/dashboard)
- [Infinity](http://localhost:7997/docs)

### Updating
- Run `docker compose pull` to fetch all the latest images
- Run `docker compose create && docker compose up -d` to update and restart all the containers
