---
name: develop
description: Comprehensive development guide for extending or modifying the self-hosted-ai-starter-kit (Docker Compose catalogue, n8n configurations, and the n8n-starter CLI). Use before any non-trivial change to compose/, the Tiltfile, compose/models/models.json or packages/cli, such as adding a service, n8n variant, model, runtime, engine, env key or CLI command.
---

# develop

Development workflow for this repository. [SPEC.md](../../../SPEC.md) at the repo root is the single source of truth; the resource files below restate its rules operationally and cite it. When they disagree, SPEC.md wins and the resource file gets fixed.

## Resource loading rule

Before modifying anything, read the resource file the router names for the task, then the SPEC.md section it cites. Load only what the task needs:

| Resource | Covers |
| --- | --- |
| [resources/compose-catalogue.md](resources/compose-catalogue.md) | `compose/`: service directory contract, naming, spec rules, ports, environment variables, networks and routing, the n8n variant cascade, model engines and the catalogue, how the Tiltfile consumes it all, dclint gates and anti-patterns, known deviations, recipes |
| [resources/n8n-starter-cli.md](resources/n8n-starter-cli.md) | `packages/cli`: stack and build, file map, command lifecycle, logger and options, `.env` handling, prompts, schemas, tests, gotchas, scaffolding leftovers, recipes |
| [../n8n-docs/SKILL.md](../n8n-docs/SKILL.md) | What n8n itself does: every `N8N_*`, `DB_*`, `QUEUE_*`, `EXECUTIONS_*` setting, edition-gated features, the public API, the n8n CLI and the instance MCP server, looked up through the `n8n-docs` MCP server and cited, never recalled from memory |

## Workflow

1. **Classify** the task with the router table and read the resource section(s) it names.
2. **Locate the source and its mirrors** before editing (list below). A value list, id rule or network name that lives in several files changes in all of them in one go.
3. **Make the smallest change** that satisfies the request. No unprompted refactoring, no cleaning up the known deviations listed in the compose resource.
4. **Validate** with the commands of the router row. Compose edits always end with `pnpm run lint`; CLI edits always end with typecheck, `pnpm -r run build` and `pnpm -r run test`, then exercise the built command.
5. **Update the documentation of record** in the same change when a rule, a default or a mirrored value changed: `SPEC.md`, the `.env.template` comments, the Tiltfile comments, `packages/cli/README.md` for CLI commands, `README.md` when the user-facing workflow changed.
6. **Report** what changed and which validation commands ran, with their result. Do not commit; the maintainer commits.

## Mirrors that must stay in sync

