# Local operations

This repository runs a local-only n8n AI stack on Apple Silicon. n8n and
Qdrant bind to `127.0.0.1`; the sandbox, task runners, Ollama adapter, and
PostgreSQL have no published host ports.

## Pinned components

- n8n and task runners: `2.46.6`
- PostgreSQL: `18.6-alpine3.24`
- Qdrant: `1.20.0`
- n8n sandbox service: `1.8.1`
- Ollama adapter runtime: Node `22.23.4` (image digest pinned in Compose)
- n8n Assistant model alias: `gpt-oss-20b-n8n` with 131072-token context

The native Ollama service runs on the Mac at `http://localhost:11434`.
Containers reach it through `host.docker.internal`.

## Create the Assistant model alias

Download the trusted `gpt-oss-20b-MXFP4.gguf` file and verify its SHA-256:

`27cd6c432c7672cb812a92f611cf3ba7bbc35928262bb1e1253ff4ee6ae35901`

Create the exact alias referenced by `.env`:

```bash
cat > /tmp/Modelfile.gpt-oss-n8n <<'EOF'
FROM "/absolute/path/to/gpt-oss-20b-MXFP4.gguf"
PARAMETER num_ctx 131072
EOF

ollama create gpt-oss-20b-n8n -f /tmp/Modelfile.gpt-oss-n8n
ollama show gpt-oss-20b-n8n
```

`ollama show` must report `context length 131072` and `num_ctx 131072`.
After creation, Ollama owns a local copy and no longer needs the source GGUF.

## Everyday commands

```bash
cd ~/Projects/self-hosted-ai-starter-kit

# Start or reconcile the complete stack
docker compose up -d --wait

# Show service state
docker compose ps -a

# Follow relevant logs
docker compose logs -f n8n n8n-runners ollama-adapter sandbox-api

# Stop application services while leaving data volumes intact
docker compose stop n8n n8n-runners

# Start them again
docker compose up -d n8n n8n-runners
```

Never run `docker compose down -v`. The `-v` flag deletes database, n8n,
Qdrant, and sandbox volumes.

## Health checks

```bash
curl -fsS http://127.0.0.1:5678/healthz
curl -fsS http://127.0.0.1:6333/

docker compose exec -T n8n \
  wget -qO- http://ollama-adapter:11435/healthz
docker compose exec -T n8n \
  wget -qO- http://sandbox-api:8080/healthz
docker compose exec -T n8n-runners \
  wget -qO- http://127.0.0.1:5680/healthz

ollama list
ollama ps
```

Expected n8n logs include registrations for both
`launcher-javascript` and `launcher-python`. The task broker listens on port
5679 only inside the Compose network.

## Validate configuration

```bash
docker compose config --quiet
docker compose config --images
node --test ollama-adapter/server.test.mjs
```

The runtime `.env` contains generated secrets and must remain ignored by Git.
The sandbox and task-runner containers receive only the secrets they require.

## Database backup

Store backups outside the repository and protect them because `globals.sql`
contains password verifiers and `runtime.env` contains secrets.

```bash
umask 077
stamp=$(date +%Y%m%d-%H%M%S)
backup="$HOME/Library/Application Support/n8n-backups/$stamp"
mkdir -p "$backup"

docker compose stop n8n n8n-runners qdrant

docker compose exec -T postgres sh -eu -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$backup/n8n.dump"

docker compose exec -T postgres sh -eu -c \
  'pg_dumpall -U "$POSTGRES_USER" --globals-only' \
  > "$backup/globals.sql"

cp .env "$backup/runtime.env"

# N8N_DEFAULT_BINARY_DATA_MODE=filesystem stores binary workflow data here.
docker run --rm \
  -v self-hosted-ai-starter-kit_n8n_storage:/source:ro \
  -v "$backup":/backup \
  postgres:18.6-alpine3.24 \
  tar -C /source -czf /backup/n8n_storage.tgz .

# Qdrant vectors are separate from PostgreSQL and need their own archive.
docker run --rm \
  -v self-hosted-ai-starter-kit_qdrant_storage:/source:ro \
  -v "$backup":/backup \
  postgres:18.6-alpine3.24 \
  tar -C /source -czf /backup/qdrant_storage.tgz .

chmod 600 "$backup"/*
shasum -a 256 "$backup"/* > "$backup/SHA256SUMS"

docker compose up -d n8n n8n-runners qdrant
```

Verify a custom-format dump before relying on it:

```bash
docker run --rm -i postgres:18.6-alpine3.24 \
  pg_restore --list < "$backup/n8n.dump" > "$backup/restore.list"
```

A complete restore also requires `n8n_storage.tgz` and
`qdrant_storage.tgz`. Restore them only while n8n and Qdrant are stopped,
into empty replacement volumes; never extract over running volumes.

## PostgreSQL 18 layout

The active database uses:

- image: `postgres:18.6-alpine3.24`
- volume: `self-hosted-ai-starter-kit_postgres18_storage`
- mount: `/var/lib/postgresql`
- `PGDATA`: `/var/lib/postgresql/18/docker`

The preserved PostgreSQL 16 rollback volume is:

`self-hosted-ai-starter-kit_postgres_storage`

Do not mount PostgreSQL 18 directly on the PostgreSQL 16 volume.

## PostgreSQL 16 emergency rollback

Rollback restores the database to the point represented by the retained PG16
volume. Stop all writers first:

```bash
docker compose stop n8n n8n-runners postgres

docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.postgres16-rollback.yml \
  up -d --no-deps --wait postgres

docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.postgres16-rollback.yml \
  up -d n8n n8n-runners
```

Confirm PostgreSQL 16 before reopening n8n:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.postgres16-rollback.yml \
  exec -T postgres sh -eu -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SHOW server_version;"'
```

Return to PostgreSQL 18 only after stopping n8n and PostgreSQL again.

## Workflow verification

The working local test workflow is:

- name: `Lokaler Assistant-Test`
- ID: `WdC4e3BRZ8GXHrJr`

The older duplicate is archived. Keep failed executions as diagnostic history
until the setup has been stable for several days.

A CLI execution needs exclusive access to the task-broker port. Stop n8n first
and always start it again:

```bash
docker compose stop n8n n8n-runners
docker compose run --rm --no-deps \
  -e N8N_RUNNERS_MODE=internal \
  n8n execute --id=WdC4e3BRZ8GXHrJr --rawOutput
docker compose up -d n8n n8n-runners
```

## Updating

1. Read release notes.
2. Create and verify a database backup.
3. Update `N8N_VERSION` in `.env` and `.env.example`.
4. Keep `n8nio/n8n` and `n8nio/runners` on the exact same version.
5. Pull explicitly, then reconcile the stack:

```bash
docker compose pull n8n n8n-import n8n-runners
docker compose up -d --wait
```

6. Repeat every health check and the workflow verification.

Do not use floating image upgrades for n8n, its runners, PostgreSQL, or the
sandbox services.
