#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RESOLVER="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/resolve-versions.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/packagecloud/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

expect_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    diag "test -f ${file}" "${file}" "packagecloud fixture exists" "missing" "Restore the Story 2.2 packagecloud fixture set."
    exit 1
  fi
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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid package resolver input fail deterministically."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Report command, artifact, expected package tuple, actual result, and remediation."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

write_metadata() {
  local target="$1"
  local pg_major="$2"
  local debian="$3"
  local platforms="$4"
  local publish="$5"
  local experimental="$6"
  local skip_reason="$7"
  python3 - "${target}" "${pg_major}" "${debian}" "${platforms}" "${publish}" "${experimental}" "${skip_reason}" <<'PY'
from pathlib import Path
import sys

target, pg_major, debian, platforms, publish, experimental, skip_reason = sys.argv[1:]
Path(target).write_text(f'''schema_version: "1"
image:
  registry: ghcr.io
  repository: pnetcloud/cloudnative-pg-timescaledb
  current_major: "18"
  primary_debian_variant: trixie
allowed:
  postgres_majors: ["17", "18", "19beta1"]
  debian_variants: ["trixie", "bookworm"]
  platforms: ["linux/amd64", "linux/arm64"]
entries:
  - pg_major: "{pg_major}"
    pg_version: "{pg_major}"
    debian_variant: {debian}
    cnpg_tag: "{pg_major}-standard-{debian}"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: [{platforms}]
    publish: {publish}
    experimental: {experimental}
    latest_eligible: false
    skip_reason: "{skip_reason}"
''')
PY
}

for fixture in \
  trixie-amd64-available.json \
  trixie-arm64-available.json \
  bookworm-amd64-available.json \
  bookworm-arm64-available.json \
  missing-timescaledb-trixie-amd64.json \
  missing-timescaledb-trixie-arm64.json \
  missing-timescaledb-bookworm-amd64.json \
  missing-timescaledb-bookworm-arm64.json \
  missing-toolkit-trixie-amd64.json \
  missing-toolkit-trixie-arm64.json \
  missing-toolkit-bookworm-amd64.json \
  missing-toolkit-bookworm-arm64.json \
  mismatched-timescaledb-version-amd64-arm64.json \
  mismatched-toolkit-version-amd64-arm64.json \
  missing-toolkit-nonpublish-skip.json \
  pg19beta1-cnpg-present-packages-missing.json \
  missing-arm64-package.json; do
  expect_file "${FIXTURE_DIR}/${fixture}"
done

"${RESOLVER}" --check-packages --fixtures "${FIXTURE_DIR}" >/tmp/story-2-2-positive.out

json_stdout="$(mktemp)"
json_stderr="$(mktemp)"
"${RESOLVER}" --check-packages --fixtures "${FIXTURE_DIR}" --json >"${json_stdout}" 2>"${json_stderr}"
if [[ -s "${json_stderr}" ]]; then
  diag "${RESOLVER} --check-packages --json" "stderr" "no human diagnostics on successful JSON output" "$(tr '\n' ' ' <"${json_stderr}")" "Keep JSON stdout clean for automation."
  rm -f "${json_stdout}" "${json_stderr}"
  exit 1
fi
python3 - "${json_stdout}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
required = {"pg_major", "debian_variant", "platforms", "timescaledb_version", "timescaledb_package_name", "timescaledb_package_version", "toolkit_version", "toolkit_package_name", "toolkit_package_version", "publish", "experimental", "skip_reason"}
entries = payload.get("entries")
if not isinstance(entries, list) or len(entries) != 6:
    raise SystemExit("expected six package resolver entries")
for entry in entries:
    if set(entry) != required:
        raise SystemExit(f"wrong package JSON keys: {sorted(entry)}")
    if entry["debian_variant"] not in {"trixie", "bookworm"}:
        raise SystemExit(f"unsupported Debian variant leaked into JSON: {entry}")
    if entry["timescaledb_package_name"] != f"timescaledb-2-postgresql-{entry['pg_major']}":
        raise SystemExit(f"wrong TimescaleDB package name: {entry}")
    if entry["toolkit_package_name"] != f"timescaledb-toolkit-postgresql-{entry['pg_major']}":
        raise SystemExit(f"wrong Toolkit package name: {entry}")
    if not entry["timescaledb_version"] or not entry["timescaledb_package_version"] or not entry["toolkit_version"] or not entry["toolkit_package_version"]:
        raise SystemExit(f"missing resolved package version: {entry}")
PY
rm -f "${json_stdout}" "${json_stderr}"

