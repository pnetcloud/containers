---
storyId: 2.7
storyKey: 2-7-barman-cloud-plugin-reference-tracking
epic: 2
title: 'Barman Cloud Plugin Reference Tracking'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: d6c647f
---

# Story 2.7: Barman Cloud Plugin Reference Tracking

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 2.1-2.6 in this epic may be assumed complete.

## Out of Scope

- Installing Barman Cloud Plugin binaries, `barman-cloud`, or backup tooling inside PostgreSQL images; explicitly out of scope for v1.
- Backup restore workflow implementation and operator deployment automation; owned by CloudNativePG/plugin usage outside this image build repo.
- Full public backup docs; owned by Stories 5.4 and 5.7.

## Source Story

### Story 2.7: Barman Cloud Plugin Reference Tracking

As a maintainer,
I want update automation to track the supported Barman Cloud Plugin reference,
So that backup guidance stays current without adding legacy backup binaries to the PostgreSQL images.

**Acceptance Criteria:**

**Given** the repository documents Barman support through the CloudNativePG Barman Cloud Plugin path
**When** `make update` or the scheduled update workflow checks Barman-related upstream references
**Then** it detects changes to the documented CloudNativePG Barman Cloud Plugin image or package reference.
**And** it updates generated docs or metadata references deterministically when the plugin reference changes.
**And** it does not add plugin binaries, legacy `barman-cloud` packages, or backup tooling packages to generated PostgreSQL images.
**And** validation fails if Dockerfiles install legacy in-image Barman tooling or docs direct users away from the Barman Cloud Plugin path.
**And** update summaries report the old reference, new reference, and no-op status for Barman plugin checks.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh`
- `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`
- update resolver check for plugin reference in `cloudnative-pg-timescaledb/scripts/resolve-versions.sh`
- `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`
- `cloudnative-pg-timescaledb/tests/barman-plugin/run.sh`
- `cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/current-reference.json`
- `cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/changed-reference.json`
- `cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/legacy-barman-cloud-dockerfile`
- `cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/legacy-barman-cloud-docs.md`

## Barman Plugin Boundary Contract

This story tracks a documentation/reference value for the CloudNativePG Barman Cloud Plugin; it must not add backup binaries to generated PostgreSQL images.

## Barman Plugin Reference Contract

- Canonical upstream source: CloudNativePG Barman Cloud Plugin documentation at `https://cloudnative-pg.io/plugin-barman-cloud/docs/installation/` and GitHub releases at `https://github.com/cloudnative-pg/plugin-barman-cloud/releases`.
- Current expected plugin release for initial fixtures on 2026-06-09: `v0.12.0`.
- Canonical install manifest reference: `https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.12.0/manifest.yaml`.
- Canonical plugin image: `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.12.0`.
- Canonical sidecar image: `ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.12.0`.
- Selection rule: choose the latest stable GitHub release tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$`; ignore `main`, `dev`, prerelease, draft, and branch snapshot references for maintained docs.
- Storage contract: `cloudnative-pg-timescaledb/versions.yaml` stores the reference under `barman_plugin.release`, `barman_plugin.manifest_url`, `barman_plugin.plugin_image`, `barman_plugin.sidecar_image`, `barman_plugin.source_url`, and `barman_plugin.updated_at_utc`.
- Generated output contract: `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md` includes release, manifest URL, plugin image, sidecar image, source URL, last checked UTC date, and the exact phrase `CloudNativePG Barman Cloud Plugin`.
- Fixture JSON schema for `current-reference.json` and `changed-reference.json`: required keys are `release`, `manifest_url`, `plugin_image`, `sidecar_image`, `source_url`, `checked_at_utc`, and `expected_changed`.
- `make update` summary fields: `old_reference`, `new_reference`, `changed`, `noop`, `manifest_url`, `plugin_image`, `sidecar_image`, and `backup_tooling_free: true`.

Required behavior:

- `make update` detects old/new CloudNativePG Barman Cloud Plugin references and reports no-op status.
- Generated Barman reference docs update deterministically when the upstream plugin reference changes.
- Validation rejects Dockerfiles that install `barman-cloud`, Barman CLI packages, plugin binaries, or backup tooling packages as v1 image contents.
- Validation rejects docs that instruct users to rely on legacy in-image `barman-cloud` binaries instead of the CloudNativePG Barman Cloud Plugin path.
- Update summaries include old reference, new reference, changed/no-op status, and explicit statement that PostgreSQL images remain backup-tooling-free for v1.

Boundary validation contract:

- Scan scope includes `cloudnative-pg-timescaledb/templates/Dockerfile.tmpl`, `cloudnative-pg-timescaledb/templates/**/*.Dockerfile`, `cloudnative-pg-timescaledb/generated/**/Dockerfile`, `cloudnative-pg-timescaledb/docs/**/*.md`, `docs/**/*.md`, and `cloudnative-pg-timescaledb/README.md`.
- Forbidden v1 image content terms in Dockerfiles: `apt-get install barman`, `apt-get install barman-cli`, `apt-get install barman-cloud`, `pip install barman`, `barman-cloud-wal-archive`, `barman-cloud-backup`, and copying plugin binaries into PostgreSQL images.
- Docs must contain the allowed phrase `CloudNativePG Barman Cloud Plugin` when discussing Barman backup support.
- Docs must not instruct users that this PostgreSQL image includes or requires legacy in-image `barman-cloud` binaries for v1 backups.
- Negative fixture diagnostics must include command, artifact path, forbidden term or missing required phrase, expected plugin-path wording, actual content excerpt, and remediation.
- Root `Makefile` `validate` must call `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`; Story 3.6 may extend its scan scope, but Story 2.7 owns the initial validator and legacy Barman rejection path.

Offline fixture contract:

- `cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` must not depend on live upstream. It invokes resolver/update logic with `BARMAN_PLUGIN_FIXTURE=<fixture-json>` for both `current-reference.json` and `changed-reference.json`.
- The current-reference fixture proves no-op behavior: exit `0`, no metadata/doc diff, summary fields `old_reference`, `new_reference`, `changed: false`, and `noop: true`.
- The changed-reference fixture proves deterministic update behavior: exit `0`, expected metadata/doc diff only, summary fields `old_reference`, `new_reference`, `changed: true`, `noop: false`, and `backup_tooling_free: true`.
- Negative legacy fixtures run through the same validation script that `make validate` calls.

## Required Validation Commands

- make update
- `bash cloudnative-pg-timescaledb/tests/barman-plugin/run.sh`
- make validate

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` must run every fixture listed in Expected Artifacts.
- `cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` must run legacy Dockerfile/docs negative fixtures through `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`, the same script called by `make validate`.
- Include positive current/changed reference fixtures and negative fixtures for legacy in-image Barman install commands and legacy backup docs.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `scripts/lib/barman-plugin.sh` and resolver/update integration for the CloudNativePG Barman Cloud Plugin reference fields in `versions.yaml`.
- [x] Generate `docs/generated/barman-plugin-reference.md` deterministically from the tracked plugin release, manifest URL, plugin image, sidecar image, source URL, and UTC check date.
- [x] Implement `validate-barman-boundary.sh` and wire it into `make validate` to reject legacy in-image Barman packages, copied plugin binaries, and docs that bypass the plugin path.
- [x] Add offline current/changed reference fixtures and legacy Dockerfile/docs negative fixtures, using the same validation scripts as production.
- [x] Run `make update`, the Barman plugin fixture runner, and `make validate`, confirming summaries include old/new reference and `backup_tooling_free: true`.

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
| FR-9 | 2.1, 2.2, 2.3, 2.6, 2.7 | CNPG resolver, package resolver, update command, Renovate | resolver tests, `make update`, Renovate config validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-5 Observability | 2.7, 4.7, 5.8, 5.9 | Barman plugin update summaries expose `old_reference`, `new_reference`, `changed`, `noop`, and `backup_tooling_free` fields. |
| NFR-8 Automation safety | 2.7, 5.7, 5.9 | Barman plugin references and generated docs update deterministically through `make update`; generated docs are not hand-edited as final fixes. |
| Barman Cloud Plugin boundary | 2.7, 3.6, 5.4, 5.7, 5.9 | Barman support uses the CloudNativePG Barman Cloud Plugin path and rejects legacy in-image `barman-cloud` guidance or packages. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-2-upstream-aware-version-maintenance/2-7-barman-cloud-plugin-reference-tracking.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Added `barman_plugin` reference storage to `versions.yaml` for release, manifest URL, plugin image, sidecar image, source URL, and UTC checked date.
- Added `scripts/lib/barman-plugin.sh` with live GitHub release resolution and `BARMAN_PLUGIN_FIXTURE` override for offline deterministic tests.
- Extended `make update` through `update_contract.py` to resolve Barman plugin references and emit `old_reference`, `new_reference`, `changed`, `noop`, manifest/image fields, and `backup_tooling_free: true`.
- Extended generated docs so `generate-docs.sh` creates `docs/generated/barman-plugin-reference.md` from metadata; `validate-generated.sh` and generated-drift fixtures now include the Barman doc.
- Added `validate-barman-boundary.sh` to reject legacy in-image Barman installs, copied plugin binaries, and docs that bypass the CloudNativePG Barman Cloud Plugin path.
- Extended metadata/CNPG/package/tag validators to allow `barman_plugin` as the only new optional top-level metadata block.
- Extended autocommit allowlist and fixtures for the single generated Barman reference doc path.
- Subagent review round 1 found two blocker gaps in Dockerfile boundary scanning: line-continuation installs and COPY/ADD plugin binaries to non-standard destinations. Both were fixed with normalization, broader COPY/ADD rejection, and negative fixtures.
- Subagent review round 2 reported no BLOCKER, MAJOR, or MINOR findings.

