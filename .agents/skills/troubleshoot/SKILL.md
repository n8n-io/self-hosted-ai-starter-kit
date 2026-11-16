---
name: troubleshoot
description: Runbook for the running stack. Use this skill when a container is unhealthy, restarting or unreachable, Tilt fails to load or reports port 10350 in use, a variant or model change does not apply, a Code node or task runner fails, or a model server (vLLM, Ollama, LiteLLM) crashes, runs out of memory or returns empty answers. Not for static checks (validate).
---

# troubleshoot

Runbook for the stack while it runs. The reasons behind the behaviour are in [SPEC.md](../../../SPEC.md). Entries marked *(unconfirmed)* come from earlier sessions and were not reproduced when this skill was written: confirm them on the first live run and correct the entry.

For a model server or the gateway (vLLM, Ollama, LiteLLM), read [references/model-servers.md](references/model-servers.md).

## Ground rules

- The stack belongs to the user. Never `tilt down` a session you did not start, never run `pnpm run reset`, never delete `.volumes/`, and start `pnpm run dev` (interactive) only when asked.
- If port 10350 is in use, a Tilt session already runs: reuse it. `tilt get uiresources -o name` lists its resources, `tilt logs <resource>` prints a log, `tilt trigger <resource>` re-applies one resource.
- Read before you change: logs and `docker inspect` first.
- `node packages/cli/dist/index.mjs secrets read <KEY>` prints one secret value for piping. Do not paste secret values into a report.
- What n8n is supposed to do is confirmed in the documentation ([n8n-docs](../n8n-docs/SKILL.md) skill), not assumed.

## Finding a container

- A container is named `<project>-<service>-1`: `n8n-n8n-1`, `n8n-n8n-runner-1`, `n8n-n8n-worker-1`, `postgres-postgres-1`, `traefik-traefik-1`. Two set a fixed name: `qdrant`, and `vllm-<id>` per model. `docker ps --format '{{.Names}}\t{{.Status}}'` lists them with their health.
- On the docker networks a service answers to its compose service name (`n8n`, `postgres`, `redis`, `litellm`), ollama to the alias `ollama`, a vllm model to `vllm-<id>`.
- From the host only traefik (`127.0.0.1:80`), postgres (`5432`) and redis (`6379`) are published. Browsers resolve `*.localhost` themselves; `curl` may need an `/etc/hosts` entry for `n8n.localhost` and the other hostnames.
- A healthcheck probe can be run by hand: `docker exec <container> <probe>; echo $?`.

## Testing a change next to the running stack *(unconfirmed)*

Run the copy under its own project name instead of the `name:` of the compose file, so the test never adopts or recreates the containers Tilt manages: `docker compose -p <name>-test -f <compose file> up -d`, removed with `docker compose -p <name>-test down`. What a second project still shares with the live one, read from the compose files:

- the bind mounts under `.volumes/`: point `VOLUMES_PATH` at a scratch directory;
- published host ports (traefik `80`, postgres `5432`, redis `6379`): a copy of one of those cannot start while the original runs;
- a fixed `container_name` (`qdrant`, `vllm-<id>`): for vllm pass another `VLLM_MODEL_ID`;
- the traefik router names and hostnames of its labels: set another `DOMAIN`.

## Symptoms

