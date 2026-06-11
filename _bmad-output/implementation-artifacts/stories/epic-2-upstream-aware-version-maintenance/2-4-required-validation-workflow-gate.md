---
storyId: 2.4
storyKey: 2-4-required-validation-workflow-gate
epic: 2
title: 'Required Validation Workflow Gate'
status: done
source: _bmad-output/planning-artifacts/epics.md
generatedOn: 2026-06-09
baseline_commit: 6c1ba90
---

# Story 2.4: Required Validation Workflow Gate

## Direct Scope

Implement this story's Source Story acceptance criteria and the Expected Artifacts below. Do not broaden the implementation into later story ownership.

## Dependencies

- Stories 2.1-2.3 in this epic may be assumed complete.

## Out of Scope

- Scheduled update/autocommit behavior; owned by Story 2.5.
- Build, scan, publish, signing, and release evidence workflows; owned by Epic 4.
- Documentation content validation beyond workflow/script safety; owned by Epic 5.

## Source Story

### Story 2.4: Required Validation Workflow Gate

As a maintainer,
I want validation workflow gates before update, build, scan, or publish workflows are considered complete,
So that broken GitHub Actions or shell scripts cannot become part of the automation path.

**Acceptance Criteria:**

**Given** repository scripts, Makefile targets, and GitHub Actions workflows exist
**When** `.github/workflows/validate.yml` runs
**Then** it triggers on `pull_request`, `push`, and `workflow_dispatch`.
**And** it runs `make validate`.
**And** it runs `actionlint` against all `.github/workflows/*.yml` files.
**And** it runs `shellcheck` against all `cloudnative-pg-timescaledb/scripts/**/*.sh` scripts.
**And** validation fails if CI-consumed shell scripts lack strict mode (`set -Eeuo pipefail`) or a documented exception.
**And** all third-party Actions in `update.yml`, `validate.yml`, `build.yml`, and `security-scan.yml` are pinned to full commit SHA with readable version comments, with any exception requiring an explicit allowlist entry.
**And** validation fails on `write-all`, broad top-level write permissions, pull request write tokens, or release-sensitive permissions outside named allowed jobs.

## Expected Artifacts

- `.github/workflows/validate.yml`
- `.github/actionlint.yaml`
- `cloudnative-pg-timescaledb/workflow-policy.yaml`
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`
- Root `Makefile` `validate` target wired to `cloudnative-pg-timescaledb/scripts/validate-workflows.sh` for workflow, action, permission, and shell validation
- `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/valid-least-privilege.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/write-all.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/top-level-write.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/pr-write-token.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/unpinned-action.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/release-sensitive-permission.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/valid-allowlisted-permission.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/invalid-allowlist-entry.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/missing-strict-mode.sh`

## Validation Workflow Contract

`.github/workflows/validate.yml` is the required CI gate before update, build, scan, or publish workflows are accepted as complete.

Required behavior:

- Triggers: `pull_request`, `push`, and `workflow_dispatch`.
- Default permissions are `{}` or read-only; no broad top-level write permissions.
- Runs `make validate`, `actionlint .github/workflows/*.yml`, `shellcheck cloudnative-pg-timescaledb/scripts/**/*.sh`, and `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`.
- `make validate` is the canonical local and CI gate and must invoke `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`; `validate.yml` may call the same script directly only for clearer diagnostics, not as CI-only behavior.
- `validate-workflows.sh` must validate `validate.yml` and must validate `update.yml`, `build.yml`, and `security-scan.yml` when present. Absence of later-owned workflows must not fail Story 2.4, but `validate.yml` and any present target workflow must satisfy action pinning and permissions rules.
- All third-party actions in existing workflow files must be pinned to full commit SHA with a readable version comment, unless explicitly allowlisted by `cloudnative-pg-timescaledb/workflow-policy.yaml`.
- The permissions validator must reject `write-all`, broad top-level write permissions, PR write tokens, unpinned actions, and release-sensitive permissions outside named allowed jobs.
- CI-consumed shell scripts must use `set -Eeuo pipefail` unless a documented exception is allowlisted.

Permission allowlist contract:

- `workflow-policy.yaml` top-level keys are `action_pin_exceptions`, `strict_mode_exceptions`, and `permission_allowlist`.
- `action_pin_exceptions[]` entries contain `workflow`, `job`, `action`, `reason`, and `owner_story`.
- `strict_mode_exceptions[]` entries contain `path`, `reason`, and `owner_story`.
- `permission_allowlist[]` entries contain `workflow`, `job`, `permission`, `reason`, and `owner_story`.
- Story 2.4 initial policy must allow no write permissions in `validate.yml`.

- `contents: write` is allowed only for named update/autocommit jobs.
- `packages: write` is allowed only for named publish jobs.
- `id-token: write` is allowed only for named signing or provenance jobs.
- `security-events: write` is allowed only for named SARIF upload jobs.
- `pull_request` workflows must never receive broad write tokens.
- All other write permissions are default-denied unless explicitly allowlisted with workflow, job, permission, reason, and owning story.
- Future owning stories extend the policy explicitly: Story 2.5 may add `update.yml` autocommit job with `contents: write`; Story 4.2/4.5 may add publish jobs with `packages: write`; Story 4.4 may add signing/provenance jobs with `id-token: write`; Story 4.3 may add SARIF upload jobs with `security-events: write`.

## Required Validation Commands

- make validate
- `actionlint .github/workflows/*.yml`
- `shellcheck cloudnative-pg-timescaledb/scripts/**/*.sh`
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`

