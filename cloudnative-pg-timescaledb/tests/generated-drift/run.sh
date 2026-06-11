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
  if [[ -d "${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata" ]]; then
    cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata" "${target}/release-metadata"
  fi
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docker-bake.hcl" "${target}/docker-bake.hcl"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/matrix.json" "${target}/matrix.json"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/compatibility.md" "${target}/docs/generated/compatibility.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/compatibility-table.md" "${target}/docs/generated/compatibility-table.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" "${target}/docs/generated/barman-plugin-reference.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md" "${target}/docs/generated/matrix-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md" "${target}/docs/generated/release-candidate-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md" "${target}/docs/generated/release-evidence-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md" "${target}/docs/generated/failure-reason-catalog.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md" "${target}/docs/generated/release-rehearsal-report.md"
}

manifest_fixture() {
  local target="$1"
  cat >"${target}" <<'JSON'
{
  "manifests": [
    {
      "tag": "17.10-standard-trixie",
      "digest": "sha256:fdc339fb142d56b852e2c9ca2474f1d52bf798ff9b8381800b520597f0ff7cc2",
      "platforms": ["linux/amd64", "linux/arm64"]
    },
    {
      "tag": "18.4-standard-trixie",
      "digest": "sha256:184219ecec559d15fa03932b0d3005e0372f7027746bb682aca478bc4918f776",
      "platforms": ["linux/amd64", "linux/arm64"]
    },
    {
      "tag": "19beta1-standard-trixie",
      "digest": "sha256:ce40f7266c82a453bb38f4a253819a8226606460e6fc12bbd4abfe337f955e60",
      "platforms": ["linux/amd64", "linux/arm64"]
    },
    {
      "tag": "17.10-standard-bookworm",
      "digest": "sha256:1273ed2ff3c3777541a010f98b805f139810f89ea240b8caeaee3efaca7bb2b8",
      "platforms": ["linux/amd64", "linux/arm64"]
    },
    {
      "tag": "18.4-standard-bookworm",
      "digest": "sha256:6d1090d7ae1ea1cf2ba35959ba0fea38a78df91cf99e02e94a28b8e1f6df3de5",
      "platforms": ["linux/amd64", "linux/arm64"]
    },
    {
      "tag": "19beta1-standard-bookworm",
      "digest": "sha256:5622736e77f38a017b0ed8ea64a8d690808235492344f831a9863f38779f2a71",
      "platforms": ["linux/amd64", "linux/arm64"]
    }
  ]
}
JSON
}

