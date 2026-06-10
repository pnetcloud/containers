---
storyId: 1.4
storyKey: 1-4-tag-policy-library-and-validation
epic: 1
title: 'Tag Policy Library and Validation'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: a6e5968
---

# Story 1.4: Tag Policy Library and Validation

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 1.1-1.3 in this epic may be assumed complete.

## Out of Scope

- GHCR publish workflow/tag promotion integration; owned by Epic 4.
- Public tag documentation and CloudNativePG examples; owned by Story 5.2.
- Release rehearsal; owned by Story 5.9.
- Catalog references or digest handling; owned by Story 4.6.
- Story-level DoD exception: this story documents the tag library/validator contract only; public tag documentation updates are intentionally deferred to Story 5.2.

## Source Story

### Story 1.4: Tag Policy Library and Validation

As an operator,
I want tags to be deterministic and guarded,
So that PostgreSQL major tags, Debian variant tags, immutable date tags, and `latest` cannot point to the wrong image line.

**Acceptance Criteria:**

**Given** valid metadata and an explicit UTC release date
**When** `cloudnative-pg-timescaledb/scripts/validate-tags.sh` runs
**Then** primary `trixie` immutable tags follow `{major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}`.
**And** secondary `bookworm` immutable tags append `-bookworm`.
**And** rolling primary tags such as `17` and `18` never cross PostgreSQL majors.
**And** rolling secondary tags include the OS suffix, for example `18-bookworm`.
**And** `latest` is emitted exactly for PostgreSQL `18` `trixie`.
**And** `latest` is never assigned to `bookworm`, PostgreSQL `17`, or experimental PostgreSQL `19beta1`.
**And** tag validation hard-fails any Debian variant other than `trixie` or `bookworm`.
**And** tag validation hard-fails any PostgreSQL line other than `17`, `18`, or experimental `19beta1`.
**And** tag generation is deterministic from metadata plus UTC `YYYYMMDD`.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/lib/tags.sh`
- `cloudnative-pg-timescaledb/scripts/validate-tags.sh`
- `cloudnative-pg-timescaledb/tests/tags/run.sh`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/valid-tags.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/wrong-latest-pg17.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/missing-latest-pg18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/wrong-latest-bookworm.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/wrong-latest-pg19beta1.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-bookworm-suffix.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-immutable-date.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/rolling-major-crosses-pg-major.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-debian-variant-alpine.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-debian-variant-bullseye.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-postgres-major.yaml`

## Required Validation Commands

