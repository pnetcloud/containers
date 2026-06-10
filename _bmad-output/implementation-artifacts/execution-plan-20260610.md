---
title: Lean Execution Plan
date: 2026-06-10
scope: CloudNativePG TimescaleDB image automation implementation
status: updated
---

# Lean Execution Plan

## Objective

Finish the current BMAD implementation goal with less loop overhead while preserving the main quality bar: GitHub Actions must pass and the repository must prove working CloudNativePG TimescaleDB images, release rehearsal, and publication automation.

## Current Ground Truth

- Story files already exist for all 35 stories under `_bmad-output/implementation-artifacts/stories/`.
- The story validation review already captured the user constraints and does not need to be rerun in full for every small CI fix.
- Latest pushed `main` evidence is commit `73b793b14c16f07d391eb05f62c235d7381b8464`.
- `Validate` passed on GitHub Actions for `73b793b14c16f07d391eb05f62c235d7381b8464`.
- `Build Release Candidates` passed on GitHub Actions for `73b793b14c16f07d391eb05f62c235d7381b8464` after SARIF upload hardening.
- `Release Rehearsal` passed on GitHub Actions for commit `1edcbdec254efede25a122897d14f85a33a2fb69`, which is on the current commit line.
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
- Both release workflows are green on the same commit.
- A change touches shared generation, matrix, tag policy, or release evidence contracts.
- A remote workflow succeeds but the evidence does not prove the story acceptance criteria.

## Subagent Policy

Use subagents only for bounded review tasks where independence adds value:

- Review a specific story against a specific implementation diff.
- Review a CI failure log and propose a minimal fix.
- Review final evidence against Story 5.9.

Do not use subagents for every shell edit, every commit, or every rerun. That creates redundant loops without improving confidence.

## Current Execution Order

### 0. Completed Remote Blockers

- `release-rehearsal.yml` dry-run workflow now passes and uploads its report.
- `Validate` now passes on latest `main`.
- `Build Release Candidates` now passes on latest `main`, including candidate builds, smoke checks, vulnerability scans, SARIF upload jobs, release evidence, tag validation, and publish rehearsal jobs.

### 1. Update Workflow Proof

Goal: prove scheduled/manual update automation and controlled autocommit behavior from the real GitHub Actions workflow.

Minimal checks before remote dispatch:

- Inspect `.github/workflows/update.yml` and its story tests.
- Run only update/autocommit workflow tests if implementation changes are required.

Remote check:

- Dispatch `update.yml` in a no-op or controlled dry-run/autocommit-safe mode.
- Record URL, head SHA, status, conclusion, and whether it made no commit or made only allowlisted generated-file changes.

Exit criteria:

- `update.yml` is visible in GitHub Actions and has at least one successful controlled run.
- Any autocommit path is constrained by the repository allowlist and does not include secrets, vendor input, or unrelated files.

### 2. Release Rehearsal Blocker

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

### 3. SARIF Upload Blocker

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

### 4. Generator/Matrix Dirty Worktree Line

Goal: decide whether the current generator/matrix local changes belong to Story 1.5/1.6 or should be parked.

Rule:

- Do not mix these changes into release-rehearsal or SARIF commits.
- After the two CI blockers are fixed, inspect this diff separately and either commit it as the next story-scoped change or leave it unstaged.

Minimal checks when that line resumes:

- Generator tests only.
- Generated drift tests only.
- Matrix validation tests only.

### 5. Final Integration Proof

Run this only after the two remote blockers are fixed on the same commit line.

Required checks:

- One clean full validation pass from a controlled tree.
- One focused BMAD/code-review pass against release workflows and Story 5.9 evidence.
- Final evidence update with GitHub Actions URLs, status, conclusion, and head SHA.

Exit criteria:

- `Validate` is green.
- `Build Release Candidates` is green.
- `Release Rehearsal` is green.
- The evidence proves real/staging image release behavior, `latest=18-trixie`, Debian `trixie`/`bookworm` only, no Alpine, and Barman Cloud Plugin boundary.

## What Is Explicitly Deferred

- Artifact Hub integration.
- Alpine support.
- Bullseye support.
- Reworking already-created story files unless an implementation contradiction is found.
- Full story revalidation after every small CI fix.
