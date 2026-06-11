---
title: Lean Execution Plan
date: 2026-06-10
scope: CloudNativePG TimescaleDB image automation implementation
status: reduced-loop-active
---

# Lean Execution Plan

## Objective

Finish the current BMAD implementation goal without unnecessary loop overhead while preserving the non-negotiable quality bar: GitHub Actions must pass, GHCR images must be published and anonymously pullable, generated release metadata must be committed, and digest-aware ClusterImageCatalog manifests must reflect published image digests.

This plan intentionally treats BMAD as a traceability and decision framework. It does not require a full BMAD loop, per-story subagent pass, or broad validation run for every small correction. From this point forward, implementation speed is protected by using evidence gates instead of repeated planning/review loops.

## Current Ground Truth

- Story files exist for all 35 stories under `_bmad-output/implementation-artifacts/stories/`; they do not need to be regenerated unless a real requirement contradiction is found.
- The story validation review exists at `_bmad-output/implementation-artifacts/stories/story-validation-review-20260609.md`; it remains the baseline and should not be rerun after every implementation edit.
- Local branch `codex/bmad-cloudnativepg-timescaledb-execution` contains the release automation baseline plus the later generator/matrix/docs contract hardening commits.
- Commit `8ae4462` added release metadata and catalog autocommit automation.
- Commit `6d60a05` is the bot autocommit that added `cloudnative-pg-timescaledb/release-metadata/*.json` and updated digest-aware catalogs.
- `Validate` passed on GitHub Actions run `27298379342` for commit `8ae446225c72fe26a87f8172f1d6da014668005b`.
- `Build Release Candidates` passed on GitHub Actions run `27298379390` for commit `8ae446225c72fe26a87f8172f1d6da014668005b`; the run included candidate builds, smoke checks, vulnerability scans, SARIF upload handling, release evidence, tag validation, final publish, public anonymous pull verification, and the release metadata/catalog autocommit job.
- The bot commit produced four release metadata JSON files and non-empty `catalog-standard-trixie.yaml` / `catalog-standard-bookworm.yaml` files.
- Verified release tags include `latest`, `18`, and `18-pg18.4-ts2.27.2-20260609` pointing to the same PG18 trixie digest.
- The generator/matrix/docs contract slice has remote green evidence on the feature branch.
- Commit `6dc1309` reset the release rehearsal checkout after the update gate and has successful remote evidence:
  - `Validate`: `https://github.com/pnetcloud/containers/actions/runs/27304013560`, success.
  - `Build Release Candidates`: `https://github.com/pnetcloud/containers/actions/runs/27304013565`, success.
  - `Release Rehearsal`: `https://github.com/pnetcloud/containers/actions/runs/27304019882`, success.
- Current local worktree contains a focused packagecloud/PG19 package ABI follow-up. It should be checked with targeted local tests before any commit and must stay separate from release workflow behavior.

## Reduced Loop Rules

Use small verification loops for implementation slices and reserve broad BMAD loops for integration gates.

Normal inner loop:

1. Pick exactly one implementation slice or one CI blocker.
2. Edit only files needed for that slice.
3. Run the smallest relevant local tests and `git diff --check` for touched paths.
4. Commit only the related files.
5. Push only when the local slice passes targeted checks.
6. Run or observe the affected GitHub Actions workflow once.
7. Record run URL, SHA, status, and conclusion when the workflow proves acceptance criteria.

Do not run full BMAD validation, all story validations, all subagent reviews, or full local validation after every small edit.

Loop budget from this point:

- One implementation slice gets one local targeted loop.
- One remote workflow observation is enough when the changed area maps cleanly to that workflow.
- One focused review pass is enough at a shared contract or final evidence boundary.
- No automatic per-story subagent validation after a passing targeted test suite.
- No BMAD loop-mode run unless a concrete acceptance conflict or repeated CI failure appears.
- If a failure repeats twice in the same area, stop broadening the loop and isolate the failing contract directly.

Run a broader gate only when one of these is true:

- An epic-level implementation boundary is complete.
- A change touches shared generator, matrix, tag, release evidence, or workflow permission contracts.
- Remote CI succeeds but does not prove the story acceptance criteria.
- The final end-to-end release evidence for Story 5.9 is being closed.

## BMAD And Subagent Policy

BMAD remains the planning and traceability framework, not a requirement to perform redundant loops.

- Use existing PRD, architecture, epics, story files, and validation review as source context.
- Do not regenerate PRD, architecture, epics, or stories unless a concrete requirement conflict appears.
- Do not validate every story with a separate subagent after every implementation slice.
- Use at most one focused review pass at a meaningful gate, scoped to the exact risk being closed.
- Prefer direct targeted tests over generic review when a script already encodes the acceptance rule.

Subagents are useful only for bounded independent checks:

- Review a specific implementation diff against a specific story.
- Review one failed CI log and propose the minimal fix.
- Review final Story 5.9 evidence against the original user constraints.

Subagents are not used for routine shell edits, fixture updates, status checks, or every commit.

Default no-subagent cases:

- Documentation-only status updates.
- Fixture changes where a deterministic test proves the fixture contract.
- Shell script hygiene changes covered by shellcheck and an existing local test.
- GitHub Actions status collection.
- Updating sprint/story status after evidence already exists.

Required review cases:

- Release workflow publish/tag behavior changes.
- Matrix eligibility changes that can affect `latest` or PG19 experimental status.
- Final Story 5.9 evidence closure.

