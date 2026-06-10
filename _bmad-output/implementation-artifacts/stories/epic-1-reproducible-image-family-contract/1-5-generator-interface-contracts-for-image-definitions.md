---
storyId: 1.5
storyKey: 1-5-generator-interface-contracts-for-image-definitions
epic: 1
title: 'Generator Interface Contracts for Image Definitions'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: 843e417
---

# Story 1.5: Generator Interface Contracts for Image Definitions

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 1.1-1.4 in this epic may be assumed complete.

## Out of Scope

- Full Dockerfile package install behavior (Epic 3)
- `Final CI matrix build/publish workflow behavior (Epic 4)`
- Final catalog digest behavior (Story 4.6)
- Final generated docs validation (Epic 5)

## Source Story

### Story 1.5: Generator Interface Contracts for Image Definitions

As a maintainer,
I want deterministic generator interfaces and skeleton outputs,
So that later Dockerfile, Bake, matrix, catalog, and docs generators extend one metadata-derived contract rather than creating competing implementations.

**Acceptance Criteria:**

**Given** valid metadata
**When** `make generate` runs
**Then** the repository exposes deterministic generator entry points for Dockerfiles, Bake, matrix, catalog, and docs under `cloudnative-pg-timescaledb/scripts/`.
**And** skeleton generated outputs are derived from `versions.yaml` and preserve PostgreSQL major isolation, Debian variant isolation, `publish`, `experimental`, and platform metadata.
**And** each generator writes compact JSON to stdout when used as a machine interface and writes human diagnostics to stderr or a summary file.
**And** generator output schemas are documented with required keys and consumers reject missing keys rather than recomputing tags, digests, or paths independently.
**And** generated outputs are reproducible from a clean checkout for the Epic 1 scope.
**And** later stories extend these generator contracts rather than introducing separate handwritten workflow rows or duplicate tag/catalog logic.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`
- `cloudnative-pg-timescaledb/scripts/generate-bake.sh`
- `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`
- `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`
- `cloudnative-pg-timescaledb/scripts/generate-docs.sh`
- `docs/generator-contracts.md`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-missing-dockerfile.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-missing-target.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-missing-include-key.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-wrong-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-missing-catalog-path.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-wrong-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-missing-doc-path.json`
- `cloudnative-pg-timescaledb/generated/17/trixie/Dockerfile`
- `cloudnative-pg-timescaledb/generated/17/bookworm/Dockerfile`
- `cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile`
- `cloudnative-pg-timescaledb/generated/18/bookworm/Dockerfile`
- `cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile`
- `cloudnative-pg-timescaledb/generated/19beta1/bookworm/Dockerfile`
- `cloudnative-pg-timescaledb/docker-bake.hcl`
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml`
- `cloudnative-pg-timescaledb/docs/generated/compatibility.md`

## Generator CLI and Schema Contract

All generator scripts must support:

- `--metadata cloudnative-pg-timescaledb/versions.yaml`
- `--output <path>` when the generator writes a single file or output root
- `--check` to compare generated output with committed output without modifying files
- `--json` to emit compact machine JSON to stdout
- human diagnostics to stderr

Each generator must document and emit one compact JSON summary with the required keys below. `cloudnative-pg-timescaledb/tests/generators/run.sh` must validate positive fixtures and must fail each missing-key fixture with diagnostics that include command, artifact path, expected key, actual payload, and remediation.

Minimum `generate-dockerfiles.sh --json` schema:

```json
{
  "dockerfiles": [
    {
      "pg_major": "18",
      "debian_variant": "trixie",
      "dockerfile": "cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile",
      "source_entry": "18-trixie",
      "publish": false,
      "experimental": false,
      "skip_reason": "Pending Story 2 resolver population"
    }
  ]
}
```

Minimum `generate-bake.sh --json` schema:

```json
{
  "bake_file": "cloudnative-pg-timescaledb/docker-bake.hcl",
  "targets": [
    {
      "name": "pg18-trixie",
      "context": ".",
      "dockerfile": "cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile",
      "platforms": ["linux/amd64", "linux/arm64"],
      "publish": false,
      "experimental": false
    }
  ]
}
```

Minimum `generate-matrix.sh --json` schema:

```json
{
  "include": [
    {
      "pg_major": "18",
      "pg_version": "18.4",
      "debian_variant": "trixie",
      "platforms": ["linux/amd64", "linux/arm64"],
      "dockerfile": "cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile",
      "bake_target": "pg18-trixie",
      "publish": false,
      "experimental": false,
      "latest_eligible": true,
      "skip_reason": "Pending Story 2 resolver population"
    }
  ]
}
```

Minimum `generate-catalog.sh --json` schema:

```json
{
  "catalogs": [
    {
      "debian_variant": "trixie",
      "catalog_path": "cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml",
      "entries": [
        {
          "pg_major": "18",
          "image": "ghcr.io/<owner>/<image>:18-pg18.4-ts2.27.2-20260609",
          "digest": "",
          "publish": false,
          "experimental": false,
          "latest_eligible": true,
          "skip_reason": "Pending Story 2 resolver population"
        }
      ]
    }
  ]
}
```

Minimum `generate-docs.sh --json` schema:

```json
{
  "docs": [
    {
      "doc_path": "cloudnative-pg-timescaledb/docs/generated/compatibility.md",
      "source": "cloudnative-pg-timescaledb/versions.yaml",
      "sections": ["compatibility"],
      "publishable_entries": 0,
      "experimental_entries": 2
    }
  ]
}
```

Minimum skeleton output rules:

- Dockerfile skeletons are generated for every `entries[]` record in `versions.yaml`; initial skeletons cover exactly `17-trixie`, `17-bookworm`, `18-trixie`, `18-bookworm`, `19beta1-trixie`, and `19beta1-bookworm`.
- Dockerfile skeletons may contain non-buildable marker comments until Story 3.1, but paths must be stable and metadata-derived.
- `docker-bake.hcl` may contain disabled/skeleton targets until Story 3.3, but target names and contexts must be metadata-derived.
- Catalog skeletons may contain empty or draft entries until Story 4.6, but filenames and top-level resource shape must be stable.
- Generated docs skeletons may contain generated table headings until Epic 5, but source markers must be stable.
- Consumers must fail on missing required JSON keys rather than recomputing them independently.
- Generator contracts must preserve `latest_eligible` exactly from metadata and must enforce that `18-trixie` is the sole `latest_eligible: true` row; every other PostgreSQL/Debian row must be `latest_eligible: false`.

## Required Validation Commands

- make generate
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh`

