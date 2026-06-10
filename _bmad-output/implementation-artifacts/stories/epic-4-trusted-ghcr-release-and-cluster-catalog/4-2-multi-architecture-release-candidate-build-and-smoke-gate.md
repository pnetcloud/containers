---
storyId: 4.2
storyKey: 4-2-multi-architecture-release-candidate-build-and-smoke-gate
epic: 4
title: 'Multi-Architecture Release Candidate Build and Smoke Gate'
status: completed
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 4.2: Multi-Architecture Release Candidate Build and Smoke Gate

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Epics 1-3 may be assumed complete through accepted story outputs, especially Story 3.3 Bake targets and Stories 3.4-3.5 container/SQL smoke contracts; Story 4.1 matrix generation may be assumed complete.

## Out of Scope

- Vulnerability scan, SBOM/provenance, signing, and tag promotion; owned by Stories 4.3-4.5.
- Catalog generation; owned by Story 4.6.
- Release summaries/permissions polish; owned by Story 4.7.

## Source Story

### Story 4.2: Multi-Architecture Release Candidate Build and Smoke Gate

As a platform engineer,
I want every publishable image built and smoke-tested as a release candidate for supported platforms,
So that no image can reach GHCR publish without first passing the runtime contract.

**Acceptance Criteria:**

**Given** generated matrix data and image definitions
**When** `.github/workflows/build.yml` runs for a publishable image
**Then** it uses Docker Buildx to build release candidates for `linux/amd64` and `linux/arm64` unless metadata marks a platform unsupported.
**And** it uses checkout/path context so generated files are present in the build.
**And** validation fails if Docker Buildx or Bake uses default Git context for generated-file builds.
**And** it runs smoke tests before any publish step.
**And** smoke tests run once per PostgreSQL/Debian/platform candidate, not only once per multi-platform tag.
**And** release candidates are addressed by per-platform digest or loaded per-platform image reference before manifest-list publication.
**And** smoke checks verify runtime architecture using `dpkg --print-architecture`, map `amd64` to `linux/amd64` and `arm64` to `linux/arm64`, and record the actual runtime architecture in candidate metadata.
**And** a multi-platform manifest is created or promoted only after every publishable platform candidate passes container and SQL smoke.
**And** the build pushes release candidates by immutable digest or candidate tag to GHCR without rolling or final release tags.
**And** it records `image`, `digest`, `platforms`, `bake_target`, Dockerfile path, candidate reference, and intended final tags as job outputs or workflow artifacts.
**And** it emits an immutable candidate metadata artifact and documented schema that downstream Stories 4.3-4.5 must consume; this story does not implement or validate those future-story consumers.
**And** this story does not push release tags to GHCR.
**And** failures identify the PostgreSQL major, Debian variant, platform, and failing gate.
**And** non-publish experimental or skipped combinations cannot accidentally enter the publish path.

## Expected Artifacts

