---
storyId: 2.1
storyKey: 2-1-cnpg-base-image-resolution
epic: 2
title: 'CNPG Base Image Resolution'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: bee7f60
---

# Story 2.1: CNPG Base Image Resolution

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Epic 1 stories 1.1-1.6 may be assumed complete only through their accepted story outputs.

## Out of Scope

- TimescaleDB and Toolkit package lookup; owned by Story 2.2.
- Local update diff orchestration and generated-file regeneration; owned by Story 2.3.
- GitHub Actions scheduled update/autocommit behavior; owned by Story 2.5.
- Dockerfile `FROM` generation, builds, and smoke tests; owned by Epic 3.

## Source Story

### Story 2.1: CNPG Base Image Resolution

As a maintainer,
I want CNPG base image tags and digests resolved from upstream,
So that image metadata tracks the actual supported `standard-*` base images without manual registry inspection.

**Acceptance Criteria:**

**Given** valid metadata for PostgreSQL `17`, `18`, and experimental `19beta1`
**When** `cloudnative-pg-timescaledb/scripts/resolve-versions.sh` checks CNPG base images
**Then** it resolves `ghcr.io/cloudnative-pg/postgresql` `standard-*` tags and digests for each publishable PostgreSQL/Debian combination.
**And** it rejects deprecated `system-*` image flavors for v1.
**And** it treats `trixie` and `bookworm` as explicit Debian dimensions, not ad hoc tag suffixes.
**And** it marks unavailable non-publish combinations with `publish: false` and a specific `skip_reason`.
**And** unavailable publishable combinations fail with diagnostics that include command, PostgreSQL major, Debian variant, platform, expected upstream reference, actual result, and remediation.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh`
- `cloudnative-pg-timescaledb/scripts/lib/cnpg.sh`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/run.sh`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/standard-trixie-valid.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/standard-bookworm-valid.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/system-flavor-deprecated.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/missing-platform-arm64.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/unavailable-nonpublish-pg19beta1.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/unavailable-publishable.yaml`

## CNPG Resolver Contract

`resolve-versions.sh --check-cnpg` owns only CNPG base image tag and digest resolution.

Required behavior:

- Query or fixture-load `ghcr.io/cloudnative-pg/postgresql` tags whose flavor contains `standard`, never `system`.
- Resolve the digest for each requested platform in metadata and write `cnpg_digest` only when all required platforms are present.
- Treat `trixie` and `bookworm` as explicit metadata dimensions; do not infer Debian variant from arbitrary tag substrings outside the resolver mapping.
- For `publish: true`, missing tag, missing digest, wrong flavor, wrong Debian variant, or missing required platform is a hard failure.
- For `publish: false`, unavailable upstream references remain non-publishable and require a specific `skip_reason` containing the upstream reference and missing dimension.
- Emit compact JSON on `--json` with `entries[]` keys: `pg_major`, `pg_version`, `debian_variant`, `cnpg_tag`, `cnpg_digest`, `platforms`, `publish`, `experimental`, `skip_reason`.
- Human diagnostics must include command, PostgreSQL major, Debian variant, platform, expected upstream reference, actual result, and remediation.

## Required Validation Commands

- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh --check-cnpg --fixtures cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures`
- `bash cloudnative-pg-timescaledb/tests/cnpg-resolver/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/cnpg-resolver/run.sh` must run every fixture listed in Expected Artifacts.
- Include positive fixtures for `standard-trixie` and `standard-bookworm`, and negative fixtures for deprecated `system-*`, missing platform, unavailable non-publish, and unavailable publishable combinations.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement CNPG upstream parsing and digest resolution in the resolver path owned by Story 2.1, reusing metadata library contracts from Epic 1.
- [x] Populate `cnpg_tag`, `cnpg_digest`, and CNPG-related skip/failure diagnostics only through resolver-owned metadata updates.
- [x] Add CNPG resolver fixtures for `standard-trixie`, `standard-bookworm`, deprecated `system-*`, missing platform, unavailable non-publish, and unavailable publishable combinations.
- [x] Ensure `standard-*` digest-pinned base images are accepted and `system-*`, Alpine, `bullseye`, or alias-based Debian variants are rejected.
- [x] Run the CNPG resolver command and fixture runner, then record changed paths and validation output.

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
| FR-9 | 2.1, 2.2, 2.3, 2.6, 2.7 | CNPG resolver, package resolver, update command, Renovate | resolver tests, `make update`, Renovate config validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-4 Maintainability | 1.1, 1.2, 1.5, 2.1, 2.2, 4.1, 5.6 | PostgreSQL majors and Debian variants are metadata-driven; Makefile targets delegate to scripts; workflows do not duplicate matrix, resolver, tag, or catalog logic. |
| Debian scope | 1.1, 1.3, 2.1, 2.2, 3.4, 5.1, 5.9 | Only `trixie` and `bookworm` are accepted; Alpine, `bullseye`, and other variants hard-fail. |
| CNPG standard base | 2.1, 3.1, 3.4 | Generated Dockerfiles use digest-pinned CNPG `standard-*` images and reject deprecated `system-*` images. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-2-upstream-aware-version-maintenance/2-1-cnpg-base-image-resolution.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add a CNPG-only resolver entrypoint and library that can fixture-load deterministic upstream inventories or use Docker CLI live inspection when fixtures are not provided.
- Resolve `standard-*` CNPG tags by PostgreSQL major and explicit Debian variant, preferring versioned rolling minor tags such as `18.4-standard-trixie` over major aliases.
- Add resolver fixtures and tests for valid trixie/bookworm inventories, deprecated `system-*`, missing platform, unavailable non-publish, unavailable publishable, wrong upstream repository, and missing CLI option values.

