# Compose catalogue rules

Operational rules for everything under `compose/`, the model catalogue and the way the [Tiltfile](../../../../Tiltfile) consumes them. [SPEC.md](../../../../SPEC.md) holds the reasoning and wins when the two disagree; cite its section in file comments instead of repeating it.

## Service directory contract

Every service lives in `compose/<group>/<service>/`:

| File | Rule |
| --- | --- |
| `docker-compose.yml` | Required. Top-level `name:` equals the directory name, so every service is its own compose project. |
| `README.md` | Required. Title = directory name; one or two sentences (what it is, its role and start behaviour in this kit, a relative link to the SPEC.md section and the `.env.template`); then links labelled Homepage, Repository, Docker image (one per pulled image), Documentation, API reference, Releases, in that order, omitting labels without a page. A bundled second image (`garage-webui`, `litellm-db`) gets a `## <service>` block with its Repository and Docker image. No features, configuration or deployment text (SPEC.md `compose/`). |
| `.env.template` | Only when the service needs `${VAR:?}` values (a pinned version with its value, a secret as an empty key) or has a knob a developer is expected to change (listed commented out with its default: `# N8N_PROTOCOL=http`). `setup` copies it to `.env` next to it and never overwrites. A service without such values has no template. With both kinds, group it under the one-line headers `# required` then `# optional`, a blank line before each. |
| `.env.secrets.json` | Only when the template has secret keys: one entry per key with `source` `generate` (random, `rotation` `free`/`manual`/`never`), `prompt` (human, `required` under root `.env` values) or `link` (`from` directory and `key` of another manifest). Editor schema `compose/.env.secrets.schema.json`, zod schema `packages/cli/src/schemas/secrets.ts`, rules in the Secrets section of SPEC.md. |
| Config files | Mounted into the container from the directory (`traefik.yml`, `garage.toml`, `server.json`, `n8n-task-runners.json`, …). |
| Runtime data | Never in the directory. It sits in `.volumes/<group>/<service>/…` at the repo root, reached as `${VOLUMES_PATH:-<relative path to .volumes>}/<group>/<service>/…` (three `../` from a service directory, two from `compose/n8n/`). `VOLUMES_PATH` always names the `.volumes` root, never a service folder. |

Groups: `proxy` (edge), `n8n` (the application, a variant cascade instead of one file), `storage` (data stores and their admin UIs), `services` (qdrant), `models` (the catalogue plus one directory per engine and per gateway: `litellm`).

## Naming

- Directory name = compose project `name:` = compose service name = traefik host label (`<service>.<DOMAIN>`). Exceptions today: `redis-insight/` runs the service `redisinsight`, `garage/` also runs `garage-webui`, `litellm/` also runs `litellm-db`.
- Model engine services are `<engine>-<runtime>` (`ollama-cpu-arm64`, `vllm-gpu-nvidia`, …), one per `AI_RUNTIME`, each in the compose profile of the same name.
- A vllm model is addressed everywhere (Tilt resource, compose project, `container_name`, hostname) by `vllm-<id>`, the `id` of its catalogue entry (`vllm-qwen3-5-0-8b`), the same value as in `AI_MODELS`; nothing normalises or derives a name.
- YAML anchors are named after what they configure (`x-n8n-env-queue`, `x-n8n-env-license`, `x-n8n-env-runners-broker`), never after a variant.

## Compose spec rules

Check every one before finishing a compose change:

