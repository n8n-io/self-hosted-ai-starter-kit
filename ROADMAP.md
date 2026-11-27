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
14. ~~cli command `n8n export` and `n8n import` with the n8n server cli~~ (run in the running container and copied with `docker compose cp`, since docker cannot mount into a running container; every workflow as its draft instead of `--published`; decrypted credentials in the gitignored `export/`)

## Next

### remove DOMAIN option *.n8n.local

### Add https option with self-signed certificate for *.n8n.localhost

### Add N8N_ENTERPRISE_VARIANT config for `compose/n8n/enterprise` variants

* regular `compose/n8n/docker-compose.enterprise.yml`
* external storage -> `compose/n8n/enterprise/docker-compose.external-storage.yml` -> `compose/storage/garage`
* external secrets -> `compose/n8n/enterprise/docker-compose.external-secrets.yml` -> `compose/storage/vault` (openbao?)
* private npm registry -> `compose/n8n/enterprise/docker-compose.private-npm-registry.yml` -> `compose/storage/verdaccio`

### Improve compose linting for production ready compose specs with owasp best practices

1. extract all the lint scripts in "compose/package.json" into "compose/lint.mjs"
2. add [compose-lint](https://github.com/tmatens/compose-lint) executing the docker image on "./compose"
3. update the github action to run the updated lint strategy
4. Do not yet make any changes to compose specs due to compose-lint errors. We'll fix that later.

Evaluate and verify the proposed compose lint improvement strategy and suggest improvements.

### Minimum Viable Collection for Models


### Implement simply Tiltfile verify_before_plan

In the Tiltfile directly (not cli), add a new verify function that only verifies that the root .env exists and prompts to run pnpm run setup. This way we can verify before load plan while running the f