# AGENTS.md

**self-hosted-ai-starter-kit v2**: a Docker Compose service catalogue that runs n8n (`dev`, `build`, `community` or `enterprise` variant) with local AI models served by Ollama or vLLM, orchestrated for development by Tilt, plus the `n8n-starter` CLI for setup and configuration. [SPEC.md](SPEC.md) is the single source of truth for architecture and rules: update it in the same change whenever a rule, a default or a mirrored value changes. [README.md](README.md) is the human-facing guide.

## Layout

```text
Tiltfile                    # Tilt orchestration: loops over the plan of `n8n-starter tilt resources`; reads the root .env
.env.template -> .env       # N8N_VARIANT, AI_RUNTIME, AI_ENGINE, AI_GATEWAY, AI_MODELS, DOMAIN (pnpm run config; AI_MODELS also pnpm run models select)
compose/                    # one compose project per service directory, .env.template and .env.secrets.json beside it when needed
  package.json              # n8n-service-catalogue: the lint scripts, .dclintrc (linter rules) beside it
  proxy/ n8n/ storage/ services/ models/
  models/models.json        # the model catalogue, one DNS-label id per entry (models.schema.json for editors)
packages/cli/               # n8n-starter: setup, verify, config, models, secrets, tilt, reset (TypeScript, tsdown -> dist/index.mjs)
assets/                     # images, icons (vscode-icons custom folder icons), videos: static assets
.mcp.json                   # the n8n docs MCP server (n8n-docs) for Claude Code; .vscode/mcp.json mirrors it for VS Code
.claude/skills/             # develop (workflow, mirrors, router, rule sheets) and n8n-docs (product lookups)
.volumes/                   # bind-mounted runtime data, gitignored
.github/workflows/ci.yml    # runs lint, build, test
```

pnpm 10 monorepo (`packageManager` in `package.json`), workspace `packages/*`, Node 24 in CI.

## Command palette

| Purpose | Command |
| --- | --- |
| Install and build the CLI | `pnpm install`, then `pnpm -r run build` (= `pnpm run build`). The root scripts and the Tiltfile run `packages/cli/dist/index.mjs`, so rebuild after every CLI change. |
| CLI operations | `pnpm run setup` (create missing `.env` files and the docker networks), `pnpm run config [KEY] [value]` (edit one key of the root `.env`: no key asks which, a key prompts it, key and value write without a prompt; `AI_MODELS` runs `models select`), `pnpm run models select [ids]` (`AI_MODELS`: multi-select, or ids without a prompt), `pnpm run models read [filter] [--json]` (the catalogue as `key=value` blocks per engine and model, `--json` an array of `{ engine, id, model, label, … }`), `pnpm run secrets read [filter] [--json]` (the secrets of the `.env` files, an exact key prints only its value, `--json` an array of `{ file, key, value, source }`), `pnpm run secrets set KEY [value]` (one human or generated secret, masked prompt without a value), `node packages/cli/dist/index.mjs tilt resources` (the Tilt plan as JSON), `pnpm run verify [--json]` (read-only check of the tool versions, `.env` files, secrets and networks, exit 1 when incomplete; `--json` the report `{ ok, success, info, warnings, errors, hints }` the Tiltfile gates on), `pnpm run reset` (delete generated `.env` files, asks first), `pnpm run cli <command> [sub-command] [value] [options]` (the bare CLI with everything after `cli` as its arguments, e.g. `pnpm run cli --help`) |
| Dev orchestration | `pnpm run dev` = `tilt up; tilt down`: interactive and starts containers, leave it to the user. Read-only Tiltfile check: `tilt alpha tiltfile-result -v` |
| Quality checks | `pnpm run lint` (= `pnpm -r run lint`: dclint with warnings as failures plus `lint:env` and `lint:healthcheck` from `compose/`, the last one needs `docker compose` and `jq`), `pnpm run lint:fix` (may rewrite unrelated compose files: revert those), `pnpm -r run build`, `pnpm -r run test` (vitest), `pnpm --filter n8n-starter-cli run typecheck` |
| Compose by hand | `docker compose -f compose/<group>/<service>/docker-compose.yml config`; n8n variants from `compose/n8n/` with `docker compose -f docker-compose.<variant>.yml …` (`DOMAIN` defaults to `n8n.localhost`); model engines from `compose/models/<engine>/` with `--profile <runtime>` |