Shell script discovery must be deterministic: `make validate` and `validate-workflows.sh` discover scripts with `git ls-files 'cloudnative-pg-timescaledb/scripts/**/*.sh'` or `find cloudnative-pg-timescaledb/scripts -type f -name '*.sh' -print0`; they must not rely on an unconfigured shell `**` expansion.

Shellcheck evidence correction: local `bash -n` fallback may be used only as an additional developer diagnostic when `shellcheck` is missing locally. It is not sufficient completion evidence for the public CI gate. `.github/workflows/validate.yml` must install or provide `shellcheck`, execute it against the deterministic script list, and fail if `shellcheck` is unavailable or reports findings.

## Required Tests and Fixtures

- `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` must run every workflow and shell fixture listed in Expected Artifacts.
- Include one positive fixture and negative fixtures for permissions, allowlist schema, release-sensitive permissions, action pinning, PR token safety, and shell strict mode.
- Keep diagnostics deterministic and include command, artifact path, expected value, actual value, and remediation.

## Tasks / Subtasks

- [x] Add `.github/workflows/validate.yml` with required triggers, least-privilege permissions, and calls to `make validate`.
- [x] Add `.github/actionlint.yaml` and `cloudnative-pg-timescaledb/workflow-policy.yaml` with the schema described above.
- [x] Implement `cloudnative-pg-timescaledb/scripts/validate-workflows.sh` for workflow permissions, action pinning, allowlist schema, and strict shell mode checks.
- [x] Wire root `Makefile` `validate` to run workflow validation, actionlint, shellcheck with deterministic script discovery, and existing validation scripts.
- [x] Add workflow-policy fixtures and `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`.
- [x] Run `make validate`, `actionlint .github/workflows/*.yml`, deterministic shellcheck, and `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`.

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
| FR-20 | 2.4, 4.7, 5.7, 5.9 | validate workflow, actionlint, shellcheck, docs validation | `.github/workflows/validate.yml`, `make validate`, release rehearsal |

## Direct NFR and Additional Traceability

| Requirement | Story IDs | Required Outcome |
| --- | --- | --- |
| NFR-3 Security | 2.4, 2.5, 4.3, 4.4, 4.7, 5.5, 5.9 | Least-privilege workflows, no secret leakage, OIDC signing, SARIF permissions, no PR write tokens, and no committed `.env` files. |
| Workflow requirements | 2.4, 2.5, 4.2, 4.3, 4.5, 4.7, 5.9 | `update.yml`, `validate.yml`, `build.yml`, and `security-scan.yml` exist, are validated, and participate in the release rehearsal. |

## Implementation Context

