# AI Starter Kit Deployment Guide

This repository contains an AI Starter Kit that can be deployed on AWS EC2 instances with either CPU (for testing) or GPU (for production) configurations.

## Architecture

- **Services**: n8n, Ollama, PostgreSQL, Qdrant
- **Persistent Storage**: AWS EFS for all data
- **Deployment Types**: CPU for testing, GPU for production
- **Access**: HTTPS with self-signed certificates

## Deployment Instructions

### Prerequisites

1. Set up AWS SSM Parameters:
   - `/aibuildkit/POSTGRES_PASSWORD` - PostgreSQL root password
   - `/aibuildkit/N8N_ENCRYPTION_KEY` - n8n encryption key
   - `/aibuildkit/N8N_USER_MANAGEMENT_JWT_SECRET` - n8n JWT secret

2. Create an EFS file system
   - Note the file system ID for configuration

### Launch Templates

#### Testing Environment (CPU)

1. Create a launch template with:
   - Amazon Linux 2 AMI
   - Instance type: t3.medium or similar CPU-only instance
   - User data: Use the cloud-init.yml file from this repository
   - IAM role with permissions to:
     - Access EFS
     - Read SSM parameters
   - Security groups allowing:
     - SSH (port 22)
     - HTTPS (port 443)
     - n8n (port 5678)
     - NFS (for EFS)

2. Launch an instance from the template

#### Production Environment (GPU)

1. Create a launch template with:
   - Amazon Linux 2 AMI with NVIDIA drivers
   - Instance type: g4dn.xlarge or similar GPU instance
   - User data: Use the cloud-init.yml file from this repository
   - Request as a Spot instance for cost savings
   - IAM role with permissions to:
     - Access EFS
     - Read SSM parameters
   - Security groups allowing:
     - SSH (port 22)
     - HTTPS (port 443)
     - n8n (port 5678)
     - NFS (for EFS)

2. Launch a Spot instance from the template

### Accessing the Services

Once the instance is running:
- n8n: https://[instance-public-ip]:5678
- Ollama: Available internally on port 11434

<<<<<<< HEAD
## Troubleshooting
=======
```bash
git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git
cd self-hosted-ai-starter-kit
cp .env.example .env # you should update secrets and passwords inside
```
>>>>>>> 06319a57af662810230c1a63175baaf312b427a9

### Logs
- sudo tail -f /var/log/cloud-init-output.log

### EFS Mounting Issues
- Check that the security groups allow NFS traffic (port 2049)
- Verify the instance has permissions to mount the EFS
- Check CloudWatch logs for mount errors

<<<<<<< HEAD
### Docker Service Issues
- SSH into the instance and check Docker logs:
  ```
  docker ps
  docker logs [container_name]
  ```
=======
```bash
git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git
cd self-hosted-ai-starter-kit
cp .env.example .env # you should update secrets and passwords inside
docker compose --profile gpu-nvidia up
```
>>>>>>> 06319a57af662810230c1a63175baaf312b427a9

### Spot Instance Termination
- The system includes automatic handling of spot instance terminations
- Data is persisted on EFS, so no data loss occurs

## Customization

<<<<<<< HEAD
To customize the deployment:
1. Edit `.env` for environment variable changes
2. Edit `docker-compose.yml` for service configuration changes
3. Edit `cloud-init.yml` for instance setup changes
=======
```bash
git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git
cd self-hosted-ai-starter-kit
cp .env.example .env # you should update secrets and passwords inside
docker compose --profile gpu-amd up
```

#### For Mac / Apple Silicon users

If you’re using a Mac with an M1 or newer processor, you can't expose your GPU
to the Docker instance, unfortunately. There are two options in this case:

1. Run the starter kit fully on CPU, like in the section "For everyone else"
   below
2. Run Ollama on your Mac for faster inference, and connect to that from the
   n8n instance

