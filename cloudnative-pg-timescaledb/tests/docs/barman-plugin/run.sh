#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures"
REQUIRED_PHRASE="CloudNativePG Barman Cloud Plugin"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

expect_fail() {
  local description="$1"
  local pattern="$2"
  local fixture="$3"
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${VALIDATOR}" "${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-barman-boundary ${fixture}" "${description}" "fixture fails" "passed" "Reject legacy in-image Barman guidance and package examples."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-barman-boundary ${fixture}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep Barman boundary diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  for required in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "validate-barman-boundary ${fixture}" "${description}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Use the standard validation diagnostic shape."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

for fixture in \
  valid-plugin-doc.md \
  legacy-barman-cloud-required.md \
  legacy-barman-cloud-instead-bypass.md \
  dockerfile-installs-barman-cloud \
  missing-plugin-phrase.md; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 3.6 fixture exists" "missing" "Restore the Barman plugin boundary fixture set."
    exit 1
  }
done

"${VALIDATOR}" "${FIXTURE_DIR}/valid-plugin-doc.md" >/tmp/story-3-6-valid-plugin-doc.out
grep -Fq 'PASS validate-barman-boundary plugin path gates' /tmp/story-3-6-valid-plugin-doc.out || {
  diag "validate-barman-boundary valid-plugin-doc.md" "${FIXTURE_DIR}/valid-plugin-doc.md" "PASS marker" "$(cat /tmp/story-3-6-valid-plugin-doc.out)" "Accept docs that use the plugin path and reject legacy in-image backup tooling."
  exit 1
}

"${VALIDATOR}" >/tmp/story-3-6-repo-scan.out
grep -Fq 'PASS validate-barman-boundary plugin path gates' /tmp/story-3-6-repo-scan.out || {
  diag "validate-barman-boundary" "repository scan" "PASS marker" "$(cat /tmp/story-3-6-repo-scan.out)" "Keep generated Dockerfiles and docs within the plugin boundary."
  exit 1
}

expect_fail "legacy doc requires in-image barman-cloud" "barman-cloud|${REQUIRED_PHRASE}" "${FIXTURE_DIR}/legacy-barman-cloud-required.md"
expect_fail "legacy doc cannot bypass with bare instead" "barman-cloud|${REQUIRED_PHRASE}" "${FIXTURE_DIR}/legacy-barman-cloud-instead-bypass.md"
expect_fail "Dockerfile installs barman-cloud" "barman-cloud|legacy Barman" "${FIXTURE_DIR}/dockerfile-installs-barman-cloud"
expect_fail "doc missing required plugin phrase" "${REQUIRED_PHRASE}" "${FIXTURE_DIR}/missing-plugin-phrase.md"

if rg -n 'plugin-barman-cloud|CloudNativePG Barman Cloud Plugin|manifest.yaml' "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/smoke-test.sh" "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke" >/tmp/story-3-6-smoke-plugin-scan.out; then
  diag "rg plugin deployment in smoke checks" "cloudnative-pg-timescaledb/scripts/smoke-test.sh cloudnative-pg-timescaledb/tests/smoke" "smoke checks do not deploy or validate the Barman plugin" "$(cat /tmp/story-3-6-smoke-plugin-scan.out)" "Keep smoke checks focused on database runtime and extension behavior."
  exit 1
fi

printf 'PASS story-3.6 Barman plugin boundary docs fixtures\n'