Full `make validate` is not required to pass for Story 1.5 until Story 1.6 wires generated drift validation. Story 1.5 must still leave `make generate` and the generator schema tests passing from a clean checkout.

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/generators/run.sh` must validate the exact positive, missing-key, and wrong-latest fixtures listed in Expected Artifacts for Dockerfiles, Bake, matrix, catalog, and docs generators.
- Include one positive fixture and at least one negative fixture for each generator schema hard-fail rule introduced by this story, including failure when `18-trixie` is not the sole `latest_eligible: true` row.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement generator entry-point scripts for Dockerfiles, Bake, matrix, catalog, and generated docs with shared metadata and tag-library consumption.
- [x] Generate the Epic 1 skeleton outputs for all required PG/Debian rows while preserving `publish`, `experimental`, `platforms`, `skip_reason`, and source-entry identity.
- [x] Preserve and validate latest eligibility so generated matrix and catalog outputs mark only PG18 `trixie` as `latest_eligible: true` and all PG17, PG19beta1, and `bookworm` rows as `false`.
- [x] Document every generator CLI and compact JSON schema in `docs/generator-contracts.md`, including stdout/stderr machine-interface rules.
- [x] Add generator fixture tests for every positive schema and every missing-key rejection case listed in Expected Artifacts.
- [x] Wire `make generate` to the generator scripts and run `make generate` plus the generator fixture suite from a clean checkout.

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
| FR-12 | 1.5, 4.1, 4.2, 5.9 | matrix schema, workflow `fromJSON`, release metadata artifacts | `generate-matrix.sh`, workflow validation, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-2 Reproducibility | 1.1, 1.3, 1.5, 1.6, 3.1, 4.2, 4.4, 5.9 | Metadata, digests, package versions, platforms, tags, generated outputs, and release evidence explain each image after the fact. |
| NFR-4 Maintainability | 1.1, 1.2, 1.5, 2.1, 2.2, 4.1, 5.6 | PostgreSQL majors and Debian variants are metadata-driven; Makefile targets delegate to scripts; workflows do not duplicate matrix, resolver, tag, or catalog logic. |
| Metadata source of truth | 1.1, 1.3, 1.5, 5.6 | `cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited image source of truth. |
| Generated artifacts | 1.5, 1.6, 3.1, 4.1, 4.6, 5.7, 5.9 | Dockerfiles, Bake file, matrix JSON, catalogs, docs tables, and README examples are generated or validated and drift-checked. |
| NFR-2 Reproducibility | 1.5 | Generator contracts define stable paths and JSON schemas for Dockerfiles, Bake targets, matrices, catalogs, and docs so later automation consumes committed deterministic outputs. |
| NFR-4 Maintainability | 1.5 | Later stories extend generator entrypoints and schemas instead of adding handwritten workflow rows, duplicate tag logic, or duplicate catalog logic. |
| NFR-8 Automation safety | 1.5 | `--check` mode and schema fixtures make stale or malformed generated skeleton outputs fail before builds or release workflows run. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-1-reproducible-image-family-contract/1-5-generator-interface-contracts-for-image-definitions.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add five stable generator entrypoints and keep shared parsing/rendering/schema behavior in one generator contract helper.
- Generate skeleton Dockerfiles, Bake, matrix, catalog, and compatibility docs from `versions.yaml` only.
- Add schema fixtures and a generator test runner that rejects missing keys and wrong `latest_eligible` propagation.