- `.github/workflows/build.yml` candidate build and smoke jobs
- `cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/valid-candidate-metadata.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/default-git-context.yml`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/smoke-after-publish.yml`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/missing-platform-smoke.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/wrong-runtime-architecture.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/final-tag-pushed-in-candidate-job.yml`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/experimental-enters-publish-path.json`

## Release Candidate Contract

- Candidate build jobs use metadata matrix rows and Buildx/Bake checkout/path context only.
- Build jobs may push candidate tags or digest-addressed candidate references to GHCR, but must not push rolling tags, immutable final release tags, or `latest`.
- Every publishable platform candidate must run container and SQL smoke before any manifest-list promotion or publish gate can consume it.
- Candidate metadata artifact required keys: `image`, `candidate_ref`, `candidate_digest`, `platform_digest`, `index_digest`, `platform_digests`, `platform`, `platforms`, `expected_platform`, `runtime_architecture`, `smoke_architecture_status`, `bake_target`, `dockerfile`, `pg_major`, `pg_version`, `debian_variant`, `intended_tags`, `publish`, `experimental`, `latest_eligible`, `smoke_container_status`, and `smoke_sql_status`.
- Digest field semantics are fixed: `candidate_digest` is the immutable candidate image reference digest used by this candidate record; `platform_digest` is the digest for the single `platform` record being smoked; `index_digest` is the multi-platform manifest/index digest created only after all listed publishable platform smoke checks pass; `platform_digests` is an object keyed by platform string (`linux/amd64`, `linux/arm64`) with immutable `sha256:<digest>` string values, and its keys must exactly equal the publishable platforms listed in `platforms` with no missing, extra, or duplicate platform entries.
- Candidate metadata validation must fail if `candidate_digest`, `platform_digest`, `index_digest`, or `platform_digests` are missing, conflated, duplicated incorrectly, non-object shaped, or inconsistent with the singular `platform` and plural `platforms` values or platform key set.
- Multi-platform manifest/index creation or promotion is allowed only after every listed publishable platform candidate has passed smoke.
- This story emits the immutable candidate metadata artifact and schema that downstream scan, evidence, signing, and publish stories must consume; it must not require those downstream jobs to already exist.
- `publish: false` and experimental non-publish rows must not enter publish or final tag paths.

## Required Validation Commands

- make build PG=18 DEBIAN=trixie
- make smoke PG=18 DEBIAN=trixie CHECKS=container
- make smoke PG=18 DEBIAN=trixie CHECKS=sql
- `bash cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh`
- `actionlint .github/workflows/build.yml`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh` must run every fixture listed in Expected Artifacts.
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh` must validate the real `.github/workflows/build.yml` uses checkout/path context for generated-file builds, pushes only candidate references in this story, runs smoke before any downstream gate handoff, records required candidate metadata keys, and excludes non-publish/experimental rows from final-tag paths.
- Include negative fixtures for default Git context, smoke after publish, missing per-platform smoke, wrong runtime architecture, final tag pushed in candidate job, and experimental/non-publish rows entering publish path.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Update `.github/workflows/build.yml` to build release candidates from the Story 4.1 generated matrix using Buildx/Bake checkout/path context.
- [x] Ensure candidate jobs push only immutable candidate references or digest-addressed candidate tags to GHCR, never final immutable tags, rolling major tags, OS-suffixed release tags, or `latest`.
- [x] Run container and SQL smoke per PostgreSQL/Debian/platform candidate before any manifest promotion or downstream release gate consumes that candidate.
- [x] Verify runtime architecture with `dpkg --print-architecture`, map `amd64` to `linux/amd64` and `arm64` to `linux/arm64`, and fail with PostgreSQL major, Debian variant, platform, actual architecture, and gate when the runtime architecture does not match the expected platform.
- [x] Record candidate metadata artifacts with the required keys for image, candidate reference, candidate digest, platform digest, index digest, platform digests, platform, expected platform, runtime architecture, architecture smoke status, platform list, Dockerfile path, Bake target, intended final tags, smoke status, publish flag, experimental flag, and latest eligibility, enforcing distinct digest semantics and cardinality.
- [x] Fail candidate metadata validation when any publishable platform lacks smoke results or when an experimental/non-publish row enters a publish/final-tag path.
- [x] Add workflow fixtures and `cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh` for Git context, smoke ordering, per-platform smoke, candidate-only tag policy, and publish-path filtering.
- [x] Run `make build PG=18 DEBIAN=trixie`, `make smoke PG=18 DEBIAN=trixie CHECKS=container`, `make smoke PG=18 DEBIAN=trixie CHECKS=sql`, `bash cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh`, and `actionlint .github/workflows/build.yml`.

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
| FR-12 | 1.5, 4.1, 4.2, 5.9 | matrix schema, workflow `fromJSON`, release metadata artifacts | `generate-matrix.sh`, workflow validation, release rehearsal |
| FR-13 | 3.3, 4.2, 4.5, 5.9 | Buildx/Bake targets, per-platform candidates, manifest digests | `make build`, per-platform smoke, release rehearsal |
| FR-14 | 3.4, 3.5, 4.2, 5.9 | container smoke, SQL smoke, per-platform smoke gates | `make smoke`, platform-specific smoke, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-2 Reproducibility | 1.1, 1.3, 1.5, 1.6, 3.1, 4.2, 4.4, 5.9 | Metadata, digests, package versions, platforms, tags, generated outputs, and release evidence explain each image after the fact. |
| NFR-6 Portability | 1.3, 2.2, 3.3, 4.2, 5.9 | `linux/amd64` and `linux/arm64` availability is resolved, built, smoked per platform, and rehearsed for every publishable combination. |
| Workflow requirements | 2.4, 2.5, 4.2, 4.3, 4.5, 4.7, 5.9 | `update.yml`, `validate.yml`, `build.yml`, and `security-scan.yml` exist, are validated, and participate in the release rehearsal. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-4-trusted-ghcr-release-and-cluster-catalog/4-2-multi-architecture-release-candidate-build-and-smoke-gate.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented candidate build workflow using generated Story 4.1 matrix rows, checkout/path Docker Buildx Bake context, GHCR candidate-only tags, per-platform build loop, container/SQL smoke before candidate index creation, raw manifest platform digest extraction, and uploaded release-candidate metadata artifact.
- Extended smoke tests with optional `SMOKE_EXPECTED_PLATFORM` runtime architecture validation using `dpkg --print-architecture` for container and SQL smoke paths.
- Added `validate-candidate-metadata.py` with required key, digest, runtime architecture, publish/experimental, candidate-only ref, and group-level platform coverage validation.
- Generated release candidate schema docs through `generate-docs.sh`/`generator_contract.py`; updated generated drift, update, autocommit, workflow policy, and generator contract references.
- Reviewer found two MAJOR issues: metadata validator did not require one record per declared platform, and workflow could record top-level digest as platform digest. Fixed both and reviewer re-check reported no remaining BLOCKER/MAJOR.
- 2026-06-10 remote GitHub Actions proof supersedes earlier local controlled-failure notes: `Build Release Candidates` completed successfully for commit `e12488ecdde7b6f3588d32b75ebf878210273534` at `https://github.com/pnetcloud/containers/actions/runs/27267944657`, proving PG17/PG18 trixie/bookworm candidate build, per-platform smoke, vulnerability scan, and SARIF upload jobs on GitHub Actions.

