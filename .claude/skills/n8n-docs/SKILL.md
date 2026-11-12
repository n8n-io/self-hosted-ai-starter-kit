---
name: n8n-docs
description: Look up n8n product facts (environment variables, features, configuration, variants and licensing, public API, n8n CLI, instance MCP server, release notes) in the official documentation through the `n8n-docs` MCP server. Use for any n8n question, and before writing or explaining an n8n setting in compose/n8n/ or the Tiltfile.
---

# n8n-docs

How to answer n8n product questions for this repository. The n8n documentation at [docs.n8n.io](https://docs.n8n.io/) is the source of truth for everything n8n does; this repository's [SPEC.md](../../../SPEC.md) only decides how it is wired. The [develop](../develop/SKILL.md) skill routes implementation tasks; it sends every n8n setting here.

## Rule

Never state or write an n8n setting from memory. Confirm it in the documentation first and cite the page URL in the report. This covers every `N8N_*`, `DB_*`, `QUEUE_*`, `EXECUTIONS_*`, `GENERIC_*` and `OFFLOAD_*` key in [compose/n8n/](../../../compose/n8n/), every feature toggled by a variant, and every claim about what n8n supports in a given version (`N8N_VERSION` in [compose/n8n/.env.template](../../../compose/n8n/.env.template)).

## Lookup routine

The `n8n-docs` MCP server is registered for the project in [.mcp.json](../../../.mcp.json) (Claude Code) and [.vscode/mcp.json](../../../.vscode/mcp.json) (VS Code): `https://docs.n8n.io/~gitbook/mcp`, streamable HTTP, no authentication. Approve it on first use. It is a GitBook server and exposes `searchDocumentation`, `getPage` and `sendFeedback`.

1. `searchDocumentation` with the exact variable name, node name or feature (`N8N_PROXY_HOPS`, `queue mode`, `task runners external`). Results are excerpts with a `Link:` per page.
2. `getPage` on the best hit for the full page; a question that spans pages (which settings change between queue mode and regular mode) is answered from several pages, not from one excerpt.
3. Report the answer with the page URL. A variable or feature that no page documents is treated as non-existent: say so instead of guessing. Example: `N8N_WEBHOOK_URL` is the current name of the deprecated `WEBHOOK_URL` (n8n 2.35.0), which only the docs can settle.

Fallbacks when the server is unavailable: every page is served as markdown at `https://docs.n8n.io/<path>.md`, the index is [llms.txt](https://docs.n8n.io/llms.txt), the full text is [llms-full.txt](https://docs.n8n.io/llms-full.txt) (large, paginated). For forum and blog material a developer can add the Kapa server by hand, it needs a browser sign-in and is therefore not committed: `claude mcp add --transport http n8n-kapa https://n8n.mcp.kapa.ai`.

## Reference sheet

Verified against the documentation on 2026-11-07; re-check the page before relying on a detail.

- **Environment variables**: [manage-settings-using-environment-variables.md](https://docs.n8n.io/deploy/host-n8n/configure-n8n/manage-settings-using-environment-variables.md) indexes the per-area pages (deployment, database, executions, queue mode, task runners, logs, security, licensing, MCP). Areas with a `<AREA>_MANAGED_BY_ENV` switch ignore their other variables until it is `true`.
- **Variants and licensing**: queue mode, task runners, external secrets, multi-main and the license key behave differently per edition; check the feature's own page and the [licensing section of the environment variables](https://docs.n8n.io/deploy/host-n8n/configure-n8n/manage-settings-using-environment-variables.md) before enabling a feature in a variant ([n8n variant cascade](../develop/resources/compose-catalogue.md#n8n-variant-cascade)).
- **Public API**: [n8n-api.md](https://docs.n8n.io/connect/n8n-api.md). Base path `https://<domain>/api/v1`, header `X-N8N-API-KEY` (key created under Settings > n8n API; scopes are Enterprise only). Interactive reference (Swagger UI) at `/api/v1/docs` on a self-hosted instance; the generated reference on the docs site is rendered with Scalar and publishes no OpenAPI file, and the `openapi.yml` in the n8n repository is a build-time skeleton, so the live `/api/v1/docs` is the operation list. `N8N_PUBLIC_API_DISABLED=true` disables the API, `N8N_PUBLIC_API_SWAGGERUI_DISABLED=true` only the playground ([disable-the-public-api.md](https://docs.n8n.io/deploy/host-n8n/configure-n8n/security/disable-the-public-api.md)).
- **`@n8n/cli` client**: [n8n-cli.md](https://docs.n8n.io/connect/n8n-cli.md). `npx @n8n/cli <group> <command>`, configured with `N8N_URL` and `N8N_API_KEY` (or `n8n-cli config set-url|set-api-key`). Groups: `workflow`, `execution`, `credential`, `project`, `tag`, `variable`, `data-table`, `user`, `source-control`, `package`, `audit`; `--format=json|table|id-only`. It ships a Claude Code skill (`n8n-cli skill install`).
- **Server CLI inside the container**: [use-the-command-line.md](https://docs.n8n.io/deploy/host-n8n/configure-n8n/use-the-command-line.md). Run as `docker exec -u node -it <n8n-container> n8n <command>`: `export:workflow --backup --output=<dir>`, `import:workflow --input=<file|dir> [--separate]`, `export:credentials`, `import:credentials`, `export:entities`/`import:entities`, `publish:workflow`/`unpublish:workflow`, `license:info|clear`, `user-management:reset`, `mfa:disable`, `audit`. These bypass access control; most work with n8n stopped.
- **Instance MCP server**: [connect-to-n8n-mcp-server.md](https://docs.n8n.io/connect/connect-to-n8n-mcp-server.md). Endpoint `https://<domain>/mcp-server/http`, enabled under Settings > Instance-level MCP or with `N8N_MCP_MANAGED_BY_ENV=true` and `N8N_MCP_ACCESS_ENABLED=true` (n8n 2.20+); OAuth or `Authorization: Bearer <token>`; `N8N_DISABLED_MODULES=mcp` removes it. Workflows are exposed one by one. A reverse proxy must pass the `MCP-Protocol-Version`, `Mcp-Method` and `Mcp-Name` headers. Tools are listed in the [tools reference](https://docs.n8n.io/connect/connect-to-n8n-mcp-server/mcp-server-tools-reference.md).
- **Release notes**: search `release notes <version>` before bumping `N8N_VERSION`; breaking changes and renamed variables are listed per release.

## Repository checks

- A task that adds, renames or removes a variable in [compose/n8n/](../../../compose/n8n/) confirms each one with the routine above and names the page in the report. The compose files set `N8N_*` keys the documentation may not know (an unknown key is silently ignored by n8n): flag such a key, do not delete it unprompted.
- A feature gated by edition or version is confirmed against `N8N_VERSION` and the variant before it is enabled; the [known deviations](../develop/resources/compose-catalogue.md#known-deviations-do-not-fix-unprompted) list stays untouched.
- Product answers for the user (what a node does, how a feature works, which setting to change) come from the documentation with the page link, in prose; the compose files are only changed when the task asks for it.
