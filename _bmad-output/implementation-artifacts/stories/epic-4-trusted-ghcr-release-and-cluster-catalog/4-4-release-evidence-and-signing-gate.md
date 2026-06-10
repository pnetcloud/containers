---
storyId: 4.4
storyKey: 4-4-release-evidence-and-signing-gate
epic: 4
title: 'Release Evidence and Signing Gate'
status: complete
baseline_commit: 6f494505057a44581f1c3e15741d13dec69a0819
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 4.4: Release Evidence and Signing Gate

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 4.1-4.3 in this epic may be assumed complete.

## Out of Scope

- Vulnerability scanning; owned by Story 4.3.
- Final GHCR tag promotion; owned by Story 4.5.
- Public verification docs; owned by Story 5.5.

## Source Story

### Story 4.4: Release Evidence and Signing Gate

As a security-conscious platform engineer,
I want SBOM, provenance, and signatures generated and verified for immutable release digests,
So that GHCR release tag promotion cannot happen without supply-chain evidence.

**Acceptance Criteria:**

**Given** a release candidate has passed build, smoke, tag validation, and vulnerability gates
**When** the release evidence job runs
**Then** it generates SBOM and provenance using BuildKit/buildx attestations for the exact candidate digest that will be promoted.
**And** evidence is associated with the final multi-platform index digest and required platform digests.
**And** signing uses `cosign` keyless GitHub OIDC against immutable `ghcr.io/...@sha256:<digest>` references.
**And** signing covers the final multi-platform index digest and required platform digests.
**And** verification runs before tag promotion and fails unless certificate identity and issuer match this repository workflow.
**And** missing SBOM, provenance, signature, or threshold-passing scan status blocks GHCR release tag promotion.
**And** evidence references and verification results are emitted in the Step Summary.

## Expected Artifacts

- BuildKit/buildx SBOM and provenance attestation config in `.github/workflows/build.yml`
- cosign keyless signing and verification steps
- `cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md`
- `cloudnative-pg-timescaledb/tests/release-evidence/run.sh`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/valid-evidence.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/missing-sbom.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/missing-provenance.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/missing-signature.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/missing-verification.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/verification-failed.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/wrong-cosign-identity.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/wrong-cosign-issuer.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/wrong-digest-signed.json`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/missing-platform-digest-evidence.json`

## Release Evidence Contract

- Evidence is generated for the exact candidate digest and final multi-platform index digest that Story 4.5 will promote.
- Required evidence metadata keys: `image`, `candidate_digest`, `index_digest`, `platform_digests`, `per_digest_evidence`, `scan_result`, `expected_certificate_identity`, `cosign_certificate_issuer`, and `verified`.
- `per_digest_evidence` must contain one record for the final `index_digest` and one record for every digest in `platform_digests`; each record must include `digest`, `sbom_ref`, `provenance_ref`, `signature_ref`, `verification_ref`, and `verified`.
- Signing uses keyless `cosign` with GitHub OIDC and immutable `ghcr.io/...@sha256:<digest>` references only.
- Verification must derive the exact expected certificate identity for the current release ref, such as `https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main` or the exact release tag ref, and must use `cosign verify --certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY" --certificate-oidc-issuer https://token.actions.githubusercontent.com ...` instead of a broad tag regexp.
- Verification must iterate over the final `index_digest` and every entry in `platform_digests`.
- Missing SBOM, provenance, signature, threshold-passing scan status, missing verification, non-passing verification, stale verification, or digest-mismatched verification blocks publish for the same digest.
- Workflow permissions handoff: provenance/signing jobs require `id-token: write` and `contents: read`; only jobs that push candidates or publish final tags may have the required GHCR package write permission; PR workflows must not receive broad write tokens.
- Step Summary must include SBOM, provenance, signature, verification identity/issuer, scan status, candidate digest, index digest, and per-platform digests.

## Required Validation Commands

