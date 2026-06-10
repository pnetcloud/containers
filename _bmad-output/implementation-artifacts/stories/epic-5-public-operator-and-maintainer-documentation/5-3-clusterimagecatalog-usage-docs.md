---
storyId: 5.3
storyKey: 5-3-clusterimagecatalog-usage-docs
epic: 5
title: 'ClusterImageCatalog Usage Docs'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: 56b374794f01a51bc6005fde8e5ef215b12e5583
---

# Story 5.3: ClusterImageCatalog Usage Docs

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 5.1-5.2 in this epic may be assumed complete.

## Out of Scope

- Catalog generation and digest validation; owned by Story 4.6.
- Tag policy details; owned by Story 5.2.
- Barman Cloud Plugin backup guidance; owned by Story 5.4.
- Release rehearsal; owned by Story 5.9.

## Source Story

### Story 5.3: ClusterImageCatalog Usage Docs

As a CloudNativePG operator,
I want catalog usage examples,
So that I can consume the generated image family through CloudNativePG `ClusterImageCatalog` resources.

**Acceptance Criteria:**

**Given** generated catalog manifests
**When** users read `docs/catalog.md` or README catalog sections
**Then** docs explain how to use `catalog-standard-trixie.yaml`.
**And** docs explain how to use `catalog-standard-bookworm.yaml` as the secondary Debian variant.
**And** examples map PostgreSQL majors to catalog references clearly.
**And** catalog examples prefer digests when available.
**And** examples avoid using `latest` as the primary CloudNativePG path.
**And** docs explain that catalog generation follows published image digests and must not reference unpublished images.

## Expected Artifacts

- `docs/catalog.md`
- README catalog section
- `cloudnative-pg-timescaledb/tests/docs/catalog/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/valid-catalog-docs.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/missing-trixie-catalog.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/missing-bookworm-secondary.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/latest-primary-catalog-example.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/unpublished-catalog-reference.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/per-platform-digest-as-release-catalog.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/pg19beta1-stable-catalog-example.md`

## Catalog Documentation Contract

- Docs must show how to apply or reference `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` as the primary catalog.
- Docs must show `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` as the secondary Debian variant and clearly label it secondary.
- Examples must map CloudNativePG catalog PostgreSQL majors to image references without using `latest` as the primary path.
- Catalog examples must prefer published multi-platform index digests where release metadata provides them.
- Docs must state catalogs are generated from release-complete images and must not reference unpublished tags, unsigned digests, missing digests, wrong PostgreSQL majors, or wrong Debian variants.
- PostgreSQL `19beta1` examples must be absent from stable catalog docs unless clearly marked experimental.

## Required Validation Commands

- make validate
- `bash cloudnative-pg-timescaledb/tests/docs/catalog/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/docs/catalog/run.sh` must run every catalog docs fixture listed in Expected Artifacts.
- Include negative fixtures for missing `trixie` catalog, missing secondary `bookworm` labeling, `latest` as the primary catalog example, unpublished catalog references, per-platform digest where a manifest-list digest is required, and `19beta1` in stable catalog examples.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Write `docs/catalog.md` and README catalog content that shows `catalog-standard-trixie.yaml` as primary and `catalog-standard-bookworm.yaml` as secondary.
- [x] Document that catalog references come from release-complete published images and must use published multi-platform manifest-list digests when available.
- [x] Ensure examples avoid `latest` as the primary CloudNativePG path and clearly map PostgreSQL majors to catalog references.
- [x] Keep `19beta1` out of stable catalog examples unless explicitly marked experimental.
- [x] Add catalog docs fixtures for missing catalog references, wrong secondary labeling, latest primary examples, unpublished references, per-platform digest misuse, and stable PG19beta1 examples.
- [x] Run `make validate` and `bash cloudnative-pg-timescaledb/tests/docs/catalog/run.sh`.

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
| FR-16 | 4.6, 5.3, 5.9 | digest-aware catalogs, catalog docs | `generate-catalog.sh`, catalog validation, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-7 Public trust | 4.4, 4.5, 4.6, 5.1, 5.3, 5.5, 5.9 | Catalog docs make published image references inspectable through CloudNativePG-native resources. |
| Generated artifacts | 1.5, 1.6, 3.1, 4.1, 4.6, 5.3, 5.7, 5.9 | Catalog examples are generated or validated against generated catalog outputs and release metadata. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-5-public-operator-and-maintainer-documentation/5-3-clusterimagecatalog-usage-docs.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add public CloudNativePG `ClusterImageCatalog` usage guidance for the primary Debian `trixie` catalog and secondary Debian `bookworm` catalog.
- Add README catalog sections that expose the same operator path without duplicating tag policy ownership from Story 5.2.
- Add deterministic docs validation and fixtures for missing catalog references, incorrect secondary labeling, `latest` primary examples, unpublished references, per-platform digest misuse, and stable PG19 beta examples.
- Wire catalog docs validation into the repo validation surface.

### Debug Log

- Baseline commit: `56b374794f01a51bc6005fde8e5ef215b12e5583`.
- Initial RED validation failed as expected because `docs/catalog.md` did not exist.
- Fixed two review findings in `tests/docs/catalog/run.sh`: unbackticked `latest` primary prose bypass and PG19 beta stable-catalog bypass where a nearby `experimental` word masked invalid guidance.
- Used staged snapshot validation because the working tree contains unrelated existing Story 1.1 fixture changes.

### Completion Notes

- Implemented Story 5.3 public catalog docs for FR-16, NFR-7 Public trust, and the generated-artifacts requirement.
- `docs/catalog.md`, root README, and package README now document `catalog-standard-trixie.yaml` as primary, `catalog-standard-bookworm.yaml` as secondary, `imageCatalogRef` major mapping, digest preference, and unpublished-image rejection.
- Added docs guardrails and all required positive/negative fixtures for catalog documentation.
- Review subagent found two validator bypasses; both were fixed and revalidated.
- Story status set to `review` after all tasks and validations passed.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/docs/catalog/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/tags/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/readme/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/catalog/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` - passed.
- `git diff --cached --check` - passed.
- Staged snapshot `make validate` via `git checkout-index --all --prefix="$tmpdir/"` - passed.

## File List

- `README.md`
- `docs/catalog.md`
- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/docs/catalog/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/valid-catalog-docs.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/missing-trixie-catalog.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/missing-bookworm-secondary.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/latest-primary-catalog-example.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/unpublished-catalog-reference.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/per-platform-digest-as-release-catalog.md`
- `cloudnative-pg-timescaledb/tests/docs/catalog/fixtures/pg19beta1-stable-catalog-example.md`

## Change Log

- 2026-06-10: Added ClusterImageCatalog usage documentation and validation fixtures for Story 5.3.
- 2026-06-10: Addressed review findings for unbackticked `latest` primary prose and PG19 beta stable-catalog bypasses.