- [ ] Image tag pinned to an exact version, literally or via `${VAR:?}` from `.env` (`N8N_VERSION`, `OLLAMA_VERSION`, `VLLM_VERSION`, `QDRANT_VERSION`).
- [ ] Only the external networks `n8n-starter-public` and `n8n-starter-private`, both declared `external: true`; a compose file never creates a network of its own.
- [ ] Exposed through traefik with the label `traefik.enable=true` on `n8n-starter-public`; no host `ports:` unless a tool needs direct access (postgres `5432`, redis `6379`). Traefik itself binds `127.0.0.1:80` only.
- [ ] Every service has a `healthcheck` in the compose file (`lint:healthcheck` fails without one; inherited through `extends` or an anchor counts, an image `HEALTHCHECK` or a disabled one does not), probing with a tool the pinned image ships: `wget`/`curl`, the service's own CLI (`/garage status`), or bash `/dev/tcp` (`qdrant`). Try the probe in the container (`docker exec <container> <probe>; echo $?`) before writing it down. Dependants inside the same project use `depends_on: { <svc>: { condition: service_healthy } }`. Never `depends_on` a service of another project: they are separate compose projects, Tilt `resource_deps` and the restart policy cover start order.
- [ ] `security_opt: [no-new-privileges=true]` where the image allows it. The docker socket is mounted read-only into `docker-socket-proxy` only, never into traefik.
- [ ] Shared config is factored into `x-*` anchors within a file. Anchors never cross files; cross-file reuse is `extends` (n8n cascade) or `.env` variables only.
- [ ] `${VAR:-default}` for optional settings (the default lives in the compose file, the template shows the knob commented out), `${VAR:?}` for values that must come from `.env`; never a bare `${VAR}`, `$VAR` or `environment: - VAR` (`lint:env` fails on the first two), never a literal credential or an absolute host path. The one exception: vllm checks `MODEL` at container start, because Tilt sets container variables, not interpolation ones.
- [ ] Comments stay one line and point to where the reasoning lives (`see ../../SPEC.md`), with a relative path from the file.
- [ ] No `version:` key; `no-version-field` is the only dclint rule switched off in `compose/.dclintrc`.
- [ ] `pnpm run lint` passes.

## Ports

| Port | Who | Published? |
| --- | --- | --- |
| 80 | traefik `web` entrypoint | yes, on `127.0.0.1` only |
| 8082 | traefik ping (healthcheck) | no |
| 5678, 5679 | n8n UI/API and task broker (`n8n-runner` dials `http://n8n:5679`, `n8n-worker-runner` dials `http://n8n-worker:5679`) | no, n8n is routed at the bare `DOMAIN` |
| 5680 | health check server of the task runner launcher in `n8n-runner` and `n8n-worker-runner` (healthcheck, `/healthz`) | no |
| 5432 | postgres | yes, `0.0.0.0` (direct tool access) |
| 6379 | redis | yes, `0.0.0.0` (direct tool access) |
| 11434 | ollama, `http://ollama:11434` (network alias on `n8n-starter-private`) | no, never routed |
| 8000 | each vllm container, `http://vllm-<id>:8000/v1`, bearer `VLLM_API_KEY` (`/health` stays open) | no, never routed |
| 3900, 3902, 3903, 3909 | garage S3, web, admin API and garage-webui | no, routed through explicit routers |

Everything else is reachable only through traefik at `<service>.<DOMAIN>`.

## Environment variables

