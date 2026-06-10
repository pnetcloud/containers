# CloudNativePG TimescaleDB Containers

This repository builds public CloudNativePG-compatible PostgreSQL images for GHCR namespace `ghcr.io/pnetcloud/cloudnative-pg-timescaledb`.

The image family adds TimescaleDB, TimescaleDB Toolkit when available, pgvector, and PGAudit on top of CloudNativePG standard PostgreSQL images. Backup integration for v1 is through the CloudNativePG Barman Cloud Plugin path; legacy in-image `barman-cloud` binaries are not part of the image scope.

Supported PostgreSQL majors are PostgreSQL `17`, PostgreSQL `18`, and experimental PostgreSQL `19beta1`. Debian `trixie` is the primary recommended variant, and Debian `bookworm` is the secondary variant. Alpine, Debian `bullseye`, legacy PostgreSQL majors, and Artifact Hub metadata are out of scope for v1.

Use PostgreSQL major tags for examples and automation, such as:

```text
ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18
```

`latest` is convenience-only in v1 and points to PostgreSQL `18` on Debian `trixie`. Prefer explicit PostgreSQL major tags for production manifests.

## Image Tags

Immutable `trixie` tags use the form `{major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}`, for example `18-pg18.4-ts2.27.2-20260609`. Debian `bookworm` tags append `-bookworm`, for example `18-pg18.4-ts2.27.2-20260609-bookworm` and rolling `18-bookworm`.

Use major-prefixed tags in CloudNativePG `imageName` fields. `latest` is convenience-only for PostgreSQL `18` on Debian `trixie`; PostgreSQL `19beta1` is experimental and never receives `latest` or normal rolling tags. Experimental preview examples use immutable tags such as `19beta1-pg19beta1-ts2.27.2-20260609`.

```yaml
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609
```

See [docs/image-tags.md](docs/image-tags.md) for CloudNativePG image examples and tag selection guidance.

See [cloudnative-pg-timescaledb/README.md](cloudnative-pg-timescaledb/README.md) for the package overview and [cloudnative-pg-timescaledb/docs/generated/compatibility-table.md](cloudnative-pg-timescaledb/docs/generated/compatibility-table.md) for the generated compatibility table.
