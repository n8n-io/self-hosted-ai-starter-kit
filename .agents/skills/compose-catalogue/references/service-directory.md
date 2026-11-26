# Service directory

What a directory `compose/<group>/<service>/` holds, and how to add one. Reasoning: [SPEC.md](../../../../SPEC.md), section "`compose/`". Paths are relative to the repository root.

## Contract

| File | Rule |
| --- | --- |
| `docker-compose.yml` | Required. Top-level `name:` equals the directory name, so every service is its own compose project. |
| `README.md` | Required. Title = directory name; one or two sentences (what it is, its role and start behaviour in this kit, a relative link to the SPEC.md section and the `.env.template`); then links labelled Homepage, Repository, Docker image (one per pulled image), Documentation, API reference, Releases, in that order, omitting labels without a page. A bundled second image (`garage-webui`, `litellm-db`) gets a `## <service>` block with its Repository and Docker image. A directory with variants or runtime flavours (`n8n`, `ollama`, `vllm`) lists them in one line each and links the canonical table in SPEC.md. No features, configuration or deployment text. |
| `.env.template` | Only when the service needs `${VAR:?}` values or has a knob a developer is expected to change. `setup` copies it to `.env` next to it and never overwrites. A service without such values has no template. What goes in and how it is laid out: the env-and-secrets reference. |
| `.env.json` | Only when the template has secret keys, one entry per key: the env-and-secrets reference. `setup` writes the secrets into the `.env`, and those no container reads into a `.env.secrets` beside it (both gitignored). |
| Config files | Mounted into the container from the directory (`traefik.yml`, `garage.<DOMAIN>.toml`, `server.json`, `n8n-task-runners.json`, …). |
| Runtime data | Never in the directory. It sits in `.volumes/<group>/<service>/…` at the repo root, reached as `${VOLUMES_PATH:-<relative path to .volumes>}/<group>/<service>/…` (three `../` from a service directory, two from `compose/n8n/`). `VOLUMES_PATH` always names the `.volumes` root, never a service folder. |

Groups: `proxy` (edge), `n8n` (the application, a variant cascade instead of one file, with the service directory `assistant/` beside it: the sandbox and web search of the n8n Assistant, one `../` deeper than the cascade for `VOLUMES_PATH`), `storage` (data stores and their admin UIs), `services` (qdrant), `models` (the catalogue plus one directory per engine and per gateway: `litellm`, and `models.cloud.json`, the cloud models of the Assistant). A new group also needs `COMPOSE_GROUPS` in `packages/cli/src/schemas/tilt.ts`, which the Tilt labels are validated against.

## Recipe: add a service

1. Create `compose/<group>/<service>/docker-compose.yml` with `name: <service>`, a pinned image, a healthcheck, `security_opt`, the right network(s) declared `external: true`, `traefik.enable=true` or no ports, and data under `${VOLUMES_PATH:-../../../.volumes}/<group>/<service>/…`. Check it against the checklist in [SKILL.md](../SKILL.md).
2. Add `.env.template` next to it only for `${VAR:?}` values and dev knobs, and a `.env.json` when one of them is a secret.
3. Add `README.md` next to it following the contract above (copy a neighbour, e.g. `compose/services/qdrant/README.md`), and check every URL resolves.
4. Register it in the Tilt plan: `tiltResources()` in `packages/cli/src/commands/tilt.ts` gets a `project([composeFile('<group>', '<service>')], [resource('<service>', ['<group>'], { links or infer_links: false, resource_deps, auto_init: false if optional, enabled per variant })])`, and `tests/tilt.test.ts` the expected names. No test notices a service that is missing from the plan, unless it has a `.env.json`. Conventions: [tilt](../../tilt/SKILL.md) skill.
5. SPEC.md: repository tree, network membership table, Tilt resource lists; README.md "What's included" when user-facing.
6. Gates: the compose, template and Tilt plan rows of the [validate](../../validate/SKILL.md) skill.
