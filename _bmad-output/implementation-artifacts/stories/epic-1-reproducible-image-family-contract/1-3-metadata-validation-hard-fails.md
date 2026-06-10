---
storyId: 1.3
storyKey: 1-3-metadata-validation-hard-fails
epic: 1
title: 'Metadata Validation Hard-Fails'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: cae19b0
---

# Story 1.3: Metadata Validation Hard-Fails

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 1.1-1.2 in this epic may be assumed complete.

## Out of Scope

- Upstream CNPG base-image availability, TimescaleDB package availability, Toolkit package availability, and per-architecture repository availability; owned by Stories 2.1 and 2.2.
- Dockerfile generation, Bake generation, image builds, smoke tests, workflow publish gates, and docs generation; owned by later stories.

## Source Story

### Story 1.3: Metadata Validation Hard-Fails

As a maintainer,
I want metadata validation to fail invalid image definitions early,
So that unsupported or unsafe image combinations cannot reach generated files or CI.

**Acceptance Criteria:**

**Given** `cloudnative-pg-timescaledb/versions.yaml`
**When** `cloudnative-pg-timescaledb/scripts/validate-metadata.sh` runs
**Then** it hard-fails missing required fields.
**And** it hard-fails Alpine, `bullseye`, non-Debian variants, unsupported PostgreSQL majors including `19`, unmarked PostgreSQL `19beta1`, missing `latest_eligible` on `18-trixie`, and any `latest_eligible` entry outside `18-trixie`.
**And** statically unsupported publishable combinations fail validation before generated files or CI consume them.
**And** non-published combinations are allowed only with `publish: false` and a non-empty `skip_reason`.
**And** platforms are explicit for every entry; `publish: true` entries must contain exactly `linux/amd64` and `linux/arm64`, while skipped `publish: false` entries may contain only allowed platform values and must include non-empty `skip_reason`.
**And** tests or fixtures cover one valid metadata set and each hard-fail class.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/lib/common.sh`
- `cloudnative-pg-timescaledb/scripts/lib/metadata.sh`
- `cloudnative-pg-timescaledb/scripts/validate-metadata.sh`
- `Makefile` validation target integration for metadata hard-fail checks
- `cloudnative-pg-timescaledb/tests/metadata/run.sh`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/valid.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/missing-top-level-key.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-current-major.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-primary-debian-variant.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-allowed-postgres-majors.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-allowed-debian-variants.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-allowed-platforms.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-field-types.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/duplicate-pg-debian-row.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/missing-required-pg-debian-row.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/missing-required-field.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-debian-variant-alpine.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-debian-variant-bullseye.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-debian-variant-non-debian.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-postgres-major.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/unmarked-pg19beta1.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-postgres-major-19.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-latest-eligible-not-18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-latest-eligible-missing-18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-latest-eligible-multiple.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-platform.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/missing-platforms.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/publish-true-missing-required-platform.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/publish-true-empty-resolver-owned.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/publish-false-without-skip-reason.yaml`

## Metadata Validation Contract

Story 1.3 validates metadata schema and static repository policy only. It must not perform upstream CNPG base-image availability, TimescaleDB package availability, Toolkit package availability, or per-architecture package repository availability resolution; those checks belong to Stories 2.1 and 2.2.

Required fields for every `entries[]` object:

- `pg_major`
- `pg_version`
- `debian_variant`
- `cnpg_tag`
- `cnpg_digest`
- `timescaledb_version`
- `timescaledb_package_version`
- `toolkit_version`
- `toolkit_package_version`
- `platforms`
- `publish`
- `experimental`
- `latest_eligible`
- `skip_reason`

Top-level schema and source-of-truth invariants owned by this story:

