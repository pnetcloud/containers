# CloudNativePG TimescaleDB Images

This directory contains the source for CloudNativePG-compatible PostgreSQL images with TimescaleDB-related extensions.

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for image lines. Generated Dockerfiles, workflow matrices, catalog manifests, generated documentation, and README tables must be derived from that metadata instead of maintained as competing sources.

Initial metadata covers PostgreSQL `17`, PostgreSQL `18`, and experimental PostgreSQL `19beta1` across Debian `trixie` and `bookworm`. Debian `trixie` is the primary variant, and Debian `bookworm` is the secondary variant.

The current metadata keeps every entry at `publish: false` until the release gates explicitly enable buildable image lines. Skipped entries keep a non-empty `skip_reason`; generated Dockerfiles and Bake targets are emitted only for publishable entries.

The `vendor/` tree is reference-only. Production image definitions and workflows must use generated project files and upstream package sources instead of copying from the vendored examples.

## Command Surface

Use the root `Makefile` for local development and CI entry points. The stable targets are `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke`.

`make bake-print` prints the generated Docker Buildx Bake plan from `cloudnative-pg-timescaledb/docker-bake.hcl`. The plan uses checkout/path context and contains no registry push output.

`make build` and `make smoke` require `PG=<17|18|19beta1>` and `DEBIAN=<trixie|bookworm>`. `make build PG=<major> DEBIAN=<variant>` invokes the selected local Bake target with `output=type=docker` and a single local `PLATFORM` override, defaulting to `linux/amd64`. If the selected row is still `publish: false`, the command exits non-zero with the target name, Dockerfile path, context, platform, and `skip_reason`.

`make smoke PG=<major> DEBIAN=<variant> CHECKS=container` runs container-level smoke checks for a locally built image line. It verifies Debian release, PostgreSQL version, required extension control files, image labels, CNPG runtime binaries, the `postgres` user, data directory permissions, and temporary PostgreSQL startup. `CHECKS=sql` is reserved for the SQL extension smoke story.
