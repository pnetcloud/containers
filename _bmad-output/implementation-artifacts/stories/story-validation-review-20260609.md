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

Updated 2026-06-10: remote GitHub Actions evidence now proves `Validate` and `Build Release Candidates` succeeded for commit `e12488ecdde7b6f3588d32b75ebf878210273534`:

- `Validate`: `https://github.com/pnetcloud/containers/actions/runs/27267944216`, status `completed`, conclusion `success`.
- `Build Release Candidates`: `https://github.com/pnetcloud/containers/actions/runs/27267944657`, status `completed`, conclusion `success`.

Remaining proof gap: Stories 4.4, 4.5, and 4.6 are implementation-complete but still need real/staging release evidence before they can be treated as product release proof: actual cosign verification against a digest, staging/final publish metadata with promoted tags, and non-empty catalogs generated from real release metadata.

### Epic 5

Subagent validation found three final-proof gaps:

- Story 5.9 did not explicitly prove `vendor/` is excluded from build/runtime/release contexts.
- Story 5.9 did not include final release-rehearsal fixtures for Alpine, `bullseye`, and unsupported Debian variants.
- Story 5.9 used ambiguous `CI-safe equivalent` wording for GitHub Actions proof.

Resolution:

- Story 5.9 now requires release rehearsal checks and fixtures for `vendor/` build/runtime consumption.
- Story 5.9 now requires release rehearsal hard-fail fixtures for Alpine, `bullseye`, and unsupported Debian variants.
- Story 5.9 now requires actual `release-rehearsal.yml` `workflow_dispatch` evidence from the same repository workflow run, with URL, status, and successful conclusion.

## Next Execution Step

Current blocker is Story 5.9 plus remote workflow availability.

Rechecked 2026-06-10: `gh workflow list --repo pnetcloud/containers --all` still lists only `Build Release Candidates` and `Validate`; `gh workflow view update.yml --repo pnetcloud/containers --yaml` and `gh workflow view release-rehearsal.yml --repo pnetcloud/containers --yaml` both return `HTTP 404`.

Do not close the final release proof until these external checks exist from the same repository:

- `update.yml` visible in GitHub Actions API and validated by at least one real `workflow_dispatch` no-op or controlled autocommit run.
- `release-rehearsal.yml` visible in GitHub Actions API and validated by `gh workflow run`, `gh run watch`, and `gh run view --json url,status,conclusion,headSha` with conclusion `success`.
- GHCR/staging publish evidence proves final tags, `latest=18-trixie`, SBOM/provenance/signature verification, and non-empty trixie/bookworm catalogs for real manifest-list digests.
