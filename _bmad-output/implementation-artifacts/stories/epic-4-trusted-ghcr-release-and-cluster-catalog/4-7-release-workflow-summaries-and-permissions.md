---
storyId: 4.7
storyKey: 4-7-release-workflow-summaries-and-permissions
epic: 4
title: 'Release Workflow Summaries and Permissions'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 4.7: Release Workflow Summaries and Permissions

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 4.1-4.6 in this epic may be assumed complete.

## Out of Scope

- Producing build, scan, evidence, publish, and catalog artifacts; owned by Stories 4.2-4.6.
- Public verification docs; owned by Story 5.5.
- Final release rehearsal; owned by Story 5.9.

## Source Story

### Story 4.7: Release Workflow Summaries and Permissions

As a maintainer,
I want release workflows to be inspectable and least-privileged,
So that public users can understand what happened without reading raw logs.

**Acceptance Criteria:**

**Given** build, smoke, vulnerability, provenance, signing, publish, catalog, and scan jobs run
**When** each workflow completes
**Then** it writes a concise GitHub Step Summary with resolved versions, tags, digests, skipped combinations, scan outcomes, signature status, SBOM/provenance status, and failure reasons.
**And** default workflow permissions are read-only or empty.
**And** `packages: write` is granted only to named candidate-push and final publish jobs.
**And** `id-token: write` is granted only to signing/provenance jobs.
**And** `security-events: write` is granted only to jobs uploading SARIF.
**And** validation fails on `write-all`, broad top-level write permissions, pull request write tokens, and any job granting `contents`, `packages`, `id-token`, or `security-events` outside the named allowed jobs.
**And** release-sensitive third-party Actions are pinned by full commit SHA with readable version comments.
**And** pull request workflows do not receive broad write tokens.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/write-step-summary.sh`
- workflow Step Summary templates for update, build, smoke, vulnerability/scan, SBOM/evidence, provenance, signing, publish, and catalog jobs
- workflow permission validation checks
- SHA pinning validation fixtures
- `cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/summaries/fixtures/valid-summary.md`
- `cloudnative-pg-timescaledb/tests/workflows/summaries/fixtures/missing-digest.md`
- `cloudnative-pg-timescaledb/tests/workflows/summaries/fixtures/missing-failure-reason.md`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/valid-release-allowlisted-permissions.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/write-all.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/broad-top-level-write.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/pr-write-token.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/disallowed-contents-write-job.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/disallowed-packages-write-job.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/disallowed-id-token-write-job.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/disallowed-security-events-write-job.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/valid-pinned-action.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/unpinned-release-action.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/action-short-sha.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/action-missing-version-comment.yml`

## Summary and Permission Contract

- Step summaries must include resolved versions, final and candidate tags, candidate digest, published digest, platform digests, skipped combinations with reasons, scan result, SBOM status, provenance status, signature status, catalog status, and failure reason when failed.
- Default workflow permissions are `{}` or read-only.
- Reuse the Story 2.4 permission allowlist categories: `contents: write` only update/autocommit/catalog commit jobs; `packages: write` only named candidate-push and final publish jobs; `id-token: write` only signing/provenance jobs; `security-events: write` only SARIF upload jobs.
- Action pinning validation scope is every third-party `uses:` entry in `.github/workflows/update.yml`, `.github/workflows/validate.yml`, `.github/workflows/build.yml`, and `.github/workflows/security-scan.yml`, except explicit Story 2.4 policy exceptions. Each scoped action must use a full 40-character lowercase hexadecimal commit SHA and a readable adjacent version comment in the form `# <action-name> <upstream-version-or-date>`.
- Pull request workflows must not receive broad write tokens.
- Validation fails if required summary fields are missing for a completed job or if a failed job lacks a failure reason.

## Step Summary Coverage Matrix

| Workflow | Job ID | Required Summary Fields | Allowed `n/a` Fields | Failure Fields | Template Path |
| --- | --- | --- | --- | --- | --- |
| `.github/workflows/update.yml` | `update-metadata` | upstream component, old version/digest, new version/digest, changed files, no-op status | candidate digest, published digest, scan result, SBOM/provenance/signature | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/update.md` |
| `.github/workflows/build.yml` | `build` | PostgreSQL major, PostgreSQL version, Debian variant, platforms, Bake target, candidate tag, candidate digest, platform digests | published digest, scan result, SBOM/provenance/signature | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/build.md` |
| `.github/workflows/build.yml` | `smoke` | PostgreSQL major, Debian variant, platform, candidate digest, container smoke result, SQL smoke result, skipped combinations with reasons | published digest, SBOM/provenance/signature | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/smoke.md` |
| `.github/workflows/security-scan.yml` | `vulnerability` | image reference, candidate digest, scanner, vulnerability threshold, scan result, report path | published digest, SBOM/provenance/signature | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/vulnerability.md` |
| `.github/workflows/security-scan.yml` | `scan-sarif` | image reference, candidate digest, SARIF path, upload status, scan result | published digest, SBOM/provenance/signature | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/scan-sarif.md` |
| `.github/workflows/build.yml` | `sbom` | image reference, candidate digest, index digest, platform digests, SBOM ref/status | published digest, scan result when handled by separate workflow, provenance/signature if not produced in this job | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/sbom.md` |
| `.github/workflows/build.yml` | `evidence` | candidate digest, index digest, platform digests, SBOM ref/status, provenance ref/status, evidence artifact path | published digest, signature if handled by separate job | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/evidence.md` |
| `.github/workflows/build.yml` | `provenance` | image reference, candidate digest, index digest, platform digests, provenance ref/status | published digest, scan result if separate, signature if separate | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/provenance.md` |
| `.github/workflows/build.yml` | `signing` | image reference, candidate digest, index digest, platform digests, signature ref/status, OIDC issuer, OIDC identity | published digest | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/signing.md` |
| `.github/workflows/build.yml` | `publish` | final tags, `latest` target, candidate digest, published digest, platform digests, scan result, SBOM/provenance/signature status | skipped combinations when none skipped | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/publish.md` |
| `.github/workflows/update.yml` | `catalog-autocommit` | catalog paths, generated catalog digests, changed files, no-op status, commit SHA when committed | candidate digest if no release candidate changed | failure reason, remediation command | `cloudnative-pg-timescaledb/templates/summaries/catalog.md` |

