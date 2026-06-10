# Maintainer Fixture

## Release Process

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited image source of truth. Generated outputs are committed for reviewability, but they must not be hand-edited as final fixes.

Use `make help`, `make update`, `make generate`, `make validate`, `make matrix`, `make bake-print`, `make catalog`, `make build PG=18 DEBIAN=trixie`, and `make smoke PG=18 DEBIAN=trixie`.

`make update` refreshes CloudNativePG base image, TimescaleDB, Toolkit, and Barman Cloud Plugin references. Renovate manages GitHub Actions and static helper dependencies.

Scheduled update no-op runs create no commit. Autocommit uses path allowlists in `autocommit-allowlist.txt` and `catalog-autocommit-allowlist.txt`, and loop prevention stops bot/generated recursion.

`GITHUB_TOKEN` is the default autocommit mechanism. A PAT personal access token fallback is only a branch-protection exception, and the security tradeoff is broader token blast radius.

Never commit `.env` files or print secrets, credentials, tokens, registry passwords, or signing secrets.

Artifact Hub metadata is out of v1 release scope. Release maintainers should publish Artifact Hub metadata after catalog generation, although Artifact Hub is out of v1 scope.

| Path or glob | Source of truth | Generator command | Commit policy | Hand-edit policy |
| --- | --- | --- | --- | --- |
| `cloudnative-pg-timescaledb/generated/{pg}/{debian_variant}/Dockerfile` | `versions.yaml` | `make generate` | Commit validated output. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/docker-bake.hcl` | `versions.yaml` | `make generate` / `make bake-print` | Commit validated output. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/matrix.json` | `versions.yaml` | `make matrix` | Commit deterministic output. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` | release metadata | `make catalog` | Commit through allowlist. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` | release metadata | `make catalog` | Commit through allowlist. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/docs/generated/**` | metadata and templates | `make generate` | Commit after `make validate`. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/config/generated/**` | resolver metadata | `make update` | Commit allowlisted output. | Do not hand-edit as final fix. |
| `.github/workflows/**` | workflow templates | owning generator | Commit after validation. | Regenerate generated sections. |
