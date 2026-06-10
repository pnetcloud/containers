---
storyId: 2.3
storyKey: 2-3-deterministic-local-update-command
epic: 2
title: 'Deterministic Local Update Command'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: d9a21989ff4db47b49ed97cd16a38004d91eb23f
---

# Story 2.3: Deterministic Local Update Command

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 2.1-2.2 in this epic may be assumed complete.

## Out of Scope

- Scheduled GitHub Actions autocommit; owned by Story 2.5.
- Renovate dependency update behavior; owned by Story 2.6.
- GHCR publish, catalog digest updates, security evidence, and docs release evidence; owned by Epics 4 and 5.

## Source Story

### Story 2.3: Deterministic Local Update Command

As a maintainer,
I want a local update command that refreshes metadata and generated files deterministically,
So that upstream changes produce clear diffs and unchanged upstream state produces a clean no-op.

**Acceptance Criteria:**

**Given** a clean checkout and valid metadata
**When** `make update` runs
**Then** it invokes the resolver, updates `versions.yaml` only when upstream state changes, and regenerates committed outputs.
**And** it preserves manual policy fields such as `publish`, `experimental`, `latest_eligible`, and `skip_reason` unless resolver rules require a hard failure.
**And** it writes compact machine-readable output when requested and human diagnostics to stderr or a summary file.
**And** a no-op run exits successfully without changing files.
**And** a changed run leaves a deterministic diff suitable for autocommit review.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh` update mode
- Root `Makefile` `update` target
- `cloudnative-pg-timescaledb/tests/update/run.sh`
- `cloudnative-pg-timescaledb/tests/update/fixtures/no-op/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/changed-cnpg/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/changed-packages/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/preserve-policy-fields/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/update-resolver-skip-reason/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/preserve-manual-skip-reason/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/hard-fail-publishable-unavailable/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/reject-unsupported-debian-or-pg/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/reject-latest-moved-from-pg18-trixie/`
- `cloudnative-pg-timescaledb/tests/update/fixtures/reject-barman-tooling-in-image-path/`
- `cloudnative-pg-timescaledb/docs/maintainer-guide/update-process.md`

## Update Command Contract

`make update` is the local contract that scheduled automation later reuses.

Required behavior:

- Invoke `resolve-versions.sh update --metadata cloudnative-pg-timescaledb/versions.yaml`, then `make generate`.
- Enforce the supported matrix before and after resolver/generator execution: Debian variants remain exactly `trixie` and `bookworm`, PostgreSQL lines remain exactly `17`, `18`, and experimental `19beta1`, and `latest_eligible: true` remains assigned only to PG18 `trixie`.
- Preserve maintainer-owned policy fields: `publish`, `experimental`, `latest_eligible`, and non-empty manual `skip_reason`, unless a resolver-owned hard failure must stop the run.
- Change `versions.yaml` only when resolver-owned values actually change.
- Sort or emit metadata deterministically so repeated no-op runs leave no diff.
- `make update UPDATE_ARGS=--json` is the required machine interface. Compact JSON is written only to stdout; human diagnostics are written only to stderr or the summary file.
- JSON fields are `changed`, `updated_entries`, `old`, `new`, `generated`, `summary_path`, `exit_code`, and `failure_reason`. Successful no-op and changed runs exit `0`; hard-fail resolver contradictions exit non-zero and set `failure_reason`.
- A no-op fixture must exit `0` and leave `git status --porcelain --untracked-files=all` empty.
- A changed fixture must leave a deterministic diff containing only resolver-owned metadata and generated artifacts.
- Unsupported Debian or PostgreSQL rows from upstream fixtures must not be generated or committed; they must produce deterministic hard-fail diagnostics naming the rejected tuple.
- No update may move `latest_eligible` away from PG18 `trixie`, clear it from PG18 `trixie`, or add it to PG17, PG19beta1, or any `bookworm` row.
- Update/generate must not add Barman packages, bundled Barman tooling, legacy `barman-cloud` references, Barman image tags in PostgreSQL image definitions, or Barman docs/catalog outputs except references to the CloudNativePG Barman Cloud Plugin owned by Story 2.7.

`skip_reason` origin rule:

- Resolver-generated skip reasons must start with reserved prefix `resolver:<code>:` where `<code>` is stable lowercase kebab-case, for example `resolver:missing-toolkit:`.
- Maintainer-authored skip reasons must not use the `resolver:` prefix.
- `make update` may update or clear only resolver-prefixed `skip_reason` values. It must preserve non-prefixed manual values unless the entry is `publish: true`, in which case any `skip_reason` is a hard-fail contradiction.
- Story 2.3 fixtures must prove update/clear behavior for resolver-prefixed reasons and preservation of non-prefixed manual reasons.

Metadata ownership rules:

| Field group | Owner | Allowed Story 2.3 transition |
| --- | --- | --- |
| `cnpg_tag`, `cnpg_digest`, `pg_version`, package version fields, platform availability | resolver-owned | Update when upstream fixture changes; no-op when unchanged. |
| `publish`, `experimental`, `latest_eligible` | maintainer-owned | Preserve exactly; hard-fail if resolver result proves a publishable entry cannot be satisfied. |
| missing or resolver-prefixed `skip_reason` for `publish: false` entries | conditionally resolver-owned | Fill, update, or clear only when upstream fixture changes resolver availability. |
| non-prefixed maintainer-authored `skip_reason` | maintainer-owned | Preserve unless it conflicts with `publish: true`; conflict hard-fails. |
| `19beta1` policy fields | maintainer-owned with resolver guard | Preserve `experimental: true`; never promote publish/latest in Story 2.3. |
| Barman backup tooling and image-path artifacts | forbidden for PostgreSQL images | Hard-fail if resolver or generator output attempts to add Barman packages, bundled backup tooling, legacy `barman-cloud`, or non-plugin Barman image references. |

Fixture runner contract:

- `cloudnative-pg-timescaledb/tests/update/run.sh` creates a temporary clean git worktree per fixture and never depends on live upstream.
- Each fixture contains `input/`, `upstream/`, `expected/`, and `expected-diff.patch` or `expected-no-diff`.
- The runner invokes `make update UPDATE_ARGS="--fixtures <fixture>/upstream --json"`, captures stdout JSON and stderr diagnostics separately, and asserts exit code, diff, generated paths, `skip_reason` origin behavior, and ownership-rule behavior.
- For no-op and hard-fail fixtures, the runner must assert `git status --porcelain --untracked-files=all` is empty after the command; hard-fail fixtures must also prove `make generate` did not leave partial generated changes.
- For changed fixtures, `git status --porcelain --untracked-files=all` must contain only allowlisted resolver-owned metadata and generated artifact paths.

## Required Validation Commands

- make update
- `make update UPDATE_ARGS=--json`
- `bash cloudnative-pg-timescaledb/tests/update/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/update/run.sh` must run no-op, changed CNPG, changed package, policy-preservation, and hard-fail fixtures.
- Include assertions that no-op leaves clean `git status`, changed runs produce deterministic allowlisted diffs, machine JSON fields are present, policy fields obey the ownership table, resolver-prefixed and manual `skip_reason` values behave differently, publishable unavailable combinations fail before generated output is committed, unsupported Debian/PG rows are not generated or committed, `latest_eligible` cannot move away from PG18 `trixie`, and Barman tooling cannot enter metadata/generated image paths except CloudNativePG Barman Cloud Plugin references.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement resolver update mode and `make update` orchestration so metadata resolution and `make generate` run through one deterministic local command.
- [x] Preserve maintainer-owned policy fields while updating only resolver-owned metadata, generated artifacts, and resolver-prefixed `skip_reason` values.
- [x] Enforce matrix and Barman boundary invariants so update cannot introduce unsupported PG/Debian rows, move `latest`, or add legacy Barman tooling to image definitions.
- [x] Add fixture worktree tests for no-op, changed CNPG, changed packages, policy preservation, resolver skip reason updates, manual skip reason preservation, and hard-fail publishable unavailability.
- [x] Implement compact JSON output for `UPDATE_ARGS=--json` with diagnostics kept out of stdout and no partial generated changes on hard failure.
- [x] Run `make update`, `make update UPDATE_ARGS=--json`, and the update fixture runner from a clean checkout.

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
| FR-10 | 2.3, 2.5, 4.6, 5.7, 5.9 | update autocommit, generated artifacts, release catalogs, docs | no-op update test, path allowlist, `make validate`, rehearsal report |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-1 Reliability | 2.3, 2.5, 5.8, 5.9 | Scheduled and local updates are idempotent, clean no-op runs create no commits, failure reasons are documented and rehearsed. |
| NFR-5 Observability | 2.3, 2.5, 4.3, 4.7, 5.8, 5.9 | Update/build/publish/scan workflows write summaries with versions, tags, digests, skipped combinations, evidence status, and failure reasons. |
| Makefile command surface | 1.2, 2.3, 3.3, 4.1, 4.6, 5.6, 5.9 | Root `Makefile` exposes stable `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` targets that delegate to scripts. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-2-upstream-aware-version-maintenance/2-3-deterministic-local-update-command.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented `resolve-versions.sh update` backed by `scripts/lib/update_contract.py`.
- Added update-mode CNPG digest drift handling so already-populated resolver-owned digests can refresh when upstream changes.
- Added transactional restore for metadata and generated outputs when post-write generation or generated-output guards fail.
- Updated package resolver with update-only manual skip preservation.
- Updated generated outputs and generator JSON fixtures after live resolution populated PostgreSQL `17.10`, PostgreSQL `18.4`, TimescaleDB `2.27.2`, and Toolkit `1.23.0` fields.
- Isolated CNPG resolver fixture tests from live `versions.yaml` by using synthetic fixture metadata.
- Fixed nested `make update` JSON cleanliness under `make validate` with `--no-print-directory`.
- Subagent review round 1 found CNPG digest drift, rollback, and fixture-structure gaps; all were fixed.
- Subagent review round 2 reported no blocking findings.
- Follow-up review found stale CNPG resolver-owned skip reasons, out-of-contract update JSON, incomplete fixture-root determinism for Barman plugin resolution, generated-only drift reporting, duplicate row detection, failure summary path handling, and release rehearsal fixture-root coupling; all were fixed.
- `--fixtures` is now a complete deterministic upstream root containing `cnpg/`, `packages/`, and `barman-plugin.json`, so update tests and release rehearsal do not depend on live Barman plugin releases.
- Follow-up review found unsupported upstream CNPG standard tags could be ignored, unresolved CNPG rows could derive package-minor CNPG tags, and named fixture directories needed executable coverage; all were fixed with resolver guards and fixture execution coverage assertions.
- Acceptance review required named Story 2.3 fixtures to be real committed inputs instead of marker-only directories; each fixture now carries `input/versions.yaml`, a complete `upstream/` root, expected artifacts, and the runner executes every committed fixture before the supplemental dynamic edge-case checks.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/cnpg-resolver/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/update/run.sh` - passed.
- `make update` - passed, no-op `changed=false`.
- `make update UPDATE_ARGS=--json` - passed, compact JSON on stdout.
- `jq 'keys, {changed, exit_code, failure_reason, generated_count:(.generated|length), updated_count:(.updated_entries|length), summary_path}' /tmp/story-2-3-update.json` - passed; JSON fields are exactly `changed`, `updated_entries`, `old`, `new`, `generated`, `summary_path`, `exit_code`, and `failure_reason`.
- `bash cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` - passed after moving Barman update fixtures into the shared update fixture root.
- `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh` - passed after release rehearsal consumed the shared update fixture root.
- `shellcheck -x cloudnative-pg-timescaledb/scripts/update.sh cloudnative-pg-timescaledb/scripts/resolve-versions.sh cloudnative-pg-timescaledb/tests/update/run.sh cloudnative-pg-timescaledb/scripts/lib/cnpg.sh` - passed.
- `shellcheck -x cloudnative-pg-timescaledb/tests/barman-plugin/run.sh cloudnative-pg-timescaledb/scripts/release-rehearsal.sh cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh` - passed.
- `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile cloudnative-pg-timescaledb/scripts/lib/update_contract.py` - passed.
- `make validate` - passed.
- `git diff --check HEAD~1..HEAD` - passed.
- `git diff --cached --check` - passed.
- Staged-index snapshot validation using `git checkout-index --all --prefix=<tmp>/ && make validate` - passed.

