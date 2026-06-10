---
storyId: 4.6
storyKey: 4-6-digest-aware-clusterimagecatalog-generation
epic: 4
title: 'Digest-Aware ClusterImageCatalog Generation'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 4.6: Digest-Aware ClusterImageCatalog Generation

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 4.1-4.5 in this epic may be assumed complete.

## Out of Scope

- Candidate build, scan, evidence, signing, and publish gates; owned by Stories 4.2-4.5.
- Public catalog usage docs; owned by Story 5.3.
- End-to-end release rehearsal; owned by Story 5.9.

## Source Story

### Story 4.6: Digest-Aware ClusterImageCatalog Generation

As a CloudNativePG operator,
I want generated `ClusterImageCatalog` manifests for release-complete images,
So that clusters can consume the image family through CloudNativePG-native catalog references.

**Acceptance Criteria:**

**Given** images have been published, signed, and associated with SBOM/provenance and scan results
**When** `cloudnative-pg-timescaledb/scripts/generate-catalog.sh` runs
**Then** it generates `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml`.
**And** it generates `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml`.
**And** catalog entries map supported PostgreSQL majors to published image references.
**And** release catalogs use the published multi-platform manifest-list digest, not a per-platform image digest.
**And** experimental PostgreSQL `19beta1` catalog entries are either excluded from stable catalogs or emitted only in an explicitly named experimental catalog or section.
**And** PostgreSQL `19beta1` entries map to numeric PostgreSQL major `19` where the CloudNativePG catalog schema requires a major, while retaining the experimental tag or reference.
**And** catalog validation fails if a digest does not cover every platform listed as publishable in metadata.
**And** validation fails if a catalog references an unpublished tag, unsigned digest, missing digest, wrong PostgreSQL major, or wrong Debian variant.
**And** catalog generation does not trigger recursive build loops.
**And** release catalog autocommit is handled by a named autocommit job with `contents: write`, explicit catalog path allowlist, no-op behavior, and loop prevention.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`
- `.github/workflows/update.yml`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml`
- `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/tests/catalog/run.sh`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/valid-trixie-catalog.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/valid-bookworm-catalog.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/unpublished-tag.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/unsigned-digest.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/missing-digest.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/platform-missing-from-index.json`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/per-platform-digest.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/wrong-postgres-major.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/wrong-debian-variant.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/pg19beta1-in-stable-catalog.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/missing-catalog-allowlist.txt`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/catalog-autocommit-stages-unlisted-path.yml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/catalog-autocommit-diff-empty.txt`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/catalog-autocommit-recursive-build-commit.json`

## ClusterImageCatalog Contract

- Stable catalogs include only release-complete published images that passed scan, evidence, signing, and publish gates.
- Release catalogs reference the published multi-platform manifest-list digest, not per-platform digests.
- Digest validation must prove the index digest covers every platform listed as publishable in metadata.
- `catalog-standard-trixie.yaml` contains only `trixie` entries; `catalog-standard-bookworm.yaml` contains only `bookworm` entries.
- Experimental `19beta1` is excluded from stable catalogs unless emitted in an explicitly named experimental catalog or section.
- Where the CloudNativePG catalog schema requires numeric PostgreSQL major, `19beta1` maps to `19` while retaining experimental tag/reference metadata.
- `.github/workflows/update.yml` must contain a named `catalog-autocommit` job.
- `catalog-autocommit` is the only story-owned workflow job allowed to commit release catalog changes, has `permissions: contents: write`, stages only paths from `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`, exits cleanly on an empty catalog diff, and prevents recursion for bot/generated catalog commits.

## Required Validation Commands