| Symptom | Cause | Action |
| --- | --- | --- |
| `pnpm run dev` reports port 10350 in use | an earlier Tilt session is still running | reuse it (`tilt trigger <resource>`); only the user stops it, with Ctrl+C in its terminal |
| Tiltfile error `Cannot find module …/packages/cli/dist/index.mjs` | the CLI bundle is missing; the plan runs before the check that would print `n8n-starter cli is not built` | `pnpm run build` |
| Tiltfile error `The environment is not ready:` with `❌` and `💡` lines | the `verify` gate failed | run the root script each hint names (`pnpm run setup`, `pnpm run secrets set KEY`). A fixed file reloads the Tiltfile by itself; a created docker network does not, so reload Tilt by hand |
| Tiltfile error `AI_MODELS …: not served by <engine> on <runtime>` | the root `.env` lists an id the engine does not serve on the runtime, or the catalogue renamed it | `pnpm run models select` rewrites the list |
| a variant change in the root `.env` did not start or stop services | Tilt kept the old enabled flags on the reload | the Tiltfile warning names the command: `tilt enable --only <resources>` |
| a CLI change has no effect in a root script or in Tilt | `dist/` was not rebuilt | `pnpm run build` |
| containers were recreated after an edit to a per-service `.env` | Tilt reloads on it and recreates exactly the services whose rendered configuration changed | expected |
| `verify` reports `Missing secret`, a link that differs from its source or a hash that does not match its password | an unfilled generated secret (also a deleted `.env.secrets`), or a link or a derived value edited out of step | `pnpm run setup` fills and re-syncs; a human secret needs `pnpm run secrets set KEY` (the license key for `N8N_VARIANT=enterprise`) |
| the n8n sign-in is refused, or the owner's email and password are read-only in the UI | the owner is managed by env: n8n applies `N8N_INSTANCE_OWNER_*` of `compose/n8n/.env` on every start | `pnpm run secrets read n8n` prints the login; change the password with `pnpm run secrets set N8N_INSTANCE_OWNER_PASSWORD` and the email in `compose/n8n/.env`, then n8n is recreated |
| n8n cannot read its stored credentials | `N8N_ENCRYPTION_KEY` changed; its rotation is `never` | only the previous key reads them again |
| postgres rejects a password changed in `.env` | rotation `manual`: the password applies when the data directory is created | the data in `.volumes/storage/postgres` still holds the old one |
| the garage link of the Tilt UI (`web.<DOMAIN>`) does not answer | known deviation of the plan | the router serves `s3web.<DOMAIN>` |
| a secrets button is missing, or one remains for a removed resource | buttons are created only for `tilt up` and `tilt ci` and stay until Tilt restarts | restart Tilt (the user) |
| production webhooks do not arrive at `DOMAIN` in `community` or `enterprise` | in queue mode `n8n-webhook` serves them at `hooks.<DOMAIN>`; main keeps only the test paths | call `hooks.<DOMAIN>` |
| a Python Code node fails in `dev` | the internal task runner is JavaScript only | Python needs the external runner: `build` or a later variant |
| a Code node import is refused | the allowlists of the runner | `NODE_FUNCTION_ALLOW_BUILTIN`, `NODE_FUNCTION_ALLOW_EXTERNAL` (JavaScript), `N8N_RUNNERS_STDLIB_ALLOW`, `N8N_RUNNERS_EXTERNAL_ALLOW` (Python) in `compose/n8n/.env`, `*` for all. Packages the runners image does not ship need an extended image |

## Task runner sidecars (`n8n-runner`, `n8n-worker-runner`)

- The launcher in the sidecar starts a runner on demand and stops an idle one after `N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT` (15 seconds by default), so no runner process between Code node executions is normal ([Set up task runners](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-task-runners)). The healthcheck probes the launcher itself, `/healthz` on port `5680`.
- A runner that never connects: both sides read `N8N_RUNNERS_AUTH_TOKEN` from `compose/n8n/.env`; `n8n-runner` dials `http://n8n:5679`, `n8n-worker-runner` dials `http://n8n-worker:5679`; the broker listens on `0.0.0.0` (`N8N_RUNNERS_BROKER_LISTEN_ADDRESS`).
- More detail in the sidecar log: `N8N_RUNNERS_LAUNCHER_LOG_LEVEL=debug` in `compose/n8n/.env`.
- *(unconfirmed)* The launcher relays what a runner writes to stderr as `ERROR` lines. An `ERROR` in the sidecar log is therefore not by itself a failure: read the message.
- *(unconfirmed)* To watch a runner start outside the stack, run the image by hand as the n8n documentation does, on the private network and with the mounted launcher config: `docker run --rm -it --network n8n-starter-private -e N8N_RUNNERS_AUTH_TOKEN=<token> -e N8N_RUNNERS_TASK_BROKER_URI=http://n8n:5679 -e N8N_RUNNERS_LAUNCHER_LOG_LEVEL=debug -v "$PWD/compose/n8n/n8n-task-runners.json:/etc/n8n-task-runners.json:ro" n8nio/runners:<N8N_VERSION>`.
