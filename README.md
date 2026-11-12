# Self-hosted AI starter kit

**Self-hosted AI Starter Kit v2** is an open-source Docker Compose service catalogue, curated by n8n, that runs a complete local AI and low-code environment on your own machine: [n8n](https://n8n.io/) with local AI models served by [Ollama](https://ollama.com/) or [vLLM](https://docs.vllm.ai/), plus the storage and supporting services the different n8n variants need. [Tilt](https://tilt.dev/) runs the whole catalogue with one command, and the `n8n-starter` CLI takes care of the configuration.

The strategy and every rule behind the catalogue live in [SPEC.md](./SPEC.md). This page gets you running and tells you where things are.

Looking for v1? Its guide is kept in [README.legacy.md](./README.legacy.md).

## What's included

Grouped like the [compose/](./compose/) directory. Services marked *on demand* are registered in Tilt but only start when you click them in the Tilt UI.

| Group | Services |
| --- | --- |
| `proxy` | [Traefik](./compose/proxy/traefik/README.md) as the edge, routing `<service>.n8n.localhost` to every exposed container, with a read-only [docker-socket-proxy](./compose/proxy/docker-socket-proxy/README.md) |
| `n8n` | [n8n](./compose/n8n/README.md) in one of four variants (`dev`, `build`, `community`, `enterprise`): a single SQLite container in `dev`, postgres and external task runners from `build`, queue-mode workers plus a webhook processor at `hooks.n8n.localhost` in `community` and `enterprise` |
| `storage` | [PostgreSQL](./compose/storage/postgres/README.md) and [pgAdmin](./compose/storage/pgadmin/README.md) (from `build`, pgAdmin on demand); [Redis](./compose/storage/redis/README.md) and [Redis Insight](./compose/storage/redis-insight/README.md) (queue mode, Redis Insight on demand); [Garage](./compose/storage/garage/README.md) S3 storage and its web UI (enterprise, on demand) |
| `services` | [Qdrant](./compose/services/qdrant/README.md) vector store (on demand) |
| `models` | [Ollama](./compose/models/ollama/README.md) **or** [vLLM](./compose/models/vllm/README.md) serving the models of the [catalogue](./compose/models/README.md), today Qwen3.5 in 0.8B, 2B and 4B; optionally the [LiteLLM](./compose/models/litellm/README.md) gateway in front of them (`AI_GATEWAY=litellm`) |

### What you can build

- AI agents for scheduling appointments
- Summarising company PDFs securely, without data leaving your machine
- Smarter Slack bots for enhanced company communications and IT operations
- Private financial document analysis at minimal cost

### What's new in v2

- **One compose project per service** instead of one big file: every service has a pinned image, a healthcheck and its own `.env`.
- **Tilt** starts, watches and tears down the whole stack; services you do not need stay visible and start on demand.
- **Four n8n variants**: a single-container `dev` on SQLite, `build` with postgres and the external task runner, `community` with queue mode, a worker and a webhook processor, `enterprise` with the license and more services on the way.
- **vLLM next to Ollama**, with a shared model catalogue and a hardware runtime setting for Apple silicon, x86 CPUs, NVIDIA and AMD GPUs.
- **The `n8n-starter` CLI** generates every `.env` file with random secrets, creates the docker networks and edits the configuration interactively.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) Engine 25.0 or newer with Docker Compose 2.24 or newer (Docker Desktop keeps both current). The compose files use `healthcheck.start_interval` ([Engine 25.0](https://docs.docker.com/engine/release-notes/25.0/)), `depends_on` with `restart: true` ([Compose 2.17](https://docs.docker.com/reference/compose-file/services/#depends_on)) and the `!override` / `!reset` merge tags.
- [Tilt](https://docs.tilt.dev/install.html) 0.37.7 or newer.
- [Node.js](https://nodejs.org/) 24 or newer and [pnpm](https://pnpm.io/) 10. With Corepack, `corepack enable` picks the pnpm version pinned in [package.json](./package.json).

`pnpm run verify` checks the Node.js, Docker Engine and Docker Compose versions against these minimums (the constants live in [packages/cli/src/utils/requirements.ts](./packages/cli/src/utils/requirements.ts)); Tilt checks its own version when it loads the Tiltfile, and `pnpm install` refuses an older Node.js.
- For the GPU runtimes: the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) for `gpu-nvidia`, or ROCm on Linux (`/dev/kfd`, `/dev/dri`) for `gpu-amd`. The CLI detects both (the `nvidia` runtime in `docker info`, `/dev/kfd` on a Linux host) and the CPU architecture of the docker daemon: `pnpm run setup` writes the fitting `AI_RUNTIME` into a new root `.env`, `pnpm run verify` warns when the configured one differs.
- Memory for the models you select. `pnpm run models select` shows the memory of the Docker VM and the estimated memory of every catalogue entry (RAM on the CPU runtimes, VRAM on the GPU runtimes), pointing out an estimate above the docker memory. Ollama serves 4-bit quantisations that fit a laptop; vLLM on CPU loads bf16 weights (about 2.3 GB per billion parameters) plus a KV cache.

## Quickstart

### 1. Set up and configure

```bash
git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git
cd self-hosted-ai-starter-kit
pnpm install
# build the n8n-starter CLI that the root scripts and Tilt call
pnpm run build
# create a .env next to every .env.template (AI_RUNTIME from the detected platform), fill its secrets and create the n8n-starter-public / n8n-starter-private docker networks
pnpm run setup
# pick one of N8N_VARIANT, AI_RUNTIME, AI_ENGINE, AI_GATEWAY, AI_MODELS or DOMAIN and configure it interactively
pnpm run config
# or name the key, or the key and its value to skip the prompts
pnpm run config N8N_VARIANT enterprise
# pick the models that start with the stack (AI_MODELS), or pass their ids; `pnpm run config AI_MODELS` does the same
pnpm run models select
pnpm run models select qwen3-5-0-8b,qwen3-5-2b
```

`setup` only creates what is missing, so re-running it never touches your edits. `config` edits one key of the root `.env` (generated from [.env.template](./.env.template)) per run and preserves its comments; `pnpm run config <KEY> <value>` writes without a prompt, so scripts and agents can use it too. `models select` does the same for `AI_MODELS` (`config AI_MODELS` runs it), and `pnpm run models read [filter]` prints the catalogue as `key=value` blocks per engine and model (`pnpm run models read vllm`, `--json` for records). Everything else (image versions, credentials, license keys) lives in the `.env` next to the compose file it belongs to, for example [compose/n8n/.env.template](./compose/n8n/.env.template). The secrets in those files are generated by `setup` as declared in the `.env.secrets.json` next to each template; `pnpm run secrets read [filter]` prints them (`pnpm run secrets read vllm`, or an exact key for only its value) and `pnpm run secrets set <KEY>` asks for the ones only you know, such as the enterprise license key. To try any other command, sub-command or flag of the bare CLI, use `pnpm run cli <command> [sub-command] [value] [options]`, for example `pnpm run cli --help` or `pnpm run cli models read vllm --json`.

### 2. Run it with Tilt

```bash
pnpm run dev
```

Tilt prints the configuration, checks that the environment is complete, then starts the services of the selected variant. The Tilt UI is at `http://localhost:10350`; n8n is at `http://n8n.localhost` once it is healthy. Pressing Ctrl+C stops Tilt and removes every container it started (`pnpm run dev` runs `tilt up` followed by `tilt down`); the docker networks, the `.env` files and the data in `.volumes/` stay. Every service that has secrets (n8n, postgres, pgadmin, litellm, vllm) carries a `secrets` button in the Tilt UI that prints them into its log.

Open `http://n8n.localhost` in a browser and create the owner account. Browsers resolve `*.localhost` to your machine on their own; command-line tools such as `curl` may need an `/etc/hosts` entry for `n8n.localhost` and the other hostnames.

### 3. Verify

```bash
pnpm run verify
```

A read-only check that the Node.js, Docker Engine and Docker Compose versions meet the [prerequisites](#prerequisites), that every `.env` file and both docker networks exist and that every secret is filled, the enterprise license key included once `N8N_VARIANT=enterprise`, with exit code 1 otherwise. Tilt runs the same check before starting anything, so an unconfigured checkout fails fast with the list of what is missing.

### Choosing hardware, engine and models

`pnpm run config` replaces the compose profiles of v1:

| v1 | v2 (`pnpm run config`) |
| --- | --- |
| `docker compose --profile gpu-nvidia up` | `AI_RUNTIME=gpu-nvidia` |
| `docker compose --profile gpu-amd up` | `AI_RUNTIME=gpu-amd` |
| Mac / Apple silicon: `docker compose up` | `AI_RUNTIME=cpu-arm64` (the default) |
| `docker compose --profile cpu up` | `AI_RUNTIME=cpu-x86-64` |
| Ollama only | `AI_ENGINE=ollama` or `AI_ENGINE=vllm` |
| Llama 3.2 pulled on start | `AI_MODELS`: `pnpm run models select`, a multi-select over the [catalogue](./compose/models/models.json); empty by default, so no model starts until you pick one |

Models that cannot run on the selected runtime are shown disabled. Ollama pulls every selected model into one server; vLLM runs one container per model. On CPU every vLLM container needs the memory shown by `models select` free in the Docker VM (its weights, a 2 GiB KV cache that `VLLM_CPU_KVCACHE_SPACE` in `compose/models/vllm/.env` changes, and about 2.5 GB for the vision processors); a text-only machine sets `VLLM_EXTRA_ARGS='--limit-mm-per-prompt={"image":0,"video":0}'` in that file and saves those 2.5 GB per container. See the [models section of SPEC.md](./SPEC.md#composemodels-engines-and-the-model-catalogue) for the reasoning.

### Using the models in n8n

- **Ollama**: use the Ollama credential with the base URL `http://ollama:11434`. The models pulled on start, and any you pull later through the API, stay in `.volumes/models/ollama`.
- **vLLM**: use the OpenAI credential with the base URL `http://vllm-<id>:8000/v1` and the `VLLM_API_KEY` of `compose/models/vllm/.env` as the API key (`pnpm run secrets read VLLM_API_KEY` prints it). The id is the `id` of the model's entry in the [catalogue](./compose/models/models.json), the same value as in `AI_MODELS`, for example `http://vllm-qwen3-5-0-8b:8000/v1`. `pnpm run models select` prints the endpoint of every selected model.
- **LiteLLM gateway** (`pnpm run config AI_GATEWAY litellm`): use one OpenAI credential for every model, with the base URL `http://litellm:4000/v1` and the `LITELLM_MASTER_KEY` of `compose/models/litellm/.env` as the API key (`pnpm run secrets read LITELLM_MASTER_KEY` prints it). The model name is the id of `AI_MODELS`, for example `qwen3-5-0-8b`, whichever engine serves it. Its dashboard is at `http://litellm.n8n.localhost/ui`, the link Tilt shows.
- **Ollama running natively on macOS** instead of in Docker: point the credential at `http://host.docker.internal:11434`.

## Architecture

```text
.
├── Tiltfile                  # Tilt orchestration of every compose project
├── .env.template             # N8N_VARIANT, AI_RUNTIME, AI_ENGINE, AI_GATEWAY, AI_MODELS, DOMAIN
├── compose/                  # the service catalogue, one compose project per directory
│   ├── package.json          # n8n-service-catalogue: lint scripts and .dclintrc
│   ├── proxy/                # traefik, docker-socket-proxy
│   ├── n8n/                  # docker-compose.yml (dev) extended by .build.yml, .community.yml and .enterprise.yml
│   ├── storage/              # postgres, pgadmin, redis, redis-insight, garage
│   ├── services/             # qdrant
│   └── models/               # models.json plus ollama/ and vllm/, and the litellm/ gateway
├── assets/                   # images, icons (vscode-icons custom folder icons), static assets
├── packages/cli/             # n8n-starter: setup, verify, config, models, secrets, tilt, reset
└── .volumes/                 # runtime data of every service, gitignored
```

Every service directory holds a `docker-compose.yml` with its own project `name:`, an optional `.env.template` for the values that must come from `.env`, an optional `.env.secrets.json` naming the secrets among them, and the config files it mounts. Runtime data never lives there: it sits under `.volumes/<group>/<service>/`, which `VOLUMES_PATH` can relocate as a whole. The full rules are in [SPEC.md](./SPEC.md#compose).

### n8n variants

`N8N_VARIANT` picks one self-contained compose file in [compose/n8n/](./compose/n8n/); each file extends the previous one, so settings are written once:

| Variant | File | What it adds | Needs |
| --- | --- | --- | --- |
| `dev` | [docker-compose.yml](./compose/n8n/docker-compose.yml) | one n8n container in regular execution mode on SQLite with the internal task runner (JavaScript Code nodes only) | nothing |
| `build` | [docker-compose.build.yml](./compose/n8n/docker-compose.build.yml) | postgres as the database and the external task runner sidecar (Python Code nodes too) | postgres |
| `community` | [docker-compose.community.yml](./compose/n8n/docker-compose.community.yml) | queue mode, an `n8n-worker` with its own task runner, an `n8n-webhook` processor serving production webhooks at `hooks.<DOMAIN>` | redis |
| `enterprise` | [docker-compose.enterprise.yml](./compose/n8n/docker-compose.enterprise.yml) | the license (`N8N_LICENSE_ACTIVATION_KEY` in `compose/n8n/.env`, set with `pnpm run secrets set N8N_LICENSE_ACTIVATION_KEY`); S3 binary data on garage, external secrets and multi-main are still to be wired up | a license key |

Any variant file also runs without Tilt: `docker compose -f docker-compose.<variant>.yml up` from `compose/n8n/` (see [Running a service without Tilt](#running-a-service-without-tilt)).

### Local AI: Ollama or vLLM

`AI_ENGINE` picks the engine, `AI_RUNTIME` the hardware (`cpu-arm64`, `cpu-x86-64`, `gpu-nvidia`, `gpu-amd`) and `AI_MODELS` the catalogue ids that start with the stack:

| Engine | Containers | Reachable at |
| --- | --- | --- |
| `ollama` | one server that pulls every selected model on start; models persist in the volume and n8n can pull more through the API | `http://ollama:11434` on the private network |
| `vllm` | one container per selected model, since a vLLM process serves one model; all containers share one Hugging Face cache | `http://vllm-<id>:8000/v1`, behind `VLLM_API_KEY` |

`AI_GATEWAY=litellm` adds the [LiteLLM](./compose/models/litellm/README.md) gateway in front of either engine: one OpenAI compatible endpoint, `http://litellm:4000/v1` behind `LITELLM_MASTER_KEY`, that serves every model of `AI_MODELS` under its catalogue id, so n8n needs one credential instead of one per vLLM container. It is empty by default, which runs no gateway.

The catalogue [compose/models/models.json](./compose/models/models.json) lists `qwen3-5-0-8b` (the lightweight default for both engines on every runtime), `qwen3-5-2b` (both engines, every runtime) and `qwen3-5-4b` (both engines, every runtime, with the largest memory estimate). Adding a model means adding one catalogue entry with a block per engine that serves it; no model name lives in a compose file.

### Networks and routing

Two external docker networks, created by `pnpm run setup`: `n8n-starter-public` holds Traefik and every container it routes to, `n8n-starter-private` holds everything else (databases, task runners, model servers). Traefik discovers containers through the socket proxy and routes every exposed service at `<service>.<DOMAIN>`; only n8n is served at the bare `DOMAIN`. Traefik binds `80` on `127.0.0.1` only; postgres (`5432`) and redis (`6379`) are the only other published ports.

| URL (with the default `DOMAIN=n8n.localhost`) | Service |
| --- | --- |
| `http://n8n.localhost` | n8n |
| `http://traefik.n8n.localhost` | Traefik dashboard |
| `http://pgadmin.n8n.localhost` | pgAdmin |
| `http://redisinsight.n8n.localhost` | Redis Insight |
| `http://litellm.n8n.localhost/ui` | LiteLLM dashboard (the host root is its OpenAPI page), with `AI_GATEWAY=litellm` |
| `http://s3.n8n.localhost`, `http://s3web.n8n.localhost`, `http://s3ui.n8n.localhost` | Garage S3 API, static web hosting, web UI |

### Configuration

- The root `.env` steers the environment: `N8N_VARIANT`, `AI_RUNTIME`, `AI_ENGINE`, `AI_GATEWAY`, `AI_MODELS`, `DOMAIN`. Edit it with `pnpm run config` (`AI_MODELS` also with `pnpm run models select`) or by hand.
- Each service keeps its own `.env` next to its compose file, generated from the committed `.env.template`, with the secret keys filled by `setup` as the committed `.env.secrets.json` beside it declares (random values once, the n8n copy of the postgres password kept in sync). Only the templates and manifests are committed. `pnpm run secrets read [filter]` prints the secrets, `pnpm run secrets set <KEY>` sets one by hand, the enterprise license key for example.
- `VOLUMES_PATH` moves all runtime data elsewhere, for example `VOLUMES_PATH=/Volumes/ext/n8n pnpm run dev`. It always points at a `.volumes`-style root.
- `pnpm run reset` deletes every generated `.env` after confirmation and keeps the templates. It warns about the secrets the data in `.volumes/` depends on (the n8n encryption key, the postgres password): back them up with `pnpm run secrets read` first or delete `.volumes/` too.

## Upgrading

```bash
git pull
pnpm install
pnpm run build
# adds .env files for new templates and fills new or empty secrets; compare your existing .env files with their templates for other new keys
pnpm run setup
pnpm run dev
```

Image versions are pinned in the per-service `.env` files (`N8N_VERSION` in `compose/n8n/.env`, `OLLAMA_VERSION`, `VLLM_VERSION`, `QDRANT_VERSION`), so bump them there; a running `pnpm run dev` picks the edit up and recreates the containers, like any other change to a per-service `.env`. To start over, run `pnpm run reset` and delete `.volumes/`.

## Development and contributing

All root scripts are thin wrappers, see [package.json](./package.json):

| Script | Runs |
| --- | --- |
| `pnpm run setup`, `verify`, `config`, `models`, `secrets`, `reset` | the matching `n8n-starter` command from [packages/cli/](./packages/cli/) |
| `pnpm run dev` | `tilt up` with the [Tiltfile](./Tiltfile), then `tilt down` once Tilt exits |
| `pnpm run build`, `pnpm run test` | `pnpm -r run build` / `pnpm -r run test` across all workspace packages |
| `pnpm run lint`, `pnpm run lint:fix` | `pnpm -r run lint` / `lint:fix`, the scripts of [compose/package.json](./compose/package.json): [dclint](https://github.com/zavoloklom/docker-compose-linter) over the catalogue with `--max-warnings 0` (warnings fail too), configured in [compose/.dclintrc](./compose/.dclintrc), then `lint:env`, which fails on any bare `${VAR}` in a compose file, and `lint:healthcheck`, which fails on a service without a healthcheck (needs `docker compose` and `jq`) |

### Editing the compose catalogue

Run `pnpm run lint` after every change; it must pass. The rules that keep the catalogue consistent are in the [compose spec rules of SPEC.md](./SPEC.md#compose-spec-rules). In short:

- Pin images to exact versions, either literally or through a `.env` variable.
- Join only the two external networks, never create one; expose through the label `traefik.enable=true` instead of host ports.
- Give every service a healthcheck, with a tool its image ships; use `${VAR:?}` only for secrets and pinned versions and `${VAR:-default}` for everything else, never a bare `${VAR}`. Required values go into the `.env.template` next to the file, optional knobs appear there commented out with their default.
- Keep comments short and point to SPEC.md instead of repeating it.

### The n8n-starter CLI

A small TypeScript CLI in [packages/cli/](./packages/cli/), bundled with [tsdown](https://tsdown.dev/) to `dist/index.mjs` and tested with [vitest](https://vitest.dev/). It must be built before the root scripts and the Tiltfile can call it:

```bash
pnpm run build                                  # bundle
pnpm run test                                   # unit tests
pnpm --filter n8n-starter-cli run typecheck         # tsc --noEmit over sources and tests
node packages/cli/dist/index.mjs --help         # every command and option
```

The commands, options and the practices inside the package are described in [packages/cli/README.md](./packages/cli/README.md) and the [CLI section of SPEC.md](./SPEC.md#n8n-starter-cli-packagescli).

### Running a service without Tilt

Every compose file is a complete project and Tilt is never required. A service needs the two docker networks, the `.env` next to its compose file with its secret keys filled and the services it talks to (n8n needs traefik, and postgres from the `build` variant up); everything else has a default, `DOMAIN` included (`n8n.localhost`):

```bash
# once: the networks and every .env (or `pnpm run setup`, which does the same)
docker network create n8n-starter-public && docker network create n8n-starter-private
cp compose/n8n/.env.template compose/n8n/.env   # and so on for every .env.template, then fill the empty secret keys it lists
# an n8n variant, from compose/n8n/
docker compose -f docker-compose.community.yml up
# another domain, from compose/n8n/ (a shell variable wins over .env and the compose default)
DOMAIN=example.test docker compose -f docker-compose.community.yml up
# a model engine, from compose/models/ollama/ (one service per AI_RUNTIME profile)
OLLAMA_PULL_MODELS=qwen3.5:0.8b docker compose --profile cpu-arm64 up
```

### CI

[.github/workflows/ci.yml](./.github/workflows/ci.yml) runs `pnpm install --frozen-lockfile`, `pnpm run lint`, `pnpm run build` and `pnpm run test` on Node 24 for every pull request and push to `main`.

### Working with coding agents

[AGENTS.md](./AGENTS.md) holds the context and guardrails for coding agents, and the `develop` skill in [.claude/skills/develop/](./.claude/skills/develop/) routes implementation tasks to the detailed rules for the compose catalogue and the CLI.

[.mcp.json](./.mcp.json) (Claude Code) and [.vscode/mcp.json](./.vscode/mcp.json) (VS Code) register the [n8n documentation MCP server](https://docs.n8n.io/connect/connect-to-n8n-docs-mcp-server.md) as `n8n-docs`, so agents look n8n settings and features up in the official docs instead of guessing; Claude Code asks once to approve the project server. The `n8n-docs` skill in [.claude/skills/n8n-docs/](./.claude/skills/n8n-docs/) holds the lookup routine and a reference sheet for the n8n public API, the n8n CLI and the instance MCP server.

## Tips and tricks

- Optional services (pgAdmin, Redis Insight, Qdrant, Garage, and the Ollama server while `AI_MODELS` is empty) are listed in the Tilt UI and start with one click.
- Keep runtime data on another disk with `VOLUMES_PATH=/path/to/volumes pnpm run dev`.
- Another proxy or load balancer in front of Traefik: raise `N8N_PROXY_HOPS` in `compose/n8n/.env` by one per hop.
- More modules in the Code node: set `NODE_FUNCTION_ALLOW_BUILTIN` / `NODE_FUNCTION_ALLOW_EXTERNAL` (JavaScript) and `N8N_RUNNERS_STDLIB_ALLOW` / `N8N_RUNNERS_EXTERNAL_ALLOW` (Python) in `compose/n8n/.env` (comma separated, `*` for all); the defaults are listed in [compose/n8n/.env.template](./compose/n8n/.env.template). Third-party packages beyond the ones the runners image ships need an [extended runners image](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-task-runners#adding-extra-dependencies).
- If `pnpm run dev` reports that port `10350` is in use, an earlier Tilt session is still running: use its UI, or stop it with Ctrl+C in that terminal first.

## Learn more

- [n8n documentation](https://docs.n8n.io/) and the [n8n community forum](https://community.n8n.io/)
- [Tilt documentation](https://docs.tilt.dev/)
- [docker-compose-linter (dclint)](https://github.com/zavoloklom/docker-compose-linter)
- [self-hosted-ai-starter-kit on GitHub](https://github.com/n8n-io/self-hosted-ai-starter-kit)

## Roadmap

- `pnpm run secrets rotate` for the secrets that may change after the first start.
- Grow the model catalogue, for example an embedding model for `gpu-nvidia`.
- Wire up the enterprise variant: binary data on Garage (S3), external secrets, multi-main behind Traefik sticky sessions.