- `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`
- `bash cloudnative-pg-timescaledb/tests/catalog/run.sh`
- `actionlint .github/workflows/update.yml`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/catalog/run.sh` must run every fixture listed in Expected Artifacts.
- Include negative fixtures for unpublished tag, unsigned digest, missing digest, missing platform in index digest, per-platform/non-index digest, wrong PostgreSQL major, wrong Debian variant, and `19beta1` in stable catalog.
- Include workflow behavior checks that fail when the catalog allowlist is missing or unused, when any staged/committed path is not present in `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`, when empty catalog diffs are not no-op, when `contents: write` is granted outside the named `catalog-autocommit` job, or when the `catalog-autocommit` job lacks a loop-prevention guard for bot/generated catalog commits.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `cloudnative-pg-timescaledb/scripts/generate-catalog.sh` to consume release-complete metadata from Stories 4.2-4.5 and generate digest-aware CloudNativePG ClusterImageCatalog YAML.
- [x] Generate `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` and `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` with only matching Debian variant entries.
- [x] Reference published multi-platform manifest-list digests, validate each digest covers every publishable platform, and reject per-platform-only digests in release catalogs.
- [x] Exclude `19beta1` from stable catalogs unless an explicitly named experimental catalog/section is implemented; when emitted experimentally, map CloudNativePG numeric major to `19` while preserving experimental reference metadata.
- [x] Add catalog validation for unpublished tags, unsigned digests, missing digest, wrong PostgreSQL major, wrong Debian variant, and missing platform coverage.
- [x] Add `catalog-autocommit` to `.github/workflows/update.yml` with `contents: write`, explicit `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`, empty-diff no-op behavior, and loop prevention for generated catalog commits.
- [x] Add catalog fixtures and `cloudnative-pg-timescaledb/tests/catalog/run.sh`, then run `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`, `bash cloudnative-pg-timescaledb/tests/catalog/run.sh`, and `actionlint .github/workflows/update.yml`.

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
| FR-4 | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.1, 5.9 | experimental metadata, resolver fixtures, catalog policy, docs | `validate-metadata.sh`, `validate-tags.sh`, catalog validation |
| FR-10 | 2.3, 2.5, 4.6, 5.7, 5.9 | update autocommit, generated artifacts, release catalogs, docs | no-op update test, path allowlist, `make validate`, rehearsal report |
| FR-16 | 4.6, 5.3, 5.9 | digest-aware catalogs, catalog docs | `generate-catalog.sh`, catalog validation, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-7 Public trust | 4.4, 4.5, 4.6, 5.1, 5.5, 5.9 | Labels, docs, SBOM, provenance, signatures, vulnerability scans, and catalogs make public releases inspectable. |
| NFR-8 Automation safety | 1.6, 2.5, 4.6, 5.6, 5.7, 5.9 | Generated artifacts are reproducible, committed through controlled paths, validated for drift, and never hand-edited as final fixes. |
| Makefile command surface | 1.2, 2.3, 3.3, 4.1, 4.6, 5.6, 5.9 | Root `Makefile` exposes stable `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` targets that delegate to scripts. |
| PostgreSQL scope | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.9 | `17`, `18`, and experimental `19beta1` are supported according to metadata and release gates. |
| Generated artifacts | 1.5, 1.6, 3.1, 4.1, 4.6, 5.7, 5.9 | Dockerfiles, Bake file, matrix JSON, catalogs, docs tables, and README examples are generated or validated and drift-checked. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-4-trusted-ghcr-release-and-cluster-catalog/4-6-digest-aware-clusterimagecatalog-generation.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented catalog release metadata loading in `generator_contract.py` using Story 4.5 `ghcr-release-metadata.json` shape.
- Fixed release tag matching so primary `trixie` rows do not match `bookworm` immutable tags.
- Regenerated default stable catalog outputs with empty `spec.images` because current committed metadata has no release-complete publish metadata.
- Added `catalog-autocommit` after resolver `autocommit` to avoid same-branch push races.
- Addressed review findings: catalog autocommit refreshes branch tip and no-ops without release metadata; recursion guard is job-level; catalog validation rejects file/name variant mismatch, duplicate release metadata records, and incomplete signer identity metadata.

### Completion Notes

- Stable catalog generation now emits CNPG `ClusterImageCatalog` entries only from release-complete metadata and excludes experimental `19beta1` from stable catalogs.
- Catalog image refs use `repo:immutable-tag@sha256:<manifest-list-digest>` and validation rejects unpublished tags, unsigned metadata, missing digest, per-platform digest, wrong PostgreSQL major, wrong Debian variant, missing platform coverage, and `19beta1` in stable catalogs.
- `make catalog` is enabled and delegates to `generate-catalog.sh`.
- Release catalog autocommit uses a dedicated allowlist, no-op empty diff behavior, permission policy entry, recursion guard, and waits for resolver autocommit.
- 2026-06-10 follow-up validation: current stable catalogs may remain empty when no release-complete metadata exists. Keep this story classified as generator implementation-complete, not final catalog product proof, until Story 5.9 records non-empty trixie/bookworm catalogs generated from real/staging release metadata and manifest-list digests.

### File List

- `.github/workflows/update.yml`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml`
- `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/scripts/catalog.sh`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/catalog/run.sh`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/catalog-autocommit-diff-empty.txt`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/catalog-autocommit-recursive-build-commit.json`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/catalog-autocommit-stages-unlisted-path.yml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/missing-catalog-allowlist.txt`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/missing-digest.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/missing-signer-identity.json`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/per-platform-digest.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/pg19beta1-in-stable-catalog.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/platform-missing-from-index.json`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/unpublished-tag.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/unsigned-digest.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/valid-bookworm-catalog.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/valid-trixie-catalog.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/wrong-catalog-name-variant.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/wrong-debian-variant.yaml`
- `cloudnative-pg-timescaledb/tests/catalog/fixtures/wrong-postgres-major.yaml`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-missing-catalog-path.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-missing-variant.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-wrong-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`
- `cloudnative-pg-timescaledb/workflow-policy.yaml`

### Validation

- `bash -n cloudnative-pg-timescaledb/tests/catalog/run.sh cloudnative-pg-timescaledb/scripts/catalog.sh cloudnative-pg-timescaledb/scripts/generate-catalog.sh cloudnative-pg-timescaledb/scripts/validate.sh cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`
- `python3 -m py_compile cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/generate-catalog.sh --check`
- `cloudnative-pg-timescaledb/scripts/generate-catalog.sh --json`
- `bash cloudnative-pg-timescaledb/tests/catalog/run.sh`
- `/tmp/codex-go-bin/actionlint .github/workflows/update.yml`
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh`
- `bash cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `git diff --check -- <story 4.6 paths>`
- Staged snapshot: `git checkout-index --all --prefix="$tmpdir/" && (cd "$tmpdir" && make validate)` passed.

### Change Log

- 2026-06-10: Implemented digest-aware release catalog generation and validation; added catalog autocommit workflow and fixture coverage.
