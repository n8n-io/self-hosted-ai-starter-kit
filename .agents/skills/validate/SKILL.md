---
name: validate
description: The verification gates of this repository and how to report them. Use this skill after any change to compose files, env templates, secrets manifests, models.json, the Tiltfile, packages/cli or the agent docs, before calling work done, and when asked to run the checks, lint or tests or to explain a CI failure.
---

# validate

Run every gate that matches what changed, from the repository root, and report each result as it was. A gate that did not run is reported as not run, never as passing.

## Which gates

| Changed | Gates |
| --- | --- |
| any `docker-compose*.yml` | lint; compose config for every changed file, and for an n8n variant file also for every file that extends it |
| `.env.template`, `.env.secrets.json` | lint; test; compose config for the file beside it; for a new template `pnpm run setup && pnpm run verify`; for a changed secret a `reset`, `setup`, `verify` cycle on a scratch copy |
| `compose/models/models.json`, `models.schema.json` | test; `pnpm run models read <id>`; Tiltfile evaluation with the id in `AI_MODELS` |
| `compose/models/<engine>/docker-compose.yml` | lint; compose config with the profile of every runtime touched |
| `compose/proxy/traefik/**` | lint; compose config for the traefik file |
| `packages/cli/src`, `packages/cli/tests` | typecheck; build; test; the built command |
| the Tilt plan (`src/commands/tilt.ts`, `src/schemas/tilt.ts`) or the `Tiltfile` | typecheck; build; test; the plan; Tiltfile evaluation |
| a new variant, runtime, engine or gateway value | every row above that applies; `pnpm run config <KEY> <value>` accepts it (restore the root `.env` afterwards) |
| an n8n setting in `compose/n8n/` | the compose rows, and the setting confirmed through the [n8n-docs](../n8n-docs/SKILL.md) skill with the page cited |
| `SPEC.md`, `README.md`, `AGENTS.md`, a skill | links resolve from the referencing file; every command named exists in `package.json`; `wc -lc AGENTS.md` within its budget; skill frontmatter is still `name` plus a one-line `description`; every skill has its symlink in `.claude/skills/` |

## The commands

```bash
pnpm run lint  # dclint, lint:env and lint:healthcheck from compose/
docker compose -f <compose file> config --quiet  # a service or an n8n variant file
docker compose -f <engine file> --profile <runtime> config --quiet  # --profile goes before config
pnpm --filter n8n-starter-cli run typecheck
pnpm -r run build  # = pnpm run build
pnpm -r run test  # = pnpm run test
node packages/cli/dist/index.mjs --help  # then the changed command, e.g. `secrets --help`
node packages/cli/dist/index.mjs verify --log-level error  # prints nothing when the environment is complete
out=$(node packages/cli/dist/index.mjs tilt resources --log-level error) || echo "$out"  # the plan: silent on exit 0, the reason on exit 1
tilt alpha tiltfile-result -v > /dev/null  # the Tiltfile, starting nothing: exit 0, or 5 with the reason
```

## Before running them

- `config --quiet` catches interpolation and `extends` errors without printing. Never print a rendered config: it contains the secrets of the `.env` beside the file. It reads that `.env`, so a fresh checkout needs `pnpm run setup` first.
- A required variable the `.env` leaves empty stops that check with `required variable … is missing a value`. `setup` never fills a human secret, so the enterprise file needs it set for the check alone: `N8N_LICENSE_ACTIVATION_KEY=x docker compose -f compose/n8n/docker-compose.enterprise.yml config --quiet`. The model variables of the engine files (`VLLM_MODEL`, `OLLAMA_PULL_MODELS`) default to empty and need nothing.
- `pnpm run lint` is the `lint` script of `compose/package.json`: dclint with `--max-warnings 0`, so every warning fails the gate (rules in `compose/.dclintrc`); then `lint:env`, which fails on a bare `${VAR}` or `$VAR`; then `lint:healthcheck`, which fails, naming file and services, on a service without a healthcheck (it needs `docker compose` and `jq`, no `.env` and no daemon).
- `pnpm run lint:fix` may rewrite unrelated compose files: revert those with `git checkout -- <file>`, after checking that the file held no other uncommitted change.
- Build before exercising the bundle, and run the typecheck locally: CI runs lint, build and test only.
- The CLI writes its log lines to stdout, errors included: discarding stdout of a CLI command hides why it failed, hence the capture above.
- The Tiltfile evaluation needs the built CLI and a complete environment, because it runs the `verify` gate. Its result is about 30 KB of JSON on stdout, which the redirect drops; its log and the reason for a failure are on stderr.
- `dotenv()` in the Tiltfile overrides exported variables. To evaluate another variant, engine or model, change the root `.env` (`pnpm run config N8N_VARIANT build`) and restore the previous value afterwards.
- A running Tilt session watches the root `.env` and reloads the live stack on that edit. `tilt get uiresources -o name` succeeds only while a session runs: when it does, ask before changing the root `.env`.
- `setup` and `verify` are safe on the user's checkout: `setup` only creates what is missing. `reset` deletes every generated `.env`, including secrets the data in `.volumes/` depends on: run a `reset`, `setup`, `verify` cycle on a scratch copy of the repository only.
- `pnpm run dev` is interactive and starts containers. It is not a gate: run it only when the user asks for it.

## Report

One line per gate with the command and its real outcome. For a failure, paste the output that shows it, unchanged (never a rendered compose config).

```text
| Gate | Command | Result |
| lint | pnpm run lint | exit 0 |
| compose config | docker compose -f compose/n8n/docker-compose.build.yml config --quiet | exit 0 |
| Tiltfile | tilt alpha tiltfile-result -v > /dev/null | NOT RUN: tilt is not installed |
```

Then the checklist:

- [ ] Only the files the task needed changed.
- [ ] Every [mirror](../compose-catalogue/references/mirrors.md) of a changed value updated.
- [ ] Every gate of the matching rows ran, and its output is reported as it was.
- [ ] Every n8n setting touched was confirmed through the `n8n-docs` MCP server and the documentation page cited.
- [ ] SPEC.md and the relevant comments and templates updated when a rule or default changed.
- [ ] Nothing committed.
