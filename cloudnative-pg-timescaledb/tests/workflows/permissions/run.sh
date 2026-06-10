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
  valid-release-allowlisted-permissions.yml \
  write-all.yml \
  top-level-write.yml \
  broad-top-level-write.yml \
  pr-write-token.yml \
  unpinned-action.yml \
  unpinned-release-action.yml \
  action-short-sha.yml \
  action-missing-version-comment.yml \
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
  valid-update-autocommit-contents-write.yml \
  invalid-update-nonautocommit-contents-write.yml; do
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
  "pr-write-token.yml pull_request workflows do not receive write tokens" \
  "pr-inline-list-write-token.yml pull_request workflows do not receive write tokens" \
  "pr-scalar-write-token.yml pull_request workflows do not receive write tokens" \
  "pr-target-write-token.yml pull_request workflows do not receive write tokens" \
  "unpinned-action.yml third-party actions pinned" \
  "unpinned-release-action.yml third-party actions pinned" \
  "action-short-sha.yml third-party actions pinned" \
  "action-missing-version-comment.yml pinned actions include readable version comments" \
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

rm -rf "${tmp_root}"
printf 'PASS story-2.4 workflow permission fixtures\n'
