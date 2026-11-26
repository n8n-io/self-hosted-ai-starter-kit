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

### Implement n8n import/export

### Local network access with \*.n8n.local

* `DOMAIN=n8n.local` only works with hosts file entries today (see Routing in SPEC.md). To serve the local network it needs its hostnames published (an mDNS publisher on the host or a hosts file helper), traefik listening beyond `127.0.0.1` and the https option below.


### CLI import and export for agents and worklfows

### Add N8N_ENTERPRISE_VARIANT config for `compose/n8n/enterprise` variants

* regular `compose/n8n/docker-compose.enterprise.yml`
* external storage -> `compose/n8n/enterprise/docker-compose.external-storage.yml` -> `compose/storage/garage`
* external secrets -> `compose/n8n/enterprise/docker-compose.external-secrets.yml` -> `compose/storage/vault` (openbao?)
* private npm registry -> `compose/n8n/enterprise/docker-compose.private-npm-registry.yml` -> `compose/storage/verdaccio`

### Implement simply Tiltfile verify_before_plan

In the Tiltfile directly (not cli), add a new verify function that only verifies that the root .env exists and prompts to run pnpm run setup. This way we can verify before load plan while running the f

### Minimum Viable Collection for Models

### Add https option with self-signed certificate for *.n8n.localhost and *.n8n.local