- Planning source: `_bmad-output/planning-artifacts/epics.md`
- PRD: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/prd.md`
- PRD addendum/vendor scan: `_bmad-output/planning-artifacts/prds/prd-containers-2026-06-09/addendum.md`
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Story output path: `_bmad-output/implementation-artifacts/stories/epic-2-upstream-aware-version-maintenance/2-4-required-validation-workflow-gate.md`

## Developer Notes

- Implement only this story's direct scope.
- Preserve prior stories' behavior and generated artifact contracts.
- Do not hand-edit generated files as the final fix; update metadata, templates, or generators and regenerate.
- Do not commit `.env` files, credentials, tokens, signing secrets, registry passwords, or secret-like values.
- Record changed paths, commands run, and validation output when this story is executed.

## Dev Agent Record

### Debug Log

- Added least-privilege `.github/workflows/validate.yml` with `pull_request`, `push`, and `workflow_dispatch` triggers.
- Added actionlint config and workflow policy schema file with empty initial allowlists.
- Implemented `validate-workflows.sh` for action pinning, readable version comments, top-level/job write permission checks, PR write token rejection, allowlist schema validation, and strict shell mode checks.
- Wired `make validate` through `scripts/validate.sh` to run workflow policy validation and workflow permission fixtures.
- Added fixtures for least privilege, write-all, top-level write, PR write token, unpinned action, release-sensitive permission, valid allowlisted permission, invalid allowlist schema, and missing shell strict mode.
- Addressed BMAD code-review findings by switching job permission checks from raw regex job blocks to parsed YAML jobs, checking required `validate.yml` commands only inside executable `run:` blocks, and preserving YAML-aware action job ownership for action allowlist checks.
- Added regression fixtures for inline-comment job IDs, quoted job IDs, flow-style job maps with job-level write permissions, unpinned reusable workflows, and `validate.yml` command strings that appear only in comments/names.
- Addressed BMAD code-review pass 2 findings by requiring required `validate.yml` gates to appear in unconditional jobs/steps and matching command-like executable lines after removing shell comments and output-only `echo`/`printf` lines.
- Added regression fixtures for commented/echoed required commands inside `run:` blocks and conditional-only validation gates.
- Addressed BMAD code-review pass 3 findings by excluding heredoc payload text from required gate matching, rejecting short-circuited required gates, requiring `apt-get install` to install `shellcheck`, and enforcing readable version comments for YAML-quoted pinned actions.
- Added regression fixtures for heredoc-only gates, short-circuited gates, `apt-get install` without `shellcheck`, and quoted pinned actions without readable version comments.
- Addressed BMAD code-review pass 4 findings by rejecting `|| true` failure masking on required gate lines, requiring `shellcheck` as an exact apt package token, skipping heredoc payloads with non-identifier delimiters, and ignoring required commands inside shell conditional blocks.
- Added regression fixtures for masked-failure gates, `shellcheck-doc` only installs, dashed heredoc delimiters, and shell `if` conditional gate bodies.
- Addressed BMAD code-review pass 5 findings by supporting one-line shell conditionals before real gates, preserving commands after closing shell block tokens, ignoring here-strings when detecting heredocs, supporting version-pinned `shellcheck=<version>` apt package tokens, and rejecting any `||` failure masking after required gate commands.
- Added regression fixtures for valid inline shell conditionals, valid here-strings before gates, valid version-pinned `shellcheck` installs, and masked failures using `|| echo`.
- Addressed BMAD code-review pass 6 findings by allowing ordinary stdout/stderr redirections after required gate commands while rejecting backgrounded gates, piped gates, `|&` gates, quoted-only gate text, and block-close failure masking.
- Added regression fixtures for valid gate redirections, heredoc suffix control flow before gates, shellcheck apt selectors, backgrounded gates, piped `|&` gates, quoted-only gates, and block-close masking.
- Addressed BMAD code-review pass 6 findings by preserving semicolons inside quoted shell text, avoiding heredoc detection on here-strings, supporting heredoc delimiters followed by control suffixes, rejecting backgrounded or piped required gate suffixes, preserving block-close control suffixes as executable text, and accepting apt selectors such as `shellcheck:amd64`.
- Added regression fixtures for quoted text containing gate-like commands, heredoc control suffixes before real gates, block-close masking, backgrounded gates, and valid apt selectors.
- Addressed BMAD code-review pass 7 preparation findings by preserving shell semicolon splitting with quote awareness, treating unsafe block-close suffixes as executable text that stops later gate recognition, and rejecting required gate lines with background or single-pipe suffixes.
- Added regression fixtures for valid heredoc control suffixes before gates, invalid backgrounded gates, and invalid quoted text containing gate-like command strings.
- Addressed BMAD code-review pass 7 findings by rejecting Bash `|&` suffixes on required gates while allowing common blocking redirection suffixes such as `2>&1`, `&>file`, `>file`, and `2>file`.
- Added regression fixtures for valid gate redirections and invalid `|&` required gate pipelines.
- Addressed BMAD code-review pass 8 preparation findings by treating backslashes literally inside single-quoted shell text, detecting heredoc redirections only outside quoted spans while preserving quoted delimiters, and adding explicit coverage for stderr redirection gates.
- Added regression fixtures for single-quoted backslash semicolon text, quoted heredoc marker strings, and valid `2>&1` gate redirections.
- Addressed BMAD code-review pass 8 findings by handling Bash ANSI-C `$'...'` escaped quotes in shell segment and heredoc scanning, tracking multiple heredoc delimiters as a queue, and keeping negative validator fixtures from being preempted by shellcheck diagnostics.
- Added regression fixtures for ANSI-C quoted gate-like text, ANSI-C quoted heredoc markers, and multiple heredoc payloads containing gate-like commands.
- Addressed BMAD code-review pass 9 findings by removing the leading `$` during ANSI-C heredoc delimiter quote removal and tracking escaped dollars before single quotes so escaped `$'...'` text is not treated as ANSI-C shell syntax.
- Added regression fixtures for real ANSI-C heredoc delimiters and escaped dollar before single-quote text.
- Addressed BMAD code-review pass 10 findings by making shell comment stripping quote-aware, tracking escaped dollars in heredoc delimiter scanning, and queueing heredocs discovered inside ignored shell conditional blocks before skipping their bodies.
- Added regression fixtures for escaped-dollar heredoc payload gates, quoted heredoc delimiters containing `#`, and heredoc payloads inside shell conditional blocks.
- Addressed BMAD code-review pass 11 findings by preserving non-comment `#` characters inside heredoc delimiters and queueing heredocs attached to block-close suffixes before ignoring non-executable payloads.
- Added regression fixtures for valid conditional hash heredocs, invalid unquoted hash heredoc payload gates, and invalid block-close heredoc payload gates.
- Addressed BMAD code-review pass 11 findings by preserving unquoted `#` inside shell words while still treating word-leading `#` as comments, and by queueing heredocs attached to shell block-close suffixes.
- Added regression fixtures for unquoted hash heredoc delimiters, conditional hash heredocs before real gates, and block-close heredoc payload gates.
- Addressed final BMAD code-review findings by requiring required gate matches to end on shell token boundaries, preserving escaped whitespace before `#` inside shell words, and collapsing shell backslash-newline continuations before heredoc scanning.
- Added regression fixtures for hash-suffixed fake gates, line-continuation hash heredoc payload gates, and valid escaped-space hash heredocs before real gates.

