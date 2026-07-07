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
  - workflow: .github/workflows/build.yml
    job: publish
    permission: "id-token: write"
    reason: Request GitHub OIDC token to sign the clean published runtime index digest
    owner_story: 4.5
  - workflow: .github/workflows/build.yml
    job: publish
    permission: "packages: write"
    reason: Promote validated GHCR final tags and upload the published digest signature
    owner_story: 4.5
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
  - workflow: .github/workflows/update.yml
    job: autocommit
    permission: "actions: write"
    reason: Dispatch release candidate build after resolver metadata autocommit
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

write_wrong_category_policy() {
  local target="$1"
  local permission="$2"
  cat >"${target}" <<EOF
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist:
  - workflow: .github/workflows/build.yml
    job: evil
    permission: "${permission}: write"
    reason: Wrong category fixture
    owner_story: 4.5
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
    job: autocommit
    permission: "actions: write"
    reason: Dispatch release candidate build after resolver metadata autocommit
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
    reason: Upload keyless cosign registry signatures for release evidence to GHCR
    owner_story: 4.4
  - workflow: .github/workflows/build.yml
    job: publish
    permission: "id-token: write"
    reason: Request GitHub OIDC token to sign the clean published runtime index digest
    owner_story: 4.5
  - workflow: .github/workflows/build.yml
    job: publish
    permission: "packages: write"
    reason: Promote validated GHCR final tags and upload the published digest signature
    owner_story: 4.5
  - workflow: .github/workflows/build.yml
    job: release_metadata_autocommit
    permission: "contents: write"
    reason: Commit release metadata and digest-aware catalogs after successful publish
    owner_story: 4.6
  - workflow: .github/workflows/build.yml
    job: ghcr_cleanup
    permission: "packages: write"
    reason: Delete temporary candidate-only GHCR package versions after successful release
    owner_story: 4.5
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

expect_pass_with_stubbed_optional_tools() {
  local description="$1"
  local target="$2"
  local stub_bin tmp
  stub_bin="$(mktemp -d)"
  printf '#!/usr/bin/env sh\nexit 0\n' >"${stub_bin}/actionlint"
  printf '#!/usr/bin/env sh\nexit 0\n' >"${stub_bin}/shellcheck"
  chmod +x "${stub_bin}/actionlint" "${stub_bin}/shellcheck"
  tmp="$(mktemp)"
  if ! PATH="${stub_bin}:${PATH}" run_validator "${target}" >"${tmp}" 2>&1; then
    diag "validate-workflows" "${description}" "passes" "$(tr '\n' ' ' <"${tmp}")" "Keep the positive workflow policy parser fixture valid."
    rm -f "${tmp}"
    rm -rf "${stub_bin}"
    exit 1
  fi
  rm -f "${tmp}"
  rm -rf "${stub_bin}"
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

expect_fail_with_stubbed_optional_tools() {
  local description="$1"
  local pattern="$2"
  local target="$3"
  local stub_bin
  stub_bin="$(mktemp -d)"
  printf '#!/usr/bin/env sh\nexit 0\n' >"${stub_bin}/actionlint"
  printf '#!/usr/bin/env sh\nexit 0\n' >"${stub_bin}/shellcheck"
  chmod +x "${stub_bin}/actionlint" "${stub_bin}/shellcheck"
  PATH="${stub_bin}:${PATH}" expect_fail "${description}" "${pattern}" "${target}"
  rm -rf "${stub_bin}"
}

for fixture in \
  valid-least-privilege.yml \
  valid-inline-shell-conditional.yml \
  valid-here-string-before-gates.yml \
  valid-heredoc-control-suffix-before-gates.yml \
  valid-quoted-heredoc-marker-before-gates.yml \
  valid-single-quote-backslash-semicolon.yml \
  valid-stderr-redirect-gates.yml \
  valid-ansi-c-quoted-heredoc-marker.yml \
  valid-ansi-c-heredoc-delimiter.yml \
  valid-conditional-exit-before-gates.yml \
  valid-case-nonmatching-exit-before-gates.yml \
  valid-case-quoted-glob-before-gates.yml \
  valid-exec-redirection-before-gates.yml \
  valid-exec-brace-fd-redirection-before-gates.yml \
  valid-exec-process-substitution-before-gates.yml \
  valid-escaped-dollar-before-single-quote.yml \
  valid-conditional-hash-heredoc-before-gates.yml \
  valid-escaped-space-hash-heredoc-before-gates.yml \
  valid-function-brace-one-line-before-gates.yml \
  valid-function-command-substitution-close-before-gates.yml \
  valid-function-close-and-true-before-gates.yml \
  valid-function-literal-brace-before-gates.yml \
  valid-function-command-substitution-before-gates.yml \
  valid-function-one-line-subshell-group-before-gates.yml \
  valid-function-subshell-one-line-before-gates.yml \
  valid-function-subshell-semicolon-before-gates.yml \
  valid-quoted-heredoc-body-continuation-before-gates.yml \
  valid-short-circuit-false-and-exit-before-gates.yml \
  valid-short-circuit-false-true-exit-before-gates.yml \
  valid-short-circuit-true-false-exit-before-gates.yml \
  valid-short-circuit-true-or-false-or-exit-before-gates.yml \
  valid-set-double-dash-before-gates.yml \
  valid-static-true-redirection-before-gates.yml \
  valid-pipeline-exit-before-gates.yml \
  valid-static-printf-redirection-before-gates.yml \
  valid-shellcheck-version-package.yml \
  valid-shellcheck-apt-selectors.yml \
  valid-gate-redirections.yml \
  valid-release-allowlisted-permissions.yml \
  disallowed-allowlisted-contents-wrong-job.yml \
  disallowed-allowlisted-packages-wrong-job.yml \
  disallowed-allowlisted-id-token-wrong-job.yml \
  disallowed-allowlisted-security-events-wrong-job.yml \
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
  validate-case-exit-before-gates.yml \
  validate-case-alternation-exit-before-gates.yml \
  validate-case-glob-exit-before-gates.yml \
  validate-case-quoted-literal-exit-before-gates.yml \
  validate-run-comments-only.yml \
  validate-conditional-gates.yml \
  validate-exit-before-gates.yml \
  validate-exec-before-gates.yml \
  validate-for-exit-before-gates.yml \
  validate-if-colon-exit-before-gates.yml \
  validate-function-brace-group-gates.yml \
  validate-function-gates.yml \
  validate-function-subshell-gates.yml \
  validate-heredoc-gates.yml \
  validate-split-function-gates.yml \
  validate-heredoc-dashed-delimiter-gates.yml \
  validate-short-circuit-gates.yml \
  validate-apt-without-shellcheck.yml \
  validate-masked-failure-gates.yml \
  validate-shellcheck-doc-only.yml \
  validate-short-circuit-exit-gates.yml \
  validate-shell-conditional-gates.yml \
  validate-block-close-mask-gates.yml \
  validate-backgrounded-gates.yml \
  validate-backtick-pipe-exit-before-gates.yml \
  validate-backtick-and-exit-before-gates.yml \
  validate-case-negated-bracket-exit-before-gates.yml \
  validate-case-quoted-paren-exit-before-gates.yml \
  validate-case-range-exit-before-gates.yml \
  validate-case-posix-class-exit-before-gates.yml \
  validate-case-literal-closing-bracket-exit-before-gates.yml \
  validate-continue-on-error-gates.yml \
  validate-continue-on-error-expression-gates.yml \
  validate-job-continue-on-error-gates.yml \
  validate-quoted-text-gates.yml \
  validate-pipe-ampersand-gates.yml \
  validate-quoted-pipe-exit-before-gates.yml \
  validate-command-substitution-pipe-exit-before-gates.yml \
  validate-quoted-process-substitution-text-exit-before-gates.yml \
  validate-echo-short-circuit-exit-before-gates.yml \
  valid-continue-on-error-expression-false.yml \
  validate-ansi-c-quoted-text-gates.yml \
  validate-multiple-heredoc-gates.yml \
  validate-mixed-and-or-exit-before-gates.yml \
  validate-mixed-or-and-exit-before-gates.yml \
  validate-escaped-dollar-heredoc-gates.yml \
  validate-hash-heredoc-delimiter-gates.yml \
  validate-hash-suffixed-gates.yml \
  validate-line-continuation-hash-heredoc-gates.yml \
  validate-one-line-if-exit-before-gates.yml \
  validate-one-line-case-exit-before-gates.yml \
  validate-one-line-case-command-exit-before-gates.yml \
  validate-one-line-case-later-arm-exit-before-gates.yml \
  validate-redirection-suffixed-gates.yml \
  validate-quoted-case-terminator-exit-before-gates.yml \
  validate-process-substitution-pipe-exit-before-gates.yml \
  validate-process-substitution-and-exit-before-gates.yml \
  validate-set-plus-e-gates.yml \
  validate-always-true-set-plus-e-gates.yml \
  validate-always-true-one-line-set-plus-e-gates.yml \
  validate-always-true-short-circuit-pipeline-or-exit-before-gates.yml \
  validate-always-true-one-line-or-exit-before-gates.yml \
  validate-case-empty-literal-exit-before-gates.yml \
  validate-case-active-arm-pipeline-or-exit-before-gates.yml \
  validate-short-circuit-or-exit-gates.yml \
  validate-short-circuit-pipeline-or-exit-before-gates.yml \
  validate-unquoted-hash-heredoc-gates.yml \
  validate-conditional-heredoc-gates.yml \
  validate-block-close-heredoc-gates.yml \
  validate-while-exit-before-gates.yml \
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

quoted_heredoc_root="${tmp_root}/valid-quoted-heredoc-marker-before-gates"
prepare_root "${quoted_heredoc_root}"
cp "${FIXTURE_DIR}/valid-quoted-heredoc-marker-before-gates.yml" "${quoted_heredoc_root}/.github/workflows/validate.yml"
expect_pass "valid quoted heredoc marker before gates" "${quoted_heredoc_root}"

single_quote_backslash_root="${tmp_root}/valid-single-quote-backslash-semicolon"
prepare_root "${single_quote_backslash_root}"
cp "${FIXTURE_DIR}/valid-single-quote-backslash-semicolon.yml" "${single_quote_backslash_root}/.github/workflows/validate.yml"
expect_pass "valid single quote backslash semicolon" "${single_quote_backslash_root}"

stderr_redirect_root="${tmp_root}/valid-stderr-redirect-gates"
prepare_root "${stderr_redirect_root}"
cp "${FIXTURE_DIR}/valid-stderr-redirect-gates.yml" "${stderr_redirect_root}/.github/workflows/validate.yml"
expect_pass "valid stderr redirect gates" "${stderr_redirect_root}"

ansi_heredoc_root="${tmp_root}/valid-ansi-c-quoted-heredoc-marker"
prepare_root "${ansi_heredoc_root}"
cp "${FIXTURE_DIR}/valid-ansi-c-quoted-heredoc-marker.yml" "${ansi_heredoc_root}/.github/workflows/validate.yml"
expect_pass "valid ansi c quoted heredoc marker" "${ansi_heredoc_root}"

ansi_delimiter_root="${tmp_root}/valid-ansi-c-heredoc-delimiter"
prepare_root "${ansi_delimiter_root}"
cp "${FIXTURE_DIR}/valid-ansi-c-heredoc-delimiter.yml" "${ansi_delimiter_root}/.github/workflows/validate.yml"
expect_pass "valid ansi c heredoc delimiter" "${ansi_delimiter_root}"

conditional_exit_root="${tmp_root}/valid-conditional-exit-before-gates"
prepare_root "${conditional_exit_root}"
cp "${FIXTURE_DIR}/valid-conditional-exit-before-gates.yml" "${conditional_exit_root}/.github/workflows/validate.yml"
expect_pass "valid conditional exit before gates" "${conditional_exit_root}"

case_nonmatching_exit_root="${tmp_root}/valid-case-nonmatching-exit-before-gates"
prepare_root "${case_nonmatching_exit_root}"
cp "${FIXTURE_DIR}/valid-case-nonmatching-exit-before-gates.yml" "${case_nonmatching_exit_root}/.github/workflows/validate.yml"
expect_pass "valid case nonmatching exit before gates" "${case_nonmatching_exit_root}"

case_quoted_glob_root="${tmp_root}/valid-case-quoted-glob-before-gates"
prepare_root "${case_quoted_glob_root}"
cp "${FIXTURE_DIR}/valid-case-quoted-glob-before-gates.yml" "${case_quoted_glob_root}/.github/workflows/validate.yml"
expect_pass "valid case quoted glob before gates" "${case_quoted_glob_root}"

exec_redirection_root="${tmp_root}/valid-exec-redirection-before-gates"
prepare_root "${exec_redirection_root}"
cp "${FIXTURE_DIR}/valid-exec-redirection-before-gates.yml" "${exec_redirection_root}/.github/workflows/validate.yml"
expect_pass "valid exec redirection before gates" "${exec_redirection_root}"

exec_brace_fd_redirection_root="${tmp_root}/valid-exec-brace-fd-redirection-before-gates"
prepare_root "${exec_brace_fd_redirection_root}"
cp "${FIXTURE_DIR}/valid-exec-brace-fd-redirection-before-gates.yml" "${exec_brace_fd_redirection_root}/.github/workflows/validate.yml"
expect_pass "valid exec brace fd redirection before gates" "${exec_brace_fd_redirection_root}"

exec_process_substitution_root="${tmp_root}/valid-exec-process-substitution-before-gates"
prepare_root "${exec_process_substitution_root}"
cp "${FIXTURE_DIR}/valid-exec-process-substitution-before-gates.yml" "${exec_process_substitution_root}/.github/workflows/validate.yml"
expect_pass "valid exec process substitution before gates" "${exec_process_substitution_root}"

escaped_dollar_root="${tmp_root}/valid-escaped-dollar-before-single-quote"
prepare_root "${escaped_dollar_root}"
cp "${FIXTURE_DIR}/valid-escaped-dollar-before-single-quote.yml" "${escaped_dollar_root}/.github/workflows/validate.yml"
expect_pass "valid escaped dollar before single quote" "${escaped_dollar_root}"

conditional_hash_heredoc_root="${tmp_root}/valid-conditional-hash-heredoc-before-gates"
prepare_root "${conditional_hash_heredoc_root}"
cp "${FIXTURE_DIR}/valid-conditional-hash-heredoc-before-gates.yml" "${conditional_hash_heredoc_root}/.github/workflows/validate.yml"
expect_pass "valid conditional hash heredoc before gates" "${conditional_hash_heredoc_root}"

escaped_space_hash_heredoc_root="${tmp_root}/valid-escaped-space-hash-heredoc-before-gates"
prepare_root "${escaped_space_hash_heredoc_root}"
cp "${FIXTURE_DIR}/valid-escaped-space-hash-heredoc-before-gates.yml" "${escaped_space_hash_heredoc_root}/.github/workflows/validate.yml"
expect_pass "valid escaped space hash heredoc before gates" "${escaped_space_hash_heredoc_root}"

function_brace_one_line_root="${tmp_root}/valid-function-brace-one-line-before-gates"
prepare_root "${function_brace_one_line_root}"
cp "${FIXTURE_DIR}/valid-function-brace-one-line-before-gates.yml" "${function_brace_one_line_root}/.github/workflows/validate.yml"
expect_pass "valid function brace one line before gates" "${function_brace_one_line_root}"

function_command_substitution_close_root="${tmp_root}/valid-function-command-substitution-close-before-gates"
prepare_root "${function_command_substitution_close_root}"
cp "${FIXTURE_DIR}/valid-function-command-substitution-close-before-gates.yml" "${function_command_substitution_close_root}/.github/workflows/validate.yml"
expect_pass "valid function command substitution close before gates" "${function_command_substitution_close_root}"

function_close_and_true_root="${tmp_root}/valid-function-close-and-true-before-gates"
prepare_root "${function_close_and_true_root}"
cp "${FIXTURE_DIR}/valid-function-close-and-true-before-gates.yml" "${function_close_and_true_root}/.github/workflows/validate.yml"
expect_pass "valid function close and true before gates" "${function_close_and_true_root}"

function_literal_brace_root="${tmp_root}/valid-function-literal-brace-before-gates"
prepare_root "${function_literal_brace_root}"
cp "${FIXTURE_DIR}/valid-function-literal-brace-before-gates.yml" "${function_literal_brace_root}/.github/workflows/validate.yml"
expect_pass_with_stubbed_optional_tools "valid function literal brace before gates" "${function_literal_brace_root}"

function_command_substitution_root="${tmp_root}/valid-function-command-substitution-before-gates"
prepare_root "${function_command_substitution_root}"
cp "${FIXTURE_DIR}/valid-function-command-substitution-before-gates.yml" "${function_command_substitution_root}/.github/workflows/validate.yml"
expect_pass "valid function command substitution before gates" "${function_command_substitution_root}"

function_one_line_subshell_group_root="${tmp_root}/valid-function-one-line-subshell-group-before-gates"
prepare_root "${function_one_line_subshell_group_root}"
cp "${FIXTURE_DIR}/valid-function-one-line-subshell-group-before-gates.yml" "${function_one_line_subshell_group_root}/.github/workflows/validate.yml"
expect_pass "valid function one line subshell group before gates" "${function_one_line_subshell_group_root}"

function_subshell_one_line_root="${tmp_root}/valid-function-subshell-one-line-before-gates"
prepare_root "${function_subshell_one_line_root}"
cp "${FIXTURE_DIR}/valid-function-subshell-one-line-before-gates.yml" "${function_subshell_one_line_root}/.github/workflows/validate.yml"
expect_pass "valid function subshell one line before gates" "${function_subshell_one_line_root}"

function_subshell_semicolon_root="${tmp_root}/valid-function-subshell-semicolon-before-gates"
prepare_root "${function_subshell_semicolon_root}"
cp "${FIXTURE_DIR}/valid-function-subshell-semicolon-before-gates.yml" "${function_subshell_semicolon_root}/.github/workflows/validate.yml"
expect_pass "valid function subshell semicolon before gates" "${function_subshell_semicolon_root}"

false_and_exit_root="${tmp_root}/valid-short-circuit-false-and-exit-before-gates"
prepare_root "${false_and_exit_root}"
cp "${FIXTURE_DIR}/valid-short-circuit-false-and-exit-before-gates.yml" "${false_and_exit_root}/.github/workflows/validate.yml"
expect_pass "valid short circuit false and exit before gates" "${false_and_exit_root}"

false_true_exit_root="${tmp_root}/valid-short-circuit-false-true-exit-before-gates"
prepare_root "${false_true_exit_root}"
cp "${FIXTURE_DIR}/valid-short-circuit-false-true-exit-before-gates.yml" "${false_true_exit_root}/.github/workflows/validate.yml"
expect_pass "valid short circuit false true exit before gates" "${false_true_exit_root}"

true_false_exit_root="${tmp_root}/valid-short-circuit-true-false-exit-before-gates"
prepare_root "${true_false_exit_root}"
cp "${FIXTURE_DIR}/valid-short-circuit-true-false-exit-before-gates.yml" "${true_false_exit_root}/.github/workflows/validate.yml"
expect_pass "valid short circuit true false exit before gates" "${true_false_exit_root}"

true_or_false_or_exit_root="${tmp_root}/valid-short-circuit-true-or-false-or-exit-before-gates"
prepare_root "${true_or_false_or_exit_root}"
cp "${FIXTURE_DIR}/valid-short-circuit-true-or-false-or-exit-before-gates.yml" "${true_or_false_or_exit_root}/.github/workflows/validate.yml"
expect_pass "valid short circuit true or false or exit before gates" "${true_or_false_or_exit_root}"

set_double_dash_root="${tmp_root}/valid-set-double-dash-before-gates"
prepare_root "${set_double_dash_root}"
cp "${FIXTURE_DIR}/valid-set-double-dash-before-gates.yml" "${set_double_dash_root}/.github/workflows/validate.yml"
expect_pass "valid set double dash before gates" "${set_double_dash_root}"

static_true_redirection_root="${tmp_root}/valid-static-true-redirection-before-gates"
prepare_root "${static_true_redirection_root}"
cp "${FIXTURE_DIR}/valid-static-true-redirection-before-gates.yml" "${static_true_redirection_root}/.github/workflows/validate.yml"
expect_pass "valid static true redirection before gates" "${static_true_redirection_root}"

pipeline_exit_root="${tmp_root}/valid-pipeline-exit-before-gates"
prepare_root "${pipeline_exit_root}"
cp "${FIXTURE_DIR}/valid-pipeline-exit-before-gates.yml" "${pipeline_exit_root}/.github/workflows/validate.yml"
expect_pass "valid pipeline exit before gates" "${pipeline_exit_root}"

quoted_heredoc_body_continuation_root="${tmp_root}/valid-quoted-heredoc-body-continuation-before-gates"
prepare_root "${quoted_heredoc_body_continuation_root}"
cp "${FIXTURE_DIR}/valid-quoted-heredoc-body-continuation-before-gates.yml" "${quoted_heredoc_body_continuation_root}/.github/workflows/validate.yml"
expect_pass "valid quoted heredoc body continuation before gates" "${quoted_heredoc_body_continuation_root}"

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

static_printf_redirection_root="${tmp_root}/valid-static-printf-redirection-before-gates"
prepare_root "${static_printf_redirection_root}"
cp "${FIXTURE_DIR}/valid-static-printf-redirection-before-gates.yml" "${static_printf_redirection_root}/.github/workflows/validate.yml"
expect_pass "valid static printf redirection before gates" "${static_printf_redirection_root}"

allow_root="${tmp_root}/allowlisted"
prepare_root "${allow_root}"
cp "${FIXTURE_DIR}/valid-allowlisted-permission.yml" "${allow_root}/.github/workflows/build.yml"
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
  "missing-timeout.yml local runner jobs declare timeout-minutes" \
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

for tuple in \
  "disallowed-allowlisted-contents-wrong-job.yml contents" \
  "disallowed-allowlisted-packages-wrong-job.yml packages" \
  "disallowed-allowlisted-id-token-wrong-job.yml id-token" \
  "disallowed-allowlisted-security-events-wrong-job.yml security-events"; do
  read -r fixture permission <<<"${tuple}"
  target="${tmp_root}/${fixture%.yml}"
  prepare_root "${target}"
  cp "${FIXTURE_DIR}/${fixture}" "${target}/.github/workflows/build.yml"
  write_wrong_category_policy "${target}/cloudnative-pg-timescaledb/workflow-policy.yaml" "${permission}"
  expect_fail "${fixture}" "write permissions are explicitly allowlisted" "${target}"
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

validate_case_exit_root="${tmp_root}/validate-case-exit-before-gates"
prepare_root "${validate_case_exit_root}"
cp "${FIXTURE_DIR}/validate-case-exit-before-gates.yml" "${validate_case_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case exit before gates" "validate workflow runs make validate" "${validate_case_exit_root}"

validate_case_alternation_exit_root="${tmp_root}/validate-case-alternation-exit-before-gates"
prepare_root "${validate_case_alternation_exit_root}"
cp "${FIXTURE_DIR}/validate-case-alternation-exit-before-gates.yml" "${validate_case_alternation_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case alternation exit before gates" "validate workflow runs make validate" "${validate_case_alternation_exit_root}"

validate_case_glob_exit_root="${tmp_root}/validate-case-glob-exit-before-gates"
prepare_root "${validate_case_glob_exit_root}"
cp "${FIXTURE_DIR}/validate-case-glob-exit-before-gates.yml" "${validate_case_glob_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case glob exit before gates" "validate workflow runs make validate" "${validate_case_glob_exit_root}"

validate_case_quoted_literal_exit_root="${tmp_root}/validate-case-quoted-literal-exit-before-gates"
prepare_root "${validate_case_quoted_literal_exit_root}"
cp "${FIXTURE_DIR}/validate-case-quoted-literal-exit-before-gates.yml" "${validate_case_quoted_literal_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case quoted literal exit before gates" "validate workflow runs make validate" "${validate_case_quoted_literal_exit_root}"

validate_case_negated_bracket_exit_root="${tmp_root}/validate-case-negated-bracket-exit-before-gates"
prepare_root "${validate_case_negated_bracket_exit_root}"
cp "${FIXTURE_DIR}/validate-case-negated-bracket-exit-before-gates.yml" "${validate_case_negated_bracket_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case negated bracket exit before gates" "validate workflow runs make validate" "${validate_case_negated_bracket_exit_root}"

validate_case_quoted_paren_exit_root="${tmp_root}/validate-case-quoted-paren-exit-before-gates"
prepare_root "${validate_case_quoted_paren_exit_root}"
cp "${FIXTURE_DIR}/validate-case-quoted-paren-exit-before-gates.yml" "${validate_case_quoted_paren_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case quoted paren exit before gates" "validate workflow runs make validate" "${validate_case_quoted_paren_exit_root}"

validate_case_range_exit_root="${tmp_root}/validate-case-range-exit-before-gates"
prepare_root "${validate_case_range_exit_root}"
cp "${FIXTURE_DIR}/validate-case-range-exit-before-gates.yml" "${validate_case_range_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case range exit before gates" "validate workflow runs make validate" "${validate_case_range_exit_root}"

validate_case_posix_class_exit_root="${tmp_root}/validate-case-posix-class-exit-before-gates"
prepare_root "${validate_case_posix_class_exit_root}"
cp "${FIXTURE_DIR}/validate-case-posix-class-exit-before-gates.yml" "${validate_case_posix_class_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case posix class exit before gates" "validate workflow runs make validate" "${validate_case_posix_class_exit_root}"

validate_case_literal_closing_bracket_exit_root="${tmp_root}/validate-case-literal-closing-bracket-exit-before-gates"
prepare_root "${validate_case_literal_closing_bracket_exit_root}"
cp "${FIXTURE_DIR}/validate-case-literal-closing-bracket-exit-before-gates.yml" "${validate_case_literal_closing_bracket_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case literal closing bracket exit before gates" "validate workflow runs make validate" "${validate_case_literal_closing_bracket_exit_root}"

validate_run_comments_root="${tmp_root}/validate-run-comments-only"
prepare_root "${validate_run_comments_root}"
cp "${FIXTURE_DIR}/validate-run-comments-only.yml" "${validate_run_comments_root}/.github/workflows/validate.yml"
expect_fail "validate run comments only" "validate workflow runs make validate" "${validate_run_comments_root}"

validate_continue_on_error_root="${tmp_root}/validate-continue-on-error-gates"
prepare_root "${validate_continue_on_error_root}"
cp "${FIXTURE_DIR}/validate-continue-on-error-gates.yml" "${validate_continue_on_error_root}/.github/workflows/validate.yml"
expect_fail "validate continue on error gates" "validate workflow runs make validate" "${validate_continue_on_error_root}"

validate_continue_on_error_expression_root="${tmp_root}/validate-continue-on-error-expression-gates"
prepare_root "${validate_continue_on_error_expression_root}"
cp "${FIXTURE_DIR}/validate-continue-on-error-expression-gates.yml" "${validate_continue_on_error_expression_root}/.github/workflows/validate.yml"
expect_fail "validate continue on error expression gates" "validate workflow runs make validate" "${validate_continue_on_error_expression_root}"

validate_job_continue_on_error_root="${tmp_root}/validate-job-continue-on-error-gates"
prepare_root "${validate_job_continue_on_error_root}"
cp "${FIXTURE_DIR}/validate-job-continue-on-error-gates.yml" "${validate_job_continue_on_error_root}/.github/workflows/validate.yml"
expect_fail "validate job continue on error gates" "validate workflow runs make validate" "${validate_job_continue_on_error_root}"

validate_conditional_root="${tmp_root}/validate-conditional-gates"
prepare_root "${validate_conditional_root}"
cp "${FIXTURE_DIR}/validate-conditional-gates.yml" "${validate_conditional_root}/.github/workflows/validate.yml"
expect_fail "validate conditional gates" "validate workflow runs make validate" "${validate_conditional_root}"

validate_exit_root="${tmp_root}/validate-exit-before-gates"
prepare_root "${validate_exit_root}"
cp "${FIXTURE_DIR}/validate-exit-before-gates.yml" "${validate_exit_root}/.github/workflows/validate.yml"
expect_fail "validate exit before gates" "validate workflow runs make validate" "${validate_exit_root}"

validate_exec_root="${tmp_root}/validate-exec-before-gates"
prepare_root "${validate_exec_root}"
cp "${FIXTURE_DIR}/validate-exec-before-gates.yml" "${validate_exec_root}/.github/workflows/validate.yml"
expect_fail "validate exec before gates" "validate workflow runs make validate" "${validate_exec_root}"

validate_for_exit_root="${tmp_root}/validate-for-exit-before-gates"
prepare_root "${validate_for_exit_root}"
cp "${FIXTURE_DIR}/validate-for-exit-before-gates.yml" "${validate_for_exit_root}/.github/workflows/validate.yml"
expect_fail "validate for exit before gates" "validate workflow runs make validate" "${validate_for_exit_root}"

validate_if_colon_exit_root="${tmp_root}/validate-if-colon-exit-before-gates"
prepare_root "${validate_if_colon_exit_root}"
cp "${FIXTURE_DIR}/validate-if-colon-exit-before-gates.yml" "${validate_if_colon_exit_root}/.github/workflows/validate.yml"
expect_fail "validate if colon exit before gates" "validate workflow runs make validate" "${validate_if_colon_exit_root}"

validate_function_root="${tmp_root}/validate-function-gates"
prepare_root "${validate_function_root}"
cp "${FIXTURE_DIR}/validate-function-gates.yml" "${validate_function_root}/.github/workflows/validate.yml"
expect_fail "validate function gates" "validate workflow runs make validate" "${validate_function_root}"

validate_split_function_root="${tmp_root}/validate-split-function-gates"
prepare_root "${validate_split_function_root}"
cp "${FIXTURE_DIR}/validate-split-function-gates.yml" "${validate_split_function_root}/.github/workflows/validate.yml"
expect_fail "validate split function gates" "validate workflow runs make validate" "${validate_split_function_root}"

validate_function_brace_group_root="${tmp_root}/validate-function-brace-group-gates"
prepare_root "${validate_function_brace_group_root}"
cp "${FIXTURE_DIR}/validate-function-brace-group-gates.yml" "${validate_function_brace_group_root}/.github/workflows/validate.yml"
expect_fail "validate function brace group gates" "validate workflow runs make validate" "${validate_function_brace_group_root}"

validate_function_subshell_root="${tmp_root}/validate-function-subshell-gates"
prepare_root "${validate_function_subshell_root}"
cp "${FIXTURE_DIR}/validate-function-subshell-gates.yml" "${validate_function_subshell_root}/.github/workflows/validate.yml"
expect_fail "validate function subshell gates" "validate workflow runs make validate" "${validate_function_subshell_root}"

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

validate_short_circuit_exit_root="${tmp_root}/validate-short-circuit-exit-gates"
prepare_root "${validate_short_circuit_exit_root}"
cp "${FIXTURE_DIR}/validate-short-circuit-exit-gates.yml" "${validate_short_circuit_exit_root}/.github/workflows/validate.yml"
expect_fail "validate short circuit exit gates" "validate workflow runs make validate" "${validate_short_circuit_exit_root}"

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

validate_backtick_pipe_exit_root="${tmp_root}/validate-backtick-pipe-exit-before-gates"
prepare_root "${validate_backtick_pipe_exit_root}"
cp "${FIXTURE_DIR}/validate-backtick-pipe-exit-before-gates.yml" "${validate_backtick_pipe_exit_root}/.github/workflows/validate.yml"
expect_fail_with_stubbed_optional_tools "validate backtick pipe exit before gates" "validate workflow runs make validate" "${validate_backtick_pipe_exit_root}"

validate_backtick_and_exit_root="${tmp_root}/validate-backtick-and-exit-before-gates"
prepare_root "${validate_backtick_and_exit_root}"
cp "${FIXTURE_DIR}/validate-backtick-and-exit-before-gates.yml" "${validate_backtick_and_exit_root}/.github/workflows/validate.yml"
expect_fail_with_stubbed_optional_tools "validate backtick and exit before gates" "validate workflow runs make validate" "${validate_backtick_and_exit_root}"

validate_quoted_text_root="${tmp_root}/validate-quoted-text-gates"
prepare_root "${validate_quoted_text_root}"
cp "${FIXTURE_DIR}/validate-quoted-text-gates.yml" "${validate_quoted_text_root}/.github/workflows/validate.yml"
expect_fail "validate quoted text gates" "validate workflow runs make validate" "${validate_quoted_text_root}"

validate_pipe_ampersand_root="${tmp_root}/validate-pipe-ampersand-gates"
prepare_root "${validate_pipe_ampersand_root}"
cp "${FIXTURE_DIR}/validate-pipe-ampersand-gates.yml" "${validate_pipe_ampersand_root}/.github/workflows/validate.yml"
expect_fail "validate pipe ampersand gates" "validate workflow runs make validate" "${validate_pipe_ampersand_root}"

validate_quoted_pipe_exit_root="${tmp_root}/validate-quoted-pipe-exit-before-gates"
prepare_root "${validate_quoted_pipe_exit_root}"
cp "${FIXTURE_DIR}/validate-quoted-pipe-exit-before-gates.yml" "${validate_quoted_pipe_exit_root}/.github/workflows/validate.yml"
expect_fail "validate quoted pipe exit before gates" "validate workflow runs make validate" "${validate_quoted_pipe_exit_root}"

validate_command_substitution_pipe_exit_root="${tmp_root}/validate-command-substitution-pipe-exit-before-gates"
prepare_root "${validate_command_substitution_pipe_exit_root}"
cp "${FIXTURE_DIR}/validate-command-substitution-pipe-exit-before-gates.yml" "${validate_command_substitution_pipe_exit_root}/.github/workflows/validate.yml"
expect_fail "validate command substitution pipe exit before gates" "validate workflow runs make validate" "${validate_command_substitution_pipe_exit_root}"

validate_quoted_process_substitution_text_exit_root="${tmp_root}/validate-quoted-process-substitution-text-exit-before-gates"
prepare_root "${validate_quoted_process_substitution_text_exit_root}"
cp "${FIXTURE_DIR}/validate-quoted-process-substitution-text-exit-before-gates.yml" "${validate_quoted_process_substitution_text_exit_root}/.github/workflows/validate.yml"
expect_fail "validate quoted process substitution text exit before gates" "validate workflow runs make validate" "${validate_quoted_process_substitution_text_exit_root}"

validate_echo_short_circuit_exit_root="${tmp_root}/validate-echo-short-circuit-exit-before-gates"
prepare_root "${validate_echo_short_circuit_exit_root}"
cp "${FIXTURE_DIR}/validate-echo-short-circuit-exit-before-gates.yml" "${validate_echo_short_circuit_exit_root}/.github/workflows/validate.yml"
expect_fail "validate echo short circuit exit before gates" "validate workflow runs make validate" "${validate_echo_short_circuit_exit_root}"

continue_on_error_expression_false_root="${tmp_root}/valid-continue-on-error-expression-false"
prepare_root "${continue_on_error_expression_false_root}"
cp "${FIXTURE_DIR}/valid-continue-on-error-expression-false.yml" "${continue_on_error_expression_false_root}/.github/workflows/validate.yml"
expect_pass "valid continue on error expression false" "${continue_on_error_expression_false_root}"

validate_ansi_text_root="${tmp_root}/validate-ansi-c-quoted-text-gates"
prepare_root "${validate_ansi_text_root}"
cp "${FIXTURE_DIR}/validate-ansi-c-quoted-text-gates.yml" "${validate_ansi_text_root}/.github/workflows/validate.yml"
expect_fail "validate ansi c quoted text gates" "validate workflow runs make validate" "${validate_ansi_text_root}"

validate_multiple_heredoc_root="${tmp_root}/validate-multiple-heredoc-gates"
prepare_root "${validate_multiple_heredoc_root}"
cp "${FIXTURE_DIR}/validate-multiple-heredoc-gates.yml" "${validate_multiple_heredoc_root}/.github/workflows/validate.yml"
expect_fail "validate multiple heredoc gates" "validate workflow runs make validate" "${validate_multiple_heredoc_root}"

validate_mixed_and_or_exit_root="${tmp_root}/validate-mixed-and-or-exit-before-gates"
prepare_root "${validate_mixed_and_or_exit_root}"
cp "${FIXTURE_DIR}/validate-mixed-and-or-exit-before-gates.yml" "${validate_mixed_and_or_exit_root}/.github/workflows/validate.yml"
expect_fail "validate mixed and or exit before gates" "validate workflow runs make validate" "${validate_mixed_and_or_exit_root}"

validate_mixed_or_and_exit_root="${tmp_root}/validate-mixed-or-and-exit-before-gates"
prepare_root "${validate_mixed_or_and_exit_root}"
cp "${FIXTURE_DIR}/validate-mixed-or-and-exit-before-gates.yml" "${validate_mixed_or_and_exit_root}/.github/workflows/validate.yml"
expect_fail "validate mixed or and exit before gates" "validate workflow runs make validate" "${validate_mixed_or_and_exit_root}"

validate_escaped_dollar_heredoc_root="${tmp_root}/validate-escaped-dollar-heredoc-gates"
prepare_root "${validate_escaped_dollar_heredoc_root}"
cp "${FIXTURE_DIR}/validate-escaped-dollar-heredoc-gates.yml" "${validate_escaped_dollar_heredoc_root}/.github/workflows/validate.yml"
expect_fail "validate escaped dollar heredoc gates" "validate workflow runs make validate" "${validate_escaped_dollar_heredoc_root}"

validate_hash_heredoc_root="${tmp_root}/validate-hash-heredoc-delimiter-gates"
prepare_root "${validate_hash_heredoc_root}"
cp "${FIXTURE_DIR}/validate-hash-heredoc-delimiter-gates.yml" "${validate_hash_heredoc_root}/.github/workflows/validate.yml"
expect_fail "validate hash heredoc delimiter gates" "validate workflow runs make validate" "${validate_hash_heredoc_root}"

validate_hash_suffixed_root="${tmp_root}/validate-hash-suffixed-gates"
prepare_root "${validate_hash_suffixed_root}"
cp "${FIXTURE_DIR}/validate-hash-suffixed-gates.yml" "${validate_hash_suffixed_root}/.github/workflows/validate.yml"
expect_fail "validate hash suffixed gates" "validate workflow runs make validate" "${validate_hash_suffixed_root}"

validate_line_continuation_hash_heredoc_root="${tmp_root}/validate-line-continuation-hash-heredoc-gates"
prepare_root "${validate_line_continuation_hash_heredoc_root}"
cp "${FIXTURE_DIR}/validate-line-continuation-hash-heredoc-gates.yml" "${validate_line_continuation_hash_heredoc_root}/.github/workflows/validate.yml"
expect_fail_with_stubbed_optional_tools "validate line continuation hash heredoc gates" "validate workflow runs make validate" "${validate_line_continuation_hash_heredoc_root}"

validate_one_line_if_exit_root="${tmp_root}/validate-one-line-if-exit-before-gates"
prepare_root "${validate_one_line_if_exit_root}"
cp "${FIXTURE_DIR}/validate-one-line-if-exit-before-gates.yml" "${validate_one_line_if_exit_root}/.github/workflows/validate.yml"
expect_fail "validate one line if exit before gates" "validate workflow runs make validate" "${validate_one_line_if_exit_root}"

validate_one_line_case_exit_root="${tmp_root}/validate-one-line-case-exit-before-gates"
prepare_root "${validate_one_line_case_exit_root}"
cp "${FIXTURE_DIR}/validate-one-line-case-exit-before-gates.yml" "${validate_one_line_case_exit_root}/.github/workflows/validate.yml"
expect_fail "validate one line case exit before gates" "validate workflow runs make validate" "${validate_one_line_case_exit_root}"

validate_one_line_case_command_exit_root="${tmp_root}/validate-one-line-case-command-exit-before-gates"
prepare_root "${validate_one_line_case_command_exit_root}"
cp "${FIXTURE_DIR}/validate-one-line-case-command-exit-before-gates.yml" "${validate_one_line_case_command_exit_root}/.github/workflows/validate.yml"
expect_fail "validate one line case command exit before gates" "validate workflow runs make validate" "${validate_one_line_case_command_exit_root}"

validate_one_line_case_later_arm_exit_root="${tmp_root}/validate-one-line-case-later-arm-exit-before-gates"
prepare_root "${validate_one_line_case_later_arm_exit_root}"
cp "${FIXTURE_DIR}/validate-one-line-case-later-arm-exit-before-gates.yml" "${validate_one_line_case_later_arm_exit_root}/.github/workflows/validate.yml"
expect_fail "validate one line case later arm exit before gates" "validate workflow runs make validate" "${validate_one_line_case_later_arm_exit_root}"

validate_redirection_suffixed_root="${tmp_root}/validate-redirection-suffixed-gates"
prepare_root "${validate_redirection_suffixed_root}"
cp "${FIXTURE_DIR}/validate-redirection-suffixed-gates.yml" "${validate_redirection_suffixed_root}/.github/workflows/validate.yml"
expect_fail "validate redirection suffixed gates" "validate workflow runs make validate" "${validate_redirection_suffixed_root}"

validate_quoted_case_terminator_exit_root="${tmp_root}/validate-quoted-case-terminator-exit-before-gates"
prepare_root "${validate_quoted_case_terminator_exit_root}"
cp "${FIXTURE_DIR}/validate-quoted-case-terminator-exit-before-gates.yml" "${validate_quoted_case_terminator_exit_root}/.github/workflows/validate.yml"
expect_fail "validate quoted case terminator exit before gates" "validate workflow runs make validate" "${validate_quoted_case_terminator_exit_root}"

validate_process_substitution_pipe_exit_root="${tmp_root}/validate-process-substitution-pipe-exit-before-gates"
prepare_root "${validate_process_substitution_pipe_exit_root}"
cp "${FIXTURE_DIR}/validate-process-substitution-pipe-exit-before-gates.yml" "${validate_process_substitution_pipe_exit_root}/.github/workflows/validate.yml"
expect_fail_with_stubbed_optional_tools "validate process substitution pipe exit before gates" "validate workflow runs make validate" "${validate_process_substitution_pipe_exit_root}"

validate_process_substitution_and_exit_root="${tmp_root}/validate-process-substitution-and-exit-before-gates"
prepare_root "${validate_process_substitution_and_exit_root}"
cp "${FIXTURE_DIR}/validate-process-substitution-and-exit-before-gates.yml" "${validate_process_substitution_and_exit_root}/.github/workflows/validate.yml"
expect_fail "validate process substitution and exit before gates" "validate workflow runs make validate" "${validate_process_substitution_and_exit_root}"

validate_set_plus_e_root="${tmp_root}/validate-set-plus-e-gates"
prepare_root "${validate_set_plus_e_root}"
cp "${FIXTURE_DIR}/validate-set-plus-e-gates.yml" "${validate_set_plus_e_root}/.github/workflows/validate.yml"
expect_fail "validate set plus e gates" "validate workflow runs make validate" "${validate_set_plus_e_root}"

validate_always_true_set_plus_e_root="${tmp_root}/validate-always-true-set-plus-e-gates"
prepare_root "${validate_always_true_set_plus_e_root}"
cp "${FIXTURE_DIR}/validate-always-true-set-plus-e-gates.yml" "${validate_always_true_set_plus_e_root}/.github/workflows/validate.yml"
expect_fail "validate always true set plus e gates" "validate workflow runs make validate" "${validate_always_true_set_plus_e_root}"

validate_always_true_one_line_set_plus_e_root="${tmp_root}/validate-always-true-one-line-set-plus-e-gates"
prepare_root "${validate_always_true_one_line_set_plus_e_root}"
cp "${FIXTURE_DIR}/validate-always-true-one-line-set-plus-e-gates.yml" "${validate_always_true_one_line_set_plus_e_root}/.github/workflows/validate.yml"
expect_fail "validate always true one line set plus e gates" "validate workflow runs make validate" "${validate_always_true_one_line_set_plus_e_root}"

validate_always_true_short_circuit_pipeline_or_exit_root="${tmp_root}/validate-always-true-short-circuit-pipeline-or-exit-before-gates"
prepare_root "${validate_always_true_short_circuit_pipeline_or_exit_root}"
cp "${FIXTURE_DIR}/validate-always-true-short-circuit-pipeline-or-exit-before-gates.yml" "${validate_always_true_short_circuit_pipeline_or_exit_root}/.github/workflows/validate.yml"
expect_fail "validate always true short circuit pipeline or exit before gates" "validate workflow runs make validate" "${validate_always_true_short_circuit_pipeline_or_exit_root}"

validate_always_true_one_line_or_exit_root="${tmp_root}/validate-always-true-one-line-or-exit-before-gates"
prepare_root "${validate_always_true_one_line_or_exit_root}"
cp "${FIXTURE_DIR}/validate-always-true-one-line-or-exit-before-gates.yml" "${validate_always_true_one_line_or_exit_root}/.github/workflows/validate.yml"
expect_fail "validate always true one line or exit before gates" "validate workflow runs make validate" "${validate_always_true_one_line_or_exit_root}"

validate_case_empty_literal_exit_root="${tmp_root}/validate-case-empty-literal-exit-before-gates"
prepare_root "${validate_case_empty_literal_exit_root}"
cp "${FIXTURE_DIR}/validate-case-empty-literal-exit-before-gates.yml" "${validate_case_empty_literal_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case empty literal exit before gates" "validate workflow runs make validate" "${validate_case_empty_literal_exit_root}"

validate_case_active_arm_pipeline_or_exit_root="${tmp_root}/validate-case-active-arm-pipeline-or-exit-before-gates"
prepare_root "${validate_case_active_arm_pipeline_or_exit_root}"
cp "${FIXTURE_DIR}/validate-case-active-arm-pipeline-or-exit-before-gates.yml" "${validate_case_active_arm_pipeline_or_exit_root}/.github/workflows/validate.yml"
expect_fail "validate case active arm pipeline or exit before gates" "validate workflow runs make validate" "${validate_case_active_arm_pipeline_or_exit_root}"

validate_short_circuit_or_exit_root="${tmp_root}/validate-short-circuit-or-exit-gates"
prepare_root "${validate_short_circuit_or_exit_root}"
cp "${FIXTURE_DIR}/validate-short-circuit-or-exit-gates.yml" "${validate_short_circuit_or_exit_root}/.github/workflows/validate.yml"
expect_fail "validate short circuit or exit gates" "validate workflow runs make validate" "${validate_short_circuit_or_exit_root}"

validate_short_circuit_pipeline_or_exit_root="${tmp_root}/validate-short-circuit-pipeline-or-exit-before-gates"
prepare_root "${validate_short_circuit_pipeline_or_exit_root}"
cp "${FIXTURE_DIR}/validate-short-circuit-pipeline-or-exit-before-gates.yml" "${validate_short_circuit_pipeline_or_exit_root}/.github/workflows/validate.yml"
expect_fail "validate short circuit pipeline or exit before gates" "validate workflow runs make validate" "${validate_short_circuit_pipeline_or_exit_root}"

validate_unquoted_hash_heredoc_root="${tmp_root}/validate-unquoted-hash-heredoc-gates"
prepare_root "${validate_unquoted_hash_heredoc_root}"
cp "${FIXTURE_DIR}/validate-unquoted-hash-heredoc-gates.yml" "${validate_unquoted_hash_heredoc_root}/.github/workflows/validate.yml"
expect_fail "validate unquoted hash heredoc gates" "validate workflow runs make validate" "${validate_unquoted_hash_heredoc_root}"

validate_conditional_heredoc_root="${tmp_root}/validate-conditional-heredoc-gates"
prepare_root "${validate_conditional_heredoc_root}"
cp "${FIXTURE_DIR}/validate-conditional-heredoc-gates.yml" "${validate_conditional_heredoc_root}/.github/workflows/validate.yml"
expect_fail "validate conditional heredoc gates" "validate workflow runs make validate" "${validate_conditional_heredoc_root}"

validate_block_close_heredoc_root="${tmp_root}/validate-block-close-heredoc-gates"
prepare_root "${validate_block_close_heredoc_root}"
cp "${FIXTURE_DIR}/validate-block-close-heredoc-gates.yml" "${validate_block_close_heredoc_root}/.github/workflows/validate.yml"
expect_fail "validate block close heredoc gates" "validate workflow runs make validate" "${validate_block_close_heredoc_root}"

validate_while_exit_root="${tmp_root}/validate-while-exit-before-gates"
prepare_root "${validate_while_exit_root}"
cp "${FIXTURE_DIR}/validate-while-exit-before-gates.yml" "${validate_while_exit_root}/.github/workflows/validate.yml"
expect_fail "validate while exit before gates" "validate workflow runs make validate" "${validate_while_exit_root}"

rm -rf "${tmp_root}"
printf 'PASS story-2.4 workflow permission fixtures\n'
