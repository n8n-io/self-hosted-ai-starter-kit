# Networks, routing and ports

Reasoning: [SPEC.md](../../../../SPEC.md), sections "Docker networks" and "Routing". Files: `compose/proxy/traefik/**` and the `networks:` and `labels:` of every compose file. Paths are relative to the repository root.

## Networks

- `n8n-starter-public` holds traefik and every container it routes to (`traefik.enable=true`); `n8n-starter-private` holds everything else. A routed service that also needs a backend joins both.
- Membership today: public only `garage`, `garage-webui`; private only `docker-socket-proxy`, `postgres`, `redis`, `n8n-runner`, `n8n-worker`, `n8n-worker-runner`, `qdrant`, `ollama`, `vllm-*`, `litellm-db`; both `traefik`, `n8n`, `n8n-webhook`, `pgadmin`, `redisinsight`, `litellm`. Update the table in SPEC.md when membership changes.
- Both networks are `external` and created by `pnpm run setup`; a compose file never creates one.

## Routing

- Traefik (`compose/proxy/traefik/traefik.yml`) discovers containers through `docker-socket-proxy` (`tcp://docker-socket-proxy:2375`, read-only: `CONTAINERS=1`, `POST=0`), `exposedByDefault: false`, provider `network: n8n-starter-public`, default rule ``Host(`<compose service>.<DOMAIN>`)``.
- n8n overrides the rule to the bare `DOMAIN` and, in queue mode, `n8n-webhook` to `hooks.<DOMAIN>` with the test paths routed back to main by the `n8n-hooks-test` router; garage declares its own routers (`s3.`, `s3web.`, `s3ui.<DOMAIN>`); the traefik dashboard is `traefik.<DOMAIN>` (`config/dashboard.yml`); model servers are never routed, only the gateway in front of them is, at `litellm.<DOMAIN>`.
- The `web` entrypoint applies the `default@file` middleware chain (compress + security headers) from `config/`. The stack is plain HTTP only; HTTPS is not supported yet.
- `N8N_PROXY_HOPS=1` because traefik is the only proxy in front of n8n; raise it by one per additional proxy.

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
| 4000 | litellm, `http://litellm:4000/v1`, bearer `LITELLM_MASTER_KEY` | no, routed at `litellm.<DOMAIN>` |
| 3900, 3902, 3903, 3909 | garage S3, web, admin API and garage-webui | no, routed through explicit routers |

Everything else is reachable only through traefik at `<service>.<DOMAIN>`.

Gates: the compose and traefik rows of the [validate](../../validate/SKILL.md) skill.
