# AGENTS.md

**self-hosted-ai-starter-kit v2**: a Docker Compose service catalogue that runs n8n (`dev`, `build`, `community` or `enterprise` variant) with local AI models served by Ollama or vLLM, orchestrated for development by Tilt and configured by the `n8n-starter` CLI. [SPEC.md](SPEC.md) is the single source of truth for architecture and rules; [README.md](README.md) is the human-facing guide.

## Layout

```text
Tiltfile                     # loops over the plan of `n8n-starter tilt resources`, gated by `verify --json`
.env.template -> .env        # N8N_VARIANT, AI_RUNTIME, AI_ENGINE, AI_GATEWAY, AI_MODELS, DOMAIN
compose/<group>/<service>/   # one compose project per directory: proxy, n8n, storage, services, models
compose/models/models.json   # the model catalogue, one DNS-label id per entry
packages/cli/                # n8n-starter (TypeScript, tsdown -> dist/index.mjs)
.agents/skills/              # task guidance, see Skills
.volumes/                    # runtime data, gitignored
```

pnpm 10 workspace (`packages/*` and `compose`), Node 24.

## Commands

| Purpose | Command |
| --- | --- |
| Install and build the CLI | `pnpm install`, `pnpm run build` |
| Lint the compose catalogue | `pnpm run lint` |
| Test and typecheck the CLI | `pnpm run test`, `pnpm --filter n8n-starter-cli run typecheck` |
| Validate one compose file | `docker compose -f compose/<group>/<service>/docker-compose.yml config --quiet` |
| Evaluate the Tiltfile, starting nothing | `tilt alpha tiltfile-result -v` |
| Check tool versions, `.env` files, secrets, networks | `pnpm run verify` |
| Create missing `.env` files, secrets and networks | `pnpm run setup` |
| Edit the root `.env` without a prompt | `pnpm run config <KEY> <value>`, `pnpm run models select <ids>` |
| Everything else the CLI does | `pnpm run cli --help` |

`pnpm run dev` (`tilt up; tilt down`) is interactive and starts containers: leave it to the user. `pnpm run reset` deletes every generated `.env`: never run it in the user's checkout.

## Rules

- Make the smallest change that satisfies the request: no unprompted refactoring or reformatting, no fixing of the known deviations listed in the `compose-catalogue` skill.
- The root scripts and the Tiltfile run `packages/cli/dist/index.mjs`: run `pnpm run build` after every CLI source change.
- A value that lives in several files changes in all of them in one go: see the [mirrors](.agents/skills/compose-catalogue/references/mirrors.md). The first list entry is the default everywhere, except `AI_GATEWAY`, which is empty.
- Update SPEC.md in the same change when a rule, a default or a mirrored value changes, and the template comments, Tiltfile comments, `packages/cli/README.md` and README.md when they describe what changed.
- Compose: images pinned to exact versions; only the external networks `n8n-starter-public` (traefik-routed) and `n8n-starter-private`; expose through the label `traefik.enable=true`, not host ports; a healthcheck on every service; `${VAR:?}` only for secrets and pinned versions, `${VAR:-default}` otherwise, never a bare `${VAR}`; a secret is an empty key in `.env.template` declared in the `.env.json` beside it, never a value.
- No model name in a compose file: `tilt resources` builds the model overrides from `models.json`. A catalogue `id` is a DNS label and docker names are `<engine>-<id>`; never derive or normalise a name.
- The Tilt topology lives in `packages/cli/src/commands/tilt.ts`: the Tiltfile only loops over that plan and never creates infrastructure. `setup` never overwrites an existing `.env` value or network.
- `verify --json`, `tilt resources`, `models read` and `secrets read` write their result to stdout and nothing else: the Tiltfile and pipes parse it.
- Never write or explain an n8n setting from memory: confirm it through the `n8n-docs` MCP server ([.mcp.json](.mcp.json)) and cite the page.
- Do not commit: the maintainer commits. `.env`, `.env.secrets`, `.volumes/` and `dist/` are gitignored.
- Reference other files by a path relative to the referencing file.
- Before reporting a change as done, run the gates of the `validate` skill and report each result as it was.

## Skills

Task guidance lives in `.agents/skills/<name>/SKILL.md`. Load the matching skill before starting; an agent that does not discover that directory reads the file itself. Skills cite the SPEC.md section behind a rule: read it before changing that rule. SPEC.md wins over a skill: fix the skill when they disagree. `.claude/skills/` holds a symlink per skill for Claude Code.

| Skill | Load it when |
| --- | --- |
| [compose-catalogue](.agents/skills/compose-catalogue/SKILL.md) | touching anything under `compose/`: services, n8n variants, models, env keys, secrets, routing |
| [tilt](.agents/skills/tilt/SKILL.md) | editing the `Tiltfile` or the Tilt plan, or a Tilt reload misbehaves |
| [n8n-starter-cli](.agents/skills/n8n-starter-cli/SKILL.md) | changing TypeScript in `packages/cli/` |
| [n8n-docs](.agents/skills/n8n-docs/SKILL.md) | answering an n8n product question, or touching `compose/n8n/` |
| [n8n-upgrade](.agents/skills/n8n-upgrade/SKILL.md) | bumping `N8N_VERSION` |
| [validate](.agents/skills/validate/SKILL.md) | a change is ready to be checked or reported |
| [troubleshoot](.agents/skills/troubleshoot/SKILL.md) | a container, the Tilt session or a model server misbehaves at runtime |

Keep this file under 80 lines and 5.5 KB: guidance for one kind of task belongs in a skill.