### Completion Notes

- Story 4.2 direct scope is complete for candidate build/smoke gate automation. Final release tag promotion, scanning, SBOM/provenance, signing, and catalog publication remain deferred to later stories.
- Earlier local `make build` and `make smoke` controlled Error 65 notes are historical from the pre-publishable metadata stage. Current remote Build RC evidence demonstrates the publishable PG17/PG18 trixie/bookworm candidate path runs successfully on GitHub Actions.
- `actionlint .github/workflows/build.yml` is now covered by CI/local tool installation in later validation passes; keep direct actionlint evidence with workflow changes.

### Validation

- `bash cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/update/run.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/matrix/run.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh` passed.
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh` passed; actionlint and shellcheck were unavailable locally and skipped by the script.
- Staged snapshot `make validate` passed.
- `make build PG=18 DEBIAN=trixie` returned Make exit 2 with controlled Error 65 for `publish:false` production row.
- `make smoke PG=18 DEBIAN=trixie CHECKS=container` returned Make exit 2 with controlled Error 65 for `publish:false` production row.
- `make smoke PG=18 DEBIAN=trixie CHECKS=sql` returned Make exit 2 with controlled Error 65 for `publish:false` production row.
- `actionlint .github/workflows/build.yml` skipped locally because `actionlint` is unavailable.
- `gh run view 27267944657 --repo pnetcloud/containers --json url,status,conclusion,headSha,name` returned `name=Build Release Candidates`, `status=completed`, `conclusion=success`, `headSha=e12488ecdde7b6f3588d32b75ebf878210273534`, `url=https://github.com/pnetcloud/containers/actions/runs/27267944657`.

### File List

- `.github/workflows/build.yml`
- `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/smoke-test.sh`
- `cloudnative-pg-timescaledb/scripts/validate-candidate-metadata.py`
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/generated-drift/run.sh`
- `cloudnative-pg-timescaledb/tests/update/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/default-git-context.yml`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/experimental-enters-publish-path.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/final-tag-pushed-in-candidate-job.yml`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/missing-platform-record.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/missing-platform-smoke.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/smoke-after-publish.yml`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/valid-candidate-metadata.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/wrong-runtime-architecture.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh`
- `cloudnative-pg-timescaledb/workflow-policy.yaml`
- `docs/generator-contracts.md`

### Change Log

- 2026-06-09: Implemented Story 4.2 candidate build/smoke workflow, candidate metadata contract, generated schema docs, regression fixtures, validation wiring, and reviewer fixes for platform coverage and platform digest extraction.
