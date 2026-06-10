---
storyId: 1.1
storyKey: 1-1-scaffold-and-versions-metadata-contract
epic: 1
title: 'Scaffold and Versions Metadata Contract'
status: complete
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: 2425d6d099de46c2889ecb91aa5e6046be1f6d63
---

# Story 1.1: Scaffold and Versions Metadata Contract

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- No previous story dependency. This is the first implementation story.

## Out of Scope

- Root Makefile implementation (Story 1.2)
- Metadata validator implementation (Story 1.3)
- Tag library and generated drift validation (Stories 1.4-1.6)

## Source Story

### Story 1.1: Scaffold and Versions Metadata Contract

As a maintainer,
I want the `cloudnative-pg-timescaledb/` source tree and `versions.yaml` metadata contract,
So that supported PostgreSQL and Debian image lines have one inspectable source of truth.

**Acceptance Criteria:**

**Given** a clean repository checkout
**When** the story is implemented
**Then** `cloudnative-pg-timescaledb/versions.yaml` exists and is documented as the only hand-edited source of truth.
**And** metadata includes PostgreSQL `17`, PostgreSQL `18`, and experimental PostgreSQL `19beta1`.
**And** Debian variants are limited to primary `trixie` and secondary `bookworm`.
**And** required fields exist for each image entry: `pg_major`, `pg_version`, `debian_variant`, `cnpg_tag`, `cnpg_digest`, `timescaledb_version`, `timescaledb_package_version`, `toolkit_version`, `toolkit_package_version`, `platforms`, `publish`, `experimental`, `latest_eligible`, and `skip_reason`.
**And** `cloudnative-pg-timescaledb/README.md` and `docs/generated-files.md` name `versions.yaml` as the only hand-edited source of truth.
**And** validation fails if docs name Dockerfiles, workflow matrices, catalogs, generated docs, or README tables as independent hand-edited sources of truth.
**And** `vendor/` is reference-only and is not used as a build context or runtime dependency.

## Expected Artifacts

- `cloudnative-pg-timescaledb/versions.yaml`
- `cloudnative-pg-timescaledb/README.md`
- `docs/generated-files.md`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/valid-minimal.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-missing-top-level.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-missing-required-entry-field.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-pg19beta1-not-experimental.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-latest-eligible-not-18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-latest-eligible-missing-18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-empty-resolver-owned-without-skip.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-build-context.md`
- `cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`

## Metadata Schema Contract

`cloudnative-pg-timescaledb/versions.yaml` must use this minimum shape so later validators and generators do not invent a competing schema:

```yaml
schema_version: "1"
image:
  registry: ghcr.io
  repository: <owner>/<image-name>
  current_major: "18"
  primary_debian_variant: trixie
allowed:
  postgres_majors: ["17", "18", "19beta1"]
  debian_variants: ["trixie", "bookworm"]
  platforms: ["linux/amd64", "linux/arm64"]
entries:
  - pg_major: "18"
    pg_version: "18.4"
    debian_variant: trixie
    cnpg_tag: "18.4-standard-trixie"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: false
    latest_eligible: true
    skip_reason: "Pending Story 2 resolver population"
```

Minimum schema rules for this story:

- `schema_version`, `image`, `allowed`, and `entries` are required top-level keys.
- `entries` is a non-empty list.
- Each `entries[]` object contains every required field from the Source Story AC.
- `pg_major`, `pg_version`, `debian_variant`, `cnpg_tag`, `cnpg_digest`, version fields, and `skip_reason` are strings.
- `platforms` is a non-empty list of strings drawn from `allowed.platforms`.
- `publish`, `experimental`, and `latest_eligible` are booleans.
- Required initial entries are exactly `17-trixie`, `18-trixie`, `19beta1-trixie`, `17-bookworm`, `18-bookworm`, and `19beta1-bookworm`.
- `19beta1` entries must set `experimental: true`.
- Exactly the `18-trixie` entry must set `latest_eligible: true`; every other required entry must set `latest_eligible: false`. Story 1.4 later owns full tag generation and publish-time tag enforcement.
- Resolver-owned values may be empty only when `publish: false` and `skip_reason` is non-empty. Later resolver stories replace those values.
- `cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh` must validate every rule in this section using the fixture files named in Expected Artifacts. Story 1.3 later promotes these same rules into the reusable production `validate-metadata.sh` validator.
- `cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh` must hard-fail if any non-vendor Dockerfile, workflow, script, or docs example treats `vendor/` as a build context, runtime input, copied source tree, or package source. Plain text that labels `vendor/` as reference-only is allowed.

## Required Validation Commands

- `test -f cloudnative-pg-timescaledb/versions.yaml`
- `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`
- `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh` must run every metadata and docs fixture listed in Expected Artifacts.
- Include positive validation for `valid-minimal.yaml` and negative validation for missing top-level metadata, missing required entry fields, unmarked PostgreSQL `19beta1`, invalid `latest_eligible` on any row other than `18-trixie`, missing `latest_eligible: true` on `18-trixie`, empty resolver-owned values without `skip_reason`, competing source-of-truth docs, and vendor build-context usage.
- Include one positive fixture and at least one negative fixture for each hard-fail rule introduced by this story.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Add Story 1.1 test runner and fixtures for metadata schema, source-of-truth docs, and vendor reference-only behavior.
- [x] Add `cloudnative-pg-timescaledb/versions.yaml` with the required initial PostgreSQL/Debian metadata entries and scaffold-safe values.
- [x] Add `cloudnative-pg-timescaledb/README.md` and `docs/generated-files.md` documenting `versions.yaml` as the only hand-edited source of truth.
- [x] Run all required validation commands and update Dev Agent Record, File List, Change Log, and status.

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
| FR-2 | 1.1, 1.3, 2.1, 2.2, 4.1, 5.1 | Debian variant metadata, resolver fixtures, matrix JSON, docs tables | `validate-metadata.sh`, resolver tests, `generate-matrix.sh` |
| FR-4 | 1.1, 1.3, 1.4, 1.5, 2.2, 4.1, 4.6, 5.1, 5.9 | experimental metadata, generator contracts, resolver fixtures, catalog policy, docs | `validate-metadata.sh`, `validate-tags.sh`, catalog validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-2 Reproducibility | 1.1, 1.3, 1.5, 1.6, 3.1, 4.2, 4.4, 5.9 | Metadata, digests, package versions, platforms, tags, generated outputs, and release evidence explain each image after the fact. |
| NFR-4 Maintainability | 1.1, 1.2, 1.5, 2.1, 2.2, 4.1, 5.6 | PostgreSQL majors and Debian variants are metadata-driven; Makefile targets delegate to scripts; workflows do not duplicate matrix, resolver, tag, or catalog logic. |
| Metadata source of truth | 1.1, 1.3, 1.5, 5.6 | `cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited image source of truth. |
| Debian scope | 1.1, 1.3, 2.1, 2.2, 3.4, 5.1, 5.9 | Only `trixie` and `bookworm` are accepted; Alpine, `bullseye`, and other variants hard-fail. |
| PostgreSQL scope | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.9 | `17`, `18`, and experimental `19beta1` are supported according to metadata and release gates. |
| NFR-2 Reproducibility | 1.1 | `versions.yaml` records PostgreSQL major, Debian variant, platforms, publish state, and resolver-owned version fields in a deterministic schema. |
| NFR-4 Maintainability | 1.1 | New PostgreSQL majors and Debian variants start from metadata entries rather than hand-created Dockerfile or workflow copies. |
| NFR-8 Automation safety | 1.1 | Documentation validation prevents generated Dockerfiles, workflow matrices, catalogs, generated docs, or README tables from becoming competing hand-edited sources of truth. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-1-reproducible-image-family-contract/1-1-scaffold-and-versions-metadata-contract.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Write a story-specific shell test runner that validates the scaffold schema and documentation rules without introducing the later production validator owned by Story 1.3.
- Keep implementation deterministic from a clean checkout by using a repo-provided parser path or a declared project validation dependency; the story test runner must not rely on optional, undeclared PyYAML availability.
- Create only scaffold-safe metadata: all resolver-owned package/digest fields remain empty with `publish: false` and non-empty `skip_reason`.

### Debug Log