### Validation Commands

- `bash cloudnative-pg-timescaledb/scripts/validate-workflows.sh` - passed.
- `bash cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` - passed.
- `shellcheck -x cloudnative-pg-timescaledb/scripts/validate-workflows.sh cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh` - passed.
- `make validate` - passed.
- `actionlint .github/workflows/*.yml` - passed.
- `git ls-files 'cloudnative-pg-timescaledb/scripts/*.sh' 'cloudnative-pg-timescaledb/scripts/**/*.sh' | sort | xargs shellcheck -x` - passed.
- `git diff --check` - passed.
- Staged-index snapshot validation using a temporary detached `git worktree`, `git diff --cached --binary | git apply --index`, and `make validate` - passed.

### Completion Notes

- FR-20: validation workflow and local gate now validate workflow policy, scripts, and repository gates before future update/build/scan/publish stories are accepted.
- NFR-3: workflows default to least privilege; write-all, broad top-level write, PR write tokens, and unallowlisted release-sensitive permissions fail validation.
- Workflow requirements: `validate.yml` exists and validates current plus future `update.yml`, `build.yml`, and `security-scan.yml` files when present.
- Review follow-up: permission validation now covers YAML-valid job keys with comments, quoted IDs, flow-style mappings, and reusable workflow job-level `uses`; `validate.yml` command checks now ignore non-executable comments, display names, shell comments, output-only lines, conditional-only gates, heredoc payloads, and short-circuited commands.
- Review follow-up: shellcheck installation evidence now requires `apt-get install` to install `shellcheck`, and readable version comment enforcement covers quoted pinned `uses:` values.
- Review follow-up: required gates now remain blocking because masked-failure suffixes are not accepted, heredoc payload variants are ignored, and shell conditional block bodies do not satisfy unconditional gate checks.
- Review follow-up: the shell text filter now avoids false failures for valid one-line conditionals, commands after block closers, here-strings, and version-pinned shellcheck packages while continuing to reject non-blocking required gate lines.
- Review follow-up: required gate matching now treats redirections as valid but rejects backgrounding, pipes, pipe-ampersand, and quoted-only gate text as non-blocking or non-executed evidence.
- Review follow-up: required gates now reject `||`, backgrounding, and non-pipeline trailing control operators after a matched gate line; gate-like commands inside quoted text do not satisfy execution requirements.
- Review follow-up: block-close suffixes such as `fi || exit 0` no longer allow later commands to satisfy the required gate checks.
- Review follow-up: required gate suffix validation now distinguishes blocking redirection syntax from non-blocking/backgrounding and pipe operators, including Bash `|&`.
- Review follow-up: heredoc detection now scans shell text instead of masking quoted delimiters, so real `<<'EOF'` payloads are ignored while quoted `<<EOF` strings do not hide later real gates.
- Review follow-up: ANSI-C quoted strings and multiple heredoc payloads no longer let non-executed gate-like text satisfy required gate checks.
- Review follow-up: ANSI-C heredoc delimiters now terminate correctly, and escaped dollar-plus-single-quote text does not poison shell quote tracking.
- Review follow-up: heredoc markers containing `#` and heredocs inside ignored conditional blocks no longer allow non-executed payload text to satisfy required gates.
- Review follow-up: non-comment `#` heredoc delimiters and heredocs attached to `fi`/`done`/`esac` suffixes no longer allow payload-only gates to satisfy required validation checks.
- Review follow-up: unquoted hash heredoc delimiters now remain intact during comment stripping, including ignored-block cases where later real gates must still be visible.
- Review follow-up: required validation command matching now rejects hash-suffixed shell words, and heredoc/comment scanning handles shell line continuations plus escaped whitespace before `#`.