- `schema_version`, `image`, `allowed`, and `entries` are required top-level keys.
- `schema_version` must be string value `"1"`.
- `image.current_major` must be string value `"18"`.
- `image.primary_debian_variant` must be string value `trixie`.
- `allowed.postgres_majors` must be exactly `17`, `18`, and `19beta1` with no extra or missing values.
- `allowed.debian_variants` must be exactly `trixie` and `bookworm` with no extra or missing values.
- `allowed.platforms` must be exactly `linux/amd64` and `linux/arm64` with no extra or missing values.
- Field types must match the Story 1.1 metadata contract: strings for scalar version/tag/digest/skip fields, booleans for policy fields, and string lists for `platforms`.
- The matrix key `(pg_major, debian_variant)` must be unique for every `entries[]` row.
- Required matrix coverage is exactly `17-trixie`, `18-trixie`, `19beta1-trixie`, `17-bookworm`, `18-bookworm`, and `19beta1-bookworm` unless a later story explicitly changes the supported matrix through updated planning docs.

Static policy checks owned by this story:

- `debian_variant` is only `trixie` or `bookworm`.
- `pg_major` is only `17`, `18`, or `19beta1`.
- PostgreSQL `19` is unsupported and must fail as an invalid `pg_major`; `19beta1` is the only accepted PostgreSQL 19 preview value.
- Any `19beta1` entry must be marked `experimental: true`.
- Exactly one entry must set `latest_eligible: true`; it must be PostgreSQL `18`, `trixie`, and `experimental: false`. Missing `latest_eligible: true` on `18-trixie`, multiple latest candidates, or any latest candidate outside `18-trixie` must hard-fail. Story 1.3 treats `latest_eligible` as a policy marker and must not require `publish: true` while resolver-owned fields are still empty in the Story 1 scaffold; publish-time tag enforcement is owned by Stories 1.4, 4.5, and 5.9.
- `platforms` is required and contains only `linux/amd64` and `linux/arm64`.
- `publish: true` entries must contain exactly `linux/amd64` and `linux/arm64`; skipped `publish: false` entries still require a `platforms` list, and values may contain only those two platforms.
- `publish: false` requires a non-empty `skip_reason`.
- `publish: true` entries cannot use empty resolver-owned values: `cnpg_digest`, `timescaledb_version`, `timescaledb_package_version`, `toolkit_version`, and `toolkit_package_version`.
- For Story 1.3, “statically unsupported publishable combination” means `publish: true` combined with unsupported `debian_variant`, unsupported `pg_major` including `19`, unmarked `19beta1`, invalid/missing/multiple `latest_eligible`, missing/invalid platforms, or empty resolver-owned fields. Actual upstream unavailability is deferred to Stories 2.1 and 2.2.

## Required Validation Commands

- `cloudnative-pg-timescaledb/scripts/validate-metadata.sh`
- `bash cloudnative-pg-timescaledb/tests/metadata/run.sh`
- make validate

