---
storyId: 5.4
storyKey: 5-4-barman-cloud-plugin-and-backup-boundary-docs
epic: 5
title: 'Barman Cloud Plugin and Backup Boundary Docs'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: d02ee67370f1394f9e87fed4677b1074ce8764a5
---

# Story 5.4: Barman Cloud Plugin and Backup Boundary Docs

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Story 2.7 must be complete; this story consumes its Barman plugin reference contract from `cloudnative-pg-timescaledb/versions.yaml` and/or `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`.
- Story 3.6 may be assumed complete; reuse or extend its Barman boundary validation instead of creating a conflicting validation path.
- Stories 5.1-5.3 in this epic may be assumed complete.

## Out of Scope

- Installing legacy in-image `barman-cloud` tooling; explicitly forbidden by this story.
- Full backup/restore operational runbooks outside the CloudNativePG plugin boundary.
- Release evidence verification docs; owned by Story 5.5.
- Release rehearsal; owned by Story 5.9.

## Source Story

### Story 5.4: Barman Cloud Plugin and Backup Boundary Docs

As a CloudNativePG operator,
I want backup integration guidance aligned with modern CloudNativePG,
So that I know this image family supports the Barman Cloud Plugin path and not legacy in-image backup binaries.

**Acceptance Criteria:**

**Given** the project supports Barman-related workflows through the plugin path
**When** users read `docs/barman-plugin.md` or backup sections
**Then** docs identify CloudNativePG Barman Cloud Plugin as the supported v1 backup integration path.
**And** docs do not require or advertise legacy in-image `barman-cloud` binaries.
**And** docs explain that the image focuses on PostgreSQL and extension runtime contents while backup plugin deployment is handled through CloudNativePG plugin mechanisms.
**And** validation fails if public docs reintroduce legacy in-image Barman guidance for v1.
**And** examples remain compatible with direct image tags and generated catalogs.

## Expected Artifacts

- `docs/barman-plugin.md`
- backup section in README if applicable
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/valid-plugin-docs.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/legacy-barman-cloud-install.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/legacy-barman-cloud-binary-required.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/missing-plugin-reference.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/wrong-plugin-image.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/direct-image-example-broken.md`

## Barman Plugin Documentation Contract

- Docs must identify the modern CloudNativePG Barman Cloud Plugin as the supported v1 backup integration path.
- Docs must reference the current Story 2.7 Barman plugin metadata, not authored hard-coded values: `barman_plugin.release`, `barman_plugin.manifest_url`, `barman_plugin.plugin_image`, and `barman_plugin.sidecar_image` from `cloudnative-pg-timescaledb/versions.yaml` or `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`.
- Hard-coded authored plugin versions/images are forbidden except as controlled Story 2.7 fixture values; docs validation must fail when public docs do not match the current Story 2.7 generated Barman reference artifact.
- Docs must explain that this image family supplies PostgreSQL and extension runtime contents; the backup plugin is deployed through CloudNativePG plugin mechanisms.
- Docs must not require, recommend, install, or validate legacy in-image `barman-cloud` binaries for v1.
- Examples must remain compatible with direct image tags and generated ClusterImageCatalog references.

## Required Validation Commands

- make validate
- `bash cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` must run every Barman docs fixture listed in Expected Artifacts.
- Repository validation must invoke the Barman docs/reference checks through `make validate`, reusing or extending `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` where appropriate.
- Include negative fixtures for legacy install commands, docs that require legacy `barman-cloud` binaries, missing CloudNativePG Barman Cloud Plugin reference, wrong plugin image reference, and backup examples that break direct image or catalog usage.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Write `docs/barman-plugin.md` and any README backup section to identify the CloudNativePG Barman Cloud Plugin as the only supported v1 backup integration path.
- [x] Document plugin image and manifest references by consuming Story 2.7 canonical fields `barman_plugin.release`, `barman_plugin.manifest_url`, `barman_plugin.plugin_image`, and `barman_plugin.sidecar_image` from metadata or `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`.
- [x] Ensure `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` validates public docs and README backup text against the current Story 2.7 Barman reference artifact and rejects drift.
- [x] Ensure repository validation invokes the Barman docs/reference checks through `make validate`, reusing or extending `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` where appropriate.
- [x] Explain the boundary between this PostgreSQL extension image family and CloudNativePG plugin deployment mechanics.
- [x] Keep backup examples compatible with direct image tags and generated ClusterImageCatalog references.
- [x] Add Barman docs fixtures for legacy install commands, legacy binary requirements, missing plugin reference, wrong plugin image, and broken direct image/catalog examples.
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
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-5-public-operator-and-maintainer-documentation/5-4-barman-cloud-plugin-and-backup-boundary-docs.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add public Barman Cloud Plugin boundary docs and README backup sections that keep backup integration on the modern CloudNativePG plugin path.
- Extend the existing Barman docs validation to check public docs against the generated Story 2.7 reference artifact.
- Add required positive and negative fixtures for legacy install commands, legacy binary requirements, missing plugin reference, wrong plugin image drift, and broken database image examples.
- Preserve existing Story 3.6 legacy Barman boundary checks and keep them invoked from `make validate`.

### Debug Log

- Baseline commit: `d02ee67370f1394f9e87fed4677b1074ce8764a5`.
- Initial RED validation failed as expected because `docs/barman-plugin.md` did not exist.
- Adjusted docs wording so the existing Barman boundary validator recognizes the legacy `barman-cloud` text as negated plugin-boundary guidance.
- Split README direct image and catalog examples after self-review found they should not appear as a single combined `spec` example.
- Fixed review findings: restricted legacy guidance negation checks to the matched sentence, then tightened them to require negation tied directly to legacy Barman terms/actions; required Barman reference values to be bound to their public-doc labels.
- Fixed final review finding by scanning every forbidden Barman docs match instead of only the first match per pattern; added a negated-first-invalid-later regression fixture.
- Used staged snapshot validation because the working tree contains unrelated existing Story 1.1 fixture changes.

### Completion Notes

- Implemented Story 5.4 for FR-8 and the Barman Cloud Plugin boundary requirement.
- `docs/barman-plugin.md`, root README, and package README now identify CloudNativePG Barman Cloud Plugin as the supported v1 backup integration path.
- Public docs include generated Story 2.7 reference values for release, manifest URL, plugin image, and sidecar image.
- Validation now rejects legacy install/require guidance, missing plugin references, wrong bound plugin image values, and broken database image examples.
- Review subagents found validator bypasses around unrelated negation and unbound generated reference values; both classes were fixed and revalidated.
- Story status set to `review` after all tasks and validations passed.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/readme/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/catalog/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/tags/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` - passed.
- `git diff --cached --check` - passed.
- Staged snapshot `make validate` via `git checkout-index --all --prefix="$tmpdir/"` - passed.

## File List

- `README.md`
- `docs/barman-plugin.md`
- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/valid-plugin-docs.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/legacy-barman-cloud-install.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/legacy-barman-cloud-binary-required.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/legacy-barman-cloud-negated-first-invalid-later.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/missing-plugin-reference.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/wrong-plugin-image.md`
- `cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures/direct-image-example-broken.md`

## Change Log

- 2026-06-10: Added Barman Cloud Plugin backup boundary docs and public docs validation for Story 5.4.
- 2026-06-10: Addressed review findings for legacy `barman-cloud` negation bypass and unbound generated reference values, including the shared Barman boundary validator.
- 2026-06-10: Added regression coverage for negated-first legacy Barman docs followed by invalid later guidance.
