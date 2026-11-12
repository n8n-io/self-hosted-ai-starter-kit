# ollama

[Ollama](https://ollama.com/) serves open models through a local API. With `AI_ENGINE=ollama` one server pulls every model of `AI_MODELS` on start and n8n reaches it at `http://ollama:11434` on `n8n-starter-private`; it auto-starts when `AI_MODELS` lists a model. One compose service per `AI_RUNTIME`, all on the same image except AMD GPUs, which use the `-rocm` tag. Engines and the catalogue: [SPEC.md](../../../SPEC.md#composemodels-engines-and-the-model-catalogue); pinned version: [.env.template](./.env.template).

- Homepage: <https://ollama.com/>
- Repository: <https://github.com/ollama/ollama>
- Docker image: <https://hub.docker.com/r/ollama/ollama>
- Documentation: <https://docs.ollama.com/>
- API reference: <https://docs.ollama.com/api>
- Model library: <https://ollama.com/library>
- Releases: <https://github.com/ollama/ollama/releases>