If a future implementation intentionally merges `vulnerability` with `scan-sarif`, or `sbom`/`provenance` with `evidence`, it must keep the exact job ID documented in the workflow and validate the union of required fields for the merged rows.

## Permission Allowlist Matrix

| Workflow | Job ID | Permission | Owner Story | Reason |
| --- | --- | --- | --- | --- |
| `.github/workflows/update.yml` | `autocommit` | `contents: write` | 2.5 | Commit deterministic generated update files through the configured allowlist. |
| `.github/workflows/update.yml` | `catalog-autocommit` | `contents: write` | 4.6 | Commit generated catalog files through `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`. |
| `.github/workflows/build.yml` | `candidate-push` | `packages: write` | 4.2 | Push immutable GHCR release candidate references or digest-addressed candidate tags before scan/evidence gates. |
| `.github/workflows/build.yml` | `publish` | `packages: write` | 4.5 | Push release-complete images and final tags to GHCR. |
| `.github/workflows/build.yml` | `provenance` | `id-token: write` | 4.4 | Generate keyless provenance attestations through GitHub OIDC. |
| `.github/workflows/build.yml` | `signing` | `id-token: write` | 4.4 | Sign immutable image digests through keyless cosign and GitHub OIDC. |
| `.github/workflows/security-scan.yml` | `scan-sarif` | `security-events: write` | 4.3 | Upload SARIF vulnerability results. |

Permissions validation must reject every `write` grant not present in this matrix, including the same permissions on any other workflow or job ID.

## Required Validation Commands