- 2026-06-09: Started Story 1.1 from baseline `2425d6d099de46c2889ecb91aa5e6046be1f6d63`.
- 2026-06-09: RED validation failed as expected before scaffold files existed: missing `cloudnative-pg-timescaledb/versions.yaml`.
- 2026-06-09: Fixed test runner project scan so negative fixtures are not treated as product files.
- 2026-06-09: Required validation passed: `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, and `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`.
- 2026-06-09: Addressed first code review pass: expanded source-of-truth fixtures, vendor misuse patterns, duplicate/missing matrix checks, unsupported value/type checks, publishable-without-digest fixture, and deterministic diagnostics.
- 2026-06-09: Re-ran `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh` and shell syntax validation successfully after review fixes.
- 2026-06-09: Addressed second code review pass: ensured all docs fixtures run, structured shell-level diagnostics, added project vendor prune, stronger vendor command patterns, unconditional `publish: false`, YAML structure guards, general Markdown source-of-truth scan, and targeted edge fixtures.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh` and `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh` successfully after second review fixes.
- 2026-06-09: Addressed third code review pass: added `image.registry`/`image.repository` validation, Make/Bake/HCL/config vendor scanning, narrowed general Markdown scan to conflict-only mode, enumerated docs fixtures explicitly, and added missing-image-field fixture.
- 2026-06-09: Re-ran Story 1.1 syntax and validation successfully after third review fixes.
- 2026-06-09: Addressed fourth code review pass: added scaffold `pg_version`/`cnpg_tag` consistency checks, negative fixture existence enforcement, and mismatched-version-tag fixture.
- 2026-06-09: Re-ran Story 1.1 syntax and validation successfully after fourth review fixes.
- 2026-06-09: Addressed fifth code review pass: added JSON vendor context coverage, resolver-owned empty-field enforcement, source-of-truth paraphrase checks, and safe generated-from-versions docs fixture.
- 2026-06-09: Re-ran Story 1.1 syntax and validation successfully after fifth review fixes.
- 2026-06-09: Addressed sixth code review pass: added stable PostgreSQL experimental guard, whitespace-only `skip_reason` rejection, plural/reverse source-of-truth checks, vendor negation handling, plural runtime dependency checks, and targeted fixtures.
- 2026-06-09: Fixed validation regression where `Do not run docker build vendor/` was still treated as vendor misuse by checking negation within the current sentence/line before the matched pattern.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, and `git diff --check` successfully after sixth review fixes.
- 2026-06-09: Addressed seventh code review pass: restored the Story 1.1 `latest_eligible` contract for exactly `18-trixie`, removed the PyYAML dependency by adding a stdlib parser for the Story 1.1 YAML subset, required exact per-entry platform coverage, added Buildx/runtime-dependency vendor fixtures, narrowed product scans to Story 1.1-owned paths, and strengthened source-of-truth positive/negative checks.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and `git diff --check` successfully after seventh review fixes.
- 2026-06-09: Triaged seventh Blind Hunter Make/CI wiring finding as out-of-scope for Story 1.1 because root Makefile implementation is explicitly owned by Story 1.2.
- 2026-06-09: Addressed eighth code review pass: narrowed docs source-of-truth negation handling, made vendor prohibition negation local to the matched phrase, covered absolute vendor build contexts, added unknown metadata key rejection, and added targeted positive/negative fixtures.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and `git diff --check` successfully after eighth review fixes.
- 2026-06-09: Addressed ninth code review pass: made unquoted numeric YAML scalars fail string-field checks, switched vendor scans to inspect every regex match, added vendored Dockerfile path coverage, moved docs source-of-truth conflict checks to clause-level evaluation, and required negative fixtures to match intended diagnostics through `expect_fail --contains`.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and `git diff --check` successfully after ninth review fixes.
- 2026-06-09: Addressed tenth code review pass: tightened direct source-of-truth negation semantics, added comma-subject conflict coverage, added Docker Compose short-form `build: ./vendor` coverage, and made the unrelated-not fixture include the positive `versions.yaml` claim so it fails on the intended competing-source invariant.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and `git diff --check` successfully after tenth review fixes.
- 2026-06-09: Addressed eleventh code review pass: made late-added fixtures self-contained in the review diff, excluded nested `cloudnative-pg-timescaledb/vendor/**` from tracked product scans, made vendor safe-negation clause-local, made generic source-of-truth checks clause-local, and added same-line safe-prefix fixtures.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after eleventh review fixes.
- 2026-06-09: Addressed twelfth code review pass: added `and`/`or` safe-prefix source-of-truth and vendor fixtures, constrained vendor command matching to clause-level scanning, added package-source-from-vendor coverage, and limited relative `which is the only hand-edited source of truth` handling to `versions.yaml` antecedents.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after twelfth review fixes.
- 2026-06-09: Addressed thirteenth code review pass: added canonical/authoritative/manual matrix source-of-truth fixtures, comma/then vendor masking fixture, `COPY vendor` no-slash coverage, reverse build-context prose coverage, and positive `COPY --from=vendor` stage-alias coverage.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after thirteenth review fixes.
- 2026-06-09: Addressed fourteenth code review pass: added BuildKit bind mount detection, vendor-tree/vendored-examples natural-language misuse fixtures, pure canonical/authoritative generated artifact checks, synonym negation fixtures, and tightened package-source matching to avoid valid README language.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after fourteenth review fixes.
- 2026-06-09: Addressed ninth BMad code review pass: rejected duplicate YAML mapping keys, made metadata negative fixture checks assert their intended diagnostics, added duplicate-key fixture coverage, and replaced working-tree product scans with git-indexed non-vendor product file scans.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, and `git diff --check` successfully after ninth review fixes.
- 2026-06-09: Addressed latest BMad code review pass: accepted generic source-of-truth/canonical safe negations, added `runtime inputs ... from vendor/` detection, added explicit vendor build-context safe negations, and expanded product script scanning to extensionless script paths.
- 2026-06-09: Re-ran `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, and scoped `git diff --check` successfully after latest review fixes.
- 2026-06-09: Addressed follow-up BMad code review pass: switched vendor safe-negation handling to match-local evaluation, added alternate container builder detection, added workflow `uses: ./vendor` detection, added Dockerfile variant path scan checks, strengthened source-of-truth diagnostics, and excluded local `__pycache__`/`.pyc` files from untracked product scans.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after follow-up review fixes.
- 2026-06-09: Addressed second follow-up BMad code review pass: limited product scans to Story 1.1-owned paths, fixed nested Makefile matching, avoided prose false positives for lowercase `add vendor/`, added shebang file scanning, covered Docker build `--file=vendor/...` with dot context, and expanded vendored-examples/source-of-truth edge fixtures.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after second follow-up review fixes.
- 2026-06-09: Addressed third follow-up BMad code review pass: added inline YAML comment support for scaffold metadata, covered inherited/pronoun source-of-truth claims, accepted negated `serve as source of truth` prose, added workflow-matrix/README-table authoritative wording fixtures, covered lowercase Dockerfile `copy`, multiline config `context: vendor`, and Make/script archive vendor path usage.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after third follow-up review fixes.
- 2026-06-09: Addressed fourth follow-up BMad code review pass: covered modal canonical/authoritative source-of-truth claims, modal pronoun follow-ups, shell line-continuation vendor builds, `docker buildx bake -f vendor/...`, vendor config include/file imports, imperative `Never use vendor/ as ...` safe negation, and comma-elided generated-artifact negation.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after fourth follow-up review fixes.
- 2026-06-09: Addressed fifth follow-up BMad code review pass: added targeted metadata fixtures for empty `entries` and numeric entry string fields, split source-of-truth checks on `and`/`or` without losing inherited predicates, added pronoun authority coverage for image combinations/supported versions, detected parent-relative vendor build contexts, and covered Markdown Dockerfile instruction examples.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after fifth follow-up review fixes.
- 2026-06-09: Addressed sixth follow-up BMad code review pass: removed out-of-scope Story 1.1 hard-fails for exact `pg_version`/`cnpg_tag` scaffold formatting, kept only required string-field validation, refined Dockerfile `COPY` detection to source operands, allowed `COPY --from=vendor` stage aliases and vendor destination paths, rejected `docker image build vendor/`, and avoided false positives for vendor label/build-arg values.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after sixth follow-up review fixes.
- 2026-06-09: Addressed seventh follow-up BMad code review pass: included `.github/workflows/**` in Story 1.1 vendor scans, added bare canonical/authoritative docs checks, covered Dockerfile JSON `COPY ["vendor/", ...]`, lowercase Markdown list copy examples, docker build commands with platform/tag options, and preserved safe prohibition handling across sentence boundaries.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after seventh follow-up review fixes.
- 2026-06-09: Addressed eighth follow-up BMad code review pass: supported inline comments on mapping headers, detected hyphenated `source-of-truth`, bare pronoun authority claims, direct apt/dpkg package files under `vendor/`, BuildKit named contexts, multiline Dockerfile JSON copy forms, lowercase fenced Dockerfile snippets, absolute/normalized/global-option docker build contexts, and leading-slash Dockerfile vendor sources.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after eighth follow-up review fixes.
- 2026-06-09: Addressed ninth follow-up BMad code review pass: normalized wrapped Markdown source-of-truth prose, detected quoted vendor build contexts and Dockerfile flags, detected quoted BuildKit named contexts, detected Markdown multiline JSON `COPY` examples, and expanded workflow `uses:` detection for nested and parent-relative vendor actions.
- 2026-06-09: Re-ran `test -f cloudnative-pg-timescaledb/versions.yaml`, `rg "versions.yaml.*only hand-edited" cloudnative-pg-timescaledb/README.md docs/generated-files.md`, `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, and scoped `git diff --check` successfully after ninth follow-up review fixes.
- 2026-06-09: Addressed tenth follow-up BMad code review pass: rejected unbalanced quoted YAML scalars, detected JSON-form `COPY/ADD` with flags before the source array, detected modal `source of truth` claims edited by hand, and detected reversed `build context comes from vendor/` prose.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 test patch: `bash -n`, `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed eleventh follow-up BMad code review pass: detected `--build-context=deps=vendor`, `docker buildx --builder ... build vendor/`, compose files under `vendor/`, `install vendor/file` runtime copy patterns, and hand-maintained generated-artifact authority prose.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 test patch: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twelfth follow-up BMad code review pass: required non-empty `pg_version`, detected value-less Docker global flags before `build vendor/`, and detected manually edited/maintained generated-artifact claims for image combinations and supported image matrices.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 test patch: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirteenth follow-up BMad code review pass: detected long-form `make --directory` and `tar --directory` vendor inputs, canonical place-to-edit-by-hand docs claims, shell-variable vendor build contexts, HCL `context = join(..., "vendor")`, and `docker build - < vendor/Dockerfile`.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 test patch: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fourteenth follow-up BMad code review pass: removed the accidental `versions.yaml` resolver-owned exemption, detected manually curated generated-doc authority claims, HCL `contexts = { ... vendor }` maps, and direct execution of vendor helper scripts.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 test patch: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifteenth follow-up BMad code review pass: detected Make/Dockerfile variable indirection for vendor build contexts, Docker/Podman runtime bind mounts from `vendor/`, vendored-examples copied-source-tree prose, and added positive safe-negation coverage for vendored examples/vendor tree policy text.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 test patch: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed sixteenth follow-up BMad code review pass: detected manually maintained docs that define/drive/determine image combinations across `and` clauses, normalized `./vendor/.` variable assignments, detected predicate-first vendor tree runtime/package-source prose, and added Dockerfile/Make variable edge fixtures.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 test patch: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed seventeenth follow-up BMad code review pass: scanned all root docs markdown, tightened quoted scalar parsing, added unhyphenated `hand edited` docs checks, direct vendor executable detection, prefixed HCL contexts maps, vendor-subdirectory variable expansion, and shell-extension script scan coverage.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 test patch: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed eighteenth follow-up BMad code review pass: detected same-sentence pronoun source-of-truth claims, shell `export`/`local` vendor build-context variables, split-quoted `$PWD` vendor paths, and `Containerfile` vendor `COPY`; accepted `should not` vendor prohibitions as safe negations.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed nineteenth follow-up BMad code review pass: made new fixtures reproducible in the review diff, rejected canonical metadata-source claims for generated docs/README tables, and detected JSON-form Dockerfile `COPY/ADD` when `vendor/` is any source operand.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twentieth follow-up BMad code review pass: added hand-curated/manually-authored generated-artifact authority checks, Docker Compose `additional_contexts` vendor detection, Dockerfile ARG default vendor substitution, and list-level source-of-truth negation support.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-first follow-up BMad code review pass: added `serve/act as ... metadata source` generated-artifact checks, inline and multi-assignment shell vendor variable expansion, Dockerfile multi-key `ENV` vendor expansion, unhyphenated `hand curated` authority checks, `versions.yaml remains` positive source-of-truth wording, negated canonical-source prose, Compose `additional_contexts` list/map forms, and shell `${VAR:-vendor}` default build-context detection.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-second follow-up BMad code review pass: added `hand-authored` and `maintained manually as the source` generated-artifact authority checks, comma-apposition `versions.yaml` positive source-of-truth wording, Compose `additional_contexts` subdirectory and YAML-anchor detection, shell `${VAR-vendor}` and quoted shell/Dockerfile parameter-default vendor detection, and metadata authority/source checks without adjective prefixes.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-third follow-up BMad code review pass: added negated metadata-source positive docs, `human-maintained` and maintainer-edited generated artifact source checks, Compose flow-list `additional_contexts`, shell `${VAR:+vendor}` alternate-value defaults, assigned vendor variable parameter-expansion forms, YAML sequence/inline-map anchors, and pronoun metadata authority/source follow-up checks.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-fourth follow-up BMad code review pass: added bare metadata-authority negation support, `human-curated`/`human-authored` generated-artifact source checks, HCL named-context subdirectory detection, `source of image metadata` / `authority for image metadata` wording checks, and HCL variable/local indirection detection for vendor build contexts.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-fifth follow-up BMad code review pass: added HCL variable interpolation/join context detection, `source for image combinations` docs checks, safe negation for source/authority of metadata, quoted Docker Compose `additional_contexts` keys, and block-list YAML parsing for entry platform lists.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-sixth follow-up BMad code review pass: added shell array and indirect expansion detection, HCL `format`/`replace` and `${path.module}/vendor` local indirection detection, leading-negation source wording support, Docker Compose folded `additional_contexts`, block-list YAML parsing for `allowed.*`, and plural `sources for image metadata` docs checks.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-seventh follow-up BMad code review pass: added HCL object-local context detection, Compose folded scalar chomping indicators, plural source negation support, Make variable inline-comment expansion, Bash array scalar/multi-element and nameref expansion, and HCL `abspath`/path-module interpolation detection.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-eighth follow-up BMad code review pass: broadened Make `export`/`override`/target-specific variable expansion, Bash `typeset`/`local -n` nameref handling, Fish `set` vendor variables, HCL nested object/path interpolation, and hand-edited image definition docs checks.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed twenty-ninth follow-up BMad code review pass: added Buildx bake `--set *.context=vendor` detection, Fish `set` flag support, GNU Make `private` variable support, deeper HCL local-object indirection, metadata-source verb checks, hand-updated docs wording, and safe negation for hand-edited image definitions.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirtieth follow-up BMad code review pass: added Buildx bake named context `--set` detection, Fish long-flag variable handling, GNU Make `define/endef` variable handling, dotted HCL local-path resolution with unrelated locals, `form`/`constitute` metadata-source checks, and safe negation for metadata-source verbs.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirty-first follow-up BMad code review pass: added GNU Make `define NAME =` and `define NAME :=` handling, Fish list/index variable handling, safe negation for Buildx bake `--set` vendor-context prohibitions, maintained-manually image-definition docs checks, and HCL bracket-indexed local context normalization.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirty-second follow-up BMad code review pass: added `override define`/`export define` Make handling, indexed Bash/Fish list resolution for non-first vendor elements without false positives on non-vendor indexes, and HCL quoted-key bracket local references.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirty-third follow-up BMad code review pass: added negative-index and range handling for Bash/Fish list selections, hyphenated GNU Make variable names, direct HCL vendor context function detection, inline quoted HCL object keys, and generated-artifact `origin of image metadata` wording checks.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirty-fourth follow-up BMad code review pass: added Bash associative/direct/appended array vendor resolution, precise Bash scalar/whole-array/slice handling to avoid non-vendor slice false positives, HCL named-context function detection, and generated-artifact `provenance for image metadata` wording checks.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirty-fifth follow-up BMad code review pass: added direct nonnumeric Bash array assignment handling, associative array declaration/assignment and whole-array handling, Bash spaced negative slice offsets, and provenance/basis metadata-source wording checks.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirty-sixth follow-up BMad code review pass: added quoted Bash associative references, associative whole-array expansion after separate assignments, Fish open-ended ranges, generated outputs/artifacts subject scanning, basis/foundation verb and preposition coverage, and paragraph-boundary preservation for docs scanning.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirty-seventh follow-up BMad code review pass: added Bash compound indexed array parsing, Fish indexed `set NAME[index]` handling, inherited `not canonical, but authoritative` docs checks, HCL local/object function indirection, and generated outputs direct metadata-control wording.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed thirty-eighth follow-up BMad code review pass: modeled Fish indexed/list mutations, rejected source-data and negated-then-positive source-of-truth claims, propagated HCL vendor-valued locals, and re-ran isolated Story 1.1 validation successfully.
- 2026-06-09: Addressed thirty-ninth follow-up BMad code review pass: handled Fish range-subscript assignment mutations, Bash negative indexed assignments, HCL list-index vendor refs, generated-output control wording, and re-ran isolated Story 1.1 validation successfully.
- 2026-06-09: Addressed fortieth follow-up BMad code review pass: tracked non-vendor Bash direct assignment state, added zsh one-based array handling, Make `word` expansion, multiline/function HCL list-index refs, generated-output govern wording, safe control negation, and re-ran isolated Story 1.1 validation successfully.
- 2026-06-09: Addressed forty-first follow-up BMad code review pass: normalized zsh direct indexed assignments, avoided stale numeric vendor overwrite state, added Make firstword/lastword and whole-variable list expansion, object/wrapped HCL list refs, govern conflict detection, and re-ran isolated Story 1.1 validation successfully.
- 2026-06-09: Addressed forty-second follow-up BMad code review pass: protected Make selector arguments from whole-variable replacement, added Make transform detection, quoted-key and inline HCL list fixtures, pronoun govern checks, and re-ran isolated Story 1.1 validation successfully.
- 2026-06-09: Addressed forty-third follow-up BMad code review pass: added same-sentence pronoun govern/determine checks, HCL list item comment stripping, Make `subst` transform detection, and re-ran isolated Story 1.1 validation successfully.
- 2026-06-09: Addressed forty-fourth follow-up BMad code review pass: evaluated simple Make `subst`/`patsubst` transforms, added `addsuffix`, HCL `//` and block comment stripping, safe vendor-removing transform coverage, and re-ran isolated Story 1.1 validation successfully.
- 2026-06-09: Addressed forty-fifth follow-up BMad code review pass: removed out-of-scope backup-plugin metadata validation from Story 1.1, evaluated Make `addprefix`/`addsuffix`, added Make foreach/call detection, multiline HCL block comment stripping, and re-ran isolated Story 1.1 validation successfully.
- 2026-06-09: Addressed forty-sixth follow-up BMad code review pass: evaluated Make `foreach` before vendor-position short-circuiting, rewrote Make `call` passthrough handling to respect used argument positions including literal/nested arguments, and kept out-of-scope backup-plugin validation excluded from Story 1.1.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed forty-seventh follow-up BMad code review pass: evaluated literal Make `call` bodies, simple variable-defined Make functions, and balanced `foreach` bodies that produce `vendor/` through suffix expressions or nested `addsuffix`.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed forty-eighth follow-up BMad code review pass: preserved safe shell/Make `vendor-cache` concatenations, detected Make `${call ...}`, target-specific Make function variables, literal Make `foreach` lists, and negated-canonical-but-governing docs claims.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed forty-ninth follow-up BMad code review pass: preserved safe Fish and Make-call `vendor-cache` concatenations, detected Make foreach list-side `sort`, indirect Make `call` function names, pronoun source/authority docs claims after authority negation, and kept HCL `${local.ctx}-cache` safe while rejecting `${path.module}/${local.ctx}`.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fiftieth follow-up BMad code review pass: let later Make helper assignments override earlier ones, parsed balanced Make call function-name expressions, resolved nested/simple transformed call names, supported safe HCL `format("%s-cache", local.ctx)`, preserved unsafe HCL path-boundary locals, and detected `serve as metadata source` docs claims after authority negation.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-first follow-up BMad code review pass: added Make `%` stem matching for `patsubst`, preserved source-order overrides across one-line and `define` helpers, avoided resolving vendor-valued helper bodies as simple aliases, narrowed direct HCL function scans with evaluated `format`/`replace` results, and detected past-tense `served as` docs source claims.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-second follow-up BMad code review pass: made derived HCL locals path-aware for safe `vendor-cache`, evaluated multi-argument HCL `format`, narrowed named-context HCL checks, added docs `function/operate as` source wording, and evaluated Make `join`.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `test -f`, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-third follow-up BMad code review pass: accepted negated `function/operate as metadata source` docs wording, evaluated Make `join` with variable arguments, preserved safe HCL interpolation concatenation, and detected HCL `replace()` when the vendor-valued reference is the first argument.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-fourth follow-up BMad code review pass: evaluated Make variables produced by supported functions before `join`, and detected HCL `replace(format(...), ...)` contexts that resolve to `vendor/` paths.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-fifth follow-up BMad code review pass: limited product scans to Story 1.1-owned paths, evaluated nested HCL `format`/`replace` and interpolation arguments, preserved safe local HCL function outputs, and restored path-aware HCL list function detection.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-sixth follow-up BMad code review pass: detected direct and named literal `replace(format(...))` contexts, plus ref-aware `format(replace(local...))` direct, derived-local, and list-index HCL contexts.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-seventh follow-up BMad code review pass: supported GNU Make `::=`/`:::=` assignment operators and replaced HCL same-function nesting checks with a balanced evaluator for nested `format`/`replace` expressions across direct, derived-local, and list-index contexts.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-eighth follow-up BMad code review pass: added GNU Make `!=` assignment support, collected prefixed `define` function bodies for `$(call ...)`, and collapsed multiline HCL function expressions before balanced nested `format`/`replace` evaluation.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed fifty-ninth follow-up BMad code review pass: recognized common GNU Make shell/path function outputs and Make built-in path variables, and extended multiline HCL collapse to `name =` / `name = [` assignment breaks.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed sixtieth follow-up BMad code review pass: recognized `$(shell echo vendor)`, relative Make path-function vendor inputs, direct Make path-function contexts, and preserved HCL `vendor-cache` direct/function contexts by requiring path-segment `vendor` matches.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed sixty-first follow-up BMad code review pass: recognized shell-produced relative vendor paths, `printf %s vendor`, `$(shell pwd)/vendor`, combined `$(CURDIR)/./vendor` path functions, and safe HCL local/list `abspath("./vendor-cache")` outputs.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed sixty-second follow-up BMad code review pass: normalized HCL `${path.module}` before path-boundary checks, made named-context function scans interpolation-aware, included `abspath`/`realpath` in HCL function RHS reference collection, and covered inline object function locals without reintroducing `vendor-cache` false positives.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed sixty-third follow-up BMad code review pass: extended Make `sh -c` shell output normalization to relative vendor paths and quoted `printf` forms for both `$(shell ...)` and `!=` assignments, with targeted regression fixtures.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed sixty-fourth follow-up BMad code review pass: recognized Make shell option clusters containing `c`, detected direct HCL list-index and `tolist` context expressions, and restored intended metadata fixture diagnostics for scaffold resolver-owned fields.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-09: Addressed sixty-fifth follow-up validation regression: removed out-of-scope Story 3.2 extension-source/package-name and backup-plugin metadata checks from the Story 1.1 runner so the review diff applies cleanly to the Story 1.1 baseline.
- 2026-06-09: Re-ran isolated Story 1.1 validation on `c9e7073` plus the current Story 1.1 tests: `bash -n`, full Story 1.1 runner, required `rg`, and scoped `git diff --check` all passed.
- 2026-06-10: Committed vendor-policy hardening as `2e885ae` and workflow vendor-scan coverage as `c08d94f`.
- 2026-06-10: Re-ran Story 1.1 validation after workflow scan coverage: `bash -n cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`, scoped `git diff --check`, clean-worktree patch apply, and `bash cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh` all passed.
- 2026-06-10: BMad code review v13 completed with Blind Hunter, Edge Case Hunter, and Acceptance Auditor all returning `PASS - no findings`.

### Completion Notes

- Implemented Story 1.1 scaffold with `versions.yaml`, source-of-truth documentation, story-specific validation runner, and metadata/docs negative fixtures.
- Initial metadata contains the six required PostgreSQL/Debian rows: `17-trixie`, `18-trixie`, `19beta1-trixie`, `17-bookworm`, `18-bookworm`, and `19beta1-bookworm`.
- All entries are scaffold-safe: `publish: false`, exactly `18-trixie` has `latest_eligible: true`, all other entries have `latest_eligible: false`, resolver-owned values are empty, and `skip_reason` is non-empty.
- First CR findings were resolved before final review rerun.
- Second CR findings were resolved before final review rerun.
- Third CR findings were resolved before final review rerun.
- Fourth CR findings were resolved before final review rerun.
- Fifth CR findings were resolved before final review rerun.
- Sixth CR findings and the follow-up validation regression were resolved before final review rerun.
- Seventh CR findings were resolved before final review rerun.
- Eighth CR findings were resolved or explicitly triaged before final review rerun.
- Ninth CR findings were resolved before final review rerun.
- Tenth CR findings were resolved before final review rerun.
- Eleventh CR findings were resolved before final review rerun.
- Twelfth CR findings were resolved before final review rerun.
- Thirteenth CR findings were resolved before final review rerun.
- Fourteenth CR findings were resolved before final review rerun.
- Latest CR findings were resolved before final review rerun.
- Follow-up CR findings were resolved before final review rerun; scaffold-only metadata invariants were triaged as intentional Story 1.1 scope and later production resolver validation remains Story 1.3/Story 2 ownership.
- Second follow-up CR findings were resolved before final review rerun.
- Third follow-up CR findings were resolved before final review rerun; block-list YAML support remains deferred to the production metadata validator story while inline comments are supported in this bootstrap runner.
- Fourth follow-up CR findings were resolved before final review rerun.
- Fifth follow-up CR findings were resolved before final review rerun.
- Sixth follow-up CR findings were resolved before final review rerun; exact tag/version generation remains Story 1.4-1.6 scope.
- Seventh follow-up CR findings were resolved before final review rerun; `pg_version`/`cnpg_tag` exact cross-check findings remained triaged as Story 1.4-1.6 scope after Acceptance Auditor's prior scope finding.
- Eighth follow-up CR findings were resolved before final review rerun.
- Ninth follow-up CR findings were resolved before final review rerun.
- Tenth follow-up CR findings were resolved before final review rerun.
- Eleventh follow-up CR findings were resolved before final review rerun.
- Twelfth follow-up CR findings were resolved before final review rerun.
- Thirteenth follow-up CR findings were resolved before final review rerun.
- Fourteenth follow-up CR findings were resolved before final review rerun.
- Fifteenth follow-up CR findings were resolved before final review rerun.
- Sixteenth follow-up CR findings were resolved before final review rerun.
- Seventeenth follow-up CR findings were resolved before final review rerun.
- Eighteenth follow-up CR findings were resolved before final review rerun.
- Nineteenth follow-up CR findings were resolved before final review rerun.
- Twentieth follow-up CR findings were resolved before final review rerun.
- Twenty-first follow-up CR findings were resolved before final review rerun.
- Twenty-second follow-up CR findings were resolved before final review rerun.
- Twenty-third follow-up CR findings were resolved before final review rerun.
- Twenty-fourth follow-up CR findings were resolved before final review rerun.
- Twenty-fifth follow-up CR findings were resolved before final review rerun.
- Twenty-sixth follow-up CR findings were resolved before final review rerun.
- Twenty-seventh follow-up CR findings were resolved before final review rerun.
- Twenty-eighth follow-up CR findings were resolved before final review rerun.
- Twenty-ninth follow-up CR findings were resolved before final review rerun.
- Thirtieth follow-up CR findings were resolved before final review rerun.
- Thirty-first follow-up CR findings were resolved before final review rerun.
- Thirty-second follow-up CR findings were resolved before final review rerun.
- Thirty-third follow-up CR findings were resolved before final review rerun.
- Thirty-fourth follow-up CR findings were resolved before final review rerun.
- Thirty-fifth follow-up CR findings were resolved before final review rerun.
- Thirty-sixth follow-up CR findings were resolved before final review rerun.
- Thirty-seventh follow-up CR findings were resolved before final review rerun.
- Forty-sixth follow-up CR findings were resolved before final review rerun; Story 1.1 remains scoped to scaffold/source-of-truth validation and does not include backup-plugin metadata validation.
- Forty-seventh follow-up CR findings were resolved before final review rerun.
- Forty-eighth follow-up CR findings were resolved before final review rerun.
- Forty-ninth follow-up CR findings were resolved before final review rerun.
- Fiftieth follow-up CR findings were resolved before final review rerun.
- Fifty-first follow-up CR findings were resolved before final review rerun.
- Fifty-second follow-up CR findings were resolved before final review rerun.
- Fifty-third follow-up CR findings were resolved before final review rerun.
- Fifty-fourth follow-up CR findings were resolved before final review rerun.
- Fifty-fifth follow-up CR findings were resolved before final review rerun.
- Fifty-sixth follow-up CR findings were resolved before final review rerun.
- Fifty-seventh follow-up CR findings were resolved before final review rerun.
- Fifty-eighth follow-up CR findings were resolved before final review rerun.
- Fifty-ninth follow-up CR findings were resolved before final review rerun.
- Sixtieth follow-up CR findings were resolved before final review rerun.
- Sixty-first follow-up CR findings were resolved before final review rerun.
- Sixty-second follow-up CR findings were resolved before final review rerun.
- Sixty-third follow-up CR findings were resolved before final review rerun.
- Sixty-fourth follow-up CR findings were resolved before final review rerun.
- Sixty-fifth validation regression was resolved before final review rerun.
- Final workflow scan coverage review loop passed with no findings across all three BMad review layers.

## File List

- `cloudnative-pg-timescaledb/versions.yaml`
- `cloudnative-pg-timescaledb/README.md`
- `docs/generated-files.md`
- `cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/valid-minimal.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-missing-top-level.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-missing-required-entry-field.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-pg19beta1-not-experimental.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-latest-eligible-not-18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-latest-eligible-missing-18-trixie.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-empty-resolver-owned-without-skip.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-publishable-without-digest.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-unsupported-postgres-major.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-unsupported-debian-variant.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-unsupported-platform.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-missing-platform.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-duplicate-entry.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-duplicate-key.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-missing-matrix-combination.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-wrong-types.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-unquoted-numeric.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-unbalanced-quote.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-bad-structure.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-missing-image-field.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-unknown-top-level.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-unknown-entry-field.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-non-empty-resolver-field.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-stable-experimental.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-blank-skip-reason.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-workflow-matrices.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-github-actions-matrix.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-catalogs.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-generated-docs.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-readme-tables.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-negated.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-paraphrase.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-plural.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-reverse-canonical.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-leading-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-other-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-bake.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-unrelated-not.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-no-longer.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-mixed-safe-conflict.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-comma-subject.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-safe-prefix.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-and-safe-prefix.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-which-other-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-authoritative.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-hand-maintained-authoritative.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-manual-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-manually-edited-combinations.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-maintained-by-hand-matrix.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-manually-curated-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-manually-edited-and-authoritative.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-manually-maintained-defines.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-canonical-edit-place.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-canonical-definitions.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-authoritative-pure.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-canonical-pure.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-synonym-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-matrix-manual.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-non-source-of-truth-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-generated-from-versions.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-plural-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-first-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-stage-alias.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-build-context-reverse.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-build-context-comes-from.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-buildkit-mount.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-copy-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-forms.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-install-file.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-path.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-buildx.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-json-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-absolute-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-unrelated-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-masked-second-match.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-same-line-safe-prefix.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-and-safe-prefix.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-comma-then-safe-prefix.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-package-source-from.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-execute-helper.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-tree-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-tree-runtime.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-tree-package.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-vendored-examples.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-no-slash.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-runtime-dependencies.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-runtime-dependencies-vendor-first.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-generic-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-build-context-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-vendored-examples-runtime-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-tree-build-input-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-runtime-from.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-runtime-loaded-from-tree.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-as-package-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-run-volume.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-podman-run-mount.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-extensionless-script.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-extensionless-script.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-serve-as.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-image-tags-canonical.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-podman-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-nerdctl-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-buildah-bud.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-workflow-uses.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-safe-period-mask.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-safe-comma-mask.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-prose-add.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-build-dot-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-vendored-examples-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-vendored-examples-copied-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-inherited-canonical.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-pronoun-canonical.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-authoritative-combinations.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-definitive-supported.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-serve-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-lowercase-copy.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-multiline-context.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-c.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-directory.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-directory-equals.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-variable-dot.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-cd.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-tar-c.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-tar-directory.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-modal-canonical.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-modal-pronoun.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-modal-edit-by-hand.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-comma-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-build-context-imperative-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-build-line-continuation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-buildx-bake-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-config-include.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-config-files.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-join-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-contexts-map.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-empty-entries.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-empty-pg-version.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/metadata/invalid-entry-string-field-numeric.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-and-modal-mask.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-pronoun-combinations.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-markdown-lowercase-copy.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-markdown-list-copy.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-parent-relative-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-stage-alias.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-copy-destination.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-label.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-image-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-json-only.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-json-copy-with-flag.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-arg-copy.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-arg-dot.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-markdown-list-lowercase-copy.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-build-platform.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-build-tag.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-bare-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-pronoun-bare-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-hyphenated.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-wrapped-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-wrapped-canonical.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-multiline-json.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-markdown-multiline-json-copy.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-leading-slash.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-quoted-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-build-absolute.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-build-normalized.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-stdin-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-debug-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-short-debug-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-build-context-quoted.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-build-context-quoted-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-build-context-equals.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-variable-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-docker-global-option-build.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-buildkit-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-buildx-builder-option.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-apt-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dpkg-file.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-workflow-uses-nested.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-workflow-uses-parent.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-same-sentence-pronoun.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-containerfile-copy.Containerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-export-variable-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-local-variable-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-split-quoted-pwd.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-build-context-should-not.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-canonical-metadata-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-readme-canonical-compatibility.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-json-second-source.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-hand-curated-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-manually-authored-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-list-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-arg-default-copy.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-serve-metadata-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-act-metadata-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-env-multi-copy.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-inline-variable-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-export-multi-variable-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-hand-curated-space-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-generated-from-versions-remains.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-canonical-source-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-list.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-inline.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-param-default-variable-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-param-default-direct-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-hand-authored-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-maintained-manually-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-generated-from-versions-apposition.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-subdir.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-list-subdir.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-param-default-nocolon-direct-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-serve-metadata-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-is-metadata-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-dockerfile-arg-quoted-default-copy.Dockerfile`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-anchor-context.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-anchor-additional-context.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-param-default-quoted-direct-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-human-maintained-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-maintainer-edit-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-metadata-source-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-flow-list.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-quoted-flow-list.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-param-alt-direct-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-param-alt-variable-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-pronoun-metadata-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-pronoun-source-for-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-sequence-anchor-context.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-inline-map-anchor-additional-context.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-assigned-param-error-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-assigned-param-substring-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-assigned-param-trim-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-human-curated-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-human-authored-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-bare-metadata-authority-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-contexts-map-subdir.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-source-of-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-authority-for-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-serve-metadata-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-variable-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-source-for-image-combinations.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-source-authority-of-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-variable-interpolated-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-variable-join-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-authority-for-metadata-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-quoted-key.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-leading-source-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-variable-format-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-variable-replace-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-array-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-indirect-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-sources-for-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-folded.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-path-module-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-plural-source-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-object-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-compose-additional-contexts-chomped-folded.yaml`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-local-abspath-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-local-path-module-interpolation-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-variable-comment.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-array-multi-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-array-scalar-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-nameref-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-hand-edited-image-definitions.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-do-not-plural-source-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-export-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-override-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-target-specific-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-typeset-nameref-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-local-nameref-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-nested-object-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-buildx-bake-set-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-local-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-exported-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-private-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-target-private-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-deep-nested-object-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-defines-metadata-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-updated-by-hand-matrix.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-hand-edited-image-definitions-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-buildx-bake-set-named-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-long-exported-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-global-exported-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-define-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-deep-nested-object-local-with-other.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-forms-metadata-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-metadata-source-verb-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-define-equals-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-define-colon-equals-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-list-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-buildx-bake-set-context-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-maintained-manually-definitions.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-bracket-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-nested-bracket-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-override-define-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-export-define-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-array-second-element-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-second-list-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-quoted-key-bracket-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-origin-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-hyphen-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-array-negative-index-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-negative-list-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-range-list-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-inline-quoted-key-bracket-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-direct-function-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-provenance-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-shell-array-scalar-non-first.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-shell-array-slice-non-vendor.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-associative-array-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-direct-array-assignment-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-appended-array-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-named-context-function.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-provides-provenance-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-basis-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-associative-array-declared-assigned-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-quoted-associative-array-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-associative-whole-array-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-direct-named-array-assignment-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-array-spaced-negative-slice-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-forms-basis-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-foundation-image-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-generated-outputs-basis.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-quoted-associative-reference-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-associative-assigned-whole-array-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-open-ended-range-list-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-leading-open-range-list-variable-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-generated-outputs-drive-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-compound-indexed-array-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-indexed-set-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-local-function-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-object-local-function-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-negated-then-bare-authority.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-negated-canonical-then-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-source-data.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-indexed-set-negative-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-indexed-set-range-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-append-indexed-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-inline-object-local-function-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-derived-local-function-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-generated-outputs-control-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-negative-direct-array-assignment-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-fish-range-set-build-context.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-list-local-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-generated-outputs-govern-metadata.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-generated-outputs-control-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-negative-direct-array-state-build-context.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-zsh-one-based-array-build-context.zsh`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-word-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-multiline-list-local-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-list-format-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-shell-direct-array-overwrite.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-shell-zsh-direct-indexed-assignment-build-context.zsh`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-object-list-local-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-tolist-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-firstword-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-lastword-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-negated-govern-then-govern.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-not-canonical-but-govern.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-not-canonical-but-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-not-canonical-but-authoritative.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-not-canonical-but-serve-source.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-make-firstword-nonvendor.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-make-word-nonvendor.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-quoted-key-list-local-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-inline-single-list-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-addprefix-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-pronoun-govern.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-same-sentence-pronoun-govern.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-source-of-truth-pronoun-determine.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-list-comment-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-subst-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-subst-produce-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-make-subst-remove-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-addsuffix-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-list-slash-comment-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-list-immediate-slash-comment-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-list-block-comment-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-list-block-comma-comment-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-addsuffix-produce-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-make-addsuffix-nonvendor.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-shell-concat-nonvendor.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-make-concat-nonvendor.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-fish-concat-nonvendor.fish`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-make-call-concat-nonvendor.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-local-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-format-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-local-prefixed-interpolation-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-list-multiline-block-comment-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-foreach-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-foreach-produce-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-foreach-suffix-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-foreach-addsuffix-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-foreach-literal-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-foreach-sort-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-make-foreach-nonvendor.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-call-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-brace-call-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-target-call-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-indirect-call-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-call-redefined-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-nested-indirect-call-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-subst-call-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-call-literal-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-call-literal-body-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-call-prefix-body-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-call-variable-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-call-variable-literal-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-function-as-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-source-of-truth-operate-as-negation.md`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-join-vars-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-join-function-var-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-derived-interpolation-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-replace-first-arg-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-replace-nested-format-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-format-replace-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-format-interpolation-arg-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-local-format-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-local-replace-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-replace-literal-format-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-replace-literal-format-named-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-format-replace-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-format-replace-derived-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-format-replace-list-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-colon-colon-equals-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-colon-colon-colon-equals-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-format-format-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-format-format-derived-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-format-format-list-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-replace-replace-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-replace-replace-derived-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-replace-replace-list-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-assignment-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-override-define-call-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-export-define-call-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-multiline-format-format-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-multiline-format-format-derived-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-multiline-format-format-list-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-multiline-replace-replace-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-multiline-replace-replace-derived-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-multiline-replace-replace-list-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-assignment-sh-c-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-abspath-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-curdir-variable-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-assignment-break-format-derived-local-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-assignment-break-format-list-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-echo-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-abspath-relative-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-realpath-parent-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-direct-abspath-relative-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-direct-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-abspath-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-echo-relative-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-printf-format-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-pwd-vendor-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-abspath-curdir-dot-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-local-abspath-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-list-abspath-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-curdir-dot-variable-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-printf-quoted-format-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-pwd-dot-vendor-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-sh-c-printf-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-abspath-format-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/valid-vendor-hcl-local-abspath-format-concat-nonvendor.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-assignment-sh-c-printf-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-assignment-sh-c-printf-quoted-variable.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-sh-c-echo-relative-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-sh-c-printf-relative-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-sh-c-printf-quoted-format-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-bash-lc-echo-relative-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-make-shell-sh-ec-echo-relative-function-build-context.mk`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-direct-list-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-direct-tolist-index-context.hcl`
- `cloudnative-pg-timescaledb/tests/fixtures/docs/invalid-vendor-hcl-named-tolist-index-context.hcl`

## Change Log

- 2026-06-09: Started implementation.
- 2026-06-09: Added Story 1.1 scaffold, fixtures, and validation; moved story to review.
- 2026-06-09: Addressed first code review pass with stronger validator coverage and diagnostics.
- 2026-06-09: Addressed second code review pass with stricter edge-case coverage and source-of-truth scanning.
- 2026-06-09: Addressed third code review pass with image metadata validation and safer docs/build-config scanning.
- 2026-06-09: Addressed fourth code review pass with scaffold version/tag consistency checks and fixture existence enforcement.
- 2026-06-09: Addressed fifth code review pass with JSON vendor context, resolver-owned empty-field enforcement, and refined source-of-truth regex coverage.
- 2026-06-09: Addressed sixth code review pass and follow-up validation regression with stronger edge-case fixtures.
- 2026-06-09: Addressed seventh code review pass with exact latest/platform contracts, stdlib metadata parsing, and expanded docs/vendor edge-case coverage.
- 2026-06-09: Addressed eighth code review pass with stricter negation semantics, absolute vendor context coverage, and unknown metadata key rejection.
- 2026-06-09: Addressed ninth code review pass with diagnostic-asserting negative fixtures, per-match vendor scanning, unquoted numeric rejection, and clause-level docs checks.
- 2026-06-09: Addressed tenth code review pass with tighter source-of-truth negation handling and Compose short-form vendor context coverage.
- 2026-06-09: Addressed eleventh code review pass with self-contained fixtures, nested vendor pruning, and clause-local safe-negation checks.
- 2026-06-09: Addressed twelfth code review pass with `and`/`or` safe-prefix fixtures and package-source-from-vendor detection.
- 2026-06-09: Addressed thirteenth code review pass with broader source-of-truth synonyms and vendor Dockerfile/build-context edge coverage.
- 2026-06-09: Addressed fourteenth code review pass with BuildKit mount, vendor-tree alias, and pure canonical/authoritative docs coverage.
- 2026-06-09: Addressed ninth code review pass with duplicate YAML key rejection, intended-diagnostic assertions for metadata fixtures, and git-indexed product scans.
- 2026-06-09: Addressed latest code review pass with generic safe-negation fixtures, runtime-from-vendor detection, and extensionless script scan coverage.
- 2026-06-09: Addressed follow-up code review pass with match-local safe-negation scanning, alternate builder/workflow vendor detection, Dockerfile variant path checks, stronger fixture diagnostics, and untracked product scan exclusions.
- 2026-06-09: Addressed second follow-up code review pass with scoped product scans, Makefile/shebang path coverage, prose-safe COPY/ADD matching, and additional source-of-truth/vendor edge fixtures.
- 2026-06-09: Addressed third follow-up code review pass with inline YAML comments, inherited/pronoun source-of-truth checks, negated serve-as prose support, lowercase Dockerfile COPY/ADD detection, multiline config context checks, and additional script/Make vendor usage fixtures.
- 2026-06-09: Addressed fourth follow-up code review pass with modal source-of-truth checks, shell line-continuation vendor build detection, buildx bake/config import vendor detection, and added matching positive negation fixtures.
- 2026-06-09: Addressed fifth follow-up code review pass with targeted metadata fixture diagnostics, stronger `and`/`or` source-of-truth checks, parent-relative vendor build detection, and Markdown Dockerfile instruction fixtures.
- 2026-06-09: Addressed sixth follow-up code review pass by removing out-of-scope exact tag/version scaffold checks and tightening Dockerfile/vendor command matching around source operands.
- 2026-06-09: Addressed seventh follow-up code review pass with workflow scan scope, bare authority docs checks, Dockerfile JSON copy coverage, lowercase Markdown list copy coverage, and docker build option-context fixtures.
- 2026-06-09: Addressed eighth follow-up code review pass with inline-comment header support, hyphenated source-of-truth checks, direct vendor package file detection, BuildKit named context detection, multiline JSON COPY checks, and expanded docker build context fixtures.
- 2026-06-09: Addressed ninth follow-up code review pass with wrapped Markdown source-of-truth normalization, quoted vendor path detection, Markdown multiline JSON COPY coverage, and nested/parent-relative workflow `uses:` fixtures.
- 2026-06-09: Addressed tenth follow-up code review pass with unbalanced quote rejection, Dockerfile JSON COPY flags, modal hand-edited source-of-truth prose, and reversed build-context prose fixtures.
- 2026-06-09: Addressed eleventh follow-up code review pass with BuildKit equals context, buildx builder option, compose file, install-file, and hand-maintained authority fixtures.
- 2026-06-09: Addressed twelfth follow-up code review pass with non-empty `pg_version`, value-less Docker global flag, and manual generated-artifact matrix authority fixtures.
- 2026-06-09: Addressed thirteenth follow-up code review pass with long-form directory options, shell variable, HCL join context, stdin Dockerfile, and canonical edit-place fixtures.
- 2026-06-09: Addressed fourteenth follow-up code review pass with strict real `versions.yaml` resolver-owned enforcement, manually curated authority, HCL contexts-map, and vendor helper execution fixtures.
- 2026-06-09: Addressed fifteenth follow-up code review pass with Make/Dockerfile vendor variable expansion, Docker/Podman runtime mount, vendored copied-source-tree, and safe vendor-negation fixtures.
- 2026-06-09: Addressed sixteenth follow-up code review pass with split manual-authority docs, predicate-first vendor prose, and dot-normalized vendor variable fixtures.
- 2026-06-09: Addressed seventeenth follow-up code review pass with root docs markdown scans, tightened quoted scalar parsing, unhyphenated source-of-truth wording, direct vendor executable detection, prefixed HCL contexts maps, and shell-extension script coverage.
- 2026-06-09: Addressed eighteenth follow-up code review pass with same-sentence pronoun source-of-truth detection, exported/local vendor variable expansion, split-quoted `$PWD` vendor path detection, `Containerfile` vendor-copy coverage, and `should not` safe-negation support.
- 2026-06-09: Addressed nineteenth follow-up code review pass with reproducible fixture diff coverage, canonical metadata-source docs checks, and JSON Dockerfile `COPY/ADD` source-operand coverage.
- 2026-06-09: Addressed twentieth follow-up code review pass with manual-authority synonym coverage, Compose `additional_contexts` vendor detection, Dockerfile ARG default substitution coverage, and source-of-truth list-negation handling.
- 2026-06-09: Addressed twenty-first follow-up code review pass with serve/act metadata-source docs coverage, inline/multi shell variable defaults, Dockerfile multi-key ENV expansion, additional Compose context forms, `versions.yaml remains` wording, and negated canonical-source positive fixtures.
- 2026-06-09: Addressed twenty-second follow-up code review pass with additional manual-authority wording, comma-apposition source-of-truth positives, Compose subdirectory/anchor contexts, shell/Dockerfile quoted parameter defaults, and bare metadata authority/source docs checks.
- 2026-06-09: Addressed twenty-third follow-up code review pass with negated metadata-source positives, human-maintained/maintainer-edited source wording, flow-list Compose contexts, shell alternate-value/default expansions, sequence/inline-map anchors, and pronoun metadata-source authority checks.
- 2026-06-09: Addressed twenty-fourth follow-up code review pass with bare metadata-authority negations, human-curated/authored source wording, HCL context subdirectories, HCL variable/local indirection, and source/authority-for-image-metadata wording.
- 2026-06-09: Addressed twenty-fifth follow-up code review pass with HCL interpolation/join indirection, image-combination source wording, source/authority negation coverage, quoted Compose additional-context keys, and block-list platform parsing.
- 2026-06-09: Addressed twenty-sixth follow-up code review pass with shell arrays/indirect expansion, HCL function/path.module indirection, leading source negations, Compose folded additional contexts, allowed block-list parsing, and plural metadata source wording.
- 2026-06-09: Addressed twenty-seventh follow-up code review pass with HCL object-local context detection, Compose chomping indicators, plural source negations, Make inline-comment expansion, Bash arrays/namerefs, and HCL abspath/path-module interpolation.
- 2026-06-09: Addressed twenty-eighth follow-up code review pass with Make export/override/target-specific variables, Fish vendor variables, broader shell namerefs, nested HCL object contexts, and hand-edited image definition docs checks.
- 2026-06-09: Addressed twenty-ninth follow-up code review pass with Buildx bake set-context detection, Fish set flags, Make private variables, deeper HCL locals, metadata-source verbs, hand-updated docs wording, and safe hand-edited image definition negations.
- 2026-06-09: Addressed thirtieth follow-up code review pass with Buildx bake named contexts, Fish long flags, Make define variables, dotted HCL local resolution, form/constitute metadata-source verbs, and negated metadata-source verb wording.
- 2026-06-09: Addressed thirty-first follow-up code review pass with Make define assignment operators, Fish list/index variables, Buildx bake set-context safe negation, maintained-manually image definitions, and HCL bracket local references.
- 2026-06-09: Addressed thirty-second follow-up code review pass with prefixed Make define variables, indexed Bash/Fish list resolution, and HCL quoted-key bracket references.
- 2026-06-09: Addressed thirty-third follow-up code review pass with negative-index Bash/Fish list handling, hyphenated Make variables, direct HCL vendor functions, inline quoted HCL keys, and origin-of-metadata docs wording.
- 2026-06-09: Addressed thirty-fourth follow-up code review pass with Bash associative/direct/appended arrays, precise Bash scalar/slice handling, HCL named-context functions, and provenance metadata wording.
- 2026-06-09: Addressed thirty-fifth follow-up code review pass with direct nonnumeric and associative Bash arrays, spaced negative slices, and provenance/basis source-of-truth wording.
- 2026-06-09: Addressed thirty-sixth follow-up code review pass with quoted Bash associative references, associative whole-array assignments, Fish open ranges, generated outputs/artifacts subjects, basis/foundation wording, and paragraph-preserving docs scanning.
- 2026-06-09: Addressed thirty-seventh follow-up code review pass with Bash compound indexed arrays, Fish indexed set, inherited authority conflicts, HCL local function indirection, and generated outputs metadata-control wording.
- 2026-06-09: Addressed thirty-eighth follow-up code review pass with Fish indexed/list mutation handling, source-data/source-of-truth conflict detection, HCL derived local propagation, and targeted fixtures.
- 2026-06-09: Addressed thirty-ninth follow-up code review pass with Fish range-set mutation handling, Bash negative indexed assignment handling, HCL list-index vendor refs, generated-output control wording, and targeted fixtures.
- 2026-06-09: Addressed fortieth follow-up code review pass with Bash direct assignment state, zsh arrays, Make `word`, HCL multiline/function lists, generated-output govern wording, and safe control negation fixtures.
- 2026-06-09: Addressed forty-first follow-up code review pass with zsh direct assignment normalization, stale overwrite prevention, Make firstword/lastword and whole-variable list expansion, object/wrapped HCL list refs, govern conflict detection, and targeted fixtures.
- 2026-06-09: Addressed forty-second follow-up code review pass with Make selector protection, Make transform detection, quoted-key and inline HCL list fixtures, pronoun govern checks, and targeted fixtures.
- 2026-06-09: Addressed forty-third follow-up code review pass with same-sentence pronoun govern/determine checks, HCL list item comment stripping, Make `subst`, and targeted fixtures.
- 2026-06-09: Addressed forty-fourth follow-up code review pass with evaluated Make transforms, `addsuffix`, HCL slash/block comment stripping, and safe vendor-removing transform fixtures.
- 2026-06-09: Addressed forty-fifth follow-up code review pass with out-of-scope backup-plugin validation removal, evaluated Make prefix/suffix transforms, Make foreach/call detection, multiline HCL block comments, and targeted fixtures.
- 2026-06-09: Addressed forty-sixth follow-up code review pass with Make `foreach` literal-output coverage, Make `call` used-argument passthrough parsing, and isolated Story 1.1 validation rerun.
- 2026-06-09: Addressed forty-seventh follow-up code review pass with Make `call` body evaluation, simple variable-defined function parsing, balanced `foreach` parsing, and targeted fixtures.
- 2026-06-09: Addressed forty-eighth follow-up code review pass with safe concatenation fixtures, Make brace-call and target-specific call parsing, literal foreach parsing, and negated-canonical/control docs coverage.
- 2026-06-09: Addressed forty-ninth follow-up code review pass with Fish/HCL safe concatenation fixtures, Make call-concat safety, Make foreach sort and indirect call detection, and pronoun source/authority docs coverage.
- 2026-06-09: Addressed fiftieth follow-up code review pass with Make helper override behavior, balanced/computed call-name parsing, safe HCL format concat, HCL path-boundary interpolation coverage, and serve-as metadata-source docs coverage.
- 2026-06-09: Addressed fifty-first follow-up code review pass with Make wildcard `patsubst`, source-ordered helper definitions, literal HCL function concat handling, HCL prefixed function outputs, and past-tense serve-as docs coverage.
- 2026-06-09: Addressed fifty-second follow-up code review pass with path-aware derived HCL locals, multi-argument HCL format, named-context safe concat, function/operate docs wording, and Make join evaluation.
- 2026-06-09: Addressed fifty-third follow-up code review pass with negated function/operate docs wording, Make join variable evaluation, safe HCL interpolation concat handling, and HCL replace first-argument detection.
- 2026-06-09: Addressed fifty-fourth follow-up code review pass with Make function-produced join variables and HCL replace nested-format detection.
- 2026-06-09: Addressed fifty-fifth follow-up code review pass with scoped product scans, nested/interpolated HCL function evaluation, safe local HCL function output handling, and HCL list function coverage.
- 2026-06-09: Addressed fifty-sixth follow-up code review pass with direct/named literal `replace(format(...))` and ref-aware `format(replace(local...))` HCL coverage.
- 2026-06-09: Addressed fifty-seventh follow-up code review pass with GNU Make `::=`/`:::=` operators and balanced HCL nested `format`/`replace` evaluation across direct, local-derived, and list-index contexts.
- 2026-06-09: Addressed fifty-eighth follow-up code review pass with GNU Make `!=`, prefixed define-call collection, and multiline HCL function expression collapse before nested evaluation.
- 2026-06-09: Addressed fifty-ninth follow-up code review pass with Make shell/path function output recognition, Make built-in path variables, and HCL assignment-break multiline function collapse.
- 2026-06-09: Addressed sixtieth follow-up code review pass with Make shell echo/path-function relative inputs, direct path-function contexts, and HCL vendor-cache path-segment safeguards.
- 2026-06-09: Addressed sixty-first follow-up code review pass with shell-produced relative vendor paths, `printf %s`, `$(shell pwd)/vendor`, combined `CURDIR` path functions, and safe HCL local/list abspath concat fixtures.
- 2026-06-09: Addressed sixty-second follow-up code review pass with HCL path-module normalization, interpolation-aware named-context scans, path-function RHS ref collection, and inline object function local handling.
- 2026-06-09: Addressed sixty-third follow-up code review pass with Make `sh -c` relative vendor and quoted `printf` normalization for `$(shell ...)` and `!=` assignments.
- 2026-06-09: Addressed sixty-fourth follow-up code review pass with Make shell option-cluster handling, direct HCL list-index context detection, and metadata fixture diagnostic ordering.
- 2026-06-09: Addressed sixty-fifth validation regression by removing out-of-scope Story 3.2 extension-source/package-name and backup-plugin metadata checks from the Story 1.1 runner.
- 2026-06-09: Addressed sixty-sixth validation regression by removing out-of-scope publish-policy checks from the Story 1.1 runner.
- 2026-06-09: Addressed sixty-seventh code review pass by rejecting resolver-owned values for all Story 1.1 scaffold rows, including publishable rows.
- 2026-06-09: Addressed sixty-eighth code review pass with generated-files source-of-truth coverage, split shell-option Make coverage, and direct multiline HCL list-index context detection.
- 2026-06-09: Addressed sixty-ninth code review pass by enforcing resolver-owned scaffold invariants on real metadata, adding compatibility-matrix source-of-truth coverage, and rejecting plain vendor runtime dependency prose.
- 2026-06-09: Addressed seventieth code review pass by requiring every Story 1.1 scaffold row to include both linux/amd64 and linux/arm64 platforms.
- 2026-06-09: Addressed seventy-first code review pass by requiring scaffold pg_version to equal pg_major and rejecting production-image vendor runtime/build prose.
- 2026-06-09: Addressed seventy-second code review pass by rejecting build-from-vendor prose, shell source of vendor scripts, and Make include of vendored build logic.
- 2026-06-09: Addressed seventy-third code review pass by scanning lowercase makefile and GNUmakefile names for vendor misuse.
- 2026-06-09: Addressed seventy-fourth code review pass by rejecting build-dependency prose that depends on vendor.
- 2026-06-09: Addressed seventy-fifth code review pass by scanning MDX and uppercase Markdown docs, while removing an out-of-scope pg_version equality check.
- 2026-06-10: Marked Story 1.1 complete after commits `2e885ae` and `c08d94f`, clean-worktree validation, and BMad code review v13 with no findings.
