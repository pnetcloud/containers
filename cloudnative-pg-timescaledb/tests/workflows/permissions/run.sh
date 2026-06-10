#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-workflows.sh"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

write_policy() {
  local target="$1"
  cat >"${target}" <<'EOF'
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist: []
EOF
}

write_allowlist_policy() {
  local target="$1"
  cat >"${target}" <<'EOF'
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist:
  - workflow: .github/workflows/update.yml
    job: publish
    permission: "packages: write"
    reason: Story fixture release permission
    owner_story: Story 4.5
EOF
}

write_update_policy() {
  local target="$1"
  cat >"${target}" <<'EOF'
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist:
  - workflow: .github/workflows/update.yml
    job: autocommit
    permission: "contents: write"
    reason: Commit resolver-owned metadata and generated artifacts after make validate
    owner_story: 2.5
EOF
}

write_update_wrong_reason_policy() {
  local target="$1"
  cat >"${target}" <<'EOF'
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist:
  - workflow: .github/workflows/update.yml
    job: autocommit
    permission: "contents: write"
    reason: Wrong reason
    owner_story: 2.5
EOF
}

write_update_wrong_owner_policy() {
  local target="$1"
  cat >"${target}" <<'EOF'
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist:
  - workflow: .github/workflows/update.yml
    job: autocommit
    permission: "contents: write"
    reason: Commit resolver-owned metadata and generated artifacts after make validate
    owner_story: 9.9
EOF
}

write_update_wrong_level_policy() {
  local target="$1"
  cat >"${target}" <<'EOF'
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist:
  - workflow: .github/workflows/update.yml
    job: autocommit
    permission: "contents: read"
    reason: Commit resolver-owned metadata and generated artifacts after make validate
    owner_story: 2.5
EOF
}

write_full_release_policy() {
  local target="$1"
  cat >"${target}" <<'EOF'
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist:
  - workflow: .github/workflows/update.yml
    job: autocommit
    permission: "contents: write"
    reason: Commit resolver-owned metadata and generated artifacts after make validate
    owner_story: 2.5
  - workflow: .github/workflows/update.yml
    job: catalog-autocommit
    permission: "contents: write"
    reason: Commit release catalog manifests after digest-aware catalog validation
    owner_story: 4.6
  - workflow: .github/workflows/build.yml
    job: candidate
    permission: "packages: write"
    reason: Push GHCR release candidate tags after per-platform smoke gates
    owner_story: 4.2
  - workflow: .github/workflows/build.yml
    job: security_scan
    permission: "security-events: write"
    reason: Delegate SARIF upload permission to required reusable security scan gate
    owner_story: 4.3
  - workflow: .github/workflows/build.yml
    job: release_evidence
    permission: "id-token: write"
    reason: Request GitHub OIDC token for keyless cosign release evidence signing
    owner_story: 4.4
  - workflow: .github/workflows/build.yml
    job: release_evidence
    permission: "packages: write"
    reason: Upload keyless cosign signature artifacts for immutable candidate digests
    owner_story: 4.4
  - workflow: .github/workflows/build.yml
    job: publish
    permission: "packages: write"
    reason: Promote validated GHCR final tags after release gates pass
    owner_story: 4.5
  - workflow: .github/workflows/build.yml
    job: release_metadata_autocommit
    permission: "contents: write"
    reason: Commit release metadata and digest-aware catalogs after successful publish
    owner_story: 4.6
  - workflow: .github/workflows/security-scan.yml
    job: upload_sarif
    permission: "security-events: write"
    reason: Upload vulnerability scan SARIF after candidate scan evaluation
    owner_story: 4.3
EOF
}

prepare_root() {
  local target="$1"
  mkdir -p "${target}/.github/workflows" "${target}/cloudnative-pg-timescaledb/scripts" "${target}/cloudnative-pg-timescaledb/tests/workflows/permissions/fixtures"
  cp "${FIXTURE_DIR}/valid-least-privilege.yml" "${target}/.github/workflows/validate.yml"
  write_policy "${target}/cloudnative-pg-timescaledb/workflow-policy.yaml"
  cat >"${target}/cloudnative-pg-timescaledb/scripts/ok.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
true
EOF
}

run_validator() {
  local target="$1"
  VALIDATE_WORKFLOWS_ROOT="${target}" "${VALIDATOR}"
}