- make validate
- `bash cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh`
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `actionlint .github/workflows/update.yml .github/workflows/validate.yml .github/workflows/build.yml .github/workflows/security-scan.yml`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh` and `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` must run the fixtures listed in Expected Artifacts.
- `cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh` must inspect the real `.github/workflows/update.yml`, `.github/workflows/build.yml`, and `.github/workflows/security-scan.yml` and verify every row in the Step Summary Coverage Matrix writes `$GITHUB_STEP_SUMMARY` through the listed template/helper on success and failure using `if: always()` or an equivalent always-run summary step.
- `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` must inspect the real `.github/workflows/update.yml`, `.github/workflows/validate.yml`, `.github/workflows/build.yml`, and `.github/workflows/security-scan.yml` and verify real workflow permissions and action pins match the Permission Allowlist Matrix and action pinning scope.
- `make validate` must invoke the summary and permission/pinning validators so real workflow regressions cannot pass by fixture-only validation.
- `valid-release-allowlisted-permissions.yml` must prove allowed named jobs pass with the exact workflow/job/permission triples in the Permission Allowlist Matrix, including `.github/workflows/update.yml` / `autocommit` / `contents: write` from Story 2.5.
- Include negative fixtures for missing digest, missing failure reason, `write-all`, broad top-level write permissions, PR write tokens, disallowed `contents: write`, disallowed `packages: write`, disallowed `id-token: write`, disallowed `security-events: write`, unpinned action tag/ref, short SHA, and missing version comment.
- Permissions validation must fail any job granting `contents`, `packages`, `id-token`, or `security-events` outside the exact workflow/job/permission triples from the Permission Allowlist Matrix.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `cloudnative-pg-timescaledb/scripts/write-step-summary.sh` and summary templates for update, build, smoke, vulnerability/SARIF, SBOM/evidence, provenance, signing, publish, and catalog jobs.
- [x] Wire workflow jobs to write `$GITHUB_STEP_SUMMARY` with resolved versions, candidate/final tags, candidate/published/platform digests, skipped combinations with reasons, scan outcomes, SBOM/provenance/signature status, catalog status, and failure reason when failed, using the listed template/helper and always-run summary behavior.
- [x] Implement workflow permission validation using the exact Permission Allowlist Matrix and reject `write-all`, broad top-level write permissions, PR write tokens, and unallowlisted `contents`, `packages`, `id-token`, or `security-events` writes.
- [x] Implement action pinning validation for third-party `uses:` entries in update, validate, build, and security-scan workflows, requiring full 40-character lowercase SHA pins and readable version comments unless an explicit Story 2.4 policy exception applies.
- [x] Add summary fixtures and `cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh` for required fields and failure reasons.
- [x] Add permission fixtures and `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` for valid allowlisted writes and each disallowed write class.
- [x] Run `make validate`, `bash cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh`, `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`, and `actionlint .github/workflows/update.yml .github/workflows/validate.yml .github/workflows/build.yml .github/workflows/security-scan.yml`.

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
| FR-3 | 1.4, 4.5, 4.7, 5.2, 5.9 | tag library, publish workflow, docs examples | `validate-tags.sh`, `make validate`, release rehearsal |
| FR-15 | 1.4, 4.5, 4.7, 5.2, 5.9 | tag policy, GHCR publish job, image tag docs | `validate-tags.sh`, publish rehearsal, docs validation |
| FR-17 | 4.4, 4.7, 5.5, 5.9 | SBOM, provenance, release evidence docs | evidence verification, release rehearsal |
| FR-18 | 4.4, 4.7, 5.5, 5.9 | OIDC signatures, digest verification docs | signature verification, release rehearsal |
| FR-19 | 4.3, 4.7, 5.5, 5.8, 5.9 | security scan workflow, SARIF, vulnerability policy | `security-scan.yml`, SARIF upload, release rehearsal |
| FR-20 | 2.4, 4.7, 5.7, 5.9 | validate workflow, actionlint, shellcheck, docs validation | `.github/workflows/validate.yml`, `make validate`, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-3 Security | 2.4, 2.5, 4.3, 4.4, 4.7, 5.5, 5.9 | Least-privilege workflows, no secret leakage, OIDC signing, SARIF permissions, no PR write tokens, and no committed `.env` files. |
| NFR-5 Observability | 2.3, 2.5, 4.3, 4.7, 5.8, 5.9 | Update/build/publish/scan workflows write summaries with versions, tags, digests, skipped combinations, evidence status, and failure reasons. |
| Workflow requirements | 2.4, 2.5, 4.2, 4.3, 4.5, 4.7, 5.9 | `update.yml`, `validate.yml`, `build.yml`, and `security-scan.yml` exist, are validated, and participate in the release rehearsal. |
| Supply-chain release gates | 4.3, 4.4, 4.5, 4.7, 5.5, 5.9 | Vulnerability scan, SBOM, provenance, signing, permissions, and summaries block release when missing or failing. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-4-trusted-ghcr-release-and-cluster-catalog/4-7-release-workflow-summaries-and-permissions.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Added shared Step Summary renderer with template substitution and success/failure field enforcement.
- Wired update, catalog, candidate build/smoke, release evidence, SBOM, provenance, signing, publish, vulnerability scan, and SARIF upload summaries through shared templates.
- Strengthened workflow validator to parse both `.yml` and `.yaml`, use YAML for permissions/triggers, require explicit top-level permissions, reject `pull_request_target` write grants, and require actual version comments for pinned actions.
- Addressed review findings: SARIF upload job now has checkout and scan-summary artifact data; vulnerability summaries account for failed scan gate output; catalog changed files are captured before commit; skipped combinations come from matrix skipped rows; summary calls enforce required success fields and failure reasons.

### Completion Notes

- `make validate` now invokes workflow summary tests in addition to permission/pinning checks.
- Summary templates cover all Story 4.7 categories and the tests inspect real workflows for helper/template usage and always-run behavior.
- Permission fixtures cover write-all, broad top-level writes, `.yaml` workflows, flow-map/commented/quoted write permissions, PR scalar/list/target triggers, disallowed release-sensitive writes, unpinned/short-SHA actions, missing version comments, and missing top-level permissions.

### File List

- `.github/workflows/build.yml`
- `.github/workflows/security-scan.yml`
- `.github/workflows/update.yml`
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/scripts/write-step-summary.sh`
- `cloudnative-pg-timescaledb/templates/summaries/*.md`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/*.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/write-all-yaml-extension.yaml`
- `cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/summaries/fixtures/*.md`

### Validation

- `bash -n cloudnative-pg-timescaledb/scripts/validate-workflows.sh cloudnative-pg-timescaledb/scripts/write-step-summary.sh cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh`
- `bash cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh`
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `/tmp/codex-go-bin/actionlint .github/workflows/update.yml .github/workflows/validate.yml .github/workflows/build.yml .github/workflows/security-scan.yml`
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`
- `bash cloudnative-pg-timescaledb/tests/security-scan/run.sh`
- `bash cloudnative-pg-timescaledb/tests/release-evidence/run.sh`
- `bash cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh`
- Staged snapshot: `git checkout-index --all --prefix="$tmpdir/" && (cd "$tmpdir" && make validate)` passed.

### Change Log

- 2026-06-10: Implemented release workflow summaries, stricter permission/pinning validation, fixtures, review fixes, and validation wiring for Story 4.7.