### Completion Notes

- FR-9: local update now invokes upstream-aware CNPG and package resolvers and writes resolver-owned fields deterministically.
- FR-10: no-op/changed update behavior is covered with JSON output, allowlisted diffs, rollback tests, and full validation wiring.
- NFR-1: no-op update leaves a clean tree; hard failures and post-write failures restore metadata/generated artifacts.
- NFR-5: update JSON and summary output include changed status, updated entries, generated paths, exit code, and failure reason.
- Additional requirements: Debian remains `trixie`/`bookworm`; PostgreSQL remains `17`, `18`, `19beta1`; `latest_eligible` remains PG18 trixie; legacy in-image Barman tooling remains forbidden.
- The compact update JSON no longer includes Barman-specific fields; Barman plugin update behavior is verified through metadata/generated doc diffs and the shared summary path while preserving Story 2.3's exact machine contract.
- Generated-only drift now contributes to top-level `changed=true`; rollback snapshots include the full generated docs directory; dirty update-owned metadata/generated paths fail before update starts.
- Unsupported upstream CNPG standard tags now hard-fail with tuple diagnostics before update writes, and unresolved CNPG rows keep CNPG tag/skip-reason evidence aligned instead of deriving a tag from package versions.
- Named Story 2.3 fixture directories now have committed input/upstream/expected data; the update runner executes those fixtures and compares `git diff --binary` against `expected-diff.patch` or clean status against `expected-no-diff`.

