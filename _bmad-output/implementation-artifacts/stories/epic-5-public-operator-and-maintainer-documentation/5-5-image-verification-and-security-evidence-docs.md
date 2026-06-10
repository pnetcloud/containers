---
storyId: 5.5
storyKey: 5-5-image-verification-and-security-evidence-docs
epic: 5
title: 'Image Verification and Security Evidence Docs'
status: review
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: 7198ede96e4b3ad563033a7afb3ed1f7dc56b725
---

# Story 5.5: Image Verification and Security Evidence Docs

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 5.1-5.4 in this epic may be assumed complete.

## Out of Scope

- Producing SBOM, provenance, signatures, and scan outputs; owned by Stories 4.3-4.4.
- Publishing and tag promotion; owned by Story 4.5.
- Troubleshooting catalog of all failures; owned by Story 5.8.
- End-to-end release rehearsal; owned by Story 5.9.

## Source Story

### Story 5.5: Image Verification and Security Evidence Docs

As a security-conscious platform engineer,
I want verification instructions for release evidence,
So that I can inspect signatures, SBOM, provenance, vulnerability scan results, and image labels before adoption.

**Acceptance Criteria:**

**Given** release evidence fixtures and staging or published image references
**When** users read `docs/user-guide/verifying-images.md` or security sections
**Then** docs explain how to verify image digests and signatures.
**And** docs explain where to find SBOM and provenance metadata.
**And** docs explain the vulnerability gate threshold and how scan results are surfaced.
**And** docs explain relevant image labels and how they map back to `versions.yaml`.
**And** docs state that missing SBOM, provenance, signature, or threshold-passing scan status is a release blocker.
**And** verification examples avoid secrets and do not require private credentials for public images.

## Expected Artifacts

- `docs/user-guide/verifying-images.md`
- security evidence verification examples
- `cloudnative-pg-timescaledb/tests/docs/verification/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/valid-verification-docs.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-cosign-issuer.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-cosign-identity.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/tag-without-digest.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/private-token-required.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-sbom-provenance.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-vulnerability-policy.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-label-metadata-mapping.md`

## Verification Documentation Contract

- Docs must verify immutable digest references, not mutable tags alone.
- Cosign examples must verify immutable digest references with `--certificate-oidc-issuer https://token.actions.githubusercontent.com` and exact per-run `--certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY"`, where the expected identity is derived from the allowed release ref such as `https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main` or the exact release tag ref. Broad tag regex verification is not allowed.
- Docs must explain where SBOM and provenance attestations are attached and how they map to the final multi-platform index digest and platform digests.
- Docs must reproduce the Vulnerability Verification Policy below and state that missing threshold pass blocks release promotion.
- Docs must explain image labels that map release images back to `versions.yaml`, including PostgreSQL version, Debian variant, TimescaleDB version, Toolkit version, source revision, and release date.
- Public verification examples must not require private credentials or expose secrets.

## Vulnerability Verification Policy

- Policy source file: `cloudnative-pg-timescaledb/config/vulnerability-policy.yaml`.
- Ignore policy file: `cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml`; undeclared ignores are rejected, and docs must not tell users to bypass the policy for normal releases.
- Required scanner: Trivy container image scanning, invoked by `.github/workflows/security-scan.yml` through the repository scan script.
- Required scanner command shape: `trivy image --scanners vuln --severity HIGH,CRITICAL --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml --format sarif --output <sarif> <image>@sha256:<digest>` plus JSON output for the same immutable digest.
- Severity threshold: any unignored `HIGH` or `CRITICAL` vulnerability fails the release gate.
- Pass/fail rule: publish promotion is allowed only when scan metadata exists for the same candidate digest, Trivy database update succeeds, scanner exit status is successful, JSON output exists, SARIF output exists when GitHub code scanning is enabled, and no unignored `HIGH` or `CRITICAL` finding remains.
- Database behavior: update the Trivy vulnerability database during the scan and fail closed if the database or scanner metadata cannot be fetched.
- Required outputs: SARIF artifact `security-scan.sarif`, scanner JSON artifact `security-scan.json`, summary field `scan_result`, and failure reason field when failed.
- User-visible docs must show where to inspect the Step Summary scan result, workflow artifacts, SARIF upload status when enabled, and the matching image digest.

## Required Validation Commands

