# Command lifecycle

What each command does, in order, and when it exits with code 1. The behaviour contract is the CLI table of [SPEC.md](../../../../SPEC.md), section "n8n-starter CLI (`packages/cli`)"; this file names the functions that implement it. Read only the section of the command you touch. Paths are relative to `packages/cli/`.

Every command takes `rootDir = process.cwd()` (the root scripts run from the repo root) and, where docker is involved, `docker: DockerOptions` with an injectable `run`.

## setup

- `findFiles(rootDir, '.env.template')`, copy each to `.env` beside it with `COPYFILE_EXCL` (`EEXIST` means `skipped`, never overwrites).
- When a root template exists, `applyDetectedRuntime`: `detectPlatform`, an info line `Detected …`; a root `.env` created in this run gets the detected `AI_RUNTIME` when the template value differs, a skipped one only a `runtimeMismatch` warning.
- `fillSecrets`: every unfilled random `generate` key of every manifest gets a value, in its `.env` or, with `file` `.env.secrets`, in that file beside it (created for its owner only); then every derived value (`staleDerived`: a `bcrypt` generator, rewritten only while empty or no longer the hash of its input) and every `link` is set to its source; logs `Generated`/`Linked` lines and one info line per `.env.secrets` written that names `secrets read <directory>`. Then a warning per `prompt` key the root `.env` requires but is unset (`checkSecrets` with `readRootConfigIfValid`).
- `ensureDockerNetworks(['n8n-starter-public', 'n8n-starter-private'])`: creates only the missing ones, `--driver bridge`. Then a summary line.
- Exit 1 when docker is unreachable (the `.env` files are still created) or a manifest is invalid.

## verify

- `checkRequirements`: node, the docker daemon and docker compose against `REQUIREMENTS`; too old or not queryable fails.
- `verifyEnvFiles`: a `.env` next to every template.
- `checkSecrets` over `readSecretState` and the root config: `missing`, `mismatch` (a link that differs from its source, a derived value that does not match its input) and `required` fail, `unset` is info, `ok` success; an invalid manifest is `secretsError`. A check names the file that holds the key, the `.env` or the `.env.secrets`.
- `verifyDockerNetworks`.
- Unless docker failed: `detectPlatform` and `runtimeMismatch` against the root config (`platform`, `runtimeWarning` of the result; `ok` ignores both).
- `formatVerifyResult` buckets the lines into `success`, `info`, `warnings`, `errors`: `Found` / `Missing` per item, one line per secret through `formatSecretCheck`, `Detected …` as info, the mismatch as a warning without a hint. It adds the `pnpm run setup` hint only when a file, a generated or linked secret or a network is missing, and the README Prerequisites hint only when a tool version fails.
- Text mode logs the buckets (`hints` through `logger.hint`, gated at the error level under `💡`); `{ json: true }` prints the report once with `console.log` and nothing else.
- Exit 1 when a tool is too old or missing, any file, secret or network is missing or stale, a manifest is invalid or docker cannot be queried.

## config [KEY] [value]

- Read the root `.env` (missing: an error naming `pnpm run setup`, exit 1).
- Resolve the key. No `KEY`: `select` over `CONFIG_KEYS`, hint from `keyHint` (description plus the available values with the current one in green). Unknown `KEY`: error listing the keys, exit 1.
- `AI_MODELS` (chosen or named) returns `models(rootDir, ['select', value?], { intro: false }, docker)`, so everything from here on is the `models select` section below.
- For the other keys resolve the value. `value` given: `configSchema.shape[key]`, else error and exit 1 without a prompt. Otherwise one prompt: `DOMAIN` text, `N8N_VARIANT`/`AI_RUNTIME`/`AI_ENGINE`/`AI_GATEWAY` select (the empty option of `AI_GATEWAY` reads `none`; a set gateway logs its endpoint with `logGatewayEndpoint`).
- `AI_RUNTIME` first runs `detectPlatform` (info line `Detected …`), marks the suggested option with a green `(detected)` in its label (a clack `hint` shows on the focused row only) and warns with `runtimeMismatch` after the write.
- `updateEnvContent` with that one key; write.
- `AI_ENGINE`/`AI_RUNTIME` then read the catalogue (a failure is a warning); `AI_ENGINE` prints where n8n reaches each model and both warn about `AI_MODELS` ids the new combination does not serve (kept as they are, pointer to `models select`).
- Every key but `DOMAIN` then warns about a `prompt` secret the new configuration requires and that is unset (`checkSecrets`); it never prompts for it.
- Exit 1 on an unknown key or a rejected value (for `AI_MODELS` also a missing catalogue); a cancel leaves the file untouched.

