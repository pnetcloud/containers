#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-metadata.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/metadata/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

expect_fail() {
  local description="$1"
  local pattern="$2"
  local file="$3"
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${VALIDATOR}" "${file}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "${VALIDATOR} ${file}" "${description}" "fixture fails" "passed" "Make invalid metadata fail validation."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${VALIDATOR} ${file}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Make the fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

"${VALIDATOR}" "${FIXTURE_DIR}/valid.yaml" >/tmp/story-1-3-valid.out

expect_fail "missing top-level key" "top-level keys exactly" "${FIXTURE_DIR}/missing-top-level-key.yaml"
expect_fail "wrong current major" "image.current_major" "${FIXTURE_DIR}/wrong-current-major.yaml"
expect_fail "wrong primary Debian" "image.primary_debian_variant" "${FIXTURE_DIR}/wrong-primary-debian-variant.yaml"
expect_fail "wrong allowed PostgreSQL majors" "allowed.postgres_majors" "${FIXTURE_DIR}/wrong-allowed-postgres-majors.yaml"
expect_fail "wrong allowed Debian variants" "allowed.debian_variants" "${FIXTURE_DIR}/wrong-allowed-debian-variants.yaml"
expect_fail "wrong allowed platforms" "allowed.platforms" "${FIXTURE_DIR}/wrong-allowed-platforms.yaml"
expect_fail "invalid field types" "is boolean|is non-empty list|is string" "${FIXTURE_DIR}/invalid-field-types.yaml"
expect_fail "pg version mismatch" "pg_version matches pg_major" "${FIXTURE_DIR}/invalid-pg-version-mismatch.yaml"
expect_fail "cnpg tag variant mismatch" "cnpg_tag matches pg_version and debian_variant" "${FIXTURE_DIR}/invalid-cnpg-tag-variant-mismatch.yaml"
expect_fail "duplicate row" "unique pg_major/debian_variant" "${FIXTURE_DIR}/duplicate-pg-debian-row.yaml"
expect_fail "missing matrix row" "matrix rows exactly" "${FIXTURE_DIR}/missing-required-pg-debian-row.yaml"
expect_fail "missing required field" "keys exactly" "${FIXTURE_DIR}/missing-required-field.yaml"
expect_fail "Alpine unsupported" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/invalid-debian-variant-alpine.yaml"
expect_fail "bullseye unsupported" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/invalid-debian-variant-bullseye.yaml"
expect_fail "non-Debian unsupported" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/invalid-debian-variant-non-debian.yaml"
expect_fail "old PostgreSQL major unsupported" "pg_major is one of" "${FIXTURE_DIR}/invalid-postgres-major.yaml"
expect_fail "plain PostgreSQL 19 unsupported" "pg_major is one of" "${FIXTURE_DIR}/invalid-postgres-major-19.yaml"
expect_fail "19beta1 unmarked" "19beta1 entries are experimental" "${FIXTURE_DIR}/unmarked-pg19beta1.yaml"
expect_fail "latest outside 18-trixie" "latest_eligible only" "${FIXTURE_DIR}/invalid-latest-eligible-not-18-trixie.yaml"
expect_fail "missing latest" "18-trixie has latest_eligible true|exactly one latest_eligible" "${FIXTURE_DIR}/invalid-latest-eligible-missing-18-trixie.yaml"
expect_fail "multiple latest" "latest_eligible only|exactly one latest_eligible" "${FIXTURE_DIR}/invalid-latest-eligible-multiple.yaml"
expect_fail "invalid platform" "platforms only" "${FIXTURE_DIR}/invalid-platform.yaml"
expect_fail "missing platforms" "non-empty list" "${FIXTURE_DIR}/missing-platforms.yaml"
expect_fail "publish missing required platform" "publishable entries.*platforms exactly" "${FIXTURE_DIR}/publish-true-missing-required-platform.yaml"
expect_fail "publish empty resolver-owned" "publishable entries have resolver-owned values" "${FIXTURE_DIR}/publish-true-empty-resolver-owned.yaml"
expect_fail "publish whitespace resolver-owned" "publishable entries have resolver-owned values" "${FIXTURE_DIR}/publish-true-whitespace-resolver-owned.yaml"
expect_fail "publish empty CNPG tag" "cnpg_tag matches pg_version and debian_variant|publishable entries have resolver-owned values" "${FIXTURE_DIR}/publish-true-empty-cnpg-tag.yaml"
expect_fail "publish false without skip" "non-published entries have non-empty skip_reason" "${FIXTURE_DIR}/publish-false-without-skip-reason.yaml"

if ! grep -Fq 'validate-metadata.sh' "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate.sh"; then
  diag "scan validate.sh" "cloudnative-pg-timescaledb/scripts/validate.sh" "make validate calls validate-metadata.sh" "missing" "Wire metadata validation into make validate."
  exit 1
fi

printf 'PASS story-1.3 metadata validation fixtures\n'
