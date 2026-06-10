---
title: Lean Execution Plan
date: 2026-06-10
scope: CloudNativePG TimescaleDB image automation implementation
status: reduced-loop-current
---

# Lean Execution Plan

## Objective

Finish the current BMAD implementation goal with less loop overhead while preserving the main quality bar: GitHub Actions must pass, GHCR images must be published and pullable, and the repository must retain digest-aware release metadata and catalogs generated from successful publication.

## Current Ground Truth

- Story files already exist for all 35 stories under `_bmad-output/implementation-artifacts/stories/`.
- The story validation review already captured the user constraints and does not need to be rerun in full for every small CI fix.
- Latest pushed `main` evidence is commit `574485e011d780ec2d9c257a9b338107c4d4f9f6`.
- `Validate` passed on GitHub Actions for `574485e011d780ec2d9c257a9b338107c4d4f9f6`.
- `Build Release Candidates` passed on GitHub Actions for `574485e011d780ec2d9c257a9b338107c4d4f9f6`, including build, smoke, security scan, release evidence, tag validation, final publish, and public anonymous pull verification.
- `Release Rehearsal` passed on GitHub Actions for commit `1edcbdec254efede25a122897d14f85a33a2fb69`, which is on the current commit line.
- `Update Metadata` passed on GitHub Actions for `574485e011d780ec2d9c257a9b338107c4d4f9f6`; resolver and catalog autocommit paths were no-op because no repository release metadata existed yet.
- GHCR already contains public tags, including `latest` and `18-pg18.4-ts2.27.2-20260609` pointing to the same digest, plus stable PG17/PG18 trixie/bookworm tags.
- Current remaining proof gap: `cloudnative-pg-timescaledb/release-metadata/*.json` is not committed to the repo, so the generated digest-aware catalogs remain empty skeletons.
- The local worktree contains unrelated generator/matrix changes, so commits must be narrowly staged.

## Reduced Loop Rules

Use targeted checks first. Run broad checks only at integration boundaries.

Do not rerun all BMAD validation, all stories, or full local validation after every small workflow edit. The normal inner loop is:

1. Identify one blocker.
2. Edit only files needed for that blocker.
3. Run syntax checks and the smallest relevant test script.
4. Commit only the relevant files.
5. Push and dispatch only the affected GitHub Actions workflow.
6. Record the CI URL and result.

Use full BMAD/code-review validation only when one of these gates is reached:

- A full epic boundary is completed.
- Release metadata persistence and catalog generation are proven on the same commit as a successful publish run.
- A change touches shared generation, matrix, tag policy, or release evidence contracts.
- A remote workflow succeeds but the evidence does not prove the story acceptance criteria.

For the current remaining work, the target validation loop is one implementation pass, one focused local test pass, one push, one `Validate` run, one `Build Release Candidates` run, and one verification that the build workflow created the expected autocommit. Do not run per-story subagent validation again unless a test or CI result contradicts story acceptance criteria.

## Subagent Policy

Use subagents only for bounded review tasks where independence adds value:

- Review a specific story against a specific implementation diff.
- Review a CI failure log and propose a minimal fix.
- Review final evidence against Story 5.9.

Do not use subagents for every shell edit, every commit, or every rerun. That creates redundant loops without improving confidence.

For this final phase, use at most one focused review pass after the release metadata autocommit implementation is locally validated. The review scope is limited to:

- workflow permission blast radius,
- autocommit allowlist/staging safety,
- recursion prevention,
- evidence that catalogs are generated from published digest metadata.

## Current Execution Order

### 0. Completed Remote Blockers

- `release-rehearsal.yml` dry-run workflow now passes and uploads its report.
- `Validate` now passes on latest `main`.
- `Build Release Candidates` now passes on latest `main`, including candidate builds, smoke checks, vulnerability scans, SARIF upload jobs, release evidence, tag validation, and publish rehearsal jobs.

### 1. Release Metadata Persistence and Catalog Autocommit

Goal: persist successful publish metadata from `.github/workflows/build.yml` into repository release metadata files, generate non-empty digest-aware catalogs, and autocommit only allowlisted release metadata/catalog paths.

Implementation slice:

- Add a post-publish job in `.github/workflows/build.yml` that needs `matrix` and `publish`.
- Run it only when publish is eligible: `workflow_dispatch`, `main`, or release tag refs.
- Grant only `contents: write` for this job; keep default workflow permission read-only.
- Download all `ghcr-release-metadata-*` artifacts from the publish matrix.
- Materialize them into `cloudnative-pg-timescaledb/release-metadata/*.json`.
- Run `generate-catalog.sh --release-metadata cloudnative-pg-timescaledb/release-metadata`.
- Validate `catalog-standard-trixie.yaml` and `catalog-standard-bookworm.yaml`.
- Stage only paths from `cloudnative-pg-timescaledb/config/release-metadata-autocommit-allowlist.txt`.
- Run `validate-autocommit-staging.sh` before commit.
- Commit with a recursion-safe message such as `chore(cnpg-timescaledb): update release metadata and catalogs`.
- No-op cleanly when downloaded metadata produces no diff.

