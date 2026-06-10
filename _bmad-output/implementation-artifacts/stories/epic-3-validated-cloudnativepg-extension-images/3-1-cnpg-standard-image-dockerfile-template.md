---
storyId: 3.1
storyKey: 3-1-cnpg-standard-image-dockerfile-template
epic: 3
title: 'CNPG Standard Image Dockerfile Template'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: 71298949cd723c58de79bbbd2a7d90abf7f64f46
---

# Story 3.1: CNPG Standard Image Dockerfile Template

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Epic 1 and Epic 2 stories may be assumed complete only through their accepted story outputs.

## Out of Scope

- Extension package installation logic; owned by Story 3.2.
- Local Buildx/Bake execution; owned by Story 3.3.
- Runtime and SQL smoke execution; owned by Stories 3.4 and 3.5.
- CI release candidate build and publish workflows; owned by Epic 4.

## Source Story

### Story 3.1: CNPG Standard Image Dockerfile Template

As an operator,
I want generated Dockerfiles to extend CNPG `standard-*` base images,
So that the image family follows the supported CloudNativePG runtime path for v1.

**Acceptance Criteria:**

**Given** valid metadata with resolved CNPG base image tags and digests
**When** `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh` renders Dockerfiles
**Then** each generated Dockerfile uses `ghcr.io/cloudnative-pg/postgresql` `standard-*` base images.
**And** each generated Dockerfile uses `FROM ghcr.io/cloudnative-pg/postgresql:${cnpg_tag}@${cnpg_digest}`.
**And** generation fails if `cnpg_digest` is missing, malformed, or does not resolve for every platform listed in metadata.
**And** no generated Dockerfile uses deprecated `system-*` images.
**And** generated Dockerfiles are emitted under `cloudnative-pg-timescaledb/generated/{pg}/{debian_variant}/Dockerfile`.
**And** generated Dockerfiles include image labels for PostgreSQL major, PostgreSQL version, Debian variant, CNPG tag, exact CNPG digest used in `FROM`, TimescaleDB version, Toolkit version, source repository, and generation date.
**And** generated Dockerfiles do not use `vendor/` as build context or runtime input.

## Expected Artifacts

- `cloudnative-pg-timescaledb/templates/Dockerfile.tmpl`
- `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`
- `cloudnative-pg-timescaledb/generated/{pg}/{debian_variant}/Dockerfile` for each metadata entry with `publish: true`
- Deterministic skipped marker and/or JSON summary for each metadata entry with `publish: false` and non-empty `skip_reason`; skipped entries must not produce buildable Dockerfiles
- `cloudnative-pg-timescaledb/tests/dockerfile/run.sh`
- `cloudnative-pg-timescaledb/tests/dockerfile/fixtures/valid-digest-pinned.yaml`
- `cloudnative-pg-timescaledb/tests/dockerfile/fixtures/missing-cnpg-digest.yaml`
- `cloudnative-pg-timescaledb/tests/dockerfile/fixtures/malformed-cnpg-digest.yaml`
- `cloudnative-pg-timescaledb/tests/dockerfile/fixtures/unresolved-or-platform-missing-cnpg-digest.yaml`
- `cloudnative-pg-timescaledb/tests/dockerfile/fixtures/skipped-nonpublish-missing-cnpg-digest.yaml`
- `cloudnative-pg-timescaledb/tests/dockerfile/fixtures/system-flavor-base.yaml`
- `cloudnative-pg-timescaledb/tests/dockerfile/fixtures/vendor-build-context.yaml`

## Dockerfile Template Contract