Maximum review budget:

- One bounded subagent/review pass per high-risk gate.
- Zero subagents for ordinary package resolver, fixture, generated output, documentation, or status-only changes when local tests encode the contract.
- If a review finds no blocker, move forward; do not chain another review for the same unchanged evidence.

## Execution Order From Here

### 0. Completed Remote Evidence

Status: completed.

- `Validate` is green on the release metadata automation commit.
- `Build Release Candidates` is green on the same commit line.
- Public GHCR pull verification succeeded.
- Release metadata persistence and catalog autocommit succeeded.
- Stable catalogs are non-empty and digest-aware.
- Release metadata/catalog bot commit exists on `origin/main`.

No extra rerun is needed for these proofs unless a later commit touches release workflow behavior.

### 1. Current Follow-Up: Packagecloud PG19 ABI Resolution

Status: in progress locally.

Goal: finish the current packagecloud resolver follow-up without reopening the whole generator/matrix/docs or release workflow slices.

Scope:

- PostgreSQL metadata version `19beta1` must resolve package names through package ABI major `19`.
- TimescaleDB and Toolkit package names must use `postgresql-19`, not `postgresql-19beta1`.
- Skip reasons for PG19 beta must report the exact missing package tokens for `timescaledb-2-postgresql-19` and `timescaledb-toolkit-postgresql-19`.
- Package resolver JSON should expose enough structured fields to prove the metadata PostgreSQL version and package ABI version are not confused.
- Negative fixtures should reject unsupported metadata/package combinations with precise diagnostics.

Out of scope:

- Reworking release publish/autocommit behavior.
- Revalidating every story file.
- Changing supported Debian versions beyond `trixie` and `bookworm`.
- Changing `latest`; it remains PG18 trixie only.
- Running a subagent review unless targeted checks expose an ambiguous contract issue.

Targeted checks for this slice:

- `bash cloudnative-pg-timescaledb/tests/packagecloud/run.sh`
- `bash cloudnative-pg-timescaledb/tests/update/run.sh`
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh`
- `shellcheck -x cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh cloudnative-pg-timescaledb/tests/packagecloud/run.sh`
- `git diff --check`

Commit rule:

- Stage only the packagecloud resolver, packagecloud fixtures/tests, regenerated matrix/docs/generated outputs, and matching story/process documentation that belong to this follow-up.
- Do not include unrelated workflow release metadata files or the local root `.gitignore` unless deliberately chosen as a separate repo hygiene change.
- Decide separately whether the untracked root `.gitignore` is intentional repo hygiene or should remain unstaged.

Remote gate after commit:

- Push feature branch and observe `Validate` first.
- Do not dispatch `Build Release Candidates` for this follow-up unless the final diff unexpectedly touches Docker build, image tag, catalog, release evidence, or publish behavior.

### 2. Update Workflow No-Op Proof

Status: pending only if touched.

Goal: keep scheduled/manual update automation no-op safe now that release metadata exists.

Run this only if a later slice changes update, generated catalog drift, release metadata, package resolution output, or generated output behavior.

Targeted checks:

- `bash cloudnative-pg-timescaledb/tests/update/run.sh`
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh`

Remote gate:

- One manual `Update Metadata` run is enough if local changes affect update behavior.
- Skip the remote run if no update workflow or resolver behavior changed.

### 3. Final Story 5.9 Evidence Closure

Status: pending after current follow-up is clean and the feature branch has the needed green `Validate` evidence.

Goal: close the goal with a compact evidence record, not a full revalidation spiral.

Required evidence:

- Latest successful `Validate` run URL, SHA, status, and conclusion.
- Latest successful `Build Release Candidates` run URL, SHA, status, and conclusion if release behavior was touched after the last green run.
- Confirmation that `latest` resolves to PG18 trixie, not PG17, PG19, or bookworm.
- Confirmation that only `trixie` and `bookworm` are in supported Debian output.
- Confirmation that PG19 remains experimental and not latest-eligible.
- Confirmation that Barman support is documented through the CloudNativePG Barman Cloud Plugin path, not legacy in-image `barman-cloud`.
- Confirmation that release metadata and catalogs are committed and digest-aware.

Review gate:

- One focused review pass is enough, scoped to final evidence versus Story 5.9 and the original user constraints.
- No per-story revalidation unless the review finds a concrete contradiction.

### 4. Optional Sprint Tracking Cleanup

Status: optional.

Goal: make BMAD tracking easier to read without affecting implementation.

Allowed actions:

- Generate or update `_bmad-output/implementation-artifacts/sprint-status.yaml` from existing epics and story files.
- Mark only evidence-backed items as `done`; otherwise keep statuses conservative.

Do not block implementation on this cleanup.

## Practical Next-Step Queue

1. Finish the current packagecloud/PG19 ABI follow-up with the targeted checks listed above.
2. Commit and push only that follow-up if the checks pass.
3. Observe `Validate` on the feature branch; skip release-candidate build unless release behavior changed.
4. Move directly to final Story 5.9 evidence closure if the branch is green and no release contract files changed.
5. Use one focused review for Story 5.9 evidence against the original constraints, then stop.

## Explicitly Deferred

- Artifact Hub integration.
- Alpine support.
- Bullseye support.
- Reworking story files that already pass current requirement review.
- Full BMAD or subagent validation after every small edit.
- Remote `Build Release Candidates` reruns for docs-only or test-only commits unless release behavior changed.
