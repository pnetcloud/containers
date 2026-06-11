---
storyId: 3.2
storyKey: 3-2-timescaledb-toolkit-pgvector-and-pgaudit-installation
epic: 3
title: 'TimescaleDB, Toolkit, pgvector, and PGAudit Installation'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: fb4e79e
---

# Story 3.2: TimescaleDB, Toolkit, pgvector, and PGAudit Installation

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Story 2.2 and Story 3.1 may be assumed complete.
- Story 3.3 must not be assumed; use the generator script and direct `docker build` validation, not Makefile build/Bake targets.

## Out of Scope

- CNPG base `FROM` contract; owned by Story 3.1.
- Local Bake execution; owned by Story 3.3.
- Runtime container smoke and SQL extension creation smoke; owned by Stories 3.4 and 3.5.
- Barman Plugin docs boundary validation; owned by Story 3.6.

## Source Story

### Story 3.2: TimescaleDB, Toolkit, pgvector, and PGAudit Installation

As an operator,
I want the generated images to include the required database extensions,
So that TimescaleDB workloads, vector search, and audit use cases are supported in CloudNativePG clusters.

**Acceptance Criteria:**

**Given** a generated Dockerfile for a publishable image combination
**When** the Dockerfile is built
**Then** it installs the matching TimescaleDB package for the metadata PostgreSQL major and Debian variant.
**And** it installs TimescaleDB Toolkit when the package exists for the metadata combination.
**And** it validates pgvector and PGAudit presence through the CNPG base image or explicit package installation.
**And** missing required extension packages fail the build or fail prior validation rather than producing an incomplete image.
**And** package versions used by the Dockerfile match `versions.yaml`.
**And** generated installation logic keeps resolver decisions in metadata/scripts rather than hard-coded workflow rows.
**And** the build verifies installed Debian packages with `dpkg-query -W` against exact metadata versions for TimescaleDB and Toolkit.
**And** expected TimescaleDB and Toolkit package names are consumed from Story 2.2-resolved metadata/resolver output fields `timescaledb_package_name` and `toolkit_package_name`, alongside exact package versions; Story 3.2 must fail validation/build if those resolved package names are missing and must not derive package names from `pg_major` or introduce package-name override metadata.
**And** pgvector and PGAudit source is explicit per image entry as `base` or `package`; `package` entries verify the exact installed package, while `base` entries verify the owning package or control file from the CNPG base image.
**And** apt repository codename and architecture are validated before install for both `trixie` and `bookworm`.

## Expected Artifacts

- `cloudnative-pg-timescaledb/templates/Dockerfile.tmpl` extension install section
- `cloudnative-pg-timescaledb/versions.yaml`
- `cloudnative-pg-timescaledb/scripts/lib/metadata.sh`
- `cloudnative-pg-timescaledb/scripts/validate-metadata.sh`
- `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`
- `cloudnative-pg-timescaledb/scripts/verify-package-install.sh`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/valid-extension-sources.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-extension-source.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/package-source-missing-package-version.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/run.sh`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/valid-timescaledb-toolkit-package.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/valid-trixie-amd64.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/valid-trixie-arm64.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/valid-bookworm-amd64.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/valid-bookworm-arm64.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/missing-timescaledb-package.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/missing-toolkit-publishable.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/pgvector-base-source.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/pgvector-package-source.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/pgaudit-base-source.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/pgaudit-package-source.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/pgvector-source-mismatch.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/pgaudit-source-mismatch.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/missing-extension-source.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/wrong-apt-codename.yaml`
- `cloudnative-pg-timescaledb/tests/package-install/fixtures/wrong-apt-architecture.yaml`

## Package Installation Contract