expect_pass() {
  local description="$1"
  local target="$2"
  local tmp
  tmp="$(mktemp)"
  if ! run_validator "${target}" >"${tmp}" 2>&1; then
    diag "validate-workflows" "${description}" "passes" "$(tr '\n' ' ' <"${tmp}")" "Keep the positive workflow policy fixture valid."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

expect_fail() {
  local description="$1"
  local pattern="$2"
  local target="$3"
  local tmp status
  tmp="$(mktemp)"
  set +e
  run_validator "${target}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-workflows" "${description}" "fails" "passed" "Make the fixture fail on its intended workflow policy invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-workflows" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep workflow diagnostics deterministic and specific."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

for fixture in \
  valid-least-privilege.yml \
  valid-inline-shell-conditional.yml \
  valid-here-string-before-gates.yml \
  valid-heredoc-control-suffix-before-gates.yml \
  valid-shellcheck-version-package.yml \
  valid-shellcheck-apt-selectors.yml \
  valid-gate-redirections.yml \
  valid-release-allowlisted-permissions.yml \
  write-all.yml \
  top-level-write.yml \
  broad-top-level-write.yml \
  pr-write-token.yml \
  inline-comment-job-write-permission.yml \
  quoted-job-write-permission.yml \
  flow-map-job-write-permission.yml \
  unpinned-action.yml \
  unpinned-reusable-workflow.yml \
  unpinned-release-action.yml \
  action-short-sha.yml \
  action-missing-version-comment.yml \
  action-quoted-missing-version-comment.yml \
  action-name-version-not-comment.yml \
  valid-pinned-action.yml \
  write-all-yaml-extension.yaml \
  flow-map-permissions.yml \
  commented-write-permissions.yml \
  quoted-write-permissions.yml \
  pr-inline-list-write-token.yml \
  pr-scalar-write-token.yml \
  pr-target-write-token.yml \
  missing-top-level-permissions.yml \
  release-sensitive-permission.yml \
  valid-allowlisted-permission.yml \
  disallowed-contents-write-job.yml \
  disallowed-packages-write-job.yml \
  disallowed-id-token-write-job.yml \
  disallowed-security-events-write-job.yml \
  invalid-allowlist-entry.yml \
  missing-strict-mode.sh \
  validate-comments-only.yml \
  validate-run-comments-only.yml \
  validate-conditional-gates.yml \
  validate-heredoc-gates.yml \
  validate-heredoc-dashed-delimiter-gates.yml \
  validate-short-circuit-gates.yml \
  validate-apt-without-shellcheck.yml \
  validate-masked-failure-gates.yml \
  validate-shellcheck-doc-only.yml \
  validate-shell-conditional-gates.yml \
  validate-block-close-mask-gates.yml \
  validate-backgrounded-gates.yml \
  validate-quoted-text-gates.yml \
  validate-pipe-ampersand-gates.yml \
  valid-update-autocommit-contents-write.yml \
  invalid-update-nonautocommit-contents-write.yml; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || { diag "test -f" "${FIXTURE_DIR}/${fixture}" "fixture exists" "missing" "Restore Story 2.4 workflow policy fixtures."; exit 1; }
done

tmp_root="$(mktemp -d)"

valid_root="${tmp_root}/valid"
prepare_root "${valid_root}"
expect_pass "valid least privilege" "${valid_root}"

inline_conditional_root="${tmp_root}/valid-inline-shell-conditional"
prepare_root "${inline_conditional_root}"
cp "${FIXTURE_DIR}/valid-inline-shell-conditional.yml" "${inline_conditional_root}/.github/workflows/validate.yml"
expect_pass "valid inline shell conditional" "${inline_conditional_root}"

here_string_root="${tmp_root}/valid-here-string-before-gates"
prepare_root "${here_string_root}"
cp "${FIXTURE_DIR}/valid-here-string-before-gates.yml" "${here_string_root}/.github/workflows/validate.yml"
expect_pass "valid here string before gates" "${here_string_root}"

heredoc_control_root="${tmp_root}/valid-heredoc-control-suffix-before-gates"
prepare_root "${heredoc_control_root}"
cp "${FIXTURE_DIR}/valid-heredoc-control-suffix-before-gates.yml" "${heredoc_control_root}/.github/workflows/validate.yml"
expect_pass "valid heredoc control suffix before gates" "${heredoc_control_root}"

shellcheck_version_root="${tmp_root}/valid-shellcheck-version-package"
prepare_root "${shellcheck_version_root}"
cp "${FIXTURE_DIR}/valid-shellcheck-version-package.yml" "${shellcheck_version_root}/.github/workflows/validate.yml"
expect_pass "valid shellcheck version package" "${shellcheck_version_root}"

shellcheck_selector_root="${tmp_root}/valid-shellcheck-apt-selectors"
prepare_root "${shellcheck_selector_root}"
cp "${FIXTURE_DIR}/valid-shellcheck-apt-selectors.yml" "${shellcheck_selector_root}/.github/workflows/validate.yml"
expect_pass "valid shellcheck apt selectors" "${shellcheck_selector_root}"

gate_redirections_root="${tmp_root}/valid-gate-redirections"
prepare_root "${gate_redirections_root}"
cp "${FIXTURE_DIR}/valid-gate-redirections.yml" "${gate_redirections_root}/.github/workflows/validate.yml"
expect_pass "valid gate redirections" "${gate_redirections_root}"

allow_root="${tmp_root}/allowlisted"
prepare_root "${allow_root}"
cp "${FIXTURE_DIR}/valid-allowlisted-permission.yml" "${allow_root}/.github/workflows/update.yml"
write_allowlist_policy "${allow_root}/cloudnative-pg-timescaledb/workflow-policy.yaml"
expect_pass "valid allowlisted permission" "${allow_root}"

update_allow_root="${tmp_root}/update-allowlisted"
prepare_root "${update_allow_root}"
cp "${FIXTURE_DIR}/valid-update-autocommit-contents-write.yml" "${update_allow_root}/.github/workflows/update.yml"
write_update_policy "${update_allow_root}/cloudnative-pg-timescaledb/workflow-policy.yaml"
expect_pass "valid update autocommit contents write" "${update_allow_root}"

release_allow_root="${tmp_root}/release-allowlisted"
prepare_root "${release_allow_root}"
cp "${FIXTURE_DIR}/valid-release-allowlisted-permissions.yml" "${release_allow_root}/.github/workflows/build.yml"
write_full_release_policy "${release_allow_root}/cloudnative-pg-timescaledb/workflow-policy.yaml"
expect_pass "valid release allowlisted permissions" "${release_allow_root}"

pinned_root="${tmp_root}/valid-pinned-action"
prepare_root "${pinned_root}"
cp "${FIXTURE_DIR}/valid-pinned-action.yml" "${pinned_root}/.github/workflows/update.yml"
expect_pass "valid pinned action" "${pinned_root}"

update_reject_root="${tmp_root}/update-rejected"
prepare_root "${update_reject_root}"
cp "${FIXTURE_DIR}/invalid-update-nonautocommit-contents-write.yml" "${update_reject_root}/.github/workflows/update.yml"
write_update_policy "${update_reject_root}/cloudnative-pg-timescaledb/workflow-policy.yaml"
expect_fail "invalid update nonautocommit contents write" "write permissions are explicitly allowlisted" "${update_reject_root}"

for tuple in \
  "update-wrong-reason write_update_wrong_reason_policy" \
  "update-wrong-owner write_update_wrong_owner_policy" \
  "update-wrong-level write_update_wrong_level_policy"; do
  read -r name writer <<<"${tuple}"
  target="${tmp_root}/${name}"
  prepare_root "${target}"
  cp "${FIXTURE_DIR}/valid-update-autocommit-contents-write.yml" "${target}/.github/workflows/update.yml"
  "${writer}" "${target}/cloudnative-pg-timescaledb/workflow-policy.yaml"
  expect_fail "${name}" "write permissions are explicitly allowlisted" "${target}"
done

for tuple in \
  "write-all.yml no write-all permissions" \
  "write-all-yaml-extension.yaml no write-all permissions" \
  "top-level-write.yml no top-level write permissions" \
  "broad-top-level-write.yml no top-level write permissions" \
  "flow-map-permissions.yml no top-level write permissions" \
  "commented-write-permissions.yml no top-level write permissions" \
  "quoted-write-permissions.yml no top-level write permissions" \
  "inline-comment-job-write-permission.yml write permissions are explicitly allowlisted" \
  "quoted-job-write-permission.yml write permissions are explicitly allowlisted" \
  "flow-map-job-write-permission.yml write permissions are explicitly allowlisted" \
  "pr-write-token.yml pull_request workflows do not receive write tokens" \
  "pr-inline-list-write-token.yml pull_request workflows do not receive write tokens" \
  "pr-scalar-write-token.yml pull_request workflows do not receive write tokens" \
  "pr-target-write-token.yml pull_request workflows do not receive write tokens" \
  "unpinned-action.yml third-party actions pinned" \
  "unpinned-reusable-workflow.yml third-party actions pinned" \
  "unpinned-release-action.yml third-party actions pinned" \
  "action-short-sha.yml third-party actions pinned" \
  "action-missing-version-comment.yml pinned actions include readable version comments" \
  "action-quoted-missing-version-comment.yml pinned actions include readable version comments" \
  "action-name-version-not-comment.yml pinned actions include readable version comments" \
  "missing-top-level-permissions.yml workflow declares explicit top-level permissions" \
  "release-sensitive-permission.yml write permissions are explicitly allowlisted"; do
  read -r fixture pattern <<<"${tuple}"
  target="${tmp_root}/${fixture%.yml}"
  prepare_root "${target}"
  if [[ "${fixture}" == *.yaml ]]; then
    cp "${FIXTURE_DIR}/${fixture}" "${target}/.github/workflows/unsafe.yaml"
  else
    cp "${FIXTURE_DIR}/${fixture}" "${target}/.github/workflows/update.yml"
  fi
  expect_fail "${fixture}" "${pattern}" "${target}"
done

for tuple in \
  "disallowed-contents-write-job.yml write permissions are explicitly allowlisted" \
  "disallowed-packages-write-job.yml write permissions are explicitly allowlisted" \
  "disallowed-id-token-write-job.yml write permissions are explicitly allowlisted" \
  "disallowed-security-events-write-job.yml write permissions are explicitly allowlisted"; do
  read -r fixture pattern <<<"${tuple}"
  target="${tmp_root}/${fixture%.yml}"
  prepare_root "${target}"
  cp "${FIXTURE_DIR}/${fixture}" "${target}/.github/workflows/build.yml"
  write_full_release_policy "${target}/cloudnative-pg-timescaledb/workflow-policy.yaml"
  expect_fail "${fixture}" "${pattern}" "${target}"
done

invalid_policy_root="${tmp_root}/invalid-policy"
prepare_root "${invalid_policy_root}"
cp "${FIXTURE_DIR}/invalid-allowlist-entry.yml" "${invalid_policy_root}/cloudnative-pg-timescaledb/workflow-policy.yaml"
expect_fail "invalid allowlist entry" "permission_allowlist\[0\] keys exactly" "${invalid_policy_root}"

strict_root="${tmp_root}/missing-strict"
prepare_root "${strict_root}"
cp "${FIXTURE_DIR}/missing-strict-mode.sh" "${strict_root}/cloudnative-pg-timescaledb/scripts/missing-strict-mode.sh"
expect_fail "missing strict mode" "set -Eeuo pipefail|missing strict mode" "${strict_root}"

validate_comments_root="${tmp_root}/validate-comments-only"
prepare_root "${validate_comments_root}"
cp "${FIXTURE_DIR}/validate-comments-only.yml" "${validate_comments_root}/.github/workflows/validate.yml"
expect_fail "validate comments only" "validate workflow runs make validate" "${validate_comments_root}"

validate_run_comments_root="${tmp_root}/validate-run-comments-only"
prepare_root "${validate_run_comments_root}"
cp "${FIXTURE_DIR}/validate-run-comments-only.yml" "${validate_run_comments_root}/.github/workflows/validate.yml"
expect_fail "validate run comments only" "validate workflow runs make validate" "${validate_run_comments_root}"

validate_conditional_root="${tmp_root}/validate-conditional-gates"
prepare_root "${validate_conditional_root}"
cp "${FIXTURE_DIR}/validate-conditional-gates.yml" "${validate_conditional_root}/.github/workflows/validate.yml"
expect_fail "validate conditional gates" "validate workflow runs make validate" "${validate_conditional_root}"

validate_heredoc_root="${tmp_root}/validate-heredoc-gates"
prepare_root "${validate_heredoc_root}"
cp "${FIXTURE_DIR}/validate-heredoc-gates.yml" "${validate_heredoc_root}/.github/workflows/validate.yml"
expect_fail "validate heredoc gates" "validate workflow runs make validate" "${validate_heredoc_root}"

validate_heredoc_dashed_root="${tmp_root}/validate-heredoc-dashed-delimiter-gates"
prepare_root "${validate_heredoc_dashed_root}"
cp "${FIXTURE_DIR}/validate-heredoc-dashed-delimiter-gates.yml" "${validate_heredoc_dashed_root}/.github/workflows/validate.yml"
expect_fail "validate heredoc dashed delimiter gates" "validate workflow runs make validate" "${validate_heredoc_dashed_root}"

validate_short_circuit_root="${tmp_root}/validate-short-circuit-gates"
prepare_root "${validate_short_circuit_root}"
cp "${FIXTURE_DIR}/validate-short-circuit-gates.yml" "${validate_short_circuit_root}/.github/workflows/validate.yml"
expect_fail "validate short circuit gates" "validate workflow runs make validate" "${validate_short_circuit_root}"

validate_apt_root="${tmp_root}/validate-apt-without-shellcheck"
prepare_root "${validate_apt_root}"
cp "${FIXTURE_DIR}/validate-apt-without-shellcheck.yml" "${validate_apt_root}/.github/workflows/validate.yml"
expect_fail "validate apt without shellcheck" "validate workflow installs or provides real shellcheck" "${validate_apt_root}"

validate_masked_root="${tmp_root}/validate-masked-failure-gates"
prepare_root "${validate_masked_root}"
cp "${FIXTURE_DIR}/validate-masked-failure-gates.yml" "${validate_masked_root}/.github/workflows/validate.yml"
expect_fail "validate masked failure gates" "validate workflow runs make validate" "${validate_masked_root}"

validate_shellcheck_doc_root="${tmp_root}/validate-shellcheck-doc-only"
prepare_root "${validate_shellcheck_doc_root}"
cp "${FIXTURE_DIR}/validate-shellcheck-doc-only.yml" "${validate_shellcheck_doc_root}/.github/workflows/validate.yml"
expect_fail "validate shellcheck doc only" "validate workflow installs or provides real shellcheck" "${validate_shellcheck_doc_root}"

validate_shell_conditional_root="${tmp_root}/validate-shell-conditional-gates"
prepare_root "${validate_shell_conditional_root}"
cp "${FIXTURE_DIR}/validate-shell-conditional-gates.yml" "${validate_shell_conditional_root}/.github/workflows/validate.yml"
expect_fail "validate shell conditional gates" "validate workflow runs make validate" "${validate_shell_conditional_root}"

validate_block_close_mask_root="${tmp_root}/validate-block-close-mask-gates"
prepare_root "${validate_block_close_mask_root}"
cp "${FIXTURE_DIR}/validate-block-close-mask-gates.yml" "${validate_block_close_mask_root}/.github/workflows/validate.yml"
expect_fail "validate block close mask gates" "validate workflow runs make validate" "${validate_block_close_mask_root}"

validate_backgrounded_root="${tmp_root}/validate-backgrounded-gates"
prepare_root "${validate_backgrounded_root}"
cp "${FIXTURE_DIR}/validate-backgrounded-gates.yml" "${validate_backgrounded_root}/.github/workflows/validate.yml"
expect_fail "validate backgrounded gates" "validate workflow runs make validate" "${validate_backgrounded_root}"

validate_quoted_text_root="${tmp_root}/validate-quoted-text-gates"
prepare_root "${validate_quoted_text_root}"
cp "${FIXTURE_DIR}/validate-quoted-text-gates.yml" "${validate_quoted_text_root}/.github/workflows/validate.yml"
expect_fail "validate quoted text gates" "validate workflow runs make validate" "${validate_quoted_text_root}"

validate_pipe_ampersand_root="${tmp_root}/validate-pipe-ampersand-gates"
prepare_root "${validate_pipe_ampersand_root}"
cp "${FIXTURE_DIR}/validate-pipe-ampersand-gates.yml" "${validate_pipe_ampersand_root}/.github/workflows/validate.yml"
expect_fail "validate pipe ampersand gates" "validate workflow runs make validate" "${validate_pipe_ampersand_root}"

rm -rf "${tmp_root}"
printf 'PASS story-2.4 workflow permission fixtures\n'