## models read [filter] [--json]

- `readModelsCatalogue`, `listModels(catalogue, filter)`: engines in `AI_ENGINES` order, models in catalogue order, kept when the engine or id contains the filter, case-insensitive.
- Text: per record a header `<engine>/<id>` and `keyValue` lines for `model`, `label`, `args`, `memory`, `note`, `runtimes` (joined with `,`) when present, a blank line between records. `{ json: true }`: the records as one array. `console.log` once, nothing else on stdout.
- Exit 1 naming the file when the catalogue is missing or invalid, or the filter when nothing matches; 1 listing `read, select` on a missing or unknown sub-command.

## models select [ids]

- Read the root `.env` (missing: same error as `config`, exit 1) and the catalogue (error, exit 1).
- `ids` given: `validateModels` (`aiModelsSchema`, then every id served by the current engine on the current runtime), else error and exit 1 without a prompt.
- Otherwise `promptModels`: `detectPlatform` (info line `Detected …`), multiselect over the engine's entries (`modelOptions` with the docker memory: an estimate above it is pointed out in yellow on a cpu runtime, never disabled), runtime-incompatible ones disabled, current ids preselected, skipped (`''`) when nothing runs on the runtime.
- `updateEnvContent` with `AI_MODELS` only; write; `logModelEndpoints`.
- Exit 1 on a rejected value or a missing `.env` or catalogue; a cancel leaves the file untouched.

## tilt resources

- `readRootConfig` (the root `.env` through `configSchema`), `readModelsCatalogue`, `secretDirectories` (which projects get a secrets button in the Tiltfile), `tiltResources(config, catalogue, secretDirs)`: it fails on an `AI_MODELS` id not served by the engine on the runtime, listing the served ids, and parses its result through `tiltResourcesSchema`.
- `console.log(JSON.stringify(plan, null, 2))`; no intro, no outro, nothing else on stdout.
- Exit 1 with the reason on a missing or invalid `.env`, catalogue or model id; 1 listing `resources` on a missing or unknown sub-command.

## secrets read [filter] [--json]

- `readSecretState`; an exact key (case-insensitive) prints only its values, otherwise `listSecrets(state, filter)` (substring of the directory or key) without the derived values, printed as the relative path of the file that holds the secrets (`.env` or `.env.secrets`) followed by `KEY=value` lines, groups separated by a blank line. The `related` keys of a secret are printed above it once per group (`relatedValue`: the `.env`, else the live or commented value of the template).
- With `{ json: true }` one array of `{ file, key, value, source, related? }` in the same order (`value` null while the key is absent, `related` only on an entry that declares it, an exact key narrows the array). `console.log` once, nothing else on stdout.
- Exit 1 naming the file when a matched `.env` or `.env.secrets` is missing, when nothing matches, or on an invalid manifest; 1 listing `read, set` on a missing or unknown sub-command.

## secrets set KEY [value]

- `readSecretState`; `KEY` must be a `generate` or `prompt` key that is not derived (a link is refused naming its source key, a derived key naming its input, an unknown key lists the keys).
- `value` given: written as `formatEnvValue` stores it (empty rejected, and a value with a single quote, a backslash or a line break: `valueProblem`). Otherwise one `password` prompt with the entry's `description`; a cancel writes nothing. A filled `rotation: never` key warns first.
- `setSecret` writes the key into its file, then every value derived from it (skipped while the hash still fits) and every link, logging `set`/`derived`/`linked` per file, never the value.
- Exit 1 on a missing key, an unknown, link or derived key, an empty or unstorable value, a missing `.env` or an invalid manifest.

## reset

- `findEnvFiles`: `findFiles` for `.env` and for `.env.secrets`, list them, warn about the filled `generate` keys with `rotation` `manual` or `never` (a manifest problem is ignored here), `confirm` (default `false`), `rm` each.
- Exit 0; a cancel deletes nothing.
