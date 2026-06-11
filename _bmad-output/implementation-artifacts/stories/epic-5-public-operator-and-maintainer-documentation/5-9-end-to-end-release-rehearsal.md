---
storyId: 5.9
storyKey: 5-9-end-to-end-release-rehearsal
epic: 5
title: 'End-to-End Release Rehearsal'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
---

# Story 5.9: End-to-End Release Rehearsal

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 5.1-5.8 in this epic may be assumed complete.

## Out of Scope

- Kubernetes cluster e2e testing, operator install testing, and real backup/restore validation.
- Manual release approval policy outside the automated release evidence gates.
- Artifact Hub publication metadata for v1.

## Source Story

### Story 5.9: End-to-End Release Rehearsal

As a maintainer,
I want a full release pipeline rehearsal from a clean checkout,
So that the completed stories prove the repository can update, validate, build, smoke-test, scan, sign, publish-rehearse, generate catalogs, and validate docs as one working system.

**Acceptance Criteria:**

**Given** a clean checkout, deterministic UTC release date, and fixture or staging GHCR namespace
**When** the release rehearsal runs
**Then** it runs `make update` and verifies both changed and no-op update behavior.
**And** it runs `make generate` and `make validate` from a clean checkout.
**And** it runs Buildx/Bake for every metadata entry with `publish: true`, including all supported PostgreSQL/Debian/platform candidates.
**And** it verifies `publish: false` and `skip_reason` behavior for unsupported or experimental combinations that are intentionally not publishable.
**And** it runs container and SQL smoke tests for every publishable PostgreSQL/Debian/platform candidate.
**And** it runs the required vulnerability scan gate and records pass/fail output.
**And** it generates or verifies SBOM and provenance for the exact candidate digest.
**And** it performs keyless signing or signing dry-run against immutable digest references and verifies the expected issuer and identity policy.
**And** it performs GHCR publish rehearsal using a staging namespace or dry-run mode and proves final tags are not promoted unless all release gates pass.
**And** it dispatches the GitHub Actions release rehearsal dry-run/staging path and records workflow run URL, status, and conclusion evidence from the actual workflow run.
**And** it generates `catalog-standard-trixie.yaml` and `catalog-standard-bookworm.yaml` from release metadata and validates catalog references.
**And** it validates README, tag docs, catalog docs, Barman Cloud Plugin docs, generated-file docs, verification docs, maintainer docs, and troubleshooting docs.
**And** it verifies no `.env`, credential, token, signing secret, registry password, or secret-like value is committed or printed in summaries.
**And** it intentionally removes or fakes missing SBOM, provenance, signature, vulnerability pass status, wrong `latest`, or stale generated files in fixture mode and proves each case blocks release.
**And** it writes one release rehearsal report with commands run, image references, digests, tags, catalog paths, security evidence references, skipped combinations, failure reasons, and remediation commands.
**And** the release rehearsal is not a Kubernetes cluster e2e test; it validates the repository release pipeline and published-image contract.

## Expected Artifacts

- `cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`
- root `Makefile` target `release-rehearsal`
- `.github/workflows/release-rehearsal.yml` workflow dispatch path wired to dry-run/staging mode
- `cloudnative-pg-timescaledb/config/release-rehearsal.yaml`
- `cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/valid-full-matrix.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/no-op-update.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/changed-update-autocommit.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/missing-publishable-pg-debian-platform.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/missing-smoke-result.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/missing-sbom.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/missing-provenance.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/missing-signature.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/vulnerability-threshold-failed.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/wrong-latest.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/latest-not-pg18-trixie.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/stale-generated-files.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/unpublished-catalog-reference.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/secret-in-summary.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/pg19beta1-promoted-to-latest.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/vendor-used-as-build-context.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/vendor-used-as-runtime-input.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/alpine-release-candidate.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/bullseye-release-candidate.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/unsupported-debian-variant.json`

## Release Rehearsal Contract