### Validation Commands

- `make update UPDATE_ARGS=--json` - passed live before GitHub API rate limiting; summary reported `old_reference=v0.12.0`, `new_reference=v0.12.0`, `changed=false`, `noop=true`, and `backup_tooling_free=true`.
- `bash cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/update/run.sh` - passed with `BARMAN_PLUGIN_FIXTURE` current reference for deterministic offline update fixtures.
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` - passed.
- `make validate` - passed in the current working tree after the minimal Story 1.1 compatibility guard for resolver-populated `versions.yaml`.
- Staged-index snapshot validation using `git checkout-index --all --prefix=<tmp>/ && BARMAN_PLUGIN_FIXTURE=<tmp>/cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/current-reference.json make update UPDATE_ARGS=--json && make validate` - passed.
- `git diff --cached --check` - passed.
- `find cloudnative-pg-timescaledb/scripts cloudnative-pg-timescaledb/tests/barman-plugin -type f -name '*.sh' -print0 | xargs -0 bash -n` - passed.

### Completion Notes

- FR-8: Barman support is documented and validated through the CloudNativePG Barman Cloud Plugin path, with legacy in-image Barman tooling rejected.
- FR-9: update automation now tracks the Barman plugin reference alongside other upstream-aware metadata without replacing resolver-owned package/image logic.
- NFR-5: update summaries include old/new Barman references, changed/no-op status, and `backup_tooling_free: true`.
- NFR-8: generated Barman plugin docs are derived from metadata and validated for drift; autocommit staging is limited to the exact generated Barman doc path plus existing resolver-owned paths.
- Barman Cloud Plugin boundary: no plugin binaries, legacy `barman-cloud` packages, Barman CLI packages, or backup tooling packages are added to generated PostgreSQL images.

## File List

- `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`
- `cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh`
- `cloudnative-pg-timescaledb/scripts/lib/cnpg.sh`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/lib/metadata.sh`
- `cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh`
- `cloudnative-pg-timescaledb/scripts/lib/tags.sh`
- `cloudnative-pg-timescaledb/scripts/lib/update_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh`
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/barman-plugin/**`
- `cloudnative-pg-timescaledb/tests/generated-drift/run.sh`
- `cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`
- `cloudnative-pg-timescaledb/tests/update/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures/barman-doc-change/README.md`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh`
- `cloudnative-pg-timescaledb/versions.yaml`
- `docs/maintainer-guide.md`

## Change Log

- Added Barman plugin reference tracking in metadata and update summaries.
- Added generated CloudNativePG Barman Cloud Plugin reference documentation.
- Added Barman boundary validation and offline fixtures for current/changed plugin references and legacy backup-tooling rejection.
- Extended generated drift, update, and autocommit tests for the new Barman generated doc path.