- `cloudnative-pg-timescaledb/scripts/validate-tags.sh --metadata cloudnative-pg-timescaledb/versions.yaml --date 20260609`
- `bash cloudnative-pg-timescaledb/tests/tags/run.sh`
- make validate

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/tags/run.sh` must call `validate-tags.sh --metadata cloudnative-pg-timescaledb/tests/tags/fixtures/<file>.yaml --date 20260609` for each fixture.
- Include one positive fixture and at least one negative fixture for each hard-fail rule introduced by this story, including missing `latest` on PG18 `trixie`, wrong `latest` on any other row, rolling major tags crossing PostgreSQL majors, unsupported Debian variants, and unsupported PostgreSQL lines.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `scripts/lib/tags.sh` as the single tag-policy library for immutable tags, rolling tags, Debian suffixes, experimental handling, and `latest` eligibility.
- [x] Implement `validate-tags.sh` with explicit UTC `--date YYYYMMDD`, metadata input, deterministic tag output checks, and actionable failure diagnostics.
- [x] Add tag fixtures covering valid tags and failures for wrong `latest` on PG17, `bookworm`, PG19beta1, invalid `bookworm` suffixes, invalid dates, and rolling-major crossover.
- [x] Integrate tag validation into `make validate` without adding GHCR publish or catalog promotion behavior owned by later stories.
- [x] Run the required tag validation commands and record outputs, changed paths, and any edge-case decisions.

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
| FR-4 | 1.1, 1.3, 1.4, 1.5, 2.2, 4.1, 4.6, 5.1, 5.9 | experimental metadata, generator contracts, resolver fixtures, catalog policy, docs | `validate-metadata.sh`, `validate-tags.sh`, catalog validation |
| FR-15 | 1.4, 4.5, 4.7, 5.2, 5.9 | tag policy, GHCR publish job, image tag docs | `validate-tags.sh`, publish rehearsal, docs validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| PostgreSQL scope | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.9 | `17`, `18`, and experimental `19beta1` are supported according to metadata and release gates. |
| Tag policy | 1.4, 4.5, 5.2, 5.9 | Immutable, rolling, `bookworm` suffix, experimental, and `latest` rules are generated, validated, documented, and rehearsed. |
| NFR-2 Reproducibility | 1.4 | Tag outputs are pure functions of metadata plus explicit UTC `YYYYMMDD`; no local timezone or workflow state can change generated tags. |
| NFR-4 Maintainability | 1.4 | Shared tag logic lives in `scripts/lib/tags.sh` so workflows, generators, docs validation, and publish gates do not recompute tag policy independently. |
| NFR-8 Automation safety | 1.4 | Negative fixtures block wrong `latest`, invalid `bookworm` suffixes, experimental promotion, and malformed immutable dates before publish integration exists. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-1-reproducible-image-family-contract/1-4-tag-policy-library-and-validation.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add a shared tag policy library that derives deterministic tags from metadata plus an explicit UTC `YYYYMMDD` release date.
- Add a CLI validator requiring `--metadata` and `--date` so tag output never depends on local time.
- Prove valid and invalid tag behavior with fixtures and wire the validator into `make validate` without publish/catalog behavior.

### Debug Log

- 2026-06-09: Started Story 1.4 from baseline `a6e5968`.
- 2026-06-09: Implemented `scripts/lib/tags.sh` and `validate-tags.sh` with deterministic diagnostics and explicit UTC date validation.
- 2026-06-09: Added tag fixtures for valid primary/secondary/experimental tags, wrong latest assignment, missing latest on `18-trixie`, invalid `bookworm` suffixes, invalid immutable dates, rolling major crossover, Alpine, `bullseye`, and unsupported PostgreSQL `19`.
- 2026-06-09: Integrated tag validation into `scripts/validate.sh` using deterministic default `TAG_VALIDATION_DATE=20260609` for local validation.
- 2026-06-09: Required validation passed: `validate-tags.sh --metadata versions.yaml --date 20260609`, `tests/tags/run.sh`, `make validate`, and `git diff --check`.
- 2026-06-09: Addressed BMad code review findings: publishable rows now require materialized `tags`, `cnpg_tag` must match `pg_version`/Debian row, generated tags must be Docker tag-safe, and tag ownership must be unique across rows.
- 2026-06-09: Re-ran `validate-tags.sh`, `tests/tags/run.sh`, `make validate`, and `git diff --check` successfully after review fixes.
- 2026-06-10: Fixed shellcheck SC2016 in `tests/tags/run.sh` without changing the literal `TAG_VALIDATION_DATE` assertion, then re-ran tag validation, fixture tests, shellcheck, `make validate`, and `git diff --check`.
- 2026-06-10: Addressed BMad review findings: added controlled `validate-tags.sh` diagnostics for missing option values, rejected `tags` on `publish: false` rows, converted directory and invalid UTF-8 metadata paths into deterministic diagnostics, removed the fixed `/tmp` positive-output path, and kept the `DATE` fallback assertion aligned with `validate.sh`.
- 2026-06-10: Addressed BMad review round 2 findings: made missing `18-trixie` latest ownership fail unconditionally, moved tag date resolution/calendar validation into shared tag policy, and proved generated matrix tags/candidate refs honor `TAG_VALIDATION_DATE -> DATE -> 20260609`.
- 2026-06-10: Addressed BMad review round 3 findings: moved Docker tag grammar validation into shared Python tag policy and matrix JSON validation, added generator/matrix regressions for invalid tag characters, and corrected stale `versions.yaml` completion notes.
- 2026-06-10: Addressed BMad review round 4 findings: required the `latest_eligible` owner to be publishable and emit `latest`, rejected digest-form candidate refs in matrix validation, and added `validate-matrix-json.py` to the File List.
- 2026-06-10: Addressed BMad review round 5 findings: included the shared `tags.sh` tag-policy refactor in the review artifact and tightened matrix validation to require row-shaped immutable tags plus exact latest/tag suffix policy.
- 2026-06-10: Addressed BMad review round 6 findings: added `timescaledb_version` to generated matrix include rows and schema docs, then enforced exact immutable tag TimescaleDB/version shape, latest owner presence, supported dimensions, and required platforms in the shared matrix validator.

### Completion Notes

- Primary `trixie` publishable rows generate rolling major tags, immutable `{major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}` tags, and `latest` only for non-experimental PostgreSQL `18` `trixie`.
- Secondary `bookworm` publishable rows generate OS-suffixed rolling and immutable tags, and never receive `latest`.
- Experimental `19beta1` rows generate immutable date tags only and never receive normal rolling tags or `latest`.
- Current `versions.yaml` has publishable PostgreSQL 17/18 `trixie` and `bookworm` rows with deterministic materialized tags, while PostgreSQL `19beta1` rows remain `publish: false`; fixture coverage also proves skipped and invalid tag cases.
- Publishable rows cannot bypass tag validation by omitting `tags`; every generated tag is checked for deterministic ownership and Docker tag grammar before later publish stories consume it.
- Skipped rows cannot carry materialized publish tags, so disabled image rows cannot accidentally retain rolling, immutable, or `latest` references.
- The only `latest_eligible` owner must be publishable and emit `latest`; skipped rows cannot reserve `latest` without producing the tag.
- Tag validation reports invalid CLI arguments and non-file/non-UTF-8 metadata inputs with the same deterministic diagnostic shape used by other validators.
- Generated tag consumers now use the same shared release-date resolution and calendar validation as tag validation, so matrix/candidate refs cannot silently drift to `20260609` or accept impossible dates.
- Matrix validation requires candidate refs to equal `image:<immutable-intended-tag>` and rejects digest-form candidate refs.
- Matrix validation also rejects fake immutable tags, bookworm `latest`, trixie immutable tags with Debian suffixes, and secondary immutable tags missing their Debian suffix.
- Matrix include rows now carry `timescaledb_version`, letting validators reject wrong TimescaleDB immutable tags instead of accepting any Docker-safe `-ts...` segment.
- Story 1.4 intentionally does not add GHCR publish, tag promotion, catalog references, or public tag docs; those remain owned by later stories.

### Latest Validation

- `bash cloudnative-pg-timescaledb/scripts/validate-tags.sh --metadata cloudnative-pg-timescaledb/versions.yaml --date 20260609` - passed.
- `bash cloudnative-pg-timescaledb/tests/tags/run.sh` - passed.
- `shellcheck -x cloudnative-pg-timescaledb/scripts/lib/tags.sh cloudnative-pg-timescaledb/scripts/validate-tags.sh cloudnative-pg-timescaledb/tests/tags/run.sh` - passed.
- `make validate` - passed.

## File List

- `cloudnative-pg-timescaledb/scripts/lib/tags.sh`
- `cloudnative-pg-timescaledb/scripts/lib/tag_policy.py`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate-tags.sh`
- `cloudnative-pg-timescaledb/scripts/validate-matrix-json.py`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/docs/generated/matrix-schema.md`
- `cloudnative-pg-timescaledb/tests/tags/run.sh`
- `cloudnative-pg-timescaledb/tests/matrix/run.sh`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/valid-publishable-matrix.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/missing-required-key.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/pg19beta1-not-experimental.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/bookworm-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-missing-include-key.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-wrong-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/valid-tags.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/wrong-latest-pg17.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/missing-latest-pg18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/wrong-latest-bookworm.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/wrong-latest-pg19beta1.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-bookworm-suffix.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-immutable-date.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/rolling-major-crosses-pg-major.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/publish-true-missing-tags.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-cnpg-tag-pg-mismatch.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-cnpg-tag-debian-mismatch.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/duplicate-tag-assignment.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-docker-tag-character.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-debian-variant-alpine.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-debian-variant-bullseye.yaml`
- `cloudnative-pg-timescaledb/tests/tags/fixtures/invalid-postgres-major.yaml`

