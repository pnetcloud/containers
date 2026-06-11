---
storyId: 2.6
storyKey: 2-6-renovate-dependency-boundaries
epic: 2
title: 'Renovate Dependency Boundaries'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: 3475a543a7e099a6cf58fa40d83a1a8715112cef
---

# Story 2.6: Renovate Dependency Boundaries

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 2.1-2.5 in this epic may be assumed complete.

## Out of Scope

- CNPG, TimescaleDB, Toolkit, and platform availability decisions; owned by custom resolver stories 2.1 and 2.2.
- Scheduled update/autocommit execution; owned by Story 2.5.
- Release build, scan, signing, and publish workflows; owned by Epic 4.

## Source Story

### Story 2.6: Renovate Dependency Boundaries

As a maintainer,
I want Renovate to manage trackable dependencies without fighting the custom resolver,
So that dependency updates are reviewable and major changes remain controlled.

**Acceptance Criteria:**

**Given** repository automation dependencies and metadata-managed image/package values
**When** Renovate scans the repository
**Then** it tracks GitHub Actions, non-resolver Docker/build metadata, non-CNPG base image digest references, and static helper dependency values that are safe for Renovate.
**And** custom managers or regex rules are documented where Renovate reads metadata-like values.
**And** major updates require manual review.
**And** Renovate does not replace the resolver for CNPG, TimescaleDB, Toolkit, or platform availability decisions.
**And** Renovate configuration avoids broad automerge for release-sensitive dependencies.
**And** update workflow summaries distinguish Renovate-originated changes from resolver-originated changes.

## Expected Artifacts

