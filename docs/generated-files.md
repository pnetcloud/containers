# Generated Files

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth and the only hand-edited image source of truth. Generated files are committed for reviewability, drift detection, and reproducible CI behavior, but they must not be hand-edited as final fixes.

If a generated file is wrong, update the source metadata, template, resolver, or generator that owns it. Then run the owning command, inspect the diff, and run `make validate` before committing.

## Ownership Matrix

| Path or glob | Source of truth | Generator command | Commit policy | Hand-edit policy |
| --- | --- | --- | --- | --- |
| `cloudnative-pg-timescaledb/generated/{pg}/{debian_variant}/Dockerfile` | `cloudnative-pg-timescaledb/versions.yaml` and Dockerfile templates | `make generate` / `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh` | Commit generated diffs after validation. | Do not hand-edit as final fix; edit metadata/templates and regenerate. |
| `cloudnative-pg-timescaledb/docker-bake.hcl` | `versions.yaml` and Bake generator templates | `make generate` / `cloudnative-pg-timescaledb/scripts/generate-bake.sh` | Commit generated diff after `make bake-print` and validation. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/matrix.json` | `versions.yaml` and matrix schema | `make matrix` / `cloudnative-pg-timescaledb/scripts/generate-matrix.sh` | Commit only deterministic generated output. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` | release-complete `trixie` metadata and published digests | `make catalog` / `cloudnative-pg-timescaledb/scripts/generate-catalog.sh` | Commit through catalog allowlist only after publish/evidence gates. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` | release-complete `bookworm` metadata and published digests | `make catalog` / `cloudnative-pg-timescaledb/scripts/generate-catalog.sh` | Commit through catalog allowlist only after publish/evidence gates. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/docs/generated/**` | `versions.yaml`, release metadata, catalog metadata, and docs templates | `make generate` / `cloudnative-pg-timescaledb/scripts/generate-docs.sh` | Commit deterministic generated docs/tables after docs validation. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/config/generated/**` | resolver and release metadata | `make update` or owning resolver script | Commit only allowlisted deterministic generated config. | Do not hand-edit as final fix. |
| `.github/workflows/**` generated sections, if any | workflow templates and repository policy files | owning generator or explicit workflow update story | Commit only after `actionlint` and permission validation. | Hand edits are allowed only to non-generated sections; generated sections must be regenerated. |

## Regeneration Rules

Run `make generate` after metadata, template, generator, or tag policy changes. The command regenerates Dockerfiles, Docker Buildx Bake definitions, matrix JSON, generated docs, and metadata-derived outputs from repository-owned inputs.

Run `make update` when refreshing resolver-owned CloudNativePG base image, TimescaleDB, TimescaleDB Toolkit, CloudNativePG Barman Cloud Plugin references, and regenerated outputs. `make update` does not own GitHub Actions or static helper dependency updates; those remain Renovate-managed.

Run `make catalog` only after release-complete publish metadata and digests are available. Catalog output must be committed through the catalog allowlist and must not reference unpublished images.

Run `make validate` before committing generated diffs. Validation must catch stale generated output, unsupported metadata drift, workflow policy issues, tag policy violations, catalog policy violations, docs drift, security policy failures, release evidence failures, and unsafe autocommit staging.

## Autocommit Boundaries

Scheduled update automation stages only allowlisted resolver-owned paths from `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`. Catalog automation stages only the stable catalog files listed in `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`.

No-op update runs must create no commits. Changed update runs must commit only allowlisted generated paths and must not recurse on bot/generated commits.

Never commit `.env` files, credentials, tokens, signing secrets, registry passwords, private keys, or secret-like values, whether hand-edited or generated.
