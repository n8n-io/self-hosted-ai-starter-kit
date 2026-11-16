# Environment variables and secrets

Reasoning: [SPEC.md](../../../../SPEC.md), sections "Compose spec rules", "Configuration" and "Secrets". Paths are relative to the repository root.

## Where a variable lives

- **Required** (`${VAR:?}` in the compose file, must come from the `.env` of the same directory): only pinned versions and secrets. The key is live in the `.env.template`: a pinned version with its value, a secret empty (`N8N_ENCRYPTION_KEY=`) and declared in the `.env.json` next to the template. An unfilled `.env` then stops the service instead of starting it with a known value. Three account names are required today as well (see the known deviations in SKILL.md).
- **Optional knob** a developer may change: `${VAR:-default}` in the compose file, and commented out with that default in the template (`# N8N_PROXY_HOPS=1`), so the default lives in exactly one place. A live template key that repeats a compose default is a mistake.
- **Everything else** stays out of the template, and a service with nothing to list has no template at all.
- A template with both kinds is grouped into sections, required first: a one-line header `# required` or `# optional` (with `, defaults live in ./docker-compose.yml` on the optional one) and a blank line before each. The n8n template adds the variant scope to the header.
- The files are the inventory: `git ls-files '*.env.template' '*.env.json'` lists every template and manifest (`.env` and `.env.secrets` are generated and gitignored), and the keys of a service are in the template beside its compose file.
- `VOLUMES_PATH` is optional everywhere and defaults to the repo's `.volumes/` from every compose file.

## Adding or changing a key

- A new required variable goes into the `# required` section of the template of the same directory, a knob into `# optional`. `setup` only creates missing `.env` files and fills empty secrets, so existing checkouts add a non-secret key by hand: say so in the change summary. A new secret is generated on the next `pnpm run setup`.
- Files to touch: the `.env.template`, the `.env.json` beside it for a secret, the `${VAR}` usages of the compose file, SPEC.md ("Secrets" or "Configuration"). A key of the root `.env` also needs the CLI: recipe "Add a root `.env` key" in the [n8n-starter-cli](../../n8n-starter-cli/SKILL.md) skill.
- A key under `compose/n8n/` is an n8n setting: what it does, its default and the edition it needs come from the [n8n-docs](../../n8n-docs/SKILL.md) skill, with the page cited.
- Gates: the template and manifest row of the [validate](../../validate/SKILL.md) skill.

## The root `.env`

- It holds only `N8N_VARIANT`, `AI_RUNTIME`, `AI_ENGINE`, `AI_GATEWAY` (empty for none, and the one key that may be absent), `AI_MODELS`, `DOMAIN`. It never holds a secret: the Tiltfile prints it.
- Tilt loads it with the `dotenv` extension, so every compose project it starts sees `DOMAIN`. By hand the compose default `n8n.localhost` applies (shell variable > `.env` next to the file > compose default) and `DOMAIN=… docker compose …` overrides it.
- `DOMAIN` is used at compose time in labels and at runtime by traefik (`{{ env "DOMAIN" }}` in the default rule and in `config/dashboard.yml`), so it reaches traefik as a container variable too. The default `n8n.localhost` is written in every compose file that uses it (traefik, n8n, garage) and in the root `.env.template`.

## Secrets manifest (`.env.json`)

- One entry per secret key of the template with `source` `generate` (written by `setup`, `rotation` `free`/`manual`/`never`), `prompt` (human, `required` under root `.env` values) or `link` (`from` directory and `key` of another manifest). An optional `prompt` key (`HF_TOKEN`) is commented out in the template and `${KEY:-}` in the compose file.
- A `generate` entry says how through `generator`: `{ "type": "random" }` is the default (`bytes`, `encoding`, `prefix`), `{ "type": "bcrypt", "input": "<KEY>" }` is the hash of a random key of the same manifest and follows it. The options live in `generator`, never on the entry.
- `"file": ".env.secrets"` keeps a generated secret out of the `.env`, in a gitignored file beside it: for a secret no container reads, the password behind a hash. Such a key is in neither the template nor a compose file. `related` names the non-secret keys of the template that belong to a secret (the email of a login), which `secrets read` prints with it; a related knob shows the default of the compose file commented out in the template.
- The n8n owner is the example: `N8N_INSTANCE_OWNER_PASSWORD` (`.env.secrets`, related `N8N_INSTANCE_OWNER_EMAIL`) and `N8N_INSTANCE_OWNER_PASSWORD_HASH` (bcrypt of it, live and empty in the template, `${…:?}` in `x-n8n-env-owner`).
- Editor schema `compose/.env.schema.json`, zod schema `packages/cli/src/schemas/secrets.ts`: they carry the same patterns and enums and change together.
- `tests/secrets.test.ts` (in `packages/cli`) checks every manifest against its template (empty live key, commented out for an optional `prompt`, absent for a `.env.secrets` key), its compose files (`${KEY:?}`, `${KEY:-}` for an optional prompt, nothing for a `.env.secrets` key), its `related` keys (in the template, a commented one with the default of the compose file) and the editor schema, and that every `${VAR:?}` named `*PASSWORD*`, `*SECRET*`, `*_KEY*` or `*TOKEN*` in the catalogue is declared.
- A link keeps one copy to maintain: n8n's `DB_POSTGRESDB_PASSWORD` follows postgres's `POSTGRES_PASSWORD`, litellm's `VLLM_API_KEY` follows the key of `compose/models/vllm`.
