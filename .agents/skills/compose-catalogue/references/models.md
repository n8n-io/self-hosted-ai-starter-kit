# Model engines, the catalogue and the gateway

Reasoning, the entries table and every measured number: [SPEC.md](../../../../SPEC.md), section "`compose/models/` engines and the model catalogue". Paths are relative to the repository root.

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

## Rules

- No model name ever lives in a compose file. `tilt resources` (`modelProjects()` in `packages/cli/src/commands/tilt.ts`) builds an inline override of the runtime service from the catalogue and the Tiltfile passes it on (how and why: [tilt](../../tilt/SKILL.md) skill).
- Container variable names are neutral on purpose: `OLLAMA_MODELS` is ollama's own model-directory setting and vLLM warns about every unknown `VLLM_*` variable. The `OLLAMA_PULL_MODELS` / `VLLM_MODEL*` interpolation names exist only for running an engine by hand.
- Every `vllm serve` flag has one home, and the precedence is model < runtime < machine. Runtime-specific flags live in the compose `command` (CPU: `--dtype=bfloat16` and `--skip-mm-profiling`, which keeps vision but skips its start-up profiling, over 20 minutes on CPU, plus the container variable `VLLM_CPU_KVCACHE_SPACE=${VLLM_CPU_KVCACHE_SPACE:-2}`, an absolute KV cache in GiB instead of vLLM's memory share, which depends on the VM size). Model-specific flags live in the catalogue `args` (`--max-model-len`, tool-call parser). Machine-specific flags live in `VLLM_EXTRA_ARGS` of `compose/models/vllm/.env` (container variable `EXTRA_ARGS`), appended last by the entrypoint.
- The Qwen3.5 entries deliberately carry no `--reasoning-parser`: with it a non-thinking answer comes back as `content: null`.
- Per container exactly one service runs: the profile named after `AI_RUNTIME` (`COMPOSE_PROFILES=$AI_RUNTIME` by hand, `profiles=[AI_RUNTIME]` in Tilt). `cpu-arm64` is the default and first wherever runtimes are listed.
- vLLM on CPU loads bf16 weights (about 2.3 GB per billion parameters) plus the KV cache of `VLLM_CPU_KVCACHE_SPACE`, the runtime overhead and about 2.5 GB for the vision processors. The catalogue `memory` is that measured sum (10 GB for the 0.8B, 12 GB for the 2B): a container needs it free in the Docker VM whatever its size. The `memory` estimate is the only guard; no entry is restricted to the GPU runtimes.
- Text only is a machine choice: `VLLM_EXTRA_ARGS='--limit-mm-per-prompt={"image":0,"video":0}'` in `compose/models/vllm/.env` (7.5 GB instead of 10 GB for the 0.8B). The catalogue `args` carry the limit flag only for an entry that is text-only everywhere.
- vLLM `v0.32.0` and later CPU images crash on the first request (vllm issue 61131), hence `VLLM_VERSION=v0.31.0` in the template: check that issue before bumping.
- `AI_MODELS=` (empty) starts no model. Changing it restarts the ollama server with the new list or adds and removes vllm containers.

Engine compose changes (flags, versions, runtime services) touch `compose/models/<engine>/docker-compose.yml`, its `.env.template` and SPEC.md.

## Catalogue entry (`compose/models/models.json`)

One entry per model: `id` (the `AI_MODELS` value and the DNS label of the docker names `<engine>-<id>`, pattern `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, at most 58 characters), `label`, and a block per engine that serves it (`ollama`, `vllm`; at least one) with `model` (engine name: ollama tag or Hugging Face id), optional `memory` (a number of GB, an estimate; `models select` prints `~<GB> GB RAM`, VRAM on a gpu runtime), `note` (a short hint shown after the memory), `runtimes` (only when that engine cannot run the model on some hardware; today unused, memory is never a reason); the vllm block adds `args`. Validated by `packages/cli/src/schemas/models.ts` and, for editors, `compose/models/models.schema.json`; both change together.

## Cloud models of the Assistant (`compose/models/models.cloud.json`)

A second, separate catalogue: the cloud models `config N8N_ASSISTANT` offers. `providers`, each with `id` (what n8n reads before the first slash of `N8N_INSTANCE_AI_MODEL`, pattern `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`), `label` and `models`, each with `id` (the name at the provider, slashes allowed for a nested vendor), `label` and an optional `note`. Validated by `packages/cli/src/schemas/assistant.ts` and, for editors, `compose/models/models.cloud.schema.json`; both change together. Nothing in it is served locally and the Tilt plan does not read it. The first model of the first provider is the default of `N8N_INSTANCE_AI_MODEL` in `compose/n8n/docker-compose.yml` and the commented knob of its template: reorder or rename it only together with both (`tests/assistant.test.ts` compares them). Adding a model is one entry, taken from the n8n documentation (n8n-docs skill), not from memory.

## The gateway (`AI_GATEWAY`, today `litellm`)

- The compose file declares the config `litellm-config` with an empty `model_list`, mounted at `/app/config.yaml`; the plan replaces its `content` (`gatewayProjects()`, [tilt](../../tilt/SKILL.md) skill). Never a model name in the compose file.
- It holds the key of every engine it calls as a `link` in its `.env.json` (`VLLM_API_KEY` of `compose/models/vllm`).

## Recipes

Each ends with the gates of the [validate](../../validate/SKILL.md) skill for the files touched; the Tilt plan steps follow the [tilt](../../tilt/SKILL.md) skill.

### Add a model

1. Add one entry to `compose/models/models.json` with its `id` (a DNS label, e.g. `qwen3-5-0-8b`), its `label` and a block per engine that serves it: the engine's `model` name, its `memory` as a number of GB and a `note` when a runtime needs a setting; the vllm block needs `args`; add `runtimes` to a block only when that engine does not run the model everywhere.
2. If the entry shape changes, update `packages/cli/src/schemas/models.ts`, `compose/models/models.schema.json` and `modelOptions()` in `packages/cli/src/utils/models.ts` together.
3. SPEC.md: the entries table of the models section.
4. Check: `tests/models.test.ts` passes; `pnpm run models read <id>` prints the entry, and the `pnpm run models select` prompt shows it (disabled on runtimes it cannot run); the Tiltfile evaluates with the id in `AI_MODELS`.

### Add a gateway

1. Add `compose/models/<gateway>/docker-compose.yml` like any service (recipe "add a service", steps 1 to 3), with the model list as a top-level `configs` entry whose `content` an override can replace, and a link in its `.env.json` for every engine key it needs.
2. Mirrors: `AI_GATEWAYS` in `packages/cli/src/schemas/config.ts` (empty stays the default), the `Options:` comment of `AI_GATEWAY` in the root `.env.template`, `GATEWAYS` in `packages/cli/src/utils/models.ts` (endpoint and key), SPEC.md (configuration block, gateway table).
3. `gatewayProjects()` in `packages/cli/src/commands/tilt.ts`: the project, enabled by its `AI_GATEWAY` value, with the model list built from the catalogue, and a case in `tests/tilt.test.ts`.
4. Check: the Tiltfile evaluates with the gateway set in the root `.env`.

### Add a runtime or engine

1. Runtime: add a `<engine>-<runtime>` service with `profiles: [<runtime>]` to every engine compose file (image, devices, flags). Engine: add `compose/models/<engine>/docker-compose.yml` with an `x-<engine>` anchor, one service per runtime, neutral container variables, a healthcheck that only turns healthy once every model is available, and an `<engine>` block in the entries of `models.json` (declared in both catalogue schemas).
2. Mirrors: `AI_RUNTIMES` / `AI_ENGINES` in `packages/cli/src/schemas/config.ts`, the `Options:` comments in the root `.env.template`, the enum in `compose/models/models.schema.json`, SPEC.md (configuration block, engines table).
3. `modelProjects()` in `packages/cli/src/commands/tilt.ts`: the engine branch that builds the inline override and resource names, with a case in `tests/tilt.test.ts`; `vllmEndpoint()` / `vllmContainerName()` in `packages/cli/src/utils/models.ts` when the endpoint shape differs.
4. Check: the compose config of every engine file touched with the profile of the new runtime; `pnpm run config <KEY> <value>` accepts the new value.