### Debug Log

- 2026-06-09: Started Story 1.5 from baseline `843e417`.
- 2026-06-09: Added `generator_contract.py` plus `generate-dockerfiles.sh`, `generate-bake.sh`, `generate-matrix.sh`, `generate-catalog.sh`, and `generate-docs.sh` wrappers.
- 2026-06-09: Ran `make generate` to produce all Epic 1 skeleton outputs from metadata.
- 2026-06-09: Added `docs/generator-contracts.md` and generator JSON schema fixtures for positive, missing-key, and wrong-latest cases.
- 2026-06-09: Updated the Story 1.2 parameter regression test so `generate` is no longer expected to be unavailable after Story 1.5 implements it.
- 2026-06-09: Required validation passed: `make generate` and `bash cloudnative-pg-timescaledb/tests/generators/run.sh`.
- 2026-06-09: Additional `make validate` was attempted but is currently blocked by unrelated unstaged Story 1.1 hardening fixtures in the working tree; Story 1.5 explicitly defers full `make validate` to Story 1.6.
- 2026-06-09: Addressed BMad code review findings: `--check --json` now performs drift checks, `--output` is reflected in Bake and docs JSON summaries, and schema validation requires exact generator row coverage.
- 2026-06-09: Re-ran `make generate`, `tests/generators/run.sh`, shell syntax checks, Python compilation, and `git diff --check` successfully after review fixes.
- 2026-06-10: Re-opened Story 1.5 under the full BMAD dev-story/code-review loop and validated the implemented contracts against later Story 3.1 and Story 4.6 ownership.
- 2026-06-10: Addressed review findings for structured metadata diagnostics, skipped matrix `dockerfile`/`bake_target` fields, exact latest validation across `include[] + skipped[]`, read-only generator schema tests, deterministic release rehearsal report generation, exact generator contract docs validation, and release rehearsal report drift checks in both `validate-generated` and `make generate --check`.
- 2026-06-10: Addressed final acceptance review finding by updating the standalone matrix validator and Story 4.1 matrix tests to reject skipped rows missing `dockerfile`/`bake_target` and to evaluate latest eligibility across `include[] + skipped[]`.
- 2026-06-10: Tightened the shared matrix validator further so `skipped` is a required top-level array and no skipped row, including `18-trixie`, may carry `latest_eligible: true`.
- 2026-06-10: Preserved later Story 3.1 behavior where `publish:false` rows emit deterministic `Dockerfile.skipped.json` markers instead of buildable Dockerfiles, and later Story 4.6 behavior where stable catalogs render only release-complete digest-pinned PG17/PG18 records from release metadata.
- 2026-06-10: Addressed final BMAD review findings for release catalog safety: partial release metadata now fails before catalog generation or validation, stable catalog YAML keeps existing digest-pinned entries when release metadata exists, and release rehearsal report writes use a same-directory temporary file plus atomic rename after path containment checks.
- 2026-06-10: Validation passed: `bash cloudnative-pg-timescaledb/tests/catalog/run.sh`, `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`, `shellcheck -x cloudnative-pg-timescaledb/scripts/release-rehearsal.sh cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh cloudnative-pg-timescaledb/tests/catalog/run.sh`, `make generate GENERATE_ARGS=--check`, `git diff --check`, and full `make validate`.

### Completion Notes