for tuple in \
  "timescaledb trixie linux/amd64 missing-timescaledb-trixie-amd64.json" \
  "timescaledb trixie linux/arm64 missing-timescaledb-trixie-arm64.json" \
  "timescaledb bookworm linux/amd64 missing-timescaledb-bookworm-amd64.json" \
  "timescaledb bookworm linux/arm64 missing-timescaledb-bookworm-arm64.json" \
  "toolkit trixie linux/amd64 missing-toolkit-trixie-amd64.json" \
  "toolkit trixie linux/arm64 missing-toolkit-trixie-arm64.json" \
  "toolkit bookworm linux/amd64 missing-toolkit-bookworm-amd64.json" \
  "toolkit bookworm linux/arm64 missing-toolkit-bookworm-arm64.json"; do
  read -r package_type debian platform fixture <<<"${tuple}"
  metadata="$(mktemp)"
  if [[ "${platform}" == "linux/arm64" ]]; then
    platforms="\"linux/arm64\", \"linux/amd64\""
  else
    platforms="\"linux/amd64\", \"linux/arm64\""
  fi
  write_metadata "${metadata}" "18" "${debian}" "${platforms}" "true" "false" ""
  expect_fail \
    "missing ${package_type} ${debian} ${platform}" \
    "pg_major=18 debian_variant=${debian} platform=${platform} package_type=${package_type}|missing package|Publishable rows require" \
    "${RESOLVER}" --check-packages --metadata "${metadata}" --fixture-file "${FIXTURE_DIR}/${fixture}"
  rm -f "${metadata}"
done

mismatch_metadata="$(mktemp)"
write_metadata "${mismatch_metadata}" "18" "trixie" "\"linux/amd64\", \"linux/arm64\"" "true" "false" ""
expect_fail "mismatched TimescaleDB package versions" "package_type=timescaledb|mismatched package versions|Choose one package version" \
  "${RESOLVER}" --check-packages --metadata "${mismatch_metadata}" --fixture-file "${FIXTURE_DIR}/mismatched-timescaledb-version-amd64-arm64.json"
expect_fail "mismatched Toolkit package versions" "package_type=toolkit|mismatched package versions|Choose one package version" \
  "${RESOLVER}" --check-packages --metadata "${mismatch_metadata}" --fixture-file "${FIXTURE_DIR}/mismatched-toolkit-version-amd64-arm64.json"
expect_fail "missing arm64 package" "platform=linux/arm64 package_type=timescaledb|missing package|Publishable rows require" \
  "${RESOLVER}" --check-packages --metadata "${mismatch_metadata}" --fixture-file "${FIXTURE_DIR}/missing-arm64-package.json"
rm -f "${mismatch_metadata}"

nonpublish_metadata="$(mktemp)"
write_metadata "${nonpublish_metadata}" "18" "trixie" "\"linux/amd64\", \"linux/arm64\"" "false" "false" "timescaledb-toolkit-postgresql-18 PostgreSQL 18 trixie linux/amd64 unsupported by upstream packagecloud fixture"
"${RESOLVER}" --check-packages --metadata "${nonpublish_metadata}" --fixture-file "${FIXTURE_DIR}/missing-toolkit-nonpublish-skip.json" >/tmp/story-2-2-nonpublish-toolkit.out
rm -f "${nonpublish_metadata}"

pg19_metadata="$(mktemp)"
write_metadata "${pg19_metadata}" "19beta1" "trixie" "\"linux/amd64\", \"linux/arm64\"" "false" "true" "timescaledb-2-postgresql-19beta1 timescaledb-toolkit-postgresql-19beta1 PostgreSQL 19beta1 trixie linux/amd64 linux/arm64 missing packages while CNPG exists"
"${RESOLVER}" --check-packages --metadata "${pg19_metadata}" --fixture-file "${FIXTURE_DIR}/pg19beta1-cnpg-present-packages-missing.json" >/tmp/story-2-2-pg19.out
rm -f "${pg19_metadata}"

missing_platform_metadata="$(mktemp)"
write_metadata "${missing_platform_metadata}" "18" "trixie" "\"linux/amd64\"" "true" "false" ""
expect_fail "publishable missing metadata platform" "platform=linux/amd64 package_type=all|linux/amd64 and linux/arm64|Publishable rows must check both" \
  "${RESOLVER}" --check-packages --metadata "${missing_platform_metadata}" --fixtures "${FIXTURE_DIR}"
rm -f "${missing_platform_metadata}"

expect_fail "missing option value" "command: resolve-versions --check-packages|artifact: arguments|expected: valid package resolver arguments|remediation:" \
  "${RESOLVER}" --check-packages --fixtures

printf 'PASS story-2.2 packagecloud resolver fixtures\n'
