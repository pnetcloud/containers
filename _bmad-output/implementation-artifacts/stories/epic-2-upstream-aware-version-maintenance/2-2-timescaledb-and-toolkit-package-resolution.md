---
storyId: 2.2
storyKey: 2-2-timescaledb-and-toolkit-package-resolution
epic: 2
title: 'TimescaleDB and Toolkit Package Resolution'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: bdb1493
---

# Story 2.2: TimescaleDB and Toolkit Package Resolution

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Story 2.1 may be assumed complete.

## Out of Scope

- CNPG base image tag/digest lookup; owned by Story 2.1.
- Local update diff orchestration and scheduled autocommit; owned by Stories 2.3 and 2.5.
- Package installation in Dockerfiles and runtime SQL smoke; owned by Stories 3.2 and 3.5.
- Vulnerability, SBOM, provenance, signing, and publish release gates; owned by Epic 4.

## Source Story

### Story 2.2: TimescaleDB and Toolkit Package Resolution

As a maintainer,
I want TimescaleDB and Toolkit package versions resolved per PostgreSQL major, Debian variant, and platform,
So that image definitions only publish combinations that upstream packages can actually satisfy.

**Acceptance Criteria:**

**Given** valid metadata and upstream package repositories
**When** `resolve-versions.sh` checks TimescaleDB and Toolkit availability
**Then** it resolves `timescaledb_version`, `timescaledb_package_name`, `timescaledb_package_version`, `toolkit_version`, `toolkit_package_name`, and `toolkit_package_version` for each publishable combination.
**And** it checks package availability separately for `trixie` and `bookworm`.
**And** it checks `linux/amd64` and `linux/arm64` availability unless the metadata marks a combination as skipped.
**And** missing TimescaleDB packages fail publishable combinations.
**And** missing Toolkit packages either fail publishable combinations or explicitly mark them unsupported according to metadata policy.
**And** package lookup logic lives in `cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh`, not GitHub Actions YAML.
**And** resolver tests or fixtures cover available and missing TimescaleDB/Toolkit packages for each Debian variant and each platform.
**And** fixtures cover PostgreSQL `19beta1` where CNPG exists but TimescaleDB or Toolkit packages are absent.
**And** tests assert the difference between hard-failing publishable combinations and emitting `publish: false` with `skip_reason` for non-publish combinations.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh`
- `cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh`
- `cloudnative-pg-timescaledb/tests/packagecloud/run.sh`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/trixie-amd64-available.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/trixie-arm64-available.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/bookworm-amd64-available.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/bookworm-arm64-available.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-timescaledb-trixie-amd64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-timescaledb-trixie-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-timescaledb-bookworm-amd64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-timescaledb-bookworm-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-trixie-amd64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-trixie-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-bookworm-amd64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-bookworm-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/mismatched-timescaledb-version-amd64-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/mismatched-toolkit-version-amd64-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-nonpublish-skip.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/pg19beta1-cnpg-present-packages-missing.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-arm64-package.json`

## Package Resolver Contract

`resolve-versions.sh --check-packages` owns TimescaleDB and Toolkit package resolution only after Story 2.1 has resolved CNPG base references.

`cloudnative-pg-timescaledb/scripts/resolve-versions.sh` must implement `--check-packages`, `--fixtures <path>`, and `--json`; it delegates package repository parsing to `cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh` and writes package fields only through the metadata library contract from Story 1.3.

Packagecloud input contract:

- Package names are derived from PostgreSQL package ABI major, not blindly from metadata `pg_major`: `17 -> 17`, `18 -> 18`, and experimental `19beta1 -> 19`. Package names are exactly `timescaledb-2-postgresql-${pg_package_major}` and `timescaledb-toolkit-postgresql-${pg_package_major}`.
- `pg_major` remains the metadata/release-policy key (`17`, `18`, or `19beta1`); `pg_package_major` is resolver-derived and must never be emitted as a supported stable PostgreSQL line by itself.
- Debian distribution values are exactly `trixie` or `bookworm` and must map back to metadata `debian_variant` without aliases.
- Platform mapping is `linux/amd64 -> amd64` and `linux/arm64 -> arm64`.
- Fixture and live parser records use the same schema and parser path. Required record fields are `name`, `version`, `distribution`, `architecture`, `pg_major`, `package_type`, and `source_url`.
- `package_type` is either `timescaledb` or `toolkit`.

