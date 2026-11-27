# assistant

The services the [n8n Assistant](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant) needs beside a model: the n8n sandbox service it runs code in (`sandbox-certs` once for the certificates, `sandbox-api`, and `sandbox-runner-1`, a privileged Docker-in-Docker container for development and testing only) and [SearXNG](https://docs.searxng.org/) for its web search. They start with `N8N_ASSISTANT=true` in the root `.env` and are reachable on `n8n-starter-private` only. Rules: [SPEC.md](../../../SPEC.md#the-n8n-assistant-n8n_assistant). Pinned versions and secrets: [.env.template](./.env.template).

- Repository: <https://github.com/n8n-io/n8n-sandbox-service>
- Docker image (sandbox API): <https://github.com/n8n-io/n8n-sandbox-service/pkgs/container/n8n-sandbox-service-api>
- Docker image (sandbox runner): <https://github.com/n8n-io/n8n-sandbox-service/pkgs/container/n8n-sandbox-service-runner-dind>
- Docker image (sandbox, pulled by the runner): <https://github.com/n8n-io/n8n-sandbox-service/pkgs/container/n8n-sandbox-service-sandbox>
- Documentation: [Set up n8n Assistant](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant) and [Install using Docker Compose](https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose), the stack this directory follows
- API reference: <https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/API.md>
- Releases: <https://github.com/n8n-io/n8n-sandbox-service/releases>

## searxng

- Homepage: <https://docs.searxng.org/>
- Repository: <https://github.com/searxng/searxng>
- Docker image: <https://github.com/searxng/searxng/pkgs/container/searxng>