`validate-metadata.sh` must accept an optional metadata file path argument for fixture execution, for example `cloudnative-pg-timescaledb/scripts/validate-metadata.sh cloudnative-pg-timescaledb/tests/metadata/fixtures/valid.yaml`. With no argument it validates `cloudnative-pg-timescaledb/versions.yaml`.

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/metadata/run.sh` must run the valid fixture and every negative fixture listed in Expected Artifacts.
- Include one positive fixture and at least one negative fixture for each hard-fail rule introduced by this story, including Alpine, `bullseye`, another non-Debian variant, invalid/missing platforms, and `publish: true` with empty resolver-owned fields.
- Include negative fixtures for missing top-level keys, wrong current major, wrong primary Debian variant, wrong allowed lists, wrong field types, duplicate PG/Debian rows, missing required PG/Debian rows, unsupported `pg_major: "19"`, unmarked `19beta1`, missing latest candidate on `18-trixie`, latest candidate outside `18-trixie`, and multiple latest candidates.
- Include a Make integration assertion that `make validate` invokes `cloudnative-pg-timescaledb/scripts/validate-metadata.sh` and cannot bypass the metadata hard-fail gate.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

Direct story-owned requirements: FR-1, FR-2, FR-4, NFR-2, NFR-4, NFR-6, NFR-8, Metadata source of truth, Debian scope, and PostgreSQL scope.

## Tasks / Subtasks

- [x] Implement shared shell libraries `common.sh` and `metadata.sh` for deterministic metadata loading, schema checks, policy diagnostics, and fixture execution.
- [x] Implement `validate-metadata.sh` with default validation of `versions.yaml` and optional metadata-file validation for fixture runs.
- [x] Add all positive and negative metadata fixtures for top-level invariants, required matrix coverage, duplicate rows, field types, required fields, Debian scope, PostgreSQL scope, `latest_eligible`, platforms, publishability, resolver-owned empty fields, and `skip_reason` rules.
- [x] Wire metadata validation into the Make validation surface and prove `make validate` calls the metadata validator without adding upstream CNPG or package availability checks owned by Epic 2.
- [x] Run `validate-metadata.sh` and the metadata fixture runner, then record changed paths and validation output.

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
| FR-1 | 1.1, 1.2, 1.3, 1.5, 1.6, 3.1 | `versions.yaml`, Makefile command surface, generated image definitions, metadata validators | `make help`, `make validate`, `validate-metadata.sh`, `validate-generated.sh` |
| FR-2 | 1.1, 1.3, 1.5, 2.1, 2.2, 4.1, 5.1 | Debian variant metadata, generator contracts, resolver fixtures, matrix JSON, docs tables | `validate-metadata.sh`, resolver tests, `generate-matrix.sh` |
| FR-4 | 1.1, 1.3, 1.4, 1.5, 2.2, 4.1, 4.6, 5.1, 5.9 | experimental metadata, generator contracts, resolver fixtures, catalog policy, docs | `validate-metadata.sh`, `validate-tags.sh`, catalog validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-2 Reproducibility | 1.1, 1.3, 1.5, 1.6, 3.1, 4.2, 4.4, 5.9 | Metadata, digests, package versions, platforms, tags, generated outputs, and release evidence explain each image after the fact. |
| NFR-6 Portability | 1.3, 2.2, 3.3, 4.2, 5.9 | `linux/amd64` and `linux/arm64` availability is resolved, built, smoked per platform, and rehearsed for every publishable combination. |
| Metadata source of truth | 1.1, 1.3, 1.5, 5.6 | `cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited image source of truth. |
| Debian scope | 1.1, 1.3, 2.1, 2.2, 3.4, 5.1, 5.9 | Only `trixie` and `bookworm` are accepted; Alpine, `bullseye`, and other variants hard-fail. |
| PostgreSQL scope | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.9 | `17`, `18`, and experimental `19beta1` are supported according to metadata and release gates. |
| NFR-2 Reproducibility | 1.3 | Static metadata validation rejects malformed image records before generators, CI matrices, or builds can consume them. |
| NFR-4 Maintainability | 1.3 | The validator centralizes allowed PostgreSQL major, Debian variant, platform, and source-of-truth policy instead of spreading checks across workflows. |
| NFR-8 Automation safety | 1.3 | Positive and negative fixtures prove every hard-fail rule and require actionable diagnostics before automation proceeds. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-1-reproducible-image-family-contract/1-3-metadata-validation-hard-fails.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add a metadata validator entry point that validates the Story 1.1 `versions.yaml` contract and accepts fixture paths.
- Keep schema and static policy checks in a shared metadata library so later generator and resolver stories can call the same gate.
- Cover every hard-fail rule with deterministic fixtures and wire the validator into `make validate`.

### Debug Log

- 2026-06-09: Started Story 1.3 from baseline `cae19b0`.
- 2026-06-09: Added `common.sh`, `metadata.sh`, `validate-metadata.sh`, metadata fixture runner, and all required metadata fixtures.
- 2026-06-09: Initial fixture run showed `invalid-latest-eligible-missing-18-trixie.yaml` failed first on incomplete matrix coverage. Updated the validator to hard-fail missing `latest_eligible` directly on the `18-trixie` row for a more precise policy diagnostic.
- 2026-06-09: Added the missing `publish-true-missing-required-platform.yaml` fixture and adjusted `missing-platforms.yaml` to prove empty platform lists hard-fail.
- 2026-06-09: Required validation passed: `validate-metadata.sh`, `tests/metadata/run.sh`, `make validate`, and `git diff --check`.
- 2026-06-09: Addressed BMad code review findings: enforced `pg_version` and `cnpg_tag` consistency with the PG/Debian row, made publishable platform checks order-independent, and rejected whitespace-only publish-critical values.
- 2026-06-09: Re-ran `validate-metadata.sh`, `tests/metadata/run.sh`, `make validate`, and `git diff --check` successfully after review fixes.
- 2026-06-10: Hardened metadata validation to reject empty/non-string `image.registry` and `image.repository`, reject unsupported extension `validation_mode` even when `creatable: true`, and fail `validate-metadata.sh` with controlled argument diagnostics when more than one metadata path or an empty explicit metadata path is passed.
- 2026-06-10: Replaced the brittle text scan for Makefile wiring with a sandboxed `make validate` fail-fast proof that `validate-metadata.sh` runs before downstream validators.