Required behavior:

- Resolve and write `timescaledb_version`, `timescaledb_package_name`, `timescaledb_package_version`, `toolkit_version`, `toolkit_package_name`, and `toolkit_package_version` for each publishable entry.
- `timescaledb_package_name` must be exactly `timescaledb-2-postgresql-${pg_package_major}` and `toolkit_package_name` must be exactly `timescaledb-toolkit-postgresql-${pg_package_major}`; these field names are resolver-owned outputs consumed by later install stories.
- Check package availability separately for every tuple of metadata `pg_major`, derived `pg_package_major`, `debian_variant`, and platform in `platforms`.
- For each entry and package, choose one exact `timescaledb_package_version` and one exact `toolkit_package_version` that exist on every required platform. A scalar package version available only on `amd64`, only on `arm64`, or with different versions per architecture is not publishable.
- Treat `trixie` and `bookworm` as separate repository dimensions. Alpine, `bullseye`, and inferred distro aliases must not be accepted.
- For `publish: true`, missing TimescaleDB, missing Toolkit, missing required platform package, or mismatched package versions across required platforms is a hard failure.
- For `publish: false`, missing packages keep the entry non-publishable with a specific `skip_reason` naming package, PostgreSQL major, Debian variant, and platform.
- `19beta1` fixtures must prove the case where CNPG exists but TimescaleDB or Toolkit packages are absent using package ABI major `19`, not package names ending in `19beta1`; it must remain `experimental: true` and `publish: false` unless packages resolve and later release gates explicitly keep it experimental.
- Package lookup logic must live in `cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh`; GitHub Actions may call Make/scripts only.
- Emit compact JSON on `--json` with `entries[]` keys: `pg_major`, `pg_package_major`, `debian_variant`, `platforms`, `timescaledb_version`, `timescaledb_package_name`, `timescaledb_package_version`, `toolkit_version`, `toolkit_package_name`, `toolkit_package_version`, `publish`, `experimental`, `skip_reason`.

## Required Validation Commands

- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh --check-packages --fixtures cloudnative-pg-timescaledb/tests/packagecloud/fixtures`
- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh --check-packages --fixtures cloudnative-pg-timescaledb/tests/packagecloud/fixtures --json`
- `bash cloudnative-pg-timescaledb/tests/packagecloud/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/packagecloud/run.sh` must run every fixture listed in Expected Artifacts.
- Include positive package fixtures for `trixie` and `bookworm` with both `linux/amd64` and `linux/arm64`, plus negative fixtures for missing TimescaleDB and missing Toolkit for each Debian/platform tuple, `19beta1` absent packages using `pg_package_major: "19"`, package names incorrectly ending in `19beta1`, missing platform package availability, and mismatched package versions across required platforms.
- `cloudnative-pg-timescaledb/tests/packagecloud/run.sh` must validate compact JSON output from `--json`: stdout contains only JSON, stderr contains human diagnostics, and `entries[]` includes `pg_major`, `pg_package_major`, `debian_variant`, `platforms`, `timescaledb_version`, `timescaledb_package_name`, `timescaledb_package_version`, `toolkit_version`, `toolkit_package_name`, `toolkit_package_version`, `publish`, `experimental`, and `skip_reason`.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `scripts/lib/packagecloud.sh` as the only package repository parsing layer for TimescaleDB and Toolkit availability.
- [x] Extend `resolve-versions.sh --check-packages` to resolve package names, package versions, extension versions, Debian variants, and platform availability per metadata entry.
- [x] Add fixtures for available, missing, mismatched, unsupported PG19beta1, and missing-platform package cases across `trixie`, `bookworm`, `amd64`, and `arm64`.
- [x] Enforce hard-fail behavior for publishable unavailable combinations and deterministic `publish: false` plus `skip_reason` behavior for non-publish combinations.
- [x] Validate compact JSON stdout/stderr separation and run all packagecloud resolver tests.

## Story Definition of Done

