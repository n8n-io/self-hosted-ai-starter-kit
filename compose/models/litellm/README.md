# litellm

[LiteLLM](https://www.litellm.ai/) is an OpenAI-compatible gateway in front of the model servers, so n8n addresses every model through one endpoint and one key. With `AI_GATEWAY=litellm` it starts next to the engine of `AI_ENGINE` and serves every model of `AI_MODELS` under its catalogue id at `http://litellm:4000/v1` on `n8n-starter-private` (`litellm.<DOMAIN>` from the host), behind `LITELLM_MASTER_KEY`. It ships with its own PostgreSQL 16 database for the UI and the models added there. Rules and the generated model list: [SPEC.md](../../../SPEC.md#composemodels-engines-and-the-model-catalogue). Secrets and knobs: [.env.template](./.env.template).

- Homepage: <https://www.litellm.ai/>
- Repository: <https://github.com/BerriAI/litellm>
- Docker image (pulled from `docker.litellm.ai`): <https://github.com/BerriAI/litellm/pkgs/container/litellm>
- Documentation: <https://docs.litellm.ai/docs/>, in particular [Docker deployment](https://docs.litellm.ai/docs/proxy/deploy)
- API reference: <https://docs.litellm.ai/docs/proxy/user_keys>
- Releases: <https://github.com/BerriAI/litellm/releases>

## litellm-db

- Docker image: <https://hub.docker.com/_/postgres>
