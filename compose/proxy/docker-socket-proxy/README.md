# docker-socket-proxy

[socket-proxy](https://github.com/linuxserver/docker-socket-proxy) by LinuxServer.io exposes a filtered, read-only view of the Docker socket over HTTP. Traefik reads container labels through it instead of mounting the socket itself; it lives on `n8n-starter-private` only and always starts with Tilt. Networks: [SPEC.md](../../../SPEC.md#docker-networks).

- Homepage: <https://www.linuxserver.io/>
- Repository: <https://github.com/linuxserver/docker-socket-proxy>
- Docker image: <https://hub.docker.com/r/linuxserver/socket-proxy>
- Documentation: <https://docs.linuxserver.io/images/docker-socket-proxy/>
- Releases: <https://github.com/linuxserver/docker-socket-proxy/releases>