- The rehearsal starts from a clean checkout and deterministic UTC date `20260609` unless the caller provides another UTC date.
- The rehearsal must enumerate every metadata entry with `publish: true` and every listed platform, including PostgreSQL `17`, PostgreSQL `18`, Debian `trixie`, Debian `bookworm`, `linux/amd64`, and `linux/arm64` where publishable.
- The rehearsal must fail unless stable PostgreSQL `17` and PostgreSQL `18` primary `trixie` entries are publishable and have `linux/amd64` and `linux/arm64` build, container smoke, SQL smoke, vulnerability scan, SBOM, provenance, signature or signing dry-run, publish rehearsal, and catalog evidence. `latest` remains restricted to `18-trixie`; `19beta1` remains experimental and never latest; `bookworm` follows metadata/package availability policy.
- The rehearsal must prove there is no missing publishable PostgreSQL/Debian/platform candidate by comparing `versions.yaml`, generated matrix JSON, Bake targets, build outputs, smoke outputs, scan outputs, evidence outputs, publish rehearsal outputs, and catalog outputs.
- The rehearsal must prove every Docker/Bake/workflow build context, Dockerfile `COPY`/`ADD` source, runtime dependency, generated release artifact, and publish/catalog input excludes `vendor/`; any consumption of `vendor/` as build context or runtime input is a release-blocking failure.
- The rehearsal must hard-fail release candidates for Alpine, `bullseye`, or any Debian variant other than `trixie` and `bookworm`, even if earlier README/docs validation also rejects those names.
- PostgreSQL `19beta1` must be covered as experimental: rehearse its explicit `publish`/`skip_reason` behavior, ensure it never receives `latest`, and fail if it is promoted to a normal stable tag without metadata policy change.
- `latest` must resolve to the publishable PostgreSQL `18` Debian `trixie` multi-platform manifest-list digest. PostgreSQL `17`, Debian `bookworm`, and PostgreSQL `19beta1` must not receive `latest`; `wrong-latest.json` and `latest-not-pg18-trixie.json` must use expected value `18-trixie`.
- The rehearsal must execute both no-op update and changed update/autocommit fixture paths and prove generated file drift is detected.
- Build, smoke, vulnerability, SBOM, provenance, signing, publish, and catalog stages must use the same candidate digest or manifest-list digest expected by Stories 4.2-4.6.
- GHCR publish rehearsal must use dry-run or staging namespace configuration and must prove final tags are not promoted until all release gates pass.
- The GitHub Actions rehearsal path is mandatory: `.github/workflows/release-rehearsal.yml` must support `workflow_dispatch` inputs `dry_run`, `date`, and `staging_namespace`, run the same dry-run/staging release rehearsal checks as the local command, and be validated with `actionlint`.
- Completion requires `gh workflow run release-rehearsal.yml ...` followed by `gh run watch` and `gh run view --json url,status,conclusion`, or CI evidence from the same repository workflow that actually invokes that GitHub `workflow_dispatch` workflow and records run URL, status, and successful conclusion. Static validation, local script execution, actionlint-only checks, documentation-only evidence, or a different workflow are not sufficient substitutes.
- The report must include commands run, matrix entries, image references, candidate digests, platform digests, final tags, `latest` target and expected value `18-trixie`, catalog paths, scan status, SBOM/provenance/signature references, GitHub Actions `release-rehearsal.yml` workflow run URL/status/conclusion, skipped combinations, failure reasons, and remediation commands.
- The rehearsal must fail if secrets or secret-like values appear in committed files or workflow summaries.

## Required Validation Commands

