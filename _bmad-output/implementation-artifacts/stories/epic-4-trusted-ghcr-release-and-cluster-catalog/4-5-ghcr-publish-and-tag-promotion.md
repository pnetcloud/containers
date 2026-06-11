---
storyId: 4.5
storyKey: 4-5-ghcr-publish-and-tag-promotion
epic: 4
title: 'GHCR Publish and Tag Promotion'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 4.5: GHCR Publish and Tag Promotion

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 4.1-4.4 in this epic may be assumed complete.

## Out of Scope

- Candidate build/smoke, scan, and evidence generation; owned by Stories 4.2-4.4.
- Catalog generation; owned by Story 4.6.
- Public tag docs; owned by Story 5.2.

## Source Story

### Story 4.5: GHCR Publish and Tag Promotion

As an operator,
I want GHCR release tags promoted only after all release gates pass,
So that clusters can pin safe images or follow a selected PostgreSQL major line.

**Acceptance Criteria:**

**Given** the same candidate digest has passed build, per-platform smoke, tag validation, vulnerability scan, SBOM/provenance, and signing verification
**When** `.github/workflows/build.yml` runs the publish job
**Then** the publish job has explicit `needs` or reusable-workflow dependencies for build, smoke, security scan, provenance, signing, and tag validation gates for the same digest.
**And** publish cannot run unless all required dependencies succeeded for the same digest and release metadata record.
**And** primary `trixie` images receive rolling major tags such as `17` or `18` and immutable tags such as `18-pg18.4-ts2.27.2-20260609`.
**And** secondary `bookworm` images receive OS-suffixed rolling and immutable tags such as `18-bookworm` and `18-pg18.4-ts2.27.2-20260609-bookworm`.
**And** `latest` is published only for PostgreSQL `18` `trixie`.
**And** `latest` is never published for `bookworm`, PostgreSQL `17`, or experimental PostgreSQL `19beta1`.
**And** PostgreSQL `19beta1` uses experimental tags and cannot be promoted to normal/latest tags without an explicit metadata policy change.
**And** SBOM, provenance, signature, scan status, tag set, and candidate metadata are associated with each final published digest.

## Expected Artifacts