Targeted local checks:

- `bash cloudnative-pg-timescaledb/tests/catalog/run.sh`
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh`
- `git diff --check -- .github/workflows/build.yml cloudnative-pg-timescaledb/workflow-policy.yaml cloudnative-pg-timescaledb/config/release-metadata-autocommit-allowlist.txt cloudnative-pg-timescaledb/tests/catalog/run.sh cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`

Exit criteria:

- `Validate` passes on the pushed commit.
- `Build Release Candidates` passes on the pushed commit.
- A follow-up bot commit appears only if release metadata/catalog files changed.
- The committed `release-metadata/*.json` files correspond to published GHCR digests.
- Both stable catalogs are non-empty and validate against current catalog rules.
- No vendor, secret, runtime artifact, or unrelated dirty generator/matrix file is staged or committed by the autocommit job.

Status: next.

### 2. Update Workflow Proof

Goal: keep scheduled/manual metadata resolver automation proven without treating its catalog no-op as a failure.

Current evidence:

- `Update Metadata` manual dispatch passed for `574485e011d780ec2d9c257a9b338107c4d4f9f6`.
- The resolver autocommit was no-op.
- The catalog autocommit was no-op because repository release metadata was absent.

Exit criteria:

- No further `update.yml` work is required until release metadata exists in the repo.
- After the build workflow persists release metadata, run `Update Metadata` only once if needed to prove scheduled/catalog regeneration remains no-op-safe.

Status: blocked by Step 1, not by workflow failure.

### 3. Release Rehearsal Blocker

Goal: make `release-rehearsal.yml` pass in dry-run mode from `main`.

Minimal local checks:

- `bash -n cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`
- `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`
- `git diff --check -- cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`

Commit scope:

- `cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`
- Any directly required release-rehearsal test fixture updates only if the test proves they are needed.

Remote check:

- Dispatch `release-rehearsal.yml` with `dry_run=true`, date `20260609`, and the staging namespace.
- Watch only that workflow until success or the next concrete failure.

Exit criteria:

- GitHub Actions `Release Rehearsal` concludes `success` on the pushed commit.
- The run URL, head SHA, status, and conclusion are recorded in the final implementation notes.

Status: completed on commit `1edcbdec254efede25a122897d14f85a33a2fb69`.

### 4. SARIF Upload Blocker

Goal: make `Build Release Candidates` pass end-to-end when vulnerability scanning succeeds, without making CodeQL SARIF upload an image release gate.

Preferred direction:

- Keep vulnerability scan failures fail-closed.
- Keep SARIF and scan summaries as artifacts/evidence.
- Make CodeQL SARIF upload non-blocking or conditional, because the prior failure happened after successful build, smoke, and scan results.

Minimal local checks:

- `bash -n .github/workflows/security-scan.yml` is not useful because YAML is not shell; instead use the existing workflow/security-scan test script if present.
- `bash cloudnative-pg-timescaledb/tests/security-scan/run.sh` if the change touches scan workflow behavior.
- `git diff --check -- .github/workflows/security-scan.yml cloudnative-pg-timescaledb/tests/security-scan/run.sh`

Remote check:

- Dispatch or rerun `Build Release Candidates` only after the targeted change is pushed.

Exit criteria:

- Candidate image build jobs pass.
- Smoke jobs pass.
- Vulnerability gate remains enforced.
- CodeQL upload failure cannot fail the candidate workflow by itself.

Status: completed on commit `73b793b14c16f07d391eb05f62c235d7381b8464`.

### 5. Generator/Matrix Dirty Worktree Line

Goal: decide whether the current generator/matrix local changes belong to Story 1.5/1.6 or should be parked.

Rule:

- Do not mix these changes into release-rehearsal or SARIF commits.
- After the two CI blockers are fixed, inspect this diff separately and either commit it as the next story-scoped change or leave it unstaged.

Minimal checks when that line resumes:

- Generator tests only.
- Generated drift tests only.
- Matrix validation tests only.

### 6. Final Integration Proof

Run this only after release metadata persistence is proven on the same commit line as a successful publish run.

Required checks:

- One clean full validation pass from a controlled tree or a green `Validate` run on the pushed commit.
- One focused review pass against release workflows, autocommit safety, and Story 5.9 evidence.
- Final evidence update with GitHub Actions URLs, status, conclusion, head SHA, generated bot commit SHA if present, and GHCR digest/tag checks.

Exit criteria:

- `Validate` is green.
- `Build Release Candidates` is green.
- `Release Rehearsal` is green.
- Repository release metadata exists for published stable rows.
- Stable catalogs are non-empty and digest-aware.
- The evidence proves real/staging image release behavior, `latest=18-trixie`, Debian `trixie`/`bookworm` only, no Alpine, and Barman Cloud Plugin boundary.

## What Is Explicitly Deferred

- Artifact Hub integration.
- Alpine support.
- Bullseye support.
- Reworking already-created story files unless an implementation contradiction is found.
- Full story revalidation after every small CI fix.
