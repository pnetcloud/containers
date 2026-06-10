---
title: Lean Execution Plan
date: 2026-06-10
scope: CloudNativePG TimescaleDB image automation implementation
status: reduced-loop-current
---

# Lean Execution Plan

## Objective

Finish the current BMAD implementation goal without unnecessary loop overhead while preserving the non-negotiable quality bar: GitHub Actions must pass, GHCR images must be published and anonymously pullable, generated release metadata must be committed, and digest-aware ClusterImageCatalog manifests must reflect published image digests.

## Current Ground Truth

- Story files exist for all 35 stories under `_bmad-output/implementation-artifacts/stories/`; they do not need to be regenerated unless a real requirement contradiction is found.
- The story validation review exists at `_bmad-output/implementation-artifacts/stories/story-validation-review-20260609.md`; it remains the baseline and should not be rerun after every implementation edit.
- Local branch `codex/bmad-cloudnativepg-timescaledb-execution` is fast-forwarded to `origin/main` commit `6d60a05`.
- Commit `8ae4462` added release metadata and catalog autocommit automation.
- Commit `6d60a05` is the bot autocommit that added `cloudnative-pg-timescaledb/release-metadata/*.json` and updated digest-aware catalogs.
- `Validate` passed on GitHub Actions run `27298379342` for commit `8ae446225c72fe26a87f8172f1d6da014668005b`.
- `Build Release Candidates` passed on GitHub Actions run `27298379390` for commit `8ae446225c72fe26a87f8172f1d6da014668005b`; the run included candidate builds, smoke checks, vulnerability scans, SARIF upload handling, release evidence, tag validation, final publish, public anonymous pull verification, and the release metadata/catalog autocommit job.
- The bot commit produced four release metadata JSON files and non-empty `catalog-standard-trixie.yaml` / `catalog-standard-bookworm.yaml` files.
- Verified release tags include `latest`, `18`, and `18-pg18.4-ts2.27.2-20260609` pointing to the same PG18 trixie digest.
- The remaining local worktree is a separate generator/matrix/docs contract slice. It must not be mixed into unrelated release workflow commits.
- Current known local blocker in that slice: catalog drift checks need to use committed release metadata when checking committed digest-aware catalog YAML.

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

### 1. Current Slice: Generator, Matrix, And Generated-Drift Contracts

Status: in progress locally.

Goal: finish the current dirty generator/matrix/docs contract slice without disturbing the already-proven release workflow.

Scope:

- Generator metadata shape validation.
- Matrix skipped-row contract, including `bake_target` / `skipped_marker` behavior.
- Matrix uniqueness and schema validation.
- Generated docs and release rehearsal report drift validation.
- Tests and fixtures for the above.
- Catalog check behavior after release metadata exists in the repository.

Known required fix:

- `generate-catalog --check` paths that compare committed catalog YAML must pass `--release-metadata cloudnative-pg-timescaledb/release-metadata` when release metadata JSON exists.
- Keep the metadata-only `generate-catalog --json` contract available for fixture and schema tests.

Targeted checks for this slice:

- `bash cloudnative-pg-timescaledb/tests/generators/run.sh`
- `bash cloudnative-pg-timescaledb/tests/matrix/run.sh`
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh`
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `bash cloudnative-pg-timescaledb/scripts/validate-docs.sh`
- `bash cloudnative-pg-timescaledb/tests/bake/run.sh`
- `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`
- `bash cloudnative-pg-timescaledb/tests/update/run.sh`
- `git diff --check`

Commit rule:

- Stage only the generator/matrix/docs contract files that belong to this slice.
- Do not include unrelated workflow release metadata files.
- Decide separately whether the untracked root `.gitignore` is intentional repo hygiene or should remain unstaged.

Remote gate after commit:

- Push feature branch and observe `Validate` first.
- Do not dispatch `Build Release Candidates` unless the committed slice changes build, matrix, catalog, release evidence, or publish behavior in a way that local tests cannot fully prove.

### 2. Update Workflow No-Op Proof

Status: pending only if touched.

Goal: keep scheduled/manual update automation no-op safe now that release metadata exists.

Run this only if the current slice changes update, generated catalog drift, release metadata, or generated output behavior.

Targeted checks:

- `bash cloudnative-pg-timescaledb/tests/update/run.sh`
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh`

Remote gate:

- One manual `Update Metadata` run is enough if local changes affect update behavior.
- Skip the remote run if no update workflow or resolver behavior changed.

### 3. Final Story 5.9 Evidence Closure

Status: pending after current slice is clean.

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

## Explicitly Deferred

- Artifact Hub integration.
- Alpine support.
- Bullseye support.
- Reworking story files that already pass current requirement review.
- Full BMAD or subagent validation after every small edit.
- Remote `Build Release Candidates` reruns for docs-only or test-only commits unless release behavior changed.
