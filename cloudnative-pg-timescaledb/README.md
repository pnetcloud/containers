# CloudNativePG TimescaleDB Images

This directory contains the source for CloudNativePG-compatible PostgreSQL images with TimescaleDB-related extensions.

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for image lines. Generated Dockerfiles, workflow matrices, catalog manifests, generated documentation, and README tables must be derived from that metadata instead of maintained as competing sources.

Initial metadata covers PostgreSQL `17`, PostgreSQL `18`, and experimental PostgreSQL `19beta1` across Debian `trixie` and `bookworm`. Debian `trixie` is the primary variant, and Debian `bookworm` is the secondary variant.

The scaffold intentionally keeps resolver-owned values empty while every entry has `publish: false` and a non-empty `skip_reason`. Later resolver stories populate CNPG digests and package versions before any image becomes publishable.

The `vendor/` tree is reference-only. Production image definitions and workflows must use generated project files and upstream package sources instead of copying from the vendored examples.

## Command Surface

Use the root `Makefile` for local development and CI entry points. The stable targets are `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke`.

`make build` and `make smoke` require `PG=<17|18|19beta1>` and `DEBIAN=<trixie|bookworm>`. Story 1.2 validates this command surface and returns documented non-zero exit codes for behavior owned by later stories.
