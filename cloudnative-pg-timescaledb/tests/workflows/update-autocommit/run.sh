#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/update-autocommit/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

prepare_project() {
  local target="$1"
  mkdir -p "${target}/cloudnative-pg-timescaledb/scripts" "${target}/cloudnative-pg-timescaledb/config" "${target}/cloudnative-pg-timescaledb/generated/18/trixie" "${target}/cloudnative-pg-timescaledb/docs/generated" "${target}/cloudnative-pg-timescaledb/catalog"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/autocommit-stage.sh" "${target}/cloudnative-pg-timescaledb/scripts/autocommit-stage.sh"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh" "${target}/cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/config/autocommit-allowlist.txt" "${target}/cloudnative-pg-timescaledb/config/autocommit-allowlist.txt"
  printf 'baseline\n' >"${target}/cloudnative-pg-timescaledb/versions.yaml"
  printf 'baseline\n' >"${target}/cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile"
  printf 'baseline\n' >"${target}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md"
  printf 'baseline\n' >"${target}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md"
  printf 'baseline\n' >"${target}/cloudnative-pg-timescaledb/docker-bake.hcl"
  printf '{"include":[]}\n' >"${target}/cloudnative-pg-timescaledb/matrix.json"
  printf 'baseline\n' >"${target}/cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml"
  (cd "${target}" && git init -q && git config user.email test@example.invalid && git config user.name test && git add . && git commit -qm baseline)
}

run_stage_validate() {
  local project="$1"
  (cd "${project}" && cloudnative-pg-timescaledb/scripts/autocommit-stage.sh >/tmp/story-2-5-stage.out && cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh >/tmp/story-2-5-validate.out)
}

expect_fail() {
  local description="$1"
  local pattern="$2"
  shift 2
  local tmp status
  tmp="$(mktemp)"
  set +e
  "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "${*}" "${description}" "fails" "passed" "Make the autocommit fixture fail on its intended safety invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep autocommit diagnostics deterministic and specific."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

assert_staged() {
  local project="$1"
  local expected="$2"
  local actual
  actual="$(cd "${project}" && git diff --cached --name-only | paste -sd ',' -)"
  if [[ "${actual}" != "${expected}" ]]; then
    diag "git diff --cached --name-only" "${project}" "${expected}" "${actual}" "Stage only the expected autocommit allowlist paths."
    exit 1
  fi
}

for fixture in no-op metadata-change generated-change barman-doc-change secret-file-staged untracked-vendor-staged runtime-artifact-staged outside-allowlist-staged; do
  [[ -d "${FIXTURE_DIR}/${fixture}" ]] || { diag "test -d" "${FIXTURE_DIR}/${fixture}" "fixture directory exists" "missing" "Restore Story 2.5 update-autocommit fixture directory."; exit 1; }
done

tmp_root="$(mktemp -d)"

noop="${tmp_root}/no-op"
prepare_project "${noop}"
run_stage_validate "${noop}"
assert_staged "${noop}" ""

metadata="${tmp_root}/metadata-change"
prepare_project "${metadata}"
printf 'changed\n' >"${metadata}/cloudnative-pg-timescaledb/versions.yaml"
run_stage_validate "${metadata}"
assert_staged "${metadata}" "cloudnative-pg-timescaledb/versions.yaml"

generated="${tmp_root}/generated-change"
prepare_project "${generated}"
printf 'changed\n' >"${generated}/cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile"
run_stage_validate "${generated}"
assert_staged "${generated}" "cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile"

barman_doc="${tmp_root}/barman-doc-change"
prepare_project "${barman_doc}"
printf 'changed\n' >"${barman_doc}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md"
run_stage_validate "${barman_doc}"
assert_staged "${barman_doc}" "cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md"

matrix_schema="${tmp_root}/matrix-schema-change"
prepare_project "${matrix_schema}"
printf 'changed\n' >"${matrix_schema}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md"
run_stage_validate "${matrix_schema}"
assert_staged "${matrix_schema}" "cloudnative-pg-timescaledb/docs/generated/matrix-schema.md"

secret="${tmp_root}/secret-file-staged"
prepare_project "${secret}"
printf 'TOKEN=bad\n' >"${secret}/.env"
(cd "${secret}" && git add .env)
expect_fail "secret file staged" "secret-like|\.env" bash -c "cd '${secret}' && cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh"

vendor="${tmp_root}/untracked-vendor-staged"
prepare_project "${vendor}"
mkdir -p "${vendor}/vendor"
printf 'vendored\n' >"${vendor}/vendor/untracked.txt"
expect_fail "untracked vendor" "vendor changes" bash -c "cd '${vendor}' && cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh"

runtime="${tmp_root}/runtime-artifact-staged"
prepare_project "${runtime}"
printf 'runtime\n' >"${runtime}/cloudnative-pg-timescaledb/generated/runtime.log"
(cd "${runtime}" && git add cloudnative-pg-timescaledb/generated/runtime.log)
expect_fail "runtime artifact staged" "runtime/build artifacts" bash -c "cd '${runtime}' && cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh"

outside="${tmp_root}/outside-allowlist-staged"
prepare_project "${outside}"
printf 'changed\n' >"${outside}/cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml"
(cd "${outside}" && git add cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml)
expect_fail "outside allowlist staged" "autocommit allowlist" bash -c "cd '${outside}' && cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh"

rm -rf "${tmp_root}"
printf 'PASS story-2.5 update autocommit fixtures\n'
