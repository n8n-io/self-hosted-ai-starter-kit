# vllm

[vLLM](https://vllm.ai/) is a high-throughput inference server with an OpenAI-compatible API. With `AI_ENGINE=vllm` one container per model of `AI_MODELS` starts, named `vllm-<id>` and reachable at `http://vllm-<id>:8000/v1` on `n8n-starter-private` behind `VLLM_API_KEY`. One compose service per `AI_RUNTIME`, each on its own image: `vllm-openai-cpu` (`-arm64`, `-x86_64` tags), `vllm-openai` (NVIDIA) and `vllm-openai-rocm` (AMD). Engines and the catalogue: [SPEC.md](../../../SPEC.md#composemodels-engines-and-the-model-catalogue); secrets and knobs: [.env.template](./.env.template).

- Homepage: <https://vllm.ai/>
- Repository: <https://github.com/vllm-project/vllm>
- Docker image (NVIDIA): <https://hub.docker.com/r/vllm/vllm-openai>
- Docker image (CPU): <https://hub.docker.com/r/vllm/vllm-openai-cpu>
- Docker image (AMD): <https://hub.docker.com/r/vllm/vllm-openai-rocm>
- Documentation: <https://docs.vllm.ai/en/latest/>
- API reference: <https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html>
- Releases: <https://github.com/vllm-project/vllm/releases>