Every implementation story must finish with a working repository state and must satisfy these shared completion rules:

- The story lists the changed artifact paths and the validation commands run by the dev agent.
- The story references the FR IDs, NFR IDs, and additional requirements it fulfills.
- The story is completable by one dev agent using only previous stories and current repository context.
- Generated files are produced through `make generate` or the owning generator script, not hand-edited as the final fix.
- `make validate` passes, or the story documents the narrower scoped validation command when a later story owns the full validation path.
- Tests or fixtures are added for new validation logic, resolver logic, tag logic, generator logic, workflow behavior, or smoke-test behavior.
- Public documentation or generated docs are updated when user-visible behavior, tags, workflows, release evidence, or troubleshooting changes.
- No `.env` file, credential, token, signing secret, registry password, or secret-like value is committed or printed in workflow summaries.
- Workflow changes include permissions review, trigger review, path-context review for Docker builds, and action pinning review where applicable.
- The story output is reviewable from a clean checkout with deterministic UTC dates and no dependency on local developer timezone.

## Direct FR Traceability

| FR | Story IDs | Key Artifacts | Primary Validation |
| --- | --- | --- | --- |
| FR-2 | 1.1, 1.3, 2.1, 2.2, 4.1, 5.1 | Debian variant metadata, resolver fixtures, matrix JSON, docs tables | `validate-metadata.sh`, resolver tests, `generate-matrix.sh` |
| FR-4 | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.1, 5.9 | experimental metadata, resolver fixtures, catalog policy, docs | `validate-metadata.sh`, `validate-tags.sh`, catalog validation |
| FR-5 | 2.2, 3.2, 3.5, 5.9 | package resolver, Dockerfile template, SQL smoke | resolver tests, `make build`, `make smoke` |
| FR-6 | 2.2, 3.2, 3.5, 5.9 | Toolkit package metadata, install checks, SQL smoke | resolver tests, `dpkg-query`, `CREATE EXTENSION timescaledb_toolkit` |
| FR-9 | 2.1, 2.2, 2.3, 2.6, 2.7 | CNPG resolver, package resolver, update command, Renovate | resolver tests, `make update`, Renovate config validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-4 Maintainability | 1.1, 1.2, 1.5, 2.1, 2.2, 4.1, 5.6 | PostgreSQL majors and Debian variants are metadata-driven; Makefile targets delegate to scripts; workflows do not duplicate matrix, resolver, tag, or catalog logic. |
| NFR-6 Portability | 1.3, 2.2, 3.3, 4.2, 5.9 | `linux/amd64` and `linux/arm64` availability is resolved, built, smoked per platform, and rehearsed for every publishable combination. |
| Debian scope | 1.1, 1.3, 2.1, 2.2, 3.4, 5.1, 5.9 | Only `trixie` and `bookworm` are accepted; Alpine, `bullseye`, and other variants hard-fail. |
| PostgreSQL scope | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.9 | `17`, `18`, and experimental `19beta1` are supported according to metadata and release gates. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-2-upstream-aware-version-maintenance/2-2-timescaledb-and-toolkit-package-resolution.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add `scripts/lib/packagecloud.sh` with fixture and live public APT index parsing normalized into one package record schema.
- Extend `resolve-versions.sh` dispatch so `--check-cnpg` remains Story 2.1-owned and `--check-packages` delegates to packagecloud only.
- Add package fixtures for trixie/bookworm, amd64/arm64, missing packages, mismatched versions, pg19beta1 package absence, and publish/non-publish policy.

### Debug Log

