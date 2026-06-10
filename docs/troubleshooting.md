# Troubleshooting

Use this page when validation, update, build, publish, catalog, or security workflows fail for `ghcr.io/pnetcloud/cloudnative-pg-timescaledb`.

The generated failure reason catalog is `cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md`. Treat that catalog as the structured reason ID reference and this page as the operator playbook.

Barman-related checks refer to the CloudNativePG Barman Cloud Plugin integration path. The PostgreSQL image remains free of legacy in-image backup binaries.

Debian `trixie` is the primary variant. Debian `bookworm` is the secondary variant. When package or catalog behavior differs, fix and verify the failing variant independently instead of assuming the other variant has the same package repository state.

`hard_fail: true` means the release gate must stop until the root cause is fixed and validation passes. `publish: false` with `skip_reason` is allowed only for combinations that are intentionally not publishable before release, such as unresolved upstream package support or experimental PostgreSQL `19beta1` rows. Do not bypass scan, SBOM, provenance, signing, publish, catalog, permissions, or validation gates for normal releases.

## Quick Commands

| Failure area | Local command |
| --- | --- |
| Full validation | `make validate` |
| Metadata schema | `bash cloudnative-pg-timescaledb/scripts/validate-metadata.sh` |
| Generated drift | `make generate && make validate` |
| Tag policy | `bash cloudnative-pg-timescaledb/scripts/validate-tags.sh --metadata cloudnative-pg-timescaledb/versions.yaml --date 20260609` |
| Matrix/latest policy | `make matrix && make validate` |
| Update resolver | `make update UPDATE_ARGS=--json` |
| Build smoke | `make build PG=18 DEBIAN=trixie` |
| Runtime smoke | `make smoke PG=18 DEBIAN=trixie CHECKS=container` |
| SQL smoke | `make smoke PG=18 DEBIAN=trixie CHECKS=sql` |
| Catalog validation | `make catalog && make validate` |
| Vulnerability scan | `trivy image --scanners vuln --severity HIGH,CRITICAL --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml <image-ref>` |

## Failure Reasons

| Reason ID | What failed | Hard fail or skipped row | First remediation |
| --- | --- | --- | --- |
| `metadata.invalid` | Invalid metadata in `versions.yaml`. | Hard fail. Do not use `publish: false` to hide invalid metadata. | Fix schema, allowed PostgreSQL majors, Debian variants, platforms, Barman plugin metadata, and entry fields; run `make validate`. |
| `generated.stale` | Stale generated files. | Hard fail. Do not hand-edit generated files as final fixes. | Run `make generate && make validate`, then commit generated output. |
| `package.unsupported-combination` | Unsupported package combinations for TimescaleDB or Toolkit. | May remain `publish: false` with `skip_reason` until upstream package support exists. | Run `make update UPDATE_ARGS=--json`; compare `trixie` debian13 package versions with `bookworm` debian12 package versions. |
| `tag.policy-invalid` | Wrong tag policy. | Hard fail. | Regenerate tags from metadata and the UTC date. `trixie` primary tags are suffixless; `bookworm` secondary tags use `-bookworm`. |
| `tag.latest-invalid` | Wrong `latest` assignment. | Hard fail. | Keep `latest` only on PostgreSQL `18` with Debian `trixie`; never on PostgreSQL `17`, `bookworm`, or experimental `19beta1`. |
| `postgresql.pg19-experimental-policy` | PostgreSQL `19beta1` experimental policy failure. | Usually `publish: false` with `skip_reason` until upstream support and policy change. | Keep `experimental: true`, `latest_eligible: false`, and no normal rolling tag for `19beta1`. |
| `build.docker-failed` | Docker build failure. | Hard fail for publishable rows. Do not convert a failed build into `publish: false`; rows intentionally disabled before build should use a metadata or package `skip_reason` instead. | Run `make build PG=18 DEBIAN=trixie`; inspect generated Dockerfile, CNPG digest, and variant package install logs. |
| `runtime.postgresql-startup-failed` | PostgreSQL startup failure. | Hard fail for publishable rows. | Run `make smoke PG=18 DEBIAN=trixie CHECKS=container`; inspect PostgreSQL logs, library paths, labels, and architecture mapping. |
| `smoke.sql-extension-failed` | SQL smoke or extension check failure. | Hard fail for publishable rows. | Run `make smoke PG=18 DEBIAN=trixie CHECKS=sql`; verify TimescaleDB, Toolkit, pgvector, and pgaudit inside the image. |
| `evidence.sbom-missing` | Missing SBOM evidence. | Hard fail. | Re-run candidate build with SBOM attestations and verify `sbom_ref` coverage for the index digest and every platform digest. |
| `evidence.provenance-missing` | Missing provenance evidence. | Hard fail. | Re-run candidate build with provenance attestations and verify `provenance_ref` coverage for the index digest and every platform digest. |
| `evidence.signature-missing` | Missing signature evidence. | Hard fail. | Re-run keyless cosign signing from the exact build workflow identity and verify `signature_ref` plus `verification_ref`. |
| `scan.vulnerability-threshold-failed` | Vulnerability threshold failure. | Hard fail for normal releases. | Fix base/package metadata or add a reviewed explicit ignore in `cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml` when justified. |
| `catalog.reference-invalid` | Catalog reference failure. | Hard fail. | Regenerate catalogs from release metadata; remove unpublished refs, tag-only refs, per-platform digests, experimental rows, and wrong Debian variant entries. |

## Variant Notes

`trixie` failures are primary release blockers for the normal image line. `bookworm` failures block that secondary image line and its catalog entries, but they must not cause `latest` to move away from PostgreSQL `18` on `trixie`.

For package resolution, `trixie` uses Debian 13 package builds and `bookworm` uses Debian 12 package builds. For catalogs, `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` must contain only `trixie` release metadata, and `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` must contain only `bookworm` release metadata.
