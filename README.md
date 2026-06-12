# pnetcloud containers

This repository contains public container image sources, release automation, and operating notes used by pnetcloud projects.

The repository is intentionally small and practical: each image family keeps its detailed build and usage documentation next to its source, while this root README stays as a map of what is available.

## Available Images

| Image | Registry | What it is | Docs |
| --- | --- | --- | --- |
| CloudNativePG TimescaleDB | `ghcr.io/pnetcloud/cloudnative-pg-timescaledb` | CloudNativePG-compatible PostgreSQL images with TimescaleDB, TimescaleDB Toolkit when available, pgvector, and PGAudit. | [cloudnative-pg-timescaledb/README.md](cloudnative-pg-timescaledb/README.md) |

## Quick Start

Pull the current PostgreSQL 18 image line:

```bash
docker pull ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18
```

For production rollouts, prefer immutable tags or digest-pinned references. Tag rules and CloudNativePG examples are in [docs/image-tags.md](docs/image-tags.md).

## Documentation

- [Documentation index](docs/README.md) - start here when looking for usage, maintenance, release, and verification docs.
- [CloudNativePG TimescaleDB image docs](cloudnative-pg-timescaledb/README.md) - image contents, supported PostgreSQL/Debian lines, catalog usage, CloudNativePG Barman Cloud Plugin backup boundary, and command surface.
- [Image tags](docs/image-tags.md) - immutable tags, rolling tags, and CloudNativePG `imageName` examples.
- [ClusterImageCatalog usage](docs/catalog.md) - generated CloudNativePG catalog manifests.
- [Verifying images](docs/user-guide/verifying-images.md) - cosign, release evidence, vulnerability policy, and image labels.
- [Maintainer guide](docs/maintainer-guide.md) - update, generation, validation, release, and cleanup workflow.
- [Troubleshooting](docs/troubleshooting.md) - common build, smoke test, catalog, and release issues.

## Working Locally

Use the root `Makefile` for the supported command surface:

```bash
make help
make validate
make build PG=18 DEBIAN=trixie
make smoke PG=18 DEBIAN=trixie
```

Generated Dockerfiles, workflow matrices, catalogs, and generated docs are derived from image metadata. For the CloudNativePG TimescaleDB image family, edit `cloudnative-pg-timescaledb/versions.yaml` and regenerate outputs instead of hand-editing generated files.

## Contributing

Small fixes are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, especially the notes about generated files and validation.

## Security

Public image verification and vulnerability gates are described in [docs/user-guide/verifying-images.md](docs/user-guide/verifying-images.md). To report a sensitive security issue, follow [SECURITY.md](SECURITY.md).

## License

This repository is released under the [MIT License](LICENSE).