- `generate-dockerfiles.sh` must render buildable Dockerfiles only for metadata entries with `publish: true`.
- For `publish: true`, `FROM` must use exactly `ghcr.io/cloudnative-pg/postgresql:${cnpg_tag}@${cnpg_digest}`.
- For `publish: true`, `cnpg_digest` is required and must match `sha256:<64 lowercase hex chars>`; missing, malformed, unresolved, or platform-incomplete digests hard-fail generation.
- For `publish: false` with non-empty `skip_reason`, missing or unresolved resolver-owned values such as `cnpg_digest` must not fail generation of publishable Dockerfiles. The generator must either omit that entry from buildable Dockerfile output or emit a deterministic skipped marker/JSON summary according to the prior generator contract, and it must ensure the skipped entry is not included in Bake buildable targets.
- Dockerfile validation for publishable entries must inspect `ghcr.io/cloudnative-pg/postgresql:${cnpg_tag}@${cnpg_digest}` as an OCI manifest or manifest index and fail when the digest cannot be resolved or when any platform from metadata is absent.
- Registry inspection may use deterministic mocked fixture output in tests, but production validation must use the same validation interface and report the inspected reference, expected platforms, and actual manifest platforms.
- `cnpg_tag` must include `standard` and must not include `system`.
- Generated Dockerfiles must not use `vendor/` in `FROM`, `COPY`, `ADD`, build context notes, package source references, or runtime inputs.
- Required labels: `org.opencontainers.image.source`, `org.opencontainers.image.created`, `org.pnet.postgresql.major`, `org.pnet.postgresql.version`, `org.pnet.debian.variant`, `org.pnet.cnpg.tag`, `org.pnet.cnpg.digest`, `org.pnet.timescaledb.version`, and `org.pnet.timescaledb_toolkit.version`.
- Generation date must use explicit UTC `YYYY-MM-DD` input or deterministic environment value; local timezone must not affect output.

## Required Validation Commands

- `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`
- `rg "FROM ghcr.io/cloudnative-pg/postgresql:.+@sha256:" cloudnative-pg-timescaledb/generated`
- `bash cloudnative-pg-timescaledb/tests/dockerfile/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/dockerfile/run.sh` must run every fixture listed in Expected Artifacts.
- Include negative fixtures for missing digest on `publish: true`, malformed digest, syntactically valid digest that does not resolve or lacks a listed platform, deprecated `system-*`, and `vendor/` build/runtime usage.
- Include a skipped fixture where `publish: false`, non-empty `skip_reason`, and missing `cnpg_digest` does not block generation of publishable Dockerfiles and does not appear in buildable output.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Update `cloudnative-pg-timescaledb/templates/Dockerfile.tmpl` to render digest-pinned CNPG `standard-*` `FROM` lines and required OCI/custom labels.
- [x] Extend `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh` to render buildable Dockerfiles for `publish: true` entries and skip `publish: false` entries with deterministic skipped output.
- [x] Hard-fail missing/malformed/unresolved CNPG digests only for publishable entries, preserving prior skipped/non-publish metadata contracts.
- [x] Generate buildable Dockerfiles only for `publish: true` metadata entries across `17/18/19beta1` and `trixie`/`bookworm`; generate deterministic skipped output, not buildable Dockerfiles, for `publish: false` entries.
- [x] Add Dockerfile validation fixtures and `cloudnative-pg-timescaledb/tests/dockerfile/run.sh`.
- [x] Run `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`, the `rg` `FROM` check, and `bash cloudnative-pg-timescaledb/tests/dockerfile/run.sh`.

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

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-2 Reproducibility | 1.1, 1.3, 1.5, 1.6, 3.1, 4.2, 4.4, 5.9 | Metadata, digests, package versions, platforms, tags, generated outputs, and release evidence explain each image after the fact. |
| CNPG standard base | 2.1, 3.1, 3.4 | Generated Dockerfiles use digest-pinned CNPG `standard-*` images and reject deprecated `system-*` images. |
| Generated artifacts | 1.5, 1.6, 3.1, 4.1, 4.6, 5.7, 5.9 | Dockerfiles, Bake file, matrix JSON, catalogs, docs tables, and README examples are generated or validated and drift-checked. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-3-validated-cloudnativepg-extension-images/3-1-cnpg-standard-image-dockerfile-template.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Added `templates/Dockerfile.tmpl` for digest-pinned `ghcr.io/cloudnative-pg/postgresql:${cnpg_tag}@${cnpg_digest}` standard CNPG bases and required OCI/custom labels.
- Extended `scripts/lib/generator_contract.py` so Dockerfile generation emits buildable Dockerfiles only for `publish:true` rows and deterministic `Dockerfile.skipped.json` markers for `publish:false` rows.
- Added publishable-row validation for `cnpg_digest` format, CNPG `standard-*` tag policy, manifest/platform resolution through `CNPG_MANIFEST_FIXTURE` or live `docker buildx`/`skopeo`, template variable resolution, UTC generation date, and reference-tree exclusion.
- Updated Bake and matrix summaries so skipped rows have no buildable Dockerfile path or Bake target, and Bake targets include only publishable rows.
- Updated generator JSON contract docs, generator fixtures, `validate-generated.sh`, and generated drift handling for skipped Dockerfile markers.
- Added `tests/dockerfile/run.sh` with positive publishable fixture coverage and negative coverage for missing digest, malformed digest, platform-incomplete digest, deprecated `system-*`, reference-tree rendered output, and skipped non-publish metadata.
- Subagent review round 1 found a blocker where `generate-dockerfiles.sh --json` bypassed publishable digest/platform validation. Fixed by validating and rendering publishable rows before JSON summary and adding negative `--json` coverage.
- Subagent review round 2 reported no blockers.

