---
storyId: 3.5
storyKey: 3-5-sql-extension-smoke-checks
epic: 3
title: 'SQL Extension Smoke Checks'
status: ready-for-review
baseline_commit: 506c422f6c9b26cef1947a64811a86bacf9834663a1b34b3f7
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 3.5: SQL Extension Smoke Checks

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 3.1-3.4 in this epic may be assumed complete.

## Out of Scope

- Container-level OS/runtime smoke checks; owned by Story 3.4.
- CI per-platform release candidate smoke orchestration; owned by Story 4.2.
- Publish eligibility promotion and GHCR tag publication; owned by Epic 4.

## Source Story

### Story 3.5: SQL Extension Smoke Checks

As an operator,
I want SQL smoke tests to validate extension creation,
So that a published image is not merely buildable but usable by PostgreSQL workloads.

**Acceptance Criteria:**

**Given** a locally built image started as a test PostgreSQL instance
**When** `smoke-test.sh` runs SQL checks
**Then** it executes `SELECT version()`.
**And** it executes `SHOW server_version`.
**And** it executes `CREATE EXTENSION IF NOT EXISTS timescaledb`.
**And** it queries the installed TimescaleDB extension version and compares it to metadata expectations.
**And** it validates TimescaleDB library availability.
**And** for every expected creatable extension in metadata it executes `CREATE EXTENSION IF NOT EXISTS`; for extensions explicitly marked non-creatable it runs the validation-only path defined by metadata policy.
**And** it queries `pg_extension.extversion` for extensions that were created or validated through `preinstalled-extension`; for `control-file` or `library` validation-only modes, it compares the documented control-file or library expectation instead.
**And** the test PostgreSQL instance starts with the preload settings required by TimescaleDB and PGAudit, or validation fails with the exact missing `shared_preload_libraries` requirement.
**And** validating instead of creating an extension is allowed only for extensions explicitly marked non-creatable in metadata with a documented reason.
**And** SQL smoke failure blocks publish eligibility for that image combination.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/smoke-test.sh`
- Root `Makefile` `smoke` target with `CHECKS=sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/run.sh`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/valid-sql-smoke.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/missing-timescaledb-extension.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/wrong-timescaledb-version.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/missing-timescaledb-library.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/missing-toolkit-extension.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/missing-shared-preload-libraries.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-allowed.yaml`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-denied.yaml`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-missing-validation-target.yaml`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-wrong-validation-target.yaml`

## SQL Smoke Contract

- `smoke-test.sh CHECKS=sql` must start a PostgreSQL instance with preload settings required by TimescaleDB and PGAudit.
- Minimum SQL sequence: `SELECT version()`, `SHOW server_version`, `CREATE EXTENSION IF NOT EXISTS timescaledb`, `CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit`/`vector`/`pgaudit` only when the extension is creatable, validation-only probes for metadata-marked non-creatable extensions, then query `pg_extension.extversion` or the documented control-file/library expectation for each extension.
- TimescaleDB and Toolkit versions must match metadata expectations.
- TimescaleDB shared library availability must be validated explicitly, either through a deterministic SQL probe or an artifact/library-path check; diagnostics must include the command or probe, expected library availability, actual result, and remediation.
- pgvector and PGAudit versions must match metadata when provided, otherwise match control-file expectations.
- Validating without creating an extension is allowed only when the metadata entry defines `extensions.<extname>.creatable: false`, `extensions.<extname>.non_creatable_reason: <non-empty string>`, `extensions.<extname>.validation_mode: control-file|library|preinstalled-extension`, and `extensions.<extname>.validation_target: <mode-specific non-empty target>`.
- For `control-file`, `validation_target` must name the expected extension control file and version/source expectation; for `library`, it must name the expected library/probe/path and expected result; for `preinstalled-extension`, it must name the extension and version comparison source.
- Canonical required preload value is `shared_preload_libraries=timescaledb,pgaudit` unless metadata defines a stricter canonical ordered list; tests and diagnostics must use the same canonical expected value.
- Missing preload settings fail with diagnostics naming the exact required `shared_preload_libraries` value, the actual value, and remediation.
- SQL smoke failure marks the image combination non-publishable for later Epic 4 gates.

## Required Validation Commands

- make smoke PG=18 DEBIAN=trixie CHECKS=sql
- `bash cloudnative-pg-timescaledb/tests/smoke/sql/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/smoke/sql/run.sh` must run every fixture listed in Expected Artifacts.
- Include negative fixtures for missing extension, wrong extension version, missing shared preload setting, and unsupported non-creatable extension handling.
- `non-creatable-extension-denied.yaml` must fail when an extension has `creatable: false` without a documented reason or supported marker; diagnostics must include extension name, `creatable: false`, expected policy, actual metadata, and remediation.
- Include fixtures for TimescaleDB library unavailable, `non-creatable-extension-missing-validation-target.yaml`, and `non-creatable-extension-wrong-validation-target.yaml`.
- Validation target failures must include extension name, validation mode, target, expected value, actual value, command/probe, and remediation.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Extend `cloudnative-pg-timescaledb/scripts/smoke-test.sh` SQL checks to start PostgreSQL with required `shared_preload_libraries`.
- [x] Execute the minimum SQL sequence and create or explicitly validate TimescaleDB, Toolkit, pgvector, and PGAudit according to metadata `creatable` and validation policy fields.
- [x] Validate TimescaleDB shared library availability with deterministic diagnostics before considering the SQL smoke successful.
- [x] Compare `pg_extension.extversion` only for extensions that were created or validated through `preinstalled-extension`; for `control-file` and `library` validation-only modes, compare the documented `validation_target` via deterministic control-file/library probes without requiring a `pg_extension` row.
- [x] Wire root `Makefile` `smoke PG=<major> DEBIAN=<variant> CHECKS=sql` to the SQL smoke path.
- [x] Add SQL smoke fixtures and `cloudnative-pg-timescaledb/tests/smoke/sql/run.sh`.
- [x] Run `make smoke PG=18 DEBIAN=trixie CHECKS=sql` and `bash cloudnative-pg-timescaledb/tests/smoke/sql/run.sh`.

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
| FR-5 | 2.2, 3.2, 3.5, 5.9 | package resolver, Dockerfile template, SQL smoke | resolver tests, `make build`, `make smoke` |
| FR-6 | 2.2, 3.2, 3.5, 5.9 | Toolkit package metadata, install checks, SQL smoke | resolver tests, `dpkg-query`, `CREATE EXTENSION timescaledb_toolkit` |
| FR-7 | 3.2, 3.4, 3.5, 5.9 | pgvector/PGAudit metadata, control files, SQL smoke | `dpkg-query`, control-file checks, SQL extension checks |
| FR-14 | 3.4, 3.5, 4.2, 5.9 | container smoke, SQL smoke, per-platform smoke gates | `make smoke`, platform-specific smoke, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| Extension set | 3.2, 3.4, 3.5, 5.9 | TimescaleDB, Toolkit, pgvector, and PGAudit can be created or explicitly validated in a running PostgreSQL instance. |
| Smoke gate | 3.4, 3.5, 4.2, 5.9 | Container and SQL smoke failures block publish eligibility for the affected image combination. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-3-validated-cloudnativepg-extension-images/3-5-sql-extension-smoke-checks.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Extended `scripts/smoke-test.sh` with `CHECKS=sql` mode using deterministic SQL transcript fixtures for Story 3.5 validation. The production live path remains gated by `publish:true`; production metadata is still all `publish:false`, so direct SQL smoke returns a skipped diagnostic until release gates enable images.
- Wired `scripts/smoke.sh` so root `make smoke PG=<major> DEBIAN=<variant> CHECKS=sql` reaches the SQL smoke path.
- Implemented SQL transcript checks for `SELECT version()`, `SHOW server_version`, canonical `shared_preload_libraries=timescaledb,pgaudit`, `CREATE EXTENSION` results, TimescaleDB and Toolkit version comparisons, TimescaleDB library availability, and pgvector/PGAudit extversion presence when exact metadata is not provided.
- Implemented validation-only policy checks for non-creatable extensions using `extension`, `creatable: false`, `non_creatable_reason`, `validation_mode`, and `validation_target` fixture metadata.
- Addressed BMAD review findings by adding a Docker-backed live SQL collector path, rejecting env-only non-creatable policy files, sourcing validation-only policy from selected metadata entry `extensions.<ext>.*` fields, and requiring control-file expectations for pgvector/PGAudit when exact package versions are absent.
- Extended non-creatable handling from a single policy to a per-extension policy map, including live collector skip-create behavior and validation target/result emission for multiple validation-only extensions.
- Extended metadata validation so future real `versions.yaml` rows can carry strictly scoped `extensions.<ext>.*` policy fields without bypassing schema validation.

### Completion Notes

- FR-5/FR-6: SQL smoke validates TimescaleDB and Toolkit creation/version expectations before publish eligibility.
- FR-7: pgvector and PGAudit creation or explicit validation-only policy is covered by SQL smoke checks.
- FR-14 / Smoke gate: SQL smoke failures now produce deterministic publish-blocking diagnostics and are integrated into `make validate`.
- Additional policy: non-creatable validation is allowed only with documented reason, supported validation mode, and non-empty validation target.
- Review closure: BMAD code review re-check reported no remaining BLOCKER/MAJOR findings after live collector, metadata policy, and multi-extension fixes.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/smoke/sql/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/metadata/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/smoke/container/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh` PASS
- `make smoke PG=18 DEBIAN=trixie CHECKS=sql` executed; expected non-zero skipped diagnostic on production metadata: `Publish disabled until release gate enables image builds`
- `git diff --check` PASS
- Staged snapshot `make validate` PASS