- `bash cloudnative-pg-timescaledb/scripts/release-rehearsal.sh --dry-run --date 20260609`
- `make release-rehearsal DATE=20260609 DRY_RUN=1`
- `actionlint .github/workflows/release-rehearsal.yml`
- `gh workflow run release-rehearsal.yml -f dry_run=true -f date=20260609 -f staging_namespace=ghcr.io/pnetcloud/cloudnative-pg-timescaledb-rehearsal`
- `gh run watch <run-id>`
- `gh run view <run-id> --json url,status,conclusion`
- `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`
- make validate

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh` must run every release rehearsal fixture listed in Expected Artifacts.
- Include positive fixtures for the full publishable matrix, no-op update, and changed update/autocommit path.
- Include negative fixtures for missing publishable PG/Debian/platform candidate, stable PostgreSQL `17` or `18` primary `trixie` not publishable, missing stable `amd64`/`arm64` evidence, missing smoke result, missing SBOM, missing provenance, missing signature, vulnerability threshold failure, missing workflow dispatch run evidence, wrong `latest`, `latest` not resolving to PostgreSQL `18` `trixie`, stale generated files, unpublished catalog reference, secret in summary, PostgreSQL `19beta1` promoted to `latest`, `vendor/` used as build context, `vendor/` used as runtime input, Alpine candidate, `bullseye` candidate, and unsupported Debian variant candidate.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Implement `cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`, root `make release-rehearsal`, `.github/workflows/release-rehearsal.yml`, and `cloudnative-pg-timescaledb/config/release-rehearsal.yaml` for dry-run/staging release rehearsal.
- [x] Rehearse `make update`, `make generate`, `make validate`, Buildx/Bake, per-platform container and SQL smoke, vulnerability scan, SBOM/provenance, signing or signing dry-run, publish dry-run/staging, catalog generation, docs validation, and secret checks from a clean checkout.
- [x] Replace fixture/evidence-only release rehearsal validation with an actual clean-checkout orchestration path, or explicitly split the evidence validator from the command runner, so the story proves the commands are executed rather than only proving that a report fixture claims they were executed. The default `make release-rehearsal` path now runs a clean-checkout command runner; `--fixture` remains the explicit evidence-validator mode for deterministic tests.
- [x] Enumerate every publishable PostgreSQL/Debian/platform candidate and prove `publish: false`/`skip_reason`, PG19 experimental, and `latest=18-trixie` behavior.
- [x] Validate GitHub Actions `workflow_dispatch` dry-run/staging path and record `release-rehearsal.yml` workflow URL, status, and successful conclusion from the same repository workflow run.
- [x] Generate `cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md` with commands, image refs, digests, tags, catalogs, security evidence, skipped combinations, failures, and remediation.
- [x] Validate GitHub Actions `workflow_dispatch` dry-run/staging path by invoking the actual workflow, watching the run, and recording URL, status, and successful conclusion; local/static/actionlint-only evidence is not sufficient.
- [x] Add release rehearsal fixtures for full matrix, update paths, missing candidates, stable PG17/18 trixie publishability/evidence gaps, missing smoke/evidence, missing workflow dispatch evidence, vulnerability failure, wrong latest, stale generated files, unpublished catalog references, secret leakage, PG19beta1 latest promotion, vendor build/runtime consumption, Alpine, `bullseye`, and unsupported Debian variants.
- [x] Run `bash cloudnative-pg-timescaledb/scripts/release-rehearsal.sh --dry-run --date 20260609`, `make release-rehearsal DATE=20260609 DRY_RUN=1`, `actionlint .github/workflows/release-rehearsal.yml`, the required `gh workflow run`/`gh run watch`/`gh run view` workflow dispatch validation, `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`, and `make validate`.

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
| FR-4 | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.1, 5.9 | experimental metadata, resolver fixtures, catalog policy, docs | `validate-metadata.sh`, `validate-tags.sh`, catalog validation |
| FR-5 | 2.2, 3.2, 3.5, 5.9 | package resolver, Dockerfile template, SQL smoke | resolver tests, `make build`, `make smoke` |
| FR-6 | 2.2, 3.2, 3.5, 5.9 | Toolkit package metadata, install checks, SQL smoke | resolver tests, `dpkg-query`, `CREATE EXTENSION timescaledb_toolkit` |
| FR-7 | 3.2, 3.4, 3.5, 5.9 | pgvector/PGAudit metadata, control files, SQL smoke | `dpkg-query`, control-file checks, SQL extension checks |
| FR-8 | 2.7, 3.6, 5.4, 5.7, 5.9 | Barman Cloud Plugin references, docs validation fixtures | docs validation, forbidden legacy `barman-cloud` checks |
| FR-10 | 2.3, 2.5, 4.6, 5.7, 5.9 | update autocommit, generated artifacts, release catalogs, docs | no-op update test, path allowlist, `make validate`, rehearsal report |
| FR-12 | 1.5, 4.1, 4.2, 5.9 | matrix schema, workflow `fromJSON`, release metadata artifacts | `generate-matrix.sh`, workflow validation, release rehearsal |
| FR-13 | 3.3, 4.2, 4.5, 5.9 | Buildx/Bake targets, per-platform candidates, manifest digests | `make build`, per-platform smoke, release rehearsal |
| FR-14 | 3.4, 3.5, 4.2, 5.9 | container smoke, SQL smoke, per-platform smoke gates | `make smoke`, platform-specific smoke, release rehearsal |
| FR-15 | 1.4, 4.5, 4.7, 5.2, 5.9 | tag policy, GHCR publish job, image tag docs | `validate-tags.sh`, publish rehearsal, docs validation |
| FR-16 | 4.6, 5.3, 5.9 | digest-aware catalogs, catalog docs | `generate-catalog.sh`, catalog validation, release rehearsal |
| FR-17 | 4.4, 4.7, 5.5, 5.9 | SBOM, provenance, release evidence docs | evidence verification, release rehearsal |
| FR-18 | 4.4, 4.7, 5.5, 5.9 | OIDC signatures, digest verification docs | signature verification, release rehearsal |
| FR-19 | 4.3, 4.7, 5.5, 5.8, 5.9 | security scan workflow, SARIF, vulnerability policy | `security-scan.yml`, SARIF upload, release rehearsal |
| FR-20 | 2.4, 4.7, 5.7, 5.9 | validate workflow, actionlint, shellcheck, docs validation | `.github/workflows/validate.yml`, `make validate`, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-1 Reliability | 2.3, 2.5, 5.8, 5.9 | Scheduled and local updates are idempotent, clean no-op runs create no commits, failure reasons are documented and rehearsed. |
| NFR-2 Reproducibility | 1.1, 1.3, 1.5, 1.6, 3.1, 4.2, 4.4, 5.9 | Metadata, digests, package versions, platforms, tags, generated outputs, and release evidence explain each image after the fact. |
| NFR-3 Security | 2.4, 2.5, 4.3, 4.4, 4.7, 5.5, 5.9 | Least-privilege workflows, no secret leakage, OIDC signing, SARIF permissions, no PR write tokens, and no committed `.env` files. |
| NFR-5 Observability | 2.3, 2.5, 4.3, 4.7, 5.8, 5.9 | Update/build/publish/scan workflows write summaries with versions, tags, digests, skipped combinations, evidence status, and failure reasons. |
| NFR-6 Portability | 1.3, 2.2, 3.3, 4.2, 5.9 | `linux/amd64` and `linux/arm64` availability is resolved, built, smoked per platform, and rehearsed for every publishable combination. |
| NFR-7 Public trust | 4.4, 4.5, 4.6, 5.1, 5.5, 5.9 | Labels, docs, SBOM, provenance, signatures, vulnerability scans, and catalogs make public releases inspectable. |
| NFR-8 Automation safety | 1.6, 2.5, 4.6, 5.6, 5.7, 5.9 | Generated artifacts are reproducible, committed through controlled paths, validated for drift, and never hand-edited as final fixes. |
| Makefile command surface | 1.2, 2.3, 3.3, 4.1, 4.6, 5.6, 5.9 | Root `Makefile` exposes stable `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke` targets that delegate to scripts. |
| Debian scope | 1.1, 1.3, 2.1, 2.2, 3.4, 5.1, 5.9 | Only `trixie` and `bookworm` are accepted; Alpine, `bullseye`, and other variants hard-fail. |
| PostgreSQL scope | 1.1, 1.3, 1.4, 2.2, 4.1, 4.6, 5.9 | `17`, `18`, and experimental `19beta1` are supported according to metadata and release gates. |
| Barman Cloud Plugin boundary | 2.7, 3.6, 5.4, 5.7, 5.9 | Barman support uses the CloudNativePG Barman Cloud Plugin path and rejects legacy in-image `barman-cloud` guidance or packages. |
| Workflow requirements | 2.4, 2.5, 4.2, 4.3, 4.5, 4.7, 5.9 | `update.yml`, `validate.yml`, `build.yml`, and `security-scan.yml` exist, are validated, and participate in the release rehearsal. |
| Generated artifacts | 1.5, 1.6, 3.1, 4.1, 4.6, 5.7, 5.9 | Dockerfiles, Bake file, matrix JSON, catalogs, docs tables, and README examples are generated or validated and drift-checked. |
| Tag policy | 1.4, 4.5, 5.2, 5.9 | Immutable, rolling, `bookworm` suffix, experimental, and `latest` rules are generated, validated, documented, and rehearsed. |
| Supply-chain release gates | 4.3, 4.4, 4.5, 4.7, 5.5, 5.9 | Vulnerability scan, SBOM, provenance, signing, permissions, and summaries block release when missing or failing. |
| Artifact Hub out of scope | 5.1, 5.6, 5.9 | Docs and release rehearsal keep Artifact Hub metadata out of v1 scope. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-5-public-operator-and-maintainer-documentation/5-9-end-to-end-release-rehearsal.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Implemented local release rehearsal script, config, Make target, workflow dispatch path, generated report, fixtures, and validation wiring.
- Subagent workflow review found unsafe Make/workflow input interpolation and non-current workflow evidence in the report; fixed by exporting Make variables, validating workflow inputs in shell, and allowing current workflow run URL/status/conclusion overrides.
- Subagent release-contract review found weak secret scanning, path-based reference-tree bypasses, placeholder-only supply-chain evidence, and nondeterministic diagnostics; fixed with recursive redacted secret location scanning, path-segment reference-tree checks, digest-bound scan/SBOM/provenance/signature evidence, and sorted diagnostics.
- Actual GitHub workflow dispatch attempted with `gh workflow run release-rehearsal.yml -f dry_run=true -f date=20260609 -f staging_namespace=ghcr.io/pnetcloud/cloudnative-pg-timescaledb-rehearsal`; GitHub returned `HTTP 404` because the new workflow is not yet present on the remote/default branch.
- 2026-06-10 independent subagent story validation confirmed Story 5.9 must remain open: GitHub Actions API still lists only `Validate` and `Build Release Candidates`, and `gh workflow view release-rehearsal.yml --repo pnetcloud/containers --yaml` returns `HTTP 404`.
- 2026-06-10 independent subagent release-rehearsal review found the local script primarily validates JSON evidence/fixtures, including command names in `commands_run`, rather than actually executing the full clean-checkout update/generate/validate/build/smoke/scan/SBOM/provenance/sign/publish/catalog path. This is now tracked as an open task above.
- 2026-06-10 remote GitHub Actions evidence on commit `b28e37bc22f4f94c92244e8e2b069076e1b3ca3b`: `Validate` completed successfully at `https://github.com/pnetcloud/containers/actions/runs/27264911399`; `Build Release Candidates` completed successfully at `https://github.com/pnetcloud/containers/actions/runs/27264911804`, including PG17/PG18 trixie/bookworm candidate build, smoke, vulnerability scan, and SARIF upload jobs.
- 2026-06-10 CI determinism gap found and fixed outside this story: `validate-generated.sh` previously inspected live CNPG manifests during `make validate`, causing a GitHub `502 Bad Gateway` failure; it now creates a deterministic manifest fixture from `versions.yaml` unless `CNPG_MANIFEST_FIXTURE` is already provided.
- 2026-06-10 follow-up implementation split Story 5.9 into two explicit paths: default clean-checkout orchestration and `--fixture` evidence validation. The orchestration path refuses dirty source checkouts, clones the current HEAD, runs `make update`, `make generate`, `make validate`, `make matrix`, `make bake-print`, per-publishable-row `make build`, per-platform container and SQL smoke, `make catalog`, and docs validation, records command logs, and fail-fasts on the first failed release gate. Tests now use shims to prove commands are actually invoked rather than only present as JSON strings.
- 2026-06-10 workflow self-certification was removed: `release-rehearsal.yml` no longer injects `WORKFLOW_RUN_STATUS=completed` or `WORKFLOW_RUN_CONCLUSION=success`. Completion evidence must come from external `gh run view` after the workflow finishes.
- 2026-06-10 update/release rehearsal fixture handling was hardened so `make update --fixtures` consumes CNPG, packagecloud, and Barman plugin references from one deterministic fixture root, fails before update when resolver-owned generated paths are dirty, and preserves maintainer-authored skip reasons while updating resolver-owned CNPG/package skip evidence.
- 2026-06-10 current remote evidence on commit `74ba26549cffbd7773c064c42a87e0a36f2b85b9`: `Validate` completed successfully at `https://github.com/pnetcloud/containers/actions/runs/27307233496`; `Build Release Candidates` completed successfully at `https://github.com/pnetcloud/containers/actions/runs/27307233530`; `Release Rehearsal` workflow_dispatch completed successfully at `https://github.com/pnetcloud/containers/actions/runs/27307826931` with job `Dry-run or staging release rehearsal` successful.

