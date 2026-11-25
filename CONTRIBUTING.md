# Self-hosted AI Starter Kit - Vision & Contribution Guidelines

Awesome that you're interested in contributing to the Self-hosted AI Starter Kit! These specific guidelines are in addition to the general [n8n contribution guidelines](https://github.com/n8n-io/n8n/blob/master/CONTRIBUTING.md). The rules every change follows live in [SPEC.md](./SPEC.md); this page explains what belongs in the kit and why.

## Vision Statement

The Self-hosted AI Starter Kit is **a complete, curated n8n and local AI stack that runs on your own machine with one command**. It goes from a single n8n container to the deployments n8n runs in practice (postgres, external task runners, queue mode with workers and webhook processors, the enterprise edition), next to local models served by Ollama or vLLM and the storage and services those setups need. Everything is a pinned, linted Docker Compose project, so what you learn and build locally carries over to a real deployment.

## Core Principles

### 1. Simple by Default, Complete on Demand

The default is the smallest useful stack: the `dev` variant (one n8n container on SQLite) with Ollama as the model engine. Everything else is one setting or one click away: `pnpm run config` switches the n8n variant, hardware runtime, model engine and gateway, and services that are not needed right away (pgAdmin, Redis Insight, Qdrant, Garage) are registered in Tilt but only start when you start them. Adding a service must not make the default path longer.

### 2. Production-Shaped, Not Production-Hardened

The n8n variants mirror n8n's own deployment options, so you can learn queue mode, task runners or the enterprise features locally before you need them. The compose files follow the same rules a production host would (pinned images, healthchecks, generated secrets, no host ports) and run without Tilt. The kit itself is still a local environment: it serves plain HTTP on `*.n8n.localhost` and does not set out to secure, back up or scale an internet-facing instance.

### 3. Curated, Not Exhaustive

Each role has one opinionated default: n8n, Ollama, PostgreSQL, Redis, Qdrant, Traefik. An alternative is added only when it covers a case the default cannot, the way vLLM covers high-throughput GPU serving and LiteLLM gives every model one OpenAI-compatible endpoint. It's better to do fewer things well than to attempt to solve every possible use case.

### 4. Privacy-First Local Development

Everything runs locally and offline once the images and models are pulled. No hosted service is required by default; anything that calls out (a license key, a cloud model provider) is opt-in.

### 5. One Source of Truth, Tooling Over Instructions

Rules live in [SPEC.md](./SPEC.md), configuration in `.env` files generated from their templates, and the [n8n-starter CLI](./packages/cli/README.md) does the setup (`setup`, `config`, `models`, `secrets`, `verify`) instead of a list of manual steps. If a task needs a paragraph of instructions, it probably belongs in the CLI.

## What Belongs in the Starter Kit

### The Service Catalogue

Grouped like the [compose/](./compose/) directory:

- **n8n**: the `dev`, `build`, `community` and `enterprise` variants and the services they need, such as task runners, workers and webhook processors
- **models**: Ollama and vLLM, the shared [model catalogue](./compose/models/models.json) and the hardware runtimes (Apple silicon, x86 CPUs, NVIDIA and AMD GPUs), plus a gateway in front of them
- **storage**: the databases, caches and object storage the n8n variants use, with their admin UIs
- **services**: the supporting services AI workflows build on, such as the Qdrant vector store
- **proxy**: Traefik and the read-only docker socket proxy that route `<service>.n8n.localhost`

### Tooling and Developer Experience

- The `n8n-starter` CLI: setup, configuration, the model catalogue, secrets and the read-only `verify` check
- Tilt orchestration of the whole catalogue, with services started on demand
- Lint rules that keep every compose file pinned, healthchecked and free of literal secrets

### Getting Started Materials

- Clear installation instructions for different platforms and hardware
- Documentation for each service in its own `README.md`, with links to the upstream and n8n documentation

## What Doesn't Belong in the Starter Kit

### Hardening for the Public Internet

- Exposing an instance to the internet and the security work that comes with it
- Backup and recovery systems
- High availability and scaling beyond what the n8n variants demonstrate
- Monitoring and logging stacks

### Other Orchestrators and Deployment Targets

- Kubernetes, Helm, Docker Swarm or other orchestrators: the kit is Docker Compose, run by Tilt
- Cloud-specific deployment templates

### Overlapping Alternatives

- A second service for a role that already has one, without a case the existing one cannot cover (another vector store, another database for the core setup, another proxy)
- Alternative workflow platforms

### Features n8n Already Provides

- Authentication, user management or access control in front of n8n
- Multi-tenancy layers

## PR Specific Requirements

- Small PRs only:
  - Focus on a single feature or fix per PR.
- Typo-only PRs:
  - Typos are not sufficient justification for a PR and will be rejected.
- Follow [SPEC.md](./SPEC.md) and update it in the same PR when a rule, a default or a mirrored value changes.
- Run the checks before opening a PR: `pnpm run lint` after any compose change; `pnpm --filter n8n-starter-cli run typecheck`, `pnpm -r run build` and `pnpm -r run test` after any CLI change.
- Cite the [n8n documentation](https://docs.n8n.io) for every n8n setting you add or change.

Remember: **It's better to be an excellent starting point than a mediocre everything-solution.**
