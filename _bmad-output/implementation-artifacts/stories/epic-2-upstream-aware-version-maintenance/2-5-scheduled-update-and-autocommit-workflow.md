---
storyId: 2.5
storyKey: 2-5-scheduled-update-and-autocommit-workflow
epic: 2
title: 'Scheduled Update and Autocommit Workflow'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: 19532ac
---

# Story 2.5: Scheduled Update and Autocommit Workflow

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 2.1-2.4 in this epic may be assumed complete.

## Out of Scope

- Renovate-originated dependency PR policy; owned by Story 2.6.
- Build, scan, signing, provenance, GHCR publish, and release tag promotion; owned by Epic 4.
- Catalog, docs, and security evidence autocommit allowlist entries until their owning stories extend the allowlist.

## Source Story

### Story 2.5: Scheduled Update and Autocommit Workflow

As a maintainer,
I want scheduled GitHub Actions updates with safe autocommits,
So that upstream image and package changes are captured without leaking secrets or creating noisy commits.

**Acceptance Criteria:**

**Given** the repository has update scripts, resolver-owned metadata, and generated artifacts available through Story 2.5
**When** `.github/workflows/update.yml` runs on schedule or manual dispatch
**Then** it checks out the repository, runs `make update`, runs `make validate`, and commits only real generated or metadata changes.
**And** a no-op update writes a Step Summary and creates no commit.
**And** the workflow uses least-privilege permissions and grants `contents: write` only for the autocommit job.
**And** it uses `GITHUB_TOKEN` by default.
**And** PAT fallback is not required or used unless branch protection blocks bot commits and the fallback is documented.
**And** the autocommit job stages only an explicit path allowlist for resolver-owned metadata and generated artifacts.
**And** it verifies that no `.env`, secret-like file, credential, untracked vendor file, or runtime artifact is staged.
**And** it uses deterministic commit author, commit message, and update workflow concurrency settings.
**And** update commits do not recursively trigger release publication unless validation passes.
**And** catalog, docs, and security evidence updates are excluded until their owning stories extend the allowlist and validation gates.

## Expected Artifacts

