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

Default outputs: `cloudnative-pg-timescaledb/matrix.json` and `cloudnative-pg-timescaledb/docs/generated/matrix-schema.md`

Required JSON keys:

```json
{"include":[{"bake_target":"pg18-trixie","candidate_ref":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609","debian_variant":"trixie","digest":"","dockerfile":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile","experimental":false,"image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb","intended_tags":["18","18-pg18.4-ts2.27.2-20260609","latest"],"latest_eligible":true,"pg_major":"18","pg_version":"18.4","platforms":["linux/amd64","linux/arm64"],"provenance_ref":"","publish":true,"sbom_ref":"","scan_result":"pending","signature_ref":""}],"skipped":[]}
```

Consumers must require `include` rows with `pg_major`, `pg_version`, `debian_variant`, `image`, `candidate_ref`, `digest`, `platforms`, `bake_target`, `dockerfile`, `intended_tags`, `publish`, `experimental`, `latest_eligible`, `scan_result`, `sbom_ref`, `provenance_ref`, and `signature_ref`. Publishable rows belong in `include[]`; skipped rows belong in `skipped[]` with `publish: false` and `skip_reason`. Consumers must reject rows where a publishable `latest_eligible: true` row is anything other than non-experimental `18-trixie`.

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

Default output: `cloudnative-pg-timescaledb/docs/generated/compatibility.md` plus generated companion docs in the same directory, including `compatibility-table.md`, `release-candidate-schema.md`, and `release-evidence-schema.md`.

Required JSON keys:

```json
{"docs":[{"doc_path":"cloudnative-pg-timescaledb/docs/generated/compatibility.md","companion_paths":["cloudnative-pg-timescaledb/docs/generated/compatibility-table.md"],"source":"cloudnative-pg-timescaledb/versions.yaml","sections":["compatibility"],"publishable_entries":0,"experimental_entries":2}]}
```

Consumers must require `doc_path`, `companion_paths`, `source`, `sections`, `publishable_entries`, and `experimental_entries`. Public README validation consumes `compatibility-table.md` as the generated compatibility table. Release workflows must consume `release-candidate-schema.md` for Story 4.2 candidate metadata and `release-evidence-schema.md` for Story 4.4 supply-chain evidence. Final public documentation validation is owned by Epic 5.
