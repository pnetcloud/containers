---
storyId: 5.2
storyKey: 5-2-tag-policy-and-cloudnativepg-image-usage-docs
epic: 5
title: 'Tag Policy and CloudNativePG Image Usage Docs'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 5.2: Tag Policy and CloudNativePG Image Usage Docs

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 5.1-5.1 in this epic may be assumed complete.

## Out of Scope

- README compatibility overview; owned by Story 5.1.
- ClusterImageCatalog usage details; owned by Story 5.3.
- Release evidence verification docs; owned by Story 5.5.
- End-to-end release rehearsal; owned by Story 5.9.

## Source Story

### Story 5.2: Tag Policy and CloudNativePG Image Usage Docs

As a CloudNativePG operator,
I want documented image tags and examples,
So that I can choose between pinned, rolling, and convenience tags without breaking PostgreSQL major isolation.

**Acceptance Criteria:**

**Given** generated tag policy examples and release evidence fixtures
**When** users read `docs/image-tags.md` or README tag sections
**Then** primary `trixie` immutable tags are documented in the form `{major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}`.
**And** secondary `bookworm` tags are documented with the `-bookworm` suffix.
**And** rolling primary major tags such as `18` and secondary tags such as `18-bookworm` are explained.
**And** `latest` is documented as convenience-only and only for PostgreSQL `18` `trixie`.
**And** direct CloudNativePG `imageName` examples use major-prefixed tags rather than `latest`.
**And** docs warn that PostgreSQL `19beta1` is experimental and never receives `latest` in v1.

## Expected Artifacts

- `docs/image-tags.md`
- README tag section
- `cloudnative-pg-timescaledb/tests/docs/tags/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/valid-tags.md`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/latest-primary-example.md`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/latest-bookworm.md`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/latest-pg17.md`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/latest-pg19beta1.md`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/bookworm-missing-suffix.md`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/missing-immutable-date-tag.md`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/pg19beta1-normal-tag.md`

## Tag Documentation Contract

- Primary immutable `trixie` tags use `{major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}`, for example `18-pg18.4-ts2.27.2-20260609`.
- Secondary `bookworm` immutable tags append `-bookworm`, for example `18-pg18.4-ts2.27.2-20260609-bookworm`.
- Rolling primary tags such as `17` and `18` are allowed only for `trixie`; rolling secondary tags must include the OS suffix, for example `18-bookworm`.
- `latest` is documented as convenience-only and only points to PostgreSQL `18` `trixie`; it must never be the primary CloudNativePG `imageName` example.
- PostgreSQL `19beta1` examples must be marked experimental and must not receive normal rolling tags or `latest`.
- Docs must recommend immutable or major-prefixed tags for CloudNativePG examples and explain when to prefer digests.

## Required Validation Commands

- make validate
- `bash cloudnative-pg-timescaledb/tests/docs/tags/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/docs/tags/run.sh` must run every tag fixture listed in Expected Artifacts.
- Include negative fixtures for `latest` as a primary example, `latest` on `bookworm`, `latest` on PostgreSQL `17`, `latest` on `19beta1`, missing `-bookworm` suffix, missing immutable date tag format, and PostgreSQL `19beta1` normal tag examples.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Write `docs/image-tags.md` and README tag content that documents immutable, rolling, OS-suffixed, experimental, and `latest` tag policy from Story 1.4 and Story 4.5.
- [x] Ensure examples prefer immutable or major-prefixed CloudNativePG `imageName` values and do not use `latest` as the primary example.
- [x] Document `latest` as convenience-only for PostgreSQL `18` `trixie`, never for `bookworm`, PostgreSQL `17`, or `19beta1`.
- [x] Add tag docs fixtures for wrong latest usage, missing `-bookworm`, missing immutable date tag format, and `19beta1` normal tag examples.
- [x] Run `make validate` and `bash cloudnative-pg-timescaledb/tests/docs/tags/run.sh`.

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

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| Tag policy | 1.4, 4.5, 5.2, 5.9 | Immutable, rolling, `bookworm` suffix, experimental, and `latest` rules are generated, validated, documented, and rehearsed. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-5-public-operator-and-maintainer-documentation/5-2-tag-policy-and-cloudnativepg-image-usage-docs.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Added `docs/image-tags.md` with immutable, rolling, bookworm-suffixed, experimental, `latest`, digest-pinning, and CloudNativePG `imageName` guidance.
- Added README tag sections with major-prefixed `imageName` examples and `latest`/PG19beta1 warnings.
- Added tag documentation validator and fixtures for `latest` misuse, missing `-bookworm`, missing immutable date suffix, and PG19beta1 rolling-tag misuse.
- Review subagent found regex bypasses for `published for` latest wording and `receives the rolling tag 19beta1`; validator and fixtures were tightened.
- Full staged-snapshot validation passed after review fixes.

### Completion Notes

- Direct CloudNativePG examples use immutable or major-prefixed tags, never `latest`.
- `latest` is documented and validated as convenience-only for PostgreSQL `18` on Debian `trixie`.
- Debian `bookworm` examples require `-bookworm` suffix for immutable and rolling tags.
- PostgreSQL `19beta1` is documented and validated as experimental with immutable preview tags only.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/docs/tags/run.sh` PASS
- `bash cloudnative-pg-timescaledb/tests/docs/readme/run.sh` PASS
- staged snapshot `make validate` PASS

### File List

- `README.md`
- `docs/image-tags.md`
- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/docs/readme/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/tags/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/tags/fixtures/*.md`

### Change Log

- 2026-06-10: Completed Story 5.2 tag policy and CloudNativePG image usage documentation with validation fixtures and review fixes.
