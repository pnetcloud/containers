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
  if ! grep -E -q -- "${pattern}" "${tmp}"; then
    diag "${VALIDATOR} --metadata ${file} --date ${DATE}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Make the fixture fail on its intended tag invariant."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

expect_arg_fail() {
  local description="$1"
  local pattern="$2"
  shift 2
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${VALIDATOR}" "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" != "64" ]]; then
    diag "${VALIDATOR} $*" "${description}" "exit 64" "exit ${status}: $(tr '\n' ' ' <"${tmp}")" "Use controlled argument diagnostics for invalid validate-tags usage."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q -- "${pattern}" "${tmp}"; then
    diag "${VALIDATOR} $*" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Print deterministic argument failure diagnostics."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

replace_line_fixture() {
  local output="$1"
  local pattern="$2"
  local replacement="$3"
  python3 - "${FIXTURE_DIR}/valid-tags.yaml" "${output}" "${pattern}" "${replacement}" <<'PY'
from pathlib import Path
import sys

source, output, pattern, replacement = sys.argv[1:]
lines = Path(source).read_text().splitlines()
replaced = False
result = []
for line in lines:
    if not replaced and pattern in line:
        result.append(replacement)
        replaced = True
    else:
        result.append(line)
if not replaced:
    raise SystemExit(f"failed to replace fixture line containing {pattern!r}")
Path(output).write_text("\n".join(result) + "\n")
PY
}

skipped_with_tags_fixture="$(mktemp)"
invalid_metadata_dir="$(mktemp -d)"
invalid_utf8_fixture="$(mktemp)"
trap 'rm -rf "${skipped_with_tags_fixture}" "${invalid_metadata_dir}" "${invalid_utf8_fixture}"' EXIT
replace_line_fixture "${skipped_with_tags_fixture}" "    publish: true" "    publish: false"
printf '\377\n' >"${invalid_utf8_fixture}"

"${VALIDATOR}" --metadata "${FIXTURE_DIR}/valid-tags.yaml" --date "${DATE}" >/dev/null

expect_arg_fail "metadata option missing value" "--metadata <path>" --metadata
expect_arg_fail "date option missing value" "--date <YYYYMMDD>" --metadata "${FIXTURE_DIR}/valid-tags.yaml" --date
expect_arg_fail "metadata option flag-as-value" "--metadata <path>" --metadata --date "${DATE}"

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
expect_fail "skipped row with tags" "tags only present on publishable rows" "${skipped_with_tags_fixture}"
expect_fail "metadata path is directory" "metadata file is a regular UTF-8 YAML file" "${invalid_metadata_dir}"
expect_fail "metadata path is invalid UTF-8" "metadata file is UTF-8 text" "${invalid_utf8_fixture}"
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
if ! grep -Fq "TAG_VALIDATION_DATE=\"\${TAG_VALIDATION_DATE:-\${DATE:-20260609}}\"" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate.sh"; then
  diag "scan validate.sh" "cloudnative-pg-timescaledb/scripts/validate.sh" "make validate falls back from TAG_VALIDATION_DATE to DATE" "missing" "Keep update/generate/validate release date inputs aligned for automated immutable tags."
  exit 1
fi

printf 'PASS story-1.4 tag validation fixtures\n'
