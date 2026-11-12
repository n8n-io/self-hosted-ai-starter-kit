# n8n

[n8n](https://n8n.io/) is the workflow automation platform this kit is built around. It is served by traefik at `DOMAIN`; the database (SQLite or postgres) and the task runner mode (internal or external) depend on the variant. `N8N_VARIANT` in the root `.env` picks one of the compose files below; each extends the previous one. The canonical table and the rules of the cascade: [SPEC.md](../../SPEC.md#composen8n-variants); keys and knobs: [.env.template](./.env.template).

| Variant | File | Differs by |
| --- | --- | --- |
| `dev` | [docker-compose.yml](./docker-compose.yml) | one unlicensed n8n container in regular execution mode on SQLite with the internal task runner (JavaScript Code nodes only) |
| `build` | [docker-compose.build.yml](./docker-compose.build.yml) | postgres as the database and the external task runner sidecar (Python Code nodes too) |
| `community` | [docker-compose.community.yml](./docker-compose.community.yml) | queue mode: a worker with its own task runner, a webhook processor serving production webhooks at `hooks.<DOMAIN>`, redis as the broker |
| `enterprise` | [docker-compose.enterprise.yml](./docker-compose.enterprise.yml) | the license key on main, worker and webhook processor; S3 binary data, external secrets and multi-main still to be wired up |

- Homepage: <https://n8n.io/>
- Repository: <https://github.com/n8n-io/n8n>
- Docker image (n8n, pulled from `docker.n8n.io`): <https://hub.docker.com/r/n8nio/n8n>
- Docker image (task runners): <https://hub.docker.com/r/n8nio/runners>
- Documentation: <https://docs.n8n.io/>, in particular [Docker installation](https://docs.n8n.io/hosting/installation/docker/), [task runners](https://docs.n8n.io/hosting/configuration/task-runners/) and [queue mode](https://docs.n8n.io/hosting/scaling/queue-mode/)
- API reference: <https://docs.n8n.io/api/>
- Releases: <https://docs.n8n.io/release-notes/>
