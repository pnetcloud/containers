---
storyId: 3.4
storyKey: 3-4-container-runtime-smoke-checks
epic: 3
title: 'Container Runtime Smoke Checks'
status: done
baseline_commit: 4fb0709e1ff178b5fa6c867f9834663a1b34b3f7
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 3.4: Container Runtime Smoke Checks

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 3.1-3.3 in this epic may be assumed complete.

## Out of Scope

- SQL extension creation and extension version checks; owned by Story 3.5.
- CI per-platform release candidate smoke orchestration; owned by Story 4.2.
- GHCR publish gates; owned by Epic 4.

## Source Story

### Story 3.4: Container Runtime Smoke Checks

As an operator,
I want container-level smoke tests before publish,
So that built images prove their OS, PostgreSQL, labels, and CloudNativePG runtime assumptions.

**Acceptance Criteria:**

**Given** a locally built image for a supported combination
**When** `cloudnative-pg-timescaledb/scripts/smoke-test.sh` runs container checks
**Then** it verifies the Debian release matches the metadata `debian_variant`.
**And** it verifies PostgreSQL major and server version match metadata.
**And** it verifies required extension control files exist for TimescaleDB, TimescaleDB Toolkit when expected, pgvector, and PGAudit.
**And** it verifies image labels match metadata values.
**And** it verifies CNPG operand runtime assumptions: PostgreSQL binaries are on the expected path, `postgres`, `initdb`, `pg_ctl`, and `psql` execute, the expected `postgres` user exists, data directory permissions allow PostgreSQL startup, and the container starts a temporary PostgreSQL instance without requiring legacy `system-*` Barman tooling.
**And** failures report the image tag, failing check, expected value, and actual value.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/smoke-test.sh`
- Root `Makefile` `smoke` target with `CHECKS=container`
- `cloudnative-pg-timescaledb/tests/smoke/container/run.sh`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/valid-container.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/wrong-debian-release.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/wrong-postgres-major.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/wrong-postgres-server-version.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/missing-control-file.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/missing-label.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/runtime-command-missing.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/missing-postgres-user.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/bad-data-dir-permissions.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/postgres-startup-fails.json`

## Container Smoke Contract

- Container checks verify Debian release, PostgreSQL major, PostgreSQL server version, required extension control files, image labels, expected binaries, expected `postgres` user, data directory permissions, and temporary PostgreSQL startup.
- Required binaries: `postgres`, `initdb`, `pg_ctl`, and `psql`.
- Required control files: `timescaledb.control`, `timescaledb_toolkit.control` when Toolkit is expected, `vector.control`, and `pgaudit.control`.
- Required labels must match the metadata and Dockerfile template label contract.
- The check must not require or validate legacy `system-*` Barman tooling.
- Failure diagnostics include image reference, `PG`, `DEBIAN`, failing check, expected value, actual value, and remediation.

## Required Validation Commands

