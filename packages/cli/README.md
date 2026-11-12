# n8n-starter

A minimal CLI for the n8n self-hosted-ai-starter-kit docker repository.

## Development

- Install dependencies:

```bash
pnpm install
```

- Run the unit tests:

```bash
pnpm test
```

- Build the CLI:

```bash
pnpm build
```

- Run the built CLI:

```bash
pnpm start -- --help
```

### Scripts

All scripts are defined in [package.json](./package.json) and run with `pnpm run <script>`:

| Script | Description |
| --- | --- |
| `build` | Bundle `src/index.ts` to `dist/index.mjs` with [tsdown](https://tsdown.dev/) |
| `dev` | Rebuild automatically on source changes (`tsdown --watch`) |
| `start` | Run the built CLI (`node dist/index.mjs`), e.g. `pnpm start -- setup` |
| `test` | Run the unit tests once with [vitest](https://vitest.dev/) |
| `typecheck` | Type-check the sources without emitting (`tsc --noEmit`) |
| `release` | Bump the version and tag a release with [bumpp](https://github.com/antfu-collective/bumpp) |

## Usage

```bash
n8n-starter --help
n8n-starter --version
n8n-starter setup
n8n-starter verify
n8n-starter reset
n8n-starter config                          # asks which key, then prompts it
n8n-starter config N8N_VARIANT              # prompts that key only
n8n-starter config N8N_VARIANT enterprise   # writes without a prompt
n8n-starter config AI_MODELS                # the same as models select, ids after it as well
n8n-starter models read                     # the catalogue as key=value blocks per engine and model
n8n-starter models read vllm --json         # filtered by a part of an engine or id, as JSON records
n8n-starter models select                   # multi-select over the catalogue, writes AI_MODELS
n8n-starter models select qwen3-5-0-8b      # writes without a prompt, "" clears the list
n8n-starter secrets read                    # every declared secret of the .env files, grouped by file
n8n-starter secrets read vllm               # only the secrets whose directory or key contains "vllm"
n8n-starter secrets read VLLM_API_KEY       # an exact key prints only its value, for piping
n8n-starter secrets read vllm --json        # the same as an array of { file, key, value, source }
n8n-starter secrets set N8N_LICENSE_ACTIVATION_KEY        # asks for the value with a masked prompt
n8n-starter secrets set N8N_LICENSE_ACTIVATION_KEY <key>  # writes without a prompt
n8n-starter tilt resources                  # the Tilt resource plan as JSON, consumed by the Tiltfile
n8n-starter secrets --help                  # the help of one command, also `n8n-starter help secrets`
```

The command line is `n8n-starter <command> [sub-command] [value] [options]`. A command may take one sub-command and one value (`config`, whose sub-command is the key; `models read [filter]`, `models select [ids]`; `secrets read [filter]`, `secrets set KEY [value]`; `tilt resources`); commands without sub-commands reject extra arguments with exit code 1. A command that needs a sub-command (`models`, `secrets`, `tilt`) called without one, or with an unknown one, prints the reason and its own help with exit code 1; `<command> --help` and `help <command>` print that help with exit code 0. Positional arguments are passed as given, so `pnpm run config N8N_VARIANT enterprise --log-level error` works from the repository root without `--`.

### Commands

| Command | Description |
| --- | --- |
| `setup` | Generate a `.env` file next to every `.env.template` file found recursively (the root `.env` it creates gets `AI_RUNTIME` from the detected platform, see [src/utils/platform.ts](./src/utils/platform.ts); an existing one is left alone and warned about when its runtime does not fit), fill the secrets declared in the `.env.secrets.json` next to each template (a random value once per empty `generate` key, every `link` copied from its source, a required `prompt` key such as the enterprise license only warned about with a pointer to `secrets set`), then create the `n8n-starter-public` and `n8n-starter-private` docker networks if they don't exist yet. Existing `.env` values and networks are never touched. Requires a running Docker daemon; exits with code 1 when it is unreachable or a manifest is invalid. |
| `verify` | Check that node, the docker daemon and docker compose meet the minimum versions of `REQUIREMENTS` in [src/utils/requirements.ts](./src/utils/requirements.ts) (Node.js 24, Docker Engine 25.0, Docker Compose 2.24; a tool that is too old or cannot be queried fails with a hint at the Prerequisites of the root [README.md](../../README.md)), that a `.env` file exists next to every `.env.template` file, that every declared secret is filled (an empty generated or linked key, a link that differs from its source and a `prompt` key the root `.env` requires, such as the license key for `N8N_VARIANT=enterprise`, fail it; an optional unset key is only reported) and that the `n8n-starter-public` and `n8n-starter-private` docker networks exist; the detected platform (docker architecture, cpus and memory, host, gpu) is reported and an `AI_RUNTIME` that does not match it is a warning naming `pnpm run config AI_RUNTIME <runtime>`, never a failure. Changes nothing; exits with code 1 when anything is missing. Each failed line names its fix: `pnpm run secrets set KEY` for a required human secret, one `pnpm run setup` hint when a file, a generated or linked secret or a network is missing. `--json` prints the report `{ ok, success, info, warnings, errors, hints }` as one JSON document and nothing else; the [Tiltfile](../../Tiltfile) runs it that way before starting any service and turns the warnings into Tilt alerts and the errors (`❌`) and hints (`💡`) into one error. In text mode a hint is marked `💡` instead of the red error square; with `--log-level error` the output stays silent unless a check fails. |
| `reset` | Delete all generated `.env` files recursively, after an interactive confirmation that is preceded by a warning naming the secrets the data in `.volumes/` depends on. `.env.template` files are kept. |
| `config [KEY] [value]` | Edit one key of the project root `.env` file: `N8N_VARIANT`, `AI_RUNTIME`, `AI_ENGINE`, `AI_GATEWAY`, `AI_MODELS` or `DOMAIN`. Without `KEY` a select lists the keys with their description and available values (the current one in green) and only the chosen key is prompted; with `KEY` only that prompt runs; with `KEY` and `value` nothing is prompted, the value is validated and an invalid value or unknown key exits with code 1 without writing. `AI_MODELS` (chosen in the select or named as `KEY`) runs `models select [ids]`: its multi-select, or the given ids validated against the catalogue. `AI_ENGINE` and `AI_RUNTIME` warn about selected models the new combination does not serve and leave them in place; `AI_ENGINE` prints the endpoint n8n uses for every selected model; `AI_GATEWAY` offers `none` first (an empty value, `config AI_GATEWAY ""` without a prompt) and prints the endpoint of the gateway it set; `AI_RUNTIME` detects the platform, marks the fitting runtime with a green `(detected)` in the prompt and warns about a value that differs from it. Comments and other keys are preserved. |
| `models read [filter] [--json]` | Print the models of the validated catalogue [compose/models/models.json](../../compose/models/models.json): one block per engine and model (a header `<engine>/<id>`, then `key=value` lines, the keys in cyan on a tty), filtered by a part of an engine or id (`models read vllm`, `models read 2b`); `--json` prints the same records as an array of `{ engine, id, model, label, args?, memory?, note?, runtimes? }`. Nothing else is written to stdout; a missing or invalid catalogue exits with code 1 naming the file, a filter nothing matches with code 1 naming it. |
| `models select [ids]` | Edit `AI_MODELS` of the project root `.env`: a multi-select over every model of the catalogue of the current engine (label, model name, memory as `~<GB> GB RAM` or VRAM after the runtime, and the note as hint), preceded by the detected platform line and with an estimate above the docker memory pointed out on the CPU runtimes, with the ones the current runtime cannot run shown disabled (skipped when none runs), or with `ids` the comma separated ids written without a prompt (`""` clears the list), validated against the catalogue for the current engine and runtime, exit code 1 without writing when rejected. ollama pulls the selected models into one server, vllm runs one container per selected model; the endpoint n8n uses for every selected model is printed. Only `AI_MODELS` is written. |
| `tilt resources` | Print the Tilt resource plan of the project root `.env` as JSON: the validated configuration and every compose project the [Tiltfile](../../Tiltfile) registers with its files, project name, profiles, inline override, `secrets` (the directory of a project with a `.env.secrets.json`, the filter of the `secrets read` button the Tiltfile adds to its resources) and resources (`name`, `labels`, `resource_deps`, `links`, `infer_links`, `auto_init`, `enabled`), see [SPEC.md](../../SPEC.md#developer-experience-with-tilt). Nothing else is written to stdout; a missing or invalid `.env`, an invalid catalogue or an `AI_MODELS` id the engine does not serve on the runtime exits with code 1 with the reason. |
| `secrets read [filter] [--json]` | Print the secrets declared in the `.env.secrets.json` manifests with their current values as `KEY=value` lines grouped by `.env` file, nothing else on stdout. `filter` keeps the keys whose directory or name contains it (case-insensitive); an exact key name prints only its value so it can be piped. With `--json` one array of `{ file, key, value, source }` in the same order (`value` is `null` while the key is absent from the file, an exact key narrows the array). A missing `.env`, no match or an invalid manifest exits with code 1. |
| `secrets set KEY [value]` | Write one secret declared as `generate` or `prompt` and copy it to every `link` of it: with `KEY` alone the value is asked for with a masked prompt (a cancel writes nothing), with `KEY value` nothing is prompted. A `link` key is refused with a pointer to its source key, an unknown key lists the keys, an empty value is rejected; all exit with code 1 without writing. Replacing a secret whose `rotation` is `never` warns first. The value is never logged. |
| `help [command]` | Print the global help, or the help of one command: its usage, sub-commands and the options. The same as `--help`. |

`setup`, `verify`, `reset` and `secrets` scan from the current working directory and skip `node_modules`, `dist` and hidden directories.

### Options

| Option | Description |
| --- | --- |
| `-h`, `--help` | Show the help message, or the help of the command named on the same command line (`secrets --help`) |
| `-v`, `--version` | Show the version number |
| `-q`, `--quiet` | Only log errors. Same as `--log-level error`. |
| `--log-level <level>` | How much a command logs: `silent`, `error`, `warn`, `info` (default) or `debug`. Applies to every command; interactive prompts are never silenced. An explicit `--log-level` wins over `--quiet`. |
| `--json` | Print JSON instead of text. Accepted by `verify`, `models read` and `secrets read`; any other command rejects it with exit code 1. |

## Libraries

- [@bomb.sh/args](https://www.npmjs.com/package/@bomb.sh/args) - A <1kB library for parsing CLI flags
- [@clack/prompts](https://www.npmjs.com/package/@clack/prompts) - Effortlessly build beautiful command-line apps
- [portless](https://www.npmjs.com/package/portless) - Local development with .localhost domains and https certificate support
- [zod](https://www.npmjs.com/package/zod) - TypeScript-first schema validation with static type inference
