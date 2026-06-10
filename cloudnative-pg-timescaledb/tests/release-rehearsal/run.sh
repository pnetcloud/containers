#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/release-rehearsal.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures"
REPORT="${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

require_fixture() {
  local name="$1"
  if [[ ! -f "${FIXTURE_DIR}/${name}" ]]; then
    diag "test -f" "${FIXTURE_DIR}/${name}" "fixture exists" "missing" "Restore the Story 5.9 release rehearsal fixture."
    exit 1
  fi
}

expect_pass() {
  local fixture="$1"
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${SCRIPT}" --dry-run --date 20260609 --fixture "${FIXTURE_DIR}/${fixture}" --no-report >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" != "0" ]]; then
    diag "release-rehearsal ${fixture}" "positive fixture passes" "exit 0" "exit ${status}: $(tr '\n' ' ' <"${tmp}")" "Keep positive release rehearsal evidence complete and aligned."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -Fq 'PASS release-rehearsal date=20260609' "${tmp}"; then
    diag "release-rehearsal ${fixture}" "positive fixture emits PASS marker" "PASS marker" "$(cat "${tmp}")" "Keep release rehearsal output machine-readable."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

expect_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${SCRIPT}" --dry-run --date 20260609 --fixture "${FIXTURE_DIR}/${fixture}" --expect-failure >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "release-rehearsal ${fixture}" "negative fixture fails" "non-zero" "exit 0" "Make the fixture break its intended release gate."
    rm -f "${tmp}"
    exit 1
  fi
  for token in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${token}" "${tmp}"; then
      diag "release-rehearsal ${fixture}" "diagnostic includes ${token}" "present" "$(cat "${tmp}")" "Keep release rehearsal diagnostics deterministic and actionable."
      rm -f "${tmp}"
      exit 1
    fi
  done
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "release-rehearsal ${fixture}" "diagnostic matches ${pattern}" "match" "$(tr '\n' ' ' <"${tmp}")" "Fail on the intended release-blocking condition."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

positive_fixtures=(
  valid-full-matrix.json
  no-op-update.json
  changed-update-autocommit.json
)

negative_fixtures=(
  missing-publishable-pg-debian-platform.json
  missing-smoke-result.json
  missing-sbom.json
  missing-provenance.json
  missing-signature.json
  vulnerability-threshold-failed.json
  scan-wrong-digest.json
  sbom-wrong-digest.json
  provenance-wrong-digest.json
  signature-wrong-digest.json
  wrong-latest.json
  latest-not-pg18-trixie.json
  stale-generated-files.json
  unpublished-catalog-reference.json
  secret-in-summary.json
  secret-in-command.json
  secret-in-workflow-url.json
  secret-in-candidate-metadata.json
  pg19beta1-promoted-to-latest.json
  vendor-used-as-build-context.json
  vendor-used-as-runtime-input.json
  vendor-exact-build-context.json
  vendor-dot-build-context.json
  vendor-absolute-runtime-input.json
  alpine-release-candidate.json
  bullseye-release-candidate.json
  unsupported-debian-variant.json
  missing-workflow-dispatch-evidence.json
)

for fixture in "${positive_fixtures[@]}" "${negative_fixtures[@]}"; do
  require_fixture "${fixture}"
done

for fixture in "${positive_fixtures[@]}"; do
  expect_pass "${fixture}"
done

expect_fail missing-publishable-pg-debian-platform.json 'matrix enumerates every supported PostgreSQL/Debian combination|17-trixie'
expect_fail missing-smoke-result.json 'smoke_sql|every platform evidence row passed'
expect_fail missing-sbom.json 'sbom|SBOM'
expect_fail missing-provenance.json 'provenance'
expect_fail missing-signature.json 'signature'
expect_fail vulnerability-threshold-failed.json 'vulnerability threshold gate passed'
expect_fail scan-wrong-digest.json 'vulnerability scan is bound to the candidate index digest'
expect_fail sbom-wrong-digest.json 'sbom evidence is bound to the candidate index digest'
expect_fail provenance-wrong-digest.json 'provenance evidence is bound to the candidate index digest'
expect_fail signature-wrong-digest.json 'signature evidence is bound to the candidate index digest'
expect_fail wrong-latest.json 'latest resolves to 18-trixie'
expect_fail latest-not-pg18-trixie.json 'latest resolves to 18-trixie'
expect_fail stale-generated-files.json 'generated files are fresh'
expect_fail unpublished-catalog-reference.json 'referenced in its catalog'
expect_fail secret-in-summary.json 'no secrets'
expect_fail secret-in-command.json 'no secrets|secret_locations'
expect_fail secret-in-workflow-url.json 'no secrets|secret_locations'
expect_fail secret-in-candidate-metadata.json 'no secrets|secret_locations'
expect_fail pg19beta1-promoted-to-latest.json 'latest resolves to 18-trixie|experimental PG19beta1'
expect_fail vendor-used-as-build-context.json 'build context excludes reference-only tree'
expect_fail vendor-used-as-runtime-input.json 'runtime inputs exclude reference-only tree'
expect_fail vendor-exact-build-context.json 'build context excludes reference-only tree'
expect_fail vendor-dot-build-context.json 'build context excludes reference-only tree'
expect_fail vendor-absolute-runtime-input.json 'runtime inputs exclude reference-only tree'
expect_fail alpine-release-candidate.json 'Alpine release candidates are blocked'
expect_fail bullseye-release-candidate.json 'bullseye release candidates are blocked'
expect_fail unsupported-debian-variant.json 'Debian variant is trixie or bookworm'
expect_fail missing-workflow-dispatch-evidence.json 'workflow_dispatch.url|actual release-rehearsal.yml workflow run URL'

"${SCRIPT}" --dry-run --date 20260609 --fixture "${FIXTURE_DIR}/valid-full-matrix.json" --report "${REPORT}" >/tmp/story-5-9-report.out

for token in \
  '# Release Rehearsal Report' \
  'UTC date: `20260609`' \
  'Expected target: `18-trixie`' \
  'Actual target: `18-trixie`' \
  'sha256:4444444444444444444444444444444444444444444444444444444444444444' \
  'cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml' \
  'cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml' \
  'https://github.com/pnetcloud/containers/actions/runs/1234567890' \
  'make release-rehearsal DATE=20260609 DRY_RUN=1'; do
  if ! grep -Fq "${token}" "${REPORT}"; then
    diag "grep ${token}" "${REPORT}" "report includes ${token}" "missing" "Regenerate the release rehearsal report from the valid fixture."
    exit 1
  fi
done

printf 'PASS story-5.9 release rehearsal fixtures\n'
