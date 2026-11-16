---
name: compose-catalogue
description: Rules and recipes for the Docker Compose service catalogue. Use this skill before adding or editing anything under compose/, even one line, such as a compose file, .env.template, secrets manifest, traefik route, n8n variant, model catalogue entry, engine, runtime or gateway. Not for packages/cli (n8n-starter-cli) or Tilt (tilt).
---

# Compose catalogue

Operational rules for everything under `compose/` and the model catalogue. [SPEC.md](../../../SPEC.md) holds the reasoning and wins when the two disagree; cite its section in file comments instead of repeating it. Paths are relative to the repository root.

Read the reference the task needs, not all of them:

| Reference | Read it when |
| --- | --- |
| [references/service-directory.md](references/service-directory.md) | adding a service, or touching what a service directory holds: its README, `.env.template`, config files, data path |
| [references/env-and-secrets.md](references/env-and-secrets.md) | adding, renaming or removing an environment variable or a secret, in the root or in a service template |
| [references/networks-routing.md](references/networks-routing.md) | changing ports, network membership, traefik labels or routes |
| [references/n8n-variants.md](references/n8n-variants.md) | touching `compose/n8n/` or adding a variant; every n8n setting also goes through the [n8n-docs](../n8n-docs/SKILL.md) skill |
| [references/models.md](references/models.md) | touching `compose/models/`: catalogue entries, engine compose files, runtimes, the gateway |
| [references/mirrors.md](references/mirrors.md) | adding, renaming or removing a value that exists in more than one file |

## Checklist for every compose edit

- [ ] Image tag pinned to an exact version, literally or via `${VAR:?}` from `.env` (`N8N_VERSION`, `OLLAMA_VERSION`, `VLLM_VERSION`, `QDRANT_VERSION`). No floating tag (`latest`, a bare major) and no pinned version with a `:-` default.
- [ ] Only the external networks `n8n-starter-public` and `n8n-starter-private`, both declared `external: true`. A compose file never creates a network of its own or declares one with a driver.
- [ ] A service on `n8n-starter-public` carries `traefik.enable=true`, and the other way round. No host `ports:` for a routed service; host ports only where a tool needs direct access (postgres `5432`, redis `6379`). Traefik itself binds `127.0.0.1:80` only, never `0.0.0.0`.
- [ ] Every service has a `healthcheck` in the compose file: `lint:healthcheck` fails without one. Inherited through `extends` or an anchor counts; an image `HEALTHCHECK` or a disabled one does not. Probe with a tool the pinned image ships: `wget` or `curl`, the service's own CLI (`/garage status`), or bash `/dev/tcp` (`qdrant`). Try the probe in the container before writing it down: `docker exec <container> <probe>; echo $?`.
- [ ] `depends_on: { <svc>: { condition: service_healthy } }` only between services of one project. Never `depends_on` a service of another project: they are separate compose projects, Tilt `resource_deps` and the restart policy cover start order.
- [ ] `security_opt: [no-new-privileges=true]` where the image allows it. The docker socket is mounted read-only into `docker-socket-proxy` only, never into traefik.
- [ ] Shared config is factored into `x-*` anchors within a file. Anchors never cross files: cross-file reuse is `extends` (the n8n cascade) or `.env` variables only.
- [ ] `${VAR:-default}` for optional settings (the default lives in the compose file, the template shows the knob commented out); `${VAR:?}` for values that must come from `.env`, never for an optional knob. Never a bare `${VAR}`, `$VAR` or `environment: - VAR` (`lint:env` fails on the first two), never a literal credential or an absolute host path. The one exception: vllm checks `MODEL` at container start, because Tilt sets container variables, not interpolation ones.
- [ ] Runtime data never lives in the service directory: bind mounts go to `${VOLUMES_PATH:-<relative path to .volumes>}/<group>/<service>/…`.
- [ ] No model name in a compose file, no model-specific flag in `command`, no runtime flag in the catalogue `args`.
- [ ] Comments stay one line and point to where the reasoning lives (`see ../../SPEC.md`), with a path relative to the file. No multi-line comment repeating SPEC.md.
- [ ] No `version:` key: `no-version-field` is the only dclint rule switched off in `compose/.dclintrc`.

## Naming

- Directory name = compose project `name:` = compose service name = traefik host label (`<service>.<DOMAIN>`). Exceptions today: `redis-insight/` runs the project and service `redisinsight`, `garage/` also runs `garage-webui`, `litellm/` also runs `litellm-db`.
- Model engine services are `<engine>-<runtime>` (`ollama-cpu-arm64`, `vllm-gpu-nvidia`, …), one per `AI_RUNTIME`, each in the compose profile of the same name.
- A vllm model is addressed everywhere (Tilt resource, compose project, `container_name`, hostname) by `vllm-<id>`, the `id` of its catalogue entry (`vllm-qwen3-5-0-8b`), the same value as in `AI_MODELS`. Nothing normalises or derives a name.
- YAML anchors are named after what they configure (`x-n8n-env-queue`, `x-n8n-env-license`, `x-n8n-env-runners-broker`), never after a variant.

## Known deviations (do not fix unprompted)

The current files deviate from the rules above in places. Mention them when relevant; do not clean them up without being asked:

- Not exactly pinned: `postgres:17`, `redis:8-alpine` and `qdrant/qdrant:${QDRANT_VERSION:?}` with `v1.19` in the template.
- No `no-new-privileges`: traefik, postgres, redis, pgadmin, redisinsight, garage, garage-webui, qdrant; `vllm-gpu-amd` has only `seccomp=unconfined`.
- A named volume instead of a `.volumes` bind mount: qdrant `qdrant_storage`.
- postgres and redis bind `0.0.0.0`.
- Required (`${VAR:?}`) without being a secret or a pinned version: `POSTGRES_USER`, `DB_POSTGRESDB_USER` and `PGADMIN_DEFAULT_EMAIL`, live in their templates with a placeholder value.
- The Tilt plan (`tiltResources()` in `packages/cli/src/commands/tilt.ts`) links garage as `web.<DOMAIN>` while its router serves `s3web.<DOMAIN>`.

## After the edit

- A new, renamed or removed service, dependency or link also changes the Tilt plan: [tilt](../tilt/SKILL.md) skill.
- Run the gates for what changed and report them: [validate](../validate/SKILL.md) skill. `pnpm run lint` must pass after every compose edit.
- Compose mechanics: the [Compose specification](https://docs.docker.com/reference/compose-file/). Lint rules: [dclint](https://github.com/zavoloklom/docker-compose-linter) and `compose/.dclintrc`.
