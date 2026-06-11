---
storyId: 5.1
storyKey: 5-1-public-readme-and-compatibility-overview
epic: 5
title: 'Public README and Compatibility Overview'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 5.1: Public README and Compatibility Overview

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Previous epics 1-4 may be assumed complete only through their accepted story outputs.

## Out of Scope

- Detailed tag policy examples; owned by Story 5.2.
- ClusterImageCatalog usage walkthrough; owned by Story 5.3.
- Barman Cloud Plugin deployment details; owned by Story 5.4.
- Image verification, maintainer operations, troubleshooting, and release rehearsal; owned by Stories 5.5-5.9.

## Source Story

### Story 5.1: Public README and Compatibility Overview

As an external platform engineer,
I want a complete public README and compatibility overview,
So that I can decide whether this image family fits my CloudNativePG and TimescaleDB use case.

**Acceptance Criteria:**

**Given** repository metadata and generated outputs
**When** the public README is rendered or validated
**Then** it explains the repository purpose, supported PostgreSQL majors, Debian variants, extension set, and GHCR image namespace.
**And** it marks Debian `trixie` as the primary recommended variant.
**And** it marks Debian `bookworm` as secondary.
**And** it marks PostgreSQL `19beta1` as experimental wherever it appears.
**And** it states Alpine, `bullseye`, legacy PostgreSQL majors, and Artifact Hub metadata are out of scope for v1.
**And** compatibility tables are generated from or validated against `versions.yaml`.

## Expected Artifacts

- `README.md`
- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/docs/generated/compatibility-table.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/valid-readme.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/missing-trixie-primary.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/bookworm-not-secondary.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/missing-pg19-experimental-warning.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/missing-latest-pg18-trixie.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/wrong-latest-target.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/missing-barman-plugin-boundary.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/legacy-barman-in-image-in-scope.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/alpine-in-scope.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/bullseye-in-scope.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/legacy-postgresql-in-scope.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/pg19-not-experimental.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/artifact-hub-in-scope.md`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/stale-compatibility-table.md`

## README Compatibility Contract

- README must name the image family as CloudNativePG-compatible PostgreSQL images with TimescaleDB, TimescaleDB Toolkit when available, pgvector, and PGAudit.
- README must state at overview level that Barman-related backup support is through the CloudNativePG Barman Cloud Plugin path, while legacy in-image `barman-cloud` binaries are not part of v1; detailed plugin deployment remains owned by Story 5.4.
- README must document the GHCR namespace and show primary examples using PostgreSQL major tags, not `latest`.
- README must state that `latest` is convenience-only and points to PostgreSQL `18` `trixie` in v1; validation must fail if `latest` is described as primary usage, assigned to `bookworm`, PostgreSQL `17`, or PostgreSQL `19beta1`, or omitted from the compatibility overview when `latest_eligible` metadata exists.
- Compatibility tables must be generated from, or mechanically validated against, `cloudnative-pg-timescaledb/versions.yaml`.
- The table must include PostgreSQL `17`, PostgreSQL `18`, experimental PostgreSQL `19beta1`, Debian `trixie` primary, and Debian `bookworm` secondary.
- The table must make `publish`, `experimental`, `latest_eligible`, supported platforms, and `skip_reason` visible for every metadata row.
- Validation must fail if README claims Alpine, `bullseye`, legacy PostgreSQL majors, Artifact Hub metadata, or non-experimental PostgreSQL `19` are in v1 scope.

## Required Validation Commands

