---
storyId: 5.6
storyKey: 5-6-maintainer-guide-for-generated-files-and-release-process
epic: 5
title: 'Maintainer Guide for Generated Files and Release Process'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 5.6: Maintainer Guide for Generated Files and Release Process

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 5.1-5.5 in this epic may be assumed complete.

## Out of Scope

- Implementing update/build/publish workflows; owned by Epics 2-4.
- Public tag, catalog, Barman, verification, and troubleshooting docs; owned by Stories 5.2-5.5 and 5.8.
- End-to-end release rehearsal automation; owned by Story 5.9.

## Source Story

### Story 5.6: Maintainer Guide for Generated Files and Release Process

As a maintainer,
I want operational docs for updates, generated files, releases, and token policy,
So that future changes preserve automation safety and do not introduce secret leakage.

**Acceptance Criteria:**

**Given** the repository has metadata, generators, workflows, and committed generated outputs
**When** maintainers read `docs/maintainer-guide.md` and `docs/generated-files.md`
**Then** docs explain that `versions.yaml` is the only hand-edited source of truth.
**And** docs explain generated outputs are committed but not hand-edited as final fixes.
**And** docs document `make update`, `make generate`, `make validate`, `make build`, `make smoke`, `make catalog`, and `make bake-print`.
**And** docs explain scheduled update no-op and autocommit behavior.
**And** docs document `GITHUB_TOKEN` as the default autocommit mechanism.
**And** docs document PAT fallback only as a branch-protection exception and include the security tradeoff.
**And** docs state `.env` files and secrets must never be committed.

## Expected Artifacts

- `docs/maintainer-guide.md`
- `docs/generated-files.md`
- `docs/maintainer-guide.md` section `## Release Process`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/valid-maintainer-docs.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/generated-files-hand-edit-allowed.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/missing-make-target.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/pat-default-token.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/missing-no-env-policy.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/artifact-hub-release-step.md`

## Maintainer Documentation Contract

- Docs must identify `cloudnative-pg-timescaledb/versions.yaml` as the only hand-edited image source of truth.
- Docs must list generated outputs and state they are committed but regenerated, not hand-edited as final fixes.
- Docs must document root Makefile targets `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke`.
- Docs must explain scheduled update no-op behavior, generated autocommit path allowlists, and loop prevention.
- Docs must document `GITHUB_TOKEN` as the default autocommit mechanism; PAT fallback is allowed only as a branch-protection exception with explicit security tradeoff.
- Docs must keep Artifact Hub metadata out of v1 release process and state `.env` files and secrets must never be committed.

## Release Process Contract

The `docs/maintainer-guide.md` section `## Release Process` must document this maintainer flow:

1. Edit only `cloudnative-pg-timescaledb/versions.yaml` for image metadata and policy changes.
2. Run `make update` to refresh resolver-owned CNPG base image, TimescaleDB, Toolkit, Barman Cloud Plugin references, and regenerated outputs. Do not describe `make update` as updating GitHub Actions or static helper dependencies; those are Renovate-managed per Story 2.6 and must remain documented in the maintainer guide's Renovate boundary section.
3. Run `make generate` to regenerate Dockerfiles, Bake definitions, matrix JSON, catalogs, docs tables, and generated docs from metadata.
4. Run `make validate` and fix drift, metadata, workflow, shell, docs, tag, catalog, and security policy failures before build or publish.
5. Inspect `make bake-print` output for the resolved PG/Debian/platform matrix and tag set.
6. Run `make build PG=<major> DEBIAN=<variant>` and `make smoke PG=<major> DEBIAN=<variant>` for the target line, or the release rehearsal for the full publishable matrix.
7. Run `make catalog` after publish metadata is available and review generated catalog diffs.
8. Review scheduled update no-op and autocommit runs: no-op runs must create no commits; changed runs must commit only allowlisted generated paths and must not recurse on bot/generated commits.
9. Use `GITHUB_TOKEN` as the default automation credential. PAT fallback is documented only as a branch-protection exception with the risk that a broader token increases blast radius.
10. Keep Artifact Hub metadata out of v1 and never commit `.env`, credentials, tokens, signing secrets, registry passwords, or secret-like values.

## Generated File Ownership Matrix

| Path or Glob | Source of Truth | Generator Command | Commit Policy | Hand-Edit Policy |
| --- | --- | --- | --- | --- |
| `cloudnative-pg-timescaledb/generated/{pg}/{debian_variant}/Dockerfile` | `cloudnative-pg-timescaledb/versions.yaml` and Dockerfile templates | `make generate` / `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh` | Commit generated diffs after validation. | Do not hand-edit as final fix; edit metadata/templates and regenerate. |
| `cloudnative-pg-timescaledb/docker-bake.hcl` | `versions.yaml` and Bake generator templates | `make generate` / `cloudnative-pg-timescaledb/scripts/generate-bake.sh` | Commit generated diff after `make bake-print` and validation. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/matrix.json` | `versions.yaml` and matrix schema | `make matrix` / `cloudnative-pg-timescaledb/scripts/generate-matrix.sh` | Commit only deterministic generated output. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` | release-complete `trixie` metadata and published digests | `make catalog` / `cloudnative-pg-timescaledb/scripts/generate-catalog.sh` | Commit through catalog allowlist only after publish/evidence gates. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` | release-complete `bookworm` metadata and published digests | `make catalog` / `cloudnative-pg-timescaledb/scripts/generate-catalog.sh` | Commit through catalog allowlist only after publish/evidence gates. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/docs/generated/**` | `versions.yaml`, release metadata, catalog metadata, and docs templates | `make generate` / `cloudnative-pg-timescaledb/scripts/generate-docs.sh` | Commit deterministic generated docs/tables after docs validation. | Do not hand-edit as final fix. |
| `cloudnative-pg-timescaledb/config/generated/**` | resolver and release metadata | `make update` or owning resolver script | Commit only allowlisted deterministic generated config. | Do not hand-edit as final fix. |
| `.github/workflows/**` generated sections, if any | workflow templates and repository policy files | owning generator or explicit workflow update story | Commit only after `actionlint` and permission validation. | Hand edits allowed only to non-generated sections; generated sections must be regenerated. |