### Debug Log

- 2026-06-09: Started Story 2.1 from baseline `bee7f60`.
- 2026-06-09: Added `scripts/lib/cnpg.sh` and `scripts/resolve-versions.sh` for CNPG base image resolution only.
- 2026-06-09: Added fixture inventories for `standard-trixie` and `standard-bookworm`, using vendor-scan versioned tags including `18.4-standard-trixie`, `18.4-standard-bookworm`, `17.6-standard-trixie`, and `17.10-standard-bookworm`.
- 2026-06-09: Added negative fixture coverage for deprecated `system-*`, missing `linux/arm64`, unavailable non-publish with specific `skip_reason`, unavailable publishable hard-fail, wrong upstream repository, and missing option values.
- 2026-06-09: Wired `tests/cnpg-resolver/run.sh` into `scripts/validate.sh`.
- 2026-06-09: Required validation passed: `resolve-versions.sh --check-cnpg --fixtures ...`, `tests/cnpg-resolver/run.sh`, shell syntax checks, `make validate`, and `git diff --cached --check`.
- 2026-06-09: Addressed subagent review findings: partial-platform manifests no longer emit `cnpg_digest`, fixture references must resolve from `ghcr.io/cloudnative-pg/postgresql`, and CLI parser errors now use deterministic diagnostics.
- 2026-06-09: Re-ran `tests/cnpg-resolver/run.sh`, `make validate`, shell syntax checks, and `git diff --cached --check` successfully after review fixes.

### Completion Notes

- `resolve-versions.sh --check-cnpg` now owns CNPG base image tag/digest validation and JSON reporting without implementing TimescaleDB, Toolkit, Dockerfile build, smoke test, or GitHub Actions behavior.
- Fixture mode is deterministic and disables live registry fallback; live fallback is limited to Docker CLI inspection when no fixture input is provided.
- JSON output follows the Story 2.1 contract and returns resolved versioned CNPG tags/digests while leaving metadata file mutation to later update orchestration.
- Publishable unavailable rows fail with diagnostics containing command, PostgreSQL major, Debian variant, platform, expected upstream reference, actual result, and remediation.
- Non-publish unavailable rows require a `skip_reason` containing the upstream reference and missing dimension; partial platform manifests keep `cnpg_digest` empty.

## File List

- `cloudnative-pg-timescaledb/scripts/lib/cnpg.sh`
- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/run.sh`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/standard-trixie-valid.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/standard-bookworm-valid.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/system-flavor-deprecated.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/missing-platform-arm64.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/unavailable-nonpublish-pg19beta1.json`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures/unavailable-publishable.yaml`

## Change Log

- 2026-06-09: Implemented Story 2.1 CNPG base image resolver and fixture suite.
- 2026-06-09: Wired CNPG resolver tests into `make validate`.
- 2026-06-09: Hardened resolver after subagent review for partial platform digest emission, upstream repository validation, and deterministic option diagnostics.