### Completion Notes

- Local release rehearsal and all repository validation gates pass from a staged clean checkout snapshot.
- `release-rehearsal.yml` is SHA-pinned, least-privilege (`contents: read`), and invokes the same `make release-rehearsal` command surface.
- Successful `Validate` and `Build Release Candidates` runs prove the repository validation path and publishable PG17/PG18 trixie/bookworm release-candidate build/smoke/security-scan path on GitHub Actions for commit `74ba26549cffbd7773c064c42a87e0a36f2b85b9`.
- Successful `Release Rehearsal` workflow_dispatch run proves the required GitHub Actions dry-run/staging path on the same commit line: URL `https://github.com/pnetcloud/containers/actions/runs/27307826931`, status `completed`, conclusion `success`.
- Story 5.9 is closed because local fixture/orchestration tests, remote `Validate`, remote `Build Release Candidates`, and remote `release-rehearsal.yml` workflow_dispatch evidence now all pass.

### Validation Commands

- `bash cloudnative-pg-timescaledb/scripts/release-rehearsal.sh --dry-run --date 20260609` passed.
- `make release-rehearsal DATE=20260609 DRY_RUN=1 RELEASE_REHEARSAL_ARGS=--no-report` passed.
- `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh` passed.
- `PATH="$(go env GOPATH)/bin:$PATH" actionlint .github/workflows/release-rehearsal.yml` passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/update/run.sh` passed after deterministic fixture-root and dirty-generated-path hardening.
- `bash cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` passed after moving Barman plugin update fixtures into the shared update fixture root.
- `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh` passed after release rehearsal consumed the shared update fixture root.
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` passed.
- `shellcheck -x cloudnative-pg-timescaledb/scripts/release-rehearsal.sh cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh cloudnative-pg-timescaledb/tests/update/run.sh cloudnative-pg-timescaledb/tests/barman-plugin/run.sh` passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh` passed.
- `git diff --check` passed.
- `gh workflow run release-rehearsal.yml --repo pnetcloud/containers --ref codex/bmad-cloudnativepg-timescaledb-execution -f dry_run=true -f date=20260609 -f staging_namespace=ghcr.io/pnetcloud/cloudnative-pg-timescaledb-rehearsal` dispatched successfully.
- `gh run view 27307826931 --repo pnetcloud/containers --json status,conclusion,url,headSha,jobs` returned status `completed`, conclusion `success`, URL `https://github.com/pnetcloud/containers/actions/runs/27307826931`, head SHA `74ba26549cffbd7773c064c42a87e0a36f2b85b9`, and job `Dry-run or staging release rehearsal` conclusion `success`.
- `gh run view 27307233496 --repo pnetcloud/containers --json status,conclusion,url,headSha,jobs` returned status `completed`, conclusion `success`, URL `https://github.com/pnetcloud/containers/actions/runs/27307233496`, and head SHA `74ba26549cffbd7773c064c42a87e0a36f2b85b9`.
- `gh run view 27307233530 --repo pnetcloud/containers --json status,conclusion,url,headSha,jobs` returned status `completed`, conclusion `success`, URL `https://github.com/pnetcloud/containers/actions/runs/27307233530`, and head SHA `74ba26549cffbd7773c064c42a87e0a36f2b85b9`.
- `bash cloudnative-pg-timescaledb/scripts/validate-generated.sh` passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-docs.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/generated-drift/run.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/update/run.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh` passed.
- `bash cloudnative-pg-timescaledb/tests/docs-validation/run.sh` passed.
- `git diff --cached --check` passed.
- Staged clean checkout snapshot `make validate` passed.
- `gh workflow run release-rehearsal.yml -f dry_run=true -f date=20260609 -f staging_namespace=ghcr.io/pnetcloud/cloudnative-pg-timescaledb-rehearsal` blocked with `HTTP 404` before workflow publication; `gh run watch` and `gh run view --json url,status,conclusion` were not possible.
- `make validate` passed on 2026-06-10 after deterministic CNPG manifest fixture hardening for `validate-generated.sh`.
- `gh run watch 27264911399 --repo pnetcloud/containers --exit-status` passed for `Validate` on commit `b28e37bc22f4f94c92244e8e2b069076e1b3ca3b`.
- `gh run watch 27264911804 --repo pnetcloud/containers --exit-status` passed for `Build Release Candidates` on commit `b28e37bc22f4f94c92244e8e2b069076e1b3ca3b`.
- `gh workflow view release-rehearsal.yml --repo pnetcloud/containers --yaml` still returns `HTTP 404`; required `workflow_dispatch` run/watch/view evidence is still blocked.
- `bash cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh` passed after adding orchestration-shim proof for command execution and fail-fast behavior.
- `shellcheck cloudnative-pg-timescaledb/scripts/release-rehearsal.sh cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh` passed.
- `PATH="$(go env GOPATH)/bin:$PATH" actionlint .github/workflows/release-rehearsal.yml` passed.
- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh` passed.

