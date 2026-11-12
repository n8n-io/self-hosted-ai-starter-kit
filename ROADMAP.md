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

## Next

### n8n assistant support

* Add N8N_ASSISTANT config
* Add `compose/n8n/assistant`
* Add command `assistant` to manage setting up the assistant.

#### Resources

* [Set up n8n Assistant](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant)
* [One-line setup](https://docs.n8n.io/deploy/host-n8n/install-options/one-line-setup)
* [Install using Docker Compose](https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose)

### CLI import and export for agents and worklfows

### n8n implement file logging best-practice

### Add N8N_ENTERPRISE_VARIANT config for `compose/n8n/enterprise` variants

* regular `compose/n8n/docker-compose.enterprise.yml`
* external storage -> `compose/n8n/enterprise/docker-compose.external-storage.yml` -> `compose/storage/garage`
* external secrets -> `compose/n8n/enterprise/docker-compose.external-secrets.yml` -> `compose/storage/vault` (openbao?)
* private npm registry -> `compose/n8n/enterprise/docker-compose.private-npm-registry.yml` -> `compose/storage/verdaccio`

### Implement simply Tilfile verify_before_plan

In the Tiltfile directly (not cli), add a new verify function that only verifies that the root .env exists and prompts to run pnpm run setup. This way we can verify before loadplan while running the f

### Minimum Viable Collection for Models

### Add https option with self-signed certificate for *.n8n.localhost

## Refactor AGENTS.md

```txt
# Audit, Optimize, and Migrate Agent Instructions to `.agents/`

## Context
This repository currently contains `SPEC.md`, a root `AGENTS.md`, and an initial skill setup under `.claude/skills/develop/` (with `resources/compose-catalogue.md` and `resources/n8n-starter-cli.md`). The current structure was created ad-hoc and needs a critical review to ensure it aligns with modern multi-agent standards, minimizes context window bloat, and avoids redundant instructions across `SPEC.md`, `AGENTS.md`, and skills.

## Objectives
1. **Audit & Evaluate Current Setup**
   - Inspect `SPEC.md`, `AGENTS.md`, and everything under `.claude/**`.
   - Evaluate whether the current split between `AGENTS.md` and `.claude/skills/develop` makes sense, where instructions are duplicated, and where token consumption can be reduced.
   - Define a clear separation of concerns: keep `AGENTS.md` lean and focused on always-on repository invariants (build/test commands, architecture rules, conventions—similar in conciseness to [temporalio/sdk-java](https://raw.githubusercontent.com/temporalio/sdk-java/refs/heads/main/AGENTS.md) and [apache/airflow](https://raw.githubusercontent.com/apache/airflow/refs/heads/main/AGENTS.md)), while offloading task-specific workflows and heavy reference material into progressive-disclosure skills under `.agents/skills/`.

2. **Align with Agent Skills Standards**
   - Structure all skills and skill descriptions according to:
     - Best practices: https://agentskills.io/skill-creation/best-practices
     - Description optimization (trigger precision & token efficiency): https://agentskills.io/skill-creation/optimizing-descriptions
   - Optimize for multi-agent compatibility and minimal baseline context overhead.

3. **Refactor & Migrate to `.agents/`**
   - Create a backup of the current `AGENTS.md` (e.g., `AGENTS.md.bak`) before making edits.
   - Keep `.claude/**` completely intact (treat as read-only source material; do not modify or delete it).
   - Migrate and refactor the optimized skills and resources into `.agents/skills/`.
   - Freely split, merge, or restructure existing skill files (`develop`, `compose-catalogue.md`, `n8n-starter-cli.md`) while preserving all learned rules, domain constraints, and strategies.

4. **Evaluate & Selectively Incorporate Candidate Skills**
   Review the previously proposed skill backlog below. Decide which items to adopt (fully or partially), merge into existing skills, or defer—keeping in mind that **executable scripts and MCP/hook configurations are out of scope for now**, so any adopted skill must be purely instructional (Markdown + reference docs):
   - **`validate`**: Single verification workflow covering every gate (`pnpm run lint`, `docker compose … config` per changed compose file, variant and engine/profile configs, `tilt alpha tiltfile-result -v`, CLI typecheck/build/test, `verify --log-level error`) with verbatim output reporting to prevent skipped gates. *(Note: defer `.claude/settings.json` `PostToolUse` dclint hook setup for now.)*
   - **`troubleshoot`**: Operational runbook for the running stack—reusing an existing Tilt session on port `10350` via `tilt trigger` (never `tilt down`), addressing containers by name and isolating tests with `-p <name>-test`, handling task-runner launcher stderr relayed as `ERROR` and starting a runner manually, and working around the vLLM CPU `v0.32.0` crash (pin `v0.31.0`, set absolute KV cache via `VLLM_CPU_KVCACHE_SPACE` instead of memory share).
   - **`n8n-upgrade`**: Workflow for bumping `N8N_VERSION` in `compose/n8n/.env.template` (n8n and runner images)—checking release notes via `n8n-docs`, auditing breaking changes and renamed/removed env vars against `compose/n8n/*.yml`, and validating variant configs.
   - **n8n MCP server integration**: Enabling MCP in the `dev` variant (`N8N_MCP_MANAGED_BY_ENV=true`, `N8N_MCP_ACCESS_ENABLED=true` in `compose/n8n/.env.template`), registering `https://<DOMAIN>/mcp-server/http` in `.mcp.json`, and passing `MCP-Protocol-Version`, `Mcp-Method`, and `Mcp-Name` headers through Traefik for end-to-end workflow verification. *(Evaluate whether this belongs in documentation/specs rather than `.agents/skills/`.)*
   - **`n8n-cli` skill**: Driving the public API with `npx @n8n/cli` against the dev instance (`N8N_URL`, `N8N_API_KEY` from `compose/n8n/.env`), blocked on workflow import/export TODO item 9.
   - **`tilt` reference skill**: Concise reference for the Tiltfile API subset used in this repo (`docker_compose` with inline overrides, `dc_resource`, `local_resource`, `config`, `warn`, `dotenv`) with links to `docs.tilt.dev` (or noting the Context7 MCP library ID).

## Strict Constraints
- **Do NOT** implement scripts inside skills (`https://agentskills.io/skill-creation/using-scripts` is deferred to a later phase).
- **Do NOT** implement skill evaluations/evals yet (deferred to a later phase).
- **Do NOT** modify or delete `.claude/**`.

## Expected Output & Execution Order
1. **Audit Report**: Briefly present your evaluation of `SPEC.md`, `AGENTS.md`, and `.claude/skills/develop`, highlighting redundancies, context-window bottlenecks, and your proposed target architecture for `AGENTS.md` + `.agents/skills/` (including which candidate skills you selected or deferred and why).
2. **Backup & Migration**: Create `AGENTS.md.bak`, write the streamlined `AGENTS.md`, and generate the refactored `.agents/skills/` directory structure.
```