If you want to run Ollama on your mac, check the
[Ollama homepage](https://ollama.com/)
for installation instructions, and run the starter kit as follows:

```bash
git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git
cd self-hosted-ai-starter-kit
cp .env.example .env # you should update secrets and passwords inside
docker compose up
```

##### For Mac users running OLLAMA locally

If you're running OLLAMA locally on your Mac (not in Docker), you need to modify the OLLAMA_HOST environment variable

1. Set OLLAMA_HOST to `host.docker.internal:11434` in your .env file. 
2. Additionally, after you see "Editor is now accessible via: <http://localhost:5678/>":

    1. Head to <http://localhost:5678/home/credentials>
    2. Click on "Local Ollama service"
    3. Change the base URL to "http://host.docker.internal:11434/"

#### For everyone else

```bash
git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git
cd self-hosted-ai-starter-kit
cp .env.example .env # you should update secrets and passwords inside
docker compose --profile cpu up
```

## ⚡️ Quick start and usage

The core of the Self-hosted AI Starter Kit is a Docker Compose file, pre-configured with network and storage settings, minimizing the need for additional installations.
After completing the installation steps above, simply follow the steps below to get started.

1. Open <http://localhost:5678/> in your browser to set up n8n. You’ll only
   have to do this once.
2. Open the included workflow:
   <http://localhost:5678/workflow/srOnR8PAY3u4RSwb>
3. Click the **Chat** button at the bottom of the canvas, to start running the workflow.
4. If this is the first time you’re running the workflow, you may need to wait
   until Ollama finishes downloading Llama3.2. You can inspect the docker
   console logs to check on the progress.

To open n8n at any time, visit <http://localhost:5678/> in your browser.

With your n8n instance, you’ll have access to over 400 integrations and a
suite of basic and advanced AI nodes such as
[AI Agent](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.agent/),
[Text classifier](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.text-classifier/),
and [Information Extractor](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.information-extractor/)
nodes. To keep everything local, just remember to use the Ollama node for your
language model and Qdrant as your vector store.

> [!NOTE]
> This starter kit is designed to help you get started with self-hosted AI
> workflows. While it’s not fully optimized for production environments, it
> combines robust components that work well together for proof-of-concept
> projects. You can customize it to meet your specific needs

## Upgrading

* ### For Nvidia GPU setups:

```bash
docker compose --profile gpu-nvidia pull
docker compose create && docker compose --profile gpu-nvidia up
```

* ### For Mac / Apple Silicon users

```bash
docker compose pull
docker compose create && docker compose up
```

* ### For Non-GPU setups:

```bash
docker compose --profile cpu pull
docker compose create && docker compose --profile cpu up
```

## 👓 Recommended reading

n8n is full of useful content for getting started quickly with its AI concepts
and nodes. If you run into an issue, go to [support](#support).

- [AI agents for developers: from theory to practice with n8n](https://blog.n8n.io/ai-agents/)
- [Tutorial: Build an AI workflow in n8n](https://docs.n8n.io/advanced-ai/intro-tutorial/)
- [Langchain Concepts in n8n](https://docs.n8n.io/advanced-ai/langchain/langchain-n8n/)
- [Demonstration of key differences between agents and chains](https://docs.n8n.io/advanced-ai/examples/agent-chain-comparison/)
- [What are vector databases?](https://docs.n8n.io/advanced-ai/examples/understand-vector-databases/)

## 🎥 Video walkthrough

- [Installing and using Local AI for n8n](https://www.youtube.com/watch?v=xz_X2N-hPg0)

## 🛍️ More AI templates

For more AI workflow ideas, visit the [**official n8n AI template
gallery**](https://n8n.io/workflows/categories/ai/). From each workflow,
select the **Use workflow** button to automatically import the workflow into
your local n8n instance.

### Learn AI key concepts

- [AI Agent Chat](https://n8n.io/workflows/1954-ai-agent-chat/)
- [AI chat with any data source (using the n8n workflow too)](https://n8n.io/workflows/2026-ai-chat-with-any-data-source-using-the-n8n-workflow-tool/)
- [Chat with OpenAI Assistant (by adding a memory)](https://n8n.io/workflows/2098-chat-with-openai-assistant-by-adding-a-memory/)
- [Use an open-source LLM (via Hugging Face)](https://n8n.io/workflows/1980-use-an-open-source-llm-via-huggingface/)
- [Chat with PDF docs using AI (quoting sources)](https://n8n.io/workflows/2165-chat-with-pdf-docs-using-ai-quoting-sources/)
- [AI agent that can scrape webpages](https://n8n.io/workflows/2006-ai-agent-that-can-scrape-webpages/)

### Local AI templates

- [Tax Code Assistant](https://n8n.io/workflows/2341-build-a-tax-code-assistant-with-qdrant-mistralai-and-openai/)
- [Breakdown Documents into Study Notes with MistralAI and Qdrant](https://n8n.io/workflows/2339-breakdown-documents-into-study-notes-using-templating-mistralai-and-qdrant/)
- [Financial Documents Assistant using Qdrant and](https://n8n.io/workflows/2335-build-a-financial-documents-assistant-using-qdrant-and-mistralai/) [Mistral.ai](http://mistral.ai/)
- [Recipe Recommendations with Qdrant and Mistral](https://n8n.io/workflows/2333-recipe-recommendations-with-qdrant-and-mistral/)

## Tips & tricks

### Accessing local files

The self-hosted AI starter kit will create a shared folder (by default,
located in the same directory) which is mounted to the n8n container and
allows n8n to access files on disk. This folder within the n8n container is
located at `/data/shared` -- this is the path you’ll need to use in nodes that
interact with the local filesystem.

**Nodes that interact with the local filesystem**

- [Read/Write Files from Disk](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.filesreadwrite/)
- [Local File Trigger](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.localfiletrigger/)
- [Execute Command](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.executecommand/)

## 📜 License

This project is licensed under the Apache License 2.0 - see the
[LICENSE](LICENSE) file for details.

## 💬 Support

Join the conversation in the [n8n Forum](https://community.n8n.io/), where you
can:

- **Share Your Work**: Show off what you’ve built with n8n and inspire others
  in the community.
- **Ask Questions**: Whether you’re just getting started or you’re a seasoned
  pro, the community and our team are ready to support with any challenges.
- **Propose Ideas**: Have an idea for a feature or improvement? Let us know!
  We’re always eager to hear what you’d like to see next.
>>>>>>> 06319a57af662810230c1a63175baaf312b427a9