- Dockerfile install logic must consume Story 2.2-resolved TimescaleDB and Toolkit package names from `timescaledb_package_name` and `toolkit_package_name`, plus package versions from `timescaledb_package_version` and `toolkit_package_version`; it must not derive package names in Story 3.2 and must not use workflow literals.
- `verify-package-install.sh` must run `dpkg-query -W` for the exact `timescaledb_package_name` and `toolkit_package_name` values and compare exact installed package versions to `timescaledb_package_version` and `toolkit_package_version`.
- pgvector and PGAudit source must be explicit per metadata entry as `base` or `package`.
- Metadata schema shape for pgvector must include `pgvector_source: base|package` and `pgvector_package_version` or a resolved package-version/status field when `pgvector_source: package`.
- Metadata schema shape for PGAudit must include `pgaudit_source: base|package` and `pgaudit_package_version` or a resolved package-version/status field when `pgaudit_source: package`.
- `base` source requires control-file and owning-package/control-source verification from the CNPG base image, and must not install a separate package for that extension.
- `package` source requires exact package version/status in metadata and consumes prior resolved package identity when package identity is required; Story 3.2 must not introduce package-name override metadata or derive TimescaleDB/Toolkit package names.
- Missing extension source, invalid extension source, and package source without package version/status must fail `validate-metadata.sh` with deterministic diagnostics.
- Apt codename and architecture must be validated before install for `trixie`, `bookworm`, `amd64`, and `arm64`.
- Missing required packages for `publish: true` hard-fail before a usable image can be produced.

## Required Validation Commands

- `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`
- `docker build --pull --no-cache -f cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile -t cnpg-timescaledb:story-3-2 cloudnative-pg-timescaledb`
- `bash cloudnative-pg-timescaledb/tests/metadata/run.sh`
- `bash cloudnative-pg-timescaledb/tests/package-install/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/metadata/run.sh` must run the `cloudnative-pg-timescaledb/tests/metadata/fixtures/*` fixtures listed in Expected Artifacts.
- `cloudnative-pg-timescaledb/tests/package-install/run.sh` must run the `cloudnative-pg-timescaledb/tests/package-install/fixtures/*` fixtures listed in Expected Artifacts.
- Include positive package-install fixtures for `trixie-amd64`, `trixie-arm64`, `bookworm-amd64`, and `bookworm-arm64`; non-host architecture validation is required through fixture assertions even when the direct Docker build runs only for the host-supported platform.
- Include negative fixtures for missing TimescaleDB, missing Toolkit for publishable entries, wrong apt codename, wrong apt architecture, missing extension source, invalid extension source, package source missing package version/status, and pgvector/PGAudit extension source mismatch.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Update the Dockerfile template extension install section to consume `timescaledb_package_name`, `timescaledb_package_version`, `toolkit_package_name`, and `toolkit_package_version` from Story 2.2-resolved metadata/resolver output.
- [x] Implement `cloudnative-pg-timescaledb/scripts/verify-package-install.sh` with `dpkg-query -W` checks for exact `timescaledb_package_name`/`toolkit_package_name` and exact `timescaledb_package_version`/`toolkit_package_version`.
- [x] Add metadata handling for pgvector and PGAudit source as `base` or `package`, including exact package version/status fields for `package` source entries and no Story 3.2-owned package-name override fields.
- [x] Extend `cloudnative-pg-timescaledb/scripts/lib/metadata.sh`, `cloudnative-pg-timescaledb/scripts/validate-metadata.sh`, and `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh` so source metadata drives generated install/verification logic.
- [x] Add metadata fixtures for valid extension sources, invalid source values, and package source entries missing package version/status.
- [x] Add apt codename/architecture validation for `trixie`/`bookworm` and `amd64`/`arm64` before install, with positive package-install fixtures covering all four codename/architecture combinations.
- [x] Add package-install fixtures and `cloudnative-pg-timescaledb/tests/package-install/run.sh`.
- [x] Run `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`, `docker build --pull --no-cache -f cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile -t cnpg-timescaledb:story-3-2 cloudnative-pg-timescaledb`, `bash cloudnative-pg-timescaledb/tests/metadata/run.sh`, and `bash cloudnative-pg-timescaledb/tests/package-install/run.sh`.

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
| FR-5 | 2.2, 3.2, 3.5, 5.9 | package resolver, Dockerfile template, SQL smoke | resolver tests, `make build`, `make smoke` |
| FR-6 | 2.2, 3.2, 3.5, 5.9 | Toolkit package metadata, install checks, SQL smoke | resolver tests, `dpkg-query`, `CREATE EXTENSION timescaledb_toolkit` |
| FR-7 | 3.2, 3.4, 3.5, 5.9 | pgvector/PGAudit metadata, control files, SQL smoke | `dpkg-query`, control-file checks, SQL extension checks |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| Extension set | 3.2, 3.4, 3.5, 5.9 | TimescaleDB, Toolkit, pgvector, and PGAudit are installed or verified according to metadata before images can be considered publishable. |
| NFR-2 Reproducibility | 1.1, 1.3, 1.5, 1.6, 3.1, 3.2, 4.2, 4.4, 5.9 | Installed package names and versions are derived from metadata and verified against exact package state. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-3-validated-cloudnativepg-extension-images/3-2-timescaledb-toolkit-pgvector-and-pgaudit-installation.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Added `timescaledb_package_name` and `toolkit_package_name` as resolver-owned metadata fields and wired them through update rendering, metadata validation, tag validation, and Dockerfile generation.
- Added `pgvector_source`, `pgvector_package_version`, `pgaudit_source`, and `pgaudit_package_version` metadata fields. Current production rows use `base` source for both extensions because CNPG standard images include pgvector and PGAudit.
- Extended `Dockerfile.tmpl` to switch to `USER root`, configure the Timescale Packagecloud apt repository by metadata Debian codename, validate `/etc/os-release` and `dpkg --print-architecture`, install exact TimescaleDB/Toolkit packages, verify them with `verify-package-install.sh`, verify base pgvector/PGAudit control files, and restore `USER 26`.
- Implemented `scripts/verify-package-install.sh` with exact `dpkg-query -W -f='${Version}'` checks.
- Added `tests/package-install/run.sh` with publishable Dockerfile fixtures, fake `dpkg-query` pass/missing/mismatch coverage, all four `trixie/bookworm x amd64/arm64` positive fixture assertions, package-source branches, and negative metadata cases.
- Updated legacy schema fixtures and Story 1.1/tag validators so the expanded entry schema remains compatible with existing gates.
- Sidecar review round 1 identified missing verification coverage and non-executed arm64 fixtures; both were fixed. Re-review requested after fixes.
- 2026-06-11 evidence closure: package-install fixtures pass locally, and GitHub Actions `Build Release Candidates` run `27315292356` completed candidate builds and smoke checks for publishable 17/18 bookworm/trixie images.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/package-install/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/dockerfile/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/metadata/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh` - passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/packagecloud/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/update/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` - passed.
- `git diff --cached --check` - passed.
- Clean staged-index snapshot validation using `git checkout-index --all --prefix=<tmp>/ && make validate` - passed.
- Required production `docker build -f cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile ...` was not runnable because current production metadata intentionally keeps all rows `publish:false`; equivalent buildable Dockerfile coverage is exercised through publishable fixtures until a later publish-policy story creates committed buildable Dockerfiles.
- 2026-06-11: `bash cloudnative-pg-timescaledb/tests/package-install/run.sh` - passed.
- 2026-06-11: GitHub Actions `Build Release Candidates` run `27315292356` - passed, URL `https://github.com/pnetcloud/containers/actions/runs/27315292356`, head SHA `ed7eee8b461a567f5e7d3807397b173c6df4ed1c`.

