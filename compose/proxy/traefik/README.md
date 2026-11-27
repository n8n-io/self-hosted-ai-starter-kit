# traefik

[Traefik](https://traefik.io/traefik/) is a reverse proxy that discovers its routes from container labels. It is the edge of this kit: every service labelled `traefik.enable=true` is served at `<service>.<DOMAIN>`, n8n at the bare `DOMAIN`, and it always starts with Tilt. Routing rules: [SPEC.md](../../../SPEC.md#routing); knobs: [.env.template](./.env.template).

- Homepage: <https://traefik.io/traefik/>
- Repository: <https://github.com/traefik/traefik>
- Docker image: <https://hub.docker.com/_/traefik>
- Documentation: <https://doc.traefik.io/traefik/>
- API reference: <https://doc.traefik.io/traefik/operations/api/>
- Releases: <https://github.com/traefik/traefik/releases>
