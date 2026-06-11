---
storyId: 5.7
storyKey: 5-7-workflow-script-and-documentation-validation-gates
epic: 5
title: 'Workflow, Script, and Documentation Validation Gates'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 5.7: Workflow, Script, and Documentation Validation Gates

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 5.1-5.6 in this epic may be assumed complete.

## Out of Scope

- Creating the public docs content; owned by Stories 5.1-5.6 and 5.8.
- Implementing build/publish/release workflow behavior; owned by Epics 2-4.
- Final release rehearsal; owned by Story 5.9.

## Source Story

### Story 5.7: Workflow, Script, and Documentation Validation Gates

As a maintainer,
I want workflows, shell scripts, and documentation examples validated,
So that the public contract remains reliable as automation evolves.

**Acceptance Criteria:**

**Given** workflows, scripts, generated examples, and docs exist
**When** `make validate` and `.github/workflows/validate.yml` run
**Then** GitHub Actions workflows are checked with `actionlint`.
**And** shell scripts are checked with real `shellcheck` in CI; syntax-only fallback is not sufficient for the public validation gate.
**And** validation fails if CI-consumed shell scripts lack strict mode (`set -Eeuo pipefail`) or a documented exception.
**And** documentation examples are validated against metadata, tag policy, catalog policy, and Barman Cloud Plugin support boundaries.
**And** scripts consumed by GitHub Actions write compact JSON to stdout and human diagnostics to stderr or GitHub Step Summary.
**And** validation fails on stale generated docs, stale generated tables, wrong `latest` examples, unpublished catalog references, or legacy in-image Barman guidance.
**And** validation summaries identify the failing file, check, and remediation command.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/generate-docs.sh`
- `cloudnative-pg-timescaledb/scripts/validate-docs.sh`
- `.github/workflows/validate.yml` docs validation wiring
- `cloudnative-pg-timescaledb/tests/docs-validation/`
- `cloudnative-pg-timescaledb/tests/docs-validation/run.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/valid-docs-set/`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/stale-generated-docs/`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/wrong-latest-example/`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/generated-doc-wrong-latest-example/`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/unpublished-catalog-reference/`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/legacy-barman-guidance/`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/script-missing-strict-mode.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/script-valid-compact-json.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/script-json-to-stderr.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/script-human-diagnostics-to-stdout.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/actionlint-invalid-workflow.yml`

## Validation Gate Contract

- `make validate` must run workflow validation, shell validation, generated-file drift validation, docs validation, and story-owned docs fixtures.
- `.github/workflows/validate.yml` must run the same validation surface needed to block stale docs and invalid examples in CI, and both `make validate` and `.github/workflows/validate.yml` must validate every workflow present, including `update.yml`, `build.yml`, and `security-scan.yml` when present.
- `actionlint` checks all GitHub Actions workflow files through deterministic workflow discovery.
- `make validate` reuses or extends `cloudnative-pg-timescaledb/scripts/validate-workflows.sh` and `cloudnative-pg-timescaledb/workflow-policy.yaml` from Story 2.4.
- `shellcheck` checks all git-tracked `cloudnative-pg-timescaledb/scripts/**/*.sh`; strict mode is enforced for scripts referenced by workflows and scripts called by `make validate`, `make generate`, or `make update`, except only documented `strict_mode_exceptions[]` from `cloudnative-pg-timescaledb/workflow-policy.yaml`.
- `.github/workflows/validate.yml` must install or provide `shellcheck`, run it against the same deterministic script list as local validation, and fail when `shellcheck` is unavailable. `bash -n` may remain a local fallback diagnostic, but it must not be reported as satisfying the CI shellcheck gate.
- Scripts consumed by GitHub Actions must write compact machine JSON to stdout and human diagnostics to stderr or `$GITHUB_STEP_SUMMARY`.
- Docs validation must fail stale generated docs/tables, wrong `latest` examples, unpublished catalog references, and legacy in-image Barman guidance.
- Validation summaries must name failing file, check id, expected value, actual value, and remediation command.

## Generated Docs Manifest

- `cloudnative-pg-timescaledb/scripts/generate-docs.sh --json` must enumerate every generated docs/table artifact with path, generator input, owner story, and deterministic generation mode.
- `cloudnative-pg-timescaledb/scripts/validate-docs.sh` must regenerate docs into a temporary directory and diff every manifest path, failing stale or missing generated docs.
- Manifest coverage must include `cloudnative-pg-timescaledb/docs/generated/compatibility-table.md`, `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`, and all existing `cloudnative-pg-timescaledb/docs/generated/**` outputs from completed prior stories.

## Documentation Reference Validation

- `validate-docs.sh` must parse image and catalog references from all git-tracked public Markdown, including `README.md`, `cloudnative-pg-timescaledb/README.md`, `docs/**/*.md`, and `cloudnative-pg-timescaledb/docs/**/*.md`, excluding `_bmad-output/`, `vendor/`, and test fixtures unless fixture mode is active.
- Tag references must be validated through `cloudnative-pg-timescaledb/scripts/validate-tags.sh --json` or the shared tag policy library.
- Catalog references must be validated against `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml`, `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml`, and release/publish metadata.
- Validation must fail docs references to `publish: false` rows, skipped combinations, absent images, wrong PostgreSQL major, wrong Debian variant, unpublished catalog references, or `latest` as a primary example.

## Machine Interface Manifest

- Docs validation must include a machine-interface manifest listing CI-consumed JSON commands, including generator, resolver, and update commands that expose `--json`.
- The validator must execute or fixture-probe each listed command and assert stdout is compact valid JSON only, stderr or `$GITHUB_STEP_SUMMARY` contains human diagnostics, stderr does not contain the JSON payload, and stdout does not contain human text.

## Required Validation Commands

- make validate
- `find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z | xargs -0 actionlint`
- `git ls-files 'cloudnative-pg-timescaledb/scripts/**/*.sh' | xargs shellcheck`
- `bash cloudnative-pg-timescaledb/tests/docs-validation/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/docs-validation/run.sh` must run every fixture listed in Expected Artifacts.
- Include negative fixtures for stale generated docs, wrong `latest` example, wrong `latest` example inside `cloudnative-pg-timescaledb/docs/generated/*.md`, unpublished catalog reference, legacy Barman guidance, shell script missing strict mode, CI script writing JSON to stderr, CI script writing human diagnostics to stdout, missing/unavailable CI shellcheck, and invalid workflow syntax caught by actionlint.
- Include a positive compact-JSON machine interface fixture proving stdout contains compact JSON only and diagnostics are outside stdout.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `cloudnative-pg-timescaledb/scripts/generate-docs.sh` and `cloudnative-pg-timescaledb/scripts/validate-docs.sh` for generated docs, examples, and documentation drift checks.
- [x] Wire `.github/workflows/validate.yml` and `make validate` to run actionlint, shellcheck, generated-file drift validation, docs validation, and story-owned docs fixtures.
- [x] Reuse or extend `cloudnative-pg-timescaledb/scripts/validate-workflows.sh` and `cloudnative-pg-timescaledb/workflow-policy.yaml` so workflow discovery, strict mode exceptions, shellcheck, permissions, and action pinning stay aligned with Story 2.4 and Story 4.7.
- [x] Enforce `set -Eeuo pipefail` for workflow-referenced scripts and scripts called by `make validate`, `make generate`, or `make update`, except documented `strict_mode_exceptions[]`.
- [x] Implement generated docs manifest output from `generate-docs.sh --json` and temp-dir regeneration diff in `validate-docs.sh`.
- [x] Validate docs examples against metadata, tag policy, catalog policy, Barman boundary, generated docs/tables, and wrong `latest` examples by parsing all git-tracked public Markdown, including `cloudnative-pg-timescaledb/docs/**/*.md`, and checking generated catalogs/release metadata.
- [x] Validate CI-consumed machine-interface commands from the manifest emit compact JSON to stdout and human diagnostics to stderr or `$GITHUB_STEP_SUMMARY`.
- [x] Add docs-validation fixtures for stale docs, wrong latest in authored docs, wrong latest in generated docs, unpublished catalog reference, legacy Barman guidance, missing strict mode, valid compact JSON, JSON-to-stderr, human diagnostics to stdout, and invalid workflow syntax.
- [x] Run `make validate`, `find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z | xargs -0 actionlint`, and `bash cloudnative-pg-timescaledb/tests/docs-validation/run.sh`.

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
| FR-10 | 2.3, 2.5, 4.6, 5.7, 5.9 | update autocommit, generated artifacts, release catalogs, docs | no-op update test, path allowlist, `make validate`, rehearsal report |
| FR-11 | 2.6, 5.6, 5.7 | Renovate config, dependency boundaries, maintainer docs | Renovate config validation, docs validation |
| FR-20 | 2.4, 4.7, 5.7, 5.9 | validate workflow, actionlint, shellcheck, docs validation | `.github/workflows/validate.yml`, `make validate`, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-8 Automation safety | 1.6, 2.5, 4.6, 5.6, 5.7, 5.9 | Generated artifacts are reproducible, committed through controlled paths, validated for drift, and never hand-edited as final fixes. |
| Barman Cloud Plugin boundary | 2.7, 3.6, 5.4, 5.7, 5.9 | Barman support uses the CloudNativePG Barman Cloud Plugin path and rejects legacy in-image `barman-cloud` guidance or packages. |
| Generated artifacts | 1.5, 1.6, 3.1, 4.1, 4.6, 5.7, 5.9 | Dockerfiles, Bake file, matrix JSON, catalogs, docs tables, and README examples are generated or validated and drift-checked. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-5-public-operator-and-maintainer-documentation/5-7-workflow-script-and-documentation-validation-gates.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Extended `generate-docs.sh --json` via the generator contract to include a generated docs manifest without removing the existing Story 1.5 `docs[]` contract.
- Added `validate-docs.sh` to regenerate docs into a temp directory, diff generated docs, scan public Markdown references, and probe compact JSON machine interfaces.
- Wired docs validation into `make validate` and added Story 5.7 docs-validation fixtures.
- Tightened `.github/workflows/validate.yml` and `validate-workflows.sh` so CI uses deterministic actionlint discovery and real shellcheck over git-tracked script files.
- Updated workflow permission positive fixture to satisfy the stronger validate workflow contract.

### Completion Notes

- `make validate` now runs generated-file drift validation, docs validation, workflow validation, shell strict-mode validation, and story-owned docs fixtures.
- Docs validation rejects stale generated docs, wrong `latest` primary examples, unpublished catalog guidance, and legacy in-image `barman-cloud` guidance.
- Machine-interface fixture tests assert compact JSON on stdout and reject JSON-to-stderr or human diagnostics on stdout.
- Local direct `actionlint` and `shellcheck` commands were not run because those binaries are unavailable in this environment; CI installs both before `make validate`, and staged snapshot `make validate` passed with the expected local skip notices from `validate-workflows.sh`.
- FR/NFR traceability covered: FR-8, FR-10, FR-11, FR-20, NFR-8, Barman Cloud Plugin boundary, Generated artifacts.

### File List

- `.github/workflows/validate.yml`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate-docs.sh`
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/run.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/valid-docs-set/README.md`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/stale-generated-docs/cloudnative-pg-timescaledb/docs/generated/compatibility.md`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/wrong-latest-example/README.md`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/generated-doc-wrong-latest-example/cloudnative-pg-timescaledb/docs/generated/compatibility.md`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/unpublished-catalog-reference/README.md`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/legacy-barman-guidance/README.md`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/script-missing-strict-mode.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/script-valid-compact-json.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/script-json-to-stderr.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/script-human-diagnostics-to-stdout.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/fixtures/actionlint-invalid-workflow.yml`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/valid-least-privilege.yml`

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/generators/run.sh`
- `bash cloudnative-pg-timescaledb/scripts/validate-docs.sh && bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh && bash cloudnative-pg-timescaledb/tests/docs-validation/run.sh`
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `bash -n cloudnative-pg-timescaledb/scripts/validate-docs.sh cloudnative-pg-timescaledb/tests/docs-validation/run.sh cloudnative-pg-timescaledb/scripts/validate-workflows.sh cloudnative-pg-timescaledb/scripts/validate.sh`
- `git diff --cached --check`
- staged snapshot: `make validate`

### Change Log

- Completed Story 5.7 workflow, script, generated docs, docs reference, and machine-interface validation gates.
- Added docs validation fixtures and wired them into repository validation.
- Strengthened CI validate workflow shellcheck/actionlint commands and workflow-policy fixtures.