## Guardrails

- After editing any Docker Compose file, run `pnpm run lint` (and `docker compose -f <file> config`) before finishing.
- After modifying CLI source in `packages/cli`, run `pnpm --filter n8n-starter-cli run typecheck`, `pnpm -r run build` and `pnpm -r run test`, then exercise the built command (`node packages/cli/dist/index.mjs --help`, `… <command> --help`, `… verify`).
- Make surgical changes only. No unprompted refactoring, no "fixing" of the known deviations listed in the develop skill, no reformatting of files you did not need to touch.
- Compose rules, one line each: images pinned to exact versions; only the external networks `n8n-starter-public` (traefik-routed) and `n8n-starter-private`, never a network of your own; expose through the label `traefik.enable=true`, no host ports unless a tool needs direct access; a healthcheck on every service, declared in the compose file (`lint:healthcheck` fails without one); `${VAR:?}` only for secrets and pinned versions, `${VAR:-default}` otherwise, never a bare `${VAR}`; required keys live in the `.env.template` next to the file, knobs there commented out with their default; a secret is an empty key in the template, declared in the `.env.secrets.json` beside it (`generate`, `prompt` or `link`), never a value; anchors never cross files; comments are one line pointing to SPEC.md.
- Never write a model name into a compose file; `tilt resources` builds the model overrides from `compose/models/models.json` and the Tiltfile only loops over its plan. The catalogue `id` is a DNS label and the docker names are `<engine>-<id>`; never normalise or derive a name from anything else.
- Variant, runtime, engine, gateway and model lists are mirrored (CLI schemas, root `.env.template`, `models.schema.json`, SPEC.md) and change together; the first entry is the default everywhere, except `AI_GATEWAY`, which is empty (none) by default. The Tilt topology (compose projects, deps, links, `auto_init`, what each variant enables) lives in `packages/cli/src/commands/tilt.ts`, not in the Tiltfile.
- `setup` never overwrites an existing `.env` value or network (it only fills empty secrets and keeps links equal to their source); the Tiltfile never creates infrastructure; `verify --json` prints one report and nothing else because the Tiltfile gates on it (`fail()` with its errors and hints, `warn()` for its warnings), and `verify --log-level error` stays silent on success.
- Never write or explain an n8n setting (environment variable, feature flag, edition-gated feature) you have not confirmed through the `n8n-docs` MCP server; cite the documentation page in the report.
- `.env` files, `.volumes/` and `dist/` are gitignored; never commit them. Do not commit at all: the maintainer commits.
- Reference other files by a relative path from the referencing file so IDEs can open them.

## Looking things up

- n8n product questions (what a variable does, how a feature or node works, queue mode, task runners, licensing, the public API, the n8n CLI, the instance MCP server, release notes) go to the `n8n-docs` MCP server registered in [.mcp.json](.mcp.json), never to memory. The [n8n-docs skill](.claude/skills/n8n-docs/SKILL.md) holds the lookup routine, the fallbacks and a reference sheet for the API, the CLI and the MCP server.
- Tilt: [docs.tilt.dev](https://docs.tilt.dev/api.html). Compose mechanics: the [Compose specification](https://docs.docker.com/reference/compose-file/). Lint rules: [dclint](https://github.com/zavoloklom/docker-compose-linter) and [compose/.dclintrc](compose/.dclintrc).
- Repository rules: [SPEC.md](SPEC.md) first, then the rule sheets of the `develop` skill.

## Progressive disclosure

For anything beyond a one-line fix, load the `develop` skill ([.claude/skills/develop/SKILL.md](.claude/skills/develop/SKILL.md)) first. It holds the workflow, the list of mirrored values, a router from task type to the detailed rule sheets ([compose catalogue](.claude/skills/develop/resources/compose-catalogue.md), [n8n-starter CLI](.claude/skills/develop/resources/n8n-starter-cli.md)) and the validation commands per task. Load the `n8n-docs` skill ([.claude/skills/n8n-docs/SKILL.md](.claude/skills/n8n-docs/SKILL.md)) for any n8n question and whenever a task touches `compose/n8n/`.