## File List

- `cloudnative-pg-timescaledb/scripts/lib/update_contract.py`
- `cloudnative-pg-timescaledb/scripts/lib/cnpg.sh`
- `cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh`
- `cloudnative-pg-timescaledb/scripts/resolve-versions.sh`
- `cloudnative-pg-timescaledb/scripts/update.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/versions.yaml`
- `cloudnative-pg-timescaledb/generated/17/bookworm/Dockerfile`
- `cloudnative-pg-timescaledb/generated/17/trixie/Dockerfile`
- `cloudnative-pg-timescaledb/generated/18/bookworm/Dockerfile`
- `cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile`
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/cnpg-resolver/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json`
- `cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`
- `cloudnative-pg-timescaledb/tests/update/**`
- `cloudnative-pg-timescaledb/tests/update/fixtures/*/expected-diff.patch`
- `cloudnative-pg-timescaledb/tests/update/fixtures/*/expected-no-diff`
- `cloudnative-pg-timescaledb/tests/update/fixtures/*/input/versions.yaml`
- `cloudnative-pg-timescaledb/tests/update/fixtures/*/upstream/**`
- `cloudnative-pg-timescaledb/tests/update/fixtures/*/expected/contract.txt`
- `cloudnative-pg-timescaledb/tests/barman-plugin/run.sh`
- `cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`
- `cloudnative-pg-timescaledb/docs/maintainer-guide/update-process.md`

## Change Log

- Added deterministic local update orchestration and JSON contract.
- Populated live resolver-owned metadata for current PG17/PG18/PG19beta1 across trixie/bookworm.
- Regenerated committed Dockerfile, matrix, and catalog outputs from updated metadata.
- Added update fixture runner, fixture directory contract markers, rollback tests, and update documentation.
- Adjusted earlier validation gates for the post-Story-2 populated metadata state.
- Hardened deterministic fixture roots, CNPG resolver-owned skip evidence refresh, exact update JSON keys, failure summary output, generated drift detection, full generated-doc rollback coverage, and release rehearsal/Barman fixture consumers.
- Rejected unsupported upstream CNPG standard tags, kept unresolved CNPG metadata aligned with CNPG evidence, and added named fixture execution coverage checks.
- Replaced Story 2.3 marker-only update fixture directories with executable committed fixtures and exact normalized expected diffs.
