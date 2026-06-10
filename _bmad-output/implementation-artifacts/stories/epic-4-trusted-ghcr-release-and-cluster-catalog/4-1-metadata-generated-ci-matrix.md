---
storyId: 4.1
storyKey: 4-1-metadata-generated-ci-matrix
epic: 4
title: 'Metadata-Generated CI Matrix'
status: ready-for-review
baseline_commit: 01c82afcf666e6fc3027a98a95d3a8580a2ee63b
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 4.1: Metadata-Generated CI Matrix

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Epics 1-3 may be assumed complete only through their accepted story outputs.

## Out of Scope

- Release candidate build, smoke, scan, evidence, signing, and publish execution; owned by Stories 4.2-4.5.
- Digest-aware catalog generation; owned by Story 4.6.
- Public docs and release rehearsal; owned by Epic 5.

## Source Story

### Story 4.1: Metadata-Generated CI Matrix

As a maintainer,
I want GitHub Actions build matrices generated from repository metadata,
So that supported images are built without hand-written workflow rows.

**Acceptance Criteria:**

**Given** valid metadata and generated image definitions
**When** `cloudnative-pg-timescaledb/scripts/generate-matrix.sh` runs
**Then** it emits compact JSON for supported PostgreSQL/Debian/platform combinations.
**And** publishable entries include PostgreSQL major, PostgreSQL version, Debian variant, platforms, Dockerfile path, Bake target, tag set, `experimental`, and `latest_eligible`.
**And** matrix JSON schema defines required keys for downstream jobs: `image`, `candidate_ref`, `digest`, `platforms`, `bake_target`, `dockerfile`, `intended_tags`, `experimental`, `latest_eligible`, `scan_result`, `sbom_ref`, `provenance_ref`, and `signature_ref` when those fields become available.
**And** downstream workflows consume matrix and release metadata through `fromJSON`, job outputs, or workflow artifacts and reject missing keys rather than recomputing tags or digests independently.
**And** skipped entries include `publish: false` and `skip_reason` when emitted for summaries.
**And** `.github/workflows/build.yml` consumes generated matrix data rather than hard-coded rows.
**And** matrix generation preserves `trixie` primary and `bookworm` secondary semantics.
**And** PostgreSQL `19beta1` entries remain marked experimental.

## Expected Artifacts

- `.github/workflows/build.yml` matrix consumption only
- `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`
- `cloudnative-pg-timescaledb/docs/generated/matrix-schema.md`
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/tests/matrix/run.sh`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/valid-publishable-matrix.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/missing-required-key.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/hardcoded-workflow-row.yml`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/pg19beta1-not-experimental.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/bookworm-latest-eligible.json`

## Matrix Contract

- `generate-matrix.sh --json` emits compact JSON with top-level `include[]` and optional `skipped[]`.
- Required `include[]` keys: `pg_major`, `pg_version`, `debian_variant`, `image`, `candidate_ref`, `digest`, `platforms`, `bake_target`, `dockerfile`, `intended_tags`, `publish`, `experimental`, `latest_eligible`, `scan_result`, `sbom_ref`, `provenance_ref`, and `signature_ref`.
- Fields not available until later release jobs must exist with empty string, `null`, or explicit pending value; downstream jobs must reject missing keys.
- `intended_tags` must be produced by the Story 1.4 tag library, not recomputed by workflows.
- `.github/workflows/build.yml` consumes matrix JSON via `fromJSON`, job outputs, or workflow artifacts and must not contain hand-written PostgreSQL/Debian rows.
- `latest_eligible: true` is valid only for PostgreSQL `18` `trixie`; `bookworm`, PostgreSQL `17`, and `19beta1` must not be latest eligible.
- `19beta1` rows must keep `experimental: true`.

## Required Validation Commands

- `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`
- `bash cloudnative-pg-timescaledb/tests/matrix/run.sh`
- `actionlint .github/workflows/build.yml`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/matrix/run.sh` must run every fixture listed in Expected Artifacts.
- `cloudnative-pg-timescaledb/tests/matrix/run.sh` must validate the real `.github/workflows/build.yml` consumes generated matrix data through `fromJSON`, job outputs, or workflow artifacts, rejects missing required matrix keys, and contains no hand-written PostgreSQL/Debian workflow rows.
- Include negative fixtures for missing required key, hard-coded workflow rows, `19beta1` without experimental marking, and invalid latest eligibility.
- Latest eligibility validation must prove exactly one publishable row has `latest_eligible: true`, and that row is PostgreSQL `18` with Debian `trixie`; PostgreSQL `17`, `19beta1`, and `bookworm` rows must fail if marked latest-eligible.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `cloudnative-pg-timescaledb/scripts/generate-matrix.sh --json` from `versions.yaml`, generated Dockerfile paths, Bake targets, platforms, tag-policy output, publish flags, experimental flags, and latest eligibility.
- [x] Generate `cloudnative-pg-timescaledb/matrix.json` with top-level `include[]` and `skipped[]` where skipped entries retain `publish: false` and `skip_reason`.
- [x] Document the matrix schema in `cloudnative-pg-timescaledb/docs/generated/matrix-schema.md`, including pending/null fields that later jobs will populate.
- [x] Wire `.github/workflows/build.yml` to consume generated matrix JSON through `fromJSON`, job outputs, or workflow artifacts without hard-coded PostgreSQL/Debian rows.
- [x] Add matrix fixtures and `cloudnative-pg-timescaledb/tests/matrix/run.sh` for required keys, hard-coded workflow rows, `latest_eligible`, and `19beta1` experimental policy.
- [x] Run `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`, `bash cloudnative-pg-timescaledb/tests/matrix/run.sh`, and `actionlint .github/workflows/build.yml`.

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
| FR-12 | 1.5, 4.1, 4.2, 5.9 | matrix schema, workflow `fromJSON`, release metadata artifacts | `generate-matrix.sh`, workflow validation, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-4 Maintainability | 1.1, 1.2, 1.5, 2.1, 2.2, 4.1, 5.6 | PostgreSQL majors and Debian variants are metadata-driven; Makefile targets delegate to scripts; workflows do not duplicate matrix, resolver, tag, or catalog logic. |
| Makefile command surface | 1.2, 2.3, 3.3, 4.1, 4.6, 5.6, 5.9 | Root `Makefile` exposes stable `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` targets that delegate to scripts. |
| PostgreSQL scope | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.9 | `17`, `18`, and experimental `19beta1` are supported according to metadata and release gates. |
| Generated artifacts | 1.5, 1.6, 3.1, 4.1, 4.6, 5.7, 5.9 | Dockerfiles, Bake file, matrix JSON, catalogs, docs tables, and README examples are generated or validated and drift-checked. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-4-trusted-ghcr-release-and-cluster-catalog/4-1-metadata-generated-ci-matrix.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Extended `generator_contract.py` matrix output to emit release-oriented `include[]` publishable rows and `skipped[]` summary rows.
- Added generated `matrix-schema.md`, shared `tag_policy.py`, and `validate-matrix-json.py` so matrix tags and workflow required-key checks use shared contracts.
- Implemented `.github/workflows/build.yml` as matrix consumer with `fromJSON`, job outputs, pinned checkout action, read-only permissions, and no hard-coded PostgreSQL/Debian rows.
- Updated generator drift, update/autocommit allowlists, and generator fixtures for the new matrix schema artifact.
- 2026-06-10: Tightened skipped matrix rows so they expose `bake_target` plus `skipped_marker`, keep `latest_eligible` policy explicit, and do not leak buildable Dockerfile paths or publish-only fields.
- 2026-06-10: Expanded matrix/generator validators and fixtures for duplicate rows, missing include keys, skipped latest ownership, and marker-only skipped row contracts.