- `renovate.json`
- `package.json`
- `package-lock.json`
- `cloudnative-pg-timescaledb/config/change-origin-rules.json`
- `cloudnative-pg-timescaledb/scripts/classify-update-origin.sh`
- `docs/maintainer-guide.md` Renovate boundary section
- `cloudnative-pg-timescaledb/tests/renovate/run.sh`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/valid-renovate.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/broad-automerge-release-sensitive.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/resolver-owned-cnpg-manager.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/resolver-owned-versions-yaml-fields.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/resolver-owned-pg-debian-matrix-fields.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/forbidden-legacy-barman-manager.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/forbidden-barman-plugin-metadata-manager.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/major-update-automerge.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/summary-origin-labels.json`

## Renovate Boundary Contract

Renovate may track simple dependency surfaces, but must not replace resolver-owned availability logic.

Allowed Renovate ownership:

- GitHub Actions versions, with release-sensitive actions still subject to SHA pinning policy.
- Static helper dependencies and tool versions where updates do not require PG/Debian/platform availability decisions.
- Docker/build metadata values that are not CNPG/TimescaleDB/Toolkit availability decisions.

Forbidden Renovate ownership:

- Selecting CNPG `standard-*` tags or digest availability for a PostgreSQL/Debian/platform tuple.
- Selecting TimescaleDB or Toolkit package availability or package versions for publishable image entries.
- Promoting PostgreSQL `19beta1`, changing `latest_eligible`, or changing `publish` policy.
- Broad automerge for release-sensitive dependencies.
- Managing `cloudnative-pg-timescaledb/versions.yaml` fields `cnpg_tag`, `cnpg_digest`, `timescaledb_version`, `timescaledb_package_version`, `toolkit_version`, `toolkit_package_version`, `platforms`, `publish`, `experimental`, `latest_eligible`, or `skip_reason`.
- Managing `cloudnative-pg-timescaledb/versions.yaml` matrix fields `pg_major`, `pg_version`, or `debian_variant`; supported PG/Debian rows are controlled by metadata policy and resolver stories, not Renovate.
- Adding or updating legacy `barman-cloud`, Barman CLI, backup-tooling packages, backup-tooling images, or generated PostgreSQL image references.
- Managing `cloudnative-pg-timescaledb/versions.yaml` `barman_plugin.*` fields; Story 2.7 owns CloudNativePG Barman Cloud Plugin reference tracking through resolver/update logic.

Summary-origin contract:

- Story 2.6 owns the classification rules only, not scheduled workflow execution.
- `cloudnative-pg-timescaledb/config/change-origin-rules.json` maps path globs and metadata fields to `renovate-originated` or `resolver-originated`.
- `change-origin-rules.json` must classify `pg_major`, `pg_version`, `debian_variant`, all resolver-owned image/package fields, and all `barman_plugin.*` fields as non-Renovate-owned/resolver-originated surfaces.
- `cloudnative-pg-timescaledb/scripts/classify-update-origin.sh --rules cloudnative-pg-timescaledb/config/change-origin-rules.json --changed-files <path>` emits compact JSON with `renovate_originated[]`, `resolver_originated[]`, and `unknown[]`.
- `cloudnative-pg-timescaledb/tests/renovate/run.sh` must assert that the production classifier labels dependency changes as `renovate-originated` and resolver-owned metadata/package changes as `resolver-originated`.
- Story 2.5 update summary generation must consume `classify-update-origin.sh` when both stories are complete.

Major updates require manual review. Patch/minor updates may automerge only when scoped to non-release-sensitive dependencies and after validation passes.

Renovate ownership matrix:

| Path or fileMatch | Manager/datasource | Allowed updates | Automerge | Required review |
| --- | --- | --- | --- | --- |
| `.github/workflows/*.yml` | `github-actions` | patch/minor/digest for non-release-sensitive actions | allowed only after validation | major or release-sensitive updates |
| `cloudnative-pg-timescaledb/workflow-policy.yaml` comments/static versions | regex/custom manager | static helper versions only | disabled | all changes |
| `package.json`, `package-lock.json` | npm | validator/tooling patch/minor | allowed after validation | major |
| `cloudnative-pg-timescaledb/scripts/**` static tool version comments | regex/custom manager | helper tool versions only | disabled unless explicitly safe | all changes |
| `cloudnative-pg-timescaledb/versions.yaml` PG/Debian matrix fields | none | forbidden | forbidden | metadata/resolver stories only |
| `cloudnative-pg-timescaledb/versions.yaml` resolver-owned image/package fields | none | forbidden | forbidden | resolver stories only |
| `cloudnative-pg-timescaledb/versions.yaml` `barman_plugin.*` fields | none | forbidden for Renovate | forbidden | Story 2.7 resolver/update path only |

Forbidden patterns include Renovate managers that modify `pg_major`, `pg_version`, `debian_variant`, CNPG `standard-*` tag selection, CNPG digests, TimescaleDB package versions, Toolkit package versions, platform availability, `publish`, `experimental`, `latest_eligible`, `skip_reason`, `barman_plugin.*`, legacy `barman-cloud`, Barman CLI, backup-tooling packages, or backup-tooling image references.

The clean-checkout validation contract is `npm ci` followed by `npm exec -- renovate-config-validator renovate.json`. `package.json` and `package-lock.json` must pin the validator toolchain needed for this command.

## Required Validation Commands

- `npm ci`
- `npm exec -- renovate-config-validator renovate.json`
- `bash cloudnative-pg-timescaledb/tests/renovate/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/renovate/run.sh` must validate the positive fixture and reject the negative fixtures listed in Expected Artifacts.
- Include negative tests for broad release-sensitive automerge, resolver-owned CNPG/package managers, major update automerge, `resolver-owned-versions-yaml-fields.json` managers for `pg_major`, `pg_version`, `debian_variant`, `cnpg_tag`, `cnpg_digest`, `timescaledb_version`, `timescaledb_package_version`, `toolkit_version`, `toolkit_package_version`, `platforms`, `publish`, `experimental`, `latest_eligible`, and `skip_reason`, plus forbidden legacy Barman and `barman_plugin.*` managers.
- Include summary-origin classification tests for Renovate-originated dependency changes and resolver-originated metadata/package/Barman plugin changes.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Add Renovate configuration and pinned validator tooling that can be installed with `npm ci` and validated from a clean checkout.
- [x] Define allowed Renovate ownership for GitHub Actions/tooling dependencies and explicit forbidden ownership for resolver-managed PG/Debian matrix, CNPG, TimescaleDB, Toolkit, platform, publish, experimental, latest, skip, Barman plugin, and legacy backup-tooling fields.
- [x] Implement `classify-update-origin.sh` and `change-origin-rules.json` for Renovate-originated versus resolver-originated update summaries.
- [x] Add Renovate fixtures that accept the valid config and reject broad automerge, resolver-owned managers, major-update automerge, and forbidden `versions.yaml` field managers.
- [x] Run `npm ci`, Renovate config validation, and the Renovate fixture runner.

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
| FR-9 | 2.1, 2.2, 2.3, 2.6, 2.7 | CNPG resolver, package resolver, update command, Renovate | resolver tests, `make update`, Renovate config validation |
| FR-11 | 2.6, 5.6, 5.7 | Renovate config, dependency boundaries, maintainer docs | Renovate config validation, docs validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-3 Security | 2.4, 2.5, 4.3, 4.4, 4.7, 5.5, 5.9 | Release-sensitive dependency automation avoids broad automerge and remains behind validation gates. |
| NFR-4 Maintainability | 1.1, 1.2, 1.5, 2.1, 2.2, 4.1, 5.6 | Renovate handles simple dependencies while resolver-owned image/package decisions stay centralized in metadata and scripts. |
| Renovate boundary | 2.6, 5.6, 5.7 | Renovate tracks safe static dependencies but does not replace CNPG, TimescaleDB, Toolkit, or platform availability resolver logic. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-2-upstream-aware-version-maintenance/2-6-renovate-dependency-boundaries.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Added root Renovate config with `github-actions` and `npm` managers only, major updates gated by manual dashboard approval, npm patch/minor automerge, and release-sensitive GitHub Actions automerge disabled.
- Added pinned `renovate` validator tooling in `package.json` and `package-lock.json`; `.github/workflows/validate.yml` now runs `npm ci` and `npm exec -- renovate-config-validator renovate.json` from a clean checkout.
- Added `change-origin-rules.json` and `classify-update-origin.sh` to classify changed paths into `renovate_originated`, `resolver_originated`, and `unknown` summary buckets.
- Updated `.github/workflows/update.yml` summary generation to consume `classify-update-origin.sh` after resolver-owned staging, preserving separate Resolver, Renovate, and Unknown headings.
- Added `tests/renovate/run.sh` with positive and negative fixtures for broad automerge, major automerge, resolver-owned CNPG/TimescaleDB/Toolkit/PG/Debian fields, Barman plugin metadata, and legacy Barman tooling managers.
- Added maintainer documentation for Renovate boundaries and resolver ownership.
- Subagent review round 1 reported no BLOCKER, MAJOR, or MINOR findings. Residual risks: branch protection controls actual automerge safety, and field-level origin rules are contract markers while current classifier operates by changed path.
- Subagent review round 2 after adding the CI Renovate validator step and classifier missing-argument diagnostics reported no BLOCKER, MAJOR, or MINOR findings.
- 2026-06-11 evidence closure: direct Renovate boundary tests and clean-checkout validator sequence pass locally, and GitHub Actions `Validate` run `27315292349` passed the repository Renovate config gate on branch `codex/bmad-cloudnativepg-timescaledb-execution`.

### Validation Commands

- `npm ci` - passed; npm audit reported 0 vulnerabilities, with Renovate dependency deprecation warnings only.
- `npm exec -- renovate-config-validator renovate.json` - passed.
- `bash cloudnative-pg-timescaledb/tests/renovate/run.sh` - passed.
- `cloudnative-pg-timescaledb/scripts/classify-update-origin.sh --rules cloudnative-pg-timescaledb/config/change-origin-rules.json --changed-files <tmp>` - passed.
- `cloudnative-pg-timescaledb/scripts/classify-update-origin.sh --changed-files` - passed negative diagnostic check.
- `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/*.yml` - passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh` - passed; local `actionlint`/`shellcheck` binaries are not installed, so the script reported deterministic SKIPs while running built-in policy checks.
- `find cloudnative-pg-timescaledb/scripts cloudnative-pg-timescaledb/tests/renovate -type f -name '*.sh' -print0 | xargs -0 bash -n` - passed.
- Staged-index snapshot validation using `git checkout-index --all --prefix=<tmp>/ && npm ci && npm exec -- renovate-config-validator renovate.json && bash cloudnative-pg-timescaledb/tests/renovate/run.sh && go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/*.yml && make validate` - passed.
- `git diff --cached --check` - passed.
- 2026-06-11: `npm ci && npm exec -- renovate-config-validator renovate.json` - passed; npm audit reported 0 vulnerabilities with Renovate dependency deprecation warnings only.
- 2026-06-11: `bash cloudnative-pg-timescaledb/tests/renovate/run.sh` - passed.
- 2026-06-11: GitHub Actions `Validate` run `27315292349` - passed, URL `https://github.com/pnetcloud/containers/actions/runs/27315292349`, head SHA `ed7eee8b461a567f5e7d3807397b173c6df4ed1c`.

### Completion Notes

- FR-9: Renovate now handles safe dependency surfaces without replacing CNPG, TimescaleDB, Toolkit, PostgreSQL/Debian, platform, publish, latest, skip, or Barman plugin resolver ownership.
- FR-11: Maintainer docs and tests document Renovate dependency boundaries and the clean-checkout validation contract.
- NFR-3 Security: release-sensitive GitHub Actions updates do not broad-automerge, major updates require manual review, and CI validates Renovate config before local gates.
- NFR-4 Maintainability: resolver-owned image/package decisions remain centralized in metadata and resolver scripts; Renovate ownership is constrained and fixture-tested.
- Renovate boundary: negative fixtures reject managers for `versions.yaml`, `pg_major`, `pg_version`, `debian_variant`, CNPG tags/digests, TimescaleDB/Toolkit package fields, policy fields, `barman_plugin.*`, and legacy Barman tooling.
- Remote repository proof is complete for Story 2.6: the GitHub Actions `Validate` workflow runs the Renovate config gate before local repository gates and passed on branch `codex/bmad-cloudnativepg-timescaledb-execution`.

## File List

- `.github/workflows/update.yml`
- `.github/workflows/validate.yml`
- `cloudnative-pg-timescaledb/config/change-origin-rules.json`
- `cloudnative-pg-timescaledb/scripts/classify-update-origin.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/renovate/run.sh`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/broad-automerge-release-sensitive.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/forbidden-barman-plugin-metadata-manager.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/forbidden-legacy-barman-manager.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/major-update-automerge.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/resolver-owned-cnpg-manager.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/resolver-owned-pg-debian-matrix-fields.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/resolver-owned-versions-yaml-fields.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/summary-origin-labels.json`
- `cloudnative-pg-timescaledb/tests/renovate/fixtures/valid-renovate.json`
- `docs/maintainer-guide.md`
- `package-lock.json`
- `package.json`
- `renovate.json`

## Change Log

- Added Renovate config, pinned validator tooling, and CI validation step.
- Added Renovate/resolver origin classifier and update summary integration.
- Added Renovate boundary tests and fixtures for resolver-owned fields, release-sensitive automerge, major updates, and Barman exclusions.
- Documented Renovate boundaries for maintainers.
