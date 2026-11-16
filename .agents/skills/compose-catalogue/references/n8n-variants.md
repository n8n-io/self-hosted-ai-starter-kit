# n8n variant cascade

`N8N_VARIANT` selects one self-contained file in `compose/n8n/`; each file extends the previous one with compose `extends`. Reasoning and the canonical table: [SPEC.md](../../../../SPEC.md), section "`compose/n8n/` variants". Every n8n setting in these files goes through the [n8n-docs](../../n8n-docs/SKILL.md) skill, with the page cited in the report. Paths are relative to the repository root.

| Variant | File | Adds |
| --- | --- | --- |
| `dev` | `docker-compose.yml` | the base: one `n8n` container in regular execution mode on SQLite (`x-n8n-env-sqlite`) with the internal task runner (`x-n8n-env-runners-internal`: `N8N_RUNNERS_MODE=internal` plus the two JavaScript allowlists; Python Code nodes need the external runner, internal mode is deprecated and n8n logs it at startup); no storage service |
| `build` | `docker-compose.build.yml` | postgres (`x-n8n-env-postgres`), the external runner on main (`x-n8n-env-runners-broker`) and `n8n-runner`, which mounts `n8n-task-runners.json`; the JavaScript defaults of `x-n8n-env-runners-code-allow` repeat the base's |
| `community` | `docker-compose.community.yml` | queue mode (`x-n8n-env-queue`: `EXECUTIONS_MODE=queue`, redis; `x-n8n-env-webhook-processor`: `N8N_WEBHOOK_URL`, `N8N_DISABLE_PRODUCTION_MAIN_PROCESS` on main), `n8n-worker` (extends `n8n`, `command: worker`), `n8n-worker-runner` (extends `n8n-runner`) and `n8n-webhook` (extends `n8n`, `command: webhook`, routed at `hooks.<DOMAIN>`, `deploy.replicas`); main gets the `n8n-hooks-test` router for the test paths |
| `enterprise` | `docker-compose.enterprise.yml` | `x-n8n-env-license` on `n8n`, `n8n-webhook` and `n8n-worker`; garage (S3 binary data), external secrets and multi-main are still to be wired up |

## Rules

- The base holds only what every variant needs. A variant adds or overrides; it never has to remove, because an inherited env var cannot be unset through `extends`.
- Anchors do not cross files, and a variant file never re-declares one. Reuse is `extends: {file, service}` across files or `extends: <service>` within one.
- Removal happens only with the `!override` / `!reset` tags, as the worker does today: `volumes: !reset []`, `networks: !override [n8n-starter-private]`, `labels: !reset []` on `n8n-worker`, `depends_on: !override` on `n8n-worker-runner`. Both tags are registered as `yaml.customTags` in `.vscode/settings.json`.
- Every variant file is a complete entry point: `docker compose -f docker-compose.<variant>.yml up` from `compose/n8n/` works without Tilt.
- A worker and its runner are a 1:1 pair (the runner dials one broker through `N8N_RUNNERS_TASK_BROKER_URI`). Scale by adding pairs, never with `--scale`. Workers carry no `.n8n` mount.
- The webhook processor starts no task runner, so it has no runner sidecar and scales with `N8N_WEBHOOK_REPLICAS` (`deploy.replicas`, default 1; keep 1 with an MCP Server Trigger). It keeps both networks and `labels: !override` with its own `hooks.<DOMAIN>` router; the test paths (`/webhook-test/`, `/form-test/`, `/mcp-test/`) are only served by main.
- The variant list is mirrored: `N8N_VARIANT_CASCADE` in `packages/cli/src/commands/tilt.ts` maps each variant to its files (Tilt runs the last one and watches the parents), and `N8N_VARIANTS` in `packages/cli/src/schemas/config.ts` lists the same keys.

## Task runner launcher config

`n8n-runner` and `n8n-worker-runner` mount `compose/n8n/n8n-task-runners.json` over `/etc/n8n-task-runners.json`: the image's launcher config with the four Code node allowlists (`NODE_FUNCTION_ALLOW_BUILTIN`, `NODE_FUNCTION_ALLOW_EXTERNAL`, `N8N_RUNNERS_STDLIB_ALLOW`, `N8N_RUNNERS_EXTERNAL_ALLOW`) moved from `env-overrides` to `allowed-env`, because the launcher forwards only listed variables to a runner. Their curated defaults live in `x-n8n-env-runners-code-allow` of the build file; `dev` sets the JavaScript pair on `n8n` through `x-n8n-env-runners-internal` of the base file. Anchors do not cross files, so keep both copies of the JavaScript defaults equal. Re-diff the file against the image on every `N8N_VERSION` bump: [n8n-upgrade](../../n8n-upgrade/SKILL.md) skill.

## `.env.template` sections

Queue-mode and license variables live in `compose/n8n/.env.template` in the section whose header names the variant scope, widest first: `# required|optional, all variants`, `…, build, community and enterprise variants` (the postgres keys, the runner token, the Python allowlists), `…, community and enterprise variants`, `…, enterprise variant`. A key that is both required and variant-specific (`N8N_LICENSE_ACTIVATION_KEY`) is placed by its requirement.

## Recipe: add an n8n variant

1. Add `compose/n8n/docker-compose.<variant>.yml` that `extends` every service from the previous file of the cascade and adds its own `x-*` anchors (named by content).
2. Register the cascade in `N8N_VARIANT_CASCADE` of `packages/cli/src/commands/tilt.ts` and any flag that gates resources for it (like `build`, `queue` and `enterprise` in `tiltResources()`), with a case in `tests/tilt.test.ts`. Conventions: [tilt](../../tilt/SKILL.md) skill.
3. Add the variant to `N8N_VARIANTS` in `packages/cli/src/schemas/config.ts`, the `Options:` comment in the root `.env.template` and the variant table in SPEC.md; rebuild and test the CLI.
4. Gates: the compose, Tilt plan and n8n setting rows of the [validate](../../validate/SKILL.md) skill, with the variant in the root `.env` for the Tiltfile evaluation.
