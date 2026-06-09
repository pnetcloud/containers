#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-generated.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generated-drift/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

prepare_fixture() {
  local target="$1"
  mkdir -p "${target}/docs/generated"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/generated" "${target}/generated"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/catalog" "${target}/catalog"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docker-bake.hcl" "${target}/docker-bake.hcl"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/matrix.json" "${target}/matrix.json"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/compatibility.md" "${target}/docs/generated/compatibility.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" "${target}/docs/generated/barman-plugin-reference.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md" "${target}/docs/generated/matrix-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md" "${target}/docs/generated/release-candidate-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md" "${target}/docs/generated/release-evidence-schema.md"
}

run_validator() {
  local fixture_root="$1"
  "${VALIDATOR}" \
    --generated-root "${fixture_root}/generated" \
    --bake-file "${fixture_root}/docker-bake.hcl" \
    --matrix-file "${fixture_root}/matrix.json" \
    --catalog-root "${fixture_root}/catalog" \
    --docs-file "${fixture_root}/docs/generated/compatibility.md"
}

prepare_contract_root() {
  local target="$1"
  mkdir -p "${target}/docs" "${target}/cloudnative-pg-timescaledb/tests/generators/fixtures" "${target}/cloudnative-pg-timescaledb/scripts"
  cp "${ROOT_DIR}/docs/generator-contracts.md" "${target}/docs/generator-contracts.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/run.sh" "${target}/cloudnative-pg-timescaledb/tests/generators/run.sh"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-valid.json" "${target}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-valid.json"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json" "${target}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json" "${target}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json" "${target}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json" "${target}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh" "${target}/cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-bake.sh" "${target}/cloudnative-pg-timescaledb/scripts/generate-bake.sh"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-matrix.sh" "${target}/cloudnative-pg-timescaledb/scripts/generate-matrix.sh"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-catalog.sh" "${target}/cloudnative-pg-timescaledb/scripts/generate-catalog.sh"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-docs.sh" "${target}/cloudnative-pg-timescaledb/scripts/generate-docs.sh"
  chmod +x "${target}"/cloudnative-pg-timescaledb/scripts/generate-*.sh
}

