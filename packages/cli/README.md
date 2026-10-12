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
n8n-starter reset
n8n-starter config
n8n-starter hello
```

### Commands

| Command | Description |
| --- | --- |
| `setup` | Generate a `.env` file next to every `.env.template` file found recursively. Existing `.env` files are never overwritten. |
| `reset` | Delete all generated `.env` files recursively, after an interactive confirmation. `.env.template` files are kept. |
| `config` | Interactively configure `DOMAIN`, `AI_RUNTIME` and `N8N_VARIANT` in the project root `.env` file. Comments and other keys are preserved. |
| `hello` | Run the interactive example prompt |

Both `setup` and `reset` scan from the current working directory and skip `node_modules`, `dist` and hidden directories.

### Options

| Option | Description |
| --- | --- |
| `-h`, `--help` | Show the help message |
| `-v`, `--version` | Show the version number |

## Libraries

- [@bomb.sh/args](https://www.npmjs.com/package/@bomb.sh/args) - A <1kB library for parsing CLI flags
- [@clack/prompts](https://www.npmjs.com/package/@clack/prompts) - Effortlessly build beautiful command-line apps
- [portless](https://www.npmjs.com/package/portless) - Local development with .localhost domains and https certificate support
- [zod](https://www.npmjs.com/package/zod) - TypeScript-first schema validation with static type inference
