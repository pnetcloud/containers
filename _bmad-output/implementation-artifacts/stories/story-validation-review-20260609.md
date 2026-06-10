---
title: Story Validation Review
date: 2026-06-09
scope: all BMAD story files
status: updated-2026-06-10
---

# Story Validation Review

## User Constraints Checked

- Public repository for personal/public use.
- Image family is CloudNativePG PostgreSQL with TimescaleDB, TimescaleDB Toolkit, pgvector, and PGAudit.
- PostgreSQL lines are `17`, `18`, and experimental `19beta1`.
- Debian variants are `trixie` and `bookworm` only; no Alpine.
- Barman support is through the modern CloudNativePG Barman Cloud Plugin, not legacy in-image Barman tooling.
- `latest` points only to PostgreSQL `18` on `trixie`.
- Immutable tags include full versions, for example `18-pg18.4-ts2.27.2-20260609`.
- `vendor/` is reference material only and must not be a build context or runtime input.
- The final outcome must prove working GitHub Actions and working images, not only static fixtures.

## Review Results

### Epic 1

Subagent validation found one story-contract defect: Story 1.5 used an incomplete catalog example tag, `18-pg18.4-ts-00000000`.

Resolution: Story 1.5 now uses `18-pg18.4-ts2.27.2-20260609` in the catalog JSON contract example.

### Epic 2

Subagent validation found two gaps:

- `shellcheck` evidence was incomplete because previous local validation used `bash -n` fallback when `shellcheck` was unavailable.
- PostgreSQL `19beta1` package lookup was underspecified and could imply invalid package names ending in `19beta1`.

Resolution:

- Stories 2.4, 2.5, and 5.7 now state that real CI `shellcheck` is required; syntax-only fallback is supplemental local evidence only.
- Story 2.2 now defines `pg_package_major`: `17 -> 17`, `18 -> 18`, and experimental `19beta1 -> 19`. It requires negative fixture coverage for package names incorrectly ending in `19beta1`.

### Epic 3

Subagent validation confirmed the story contracts cover CNPG `standard-*` bases, extension install/validation, `vendor/` exclusion, and Barman plugin boundary.

Gap: Epic 3 records still show fixture/contract validation rather than production working images because production metadata rows were not yet publishable at that stage.

Resolution path: This is an execution gap, not a contradiction in Epic 3. Story 5.9 now requires final release rehearsal evidence for real build, container smoke, SQL smoke, vulnerability scan, SBOM, provenance, signature or signing dry-run, publish rehearsal, and catalog evidence for stable PostgreSQL `17` and `18` primary `trixie` entries.

### Epic 4

Subagent validation confirmed the constraints are correctly represented, including `latest=18-trixie`, full version tags, Debian scope, and no baked-in Barman.

Updated 2026-06-10: remote GitHub Actions evidence now proves `Validate` and `Build Release Candidates` succeeded for commit `74b4a07e8ccb5644f8ac4d5c6f4300fa7e191522`:

- `Validate`: `https://github.com/pnetcloud/containers/actions/runs/27265859709`, status `completed`, conclusion `success`.
- `Build Release Candidates`: `https://github.com/pnetcloud/containers/actions/runs/27265860054`, status `completed`, conclusion `success`.

Remaining proof gap: Stories 4.4, 4.5, and 4.6 are implementation-complete but still need real/staging release evidence before they can be treated as product release proof: actual cosign verification against a digest, staging/final publish metadata with promoted tags, and non-empty catalogs generated from real release metadata.

Follow-up validation on 2026-06-10 found a regression in the latest remote `Build Release Candidates` run for commit `c92c5d3`: all four PG17/PG18 `trixie`/`bookworm` candidate build and smoke jobs completed successfully, then the workflow failed because `security-scan.yml` attempted to upload a SARIF artifact that the scanner had not produced. Resolution in progress: Story 4.3 now requires explicit `scanner_failed` output, deterministic SARIF diagnostic evidence before artifact upload, fail-closed scan gate behavior, and no CodeQL SARIF upload when SARIF generation failed.

Updated 2026-06-10: remote GitHub Actions evidence now proves `Validate` and `Build Release Candidates` succeeded on latest `main` commit `73b793b14c16f07d391eb05f62c235d7381b8464` after SARIF upload hardening:

- `Validate`: `https://github.com/pnetcloud/containers/actions/runs/27294485168`, status `completed`, conclusion `success`.
- `Build Release Candidates`: `https://github.com/pnetcloud/containers/actions/runs/27294485301`, status `completed`, conclusion `success`.

Resolution: CodeQL SARIF upload is non-blocking and summarized from the upload step outcome, while vulnerability scanning remains fail-closed in the scan job. Candidate builds, smoke checks, vulnerability scans, SARIF upload jobs, release evidence, tag validation, and publish rehearsal jobs all completed successfully in the latest build run.

### Epic 5

Subagent validation found three final-proof gaps:

- Story 5.9 did not explicitly prove `vendor/` is excluded from build/runtime/release contexts.
- Story 5.9 did not include final release-rehearsal fixtures for Alpine, `bullseye`, and unsupported Debian variants.
- Story 5.9 used ambiguous `CI-safe equivalent` wording for GitHub Actions proof.

Resolution:

- Story 5.9 now requires release rehearsal checks and fixtures for `vendor/` build/runtime consumption.
- Story 5.9 now requires release rehearsal hard-fail fixtures for Alpine, `bullseye`, and unsupported Debian variants.
- Story 5.9 now requires actual `release-rehearsal.yml` `workflow_dispatch` evidence from the same repository workflow run, with URL, status, and successful conclusion.

Updated 2026-06-10: remote GitHub Actions evidence proves `release-rehearsal.yml` completed successfully on commit `1edcbdec254efede25a122897d14f85a33a2fb69`:

- `Release Rehearsal`: `https://github.com/pnetcloud/containers/actions/runs/27291928457`, status `completed`, conclusion `success`.

That run executed the dry-run/staging release rehearsal path, including build/smoke orchestration and upload of the generated rehearsal report.

## Next Execution Step

Use the lean execution plan in `_bmad-output/implementation-artifacts/execution-plan-20260610.md` for the active loop. The objective is unchanged, but the execution loop is now narrower: fix one remote blocker, run the smallest local test that proves that blocker, push, and dispatch only the affected workflow.

Current remote blocker status:

- `Release Rehearsal` dry-run workflow is green on the current commit line.
- `Validate` is green on latest `main`.
- `Build Release Candidates` is green on latest `main`, including candidate builds, smoke checks, vulnerability scans, SARIF upload jobs, release evidence, tag validation, and publish rehearsal jobs.

Do not close the final release proof until these external checks exist from the same repository and preferably the same commit line:

- `Validate` completed successfully.
- `Build Release Candidates` completed successfully after build, smoke, vulnerability scan, and artifact/evidence collection.
- `release-rehearsal.yml` completed successfully via `workflow_dispatch`, with URL, status, conclusion, and head SHA recorded.
- `update.yml` is visible in GitHub Actions API and validated by at least one real `workflow_dispatch` no-op or controlled autocommit run.
- GHCR/staging publish evidence proves final tags, `latest=18-trixie`, SBOM/provenance/signature verification, and non-empty trixie/bookworm catalogs for real manifest-list digests.