expect_fail() {
  local description="$1"
  local pattern="$2"
  local fixture_root="$3"
  local tmp status
  tmp="$(mktemp)"
  set +e
  run_validator "${fixture_root}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-generated ${fixture_root}" "${description}" "fixture fails" "passed" "Make stale generated artifacts fail drift validation."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-generated ${fixture_root}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Report the stale artifact and regeneration command."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

expect_direct_fail() {
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
    diag "${*}" "${description}" "command fails" "passed" "Make generated drift contract failures fail validation."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Report the stale or missing contract artifact."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

test -d "${FIXTURE_DIR}/clean" || { diag "test -d clean fixture" "${FIXTURE_DIR}/clean" "fixture directory exists" "missing" "Restore clean generated-drift fixture directory."; exit 1; }
test -d "${FIXTURE_DIR}/stale" || { diag "test -d stale fixture" "${FIXTURE_DIR}/stale" "fixture directory exists" "missing" "Restore stale generated-drift fixture directory."; exit 1; }

clean_root="$(mktemp -d)"
prepare_fixture "${clean_root}"
run_validator "${clean_root}" >/tmp/story-1-6-clean.out

stale_dockerfile_root="$(mktemp -d)"
prepare_fixture "${stale_dockerfile_root}"
printf '\n# hand edit that must be regenerated\n' >>"${stale_dockerfile_root}/generated/18/trixie/Dockerfile"
expect_fail "stale generated Dockerfile" "generated/18/trixie/Dockerfile|committed output matches generated content|make generate" "${stale_dockerfile_root}"

stale_matrix_root="$(mktemp -d)"
prepare_fixture "${stale_matrix_root}"
python3 - "${stale_matrix_root}/matrix.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["skipped"][1]["latest_eligible"] = False
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
expect_fail "stale generated matrix" "matrix.json|committed output matches generated content|make generate" "${stale_matrix_root}"

stale_bake_root="$(mktemp -d)"
prepare_fixture "${stale_bake_root}"
printf '\n# hand edit that must be regenerated\n' >>"${stale_bake_root}/docker-bake.hcl"
expect_fail "stale generated Bake file" "docker-bake.hcl|committed output matches generated content|make generate" "${stale_bake_root}"

stale_catalog_root="$(mktemp -d)"
prepare_fixture "${stale_catalog_root}"
printf '\n# hand edit that must be regenerated\n' >>"${stale_catalog_root}/catalog/catalog-standard-trixie.yaml"
expect_fail "stale generated catalog" "catalog-standard-trixie.yaml|committed output matches generated content|make generate" "${stale_catalog_root}"

stale_docs_root="$(mktemp -d)"
prepare_fixture "${stale_docs_root}"
printf '\n<!-- hand edit that must be regenerated -->\n' >>"${stale_docs_root}/docs/generated/compatibility.md"
expect_fail "stale generated docs" "compatibility.md|committed output matches generated content|make generate" "${stale_docs_root}"

orphan_dockerfile_root="$(mktemp -d)"
prepare_fixture "${orphan_dockerfile_root}"
mkdir -p "${orphan_dockerfile_root}/generated/99/trixie"
printf '# stale orphan Dockerfile\n' >"${orphan_dockerfile_root}/generated/99/trixie/Dockerfile"
expect_fail "orphan generated Dockerfile" "generated artifact file set|generated/99/trixie/Dockerfile|make generate" "${orphan_dockerfile_root}"

orphan_catalog_root="$(mktemp -d)"
prepare_fixture "${orphan_catalog_root}"
printf 'apiVersion: stale\n' >"${orphan_catalog_root}/catalog/catalog-standard-bullseye.yaml"
expect_fail "orphan generated catalog" "generated artifact file set|catalog-standard-bullseye.yaml|make generate" "${orphan_catalog_root}"

orphan_docs_root="$(mktemp -d)"
prepare_fixture "${orphan_docs_root}"
printf '# stale generated docs\n' >"${orphan_docs_root}/docs/generated/old-compatibility.md"
expect_fail "orphan generated docs" "generated artifact file set|old-compatibility.md|make generate" "${orphan_docs_root}"

tmp="$(mktemp)"
set +e
"${VALIDATOR}" --generated-root >"${tmp}" 2>&1
status="$?"
set -e
if [[ "${status}" != "64" ]] || ! grep -Fq 'Pass --generated-root <path>' "${tmp}"; then
  diag "${VALIDATOR} --generated-root" "missing option value" "exit 64 with deterministic diagnostic" "exit ${status}: $(tr '\n' ' ' <"${tmp}")" "Validate missing option values before shifting arguments."
  rm -f "${tmp}"
  exit 1
fi
rm -f "${tmp}"

missing_contract_root="$(mktemp -d)"
prepare_contract_root "${missing_contract_root}"
rm -f "${missing_contract_root}/docs/generator-contracts.md"
expect_direct_fail "missing generator contract docs" "Story 1.5 generator contract artifact exists" "${VALIDATOR}" --contract-root "${missing_contract_root}"

stale_contract_root="$(mktemp -d)"
prepare_contract_root "${stale_contract_root}"
printf '\nContradictory hand edit.\n' >>"${stale_contract_root}/docs/generator-contracts.md"
expect_direct_fail "stale generator contract docs" "generator-contracts.md matches Story 1.5 generator contract" "${VALIDATOR}" --contract-root "${stale_contract_root}"

nonexec_contract_root="$(mktemp -d)"
prepare_contract_root "${nonexec_contract_root}"
chmod -x "${nonexec_contract_root}/cloudnative-pg-timescaledb/scripts/generate-matrix.sh"
expect_direct_fail "non-executable generator entrypoint" "generator entrypoint is executable" "${VALIDATOR}" --contract-root "${nonexec_contract_root}"

printf 'PASS story-1.6 generated drift validation fixtures\n'