- Required (`${VAR:?}`, must come from the `.env` of the same directory): `N8N_VERSION`, `N8N_ENCRYPTION_KEY`, `N8N_USER_MANAGEMENT_JWT_SECRET`, `DB_POSTGRESDB_USER`, `DB_POSTGRESDB_PASSWORD`, `N8N_RUNNERS_AUTH_TOKEN` (these three from `build` up), `N8N_LICENSE_ACTIVATION_KEY` (enterprise only), `QDRANT_VERSION`, `LITELLM_VERSION`, `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `OLLAMA_VERSION`, `VLLM_VERSION`, `VLLM_API_KEY`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`, `LITELLM_DB_PASSWORD`; litellm also requires `VLLM_API_KEY`, a link to the key of `compose/models/vllm`.
- Optional, default in the compose file: `DOMAIN` (`n8n.localhost`, in traefik, n8n, garage and the Tiltfile), `TZ` (`Europe/Berlin`, traefik and n8n), `POSTGRES_DB`, `LITELLM_DB_USER` and `LITELLM_DB_NAME` (both `litellm`), `N8N_LOG_LEVEL`, `N8N_PROTOCOL` (`http`), `N8N_SECURE_COOKIE` (`false`), `N8N_PROXY_HOPS` (`1`), `DB_POSTGRESDB_DATABASE` (`n8n`), `N8N_RUNNERS_LAUNCHER_LOG_LEVEL`, the Code node allowlists `NODE_FUNCTION_ALLOW_BUILTIN`, `NODE_FUNCTION_ALLOW_EXTERNAL`, `N8N_RUNNERS_STDLIB_ALLOW`, `N8N_RUNNERS_EXTERNAL_ALLOW` (curated lists in `x-n8n-env-runners-code-allow` of the build file, forwarded by the mounted `compose/n8n/n8n-task-runners.json`; `dev` sets the JavaScript pair on `n8n` through `x-n8n-env-runners-internal`), `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS` (`true`), `QUEUE_WORKER_CONCURRENCY` (`10`), `N8N_LICENSE_TENANT_ID` (`1001`), `TZ`, `OLLAMA_PULL_MODELS`, `VLLM_MODEL`, `VLLM_MODEL_ARGS`, `VLLM_MODEL_ID`, `HF_TOKEN`, `VLLM_CPU_KVCACHE_SPACE` (`2`), `VLLM_EXTRA_ARGS` (empty), `VOLUMES_PATH` (everywhere).
- `.env.template` files exist for the root, `compose/proxy/traefik` (knobs only), `compose/n8n`, `compose/storage/postgres`, `compose/storage/pgadmin`, `compose/services/qdrant`, `compose/models/ollama`, `compose/models/vllm`, `compose/models/litellm`. Required keys are live: a pinned version with its value, a secret empty (`N8N_ENCRYPTION_KEY=`) and declared in the `.env.secrets.json` next to the template; knobs are commented out with their default (`# N8N_PROXY_HOPS=1`). A new required variable goes into the `# required` section of the template of the same directory (a knob into `# optional`); `setup` only creates missing `.env` files and fills empty secrets, so existing checkouts add a non-secret key by hand (say so in the change summary) while a new secret is generated on the next `setup`.
- Manifests exist for `compose/n8n`, `compose/storage/postgres`, `compose/storage/pgadmin`, `compose/models/litellm` and `compose/models/vllm`; `tests/secrets.test.ts` checks every manifest against its template (empty live key, or commented out for an optional `prompt`), its compose files (`${KEY:?}`, or `${KEY:-}` for an optional prompt) and the editor schema, and that every `${VAR:?}` named `*PASSWORD*`, `*SECRET*`, `*_KEY*` or `*TOKEN*` in the catalogue is declared. The root `.env` never holds a secret: the Tiltfile prints it.
- The root `.env` holds only `N8N_VARIANT`, `AI_RUNTIME`, `AI_ENGINE`, `AI_GATEWAY` (empty for none, and the one key that may be absent), `AI_MODELS`, `DOMAIN`. Tilt loads it with the `dotenv` extension, so every compose project it starts sees `DOMAIN`; by hand the compose default `n8n.localhost` applies (shell variable > `.env` next to the file > compose default) and `DOMAIN=… docker compose …` overrides it.
- `DOMAIN` is used at compose time in labels and at runtime by traefik (`{{ env "DOMAIN" }}` in the default rule and in `config/dashboard.yml`), so it reaches traefik as a container variable too.
- What an n8n variable does, its default and the edition it needs is never recalled from memory: the [n8n-docs skill](../../n8n-docs/SKILL.md) looks it up through the `n8n-docs` MCP server and the report cites the page.

## Networks and routing

- `n8n-starter-public` holds traefik and every container it routes to (`traefik.enable=true`); `n8n-starter-private` holds everything else. A routed service that also needs a backend joins both.
- Membership today: public only `garage`, `garage-webui`; private only `docker-socket-proxy`, `postgres`, `redis`, `n8n-runner`, `n8n-worker`, `n8n-worker-runner`, `qdrant`, `ollama`, `vllm-*`, `litellm-db`; both `traefik`, `n8n`, `n8n-webhook`, `pgadmin`, `redisinsight`, `litellm`. Update the table in SPEC.md when membership changes.
- Traefik (`compose/proxy/traefik/traefik.yml`) discovers containers through `docker-socket-proxy` (`tcp://docker-socket-proxy:2375`, read-only: `CONTAINERS=1`, `POST=0`), `exposedByDefault: false`, provider `network: n8n-starter-public`, default rule ``Host(`<compose service>.<DOMAIN>`)``. n8n overrides the rule to the bare `DOMAIN` and, in queue mode, `n8n-webhook` to `hooks.<DOMAIN>` with the test paths routed back to main by the `n8n-hooks-test` router; garage declares its own routers (`s3.`, `s3web.`, `s3ui.<DOMAIN>`); the traefik dashboard is `traefik.<DOMAIN>` (`config/dashboard.yml`); model servers are never routed.
- The `web` entrypoint applies the `default@file` middleware chain (compress + security headers) from `config/`. The stack is plain HTTP only; HTTPS is not supported yet.
- `N8N_PROXY_HOPS=1` because traefik is the only proxy in front of n8n; raise it by one per additional proxy.

