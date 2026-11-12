# models

The local AI engines, their shared model catalogue and the gateway in front of them. `AI_ENGINE` picks one engine directory, `AI_RUNTIME` its compose profile, `AI_MODELS` the catalogue ids that start with the stack and `AI_GATEWAY` an optional gateway directory; no model name lives in a compose file. Rules and the catalogue entries: [SPEC.md](../../SPEC.md#composemodels-engines-and-the-model-catalogue).

| File | Role |
| --- | --- |
| [models.json](./models.json) | the catalogue, one entry per model with a block per engine that serves it; edit with [models.schema.json](./models.schema.json) |
| [ollama/](./ollama/README.md) | one server that pulls every selected model |
| [vllm/](./vllm/README.md) | one container per selected model |
| [litellm/](./litellm/README.md) | the gateway: one endpoint and key for every selected model |

- Pick models: `pnpm run models select`, list them: `pnpm run models read`
- Ollama model library: <https://ollama.com/library>
- Hugging Face model ids for vLLM: <https://huggingface.co/models>