- `.github/workflows/build.yml` publish/tag promotion job
- `cloudnative-pg-timescaledb/scripts/validate-publish-gates.sh`
- GHCR release metadata outputs
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/valid-publish-release.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-build-gate.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-smoke-gate.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-scan-gate.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-sbom.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-provenance.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-signature.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/verification-not-passed.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-tag-validation-gate.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/metadata-record-mismatch.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/digest-mismatch.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/wrong-latest-bookworm.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/pg19beta1-normal-tag.json`

## Publish Promotion Contract

- Publish consumes an existing release metadata record artifact passed through prior gates; the record must include `release_metadata_record_id` or `release_metadata_ref` and must carry the Story 4.2 candidate metadata, Story 4.3 scan result, Story 4.4 evidence/signing/verification refs, candidate digest, index digest, platform digests, and intended final tags. If prior gate artifacts lack this id/ref, this story must add a deterministic pass-through aggregation artifact before publish without recomputing digests, tags, scan status, evidence refs, or signatures.
- Required gates for the same digest: candidate build, per-platform smoke, tag validation, vulnerability scan pass, SBOM present, provenance present, cosign signature present, and cosign verification pass.
- Publish job has explicit `needs` or same-run reusable workflow dependencies for every gate; asynchronous scan/evidence completion is not sufficient.
- Final tags are applied only after all gates pass.
- `latest` only for PostgreSQL `18` `trixie`; never for `bookworm`, PostgreSQL `17`, or `19beta1`.
- `19beta1` may receive only experimental tags while experimental metadata is true.
- Release metadata output keys: `image`, `release_metadata_record_id` or `release_metadata_ref`, `published_digest`, `final_tags`, `scan_result`, `sbom_ref`, `provenance_ref`, `signature_ref`, `verified`, `cosign_certificate_identity`, `cosign_certificate_issuer`, `candidate_digest`, `index_digest`, `platform_digests`, and `promotion_status`.
- Publish must pass through `release_metadata_record_id`/`release_metadata_ref`, verification status, certificate identity/issuer, and platform digests from prior gate metadata; it must not recompute or mix data across metadata records.

## Required Validation Commands

- `bash cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh`
- `cloudnative-pg-timescaledb/scripts/validate-tags.sh --date 20260609`
- `actionlint .github/workflows/build.yml`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh` must run every fixture listed in Expected Artifacts.
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh` or a dedicated workflow validator must parse the real `.github/workflows/build.yml` as YAML, identify the actual publish/tag-promotion job or jobs, resolve same-run `needs` and reusable `workflow_call` dependencies, and fail unless candidate build, per-platform smoke, tag validation, vulnerability scan, SBOM/provenance, signing, and cosign verification are explicit dependencies for the same digest/release metadata record. Text/grep-only validation is not sufficient.
- Include negative fixtures for missing candidate build gate, missing per-platform smoke gate, missing scan gate, missing SBOM, missing provenance, missing signature, failed/missing verification, missing tag-validation gate, release metadata record mismatch, digest mismatch, wrong `latest` on `bookworm`, and normal tag promotion for `19beta1`.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement the `.github/workflows/build.yml` publish/tag promotion job with explicit same-run `needs` or reusable-workflow dependencies on candidate build, per-platform smoke, tag validation, vulnerability scan, SBOM/provenance, signing, and verification gates.
- [x] Implement `cloudnative-pg-timescaledb/scripts/validate-publish-gates.sh` to verify all gates refer to the same release metadata record, candidate digest, final index digest, and intended tag set.
- [x] Promote only validated final tags from the Story 1.4 tag library: primary `trixie` rolling/immutable tags, secondary `bookworm` OS-suffixed tags, and `latest` only for PostgreSQL `18` `trixie`.
- [x] Reject `latest` for `bookworm`, PostgreSQL `17`, and `19beta1`; reject normal/non-experimental tag promotion for `19beta1` while `experimental: true`.
- [x] Emit GHCR release metadata outputs with release metadata record id/ref, published digest, final tags, scan result, SBOM/provenance/signature refs, verification result, cosign identity/issuer, candidate digest, index digest, platform digests, and promotion status.
- [x] Add publish/tag promotion fixtures and `cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh` for missing candidate build/smoke/scan/SBOM/provenance/signature/verification/tag-validation gates, release metadata record mismatch, digest mismatch, wrong latest target, and `19beta1` normal tag promotion.
- [x] Run `bash cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh`, `cloudnative-pg-timescaledb/scripts/validate-tags.sh --date 20260609`, and `actionlint .github/workflows/build.yml`.

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
| FR-13 | 3.3, 4.2, 4.5, 5.9 | Buildx/Bake targets, per-platform candidates, manifest digests | `make build`, per-platform smoke, release rehearsal |
| FR-15 | 1.4, 4.5, 4.7, 5.2, 5.9 | tag policy, GHCR publish job, image tag docs | `validate-tags.sh`, publish rehearsal, docs validation |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-7 Public trust | 4.4, 4.5, 4.6, 5.1, 5.5, 5.9 | Labels, docs, SBOM, provenance, signatures, vulnerability scans, and catalogs make public releases inspectable. |
| Workflow requirements | 2.4, 2.5, 4.2, 4.3, 4.5, 4.7, 5.9 | `update.yml`, `validate.yml`, `build.yml`, and `security-scan.yml` exist, are validated, and participate in the release rehearsal. |
| Tag policy | 1.4, 4.5, 5.2, 5.9 | Immutable, rolling, `bookworm` suffix, experimental, and `latest` rules are generated, validated, documented, and rehearsed. |
| Supply-chain release gates | 4.3, 4.4, 4.5, 4.7, 5.5, 5.9 | Vulnerability scan, SBOM, provenance, signing, permissions, and summaries block release when missing or failing. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-4-trusted-ghcr-release-and-cluster-catalog/4-5-ghcr-publish-and-tag-promotion.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- 2026-06-09: Implemented Story 4.5 publish/tag promotion flow from staged baseline after Story 4.4.
- 2026-06-09: Added `publish` job to `.github/workflows/build.yml` with same-run dependencies on `candidate`, `security_scan`, `release_evidence`, and `tag_validation`.
- 2026-06-09: Added `tag_validation` job to produce `release-gate-metadata-${{ matrix.bake_target }}` with deterministic release metadata record id/ref before publish.
- 2026-06-09: Added `validate-publish-gates.sh` to bind candidate metadata, scan summary, release evidence, release gate metadata, final tags, index digest, platform digests, and certificate evidence.
- 2026-06-09: Updated candidate metadata validation so publishable experimental `19beta1` rows are allowed only with immutable preview tags and no rolling/latest tags.
- 2026-06-09: Added publish/tag promotion fixtures and YAML-parsing workflow validation in `tests/publish-tag-promotion/run.sh`.
- 2026-06-09: First bmad-code-review pass found blockers around synthesized gate metadata, record id/ref recomputation, `19beta1` blocking, non-YAML workflow validation, and missing positive bookworm/19beta1 coverage.
- 2026-06-09: Fixed review blockers by adding same-run release gate artifact pass-through, YAML parsing with PyYAML, positive `bookworm` and `19beta1` coverage, and stricter release metadata id/ref checks.
- 2026-06-09: Second bmad-code-review pass found a remaining high issue where publish mode accepted gate metadata missing one identity field.
- 2026-06-09: Fixed remaining high issue by requiring both `release_metadata_record_id` and `release_metadata_ref` in release gate metadata and adding regression checks for each missing field.

### Completion Notes

- `.github/workflows/build.yml` now separates candidate build/smoke, security scan, release evidence, tag validation/release gate metadata, and final publish promotion.
- Publish promotes only validated `final_tags` from candidate metadata by running `docker buildx imagetools create` from `image@published_digest` to each final tag.
- `latest` remains limited to PostgreSQL `18` `trixie`; `bookworm` requires OS-suffixed rolling/immutable tags; `19beta1` may pass only with immutable experimental tags.
- Publish output metadata includes `image`, `release_metadata_record_id`, `release_metadata_ref`, `published_digest`, `final_tags`, `scan_result`, `sbom_ref`, `provenance_ref`, `signature_ref`, `verified`, `cosign_certificate_identity`, `cosign_certificate_issuer`, `candidate_digest`, `index_digest`, `platform_digests`, and `promotion_status`.
- `workflow-policy.yaml` now allowlists `packages: write` for only the Story 4.5 `publish` job.
- 2026-06-10 follow-up validation: keep this story classified as implementation-complete, not final product release proof, until Story 5.9 records GHCR/staging publish evidence with real image refs, manifest-list digests, promoted final tags, and `latest=18-trixie` from an actual successful workflow run.
- Story 4.5 validation is wired into `make validate` through `cloudnative-pg-timescaledb/scripts/validate.sh`.

### Validation Commands

- `bash -n cloudnative-pg-timescaledb/scripts/validate-publish-gates.sh cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh` - PASS
- `bash cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh` - PASS
- `cloudnative-pg-timescaledb/scripts/validate-tags.sh --metadata cloudnative-pg-timescaledb/versions.yaml --date 20260609` - PASS
- `/tmp/codex-go-bin/actionlint .github/workflows/build.yml` - PASS
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh` - PASS, with local `actionlint`/`shellcheck` skips in PATH-based optional wrapper while direct actionlint passed separately
- `bash cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh` - PASS
- `bash cloudnative-pg-timescaledb/tests/security-scan/run.sh` - PASS
- `bash cloudnative-pg-timescaledb/tests/release-evidence/run.sh` - PASS
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` - PASS
- `git diff --cached --check` - PASS
- Staged snapshot `make validate` via `git checkout-index --all --prefix=<tmp>/ && make validate` - PASS

### File List

- `.github/workflows/build.yml`
- `cloudnative-pg-timescaledb/scripts/validate-candidate-metadata.py`
- `cloudnative-pg-timescaledb/scripts/validate-publish-gates.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/digest-mismatch.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/metadata-record-mismatch.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-build-gate.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-provenance.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-sbom.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-scan-gate.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-signature.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-smoke-gate.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/missing-tag-validation-gate.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/pg19beta1-normal-tag.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/valid-bookworm-release.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/valid-pg19beta1-experimental-release.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/valid-publish-release.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/verification-not-passed.json`
- `cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures/wrong-latest-bookworm.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/experimental-enters-publish-path.json`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh`
- `cloudnative-pg-timescaledb/workflow-policy.yaml`

### Change Log

- 2026-06-09: Completed Story 4.5 GHCR publish and tag promotion with release gate metadata pass-through, publish validation, workflow integration, fixtures, review fixes, and staged snapshot validation.
