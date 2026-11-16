---
name: n8n-starter-cli
description: Conventions for the n8n-starter CLI in packages/cli. Use this skill before adding or changing a command, sub-command, flag, prompt, schema, util or test there, or when a root script such as pnpm run setup, verify, config, models or secrets misbehaves. Not needed to run the CLI. The Tilt plan in src/commands/tilt.ts also needs the tilt skill.
---

# n8n-starter CLI

Operational rules for `packages/cli`, the `n8n-starter` CLI that the root scripts (`pnpm run setup|verify|config|models|secrets|reset|cli`) and the [Tiltfile](../../../Tiltfile) call as `node packages/cli/dist/index.mjs <command>`. The section "n8n-starter CLI" of [SPEC.md](../../../SPEC.md) holds the behaviour contract, `packages/cli/README.md` is the package's usage page and `COMMAND_HELP` in `src/help.ts` is what `--help` prints. Paths starting with `src/` or `tests/` are relative to `packages/cli/`.

| Reference | Read it when |
| --- | --- |
| [references/commands.md](references/commands.md) | changing or debugging what one command does, logs or exits with (read only its section) |
| [references/internals.md](references/internals.md) | locating code, or touching the build setup, the option parsing and help, how `.env` files are read and written, or a schema |
| [references/prompts.md](references/prompts.md) | adding or changing an interactive prompt |
| [references/recipes.md](references/recipes.md) | adding a command, a root `.env` key or a catalogue field |

The Tilt plan (`src/commands/tilt.ts`, `src/schemas/tilt.ts`) follows the [tilt](../tilt/SKILL.md) skill. Before adding, renaming or removing a value that also lives outside the package (option lists, commands, root keys, tool minimums, network names), read the [mirrors](../compose-catalogue/references/mirrors.md).

## Stack and build

- TypeScript ESM: `@bomb.sh/args` (flags), `@clack/prompts` (output and prompts), `zod` (schemas), bundled by tsdown into one file `dist/index.mjs` (bin `n8n-starter`).
- `dist/` is gitignored and consumed by the root scripts and the Tiltfile, which fails to load without the bundle. **Every source change needs `pnpm -r run build` (= `pnpm run build`) before `pnpm run <command>` or Tilt see it.** Tests run against `src/`, so green tests do not mean a rebuilt CLI.
- CI (`.github/workflows/ci.yml`) runs lint, build and test on Node 24. Typecheck is not in CI; run it locally.

## Contracts to keep

- `verify --json` is the Tiltfile's gate: stdout holds exactly one JSON report `{ ok, success, info, warnings, errors, hints }`. The report carries no markers, the consumer renders them. In text mode `--log-level error` prints nothing on success and only the failed checks and hints otherwise.
- `tilt resources` is the Tiltfile's plan, run with `--log-level error`: on exit 0 stdout holds exactly one JSON document, on exit 1 the logged reason. `models read` and `secrets read` follow the same stdout contract (the `key=value` lines carry colour codes only on a tty). How the Tiltfile consumes both: [tilt](../tilt/SKILL.md) skill.
- Every other line of output goes through `logger` (`src/utils/logger.ts`), which writes to stdout too, errors included. `console.log` is reserved for the result of those four commands, `--help` and `--version`; never add output that bypasses `logger`.
- `setup`, `secrets set` and `reset` are the only writers of per-service `.env` files; `config` and `models select` edit the root one only. Nothing ever overwrites a filled value (a link follows its source, that is the one derived value) or touches an existing docker network; `setup` fills a secret that is absent, empty or still equal to its template value, and sets `AI_RUNTIME` only in a root `.env` it created in the same run (a `skipped` one gets a warning at most).
- Commands are idempotent: re-running them changes nothing that is already in place.
- User-facing text names the CLI `n8n-starter` in intros and help; every "run …" hint names the root script through `runCommand()` of `src/utils/format.ts` (`pnpm run setup`, `pnpm run secrets set KEY`), since the root scripts are the only documented way to run the CLI (no global install).
- The CLI never runs Tilt; the Tiltfile calls `verify` and `tilt resources`, not the other way round.

## Output and arguments

- `logger` wraps clack's output behind one process-wide level and keeps clack's symbol per level; `hint` logs at the error level under `💡` (`HINT_SYMBOL`) so a fix never looks like a failure. Never prepend a second marker to a message.
- Interactive prompts are input, not output: the log level never silences them.
- `@bomb.sh/args` types a flag by its raw key before resolving aliases, so every short alias (`h`, `v`, `q`) and every value-less flag (`json`) is listed in `boolean`; otherwise it swallows the next token as its value.
- Positional arguments come from `positionals(argv)` in `src/index.ts`, not from the parser's `_`: the parser coerces them (`123` to a number, `true` to a boolean, `""` dropped, everything after `--` dropped). pnpm forwards `pnpm run config KEY value --log-level error` unchanged; never document a `--` separator (pnpm passes it through and the parser then drops what follows).

## Testing practices

- vitest without a config file; `pnpm -r run test` from the root runs every workspace's tests.
- Anything that touches the outside world is injectable: every command takes `rootDir`, docker helpers take a `run` function, and a command exports its logic separately from the command function, so tests use temp directories and a fake docker instead of a real daemon.
- `vi.mock('@clack/prompts', () => ({...}))` wholesale: `intro`, `outro`, `cancel`, `log.*` and the prompt functions as `vi.fn()` driven per test (`textMock.mockResolvedValueOnce(...)`); a cancel is simulated with a hoisted `CANCEL` symbol and a custom `isCancel`.
- Every test gets a fresh `mkdtemp` root and removes it in `afterEach`; docker is a fake `DockerRunner` that inspects `args` (`['network', 'ls', ...]`, `['network', 'create', ...]`) and returns stdout.
- `process.exitCode` and the log level are reset in `afterEach`; tests that expect an exit code save and restore the previous value.
- Tests are part of the TypeScript project, so `typecheck` covers them.

## Gotchas

- `--version` reads `../package.json` relative to `dist/index.mjs` (`import.meta.url`): keep the bundle one level below `package.json`. It prints `0.0.0` today.
- The root scripts pass only the command name; test flags against the bundle directly (`node packages/cli/dist/index.mjs verify --log-level error`).
- SPEC.md says `pnpm typecheck`; there is no root script of that name. Use `pnpm --filter n8n-starter-cli run typecheck` or run it inside `packages/cli/`.
- Platform detection (`detectPlatform`) runs in `setup`, `verify`, `config AI_RUNTIME` and the `models select` prompt (also reached through `config AI_MODELS`) only, always through the injectable `run`; tests pass a fake `info` answer and the host seams (`arch`, `os`, `totalmem`, `exists`) or the result depends on the machine running them. A mismatch is a warning everywhere, never a failure or an exit code.

## Scaffolding (do not build on)

Leftovers from the package scaffold that are not part of the product: `src/utils/hosts.ts` and the `portless` dependency (nothing imports them), and `src/commands/config.md` (a stale stub mentioning a `basic` variant). The scaffold's `hello` command was removed on 2026-11-08. Leave them alone unless asked to remove them, and do not reference them in new code or docs.

## Before reporting

`pnpm --filter n8n-starter-cli run typecheck`, `pnpm -r run build` and `pnpm -r run test` must all pass, then exercise the built command once by hand. Gates and report format: [validate](../validate/SKILL.md) skill. Update `packages/cli/README.md` and the CLI table of SPEC.md when a command, option or behaviour changed.
