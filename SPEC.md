# Self-hosted AI starter kit

**Self-hosted AI Starter Kit** is an open-source Docker Compose template designed to swiftly initialize a comprehensive local AI and low-code development environment.

## Quickstart

> Implementation of the CLI helpers to set up the environment

```bash
# Install dependencies
pnpm install
# Build ./packages/cli
pnpm run build
# Run cli setup
# 1. Generate .env files from any .env.template file
# 2. (To be implemented later) Replace any secrets in .env files with randomly generated values
pnpm run setup
# Run the tilt docker experience
pnpm run dev
```

## Developer Experience

The `self-hosted-ai-starter-kit` provides a Docker Compose experience using [tilt](https://tilt.dev/) and the [n8n-starter cli](packages/cli) for easy setup and configuration. Running `pnpm run dev` runs `tilt up` using the [Tiltfile](./Tiltfile), which loads configuration from [.env](./.env).

```bash
# The domain to run the Docker Compose services on
DOMAIN=dev.localhost
# The hardware-supported AI runtime
# Options: cpu-x86-64, cpu-arm64, apple-silicon, dgx-spark, gpu-nvidia or gpu-amd
AI_RUNTIME=cpu-x86-64
# Which variant of n8n to run in ./compose/n8n
# Options: base, community or enterprise
N8N_VARIANT=base
```

## Best practices

* Configurations are loaded from `.env` files that are never committed to git.
* On setup, `.env` files are generated from `.env.template` files.

## Structure

* `./compose` docker compose specifications
* `./packages/cli` n8n-starter to manage setup and config
