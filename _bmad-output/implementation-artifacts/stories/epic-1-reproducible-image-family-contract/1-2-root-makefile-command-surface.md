---
storyId: 1.2
storyKey: 1-2-root-makefile-command-surface
epic: 1
title: 'Root Makefile Command Surface'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: c9e7073
---

# Story 1.2: Root Makefile Command Surface

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 1.1-1.1 in this epic may be assumed complete.

## Out of Scope

- `Resolver, tag, catalog, Dockerfile, and publish logic beyond stable command delegation/stub validation`

## Source Story

### Story 1.2: Root Makefile Command Surface

As a maintainer,
I want stable root-level Makefile commands,
So that local development and CI use the same entry points.

**Acceptance Criteria:**

**Given** a clean repository checkout
**When** I run `make help`
**Then** it lists at least `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke`.
**And** implemented targets delegate to scripts under `cloudnative-pg-timescaledb/scripts/`.
**And** targets whose full behavior is outside Epic 1 expose stable parameter validation and a documented non-zero exit code naming the required implementation area.
**And** Makefile targets do not duplicate resolver, tag, catalog, or validation logic inline.
**And** Makefile targets do not depend on `vendor/`.

## Expected Artifacts

- `Makefile`
- `cloudnative-pg-timescaledb/scripts/ entry-point directory`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`
- `docs/generated-files.md` or `cloudnative-pg-timescaledb/README.md` command-surface section

## Makefile Target Contract

Story 1.2 owns the root command surface, not the full later behavior behind every command.

Targets that must run or delegate successfully in this story:

- `make help`
- `make generate` delegates to `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`, `generate-bake.sh`, `generate-matrix.sh`, `generate-catalog.sh`, and `generate-docs.sh` when those scripts exist; missing later-owned behavior returns the documented non-zero code below.
- `make validate` delegates to currently available validation scripts and reports later-owned validators as controlled non-zero exits until implemented.

Targets that must exist with stable parameter validation and controlled non-zero behavior until later stories implement them:

- `make update`
- `make matrix`
- `make bake-print`
- `make catalog`
- `make build PG=<major> DEBIAN=<variant>`
- `make smoke PG=<major> DEBIAN=<variant>`

Parameter and exit-code rules:

- `PG` accepts only `17`, `18`, or `19beta1`.
- `DEBIAN` accepts only `trixie` or `bookworm`.
- Missing required `PG` or `DEBIAN` for `build` and `smoke` returns exit code `64`.
- Unsupported values return exit code `65`.
- Later-owned target behavior that is not available until its owning story returns exit code `69` and prints the owning story or implementation area.
- `Makefile` must not contain resolver, tag, catalog, package lookup, Dockerfile generation, or publish logic inline; it only validates parameters and delegates.

## Required Validation Commands

- make help
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh`
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh`
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh`, `story-1-2-make-delegation.sh`, and `story-1-2-make-params.sh` must validate the Makefile command surface listed in Expected Artifacts.
- Include positive checks for `make help`, controlled delegation for later-owned targets, valid `PG`/`DEBIAN` parameters, and negative checks for missing required parameters, unsupported PostgreSQL majors, unsupported Debian variants, Alpine, `bullseye`, and unrecognized targets.
- Include one positive fixture and at least one negative fixture for each hard-fail rule introduced by this story.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Create the root `Makefile` facade with the required help text and stable targets: `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke`.
- [x] Add script entry points under `cloudnative-pg-timescaledb/scripts/` so Make targets validate parameters and delegate instead of embedding resolver, tag, catalog, package lookup, Dockerfile, or publish logic inline.
- [x] Implement controlled exit behavior for missing parameters, unsupported PostgreSQL/Debian values, and later-owned target behavior, including explicit rejection of Alpine and `bullseye`.
- [x] Add `story-1-2` Makefile tests for help output, delegation boundaries, parameter validation, unrecognized targets, and absence of `vendor/` dependencies.
- [x] Update the command-surface documentation and run every required validation command from a clean checkout.

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
| FR-1 | 1.1, 1.2, 1.3, 1.5, 1.6, 3.1 | `versions.yaml`, Makefile command surface, generated image definitions, metadata validators | `make help`, `make validate`, `validate-metadata.sh`, `validate-generated.sh` |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-4 Maintainability | 1.1, 1.2, 1.5, 2.1, 2.2, 4.1, 5.6 | PostgreSQL majors and Debian variants are metadata-driven; Makefile targets delegate to scripts; workflows do not duplicate matrix, resolver, tag, or catalog logic. |
| Makefile command surface | 1.2, 2.3, 3.3, 4.1, 4.6, 5.6, 5.9 | Root `Makefile` exposes stable `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` targets that delegate to scripts. |
| NFR-4 Maintainability | 1.2 | Root `Makefile` is a stable command facade that validates user parameters and delegates resolver, tag, generator, catalog, build, smoke, and workflow logic to owned scripts. |
| Makefile parameter safety | 1.2 | `make validate` and subtargets fail deterministically on missing or unsupported parameters, avoiding accidental broad builds or silent no-op automation. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-1-reproducible-image-family-contract/1-2-root-makefile-command-surface.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add a thin root `Makefile` that delegates every target to scripts under `cloudnative-pg-timescaledb/scripts/`.
- Keep parameter validation and controlled exit diagnostics in shared shell helpers instead of Makefile inline logic.
- Run Story 1.1 validation through `make validate` as the currently available gate; leave later behavior as controlled unavailable exits.

