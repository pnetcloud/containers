---
storyId: 3.3
storyKey: 3-3-local-build-and-bake-execution
epic: 3
title: 'Local Build and Bake Execution'
status: done
baseline_commit: 245684269a59983d23355c01b6b327daea65e92a
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 3.3: Local Build and Bake Execution

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 3.1-3.2 in this epic may be assumed complete.

## Out of Scope

- Runtime and SQL smoke checks; owned by Stories 3.4 and 3.5.
- CI multi-architecture release candidate build, push, and manifest promotion; owned by Epic 4.
- GHCR publish tags and release gates; owned by Epic 4.

## Source Story

### Story 3.3: Local Build and Bake Execution

As a maintainer,
I want local Buildx/Bake targets for each supported image combination,
So that image build behavior can be reproduced before CI publish workflows run.

**Acceptance Criteria:**

**Given** generated Dockerfiles and metadata
**When** `make bake-print` runs
**Then** Docker Bake output includes targets for supported PostgreSQL/Debian/platform combinations.
**And** targets preserve PostgreSQL major isolation and Debian variant isolation.
**And** `make build PG=18 DEBIAN=trixie` builds the selected image target using checkout/path context.
**And** unsupported or skipped combinations are omitted from publishable Bake targets or clearly marked with `skip_reason`.
**And** build commands do not publish images in this epic.
**And** build failures identify the image combination and Dockerfile path.

## Expected Artifacts

- `cloudnative-pg-timescaledb/docker-bake.hcl`
- `cloudnative-pg-timescaledb/scripts/generate-bake.sh`
- Root `Makefile` `bake-print` and `build` targets
- `cloudnative-pg-timescaledb/tests/bake/run.sh`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/valid-publishable-targets.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/skipped-combination.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/default-git-context.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/publish-output-enabled.json`

## Local Bake Contract

- Bake targets are generated from metadata and generator contracts, not handwritten workflow rows.
- Target names use `pg{major}-{debian_variant}`, for example `pg18-trixie` and `pg18-bookworm`.
- Build context must be checkout/path context (`.` or explicit local path), never Docker Buildx default Git context.
- Local `make build` must load or keep images local and must not push to GHCR or create release tags.
- `publish: false` entries are omitted from publishable targets or emitted only as disabled/skipped targets carrying `skip_reason`.
- Build failure diagnostics must include `PG`, `DEBIAN`, target name, Dockerfile path, context, and platform.

## Required Validation Commands

- make bake-print
- make build PG=18 DEBIAN=trixie
- `bash cloudnative-pg-timescaledb/tests/bake/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/bake/run.sh` must run every fixture listed in Expected Artifacts.
- Include negative fixtures for default Git context, publish output enabled in local build, and skipped combinations entering publishable targets.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Extend `cloudnative-pg-timescaledb/scripts/generate-bake.sh` to emit metadata-derived Bake targets for publishable image combinations.
- [x] Wire root `Makefile` `bake-print` and `build PG=<major> DEBIAN=<variant>` targets to generated Bake output.
- [x] Ensure local builds use checkout/path context and never default Git context.
- [x] Ensure local builds do not push images or create GHCR/release tags in Epic 3.
- [x] Add Bake fixtures and `cloudnative-pg-timescaledb/tests/bake/run.sh`.
- [x] Run `make bake-print`, `make build PG=18 DEBIAN=trixie`, and `bash cloudnative-pg-timescaledb/tests/bake/run.sh`.

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
| FR-13 | 3.3, 4.2, 4.5, 5.9 | Buildx/Bake targets, per-platform candidates, manifest digests | `make build`, per-platform smoke, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-6 Portability | 1.3, 2.2, 3.3, 4.2, 5.9 | `linux/amd64` and `linux/arm64` availability is resolved, built, smoked per platform, and rehearsed for every publishable combination. |
| Makefile command surface | 1.2, 2.3, 3.3, 4.1, 4.6, 5.6, 5.9 | Root `Makefile` exposes stable `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` targets that delegate to scripts. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-3-validated-cloudnativepg-extension-images/3-3-local-build-and-bake-execution.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented Bake JSON summary with `targets` for `publish:true` rows and `skipped` rows carrying `skip_reason` for `publish:false` rows.
- Replaced Story 1.5 `bake-print`/`build` controlled-unavailable behavior with Docker Buildx Bake execution through the root Makefile delegation path.
- Kept production rows at `publish:false`; positive local build execution is covered by a publishable metadata fixture and fake Docker, while production `make build PG=18 DEBIAN=trixie` returns a deterministic skipped diagnostic until release gates enable publishable rows.
- Updated stable-row `skip_reason` from the stale Story 2 resolver wording to release-gate wording and regenerated derived artifacts.
- Live `make validate` was run and failed before Story 3.3 gates because unrelated unstaged Story 1.1 validator changes reject the already-committed package/source metadata fields. Staged snapshot validation is the authoritative clean-checkout validation for this story.
- Subagent review found one blocker: root `BUILD_ARGS` passthrough could override local `output=type=docker` with registry push output. Fixed by rejecting all extra Bake passthrough args in Epic 3 `build.sh`, removing `${@:3}` from the Docker invocation, and adding a negative fake-Docker test proving unsafe `BUILD_ARGS` fail before Docker is called.
- 2026-06-11 evidence closure: Bake contract fixtures pass locally, and GitHub Actions `Build Release Candidates` run `27315292356` generated the image matrix and built/smoked all publishable candidate targets.

### Completion Notes

- FR-13: local Buildx/Bake plan and selected-target build command are generated from metadata and reproducible before CI publish workflows.
- NFR-6: Bake summaries and target fixtures preserve `linux/amd64` and `linux/arm64` platform declarations for publishable rows; local build defaults to one loadable platform via `PLATFORM=linux/amd64` override.
- Makefile command surface: root `make bake-print` and `make build PG=<major> DEBIAN=<variant>` delegate to implemented scripts and are covered by Story 3.3 tests.
- Additional requirements: checkout/path context enforced, default Git context rejected, skipped rows prevented from leaking into publishable targets, and local build command prevents registry push/GHCR publish behavior in Epic 3.

### Validation Commands
- 2026-06-11: `bash cloudnative-pg-timescaledb/tests/bake/run.sh` - passed.
- 2026-06-11: GitHub Actions `Build Release Candidates` run `27315292356` - passed, URL `https://github.com/pnetcloud/containers/actions/runs/27315292356`, head SHA `ed7eee8b461a567f5e7d3807397b173c6df4ed1c`.