- Generator outputs preserve PostgreSQL major, Debian variant, platforms, `publish`, `experimental`, `latest_eligible`, `skip_reason`, and source-entry identity.
- Matrix schema validation requires `18-trixie` to be the sole `latest_eligible: true` row across both publishable and skipped rows.
- Generator `--json` emits compact machine JSON to stdout; human generation diagnostics go to stderr.
- `--check` compares generated content to committed skeleton outputs and fails on drift.
- Combining `--check` and `--json` still validates committed output before emitting machine JSON, so consumers cannot bypass drift checks.
- Generator schema validation rejects missing rows, duplicate rows, missing catalog variants, missing keys, and wrong matrix latest eligibility instead of accepting partial payloads.
- Metadata entry schema validation now fails with structured `command/artifact/expected/actual/remediation` diagnostics before downstream code indexes missing keys.
- Skipped matrix rows expose stable `dockerfile` and `bake_target` fields so downstream workflows do not recompute paths or targets.
- `make generate` now regenerates `release-rehearsal-report.md` from deterministic fixture evidence and replaces `docs/generated` atomically instead of preserving stale generated docs from a prior checkout.
- `validate-generated` exact-checks `docs/generator-contracts.md` and release rehearsal report contents, while `make generate --check` also fails stale release rehearsal reports.
- Final repo behavior intentionally reflects later story supersession: `publish:false` PG19beta1 rows use `Dockerfile.skipped.json` markers, and stable catalogs remain digest-aware, rendering only release-complete PG17/PG18 records when release metadata exists.
- Release metadata directories must be complete for every publishable stable PostgreSQL/Debian row before catalog generation or validation can succeed; partial catalog output is rejected.
- Release rehearsal report generation rejects explicit checkout escape paths and symlink report files, then writes via atomic replacement to avoid following a changed report target at write time.

## File List

- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/build.sh`
- `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`
- `cloudnative-pg-timescaledb/scripts/generate-bake.sh`
- `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`
- `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`
- `cloudnative-pg-timescaledb/scripts/generate-docs.sh`
- `cloudnative-pg-timescaledb/scripts/generate.sh`
- `cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`
- `cloudnative-pg-timescaledb/scripts/validate-docs.sh`
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `cloudnative-pg-timescaledb/scripts/validate-matrix-json.py`
- `cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh`
- `docs/generator-contracts.md`
- `cloudnative-pg-timescaledb/tests/bake/run.sh`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/skipped-combination.json`
- `cloudnative-pg-timescaledb/tests/bake/fixtures/valid-publishable-targets.json`
- `cloudnative-pg-timescaledb/tests/catalog/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `cloudnative-pg-timescaledb/tests/generated-drift/run.sh`
- `cloudnative-pg-timescaledb/tests/matrix/run.sh`
- `cloudnative-pg-timescaledb/tests/update/run.sh`
- `cloudnative-pg-timescaledb/tests/barman-plugin/run.sh`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-missing-dockerfile.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-missing-row.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-missing-target.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-missing-include-key.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-duplicate-row.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-wrong-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-missing-catalog-path.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-missing-variant.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-wrong-latest-eligible.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-missing-doc-path.json`
- `cloudnative-pg-timescaledb/tests/matrix/fixtures/valid-publishable-matrix.json`
- `cloudnative-pg-timescaledb/generated/17/trixie/Dockerfile`
- `cloudnative-pg-timescaledb/generated/17/bookworm/Dockerfile`
- `cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile`
- `cloudnative-pg-timescaledb/generated/18/bookworm/Dockerfile`
- `cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/generated/19beta1/bookworm/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/docker-bake.hcl`
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml`
- `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml`
- `cloudnative-pg-timescaledb/docs/generated/compatibility.md`
- `cloudnative-pg-timescaledb/docs/generated/matrix-schema.md`

## Change Log

- 2026-06-09: Implemented Story 1.5 generator interface contracts and metadata-derived skeleton outputs.
- 2026-06-09: Added generator schema documentation and fixture tests for missing keys and wrong latest eligibility.
- 2026-06-09: Enabled `make generate` now that generator entrypoints exist.
- 2026-06-09: Hardened generator contract validation after code review for check-json drift, custom output JSON paths, exact row coverage, duplicate rows, and missing catalog variants.
- 2026-06-10: Hardened Story 1.5 closure after repeated BMAD review rounds: structured metadata diagnostics, skipped matrix path/target fields, deterministic docs generation, release rehearsal report drift checks, exact contract docs validation, and read-only generator schema tests.