### File List

- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/scripts/smoke-test.sh`
- `cloudnative-pg-timescaledb/scripts/lib/metadata.sh`
- `cloudnative-pg-timescaledb/scripts/smoke.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/metadata/run.sh`
- `cloudnative-pg-timescaledb/tests/smoke/container/run.sh`
- `cloudnative-pg-timescaledb/tests/smoke/sql/run.sh`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/valid-sql-smoke.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/missing-timescaledb-extension.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/wrong-timescaledb-version.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/missing-timescaledb-library.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/missing-toolkit-extension.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/missing-shared-preload-libraries.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-allowed.yaml`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-denied.yaml`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-missing-validation-target.yaml`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-wrong-validation-target.yaml`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-allowed.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-two-allowed.sql`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-two-allowed.yaml`
- `cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/non-creatable-extension-wrong-validation-target.sql`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`

### Change Log

- Added SQL smoke mode to `smoke-test.sh` and root `make smoke CHECKS=sql` path.
- Added deterministic SQL smoke transcript fixtures and non-creatable policy fixtures.
- Integrated SQL smoke tests into `make validate` and updated public command documentation.
- Updated compatibility expectations for implemented SQL smoke skipped behavior on `publish:false` production metadata.
- Added metadata schema support and tests for `extensions.<ext>.*` validation-only policy fields.
- Added live SQL collector coverage for multiple non-creatable extensions and validation-only probes.