- make validate
- `bash cloudnative-pg-timescaledb/tests/docs/readme/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/docs/readme/run.sh` must run every README fixture listed in Expected Artifacts.
- Include one positive README fixture and negative fixtures for missing primary `trixie`, missing secondary `bookworm`, missing PostgreSQL `19beta1` experimental warning, missing `latest` equals PostgreSQL `18` `trixie` overview, wrong `latest` target, missing Barman Cloud Plugin boundary, legacy in-image Barman scope, forbidden Alpine scope, forbidden `bullseye` scope, forbidden legacy PostgreSQL majors, non-experimental PostgreSQL `19`, forbidden Artifact Hub scope, and stale compatibility table contents.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Update root `README.md` and `cloudnative-pg-timescaledb/README.md` to describe the public image family, GHCR namespace, supported extensions, Debian scope, PostgreSQL scope, and v1 out-of-scope items.
- [x] Generate or validate `cloudnative-pg-timescaledb/docs/generated/compatibility-table.md` from `cloudnative-pg-timescaledb/versions.yaml` with `publish`, `experimental`, `latest_eligible`, platforms, and `skip_reason` visible.
- [x] Mark `trixie` as primary, `bookworm` as secondary, and `19beta1` as experimental everywhere it appears.
- [x] Document overview-level `latest` behavior as convenience-only for PostgreSQL `18` `trixie` and overview-level Barman support through CloudNativePG Barman Cloud Plugin, leaving detailed tag/Barman docs to Stories 5.2 and 5.4.
- [x] Add README docs fixtures for primary/secondary Debian labels, PG19 experimental warnings, `latest` target, Barman boundary, forbidden Alpine/`bullseye`/legacy PostgreSQL/Artifact Hub scope, and stale compatibility tables.
- [x] Run `make validate` and `bash cloudnative-pg-timescaledb/tests/docs/readme/run.sh`.

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
| FR-3 | 1.4, 4.5, 4.7, 5.1, 5.2, 5.9 | tag library, README overview, publish workflow, docs examples | `validate-tags.sh`, README docs validation, release rehearsal |
| FR-4 | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.1, 5.9 | experimental metadata, resolver fixtures, catalog policy, docs | `validate-metadata.sh`, `validate-tags.sh`, catalog validation |
| FR-8 | 2.7, 3.6, 5.1, 5.4, 5.7, 5.9 | Barman Cloud Plugin overview, docs validation fixtures | README docs validation, forbidden legacy `barman-cloud` checks |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-7 Public trust | 4.4, 4.5, 4.6, 5.1, 5.5, 5.9 | Labels, docs, SBOM, provenance, signatures, vulnerability scans, and catalogs make public releases inspectable. |
| Debian scope | 1.1, 1.3, 2.1, 2.2, 3.4, 5.1, 5.9 | Only `trixie` and `bookworm` are accepted; Alpine, `bullseye`, and other variants hard-fail. |
| Artifact Hub out of scope | 5.1, 5.6, 5.9 | Docs and release rehearsal keep Artifact Hub metadata out of v1 scope. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-5-public-operator-and-maintainer-documentation/5-1-public-readme-and-compatibility-overview.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented generated `compatibility-table.md` as a companion artifact from `generate-docs.sh` rather than hand-editing the table.
- Added README validation fixtures for every Story 5.1 negative case and connected the gate to `make validate`.
- Extended update/autocommit allowlists and fixtures so generated compatibility docs are staged by resolver update automation.
- Adjusted the Barman boundary validator to allow explicit negative `legacy in-image barman-cloud is not part of v1` wording while continuing to reject legacy in-image guidance.
- Ran a separate review subagent against the staged Story 5.1 diff; no blocking findings were reported.

### Completion Notes

- Root and package READMEs now document the public image family, GHCR namespace, extension set, PostgreSQL/Debian scope, v1 exclusions, `latest` target, and Barman plugin boundary.
- `cloudnative-pg-timescaledb/docs/generated/compatibility-table.md` is generated from `versions.yaml` and exposes `publish`, `experimental`, `latest_eligible`, platforms, and `skip_reason` for each row.
- README docs validation fails on missing/stale compatibility table content, forbidden scope claims, missing PG19 experimental warning, wrong `latest` target, and missing Barman plugin boundary.
- Full staged-snapshot validation passed.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/docs/readme/run.sh` PASS
- `cloudnative-pg-timescaledb/scripts/generate-docs.sh --check` PASS
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` PASS
- `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/update/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/renovate/run.sh` PASS
- staged snapshot `make validate` PASS

### File List

- `README.md`
- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/config/change-origin-rules.json`
- `cloudnative-pg-timescaledb/docs/generated/compatibility.md`
- `cloudnative-pg-timescaledb/docs/generated/compatibility-table.md`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/lib/update_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/docs/readme/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/readme/fixtures/*.md`
- `cloudnative-pg-timescaledb/tests/generated-drift/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `cloudnative-pg-timescaledb/tests/update/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh`
- `docs/generator-contracts.md`

### Change Log

- 2026-06-10: Completed Story 5.1 public README, generated compatibility table, README validation fixtures, and update/autocommit generated-doc allowlists.
