# CloudNativePG TimescaleDB Images

This directory contains the source for CloudNativePG-compatible PostgreSQL images published under GHCR namespace `ghcr.io/pnetcloud/cloudnative-pg-timescaledb`.

The image family layers TimescaleDB, TimescaleDB Toolkit when available, pgvector, and PGAudit onto CloudNativePG standard PostgreSQL images. Barman-related backup support is intentionally outside the image filesystem: use the CloudNativePG Barman Cloud Plugin path for backup integration, and legacy in-image `barman-cloud` binaries are not part of v1 images.

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for image lines. Generated Dockerfiles, workflow matrices, catalog manifests, generated documentation, and README tables must be derived from that metadata instead of maintained as competing sources.

Initial metadata covers PostgreSQL `17`, PostgreSQL `18`, and experimental PostgreSQL `19beta1` across Debian `trixie` and `bookworm`. Debian `trixie` is the primary recommended variant, and Debian `bookworm` is the secondary variant. PostgreSQL `19beta1` is experimental everywhere it appears.

Alpine, Debian `bullseye`, legacy PostgreSQL majors outside `17`, `18`, and experimental `19beta1`, and Artifact Hub metadata are out of scope for v1.

Use PostgreSQL major tags in CloudNativePG manifests and automation, for example:

```text
ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18
```

`latest` is convenience-only in v1 and points to PostgreSQL `18` on Debian `trixie`. Prefer explicit PostgreSQL major tags over `latest` in operator-managed manifests.

The compatibility overview is generated from `cloudnative-pg-timescaledb/versions.yaml`:

- `cloudnative-pg-timescaledb/docs/generated/compatibility.md`
- `cloudnative-pg-timescaledb/docs/generated/compatibility-table.md`

The current metadata keeps every entry at `publish: false` until the release gates explicitly enable buildable image lines. Skipped entries keep a non-empty `skip_reason`; generated Dockerfiles and Bake targets are emitted only for publishable entries.

The `vendor/` tree is reference-only. Production image definitions and workflows must use generated project files and upstream package sources instead of copying from the vendored examples.

## Command Surface

Use the root `Makefile` for local development and CI entry points. The stable targets are `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke`.

`make bake-print` prints the generated Docker Buildx Bake plan from `cloudnative-pg-timescaledb/docker-bake.hcl`. The plan uses checkout/path context and contains no registry push output.

`make build` and `make smoke` require `PG=<17|18|19beta1>` and `DEBIAN=<trixie|bookworm>`. `make build PG=<major> DEBIAN=<variant>` invokes the selected local Bake target with `output=type=docker` and a single local `PLATFORM` override, defaulting to `linux/amd64`. If the selected row is still `publish: false`, the command exits non-zero with the target name, Dockerfile path, context, platform, and `skip_reason`.

`make smoke PG=<major> DEBIAN=<variant> CHECKS=container` runs container-level smoke checks for a locally built image line. It verifies Debian release, PostgreSQL version, required extension control files, image labels, CNPG runtime binaries, the `postgres` user, data directory permissions, and temporary PostgreSQL startup.

`make smoke PG=<major> DEBIAN=<variant> CHECKS=sql` runs SQL extension smoke checks for a locally built image line. It verifies basic SQL execution, server version, canonical `shared_preload_libraries=timescaledb,pgaudit`, TimescaleDB and Toolkit extension versions, TimescaleDB library availability, pgvector/PGAudit creation or explicitly documented validation-only policy, and deterministic diagnostics for publish-blocking failures.
