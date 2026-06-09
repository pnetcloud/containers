# Generator Contracts

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for image generator inputs. Generator scripts derive Dockerfile paths, Bake targets, matrix rows, catalog skeletons, and generated compatibility docs from that metadata.

All generator scripts support the same interface:

```bash
cloudnative-pg-timescaledb/scripts/<generator>.sh \
  --metadata cloudnative-pg-timescaledb/versions.yaml \
  --output <path> \
  --check \
  --json
```

`--metadata` defaults to `cloudnative-pg-timescaledb/versions.yaml`. `--output` overrides the default output file or root for generators that write a single artifact. `--check` compares generated content with committed output and exits non-zero on drift. `--json` writes compact machine JSON to stdout. Human diagnostics go to stderr.

## Dockerfiles

Command: `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`

Default output root: `cloudnative-pg-timescaledb/generated/`

Required JSON keys:

```json
{"dockerfiles":[{"pg_major":"18","debian_variant":"trixie","dockerfile":"","skipped_marker":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile.skipped.json","base_image":"","source_entry":"18-trixie","publish":false,"experimental":false,"skip_reason":"Pending Story 2 resolver population"}]}
```

Consumers must require `pg_major`, `debian_variant`, `dockerfile`, `skipped_marker`, `base_image`, `source_entry`, `publish`, `experimental`, and `skip_reason` for every row. Publishable rows expose `dockerfile` and `base_image` and leave `skipped_marker` empty. Skipped rows expose `skipped_marker` and leave `dockerfile` and `base_image` empty.

## Bake

Command: `cloudnative-pg-timescaledb/scripts/generate-bake.sh`

Default output: `cloudnative-pg-timescaledb/docker-bake.hcl`

Required JSON keys:

```json
{"bake_file":"cloudnative-pg-timescaledb/docker-bake.hcl","targets":[]}
```

Consumers must require `bake_file` plus target `name`, `context`, `dockerfile`, `platforms`, `publish`, and `experimental` for every target. The target list contains only publishable entries; it may be empty when all metadata rows are skipped.

## Matrix

Command: `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`

Default output: `cloudnative-pg-timescaledb/matrix.json`

Required JSON keys:

```json
{"include":[{"pg_major":"18","pg_version":"18.4","debian_variant":"trixie","platforms":["linux/amd64","linux/arm64"],"dockerfile":"","skipped_marker":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile.skipped.json","bake_target":"","publish":false,"experimental":false,"latest_eligible":true,"skip_reason":"Pending Story 2 resolver population"}]}
```

Consumers must require `include` rows with `pg_major`, `pg_version`, `debian_variant`, `platforms`, `dockerfile`, `skipped_marker`, `bake_target`, `publish`, `experimental`, `latest_eligible`, and `skip_reason`. Publishable rows expose `dockerfile` and `bake_target`; skipped rows expose `skipped_marker` only. Consumers must reject rows where `18-trixie` is not the sole `latest_eligible: true` row.

## Catalog

Command: `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`

Default output root: `cloudnative-pg-timescaledb/catalog/`

Required JSON keys:

```json
{"catalogs":[{"debian_variant":"trixie","catalog_path":"cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml","entries":[{"pg_major":"18","image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18-tsunresolved-00000000","digest":"","publish":false,"experimental":false,"latest_eligible":true,"skip_reason":"Pending Story 2 resolver population"}]}]}
```

Consumers must require `debian_variant`, `catalog_path`, and entry `pg_major`, `image`, `digest`, `publish`, `experimental`, `latest_eligible`, and `skip_reason`. Catalog generators preserve metadata `latest_eligible`; final digest-aware catalog behavior is owned by Story 4.6.

## Docs

Command: `cloudnative-pg-timescaledb/scripts/generate-docs.sh`

Default output: `cloudnative-pg-timescaledb/docs/generated/compatibility.md`

Required JSON keys:

```json
{"docs":[{"doc_path":"cloudnative-pg-timescaledb/docs/generated/compatibility.md","source":"cloudnative-pg-timescaledb/versions.yaml","sections":["compatibility"],"publishable_entries":0,"experimental_entries":2}]}
```

Consumers must require `doc_path`, `source`, `sections`, `publishable_entries`, and `experimental_entries`. Final public documentation validation is owned by Epic 5.