### Validation Commands

- `bash cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh` - passed; production metadata currently has `buildable=0 skipped=6`.
- `bash cloudnative-pg-timescaledb/tests/dockerfile/run.sh` - passed.
- Publishable fixture `rg "FROM ghcr.io/cloudnative-pg/postgresql:.+@sha256:" <tmp>/generated` - passed; committed production generated tree has no buildable Dockerfiles because every current metadata row is `publish:false`.
- `bash cloudnative-pg-timescaledb/tests/generators/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh` - passed.
- `git diff --cached --check` - passed.
- Clean staged-index snapshot validation using `git checkout-index --all --prefix=<tmp>/ && make validate` - passed.
- Worktree `make validate` - blocked by unrelated unstaged Story 1.1 hardening state that expects resolver-owned fields to be empty; the staged snapshot for this story passes full validation.

### Completion Notes

- FR-1: Generated image definitions now distinguish publishable Dockerfiles from skipped rows and preserve the `17`, `18`, `19beta1` by `trixie`, `bookworm` matrix without exposing skipped rows as buildable.
- NFR-2: Publishable Dockerfiles are reproducible from metadata, template, exact CNPG digest, manifest/platform validation, and deterministic generation date.
- CNPG standard base: Publishable rows require `standard-*` CNPG tags, reject `system-*`, and use digest-pinned `ghcr.io/cloudnative-pg/postgresql` base references.
- Generated artifacts: Drift validation now tracks `Dockerfile.skipped.json` markers and removes stale alternate generated artifacts when publish state changes.

## File List

- `cloudnative-pg-timescaledb/docker-bake.hcl`
- `cloudnative-pg-timescaledb/generated/**/Dockerfile.skipped.json`
- `cloudnative-pg-timescaledb/generated/**/Dockerfile` deletions for current `publish:false` rows
- `cloudnative-pg-timescaledb/matrix.json`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/templates/Dockerfile.tmpl`
- `cloudnative-pg-timescaledb/tests/dockerfile/**`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-*.json`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-*.json`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `docs/generator-contracts.md`

## Change Log

- Added Story 3.1 Dockerfile template rendering and validation for digest-pinned CNPG standard bases.
- Replaced current non-publish generated Dockerfile skeletons with deterministic skipped markers.
- Excluded skipped metadata rows from Bake targets and buildable matrix fields.
- Extended generator contracts, fixtures, drift validation, and full validation gate with Dockerfile-specific tests.