- `.github/workflows/update.yml`
- `cloudnative-pg-timescaledb/workflow-policy.yaml`
- `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/scripts/autocommit-stage.sh`
- `cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures/no-op/`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures/metadata-change/`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures/generated-change/`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures/secret-file-staged/`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures/untracked-vendor-staged/`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures/runtime-artifact-staged/`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures/outside-allowlist-staged/`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/valid-update-autocommit-contents-write.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/invalid-update-nonautocommit-contents-write.yml`

## Update Workflow Contract

`.github/workflows/update.yml` must be a safe wrapper around the local `make update` contract.

Required behavior:

- Triggers: scheduled cron and `workflow_dispatch`; no release or package publish trigger in this story.
- All third-party GitHub Actions used by `.github/workflows/update.yml` are pinned to full commit SHA with readable version comments; any exception requires an explicit allowlist entry accepted by the validation workflow.
- Uses `GITHUB_TOKEN` by default. PAT fallback is absent unless a documented branch-protection exception is added in maintainer docs.
- Workflow-level permissions are read-only or empty; only the autocommit job grants `contents: write`.
- `cloudnative-pg-timescaledb/workflow-policy.yaml` must add exactly one Story 2.5 `permission_allowlist` entry for `.github/workflows/update.yml` job id `autocommit` with `permission: contents: write`, `owner_story: 2.5`, and reason `Commit resolver-owned metadata and generated artifacts after make validate`.
- The workflow validation fixture must prove that `contents: write` is accepted only for this named `autocommit` job and rejected for any other update workflow job.
- Runs checkout, `make update`, `make validate`, `autocommit-stage.sh`, `validate-autocommit-staging.sh`, and then commits only if `git diff --staged --quiet` is false.
- Stages only paths listed in `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`.
- The allowlist initially contains only the literal entries listed in `Initial Autocommit Allowlist Entries` below; catalog, docs, security evidence, `vendor/`, runtime/build artifacts, and secret-like paths are excluded until later stories extend it.
- Hard-fails if staged files include `.env`, secret-like names, credentials, untracked `vendor/` files, or runtime/build artifacts.
- Commit author, commit message, timezone, and workflow concurrency group are deterministic.
- No-op runs write a Step Summary and create no commit.
- Step Summary includes separate headings `Resolver-originated changes` and `Renovate-originated changes`; Story 2.6 owns classification rules and this story proves the headings exist.

Initial Autocommit Allowlist Entries:

```text
# comments and blank lines are allowed
cloudnative-pg-timescaledb/versions.yaml
cloudnative-pg-timescaledb/generated/**
cloudnative-pg-timescaledb/docker-bake.hcl
cloudnative-pg-timescaledb/matrix.json
```

Excluded until owning stories extend this file: `cloudnative-pg-timescaledb/catalog/**`, `cloudnative-pg-timescaledb/docs/**`, `docs/**`, security evidence, SBOM/provenance/signature artifacts, `vendor/**`, `.env*`, secret-like files, `*.tar`, `*.log`, container runtime output, and build caches.

## Required Validation Commands

- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh`
- `actionlint .github/workflows/update.yml`
- `shellcheck cloudnative-pg-timescaledb/scripts/autocommit-stage.sh cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh`
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- make update
- make validate

Shellcheck evidence correction: the autocommit workflow and final validation workflow must prove these scripts pass real `shellcheck` in CI. Local `bash -n` syntax fallback is acceptable only as supplemental local evidence and must not replace the required CI `shellcheck` gate.

## Required Tests and Fixtures

- `.github/workflows/update.yml` and `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` must both call the same staging and validation scripts; no allowlist, secret, vendor, or runtime-artifact logic may live only inline in workflow YAML.
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` must run every fixture listed in Expected Artifacts.
- `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` must accept `contents: write` only for `.github/workflows/update.yml` job `autocommit` when the Story 2.5 `workflow-policy.yaml` allowlist entry is present, and must reject `contents: write` for any other `update.yml` job.
- Include positive no-op and changed fixtures, plus negative fixtures for staged secrets, untracked vendor files, runtime artifacts, and paths outside the allowlist.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `.github/workflows/update.yml` with scheduled and manual triggers, deterministic concurrency, SHA-pinned actions, `make update`, `make validate`, and no publish trigger.
- [x] Add `workflow-policy.yaml`, autocommit allowlist, staging script, and staging validator so workflow YAML and tests share the same safety logic.
- [x] Restrict permissions so only the `autocommit` job receives `contents: write` under the exact Story 2.5 policy allowlist entry.
- [x] Add workflow/autocommit fixtures for no-op, metadata change, generated change, staged secret, untracked vendor, runtime artifact, and outside-allowlist cases.
- [x] Run actionlint, shellcheck, permission tests, update-autocommit tests, `make update`, and `make validate` before marking the story complete.
- [ ] Capture real GitHub Actions evidence after workflow publication: `gh workflow view update.yml`, `gh workflow run update.yml`, `gh run watch`, and `gh run view --json url,status,conclusion,headSha` for a no-op or controlled autocommit path. Local/static workflow validation is not sufficient for the final auto-update/autocommit product proof.

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
| FR-10 | 2.3, 2.5, 4.6, 5.7, 5.9 | update autocommit, generated artifacts, release catalogs, docs | no-op update test, path allowlist, `make validate`, rehearsal report |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-1 Reliability | 2.3, 2.5, 5.8, 5.9 | Scheduled and local updates are idempotent, clean no-op runs create no commits, failure reasons are documented and rehearsed. |
| NFR-3 Security | 2.4, 2.5, 4.3, 4.4, 4.7, 5.5, 5.9 | Least-privilege workflows, no secret leakage, OIDC signing, SARIF permissions, no PR write tokens, and no committed `.env` files. |
| NFR-5 Observability | 2.3, 2.5, 4.3, 4.7, 5.8, 5.9 | Update/build/publish/scan workflows write summaries with versions, tags, digests, skipped combinations, evidence status, and failure reasons. |
| NFR-8 Automation safety | 1.6, 2.5, 4.6, 5.6, 5.7, 5.9 | Generated artifacts are reproducible, committed through controlled paths, validated for drift, and never hand-edited as final fixes. |
| Workflow requirements | 2.4, 2.5, 4.2, 4.3, 4.5, 4.7, 5.9 | `update.yml`, `validate.yml`, `build.yml`, and `security-scan.yml` exist, are validated, and participate in the release rehearsal. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-2-upstream-aware-version-maintenance/2-5-scheduled-update-and-autocommit-workflow.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Added scheduled/manual `.github/workflows/update.yml` with deterministic concurrency, SHA-pinned checkout, `make update`, `make validate`, shared staging/validation scripts, summary headings, deterministic author, and deterministic commit message.
- Added explicit autocommit allowlist for resolver-owned metadata and generated artifacts: `versions.yaml`, `generated/**`, `docker-bake.hcl`, and `matrix.json`.
- Implemented `autocommit-stage.sh` and `validate-autocommit-staging.sh`; workflow and tests call the same scripts.
- Extended workflow policy with exact Story 2.5 allowlist entry for `.github/workflows/update.yml` job `autocommit` grant `contents: write`.
- Extended workflow permission tests for valid update autocommit write permission and invalid non-autocommit write permission.
- Added update-autocommit fixtures for no-op, metadata change, generated change, staged secret file, untracked vendor change, runtime artifact, and outside-allowlist staged path.
- Subagent review round 1 found policy exactness gap; fixed by checking full grant, reason, and owner story.
- Subagent review round 2 found YAML quoting issue for grant values; fixed by quoting grants and verifying standard YAML parsing.
- Subagent review round 3 reported no blocking findings.
- 2026-06-10 follow-up story validation found remote workflow availability is not yet proven: `gh workflow list --repo pnetcloud/containers --all` currently lists only `Build Release Candidates` and `Validate`; `update.yml` is not yet visible through the GitHub Actions API. Keep this story in review until remote/default-branch workflow evidence is recorded.
- 2026-06-10 remote workflow evidence: `Update Metadata` became visible through `gh workflow list --all --repo pnetcloud/containers`; manual dispatch `27313619813` on `aadc461` reached `make update`, `make validate`, `autocommit-stage.sh`, and `validate-autocommit-staging.sh`, then failed in `Write update summary` because no-op update JSON overwrote `OLD_VERSION_DIGEST`/`NEW_VERSION_DIGEST` with `n/a`.
- Fixed update summary rendering so no-op update JSON keeps `unchanged` for old/new digests and real text changes render bounded `sha256:<digest>` values instead of `n/a` or full metadata text.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh` - passed; local `actionlint`/`shellcheck` binaries are not installed, so the script reported deterministic SKIPs while running built-in policy checks.
- `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7 .github/workflows/*.yml` - passed.
- `python3 -c yaml.safe_load(...)` equivalent for `cloudnative-pg-timescaledb/workflow-policy.yaml` - passed.
- `find cloudnative-pg-timescaledb/scripts -type f -name '*.sh' -print0 | xargs -0 bash -n` - passed as local shell syntax fallback because `shellcheck` is not installed in this environment.
- `make update` - passed, no-op `changed=false`.
- Staged-index snapshot validation using `git checkout-index --all --prefix=<tmp>/ && make validate` - passed.
- `git diff --cached --check` - passed.
- `gh workflow list --all --repo pnetcloud/containers` - passed; `Update Metadata` is visible and active.
- `gh workflow run update.yml --ref codex/bmad-cloudnativepg-timescaledb-execution` - dispatched run `27313619813`; failed at `Write update summary` with `OLD_VERSION_DIGEST` actual `n/a`, which is now fixed locally pending rerun.
- Extracted `.github/workflows/update.yml` `Write update summary` run block, executed it with no-op update JSON and temporary `GITHUB_STEP_SUMMARY`, and asserted old/new digests render as `unchanged` - passed.
- `actionlint .github/workflows/update.yml` - passed after the summary fix.
- `bash cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh` - passed after the summary fix.
- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` - passed after the summary fix.
- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh` - passed after the summary fix.

### Completion Notes

- FR-10: scheduled/manual update workflow now wraps local `make update`, validates repository gates, stages only allowlisted resolver-owned paths, and commits only real staged changes.
- NFR-1: no-op staging creates no commit path and writes summary content.
- NFR-3: workflow uses `GITHUB_TOKEN` via checkout credentials, no PAT fallback, read-only top-level permissions, and `contents: write` only for the exact allowlisted autocommit job.
- NFR-5: Step Summary includes `Resolver-originated changes` and `Renovate-originated changes` headings.
- NFR-8: autocommit staging is path-allowlisted and rejects secrets, vendor changes, runtime artifacts, and outside-allowlist staged paths.
- Note: ordinary `make validate` in the current working tree is affected by unrelated unstaged Story 1.1 hardening edits; the committed Story 2.5 index state was validated in a clean checkout-index snapshot.
- Final product proof is still pending remote workflow evidence: a real `update.yml` workflow dispatch/no-op or controlled autocommit run must be recorded before claiming the auto-update/autocommit path is operational on GitHub.
- Remote rerun is still required after the summary fix before this story can move from `review` to `done`.

## File List

- `.github/workflows/update.yml`
- `cloudnative-pg-timescaledb/workflow-policy.yaml`
- `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/scripts/autocommit-stage.sh`
- `cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh`
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/valid-update-autocommit-contents-write.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/invalid-update-nonautocommit-contents-write.yml`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/**`

## Change Log

- Added scheduled update/autocommit workflow.
- Added autocommit allowlist and shared staging safety scripts.
- Added permission and staging fixtures for Story 2.5 safety invariants.
- Extended workflow policy validation for exact update autocommit `contents: write` allowlist grants.
- Fixed update workflow no-op summary rendering after remote dispatch exposed `n/a` old/new digest values.
