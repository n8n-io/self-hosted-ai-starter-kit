---
name: n8n-docs
description: Look up n8n product facts in the official documentation through the n8n-docs MCP server instead of answering from memory. Use this skill for any question about what n8n does (settings, features, editions, queue mode, task runners, public API, n8n CLI, instance MCP server, release notes) and before writing or explaining an n8n setting in compose/n8n/.
---

# n8n-docs

How to answer n8n product questions for this repository. The n8n documentation at [docs.n8n.io](https://docs.n8n.io/) is the source of truth for everything n8n does; this repository's [SPEC.md](../../../SPEC.md) only decides how it is wired.

## Rule

Never state or write an n8n setting from memory. Confirm it in the documentation first and cite the page URL in the report. This covers every `N8N_*`, `DB_*`, `QUEUE_*`, `EXECUTIONS_*`, `GENERIC_*` and `OFFLOAD_*` key in `compose/n8n/`, every feature toggled by a variant, and every claim about what n8n supports in a given version (`N8N_VERSION` in `compose/n8n/.env.template`).

## Lookup routine

The `n8n-docs` MCP server is registered for the project in [.mcp.json](../../../.mcp.json) (Claude Code) and [.vscode/mcp.json](../../../.vscode/mcp.json) (VS Code): `https://docs.n8n.io/~gitbook/mcp`, streamable HTTP, no authentication. Approve it on first use. It is a GitBook server and exposes `searchDocumentation`, `getPage` and `sendFeedback`.

1. `searchDocumentation` with the exact variable name, node name or feature (`N8N_PROXY_HOPS`, `queue mode`, `task runners external`). Results are excerpts with a `Link:` per page.
2. `getPage` on the best hit for the full page; a question that spans pages (which settings change between queue mode and regular mode) is answered from several pages, not from one excerpt.
3. Report the answer with the page URL. A variable or feature that no page documents is treated as non-existent: say so instead of guessing. Example: `N8N_WEBHOOK_URL` is the current name of the deprecated `WEBHOOK_URL` (n8n 2.35.0), which only the docs can settle.

Fallbacks when the server is unavailable or the agent has no MCP client: every page is served as markdown at `https://docs.n8n.io/<path>.md`, the index is [llms.txt](https://docs.n8n.io/llms.txt), the full text is [llms-full.txt](https://docs.n8n.io/llms-full.txt) (large, paginated). For forum and blog material a developer can add the Kapa server by hand, it needs a browser sign-in and is therefore not committed: `claude mcp add --transport http n8n-kapa https://n8n.mcp.kapa.ai`.

## Starting pages

Verified against the documentation on 2026-11-07; re-check the page before relying on a detail.

- **Environment variables**: [manage-settings-using-environment-variables.md](https://docs.n8n.io/deploy/host-n8n/configure-n8n/manage-settings-using-environment-variables.md) indexes the per-area pages (deployment, database, executions, queue mode, task runners, logs, security, licensing, MCP). Areas with a `<AREA>_MANAGED_BY_ENV` switch ignore their other variables until it is `true`.
- **Variants and licensing**: queue mode, task runners, external secrets, multi-main and the license key behave differently per edition; check the feature's own page and the [licensing section of the environment variables](https://docs.n8n.io/deploy/host-n8n/configure-n8n/manage-settings-using-environment-variables.md) before enabling a feature in a variant ([n8n variant cascade](../compose-catalogue/references/n8n-variants.md)).
- **Release notes**: search `release notes <version>` before bumping `N8N_VERSION`; breaking changes and renamed variables are listed per release. The bump itself follows the [n8n-upgrade](../n8n-upgrade/SKILL.md) skill.
- **Public API, `@n8n/cli`, the server CLI inside the container, the instance MCP server**: read [references/n8n-interfaces.md](references/n8n-interfaces.md) when the question is about driving an n8n instance from outside.

## Repository checks

- A task that adds, renames or removes a variable in `compose/n8n/` confirms each one with the routine above and names the page in the report. The compose files set `N8N_*` keys the documentation may not know (an unknown key is silently ignored by n8n): flag such a key, do not delete it unprompted.
- A feature gated by edition or version is confirmed against `N8N_VERSION` and the variant before it is enabled; the known deviations listed in the [compose-catalogue](../compose-catalogue/SKILL.md) skill stay untouched.
- Product answers for the user (what a node does, how a feature works, which setting to change) come from the documentation with the page link, in prose; the compose files are only changed when the task asks for it.