- make validate
- `bash cloudnative-pg-timescaledb/tests/docs/verification/run.sh`

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/docs/verification/run.sh` must run every verification docs fixture listed in Expected Artifacts.
- Include negative fixtures for missing cosign issuer, missing cosign identity, tag-only verification, private token requirement, missing SBOM/provenance explanation, missing vulnerability policy, and missing image-label-to-metadata mapping.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Write `docs/user-guide/verifying-images.md` and security evidence examples that verify immutable digest references, not mutable tags alone.
- [x] Document exact cosign keyless verification using `--certificate-oidc-issuer https://token.actions.githubusercontent.com` and exact `--certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY"` derived from the release ref.
- [x] Explain where SBOM and provenance attestations are attached for the final multi-platform index digest and platform digests.
- [x] Document vulnerability threshold policy, scanner outputs, SARIF/JSON artifacts, failure behavior, and Step Summary locations from Story 4.3.
- [x] Document image labels that map release images back to `versions.yaml` and release metadata.
- [x] Add verification docs fixtures for missing issuer/identity, tag-only verification, private-token requirements, missing SBOM/provenance, missing vulnerability policy, and missing label mapping.
- [x] Run `make validate` and `bash cloudnative-pg-timescaledb/tests/docs/verification/run.sh`.

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
| FR-19 | 4.3, 4.7, 5.5, 5.8, 5.9 | security scan workflow, SARIF, vulnerability policy | `security-scan.yml`, SARIF upload, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-3 Security | 2.4, 2.5, 4.3, 4.4, 4.7, 5.5, 5.9 | Least-privilege workflows, no secret leakage, OIDC signing, SARIF permissions, no PR write tokens, and no committed `.env` files. |
| NFR-7 Public trust | 4.4, 4.5, 4.6, 5.1, 5.5, 5.9 | Labels, docs, SBOM, provenance, signatures, vulnerability scans, and catalogs make public releases inspectable. |
| Supply-chain release gates | 4.3, 4.4, 4.5, 4.7, 5.5, 5.9 | Vulnerability scan, SBOM, provenance, signing, permissions, and summaries block release when missing or failing. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-5-public-operator-and-maintainer-documentation/5-5-image-verification-and-security-evidence-docs.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Implementation Plan

- Add a public user guide for immutable digest verification, exact cosign OIDC verification, release evidence inspection, vulnerability policy, and image label mapping.
- Add concise security verification sections to root and package READMEs.
- Add docs validation and fixtures for exact issuer/identity, tag-only references, private-token guidance, SBOM/provenance coverage, vulnerability policy, and label mapping.
- Wire verification docs validation into `make validate`.

### Debug Log

- Baseline commit: `7198ede96e4b3ad563033a7afb3ed1f7dc56b725`.
- Initial RED validation failed as expected because `docs/user-guide/verifying-images.md` did not exist.
- Fixed validator false positives around explanatory certificate regex text and `unignored HIGH/CRITICAL` wording.
- Fixed review findings: exact issuer parsing, exact main certificate identity assignment, generalized digest-only checks for cosign/Trivy command references, and quoted/unquoted `IMAGE_REF` assignments.
- Used staged snapshot validation because the working tree contains unrelated existing Story 1.1 fixture changes.

### Completion Notes

- Implemented Story 5.5 for FR-17, FR-18, FR-19, NFR-3 Security, NFR-7 Public trust, and supply-chain release gates.
- `docs/user-guide/verifying-images.md`, root README, and package README now document digest verification, exact cosign issuer/identity, SBOM/provenance/signature/verification evidence, vulnerability scan policy, and image-label mapping to `versions.yaml`.
- Added deterministic docs guardrails and required positive/negative fixtures.
- Review subagent found validator bypasses; they were fixed and revalidated.
- Story status set to `review` after all tasks and validations passed.

### Validation Commands

- `bash cloudnative-pg-timescaledb/tests/docs/verification/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/security-scan/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/release-evidence/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/readme/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/catalog/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/tags/run.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh` - passed.
- `git diff --cached --check` - passed.
- Staged snapshot `make validate` via `git checkout-index --all --prefix="$tmpdir/"` - passed.

## File List

- `README.md`
- `docs/user-guide/verifying-images.md`
- `cloudnative-pg-timescaledb/README.md`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/docs/verification/run.sh`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/valid-verification-docs.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-cosign-issuer.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-cosign-identity.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/tag-without-digest.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/private-token-required.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-sbom-provenance.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-vulnerability-policy.md`
- `cloudnative-pg-timescaledb/tests/docs/verification/fixtures/missing-label-metadata-mapping.md`

## Change Log

- 2026-06-10: Added image verification and security evidence docs with validation fixtures for Story 5.5.
- 2026-06-10: Addressed review findings for exact cosign issuer/identity and tag-only verification bypasses.