### File List

- `.github/workflows/release-rehearsal.yml`
- `Makefile`
- `cloudnative-pg-timescaledb/config/release-rehearsal.yaml`
- `cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md`
- `cloudnative-pg-timescaledb/scripts/release-rehearsal.sh`
- `cloudnative-pg-timescaledb/scripts/lib/cnpg.sh`
- `cloudnative-pg-timescaledb/scripts/lib/update_contract.py`
- `cloudnative-pg-timescaledb/scripts/lib/generator_contract.py`
- `cloudnative-pg-timescaledb/scripts/make-help.sh`
- `cloudnative-pg-timescaledb/scripts/validate-docs.sh`
- `cloudnative-pg-timescaledb/scripts/validate-generated.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/generated-drift/run.sh`
- `cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json`
- `cloudnative-pg-timescaledb/tests/generators/run.sh`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/*.json`
- `cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh`
- `cloudnative-pg-timescaledb/tests/barman-plugin/run.sh`
- `cloudnative-pg-timescaledb/tests/update/run.sh`
- `cloudnative-pg-timescaledb/tests/docs-validation/run.sh`
- `docs/generator-contracts.md`

### Change Log

- Added deterministic release rehearsal command, config, workflow dispatch, generated report, fixture suite, and validation integration.
- Extended generated-doc manifest ownership so `release-rehearsal-report.md` is accepted by drift checks while remaining owned by `release-rehearsal.sh`.
- Hardened rehearsal evidence validation for latest policy, Debian/PostgreSQL scope, platform coverage, supply-chain digest binding, secret redaction, and reference-tree exclusion.
- Hardened deterministic update fixture roots, resolver-owned skip evidence, dirty generated path guards, and closed Story 5.9 with successful current `release-rehearsal.yml` workflow_dispatch evidence.
