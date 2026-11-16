---
name: tilt
description: How this repository drives Tilt. Use this skill before editing the Tiltfile or the resource plan in packages/cli/src/commands/tilt.ts, when registering a service with Tilt or changing its deps, links, labels, auto start or what a variant enables, and when a Tilt reload, an enabled resource or a secrets button behaves unexpectedly.
---

# Tilt orchestration

The [Tiltfile](../../../Tiltfile) holds no topology. `n8n-starter tilt resources` builds a JSON plan from the root `.env` and `compose/models/models.json`, `n8n-starter verify --json` gates it, and the Tiltfile loops over the plan. Reasoning: [SPEC.md](../../../SPEC.md), section "Developer experience with Tilt". Paths are relative to the repository root; `src/` and `tests/` are short for `packages/cli/src/` and `packages/cli/tests/`, where the TypeScript conventions of the [n8n-starter-cli](../n8n-starter-cli/SKILL.md) skill apply.

Read [references/tiltfile-api.md](references/tiltfile-api.md) before editing the Tiltfile itself: the calls it uses, with documentation links.

## What the Tiltfile does, in order

1. Loads the root `.env` with the `dotenv` extension, so the compose projects inherit `DOMAIN`.
2. `load_plan()`: runs `node packages/cli/dist/index.mjs tilt resources --log-level error` through `local(quiet=True)` and `decode_json`s it. An invalid `.env` key or an `AI_MODELS` id the engine does not serve on the runtime fails that command with the reason, and with it the Tiltfile. It `watch_file()`s the root `.env` and `models.json` so edits reload it; the Tiltfile reads neither `models.json` nor any compose list itself.
3. `watch_plan()`: registers the `watch` list of every project (the `.env` beside its entry file and the cascade parents) before the gate, because Tilt keeps the paths recorded before a `fail()`: a `pnpm run setup` or `secrets set` that fixes a failed gate reloads the Tiltfile by itself. A missing docker network is no file change, so reload Tilt by hand after creating it.
4. `verify()`: runs `node packages/cli/dist/index.mjs verify --json` as the gate. Its warnings become `warn()`, its errors (`❌`) and hints (`💡`) one `fail()`. `local()` cannot read an exit code and raises on exit 1, hence `|| true` and the `ok` field of the report.
5. `apply_enabled_resources()`: `config.clear_enabled_resources()`, then `config.set_enabled_resources()` with the `enabled` ones. During `tilt up` it then runs `tilt enable --only <enabled already-registered resources>`, because Tilt keeps the old flags on a reload unless `tilt args` changed (tilt-dev/tilt#6800): this is what makes a variant change in the root `.env` take effect without a restart. A failure of that call is a `warn()` with the command to run by hand, never a load error.
6. The loop: `docker_compose(files [+ encode_yaml(override)], project_name, profiles)` per project, `dc_resource()` per resource with the keys of the plan resource, plus a `cmd_button('<resource>-secrets', argv=['node', CLI, 'secrets', 'read', <secrets>])` per resource of a project that carries `secrets`.

A reload re-renders every project and recreates only the services whose rendered config changed. The Tiltfile orchestrates only: it never creates networks or `.env` files (`setup` creates, `verify` checks), and it should not grow conditions.

## The plan

`tiltResources()` in `src/commands/tilt.ts` builds it (shape in `src/schemas/tilt.ts`, tests in `tests/tilt.test.ts`): compose files relative to the Tiltfile, project names, profiles, inline overrides, resource deps, links, labels, `auto_init` and `enabled` per variant and engine. It speaks Tilt's own vocabulary (`dc_resource` keyword names) without importing anything Tilt-specific. The resources per variant are listed in that function and in the Tilt section of SPEC.md.

- One project per `compose/` directory. Every compose project is registered, so disabled services stay visible in the UI and can be started by hand; `enabled` says what the root `.env` switches on.
- `labels` is the compose directory, one of `COMPOSE_GROUPS`.
- `links` is the traefik hostname (`<service>.<DOMAIN>`, `DOMAIN` for n8n, `hooks.<DOMAIN>` for n8n-webhook, `litellm.<DOMAIN>/ui` for litellm); `infer_links: false` on services without a UI, the model servers included (`docker-socket-proxy`, `n8n-runner` and `qdrant` do not set it yet).
- `resource_deps` only for real start-order needs: pgadmin → postgres, redisinsight → redis, n8n → postgres from `build` and redis in queue mode, n8n-runner → n8n, n8n-worker → n8n + redis, n8n-worker-runner → n8n-worker, n8n-webhook → n8n + redis, litellm → litellm-db, never a model server. The schema refuses a dependency on an unknown or, for an enabled resource, a disabled resource.
- Optional services are `auto_init: false` (ollama only while `AI_MODELS` is empty).
- Models (`modelProjects()`): ollama is one project `ollama` with the container variable `MODELS`; vllm one project per model, `vllm-<id>` with `MODEL`, `MODEL_ARGS` and `container_name`. The profile service `<engine>-<runtime>` is exposed under the resource `name` (`ollama` or `vllm-<id>`). The id is the `id` field of the catalogue entry; `vllmContainerName()` in `src/utils/models.ts` is the one place that prefixes it.
- The gateway (`gatewayProjects()`) gets its model list like an engine gets its models, as an inline override: the `content` of the compose config `litellm-config`, one `model_list` entry per id of `AI_MODELS` (JSON, read as YAML). Compose and Tilt compare the service, not the content of a config, so the override also sets the label `n8n-starter.config-hash` (`GATEWAY_CONFIG_HASH_LABEL`) on the `litellm` service: without it a changed list would not recreate the container.
- Every project watches the `.env` beside its entry file, because Tilt does not watch a compose project's own `.env` by itself. A `.env.secrets` is not watched: the CLI rewrites the derived value in the `.env` whenever it writes one. For n8n the parents of the cascade (`N8N_VARIANT_CASCADE`) are watched too, so editing the base reloads while a variant is active.
- A project whose directory holds a `.env.json` carries that directory as `secrets` (`secretDirectories()`), which gives its resources the secrets button: never hard-code a button in the Tiltfile.

## Recipe: change the Tilt plan

A service, a dependency, a link, what a variant enables:

1. `tiltResources()` in `src/commands/tilt.ts`: the `project(...)`/`resource(...)` entry, with `enabled` and `auto_init` as the variant requires; the schema in `src/schemas/tilt.ts` only when the shape changes (then the loop in the Tiltfile too).
2. `tests/tilt.test.ts`: the expected names per variant and the repository test (every file of the plan must exist).
3. The Tilt section of SPEC.md.
4. Gates: the Tilt plan row of the [validate](../validate/SKILL.md) skill, which also says how to evaluate the Tiltfile for another variant without disturbing a running session.

## Gotchas

- Model names cannot reach a compose project through environment variables: `os.putenv` is global to the Tilt process, so every project would see the last value. Hence the inline override.
- The plan runs before the gate, so a missing CLI bundle fails in `load_plan()` with node's `Cannot find module`, not with the `n8n-starter cli is not built` message of `verify()`.
- `pnpm run dev` is `tilt up; tilt down`: Ctrl+C stops and removes every container and keeps networks, `.env` files and volumes. It is interactive: run it only when the user asks.
- No API server runs for `tilt down` or `tilt alpha tiltfile-result`, and nothing is registered on the first load: `apply_enabled_resources()` returns early unless `config.tilt_subcommand` is `up`.
- A session that is already running (port 10350 in use), a reload that did not apply, a missing secrets button: [troubleshoot](../troubleshoot/SKILL.md) skill. Never `tilt down` a session you did not start.