- 2026-06-09: Started Story 2.2 from baseline `bdb1493`.
- 2026-06-09: Added `scripts/lib/packagecloud.sh` and `resolve-versions.sh --check-packages` dispatch.
- 2026-06-09: Added positive fixtures for `trixie` and `bookworm` on `amd64` and `arm64`, with TimescaleDB and Toolkit package records for PostgreSQL `17`, `18`, and `19beta1`.
- 2026-06-09: Added negative fixture coverage for missing TimescaleDB, missing Toolkit, mismatched cross-platform package versions, missing arm64 package availability, and pg19beta1 package absence while CNPG exists.
- 2026-06-09: Wired `tests/packagecloud/run.sh` into `scripts/validate.sh`.
- 2026-06-09: Required validation passed: `resolve-versions.sh --check-packages --fixtures ...`, `resolve-versions.sh --check-packages --fixtures ... --json`, `tests/packagecloud/run.sh`, shell syntax checks, `make validate`, and `git diff --cached --check`.
- 2026-06-09: Addressed subagent review findings: publishable package rows now require both `linux/amd64` and `linux/arm64`, and live resolution now parses public Packagecloud Debian `Packages` indexes without requiring an API token.
- 2026-06-09: Live smoke passed for PostgreSQL `18` on `trixie`, resolving `timescaledb-2-postgresql-18` to `2.27.2~debian13-1804` and Toolkit to `1:1.23.0~debian13`.
- 2026-06-09: Re-ran `tests/packagecloud/run.sh`, `make validate`, shell syntax checks, live smoke, and `git diff --cached --check` successfully after review fixes.
- 2026-06-10: Closed the review correction for experimental metadata `pg_major: 19beta1` by deriving package ABI `pg_package_major: 19` for package names, lookup keys, fixtures, skip reasons, and compact JSON output.
- 2026-06-10: Added negative coverage rejecting package fixture records named with `postgresql-19beta1` and rejecting metadata `pg_major: 19` as a supported stable line.
- 2026-06-10: Re-ran targeted validation successfully: `bash cloudnative-pg-timescaledb/tests/packagecloud/run.sh`, `bash cloudnative-pg-timescaledb/tests/update/run.sh`, `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh`, `bash cloudnative-pg-timescaledb/tests/generators/run.sh`, `shellcheck -x cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh cloudnative-pg-timescaledb/tests/packagecloud/run.sh`, and `git diff --check`.

### Completion Notes

- `resolve-versions.sh --check-packages` now resolves package names, package versions, and extension versions for TimescaleDB and Toolkit per PostgreSQL major, Debian variant, and platform.
- Package names are derived from PostgreSQL package ABI major. Experimental metadata `pg_major: 19beta1` maps to `pg_package_major: 19`, package names ending in `19beta1` are rejected, and compact resolver JSON includes `pg_package_major` without treating `19` as a supported stable metadata line.
- Publishable rows hard-fail when either required platform is absent, when a package is missing, or when versions differ across required platforms.
- Non-publish rows require a specific `skip_reason` naming package, PostgreSQL major, Debian variant, and platform for missing package cases.
- JSON output is compact and stdout-only on success; human diagnostics use deterministic `command/artifact/expected/actual/remediation` fields.
- Scope remains limited to resolver behavior; Dockerfile installation, SQL smoke, update orchestration, workflows, SBOM/provenance, signing, and publish remain later stories.

## File List

- `cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh`
- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/packagecloud/run.sh`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/trixie-amd64-available.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/trixie-arm64-available.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/bookworm-amd64-available.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/bookworm-arm64-available.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-timescaledb-trixie-amd64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-timescaledb-trixie-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-timescaledb-bookworm-amd64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-timescaledb-bookworm-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-trixie-amd64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-trixie-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-bookworm-amd64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-bookworm-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/mismatched-timescaledb-version-amd64-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/mismatched-toolkit-version-amd64-arm64.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-toolkit-nonpublish-skip.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/pg19beta1-cnpg-present-packages-missing.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/invalid-pg19beta1-package-name.json`
- `cloudnative-pg-timescaledb/tests/packagecloud/fixtures/missing-arm64-package.json`
- `cloudnative-pg-timescaledb/versions.yaml`
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/generated/19beta1/bookworm/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/docs/generated/compatibility-table.md`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json`
- `_bmad-output/implementation-artifacts/execution-plan-20260610.md`

## Change Log

- 2026-06-09: Implemented Story 2.2 package resolver and fixture suite.
- 2026-06-09: Wired package resolver tests into `make validate`.
- 2026-06-09: Hardened package resolver after subagent review for required platform coverage and live public Packagecloud index parsing.
- 2026-06-10: Completed PG19 beta package ABI correction, regenerated derived outputs, and marked Story 2.2 done after targeted validation passed.
