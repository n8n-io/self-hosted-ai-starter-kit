# Model servers and the gateway at runtime

Rules behind these entries: [SPEC.md](../../../../SPEC.md), section "`compose/models/` engines and the model catalogue". Editing the catalogue or an engine compose file follows the [compose-catalogue](../../compose-catalogue/SKILL.md) skill. Paths are relative to the repository root.

| Symptom | Cause | Action |
| --- | --- | --- |
| a vLLM container on a CPU runtime crashes on the first request | `v0.32.0` and later CPU images (vllm issue 61131) | keep `VLLM_VERSION=v0.31.0` in `compose/models/vllm/.env` while that issue is open |
| a vLLM container is killed or does not come up for lack of memory | on CPU it needs its bf16 weights, the runtime overhead, the KV cache and about 2.5 GB for the vision processors free in the Docker VM | compare the `memory` of `pnpm run models read <id>` with the docker memory `pnpm run verify` reports. Lower `VLLM_CPU_KVCACHE_SPACE` (GiB, default `2`) or go text only with `VLLM_EXTRA_ARGS='--limit-mm-per-prompt={"image":0,"video":0}'`, both in `compose/models/vllm/.env` |
| vLLM on CPU refuses to start for lack of free memory although the model would fit | without an absolute KV cache vLLM reserves a share of the memory it sees (`--gpu-memory-utilization`, `0.92`, on CPU the whole Docker VM) and refuses to start unless that share is free | keep `VLLM_CPU_KVCACHE_SPACE` set; do not replace it with a memory share |
| vLLM on CPU is not healthy after the 15 minute `start_period` | the weights are still downloading into `.volumes/models/vllm/huggingface`, or `--skip-mm-profiling` is gone from the CPU `command` (profiling the vision encoder takes over 20 minutes) | check the log for the download; restore the flag |
| n8n shows an empty answer, the API returns `content: null` | a `--reasoning-parser` was added in the catalogue `args` or in `VLLM_EXTRA_ARGS` | remove it: the Qwen3.5 entries carry none on purpose |
| vLLM stops with `MODEL is required` | it was started by hand without `VLLM_MODEL`; under Tilt the plan sets `MODEL` | pass `VLLM_MODEL`, `VLLM_MODEL_ARGS` and `VLLM_MODEL_ID`, or start it through Tilt |
| a `/v1` endpoint of vLLM answers 401 | the bearer token is `VLLM_API_KEY` of `compose/models/vllm/.env`; `/health` stays open | send the key |
| a gated Hugging Face model does not download | no token | `pnpm run secrets set HF_TOKEN` |
| the log shows a warning about an unknown `VLLM_*` variable | vLLM warns about every `VLLM_*` variable it does not know | container variables are named neutrally (`MODEL`, `MODEL_ARGS`, `EXTRA_ARGS`): do not add a `VLLM_*` one |
| ollama stays unhealthy | it turns healthy only when `ollama show` succeeds for every model of `AI_MODELS`; the pull runs in the background of `ollama serve` (`start_period: 15m`) | wait for the pull, the weights persist in `.volumes/models/ollama` |
| changing `AI_MODELS` restarted ollama, or added and removed vllm containers | the list is part of the rendered configuration | expected |
| LiteLLM does not serve a model that was just selected | the proxy is recreated only when its `n8n-starter.config-hash` label changes, which a Tilt reload does after `models select`, an `AI_ENGINE` change or an edited model name; started by hand its `model_list` is empty | let Tilt reload, or add the model in the LiteLLM UI |
| LiteLLM gets 401 from a vLLM container | `VLLM_API_KEY` in `compose/models/litellm/.env` is a link that went out of step | `pnpm run setup` re-syncs it; `pnpm run verify` reports the mismatch |
| `litellm.<DOMAIN>` shows an API page instead of the dashboard | the host root is the OpenAPI page | the dashboard is `litellm.<DOMAIN>/ui` |
| a model answers on its own endpoint but not through n8n | wrong address or key | ollama `http://ollama:11434`; vllm `http://vllm-<id>:8000/v1` with `VLLM_API_KEY`; the gateway `http://litellm:4000/v1` with `LITELLM_MASTER_KEY` and the catalogue id as the model name. `pnpm run models select` prints them |