### Completion Notes

- FR-2/FR-4/FR-12: matrix generation is metadata-driven, preserves trixie/bookworm and 19beta1 experimental policy, and exposes downstream release placeholder fields.
- NFR-4: workflows consume generated matrix JSON instead of duplicating matrix rows.
- Review closure: BMAD review found two MAJOR issues; fixes landed for shared tag policy and shared workflow matrix-key validation, then re-check reported no remaining BLOCKER/MAJOR findings.
- Skipped row summaries now remain useful for observability and release rehearsal without becoming build inputs; buildable rows stay limited to publishable metadata rows.

### Validation Commands

- `cloudnative-pg-timescaledb/scripts/generate-matrix.sh --json` PASS
- `make --no-print-directory matrix` PASS
- `bash cloudnative-pg-timescaledb/tests/matrix/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` PASS
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh` PASS
- `bash cloudnative-pg-timescaledb/scripts/validate-docs.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/bake/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/update/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/tags/run.sh` PASS
- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh` PASS; local `actionlint` unavailable, CI `validate.yml` installs it before `make validate`
- Staged snapshot `make validate` PASS

### File List

- `.github/workflows/build.yml`
- `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/config/change-origin-rules.json`
- `cloudnative-pg-timescaledb/docs/generated/matrix-schema.md`
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/lib/tag_policy.py`
- `cloudnative-pg-timescaledb/scripts/lib/tags.sh`
- `cloudnative-pg-timescaledb/scripts/matrix.sh`
- `cloudnative-pg-timescaledb/scripts/build.sh`
- `cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`
- `cloudnative-pg-timescaledb/scripts/validate-docs.sh`
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `cloudnative-pg-timescaledb/scripts/validate-matrix-json.py`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/bake/run.sh`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/skipped-combination.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/valid-publishable-targets.json`
- `cloudnative-pg-timescaledb/tests/generated-drift/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-missing-include-key.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-duplicate-row.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-wrong-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/matrix/run.sh`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/valid-publishable-matrix.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/missing-required-key.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/hardcoded-workflow-row.yml`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/pg19beta1-not-experimental.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/bookworm-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`
- `cloudnative-pg-timescaledb/tests/update/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh`
- `docs/generator-contracts.md`

### Change Log

- Added metadata-generated release matrix schema and generated `matrix.json`/`matrix-schema.md` artifacts.
- Added build workflow matrix consumption through generated JSON and shared required-key validation.
- Added matrix fixtures for missing keys, hard-coded workflow rows, PostgreSQL 19 experimental policy, and latest eligibility.
- Updated generated drift and update/autocommit safety gates for the new matrix schema artifact.
- Tightened skipped matrix/Bake row contracts and release rehearsal consumers so skipped rows stay summaries rather than buildable inputs.
