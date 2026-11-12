# garage

[Garage](https://garagehq.deuxfleurs.fr/) is a lightweight S3-compatible object store, intended for n8n's binary data in the `enterprise` variant (still to be wired up). Traefik serves the S3 API at `s3.<DOMAIN>` and the web endpoint at `s3web.<DOMAIN>`; the bundled [garage-webui](https://github.com/khairul169/garage-webui) at `s3ui.<DOMAIN>`. Both start on demand from the Tilt UI. Node configuration: [garage.toml](./garage.toml); routing: [SPEC.md](../../../SPEC.md#routing).

- Homepage: <https://garagehq.deuxfleurs.fr/>
- Repository: <https://git.deuxfleurs.fr/Deuxfleurs/garage>
- Docker image: <https://hub.docker.com/r/dxflrs/garage>
- Documentation: <https://garagehq.deuxfleurs.fr/documentation/quick-start/>
- API reference: [S3 compatibility](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/), [admin API](https://garagehq.deuxfleurs.fr/api/garage-admin-v2.html)
- Releases: <https://git.deuxfleurs.fr/Deuxfleurs/garage/releases>

## garage-webui

- Repository: <https://github.com/khairul169/garage-webui>
- Docker image: <https://hub.docker.com/r/khairul169/garage-webui>
