# CLI recipes

Paths are relative to `packages/cli/` unless they start at the repository root. Each recipe ends with the gates of the [validate](../../validate/SKILL.md) skill (typecheck, build, test), then one run of the built command by hand. Changing the Tilt plan is a recipe of the [tilt](../../tilt/SKILL.md) skill.

## Add a command

1. `src/commands/<name>.ts`: export the logic (`doSomething(rootDir, ...)`) separately from the command function (`<name>(rootDir = process.cwd(), docker = {})`) that owns `logger.intro` / `logger.outro` and the prompts; inject `rootDir` and `run`.
2. `src/help.ts`: the table entry (`usage`, `description`, `subcommands` with `name`, `usage` and `description` when the command needs one); `src/index.ts`: the `case` and any new flags (short aliases and value-less flags into `boolean`). The dispatcher derives the sub-command checks and the help from the table.
3. `tests/<name>.test.ts` with the clack mock, a temp root and a fake docker runner where needed.
4. A root `package.json` script (`"<name>": "node packages/cli/dist/index.mjs <name>"`) when it should be a root wrapper; the command table in `packages/cli/README.md`; the CLI table and root script table in SPEC.md; the Commands table in `AGENTS.md` when agents should use it.

## Add a root `.env` key

1. `src/schemas/config.ts`: the schema and the `configSchema` field (plus a const tuple when it is an enum).
2. `src/commands/config.ts`: the key in `CONFIG_KEYS` (template order) and `CONFIG_KEY_DESCRIPTIONS` (the template comment), an entry in `CHOICES` for an enum key (like `DOMAIN`) or its own prompt function and the branch that picks it. A value given on the command line is validated by `configSchema.shape[key]`, so a rule beyond the shape of one key belongs in the schema.
3. The root `.env.template` (a comment line above the key, an `Options:` comment for enums), the `KEY:` note of `COMMAND_HELP.config` in `src/help.ts`, the banner line in `print_env()` of the Tiltfile (the key reaches Tilt through the `config` of the plan, which extends `configSchema`), the Configuration block of SPEC.md, `tests/config.test.ts` (`VALID_CONFIG`, the template-defaults and the key-mirror tests).

## Add a generator

1. `src/schemas/secrets.ts`: a `.strict()` member of `generatorSchema` with its `type` literal, and the type in `GENERATOR_TYPES`. A generator with an `input` is derived: it follows that key.
2. `src/utils/generators.ts`: its case in `derive` and `isDerivedFrom` (or its own function beside `generateRandom` when it needs no input, called from `fillSecrets`).
3. `compose/.env.schema.json`: the definition and its `$ref` in `generator.oneOf`, in the order of `GENERATOR_TYPES` (`tests/secrets.test.ts` compares both).
4. Tests in `tests/secrets.test.ts`; the `generate` bullet of the Secrets section of SPEC.md; the manifest section of the env-and-secrets reference of the compose-catalogue skill.

## Add a catalogue field

1. `src/schemas/models.ts` (a model field or a block field, keep `.strict()`), `compose/models/models.schema.json`, `ModelRecord` and `listModels()` in `src/utils/models.ts` so `models read` prints it, and `modelOptions()` when the field belongs in the hint or affects `disabled`.
2. The fixtures in `tests/models.test.ts`, `tests/config.test.ts`, `tests/models-command.test.ts` and `tests/tilt.test.ts`; the entries table in SPEC.md; `modelProjects()` in `src/commands/tilt.ts` only when the field reaches a container.
