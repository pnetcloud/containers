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
    permission: packages
    reason: Story fixture release permission
    owner_story: Story 4.5
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

for fixture in valid-least-privilege.yml write-all.yml top-level-write.yml pr-write-token.yml unpinned-action.yml release-sensitive-permission.yml valid-allowlisted-permission.yml invalid-allowlist-entry.yml missing-strict-mode.sh; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || { diag "test -f" "${FIXTURE_DIR}/${fixture}" "fixture exists" "missing" "Restore Story 2.4 workflow policy fixtures."; exit 1; }
done

tmp_root="$(mktemp -d)"

valid_root="${tmp_root}/valid"
prepare_root "${valid_root}"
expect_pass "valid least privilege" "${valid_root}"

allow_root="${tmp_root}/allowlisted"
prepare_root "${allow_root}"
cp "${FIXTURE_DIR}/valid-allowlisted-permission.yml" "${allow_root}/.github/workflows/update.yml"
write_allowlist_policy "${allow_root}/cloudnative-pg-timescaledb/workflow-policy.yaml"
expect_pass "valid allowlisted permission" "${allow_root}"

for tuple in \
  "write-all.yml no write-all permissions" \
  "top-level-write.yml no top-level write permissions" \
  "pr-write-token.yml pull_request workflows do not receive write tokens" \
  "unpinned-action.yml third-party actions pinned" \
  "release-sensitive-permission.yml write permissions are explicitly allowlisted"; do
  read -r fixture pattern <<<"${tuple}"
  target="${tmp_root}/${fixture%.yml}"
  prepare_root "${target}"
  cp "${FIXTURE_DIR}/${fixture}" "${target}/.github/workflows/update.yml"
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

rm -rf "${tmp_root}"
printf 'PASS story-2.4 workflow permission fixtures\n'
