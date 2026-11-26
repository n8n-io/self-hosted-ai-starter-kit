---
name: n8n-upgrade
description: Workflow for upgrading n8n by bumping N8N_VERSION, which pins the n8n and task runner images together. Use this skill when asked to upgrade, update or bump n8n or its runners image, to check what a newer n8n release breaks, or to adopt a setting that needs a newer version.
---

# n8n upgrade

`N8N_VERSION` in `compose/n8n/.env.template` pins two images at once: `docker.n8n.io/n8nio/n8n` (main, worker, webhook processor) and `n8nio/runners` (the task runner sidecars). The n8n documentation requires the two versions to match ([Set up task runners](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-task-runners)). Every product fact comes from the documentation through the [n8n-docs](../n8n-docs/SKILL.md) skill, never from memory. Paths are relative to the repository root.

## Checklist

- [ ] **Versions.** Note the current value in `compose/n8n/.env.template` and the target. Read the [release notes](https://docs.n8n.io/changelog/release-notes) of every version in between, the breaking-changes page of each major version crossed, and [Update n8n](https://docs.n8n.io/deploy/host-n8n/keep-n8n-running/update-n8n). Keep the page URLs for the report.
- [ ] **Settings audit.** List every key the cascade sets (`grep -ohE '^ +[A-Z][A-Z0-9_]+:' compose/n8n/docker-compose*.yml | sort -u`, plus the keys of `compose/n8n/.env.template`) and check each against those notes: renamed, removed, deprecated, a new default, moved to another edition. A key the documentation does not know is flagged, not deleted.
- [ ] **Launcher config.** `compose/n8n/n8n-task-runners.json` mirrors the image: diff it against `docker run --rm --entrypoint cat n8nio/runners:<version> /etc/n8n-task-runners.json` (this pulls the image) and carry over upstream changes, keeping the four Code node allowlists in `allowed-env` instead of `env-overrides`.
- [ ] **Assistant.** The sandbox of `compose/n8n/assistant` is a release of its own: compare `N8N_SANDBOX_VERSION` in `compose/n8n/assistant/.env.template` with `SANDBOX_VERSION` of n8n's [get-n8n.sh](https://github.com/n8n-io/n8n/blob/master/docker/get-n8n.sh), and its services with [get-n8n-compose.yml](https://github.com/n8n-io/n8n/blob/master/docker/get-n8n-compose.yml). Check the `N8N_INSTANCE_AI_*` keys of `x-n8n-env-assistant` against `packages/@n8n/config/src/configs/instance-ai.config.ts` of the target version (`N8N_INSTANCE_AI_ENABLED` exists from 2.47.0), and the first model of `compose/models/models.cloud.json` against the models the documentation recommends and the default of `N8N_INSTANCE_AI_MODEL` in that file.
- [ ] **Edits.** `N8N_VERSION` in `compose/n8n/.env.template`; the compose files and template comments for every setting that changed, following the [compose-catalogue](../compose-catalogue/SKILL.md) skill; SPEC.md where it names version-specific behaviour (section "`compose/n8n/` variants"); README.md when the user-facing workflow changes.
- [ ] **Existing checkouts.** `setup` never overwrites a `.env`, so `compose/n8n/.env` keeps the old version: say in the change summary that it is bumped there by hand (README.md, "Upgrading"), and ask before editing the local file.
- [ ] **Gates.** The compose row of the [validate](../validate/SKILL.md) skill for all four variant files of `compose/n8n/`; the enterprise file needs the license variable set for the check.
- [ ] **Report.** Old and new version, the pages read with their URLs, each setting that changed and why, the result of the launcher diff, the gates.

## Gotchas

- Do not start the stack to try the new version unless asked. `.volumes/` holds the user's data, and every n8n process runs pending database migrations when it starts ([Update n8n](https://docs.n8n.io/deploy/host-n8n/keep-n8n-running/update-n8n)): report what the documentation says about going back instead of assuming it is possible.
- A running `pnpm run dev` picks up an edited `compose/n8n/.env` at once and recreates the n8n containers.
- The value has no `v` prefix (`2.49.7`), unlike `VLLM_VERSION` or `QDRANT_VERSION`.
