#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-tags.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/tags/fixtures"
DATE="20260609"

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
  "${VALIDATOR}" --metadata "${file}" --date "${DATE}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "${VALIDATOR} --metadata ${file} --date ${DATE}" "${description}" "fixture fails" "passed" "Make invalid tag policy fail validation."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${VALIDATOR} --metadata ${file} --date ${DATE}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Make the fixture fail on its intended tag invariant."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

"${VALIDATOR}" --metadata "${FIXTURE_DIR}/valid-tags.yaml" --date "${DATE}" >/tmp/story-1-4-valid-tags.out

expect_fail "wrong latest on PG17" "latest only for non-experimental 18 trixie" "${FIXTURE_DIR}/wrong-latest-pg17.yaml"
expect_fail "missing latest on PG18 trixie" "PostgreSQL 18 trixie has latest_eligible true" "${FIXTURE_DIR}/missing-latest-pg18-trixie.yaml"
expect_fail "wrong latest on bookworm" "latest only for non-experimental 18 trixie" "${FIXTURE_DIR}/wrong-latest-bookworm.yaml"
expect_fail "wrong latest on PG19beta1" "latest only for non-experimental 18 trixie" "${FIXTURE_DIR}/wrong-latest-pg19beta1.yaml"
expect_fail "invalid bookworm suffix" "tags exactly generated policy tags" "${FIXTURE_DIR}/invalid-bookworm-suffix.yaml"
expect_fail "invalid immutable date" "tags exactly generated policy tags" "${FIXTURE_DIR}/invalid-immutable-date.yaml"
expect_fail "rolling major crosses PG major" "tags exactly generated policy tags" "${FIXTURE_DIR}/rolling-major-crosses-pg-major.yaml"
expect_fail "publish missing materialized tags" "tags is present for publishable rows" "${FIXTURE_DIR}/publish-true-missing-tags.yaml"
expect_fail "CNPG tag PostgreSQL mismatch" "cnpg_tag matches pg_version and debian_variant" "${FIXTURE_DIR}/invalid-cnpg-tag-pg-mismatch.yaml"
expect_fail "CNPG tag Debian mismatch" "cnpg_tag matches pg_version and debian_variant" "${FIXTURE_DIR}/invalid-cnpg-tag-debian-mismatch.yaml"
expect_fail "duplicate generated tag ownership" "exactly one image row owner" "${FIXTURE_DIR}/duplicate-tag-assignment.yaml"
expect_fail "invalid Docker tag character" "valid tag grammar" "${FIXTURE_DIR}/invalid-docker-tag-character.yaml"
expect_fail "Alpine unsupported" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/invalid-debian-variant-alpine.yaml"
expect_fail "bullseye unsupported" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/invalid-debian-variant-bullseye.yaml"
expect_fail "unsupported PostgreSQL line" "pg_major is one of" "${FIXTURE_DIR}/invalid-postgres-major.yaml"

tmp="$(mktemp)"
set +e
"${VALIDATOR}" --metadata "${FIXTURE_DIR}/valid-tags.yaml" --date 20261340 >"${tmp}" 2>&1
status="$?"
set -e
if [[ "${status}" == "0" ]] || ! grep -Eq 'valid UTC calendar date|UTC release date' "${tmp}"; then
  diag "${VALIDATOR} --metadata ${FIXTURE_DIR}/valid-tags.yaml --date 20261340" "invalid date argument" "calendar date fails" "exit ${status}: $(tr '\n' ' ' <"${tmp}")" "Reject invalid UTC YYYYMMDD inputs."
  rm -f "${tmp}"
  exit 1
fi
rm -f "${tmp}"

if ! grep -Fq 'validate-tags.sh' "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate.sh"; then
  diag "scan validate.sh" "cloudnative-pg-timescaledb/scripts/validate.sh" "make validate calls validate-tags.sh" "missing" "Wire tag validation into make validate."
  exit 1
fi
if ! grep -Fq 'TAG_VALIDATION_DATE="${TAG_VALIDATION_DATE:-${DATE:-20260609}}"' "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate.sh"; then
  diag "scan validate.sh" "cloudnative-pg-timescaledb/scripts/validate.sh" "make validate falls back from TAG_VALIDATION_DATE to DATE" "missing" "Keep update/generate/validate release date inputs aligned for automated immutable tags."
  exit 1
fi

printf 'PASS story-1.4 tag validation fixtures\n'