run_validator() {
  local fixture_root="$1"
  local manifest
  manifest="${fixture_root}/cnpg-manifest-fixture.json"
  manifest_fixture "${manifest}"
  CNPG_MANIFEST_FIXTURE="${manifest}" "${VALIDATOR}" \
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

prepare_generate_check_project() {
  local target="$1"
  mkdir -p "${target}/cloudnative-pg-timescaledb" "${target}/docs"
  cp "${ROOT_DIR}/Makefile" "${target}/Makefile"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts" "${target}/cloudnative-pg-timescaledb/scripts"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/templates" "${target}/cloudnative-pg-timescaledb/templates"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/config" "${target}/cloudnative-pg-timescaledb/config"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/generated" "${target}/cloudnative-pg-timescaledb/generated"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/catalog" "${target}/cloudnative-pg-timescaledb/catalog"
  if [[ -d "${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata" ]]; then
    cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata" "${target}/cloudnative-pg-timescaledb/release-metadata"
  fi
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/docs" "${target}/cloudnative-pg-timescaledb/docs"
  mkdir -p "${target}/cloudnative-pg-timescaledb/tests/release-rehearsal"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures" "${target}/cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${target}/cloudnative-pg-timescaledb/versions.yaml"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docker-bake.hcl" "${target}/cloudnative-pg-timescaledb/docker-bake.hcl"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/matrix.json" "${target}/cloudnative-pg-timescaledb/matrix.json"
  cp "${ROOT_DIR}/docs/generator-contracts.md" "${target}/docs/generator-contracts.md"
}

test -d "${FIXTURE_DIR}/clean" || { diag "test -d clean fixture" "${FIXTURE_DIR}/clean" "fixture directory exists" "missing" "Restore clean generated-drift fixture directory."; exit 1; }
test -d "${FIXTURE_DIR}/stale" || { diag "test -d stale fixture" "${FIXTURE_DIR}/stale" "fixture directory exists" "missing" "Restore stale generated-drift fixture directory."; exit 1; }

clean_root="$(mktemp -d)"
prepare_fixture "${clean_root}"
run_validator "${clean_root}" >/tmp/story-1-6-clean.out
rm -rf "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/__pycache__"
run_validator "${clean_root}" >/tmp/story-1-6-no-bytecode.out
if [[ -e "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/__pycache__" ]]; then
  diag "validate-generated bytecode hygiene" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/__pycache__" "validation leaves checkout free of Python bytecode cache" "present" "Keep PYTHONDONTWRITEBYTECODE=1 set for validation paths."
  rm -rf "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/__pycache__"
  exit 1
fi

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
payload["include"] = payload["include"][:-1]
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

stale_table_root="$(mktemp -d)"
prepare_fixture "${stale_table_root}"
printf '\n<!-- hand edit that must be regenerated -->\n' >>"${stale_table_root}/docs/generated/compatibility-table.md"
expect_fail "stale generated compatibility table" "compatibility-table.md|committed output matches generated content|make generate" "${stale_table_root}"

stale_failure_catalog_root="$(mktemp -d)"
prepare_fixture "${stale_failure_catalog_root}"
printf '\n<!-- hand edit that must be regenerated -->\n' >>"${stale_failure_catalog_root}/docs/generated/failure-reason-catalog.md"
expect_fail "stale generated failure reason catalog" "failure-reason-catalog.md|committed output matches generated content|make generate" "${stale_failure_catalog_root}"

stale_rehearsal_report_root="$(mktemp -d)"
prepare_fixture "${stale_rehearsal_report_root}"
printf '\n<!-- hand edit that must be regenerated -->\n' >>"${stale_rehearsal_report_root}/docs/generated/release-rehearsal-report.md"
expect_fail "stale generated release rehearsal report" "release-rehearsal-report.md|committed output matches generated content|make generate" "${stale_rehearsal_report_root}"

stale_generate_check_root="$(mktemp -d)"
prepare_generate_check_project "${stale_generate_check_root}"
printf '\n<!-- hand edit that must be regenerated -->\n' >>"${stale_generate_check_root}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md"
expect_direct_fail "make generate check detects stale release rehearsal report" "release-rehearsal-report.md|committed output matches generated content|make generate" make --no-print-directory -C "${stale_generate_check_root}" generate GENERATE_ARGS=--check

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
expect_direct_fail "stale generator contract docs" "generator-contracts.md matches current generator contract" "${VALIDATOR}" --contract-root "${stale_contract_root}"

stale_schema_fixture_root="$(mktemp -d)"
prepare_contract_root "${stale_schema_fixture_root}"
python3 - "${stale_schema_fixture_root}/cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["include"] = payload["include"][:-1]
path.write_text(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
PY
expect_direct_fail "stale generator schema fixture" "generate-matrix-valid.json|generate-matrix.sh --json > cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json" "${VALIDATOR}" --contract-root "${stale_schema_fixture_root}"

nonexec_contract_root="$(mktemp -d)"
prepare_contract_root "${nonexec_contract_root}"
chmod -x "${nonexec_contract_root}/cloudnative-pg-timescaledb/scripts/generate-matrix.sh"
expect_direct_fail "non-executable generator entrypoint" "generator entrypoint is executable" "${VALIDATOR}" --contract-root "${nonexec_contract_root}"

printf 'PASS story-1.6 generated drift validation fixtures\n'
