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

## Next

### remove DOMAIN option *.n8n.local

### Add https option with self-signed certificate for *.n8n.localhost

### Implement n8n project export/import cli commands using the n8n api

* cli command "n8n xxx" always pre checks if an n8n api key was set before executing commands
* if no api key is set, the cli prompts to enter an n8n api key with a required set of scopes
* where to store the api key once entered?
* cli command "n8n export" renders select project list and exports selected into ./projects/{PROJECT NAME}/[credential|workflow].json files
* cli command "n8n export" also exports any credential dependencies even if they are coming from another project
* cli command "n8n import" renders a select list with available projects in "./projects" and imports selected

### Add N8N_ENTERPRISE_VARIANT config for `compose/n8n/enterprise` variants

* regular `compose/n8n/docker-compose.enterprise.yml`
* external storage -> `compose/n8n/enterprise/docker-compose.external-storage.yml` -> `compose/storage/garage`
* external secrets -> `compose/n8n/enterprise/docker-compose.external-secrets.yml` -> `compose/storage/vault` (openbao?)
* private npm registry -> `compose/n8n/enterprise/docker-compose.private-npm-registry.yml` -> `compose/storage/verdaccio`

### Implement simply Tiltfile verify_before_plan

In the Tiltfile directly (not cli), add a new verify function that only verifies that the root .env exists and prompts to run pnpm run setup. This way we can verify before load plan while running the f

### Minimum Viable Collection for Models