- make smoke PG=18 DEBIAN=trixie CHECKS=container
- `bash cloudnative-pg-timescaledb/tests/smoke/container/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/smoke/container/run.sh` must run every fixture listed in Expected Artifacts.
- Include negative fixtures for wrong Debian release, wrong PostgreSQL major, wrong PostgreSQL server version, missing extension control file, missing label, missing runtime binary, missing `postgres` user, invalid data directory permissions, and failed temporary PostgreSQL startup.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement container checks in `cloudnative-pg-timescaledb/scripts/smoke-test.sh` for Debian release, PostgreSQL version, labels, control files, binaries, user, permissions, and temporary startup.
- [x] Wire root `Makefile` `smoke PG=<major> DEBIAN=<variant> CHECKS=container` to the smoke script.
- [x] Add deterministic diagnostics for image reference, `PG`, `DEBIAN`, failing check, expected value, actual value, and remediation.
- [x] Add container smoke fixtures and `cloudnative-pg-timescaledb/tests/smoke/container/run.sh`.
- [x] Run `make smoke PG=18 DEBIAN=trixie CHECKS=container` and `bash cloudnative-pg-timescaledb/tests/smoke/container/run.sh`.

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
| FR-7 | 3.2, 3.4, 3.5, 5.9 | pgvector/PGAudit metadata, control files, SQL smoke | `dpkg-query`, control-file checks, SQL extension checks |
| FR-14 | 3.4, 3.5, 4.2, 5.9 | container smoke, SQL smoke, per-platform smoke gates | `make smoke`, platform-specific smoke, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| Debian scope | 1.1, 1.3, 2.1, 2.2, 3.4, 5.1, 5.9 | Only `trixie` and `bookworm` are accepted; Alpine, `bullseye`, and other variants hard-fail. |
| CNPG standard base | 2.1, 3.1, 3.4 | Generated Dockerfiles use digest-pinned CNPG `standard-*` images and reject deprecated `system-*` images. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-3-validated-cloudnativepg-extension-images/3-4-container-runtime-smoke-checks.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented `scripts/smoke-test.sh` as the Story 3.4 container-level smoke runner. It reads metadata, selects the PG/Debian row, verifies labels and runtime facts, and supports deterministic JSON fixtures for validation.
- Wired root `make smoke PG=<major> DEBIAN=<variant> CHECKS=container` through `scripts/smoke.sh`; `CHECKS=sql` remains controlled-unavailable for Story 3.5.
- Production `versions.yaml` remains all `publish:false`, so production `make smoke PG=18 DEBIAN=trixie CHECKS=container` returns the expected skipped diagnostic until release gates enable publishable images. Positive smoke behavior is covered with a publishable metadata fixture and container JSON fixture.
- The smoke runner checks Debian release, PostgreSQL major/version, TimescaleDB/Toolkit/vector/PGAudit control files, Dockerfile label contract, CNPG runtime binaries, `postgres` user, data directory permissions, and temporary PostgreSQL startup without validating legacy `system-*` Barman tooling.
- Subagent review found two issues: the live `/bin/sh -eu` collector used bash-only `${RANDOM}`, and beta major comparison normalized `19beta1` to `19`. Fixed by using POSIX `mktemp -d`, comparing PostgreSQL major exactly to metadata, adding a `19beta1` fixture, and adding a fake-Docker live collector test that fails if `RANDOM` appears in the shell path.
- Subagent re-review found one remaining major: runtime binaries were verified as executable but not checked against the expected PostgreSQL path. Fixed by collecting and asserting `/usr/lib/postgresql/<pg_major>/bin/<binary>` for `postgres`, `initdb`, `pg_ctl`, and `psql`, plus a `wrong-binary-path` negative fixture.
- 2026-06-11 evidence closure: container smoke fixtures pass locally, and GitHub Actions `Build Release Candidates` run `27315292356` ran candidate build/smoke jobs for publishable 17/18 bookworm/trixie images.

### Completion Notes

- FR-7: required extension control files are checked at container runtime before publish.
- FR-14: local container smoke command and deterministic validation fixtures are implemented for image runtime assumptions.
- Debian scope: invalid Debian variants still hard-fail through existing parameter gates; smoke checks verify runtime Debian codename against metadata.
- CNPG standard base: smoke checks align with generated standard-image Dockerfile labels and runtime assumptions, with Barman legacy tooling left out of the container path.

### Validation Commands
- 2026-06-11: `bash cloudnative-pg-timescaledb/tests/smoke/container/run.sh` - passed.
- 2026-06-11: GitHub Actions `Build Release Candidates` run `27315292356` - passed, URL `https://github.com/pnetcloud/containers/actions/runs/27315292356`, head SHA `ed7eee8b461a567f5e7d3807397b173c6df4ed1c`.

- `bash cloudnative-pg-timescaledb/tests/smoke/container/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh` PASS
- `make smoke PG=18 DEBIAN=trixie CHECKS=container` executed; expected non-zero skipped diagnostic on production metadata: `Publish disabled until release gate enables image builds`
- `SMOKE_METADATA=... SMOKE_CONTAINER_FIXTURE=valid-pg19beta1-container.json scripts/smoke-test.sh 19beta1 trixie` PASS through `tests/smoke/container/run.sh`
- Fake-Docker live collector path PASS through `tests/smoke/container/run.sh`
- Runtime binary path negative fixture PASS through `tests/smoke/container/run.sh`
- `git diff --check` PASS
- Staged snapshot `make validate` PASS

### File List

- `Makefile`
- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/scripts/make-help.sh`
- `cloudnative-pg-timescaledb/scripts/smoke.sh`
- `cloudnative-pg-timescaledb/scripts/smoke-test.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/smoke/container/run.sh`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/valid-container.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/valid-pg19beta1-container.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/wrong-debian-release.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/wrong-postgres-major.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/wrong-postgres-server-version.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/missing-control-file.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/missing-label.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/wrong-binary-path.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/runtime-command-missing.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/missing-postgres-user.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/bad-data-dir-permissions.json`
- `cloudnative-pg-timescaledb/tests/smoke/container/fixtures/postgres-startup-fails.json`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`

### Change Log

- Added container runtime smoke runner and root `make smoke CHECKS=container` wiring.
- Added deterministic container smoke fixtures for all Story 3.4 expected positive and negative cases.
- Integrated Story 3.4 smoke tests into `make validate` and updated command help/docs.
- Updated Story 1.2 parameter compatibility expectations for implemented container smoke behavior.
