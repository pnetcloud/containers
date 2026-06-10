#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs-validation/fixtures"
VALIDATE_DOCS="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-docs.sh"
VALIDATE_WORKFLOWS="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-workflows.sh"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

copy_base_docs_root() {
  local target="$1"
  mkdir -p \
    "${target}/cloudnative-pg-timescaledb" \
    "${target}/cloudnative-pg-timescaledb/docs" \
    "${target}/cloudnative-pg-timescaledb/catalog" \
    "${target}/docs"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${target}/cloudnative-pg-timescaledb/versions.yaml"
  cp -a "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated" "${target}/cloudnative-pg-timescaledb/docs/"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml" "${target}/cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml" "${target}/cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml"
}

run_docs_fixture() {
  local fixture="$1"
  local tmp status
  tmp="$(mktemp -d)"
  copy_base_docs_root "${tmp}"
  cp -a "${FIXTURE_DIR}/${fixture}/." "${tmp}/"
  set +e
  "${VALIDATE_DOCS}" --root "${tmp}"
  status="$?"
  rm -rf "${tmp}"
  if [[ "${status}" == "0" ]]; then
    set -e
  fi
  return "${status}"
}

expect_docs_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status out
  tmp="$(mktemp)"
  set +e
  run_docs_fixture "${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-docs --root fixture" "${FIXTURE_DIR}/${fixture}" "fixture fails" "passed" "Make the docs-validation fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  out="$(tr '\n' ' ' <"${tmp}")"
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-docs --root fixture" "${FIXTURE_DIR}/${fixture}" "diagnostic matches ${pattern}" "${out}" "Keep docs validation diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  for required in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "validate-docs --root fixture" "${FIXTURE_DIR}/${fixture}" "diagnostic includes ${required}" "${out}" "Use the standard validation diagnostic shape."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

write_minimal_workflow_root() {
  local target="$1"
  mkdir -p "${target}/.github/workflows" "${target}/cloudnative-pg-timescaledb/scripts" "${target}/cloudnative-pg-timescaledb"
  cat >"${target}/cloudnative-pg-timescaledb/workflow-policy.yaml" <<'EOF'
action_pin_exceptions: []
strict_mode_exceptions: []
permission_allowlist: []
EOF
  cat >"${target}/.github/workflows/validate.yml" <<'EOF'
name: Validate
on:
  pull_request:
  push:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  validate:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      # actions/checkout v4.2.2
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - run: |
          set -Eeuo pipefail
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends shellcheck
          go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.7
      - run: make validate
      - run: find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z | xargs -0 actionlint
      - run: git ls-files 'cloudnative-pg-timescaledb/scripts/*.sh' 'cloudnative-pg-timescaledb/scripts/**/*.sh' | sort | xargs shellcheck
EOF
}

expect_workflow_fail() {
  local description="$1"
  local pattern="$2"
  shift 2
  local tmp status out
  tmp="$(mktemp)"
  set +e
  "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "$*" "${description}" "fails" "passed" "Make the workflow validation fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  out="$(tr '\n' ' ' <"${tmp}")"
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "$*" "${description}" "diagnostic matches ${pattern}" "${out}" "Keep workflow diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

validate_machine_script() {
  local script="$1"
  python3 - "${script}" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

script = Path(sys.argv[1])
proc = subprocess.run([str(script)], text=True, capture_output=True, check=False)
command = f"validate-machine-interface {script}"

def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {script}\n"
        f"expected: {expected}\n"
        f"actual: {str(actual).replace(chr(10), ' ')[:240]}\n"
        f"remediation: {remediation}"
    )

if proc.returncode != 0:
    fail("script exits 0", proc.returncode, "Keep machine-interface fixtures executable.")
stdout = proc.stdout
if not stdout.endswith("\n") or "\n" in stdout[:-1]:
    fail("stdout is one compact JSON line", repr(stdout), "Write compact JSON only to stdout.")
try:
    json.loads(stdout)
except json.JSONDecodeError as exc:
    fail("stdout is valid compact JSON", str(exc), "Do not write human diagnostics to stdout.")
if proc.stderr.strip().startswith("{") or proc.stderr.strip().startswith("["):
    fail("stderr contains human diagnostics only", proc.stderr, "Do not write JSON payloads to stderr.")
PY
}

expect_machine_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status out
  tmp="$(mktemp)"
  set +e
  validate_machine_script "${FIXTURE_DIR}/${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-machine-interface" "${FIXTURE_DIR}/${fixture}" "fixture fails" "passed" "Make the machine-interface fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  out="$(tr '\n' ' ' <"${tmp}")"
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-machine-interface" "${FIXTURE_DIR}/${fixture}" "diagnostic matches ${pattern}" "${out}" "Keep machine-interface diagnostics deterministic."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

for fixture in \
  valid-docs-set \
  stale-generated-docs \
  wrong-latest-example \
  generated-doc-wrong-latest-example \
  unpublished-catalog-reference \
  legacy-barman-guidance; do
  [[ -d "${FIXTURE_DIR}/${fixture}" ]] || { diag "test -d" "${FIXTURE_DIR}/${fixture}" "docs-validation fixture exists" "missing" "Restore the Story 5.7 docs-validation fixture set."; exit 1; }
done
for fixture in \
  script-missing-strict-mode.sh \
  script-valid-compact-json.sh \
  script-json-to-stderr.sh \
  script-human-diagnostics-to-stdout.sh \
  actionlint-invalid-workflow.yml; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || { diag "test -f" "${FIXTURE_DIR}/${fixture}" "docs-validation fixture exists" "missing" "Restore the Story 5.7 docs-validation fixture set."; exit 1; }
done

run_docs_fixture valid-docs-set >/tmp/story-5-7-valid-docs.out
expect_docs_fail stale-generated-docs "stale|committed generated docs"
expect_docs_fail wrong-latest-example "latest is not used as a primary|latest is convenience-only"
expect_docs_fail generated-doc-wrong-latest-example "stale|latest is convenience-only"
expect_docs_fail unpublished-catalog-reference "unpublished"
expect_docs_fail legacy-barman-guidance "barman-cloud|Barman Cloud Plugin"

validate_machine_script "${FIXTURE_DIR}/script-valid-compact-json.sh"
expect_machine_fail script-json-to-stderr.sh "stderr contains human diagnostics only"
expect_machine_fail script-human-diagnostics-to-stdout.sh "valid compact JSON|human diagnostics"

strict_tmp="$(mktemp -d)"
write_minimal_workflow_root "${strict_tmp}"
cp "${FIXTURE_DIR}/script-missing-strict-mode.sh" "${strict_tmp}/cloudnative-pg-timescaledb/scripts/script-missing-strict-mode.sh"
expect_workflow_fail "script missing strict mode" "strict mode|pipefail" env VALIDATE_WORKFLOWS_ROOT="${strict_tmp}" "${VALIDATE_WORKFLOWS}"
rm -rf "${strict_tmp}"

workflow_tmp="$(mktemp -d)"
write_minimal_workflow_root "${workflow_tmp}"
cp "${FIXTURE_DIR}/actionlint-invalid-workflow.yml" "${workflow_tmp}/.github/workflows/invalid.yml"
cat >"${workflow_tmp}/cloudnative-pg-timescaledb/scripts/valid.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' ok
EOF
expect_workflow_fail "invalid workflow syntax/action pinning" "actionlint|pinned|workflow YAML|top-level permissions" env VALIDATE_WORKFLOWS_ROOT="${workflow_tmp}" "${VALIDATE_WORKFLOWS}"
rm -rf "${workflow_tmp}"

printf 'PASS story-5.7 docs validation fixtures\n'