| Source | Mirrors |
| --- | --- |
| `AI_RUNTIMES`, `AI_ENGINES`, `N8N_VARIANTS` in `packages/cli/src/schemas/config.ts` (first entry = default) and `AI_GATEWAYS` (empty = default) | `N8N_VARIANT_CASCADE` in `packages/cli/src/commands/tilt.ts`; `Options:` comments and defaults in `.env.template`; the `runtimes` enum in `compose/models/models.schema.json`; one `<engine>-<runtime>` profile service per runtime in `compose/models/<engine>/docker-compose.yml`; for a gateway its directory `compose/models/<gateway>/`, `GATEWAYS` in `packages/cli/src/utils/models.ts` and `gatewayProjects()` in `tilt.ts`; the Configuration block of `SPEC.md` |
| `id` of every entry in `compose/models/models.json` (a DNS label of at most 58 characters, the same for the same model in every engine; `MODEL_ID_PATTERN` and `MODEL_ID_MAX_LENGTH` in `packages/cli/src/schemas/models.ts`) | the `id` pattern and `maxLength` in `compose/models/models.schema.json`; the `AI_MODELS` regex in `src/schemas/config.ts`; `vllmContainerName()` and `vllmEndpoint()` in `packages/cli/src/utils/models.ts` (`vllm-<id>`); `container_name: vllm-${VLLM_MODEL_ID:-model}` in the vllm compose file; nothing normalises an id |
| `compose/models/models.json` | `compose/models/models.schema.json`; `packages/cli/src/schemas/models.ts`; the entries table in `SPEC.md`; `models read` prints it validated, one record per engine and model |
| `tiltResources()` in `packages/cli/src/commands/tilt.ts` (every compose project, its resources, deps, links, `auto_init`, what each variant enables; schema in `src/schemas/tilt.ts`) | the `compose/` directories; the resource lists in the Tilt section of `SPEC.md`; `tests/tilt.test.ts`. The `Tiltfile` only loops over the JSON of `tilt resources` |
| `REQUIREMENTS` in `packages/cli/src/utils/requirements.ts` (minimum node, docker daemon and docker compose versions, checked by `verify`) | the Prerequisites of `README.md`; the Requirements line of `SPEC.md`; `engines.node` of the root `package.json` (`tests/requirements.test.ts` checks it); the Tilt minimum stays in `version_settings()` of the `Tiltfile` |
| `DOCKER_NETWORKS` in `packages/cli/src/commands/setup.ts` | `networks: … external: true` in every compose file; the network table in `SPEC.md` |
| `COMMAND_HELP` in `packages/cli/src/help.ts` (commands, their sub-commands, usages and descriptions; the dispatcher of `src/index.ts` derives its checks from it) | the command table in `packages/cli/README.md`; the CLI table in `SPEC.md`; root `package.json` scripts (`setup`, `verify`, `config`, `models`, `secrets`, `reset`); the palette in `AGENTS.md`; the `*_SUBCOMMANDS` constants of the command modules (`tests/help.test.ts` checks them) |
| `CONFIG_KEYS` and `CONFIG_KEY_DESCRIPTIONS` in `packages/cli/src/commands/config.ts` | the keys and the comment line above each key in the root `.env.template` (a test checks both; `AI_MODELS` is a config key that `config` hands to `models select`); the `KEY:` line of `HELP` |
| `.env.template` files | the `${VAR:?}` and `${VAR:-default}` usages of the compose file next to them |
| `.env.secrets.json` manifests | the empty secret keys of the `.env.template` beside them (an optional `prompt` key commented out) and the `${KEY:?}` (`${KEY:-}`) of the compose file; `compose/.env.secrets.schema.json` and `src/schemas/secrets.ts` carry the same patterns and enums (`tests/secrets.test.ts` checks all of it) |

## Router

