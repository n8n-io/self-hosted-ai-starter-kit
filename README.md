> [📣 Read the announcement]()
>
> 💡 Help and Support: [💬 Discord]() [📖 Community Forum]()

**Self-hosted AI Starter Kit** is an open, docker compose template that
quickly bootstraps a fully featured Local AI and Low Code development
environment.

Curated by <https://github.com/n8n-io>, it combines the self-hosted n8n
platform with a curated list of compatible AI products and components that
lets you build production-level AI workflows in minutes.

### What’s included

✅ [**Self-hosted n8n**](https://n8n.io/) - Low-code platform with over 400 integrations and advanced AI components

✅ [**Ollama**](https://ollama.com/) - Cross-platform LLM platform to install and run the latest local LLMs

✅ [**Qdrant**](https://qdrant.tech/) - Open-source, high performance vector store with an comprehensive API

✅ [**PostgreSQL**](https://www.postgresql.org/) -  Workhorse of the Data Engineering world, handles large amounts of data safely.

### What you can build

⭐️ AI Agents which can schedule appointments

⭐️ Summarise company PDFs without leaking data

⭐️ Smarter slack bots for company comms and IT-ops

⭐️ Analyse financial documents privately and for little cost

## Installation

### For Nvidia GPU users

```
git clone https://github.com/n8n-io/self-hosted-ai-demo.git
cd self-hosted-ai-demo
docker compose --profile gpu-nvidia up
```

### For everyone else

```
git clone https://github.com/n8n-io/self-hosted-ai-demo.git
cd self-hosted-ai-demo
docker compose --profile cpu up
```

If you run on a Mac with an M1 or newer processor, you can also run Ollama on
your host machine to be able to use faster inference on the GPU.
Unfortunately, you can't expose the GPU to docker instances. Refer to the
[Ollama homepage](https://ollama.com/) for installation instructions and use
`http://host.docker.internal:11434/` as the Ollama host in your credentials.


## ⚡️ QuickStart and usage

The Self-hosted AI Starter Kit is a docker compose file pre-configured with
network and disk so there isn’t much else you need to install.

1. Open <http://localhost:5678/> in your browser to set up n8n. You’ll only
   have to do this once.
2. Open the included workflow:
   <http://localhost:5678/workflow/srOnR8PAY3u4RSwb>
3. Select **Test workflow** to start running the workflow.
4. If this is the first time you’re running the workflow, you may need to wait
   until Ollama finishes downloading Llama3.1. You can inspect the docker
   console logs.

To open n8n at any time, visit <http://localhost:5678/> in your browser.

With your n8n instance, you’ll have access to over 400 integrations and a
suite of basic and advanced AI nodes such as
[AI Agent](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.agent/),
[Text classifier](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.text-classifier/),
and [Information Extractor](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.information-extractor/)
nodes. To keep everything local, just remember to use the Ollama node for your
language model and Qdrant as your vector store.

## Upgrading

### For Nvidia GPU users

```
docker compose --profile gpu-nvidia pull
docker compose create && docker compose up
```

### For everyone else

```
docker compose --profile cpu pull
docker compose create && docker compose up
```

## 👓 Recommended Reading

n8n is full of useful content for getting started quickly with its AI concepts
and nodes. If you can’t find an answer to your question, remember to visit the
community forum and pop a message in the Discord!

- [AI agents for developers: from theory to practice with n8n](https://blog.n8n.io/ai-agents/)
- [Tutorial: Build an AI workflow in n8n](https://docs.n8n.io/advanced-ai/intro-tutorial/)
- [Langchain Concepts in n8n](https://docs.n8n.io/advanced-ai/langchain/langchain-n8n/)
- [Demonstration of key differences between agents and chains](https://docs.n8n.io/advanced-ai/examples/agent-chain-comparison/)
- [What are vector databases?](https://docs.n8n.io/advanced-ai/examples/understand-vector-databases/)

## 🎥 Video walkthrough

- [Installing and using Local AI for n8n](https://www.youtube.com/watch?v=xz_X2N-hPg0)

## 🛍️ More AI Templates

For more AI workflow ideas, visit the [**official n8n AI template
gallery**](https://n8n.io/workflows/?categories=AI). From each workflow,
select the **Use workflow** button to automatically import the workflow into
your local n8n instance.

### Learn AI Key Concepts

- [AI Agent Chat](https://n8n.io/workflows/1954-ai-agent-chat/)
- [AI chat with any data source (using the n8n workflow too)](https://n8n.io/workflows/2026-ai-chat-with-any-data-source-using-the-n8n-workflow-tool/)
- [Chat with OpenAI Assistant (by adding a memory)](https://n8n.io/workflows/2098-chat-with-openai-assistant-by-adding-a-memory/)
- [Use an open-source LLM (via HuggingFace)](https://n8n.io/workflows/1980-use-an-open-source-llm-via-huggingface/)
- [Chat with PDF docs using AI (quoting sources)](https://n8n.io/workflows/2165-chat-with-pdf-docs-using-ai-quoting-sources/)
- [AI agent that can scrape webpages](https://n8n.io/workflows/2006-ai-agent-that-can-scrape-webpages/)

### Local AI templates

- [Tax Code Assistant](https://n8n.io/workflows/2341-build-a-tax-code-assistant-with-qdrant-mistralai-and-openai/)
- [Breakdown Documents into Study Notes with MistralAI and Qdrant](https://n8n.io/workflows/2339-breakdown-documents-into-study-notes-using-templating-mistralai-and-qdrant/)
- [Financial Documents Assistant using Qdrant and](https://n8n.io/workflows/2335-build-a-financial-documents-assistant-using-qdrant-and-mistralai/) [Mistral.ai](http://mistral.ai/)
- [Recipe Recommendations with Qdrant and Mistral](https://n8n.io/workflows/2333-recipe-recommendations-with-qdrant-and-mistral/)

## Tips & Tricks

### Accessing Local Files

The Self-hosted AI Starter Kit will create a shared folder (by default, located in
the same directory) which is mounted to the n8n container and allows n8n to
access files on disk. This folder within the n8n container is located at
`/data/shared` - this is the path you’ll need to use in nodes that interact
with the local filesystem.

**Nodes that interact with the local filesystem**

- [Read/Write Files from Disk](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.filesreadwrite/)
- [Local File Trigger](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.localfiletrigger/)
- [Execute Command](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.executecommand/)