- `bash cloudnative-pg-timescaledb/tests/release-evidence/run.sh`
- `cosign verify --certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY" --certificate-oidc-issuer https://token.actions.githubusercontent.com ghcr.io/pnetcloud/cloudnative-pg-timescaledb@sha256:<digest>`
- `actionlint .github/workflows/build.yml`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/release-evidence/run.sh` must run every fixture listed in Expected Artifacts.
- Include negative fixtures for missing SBOM, missing provenance, missing signature, missing verification, failed verification, wrong cosign identity/issuer, signed digest mismatch, and missing per-platform digest evidence.
- `wrong-cosign-issuer.json` must use a correct repository workflow identity but `cosign_certificate_issuer != https://token.actions.githubusercontent.com`, and `run.sh` must reject it.
- Fixture/dry-run validation must enforce the same OIDC issuer and exact expected certificate identity used by the required `cosign verify` command.
- `cloudnative-pg-timescaledb/tests/release-evidence/run.sh` must reject absent, `false`, stale, or digest-mismatched verification results for both the final index digest and every platform digest.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Add BuildKit/buildx SBOM and provenance attestation configuration to `.github/workflows/build.yml` for the exact candidate digest and final multi-platform index digest that will be promoted.
- [x] Add keyless cosign signing for immutable `ghcr.io/...@sha256:<digest>` references using GitHub OIDC, covering the final multi-platform index digest and every required platform digest.
- [x] Add cosign verification before publish with issuer `https://token.actions.githubusercontent.com` and exact expected certificate identity derived from the current allowed release ref.
- [x] Iterate signing and verification over `index_digest` plus every `platform_digests[]` entry, failing if any digest lacks SBOM, provenance, signature, or passing verification metadata.
- [x] Emit release evidence metadata with candidate digest, index digest, platform digests, per-digest SBOM/provenance/signature/verification refs, scan result, expected OIDC identity/issuer, and verification status.
- [x] Restrict workflow permissions for provenance/signing to `id-token: write` plus `contents: read`, and keep GHCR package write permissions only on candidate/publish push jobs.
- [x] Ensure missing SBOM, provenance, signature, verification pass, or threshold-passing scan status blocks Story 4.5 promotion for the same digest.
- [x] Add release evidence fixtures and `cloudnative-pg-timescaledb/tests/release-evidence/run.sh` for missing evidence, wrong identity/issuer, and signed digest mismatch.
- [x] Run `bash cloudnative-pg-timescaledb/tests/release-evidence/run.sh`, `actionlint .github/workflows/build.yml`, and the documented `cosign verify` command against a real digest or an explicitly documented dry-run fixture when no published digest exists yet.

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
| FR-17 | 4.4, 4.7, 5.5, 5.9 | SBOM, provenance, release evidence docs | evidence verification, release rehearsal |
| FR-18 | 4.4, 4.7, 5.5, 5.9 | OIDC signatures, digest verification docs | signature verification, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-2 Reproducibility | 1.1, 1.3, 1.5, 1.6, 3.1, 4.2, 4.4, 5.9 | Metadata, digests, package versions, platforms, tags, generated outputs, and release evidence explain each image after the fact. |
| NFR-3 Security | 2.4, 2.5, 4.3, 4.4, 4.7, 5.5, 5.9 | Least-privilege workflows, no secret leakage, OIDC signing, SARIF permissions, no PR write tokens, and no committed `.env` files. |
| NFR-7 Public trust | 4.4, 4.5, 4.6, 5.1, 5.5, 5.9 | Labels, docs, SBOM, provenance, signatures, vulnerability scans, and catalogs make public releases inspectable. |
| Supply-chain release gates | 4.3, 4.4, 4.5, 4.7, 5.5, 5.9 | Vulnerability scan, SBOM, provenance, signing, permissions, and summaries block release when missing or failing. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-4-trusted-ghcr-release-and-cluster-catalog/4-4-release-evidence-and-signing-gate.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented Story 4.4 after Stories 4.1-4.3 were already committed.
- Subagent review was requested from reviewer `019ead6f-f063-7223-a43a-f71e276e4219`; review returned two BLOCKER findings.
- BLOCKER fix 1: changed candidate workflow to build one multi-platform candidate index directly with `docker buildx bake --sbom=true --provenance=mode=max`, then smoke each platform from that same candidate index. This avoids creating the promoted index later without BuildKit attestations.
- BLOCKER fix 2: changed release evidence validation from self-asserted refs/booleans to persisted verifier artifacts. `validate-release-evidence.py` now parses cosign verification JSON and raw BuildKit attestation index inspection output.
- Permission note: `release_evidence` needs `packages: write` because keyless cosign registry signatures are uploaded to GHCR. The permission is job-scoped, allowlisted, and the workflow has no `pull_request` trigger.

### Completion Notes

- Release candidate build now emits BuildKit SBOM/provenance attestations on the candidate index and verifies attestation manifests are present before uploading candidate metadata.
- Release evidence job runs after `security_scan`, validates the same candidate refs/platform digests were scanned, signs index and platform digests with cosign keyless OIDC, verifies exact workflow identity/issuer, stores verifier outputs, validates the evidence contract, uploads `release-evidence-${{ matrix.bake_target }}`, and writes Step Summary evidence.
- Generated `release-evidence-schema.md` is owned by `generate-docs.sh`; generated-drift, update, and autocommit allowlists were extended for the new generated artifact.
- Added negative fixtures for missing SBOM/provenance/signature/verification refs, failed verification, wrong identity, wrong issuer, signed digest mismatch, wrong verification output digest, missing attestation output, and missing platform digest evidence.

### Validation Commands Run

- `bash cloudnative-pg-timescaledb/tests/release-evidence/run.sh` - PASS
- `bash cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh` - PASS
- `bash cloudnative-pg-timescaledb/tests/security-scan/run.sh` - PASS
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh` - PASS
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` - PASS
- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` - PASS
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh` - PASS
- `/tmp/codex-go-bin/actionlint .github/workflows/*.yml` - PASS
- `git diff --cached --check` - PASS
- staged snapshot `make validate` - PASS
- Real `cosign verify ... ghcr.io/pnetcloud/cloudnative-pg-timescaledb@sha256:<digest>` was not run because no newly published digest exists in this local execution; dry-run fixture validation covers the exact command identity, issuer, digest, verifier-output, and BuildKit attestation inspection contract.
- 2026-06-10 follow-up validation: keep this story classified as implementation-complete, not final release proof, until Story 5.9 records real/staging digest evidence with `cosign verify` against an actual `ghcr.io/pnetcloud/cloudnative-pg-timescaledb@sha256:<digest>` candidate or published manifest-list digest.

### File List

- `.github/workflows/build.yml`
- `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`
- `cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `cloudnative-pg-timescaledb/scripts/validate-release-evidence.py`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/generated-drift/run.sh`
- `cloudnative-pg-timescaledb/tests/release-evidence/run.sh`
- `cloudnative-pg-timescaledb/tests/release-evidence/fixtures/**`
- `cloudnative-pg-timescaledb/tests/update/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/final-tag-pushed-in-candidate-job.yml`
- `cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/smoke-after-publish.yml`
- `cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh`
- `cloudnative-pg-timescaledb/workflow-policy.yaml`
- `docs/generator-contracts.md`

### Change Log

- 2026-06-09: Implemented release evidence/signing gate with BuildKit attestations, cosign keyless signing/verification, generated schema docs, evidence validator, and regression fixtures.