## File List

- `.github/workflows/validate.yml`
- `.github/actionlint.yaml`
- `cloudnative-pg-timescaledb/workflow-policy.yaml`
- `cloudnative-pg-timescaledb/scripts/validate-workflows.sh`
- `cloudnative-pg-timescaledb/scripts/validate.sh`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/*.yml`
- `cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures/missing-strict-mode.sh`

## Change Log

- Added required validation workflow and workflow policy validator.
- Added workflow permission/action pinning/strict-mode fixtures and test runner.
- Integrated workflow policy validation into `make validate`.
- 2026-06-10: Addressed BMAD code-review findings for YAML job parsing, executable `validate.yml` command checks, and shellcheck evidence.
- 2026-06-10: Hardened workflow validation for reusable workflows, conditional required gates, and commented/echoed required commands.
- 2026-06-10: Hardened workflow validation for heredoc/short-circuit gate bypasses, explicit shellcheck installation, and quoted pinned action version comments.
- 2026-06-10: Hardened workflow validation for masked failures, exact shellcheck package matching, dashed heredoc delimiters, and shell conditional bodies.
- 2026-06-10: Hardened workflow validation for inline shell block parsing, here-strings, version-pinned shellcheck package tokens, generalized `||` masking, and matching positive fixtures.
- 2026-06-10: Hardened workflow validation for gate redirections versus backgrounded, piped, pipe-ampersand, and quoted-only gate lines.
- 2026-06-10: Hardened workflow validation for quoted shell text, heredoc control suffixes, block-close masking, backgrounded gates, and apt package selectors.
- 2026-06-10: Hardened workflow validation for shell quote-aware segmentation, unsafe block-close suffixes, and background/single-pipe required gate suffixes.
- 2026-06-10: Hardened required gate suffix validation for Bash `|&` pipelines while preserving valid redirection suffixes.
- 2026-06-10: Hardened quote/backslash handling, heredoc delimiter scanning, and explicit stderr redirection coverage.
- 2026-06-10: Hardened ANSI-C quote handling, multiple heredoc queues, and validator-specific fixtures that avoid shellcheck preemption.
- 2026-06-10: Hardened ANSI-C heredoc delimiter quote removal and escaped-dollar quote tracking.
- 2026-06-10: Hardened quote-aware comment stripping and heredoc queueing inside ignored shell blocks.
- 2026-06-11: Hardened non-comment hash heredoc delimiters and block-close heredoc suffix queueing.
- 2026-06-10: Hardened unquoted hash heredoc delimiters and block-close heredoc suffix handling.
- 2026-06-11: Hardened required gate token boundaries, shell line continuations, and escaped-space hash heredoc parsing after final BMAD review findings.