### Completion Notes

- Metadata validation now rejects unsupported PostgreSQL majors, plain `19`, unmarked `19beta1`, Alpine, `bullseye`, other Debian variants, invalid platform sets, malformed rows, duplicate or missing matrix rows, bad `latest_eligible` policy, unsafe publishable rows, and skipped rows without a reason.
- Metadata validation also ensures `pg_version` belongs to `pg_major`, `cnpg_tag` matches `<pg_version>-standard-<debian_variant>`, and publishable resolver-owned/build-critical values are not empty or whitespace-only.
- Metadata validation now also ensures `image.registry` and `image.repository` are usable non-empty strings, and that extension validation modes are constrained for both creatable and non-creatable extension policy entries.
- Story 1.3 intentionally does not perform upstream CNPG image, TimescaleDB package, Toolkit package, or per-architecture package availability checks; those remain owned by Stories 2.1 and 2.2.
- `latest_eligible` remains a policy marker for `18-trixie` and does not require `publish: true` while resolver-owned values are still empty.

### Latest Validation

- `bash cloudnative-pg-timescaledb/scripts/validate-metadata.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/metadata/run.sh` - passed.
- `shellcheck -x cloudnative-pg-timescaledb/scripts/lib/metadata.sh cloudnative-pg-timescaledb/scripts/validate-metadata.sh cloudnative-pg-timescaledb/tests/metadata/run.sh` - passed.
- `make validate` - passed.

## File List

- `cloudnative-pg-timescaledb/scripts/lib/common.sh`
- `cloudnative-pg-timescaledb/scripts/lib/metadata.sh`
- `cloudnative-pg-timescaledb/scripts/validate-metadata.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/metadata/run.sh`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/valid.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/missing-top-level-key.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-current-major.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-primary-debian-variant.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-allowed-postgres-majors.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-allowed-debian-variants.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/wrong-allowed-platforms.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-field-types.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-pg-version-mismatch.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-cnpg-tag-variant-mismatch.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/duplicate-pg-debian-row.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/missing-required-pg-debian-row.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/missing-required-field.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-debian-variant-alpine.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-debian-variant-bullseye.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-debian-variant-non-debian.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-postgres-major.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/unmarked-pg19beta1.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-postgres-major-19.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-latest-eligible-not-18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-latest-eligible-missing-18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-latest-eligible-multiple.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/invalid-platform.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/missing-platforms.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/publish-true-missing-required-platform.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/publish-true-empty-resolver-owned.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/publish-true-whitespace-resolver-owned.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/publish-true-empty-cnpg-tag.yaml`
- `cloudnative-pg-timescaledb/tests/metadata/fixtures/publish-false-without-skip-reason.yaml`

## Change Log

- 2026-06-09: Implemented Story 1.3 metadata schema and static policy validation gate.
- 2026-06-09: Added deterministic metadata fixtures for valid metadata and every story-owned hard-fail class.
- 2026-06-09: Wired metadata validation into `make validate` while leaving upstream availability checks to Epic 2.
- 2026-06-09: Hardened static policy validation after code review so mismatched CNPG tags, mismatched PG versions, whitespace-only publish fields, and order-only platform differences are handled correctly.
- 2026-06-10: Hardened image registry/repository validation, extension validation modes, validator argument handling, and Make metadata gate proof after additional code review.
