# Generator Contracts

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for image generator inputs. Generator scripts derive Dockerfile paths or skipped markers, Bake targets, matrix rows, stable catalog paths, and generated documentation from that metadata and release metadata.

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
{"dockerfiles":[{"pg_major":"18","debian_variant":"trixie","dockerfile":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile","skipped_marker":"","base_image":"ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie@sha256:...","source_entry":"18-trixie","publish":true,"experimental":false,"skip_reason":""}]}
```

Consumers must require `pg_major`, `debian_variant`, `dockerfile`, `skipped_marker`, `base_image`, `source_entry`, `publish`, `experimental`, and `skip_reason` for every row. Publishable rows expose `dockerfile` and `base_image` and leave `skipped_marker` empty. Skipped rows expose `skipped_marker` and leave `dockerfile` and `base_image` empty so non-publishable rows cannot be built accidentally.

## Bake

Command: `cloudnative-pg-timescaledb/scripts/generate-bake.sh`

Default output: `cloudnative-pg-timescaledb/docker-bake.hcl`

Required JSON keys:

```json
{"bake_file":"cloudnative-pg-timescaledb/docker-bake.hcl","targets":[],"skipped":[]}
```

Consumers must require `bake_file` plus target `name`, `context`, `dockerfile`, `platforms`, `publish`, and `experimental` for every target. The buildable target list contains only publishable entries. Skipped rows remain in `skipped[]` with `pg_major`, `debian_variant`, `name`, `skipped_marker`, `publish`, `experimental`, and `skip_reason`.

## Matrix

Command: `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`

Default outputs: `cloudnative-pg-timescaledb/matrix.json` and `cloudnative-pg-timescaledb/docs/generated/matrix-schema.md`

Required JSON keys:

```json
{"include":[{"bake_target":"pg18-trixie","candidate_ref":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609","debian_variant":"trixie","digest":"","dockerfile":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile","experimental":false,"image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb","intended_tags":["18","18-pg18.4-ts2.27.2-20260609","latest"],"latest_eligible":true,"pg_major":"18","pg_version":"18.4","platforms":["linux/amd64","linux/arm64"],"provenance_ref":"","publish":true,"release_date":"20260609","sbom_ref":"","scan_result":"pending","signature_ref":"","timescaledb_version":"2.27.2"}],"skipped":[{"bake_target":"pg19beta1-trixie","debian_variant":"trixie","experimental":true,"latest_eligible":false,"pg_major":"19beta1","pg_version":"19beta1","platforms":["linux/amd64","linux/arm64"],"publish":false,"skip_reason":"Experimental PostgreSQL 19beta1 pending upstream support","skipped_marker":"cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile.skipped.json"}]}
```

Consumers must require `include[]` rows with `pg_major`, `pg_version`, `timescaledb_version`, `debian_variant`, `image`, `candidate_ref`, `release_date`, `digest`, `platforms`, `bake_target`, `dockerfile`, `intended_tags`, `publish`, `experimental`, `latest_eligible`, `scan_result`, `sbom_ref`, `provenance_ref`, and `signature_ref`. Skipped rows must require `pg_major`, `pg_version`, `debian_variant`, `platforms`, `bake_target`, `skipped_marker`, `publish`, `experimental`, `latest_eligible`, and `skip_reason` and must expose marker paths, not buildable Dockerfile paths. Generator summaries preserve metadata `latest_eligible`; workflow validators reject skipped rows that try to own `latest` and require the sole publishable `latest_eligible: true` row to be PostgreSQL `18` on Debian `trixie`.

## Catalog

Command: `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`

Default output root: `cloudnative-pg-timescaledb/catalog/`

Required JSON keys:

```json
{"catalogs":[{"debian_variant":"trixie","catalog_path":"cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml","entries":[{"pg_major":"18","debian_variant":"trixie","image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-00000000","digest":"","publish":true,"experimental":false,"latest_eligible":true,"skip_reason":""}]},{"debian_variant":"bookworm","catalog_path":"cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml","entries":[{"pg_major":"18","debian_variant":"bookworm","image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-00000000-bookworm","digest":"","publish":true,"experimental":false,"latest_eligible":false,"skip_reason":""}]}]}
```

Consumers must require top-level `catalogs[]` rows with `debian_variant`, `catalog_path`, and `entries`. Catalog JSON entries always include metadata-derived `pg_major`, `debian_variant`, `image`, `digest`, `publish`, `experimental`, `latest_eligible`, and `skip_reason`; without release-complete metadata, `digest` is empty and the rendered stable catalog YAML intentionally contains `spec.images: []`. When `--release-metadata` is supplied, each release-complete catalog entry must also require numeric `major`, immutable `tag`, `source_entry`, `platforms`, and `release_metadata_record_id`. Stable catalog YAML contains only release-complete PostgreSQL `17` and `18` rows for their matching Debian variant; experimental PostgreSQL `19beta1` stays out of stable catalogs unless a later explicit experimental catalog is introduced.

The catalog generator still preserves the Story 1.5 metadata-derived contract by keeping every JSON row tied to the metadata variant. Metadata-only JSON rows may include placeholder tag references with empty `digest`; they are summaries, not release catalog candidates. Stable `ClusterImageCatalog` YAML entries are emitted only after the publish workflow supplies the digest, immutable tag, platform digest set, signature, SBOM, provenance, and release metadata record that prove the row is safe to reference from CloudNativePG.

## Docs

Command: `cloudnative-pg-timescaledb/scripts/generate-docs.sh`

Default output: `cloudnative-pg-timescaledb/docs/generated/compatibility.md` plus generated docs owned by the docs generator in the same directory: `compatibility-table.md`, `release-candidate-schema.md`, `release-evidence-schema.md`, `failure-reason-catalog.md`, and `barman-plugin-reference.md` when CloudNativePG Barman Cloud Plugin metadata exists. The generated docs manifest also enumerates `matrix-schema.md` from `generate-matrix.sh` and `release-rehearsal-report.md` from `release-rehearsal.sh` so drift validation and autocommit paths cover the full generated docs set.

Required JSON keys (abridged example; the manifest list in generated output is canonical and must enumerate every generated docs artifact in contract order):

```json
{"docs":[{"doc_path":"cloudnative-pg-timescaledb/docs/generated/compatibility.md","companion_paths":["cloudnative-pg-timescaledb/docs/generated/compatibility-table.md"],"source":"cloudnative-pg-timescaledb/versions.yaml","sections":["compatibility"],"publishable_entries":4,"experimental_entries":2}],"generated_docs_manifest":[{"path":"cloudnative-pg-timescaledb/docs/generated/compatibility.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"1.5","deterministic_generation_mode":"metadata-rendered compatibility skeleton"},{"path":"cloudnative-pg-timescaledb/docs/generated/compatibility-table.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"5.1","deterministic_generation_mode":"metadata-rendered compatibility table"},{"path":"cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"4.2","deterministic_generation_mode":"static generated schema documentation"},{"path":"cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"4.4","deterministic_generation_mode":"static generated schema documentation"},{"path":"cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"5.8","deterministic_generation_mode":"static generated failure reason catalog"},{"path":"cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md","generator_input":"cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/valid-full-matrix.json;cloudnative-pg-timescaledb/config/release-rehearsal.yaml;DATE=20260609;DRY_RUN=1","generator_command":"cloudnative-pg-timescaledb/scripts/release-rehearsal.sh","owner_story":"5.9","deterministic_generation_mode":"dry-run release rehearsal report"},{"path":"cloudnative-pg-timescaledb/docs/generated/matrix-schema.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-matrix.sh","owner_story":"4.1","deterministic_generation_mode":"static generated matrix schema documentation"},{"path":"cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"2.7","deterministic_generation_mode":"metadata-rendered Barman Cloud Plugin reference"}]}
```

Consumers must require `docs[]` rows with `doc_path`, `companion_paths`, `source`, `sections`, `publishable_entries`, and `experimental_entries`. Consumers must also require `generated_docs_manifest[]` rows with `path`, `generator_input`, `generator_command`, `owner_story`, and `deterministic_generation_mode`. `make generate` regenerates the release rehearsal report from deterministic fixture evidence instead of preserving stale docs from a prior checkout.