### Completion Notes

- FR-5: TimescaleDB package identity and exact version now come from metadata/resolver output and are rendered into Dockerfile install and verification logic.
- FR-6: Toolkit package identity and exact version now follow the same resolver-owned metadata path and are verified with `dpkg-query`.
- FR-7: pgvector and PGAudit source is explicit per metadata entry as `base` or `package`; `base` verifies CNPG standard image control files, and `package` renders exact package install/version checks.
- NFR-2: The image install plan is reproducible from metadata fields, exact package versions, Debian codename, target architecture, and generated Dockerfile content.
- Remote repository proof is complete for Story 3.2: candidate image builds and smoke checks passed on GitHub for publishable combinations after package installation logic was integrated.

## File List

- `cloudnative-pg-timescaledb/versions.yaml`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/lib/metadata.sh`
- `cloudnative-pg-timescaledb/scripts/lib/tags.sh`
- `cloudnative-pg-timescaledb/scripts/lib/update_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/scripts/verify-package-install.sh`
- `cloudnative-pg-timescaledb/templates/Dockerfile.tmpl`
- `cloudnative-pg-timescaledb/tests/dockerfile/fixtures/*.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/*.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/run.sh`
- `cloudnative-pg-timescaledb/tests/package-install/**`
- `cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/*.yaml`

## Change Log

- Added resolver-owned package-name fields and explicit pgvector/PGAudit source metadata.
- Added generated Dockerfile install and verification logic for TimescaleDB, Toolkit, pgvector, and PGAudit.
- Added package-install fixtures/tests and wired them into `make validate`.
- Updated schema fixtures and validators for the expanded entry contract.