### Debug Log

- 2026-06-09: Started Story 1.2 from baseline `c9e7073`.
- 2026-06-09: Added root `Makefile`, delegated command scripts, shared command helper, and Story 1.2 test runners.
- 2026-06-09: Initial `story-1-2-make-params.sh` expected GNU Make to propagate recipe exit code `69`; validation showed GNU Make returns `2` for failed recipes while reporting `Error 69`.
- 2026-06-09: Updated parameter tests to verify exact `64`/`65`/`69` on delegated scripts and `Error <code>` plus owner diagnostics on root Make targets.
- 2026-06-09: Required validation passed: `make help`, `story-1-2-make-help.sh`, `story-1-2-make-delegation.sh`, `story-1-2-make-params.sh`, `make validate`, and `git diff --check`.
- 2026-06-09: Addressed first BMad code review pass: `make validate` now runs Story 1.2 gates, delegation tests verify those gates, and `generate.sh` preflights all required generators before executing any generator to prevent partial side effects.
- 2026-06-09: Re-ran Story 1.2 required validation and `make validate` successfully after review fixes.
- 2026-06-10: Addressed final BMad review findings: hardened root Make variables against make-time and shell metacharacter injection, made `PROJECT_DIR`/`SCRIPT_DIR` non-overridable, pinned plain `PG=19` rejection, and made default `make generate` transactional with rollback/preservation tests.
- 2026-06-10: Final BMad review round passed with Edge Case Hunter and Acceptance Auditor reporting no findings on the staged Story 1.2 diff; staged-only temp clone validation also passed.

### Completion Notes

- Root `Makefile` now exposes stable `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` targets.
- Make targets delegate to `cloudnative-pg-timescaledb/scripts/` entry points; implementation-heavy resolver, generator, catalog, build, and smoke behavior remains owned by later stories.
- `build` and `smoke` validate `PG` and `DEBIAN` before returning controlled unavailable diagnostics for later-owned behavior.
- `make validate` runs the available Story 1.1 and Story 1.2 gates; later stories extend this target as their validators are implemented.
- Root Make variables reject unsafe make-time or shell metacharacter input before recipe execution; scalar `PG`/`DEBIAN` values that are safe to quote still delegate to script validation and report controlled `Error 65`.
- Default `make generate` renders into temporary outputs and promotes them only after all generators succeed; rollback preserves previous generated outputs if promotion fails.

### Latest Validation

- `make help` - passed.
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh` - passed.
- `shellcheck -x cloudnative-pg-timescaledb/scripts/generate.sh cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh` - passed.
- `make validate` - passed.
- Staged-only temp clone validation passed: `make help`, the three Story 1.2 test runners, and `make validate`.
- Final BMad review round passed: Edge Case Hunter no findings, Acceptance Auditor no findings.

## File List

- `Makefile`
- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/scripts/lib/command.sh`
- `cloudnative-pg-timescaledb/scripts/make-help.sh`
- `cloudnative-pg-timescaledb/scripts/update.sh`
- `cloudnative-pg-timescaledb/scripts/generate.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/scripts/matrix.sh`
- `cloudnative-pg-timescaledb/scripts/bake-print.sh`
- `cloudnative-pg-timescaledb/scripts/catalog.sh`
- `cloudnative-pg-timescaledb/scripts/build.sh`
- `cloudnative-pg-timescaledb/scripts/smoke.sh`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`

## Change Log

- 2026-06-09: Implemented Story 1.2 Makefile command surface and delegated scripts.
- 2026-06-09: Added Story 1.2 validation tests for help output, delegation, parameters, unsupported values, and controlled later-owned exits.
- 2026-06-09: Updated Story 1.2 validation after code review so `make validate` executes Story 1.2 tests and generation preflight avoids partial side effects.
- 2026-06-10: Hardened Make variable handling, transactional generation, plain `PG=19` coverage, release rehearsal delegation coverage, and final Story 1.2 review evidence.