## Change Log

- 2026-06-09: Implemented Story 1.4 tag policy library and explicit-date tag validator.
- 2026-06-09: Added deterministic tag fixtures for primary `trixie`, secondary `bookworm`, experimental `19beta1`, `latest`, rolling tags, immutable dates, and unsupported dimensions.
- 2026-06-09: Wired tag validation into `make validate` without adding publish or catalog behavior.
- 2026-06-09: Hardened tag validation after code review for missing materialized tags, CNPG base mismatch, duplicate tag ownership, and invalid Docker tag characters.
- 2026-06-10: Fixed shellcheck quoting in tag fixture runner and refreshed validation evidence.
- 2026-06-10: Resolved BMad review findings for tag CLI argument diagnostics, skipped-row tag rejection, metadata read diagnostics, test temp output, and review artifact self-consistency.
- 2026-06-10: Resolved BMad review round 2 findings for required latest ownership and shared generated tag-date validation.
- 2026-06-10: Resolved BMad review round 3 findings for shared Docker tag grammar enforcement and stale completion notes.
- 2026-06-10: Resolved BMad review round 4 findings for skipped latest ownership, digest candidate refs, and File List completeness.
- 2026-06-10: Resolved BMad review round 5 findings for review artifact composition and strict matrix immutable/latest policy validation.
- 2026-06-10: Resolved BMad review round 6 findings for exact TimescaleDB immutable tags, required latest owner, supported matrix dimensions, and matrix schema drift.
