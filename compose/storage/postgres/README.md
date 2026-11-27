# postgres

[PostgreSQL](https://www.postgresql.org/) is the relational database n8n stores its workflows, credentials and executions in. It always starts with Tilt, on `n8n-starter-private` only; [init-data.sh](./init-data.sh) creates the n8n role on the first start. Secrets and knobs: [.env.template](./.env.template) and [SPEC.md](../../../SPEC.md#secrets).

- Homepage: <https://www.postgresql.org/>
- Repository: <https://github.com/postgres/postgres>
- Docker image: <https://hub.docker.com/_/postgres>
- Documentation: <https://www.postgresql.org/docs/17/>
- Releases: <https://www.postgresql.org/docs/release/>