## n8n variant cascade

`N8N_VARIANT` selects one self-contained file in `compose/n8n/`; each file extends the previous one with compose `extends`:

| Variant | File | Adds |
| --- | --- | --- |
| `dev` | `docker-compose.yml` | the base: one `n8n` container in regular execution mode on SQLite (`x-n8n-env-sqlite`) with the internal task runner (`x-n8n-env-runners-internal`: `N8N_RUNNERS_MODE=internal` plus the two JavaScript allowlists; Python Code nodes need the external runner, internal mode is deprecated and n8n logs it at startup); no storage service |
| `build` | `docker-compose.build.yml` | postgres (`x-n8n-env-postgres`), the external runner on main (`x-n8n-env-runners-broker`) and `n8n-runner`, which mounts `n8n-task-runners.json` (the image's launcher config with the Code node allowlists moved to `allowed-env`; re-diff it against the image on an `N8N_VERSION` bump); the JavaScript defaults of `x-n8n-env-runners-code-allow` repeat the base's |
| `community` | `docker-compose.community.yml` | queue mode (`x-n8n-env-queue`: `EXECUTIONS_MODE=queue`, redis; `x-n8n-env-webhook-processor`: `N8N_WEBHOOK_URL`, `N8N_DISABLE_PRODUCTION_MAIN_PROCESS` on main), `n8n-worker` (extends `n8n`, `command: worker`), `n8n-worker-runner` (extends `n8n-runner`) and `n8n-webhook` (extends `n8n`, `command: webhook`, routed at `hooks.<DOMAIN>`, `deploy.replicas`); main gets the `n8n-hooks-test` router for the test paths |
| `enterprise` | `docker-compose.enterprise.yml` | `x-n8n-env-license` on `n8n` and `n8n-worker`; garage (S3 binary data), external secrets and multi-main are still to be wired up |

Rules:

- The base holds only what every variant needs. A variant adds or overrides; it never has to remove, because an inherited env var cannot be unset through `extends`.
- Anchors do not cross files. Reuse is `extends: {file, service}` across files or `extends: <service>` within one.
- Removal happens only with the `!override` / `!reset` tags, as the worker does today: `volumes: !reset []`, `networks: !override [n8n-starter-private]`, `labels: !reset []` on `n8n-worker`, `depends_on: !override` on `n8n-worker-runner`. Both tags are registered as `yaml.customTags` in `.vscode/settings.json`.
- Every variant file is a complete entry point: `docker compose -f docker-compose.<variant>.yml up` from `compose/n8n/` works without Tilt.
- A worker and its runner are a 1:1 pair (the runner dials one broker through `N8N_RUNNERS_TASK_BROKER_URI`). Scale by adding pairs, never with `--scale`. Workers carry no `.n8n` mount.
- The webhook processor starts no task runner, so it has no runner sidecar and scales with `N8N_WEBHOOK_REPLICAS` (`deploy.replicas`, default 1; keep 1 with an MCP Server Trigger). It keeps both networks and `labels: !override` with its own `hooks.<DOMAIN>` router; the test paths (`/webhook-test/`, `/form-test/`, `/mcp-test/`) are only served by main.
- Queue-mode and license variables live in `compose/n8n/.env.template` in the section whose header names the variant scope: `# required|optional, all variants`, `…, build, community and enterprise variants` (the postgres keys, the runner token, the Python allowlists), `…, community and enterprise variants`, `…, enterprise variant` (widest first). A key that is both required and variant-specific (`N8N_LICENSE_ACTIVATION_KEY`) is placed by its requirement.
- The Tiltfile maps the variants in `N8N_VARIANT_CASCADE` and watches the parent files; `N8N_VARIANTS` in `packages/cli/src/schemas/config.ts` lists the same keys.

## Model engines and the catalogue

| | ollama | vllm |
| --- | --- | --- |
| Compose file | `compose/models/ollama/docker-compose.yml`, anchor `x-ollama` | `compose/models/vllm/docker-compose.yml`, anchors `x-vllm` and `x-vllm-cpu` |
| Services | `ollama-<runtime>`, image `ollama/ollama:${OLLAMA_VERSION:?}` (`-rocm` suffix on `gpu-amd`) | `vllm-<runtime>`, images `vllm/vllm-openai-cpu:${VLLM_VERSION:?}-arm64` / `-x86_64`, `vllm/vllm-openai-rocm`, `vllm/vllm-openai` |
| Containers | one server pulls every model of `AI_MODELS` in the background of `ollama serve` (PID 1) | one container per model (`container_name: vllm-${VLLM_MODEL_ID:-model}`), each its own compose project |
| Container variables (set by Tilt from the plan of `tilt resources`) | `MODELS` (comma separated ollama tags) | `MODEL`, `MODEL_ARGS`, plus `container_name` |
| Interpolation variables (manual runs) | `OLLAMA_PULL_MODELS` | `VLLM_MODEL`, `VLLM_MODEL_ARGS`, `VLLM_MODEL_ID`, `VLLM_EXTRA_ARGS` |
| Reachable | `http://ollama:11434` on `n8n-starter-private` | `http://vllm-<id>:8000/v1` on `n8n-starter-private`, bearer `VLLM_API_KEY` |
| Healthy when | `ollama show` succeeds for every model (`start_period: 15m`) | `/health` answers after the download (`start_period: 15m`) |
| Weights | `.volumes/models/ollama/data` | `.volumes/models/vllm/huggingface`, shared by all containers |

Rules:

- No model name ever lives in a compose file. `tilt resources` (`modelProjects()` in `packages/cli/src/commands/tilt.ts`) builds an inline override of the runtime service from the catalogue and the Tiltfile passes it as `docker_compose([file, encode_yaml(override)])`. Environment variables cannot do this because `os.putenv` is global to the Tilt process.
- Container variable names are neutral on purpose: `OLLAMA_MODELS` is ollama's own model-directory setting and vLLM warns about every unknown `VLLM_*` variable. The `OLLAMA_PULL_MODELS` / `VLLM_MODEL*` interpolation names exist only for running an engine by hand.
- Runtime-specific `vllm serve` flags live in the compose `command` (CPU: `--dtype=bfloat16` and `--skip-mm-profiling`, which keeps vision but skips its start-up profiling, over 20 minutes on CPU, plus the container variable `VLLM_CPU_KVCACHE_SPACE=${VLLM_CPU_KVCACHE_SPACE:-2}`, an absolute KV cache in GiB instead of vLLM's memory share, which depends on the VM size); model-specific flags live in the catalogue `args` (`--max-model-len`, tool-call parser); machine-specific flags live in `VLLM_EXTRA_ARGS` of `compose/models/vllm/.env` (container variable `EXTRA_ARGS`), appended last by the entrypoint, so the precedence is model < runtime < machine. The Qwen3.5 entries deliberately carry no `--reasoning-parser`: with it a non-thinking answer comes back as `content: null`.
- Catalogue entry fields, one entry per model: `id` (the `AI_MODELS` value and the DNS label of the docker names `<engine>-<id>`, pattern `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, at most 58 characters), `label`, and a block per engine that serves it (`ollama`, `vllm`; at least one) with `model` (engine name: ollama tag or Hugging Face id), optional `memory` (a number of GB, an estimate; `models select` prints `~<GB> GB RAM`, VRAM on a gpu runtime), `note` (a short hint shown after the memory), `runtimes` (only when that engine cannot run the model on some hardware; today unused, memory is never a reason); the vllm block adds `args`. Validated by `packages/cli/src/schemas/models.ts` and, for editors, `compose/models/models.schema.json`; both change together.
- Per container exactly one service runs: the profile named after `AI_RUNTIME` (`COMPOSE_PROFILES=$AI_RUNTIME` by hand, `profiles=[AI_RUNTIME]` in Tilt). `cpu-arm64` is the default and first wherever runtimes are listed.
- vLLM on CPU loads bf16 weights (about 2.3 GB per billion parameters) plus the KV cache of `VLLM_CPU_KVCACHE_SPACE`, the runtime overhead and about 2.5 GB for the vision processors (the catalogue `memory` is that measured sum, 10 GB for the 0.8B, 12 GB for the 2B): a container needs it free in the Docker VM whatever its size; the `memory` estimate is the only guard, no entry is restricted to the GPU runtimes. Text only is a machine choice: `VLLM_EXTRA_ARGS='--limit-mm-per-prompt={"image":0,"video":0}'` in `compose/models/vllm/.env` (7.5 GB instead of 10 GB for the 0.8B); the catalogue `args` carry the limit flag only for an entry that is text-only everywhere. vLLM `v0.32.0` and later CPU images crash on the first request (vllm issue 61131), hence `VLLM_VERSION=v0.31.0` in the template.
- `AI_MODELS=` (empty) starts no model. Changing it restarts the ollama server with the new list or adds and removes vllm containers.

## How Tilt consumes the catalogue

- The Tiltfile loads the root `.env` (dotenv, so the compose projects inherit `DOMAIN`), runs `node packages/cli/dist/index.mjs tilt resources --log-level error` through `local(quiet=True)` and `decode_json`: the plan (an invalid `.env` key or an `AI_MODELS` id the engine does not serve on the runtime fails that command with the reason, and with it the Tiltfile), then `node packages/cli/dist/index.mjs verify --json` as the gate (its warnings become `warn()`, its errors and hints one `fail()`). The plan comes first and `watch_plan()` registers the `watch` list of every project (the `.env` beside its entry file and the cascade parents) before the gate, because Tilt keeps the paths recorded before a `fail()`: a `pnpm run setup` or `secrets set` that fixes a failed gate reloads the Tiltfile by itself. The Tiltfile reads neither `models.json` nor any compose list itself; it `watch_file()`s the root `.env` and `models.json` so edits reload it.
- The plan (`tiltResources()` in `packages/cli/src/commands/tilt.ts`, shape in `src/schemas/tilt.ts`, tests in `tests/tilt.test.ts`) lists one project per `compose/` directory with its resources: proxy `docker-socket-proxy`, `traefik`; n8n `n8n` (+ `n8n-runner` from `build`; `n8n-worker`, `n8n-worker-runner`, `n8n-webhook` in queue mode); storage `postgres`, `pgadmin` (enabled from `build`; `redis`, `redisinsight` enabled in queue mode; `garage`, `garage-webui` enabled for enterprise); services `qdrant`; models `litellm-db`, `litellm` (enabled by `AI_GATEWAY=litellm`, `gatewayProjects()`), then `ollama`, or `vllm-<id>` per model. Every compose project is registered, so disabled services stay visible in the UI and can be started by hand. The gateway gets its model list like an engine gets its models, as an inline override: the `content` of the compose config `litellm-config`, one `model_list` entry per id of `AI_MODELS` (JSON, read as YAML), never a model name in the compose file. Compose and Tilt compare the service, not the content of a config, so the override also sets the label `n8n-starter.config-hash` (`GATEWAY_CONFIG_HASH_LABEL`) on the `litellm` service: without it a changed list would not recreate the container.
- The Tiltfile loops: `docker_compose(files [+ encode_yaml(override)], project_name, profiles)` per project, `dc_resource(service, new_name, project_name, labels, resource_deps, links, infer_links, auto_init)` per resource, plus a `cmd_button('<resource>-secrets', argv=['node', CLI, 'secrets', 'read', <secrets>])` per resource of a project that carries `secrets` (its directory, set by the plan when a `.env.secrets.json` sits beside the compose file; never hard-code a button), and `config.set_enabled_resources()` with the `enabled` ones; during `tilt up` it then runs `tilt enable --only <enabled already-registered resources>`, because Tilt keeps the old flags on a reload unless `tilt args` changed (tilt-dev/tilt#6800), so a variant change in the root `.env` takes effect without a restart. `labels` is the compose directory; `links` is the traefik hostname (`DOMAIN` for n8n), `infer_links: false` on services without a UI; `resource_deps` only for real start-order needs (pgadmin → postgres, redisinsight → redis, n8n → postgres from `build` and redis in queue mode, n8n-runner → n8n, n8n-worker → n8n + redis, n8n-worker-runner → n8n-worker); optional services are `auto_init: false` (ollama only while `AI_MODELS` is empty). The schema refuses a dependency on an unknown or, for an enabled resource, a disabled resource.
- Models: ollama is one project `ollama` with `MODELS`; vllm one project per model, `vllm-<id>` with `MODEL`, `MODEL_ARGS` and `container_name`; the profile service `<engine>-<runtime>` is exposed under the resource `name` (`ollama` or `vllm-<id>`). The id is the `id` field of the entry; `vllmContainerName()` in `packages/cli/src/utils/models.ts` is the one place that prefixes it.
- Every project watches the `.env` beside its entry file, because Tilt does not watch a compose project's own `.env` by itself; a reload re-renders every project and recreates only the services whose rendered config changed. For n8n the parents of the cascade are watched too, so editing the base reloads while a variant is active.
- The Tiltfile orchestrates only; it never creates networks or `.env` files (`setup` creates, `verify` checks).
- `pnpm run dev` is `tilt up; tilt down`: Ctrl+C stops and removes every container and keeps networks, `.env` files and volumes. Evaluate the Tiltfile without starting anything with `tilt alpha tiltfile-result -v`; its `dotenv()` call overrides exported variables, so edit the root `.env` temporarily to test another variant and restore it afterwards. If `tilt up` reports port 10350 in use, an earlier Tilt is still running: reuse it (`tilt trigger <resource>`), do not `tilt down` it.

## Quality gates and anti-patterns

Gates: `pnpm run lint` (`pnpm -r run lint`, i.e. the `lint` script of `compose/package.json`: dclint over the catalogue with `--max-warnings 0` so every warning fails the gate, rules in `compose/.dclintrc`, then `lint:env`, a grep in the same `package.json` that fails on any bare `${VAR}` or `$VAR` in a `docker-compose*.yml`, then `lint:healthcheck`, which renders every `docker-compose*.yml` with `docker compose config --no-interpolate` and all profiles and fails, naming file and services, on a service without a healthcheck; it needs `docker compose` and `jq`, no `.env` and no daemon); `docker compose -f <file> config` from the service directory with the required variables set, which catches interpolation and `extends` errors; `pnpm run lint:fix` may rewrite unrelated compose files, revert those with `git checkout -- <file>`.

Anti-patterns that fail review:

- Declaring `networks:` with a driver, or joining `n8n-starter-public` without `traefik.enable=true` (and vice versa).
- Publishing host ports for a routed service, or binding traefik to `0.0.0.0`.
- Floating image tags (`latest`, a bare major), or a pinned version with a `:-` default.
- `${VAR:?}` for an optional knob, a bare `${VAR}`, or a live `.env.template` key that repeats a compose default (knobs are commented out).
- A model name in a compose file, or a model-specific flag in `command` / a runtime flag in the catalogue `args`.
- Re-declaring an `x-*` anchor in a variant file, naming an anchor after a variant, or removing inherited settings without `!override` / `!reset`.
- `depends_on` across compose projects, or `--scale` for workers.
- Adding a runtime, engine, variant or model in one place only (see the mirrors list in [SKILL.md](../SKILL.md)).
- Multi-line comments repeating SPEC.md, or a `version:` key.

## Known deviations (do not fix unprompted)

The current files deviate from the rules above in places. Mention them when relevant; do not clean them up without being asked:

- Not exactly pinned: `postgres:17`, `redis:8-alpine` and `qdrant/qdrant:${QDRANT_VERSION:?}` with `v1.19` in the template.
- No `no-new-privileges`: traefik, postgres, redis, pgadmin, redisinsight, garage, garage-webui, qdrant; `vllm-gpu-amd` has only `seccomp=unconfined`.
- Named volumes instead of `.volumes` bind mounts: qdrant `qdrant_storage`.
- postgres and redis bind `0.0.0.0`.
- The Tiltfile links garage as `web.<DOMAIN>` while its router serves `s3web.<DOMAIN>`.

## Recipes

### Add a service

1. Create `compose/<group>/<service>/docker-compose.yml` with `name: <service>`, a pinned image, a healthcheck, `security_opt`, the right network(s) declared `external: true`, `traefik.enable=true` or no ports, and data under `${VOLUMES_PATH:-../../../.volumes}/<group>/<service>/…`.
2. Add `.env.template` next to it only for `${VAR:?}` values and dev knobs.
3. Add `README.md` next to it following the contract above (copy a neighbour, e.g. `compose/services/qdrant/README.md`), and check every URL resolves.
4. `tiltResources()` in `packages/cli/src/commands/tilt.ts`: a `project([composeFile('<group>', '<service>')], [resource('<service>', ['<group>'], { links or infer_links: false, resource_deps, auto_init: false if optional, enabled per variant })])`, and the expected names in `tests/tilt.test.ts`.
5. SPEC.md: repository tree, network membership table, Tilt resource lists; README "What's included" when user-facing.
6. Validate: `pnpm run lint`; `docker compose -f compose/<group>/<service>/docker-compose.yml config`; `pnpm run setup && pnpm run verify` (new `.env`); CLI typecheck + build + test; `tilt alpha tiltfile-result -v`.

### Add an n8n variant

1. Add `compose/n8n/docker-compose.<variant>.yml` that `extends` every service from the previous file of the cascade and adds its own `x-*` anchors (named by content).
2. Register the cascade in `N8N_VARIANT_CASCADE` of `packages/cli/src/commands/tilt.ts` and any flag that gates resources for it (like `build`, `queue` and `enterprise` in `tiltResources()`), with a case in `tests/tilt.test.ts`.
3. Add the variant to `N8N_VARIANTS` in `packages/cli/src/schemas/config.ts`, the `Options:` comment in the root `.env.template` and the variant table in SPEC.md; rebuild and test the CLI.
4. Validate: `pnpm run lint`; `(cd compose/n8n && docker compose -f docker-compose.<variant>.yml config)`; CLI typecheck + build + test; `tilt alpha tiltfile-result -v` with the variant in the root `.env`.

### Add a model

1. Add one entry to `compose/models/models.json` with its `id` (a DNS label, e.g. `qwen3-5-0-8b`), its `label` and a block per engine that serves it: the engine's `model` name, its `memory` as a number of GB and a `note` when a runtime needs a setting; the vllm block needs `args`; add `runtimes` to a block only when that engine does not run the model everywhere.
2. If the entry shape changes, update `packages/cli/src/schemas/models.ts`, `compose/models/models.schema.json` and `modelOptions()` in `packages/cli/src/utils/models.ts` together.
3. SPEC.md: the entries table of the models section.
4. Validate: `pnpm -r run test` (`tests/models.test.ts`); `pnpm run models select` shows the entry (disabled on runtimes it cannot run); `tilt alpha tiltfile-result -v` with the id in `AI_MODELS`.

### Add a gateway

1. Add `compose/models/<gateway>/docker-compose.yml` like any service (Add a service, steps 1 to 3), with the model list as a top-level `configs` entry whose `content` an override can replace, and a link in its `.env.secrets.json` for every engine key it needs.
2. Mirrors: `AI_GATEWAYS` in `packages/cli/src/schemas/config.ts` (empty stays the default), the `Options:` comment of `AI_GATEWAY` in the root `.env.template`, `GATEWAYS` in `packages/cli/src/utils/models.ts` (endpoint and key), SPEC.md (configuration block, gateway table).
3. `gatewayProjects()` in `packages/cli/src/commands/tilt.ts`: the project, enabled by its `AI_GATEWAY` value, with the model list built from the catalogue, and a case in `tests/tilt.test.ts`.
4. Validate: `pnpm run lint`; `docker compose -f compose/models/<gateway>/docker-compose.yml config`; CLI typecheck + build + test; `tilt alpha tiltfile-result -v` with the gateway set.

### Add a runtime or engine

1. Runtime: add a `<engine>-<runtime>` service with `profiles: [<runtime>]` to every engine compose file (image, devices, flags). Engine: add `compose/models/<engine>/docker-compose.yml` with an `x-<engine>` anchor, one service per runtime, neutral container variables, a healthcheck that only turns healthy once every model is available, and an `<engine>` block in the entries of `models.json` (declared in both catalogue schemas).
2. Mirrors: `AI_RUNTIMES` / `AI_ENGINES` in `packages/cli/src/schemas/config.ts`, the `Options:` comments in the root `.env.template`, the enum in `compose/models/models.schema.json`, SPEC.md (configuration block, engines table).
3. `modelProjects()` in `packages/cli/src/commands/tilt.ts`: the engine branch that builds the inline override and resource names, with a case in `tests/tilt.test.ts`; `vllmEndpoint()` / `vllmContainerName()` in `packages/cli/src/utils/models.ts` when the endpoint shape differs.
4. Validate: `pnpm run lint`; `(cd compose/models/<engine> && docker compose --profile <runtime> config)` with `VLLM_MODEL=…` or `OLLAMA_PULL_MODELS=…` set; CLI typecheck + build + test; `tilt alpha tiltfile-result -v`.

## Validation commands

```bash
pnpm run lint                                   # the lint script of compose/package.json: dclint + lint:env + lint:healthcheck
docker compose -f compose/<group>/<service>/docker-compose.yml config
(cd compose/n8n && docker compose -f docker-compose.<variant>.yml config)
(cd compose/models/<engine> && docker compose --profile <runtime> config)
tilt alpha tiltfile-result -v                   # evaluates the Tiltfile without starting anything
pnpm run setup && pnpm run verify               # after adding a .env.template
```
