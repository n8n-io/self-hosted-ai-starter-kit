# ROADMAP

## Done

1. ~~n8n variants for dev, community and enterprise~~
2. ~~AI Runtime + Ollama + Vllm + Minimal CPU Model~~
3. ~~Minimal Agent.md with docs mcp~~
4. ~~Refactor cli with commands and subcommands~~
5. ~~Introduce secrets setup strategy (enterprise license key, postgres password)~~
6. ~~Auto AI_RUNTIME detection for CPU and GPU~~
7. ~~Cleanup repo to prep for migration into public PR~~
8. ~~add BUILD variant~~
9. ~~n8n enterprise variant: multi main~~
10. ~~n8n community variant: webhook processors~~
11. ~~Refactor AGENTS.md, Spec.md and .agents/ skills~~
12. ~~n8n owner account setup via env var~~
13. ~~n8n export/import cli command for the owner's personal space using the n8n api for packages and data tables~~ (community-compatible: flat workflow package into the caller's personal project, data table rows moved by the CLI, `N8N_API_KEY` in the root `.env.secrets`)
14. ~~cli command `n8n export` and `n8n import` with the n8n server cli~~s

## Next

### Add https option with self-signed certificate for *.n8n.localhost

### Add N8N_ENTERPRISE_VARIANT config for `compose/n8n/enterprise` variants

* regular `compose/n8n/docker-compose.enterprise.yml`
* external storage -> `compose/n8n/enterprise/docker-compose.external-storage.yml` -> `compose/storage/garage`
* external secrets -> `compose/n8n/enterprise/docker-compose.external-secrets.yml` -> `compose/storage/vault` (openbao?)
* private npm registry -> `compose/n8n/enterprise/docker-compose.private-npm-registry.yml` -> `compose/storage/verdaccio`