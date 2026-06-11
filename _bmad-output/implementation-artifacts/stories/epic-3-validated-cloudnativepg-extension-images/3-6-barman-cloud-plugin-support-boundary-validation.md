---
storyId: 3.6
storyKey: 3-6-barman-cloud-plugin-support-boundary-validation
epic: 3
title: 'Barman Cloud Plugin Support Boundary Validation'
status: done
baseline_commit: 894c49adf98d85aeb47384e975f5b240081bc31b
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 3.6: Barman Cloud Plugin Support Boundary Validation

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Story 2.7 must be complete; this story extends its `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`, reuses the canonical phrase `CloudNativePG Barman Cloud Plugin`, and validates the generated Barman reference artifact without re-owning upstream reference tracking.
- Stories 3.1-3.5 in this epic may be assumed complete.

## Out of Scope

- Barman Plugin upstream reference tracking; owned by Story 2.7.
- Full public backup guide; owned by Story 5.4.
- CloudNativePG backup/restore workflow implementation; outside v1 image build scope.

## Source Story

### Story 3.6: Barman Cloud Plugin Support Boundary Validation

As a CloudNativePG operator,
I want backup support documented through the modern Barman Cloud Plugin path,
So that I do not depend on deprecated in-image `barman-cloud` binaries for v1.

**Acceptance Criteria:**

**Given** generated image definitions and validation fixtures
**When** image and docs validation run
**Then** the repository documents Barman support through the CloudNativePG Barman Cloud Plugin path.
**And** generated images do not install or advertise legacy in-image `barman-cloud` binaries as the v1 backup mechanism.
**And** validation fails if docs require legacy in-image `barman-cloud` for the v1 image family.
**And** smoke checks keep database extension/runtime validation separate from plugin deployment documentation.
**And** validation fixtures include the exact phrase `CloudNativePG Barman Cloud Plugin` and reject install commands or examples that require legacy in-image `barman-cloud` binaries.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`
- `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/valid-plugin-doc.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/legacy-barman-cloud-required.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/dockerfile-installs-barman-cloud`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/missing-plugin-phrase.md`

## Barman Boundary Validation Contract

- Reuse the Story 2.7 canonical phrase `CloudNativePG Barman Cloud Plugin`.
- Scan `cloudnative-pg-timescaledb/templates/Dockerfile.tmpl`, `cloudnative-pg-timescaledb/templates/**/*.Dockerfile`, `cloudnative-pg-timescaledb/generated/**/Dockerfile`, `cloudnative-pg-timescaledb/docs/**/*.md`, `docs/**/*.md`, and `cloudnative-pg-timescaledb/README.md`.
- Reject Dockerfile/package install examples containing `barman-cloud`, `barman-cloud-wal-archive`, `barman-cloud-backup`, `apt-get install barman`, `apt-get install barman-cloud`, or `pip install barman` as v1 image contents.
- Reject docs that state the PostgreSQL image includes or requires legacy in-image `barman-cloud` binaries for backup.
- Allow docs that mention legacy Barman only to explain that v1 backup support uses the CloudNativePG Barman Cloud Plugin path instead.
- Smoke tests must not deploy the plugin; they only verify database runtime and extension behavior.

## Required Validation Commands

- make validate
- `bash cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` must run every fixture listed in Expected Artifacts.
- Include positive plugin-path docs and negative fixtures for legacy Barman docs, Dockerfile install commands, and missing required plugin phrase.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Extend `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` from Story 2.7 for Epic 3 generated Dockerfiles and docs scope.
- [x] Ensure validation scans `cloudnative-pg-timescaledb/templates/Dockerfile.tmpl` and generated Dockerfiles for forbidden legacy Barman install commands.
- [x] Ensure docs mention the `CloudNativePG Barman Cloud Plugin` path and do not require legacy in-image `barman-cloud` binaries.
- [x] Add docs/Barman fixtures and `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh`.
- [x] Run `make validate` and `bash cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh`.

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
| FR-8 | 2.7, 3.6, 5.4, 5.7, 5.9 | Barman Cloud Plugin references, docs validation fixtures | docs validation, forbidden legacy `barman-cloud` checks |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| Barman Cloud Plugin boundary | 2.7, 3.6, 5.4, 5.7, 5.9 | Barman support uses the CloudNativePG Barman Cloud Plugin path and rejects legacy in-image `barman-cloud` guidance or packages. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-3-validated-cloudnativepg-extension-images/3-6-barman-cloud-plugin-support-boundary-validation.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Extended `validate-barman-boundary.sh` document scanning to reject legacy `barman-cloud` install commands and command examples in docs, while still allowing clearly negated legacy mentions that include the canonical `CloudNativePG Barman Cloud Plugin` phrase.
- Added dedicated Story 3.6 docs fixtures for valid plugin-path docs, required legacy in-image `barman-cloud`, Dockerfile install commands, missing plugin phrase, and a reviewed bypass case using bare `instead`.
- Wired `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` into `make validate` without changing Story 2.7 Barman reference tracking ownership.
- 2026-06-11 evidence closure: Barman plugin docs fixtures and production boundary validator pass locally, and GitHub Actions `Validate` run `27315292349` passed repository validation gates.

### Completion Notes

- FR-8: Barman support remains documented through the CloudNativePG Barman Cloud Plugin path and legacy in-image Barman guidance is rejected.
- Boundary requirement: generated Dockerfiles/docs and smoke checks stay separated from plugin deployment documentation.
- Review closure: BMAD code review reported no remaining BLOCKER/MAJOR findings after the `instead` bypass fixture and validator fix.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` PASS
- `bash cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` PASS
- `git diff --cached --check` PASS
- Staged snapshot `make validate` PASS
- 2026-06-11: `bash cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` - passed.
- 2026-06-11: `bash cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` - passed.
- 2026-06-11: GitHub Actions `Validate` run `27315292349` - passed, URL `https://github.com/pnetcloud/containers/actions/runs/27315292349`, head SHA `ed7eee8b461a567f5e7d3807397b173c6df4ed1c`.

### File List

- `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/valid-plugin-doc.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/legacy-barman-cloud-required.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/legacy-barman-cloud-instead-bypass.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/dockerfile-installs-barman-cloud`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/missing-plugin-phrase.md`

### Change Log

- Strengthened Barman Cloud Plugin boundary validation for docs and generated Dockerfile scope.
- Added Story 3.6 Barman plugin docs fixture harness and make validation integration.
- Added regression coverage for legacy `barman-cloud` install-command and `instead` wording bypasses.
