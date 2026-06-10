# Valid Troubleshooting Fixture

The public docs reference `cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md`.

Debian trixie is the primary variant and Debian bookworm is the secondary variant. `hard_fail` means the gate blocks release. Use `publish: false` with `skip_reason` only for intentionally unpublished combinations.

## `metadata.invalid`

- `reason_id`: `metadata.invalid`
- `category`: invalid metadata
- `applies_to`: versions.yaml validation
- `gate_or_command`: `validate-metadata.sh`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Invalid metadata must be fixed.
- `local_command`: `make validate`
- `remediation`: Fix versions.yaml.
- `trixie_bookworm_notes`: same

## `generated.stale`

- `reason_id`: `generated.stale`
- `category`: stale generated files
- `applies_to`: generated artifacts
- `gate_or_command`: `validate-generated.sh`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Regenerate files instead.
- `local_command`: `make generate && make validate`
- `remediation`: Regenerate and commit outputs.
- `trixie_bookworm_notes`: same

## `package.unsupported-combination`

- `reason_id`: `package.unsupported-combination`
- `category`: unsupported package combinations
- `applies_to`: package resolver
- `gate_or_command`: `make update`
- `hard_fail`: `false`
- `publish_false_skip_reason_allowed`: Yes. Keep publish: false with skip_reason until upstream packages exist.
- `local_command`: `make update UPDATE_ARGS=--json`
- `remediation`: Resolve package versions or keep the row skipped.
- `trixie_bookworm_notes`: trixie uses debian13 packages and bookworm uses debian12 packages.

## `tag.policy-invalid`

- `reason_id`: `tag.policy-invalid`
- `category`: wrong tag policy
- `applies_to`: tag generation
- `gate_or_command`: `validate-tags.sh`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Fix tag policy before release.
- `local_command`: `bash cloudnative-pg-timescaledb/scripts/validate-tags.sh --metadata cloudnative-pg-timescaledb/versions.yaml --date 20260609`
- `remediation`: Regenerate tags from metadata.
- `trixie_bookworm_notes`: trixie is suffixless and bookworm uses the -bookworm suffix.

## `tag.latest-invalid`

- `reason_id`: `tag.latest-invalid`
- `category`: wrong latest
- `applies_to`: latest tag assignment
- `gate_or_command`: `make matrix`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. latest must be fixed.
- `local_command`: `make matrix && make validate`
- `remediation`: Keep latest only on PostgreSQL 18 trixie.
- `trixie_bookworm_notes`: trixie PostgreSQL 18 is latest and bookworm never receives latest.

## `postgresql.pg19-experimental-policy`

- `reason_id`: `postgresql.pg19-experimental-policy`
- `category`: PostgreSQL 19beta1 experimental failures
- `applies_to`: experimental metadata
- `gate_or_command`: `make validate`
- `hard_fail`: `false`
- `publish_false_skip_reason_allowed`: Yes. Keep publish: false with skip_reason while experimental.
- `local_command`: `make matrix && make validate`
- `remediation`: Keep experimental true and latest_eligible false.
- `trixie_bookworm_notes`: same

## `build.docker-failed`

- `reason_id`: `build.docker-failed`
- `category`: Docker build failures
- `applies_to`: image builds
- `gate_or_command`: `make build`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: Yes. Only intentionally disabled rows may remain publish: false with skip_reason before release.
- `local_command`: `make build PG=18 DEBIAN=trixie`
- `remediation`: Inspect Dockerfile and package install logs.
- `trixie_bookworm_notes`: trixie uses debian13 package versions and bookworm uses debian12 package versions.

## `runtime.postgresql-startup-failed`

- `reason_id`: `runtime.postgresql-startup-failed`
- `category`: PostgreSQL startup failures
- `applies_to`: container smoke
- `gate_or_command`: `make smoke`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Startup failures block promotion.
- `local_command`: `make smoke PG=18 DEBIAN=trixie CHECKS=container`
- `remediation`: Inspect PostgreSQL logs and image labels.
- `trixie_bookworm_notes`: same

## `smoke.sql-extension-failed`

- `reason_id`: `smoke.sql-extension-failed`
- `category`: SQL smoke failures
- `applies_to`: extension smoke
- `gate_or_command`: `make smoke`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. SQL smoke failures block promotion.
- `local_command`: `make smoke PG=18 DEBIAN=trixie CHECKS=sql`
- `remediation`: Verify TimescaleDB, Toolkit, pgvector, and pgaudit.
- `trixie_bookworm_notes`: trixie and bookworm can differ by package repository build.

## `evidence.sbom-missing`

- `reason_id`: `evidence.sbom-missing`
- `category`: missing SBOM
- `applies_to`: release evidence
- `gate_or_command`: `release evidence verification`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Missing SBOM blocks release.
- `local_command`: `make validate`
- `remediation`: Rebuild with SBOM attestations.
- `trixie_bookworm_notes`: same

## `evidence.provenance-missing`

- `reason_id`: `evidence.provenance-missing`
- `category`: missing provenance
- `applies_to`: release evidence
- `gate_or_command`: `release evidence verification`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Missing provenance blocks release.
- `local_command`: `make validate`
- `remediation`: Rebuild with provenance attestations.
- `trixie_bookworm_notes`: same

## `evidence.signature-missing`

- `reason_id`: `evidence.signature-missing`
- `category`: missing signature
- `applies_to`: signing evidence
- `gate_or_command`: `cosign sign`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Missing signature blocks release.
- `local_command`: `make validate`
- `remediation`: Re-run keyless signing and verification.
- `trixie_bookworm_notes`: same

## `scan.vulnerability-threshold-failed`

- `reason_id`: `scan.vulnerability-threshold-failed`
- `category`: vulnerability threshold failures
- `applies_to`: security scan
- `gate_or_command`: `security-scan.yml`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Vulnerability threshold failures block normal releases.
- `local_command`: `trivy image --scanners vuln --severity HIGH,CRITICAL --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml <image-ref>`
- `remediation`: Fix packages or add a reviewed ignore.
- `trixie_bookworm_notes`: trixie and bookworm scan results are evaluated independently.

## `catalog.reference-invalid`

- `reason_id`: `catalog.reference-invalid`
- `category`: catalog reference failures
- `applies_to`: ClusterImageCatalog
- `gate_or_command`: `make catalog`
- `hard_fail`: `true`
- `publish_false_skip_reason_allowed`: No. Invalid catalog references block release.
- `local_command`: `make catalog && make validate`
- `remediation`: Regenerate catalogs from release metadata.
- `trixie_bookworm_notes`: trixie catalog is primary and bookworm catalog is secondary.