## Required Validation Commands

- make validate
- `bash cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh` must run every maintainer docs fixture listed in Expected Artifacts.
- Include negative fixtures for allowing hand edits to generated files, missing required Makefile target, PAT described as default token path, missing `.env`/secrets policy, and Artifact Hub metadata in v1 release steps.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Write `docs/maintainer-guide.md` and `docs/generated-files.md` with `versions.yaml` as the only hand-edited image source of truth.
- [x] Document generated outputs, ownership, regeneration commands, drift validation, and the rule that generated files are not hand-edited as final fixes.
- [x] Document root Makefile targets `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` with their intended maintainer use.
- [x] Document scheduled update no-op behavior, autocommit path allowlists, loop prevention, `GITHUB_TOKEN` default, PAT fallback exception, and `.env`/secrets policy.
- [x] Keep Artifact Hub metadata out of the v1 release process docs.
- [x] Add maintainer docs fixtures for hand-edit guidance, missing Make targets, PAT default misuse, missing no-env policy, and Artifact Hub release steps.
- [x] Run `make validate` and `bash cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh`.

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
| FR-11 | 2.6, 5.6, 5.7 | Renovate config, dependency boundaries, maintainer docs | Renovate config validation, docs validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-4 Maintainability | 1.1, 1.2, 1.5, 2.1, 2.2, 4.1, 5.6 | PostgreSQL majors and Debian variants are metadata-driven; Makefile targets delegate to scripts; workflows do not duplicate matrix, resolver, tag, or catalog logic. |
| NFR-8 Automation safety | 1.6, 2.5, 4.6, 5.6, 5.7, 5.9 | Generated artifacts are reproducible, committed through controlled paths, validated for drift, and never hand-edited as final fixes. |
| Metadata source of truth | 1.1, 1.3, 1.5, 5.6 | `cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited image source of truth. |
| Makefile command surface | 1.2, 2.3, 3.3, 4.1, 4.6, 5.6, 5.9 | Root `Makefile` exposes stable `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` targets that delegate to scripts. |
| Artifact Hub out of scope | 5.1, 5.6, 5.9 | Docs and release rehearsal keep Artifact Hub metadata out of v1 scope. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-5-public-operator-and-maintainer-documentation/5-6-maintainer-guide-for-generated-files-and-release-process.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented maintainer docs and generated-file ownership docs as hand-authored documentation for Story 5.6.
- Added `cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh` with deterministic diagnostics and fixtures for the Story 5.6 documentation contract.
- Wired maintainer docs validation into `cloudnative-pg-timescaledb/scripts/validate.sh`.
- Fixed validator false positives around `GITHUB_TOKEN` default plus PAT fallback wording and Artifact Hub out-of-scope wording.

### Completion Notes

- `docs/maintainer-guide.md` documents the release process, command surface, Renovate boundary, scheduled update/autocommit behavior, token policy, and no-secret policy.
- `docs/generated-files.md` documents the generated file ownership matrix, regeneration commands, commit policy, autocommit boundaries, and no-secret policy.
- Maintainer docs fixtures cover valid docs plus negative cases for generated hand edits, missing Make targets, PAT default misuse, missing `.env`/secrets policy, and Artifact Hub release steps.
- FR/NFR traceability covered: FR-11, NFR-4, NFR-8, Metadata source of truth, Makefile command surface, Artifact Hub out of scope.

### File List

- `docs/maintainer-guide.md`
- `docs/generated-files.md`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/valid-maintainer-docs.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/generated-files-hand-edit-allowed.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/missing-make-target.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/pat-default-token.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/missing-no-env-policy.md`
- `cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures/artifact-hub-release-step.md`

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh`
- `bash -n cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh cloudnative-pg-timescaledb/scripts/validate.sh`
- `bash cloudnative-pg-timescaledb/tests/docs/readme/run.sh && bash cloudnative-pg-timescaledb/tests/docs/tags/run.sh && bash cloudnative-pg-timescaledb/tests/docs/catalog/run.sh && bash cloudnative-pg-timescaledb/tests/docs/verification/run.sh`
- `git diff --cached --check`
- staged snapshot: `make validate`

### Change Log

- Completed Story 5.6 maintainer and generated-files documentation.
- Added maintainer docs validation and fixtures.
- Added maintainer docs validation to the repository `make validate` path.