- `bash cloudnative-pg-timescaledb/tests/bake/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh` PASS
- `make bake-print` PASS, production Bake plan currently has no targets because all rows are `publish:false`
- `make build PG=18 DEBIAN=trixie` executed; expected non-zero skipped diagnostic on production metadata: `Publish disabled until release gate enables image builds`
- `docker buildx bake --file <publishable-fixture-bake> pg18-trixie --set pg18-trixie.platform=linux/amd64 --set pg18-trixie.output=type=docker --print` PASS
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh` PASS
- `bash cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` PASS
- `git diff --check` PASS
- Staged snapshot `make validate` PASS

### File List

- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/versions.yaml`
- `cloudnative-pg-timescaledb/docker-bake.hcl`
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml`
- `cloudnative-pg-timescaledb/docs/generated/compatibility.md`
- `cloudnative-pg-timescaledb/generated/17/bookworm/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/generated/17/trixie/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/generated/18/bookworm/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/scripts/bake-print.sh`
- `cloudnative-pg-timescaledb/scripts/build.sh`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/bake/run.sh`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/valid-publishable-targets.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/skipped-combination.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/default-git-context.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/publish-output-enabled.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/metadata/valid-publishable-targets.yaml`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-missing-target.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-missing-catalog-path.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-missing-variant.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-wrong-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-missing-dockerfile.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-missing-row.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-duplicate-row.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-missing-include-key.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-wrong-latest-eligible.json`

### Change Log

- Added metadata-derived Bake target/skipped summary generation and local HCL rendering for publishable rows.
- Implemented root `make bake-print` and `make build PG=<major> DEBIAN=<variant>` execution paths using generated Bake output.
- Added Story 3.3 bake fixtures, schema checks, fake Docker command assertions, and validation integration.
- Updated skipped stable-row wording and regenerated derived artifacts and docs.