| Task | Read | Primary files | Validate |
| --- | --- | --- | --- |
| Add or change a service under `compose/` | compose-catalogue: Service directory contract, Compose spec rules, Ports, Networks and routing, Recipes › Add a service | `compose/<group>/<service>/docker-compose.yml`, its `.env.template`, `tiltResources()` in `packages/cli/src/commands/tilt.ts` (the project, its resources, `enabled`, `auto_init`) and `tests/tilt.test.ts`, `SPEC.md` tree and network table | `pnpm run lint`; `docker compose -f <file> config`; `pnpm run setup && pnpm run verify`; CLI typecheck + build + test; `tilt alpha tiltfile-result -v` |
| n8n variant cascade | compose-catalogue: n8n variant cascade, Recipes › Add an n8n variant; n8n-docs skill for every n8n setting and edition-gated feature | `compose/n8n/docker-compose*.yml`, `compose/n8n/.env.template`, `N8N_VARIANT_CASCADE` and the queue/enterprise flags in `packages/cli/src/commands/tilt.ts`, `packages/cli/src/schemas/config.ts` | `pnpm run lint`; `(cd compose/n8n && docker compose -f docker-compose.<variant>.yml config)`; CLI typecheck + build + test when `N8N_VARIANTS` changed; every n8n setting confirmed in the docs and cited |
| Catalogue entry (add, remove, `id`, `args`, `memory`, `note`, `runtimes`) | compose-catalogue: Model engines and the catalogue, Recipes › Add a model | `compose/models/models.json`, `SPEC.md` entries table; the schema files only when the entry shape changes | `pnpm -r run test`; `pnpm run models select`; `tilt alpha tiltfile-result -v` |
| Engine compose (flags, versions, runtime services) | compose-catalogue: Model engines and the catalogue, How Tilt consumes the catalogue | `compose/models/<engine>/docker-compose.yml`, its `.env.template`, `SPEC.md` | `pnpm run lint`; `(cd compose/models/<engine> && docker compose --profile <runtime> config)` |
| New `AI_RUNTIME`, `AI_ENGINE`, `AI_GATEWAY` or `N8N_VARIANT` value | the mirrors above; compose-catalogue: Recipes › Add a runtime or engine, Add a gateway | `packages/cli/src/schemas/config.ts`, `packages/cli/src/commands/tilt.ts` (cascade, model projects), root `.env.template`, `models.schema.json`, engine compose services, `SPEC.md` | typecheck + build + test; `pnpm run lint`; `tilt alpha tiltfile-result -v`; `pnpm run config` |
| Root or per-service `.env` keys, secrets | compose-catalogue: Environment variables, Service directory contract (`.env.secrets.json`); n8n-starter-cli: State and `.env` handling, the `secrets` rows of the lifecycle table; n8n-docs skill for keys under `compose/n8n/` | `.env.template` files, the `.env.secrets.json` beside them for a secret, the compose `${VAR}` usages, `config.ts` and `schemas/config.ts` for root keys, `SPEC.md` (Secrets) | `pnpm run lint`; on a scratch copy `reset`, `setup`, `verify`; CLI tests for root keys; every n8n variable confirmed in the docs and cited |
| Tilt orchestration (deps, labels, links, `auto_init`, enabled resources) | compose-catalogue: How Tilt consumes the catalogue; n8n-starter-cli: `tilt resources` | `packages/cli/src/commands/tilt.ts` and `tests/tilt.test.ts` (the plan), `src/schemas/tilt.ts` (its shape), the `Tiltfile` only for how the plan is applied, the Tilt section of `SPEC.md` | CLI typecheck + build + test; `node packages/cli/dist/index.mjs tilt resources --log-level error`; `tilt alpha tiltfile-result -v`; `pnpm run dev` only when the user runs it or asks for it |
| Traefik, routing, HTTPS | compose-catalogue: Networks and routing | `compose/proxy/traefik/**`, the Routing section of `SPEC.md` | `pnpm run lint`; `docker compose -f compose/proxy/traefik/docker-compose.yml config` |
| CLI command, option, schema or util | n8n-starter-cli (all sections), Recipes | `packages/cli/src/**`, `packages/cli/tests/**`, `packages/cli/README.md`, the CLI table of `SPEC.md`, root `package.json` | `pnpm --filter n8n-starter-cli run typecheck && pnpm -r run build && pnpm -r run test`; `node packages/cli/dist/index.mjs --help` |
| Documentation (`SPEC.md`, `README.md`, `AGENTS.md`, this skill) | the file in question | that file | links resolve from the referencing file; commands exist in `package.json`; `wc -l AGENTS.md` stays under 100 |

## Validation commands

```bash
pnpm run lint                                        # = pnpm -r run lint: dclint + lint:env (no bare ${VAR}) + lint:healthcheck (every service) from compose/, after any compose edit
docker compose -f compose/<group>/<service>/docker-compose.yml config
(cd compose/n8n && docker compose -f docker-compose.<variant>.yml config)
(cd compose/models/<engine> && docker compose --profile <runtime> config)
pnpm --filter n8n-starter-cli run typecheck && pnpm -r run build && pnpm -r run test
node packages/cli/dist/index.mjs --help
node packages/cli/dist/index.mjs verify --log-level error   # prints nothing when the environment is complete
tilt alpha tiltfile-result -v                        # evaluates the Tiltfile, starts nothing
```

`pnpm run lint:fix` may rewrite unrelated compose files; revert those with `git checkout -- <file>`. `pnpm run dev` (`tilt up; tilt down`) is interactive and starts containers: leave it to the user unless asked.

## Done checklist

- [ ] Only the files the task needed changed.
- [ ] Every mirror of a changed value updated.
- [ ] The validation commands of the router row ran and passed; their output reported as it was.
- [ ] Every n8n setting touched was confirmed through the `n8n-docs` MCP server and the documentation page cited.
- [ ] `SPEC.md` and the relevant comments and templates updated when a rule or default changed.
- [ ] Nothing committed.
