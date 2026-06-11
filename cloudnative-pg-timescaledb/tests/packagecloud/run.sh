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
  shift
  local fragments=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    fragments+=("$1")
    shift
  done
  if [[ "$#" -eq 0 ]]; then
    diag "expect_fail ${description}" "test harness" "separator -- before command" "missing" "Pass required diagnostic fragments before -- and the command after it."
    exit 1
  fi
  shift
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
  local fragment
  for fragment in "${fragments[@]}"; do
    if ! grep -F -q "${fragment}" "${tmp}"; then
      diag "${*}" "${description}" "diagnostic contains ${fragment}" "$(tr '\n' ' ' <"${tmp}")" "Report command, artifact, expected package tuple, actual result, and remediation."
      rm -f "${tmp}"
      exit 1
    fi
  done
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
  invalid-pg19beta1-package-name.json \
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
required = {"pg_major", "pg_package_major", "debian_variant", "platforms", "timescaledb_version", "timescaledb_package_name", "timescaledb_package_version", "toolkit_version", "toolkit_package_name", "toolkit_package_version", "publish", "experimental", "skip_reason"}
entries = payload.get("entries")
if not isinstance(entries, list) or len(entries) != 6:
    raise SystemExit("expected six package resolver entries")
for entry in entries:
    if set(entry) != required:
        raise SystemExit(f"wrong package JSON keys: {sorted(entry)}")
    if entry["debian_variant"] not in {"trixie", "bookworm"}:
        raise SystemExit(f"unsupported Debian variant leaked into JSON: {entry}")
    expected_package_major = "19" if entry["pg_major"] == "19beta1" else entry["pg_major"]
    if entry["pg_package_major"] != expected_package_major:
        raise SystemExit(f"wrong package ABI major: {entry}")
    if entry["timescaledb_package_name"] != f"timescaledb-2-postgresql-{entry['pg_package_major']}":
        raise SystemExit(f"wrong TimescaleDB package name: {entry}")
    if entry["toolkit_package_name"] != f"timescaledb-toolkit-postgresql-{entry['pg_package_major']}":
        raise SystemExit(f"wrong Toolkit package name: {entry}")
    if entry["pg_major"] == "19beta1" and (entry["timescaledb_package_name"].endswith("19beta1") or entry["toolkit_package_name"].endswith("19beta1")):
        raise SystemExit(f"forbidden 19beta1 package name leaked into JSON: {entry}")
    if entry["publish"] and (not entry["timescaledb_version"] or not entry["timescaledb_package_version"] or not entry["toolkit_version"] or not entry["toolkit_package_version"]):
        raise SystemExit(f"missing resolved package version: {entry}")
expected_package_versions = {
    ("17", "trixie"): ("2.27.2~debian13-1710", "1:1.23.0~debian13"),
    ("18", "trixie"): ("2.27.2~debian13-1804", "1:1.23.0~debian13"),
    ("17", "bookworm"): ("2.27.2~debian12-1710", "1:1.23.0~debian12"),
    ("18", "bookworm"): ("2.27.2~debian12-1804", "1:1.23.0~debian12"),
}
for entry in entries:
    expected = expected_package_versions.get((entry["pg_major"], entry["debian_variant"]))
    if expected and (entry["timescaledb_package_version"], entry["toolkit_package_version"]) != expected:
        raise SystemExit(f"resolved package versions drifted from metadata fixture expectation: {entry}")
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
    "command: resolve-versions --check-packages" \
    "artifact: ${metadata}" \
    "pg_major=18 debian_variant=${debian} platform=${platform} package_type=${package_type}" \
    "missing package" \
    "Publishable rows require" \
    "--" \
    "${RESOLVER}" --check-packages --metadata "${metadata}" --fixture-file "${FIXTURE_DIR}/${fixture}"
  rm -f "${metadata}"
done

mismatch_metadata="$(mktemp)"
write_metadata "${mismatch_metadata}" "18" "trixie" "\"linux/amd64\", \"linux/arm64\"" "true" "false" ""
expect_fail "mismatched TimescaleDB package versions" \
  "command: resolve-versions --check-packages" \
  "artifact: ${mismatch_metadata}" \
  "package_type=timescaledb" \
  "mismatched package versions" \
  "Choose one package version" \
  "--" \
  "${RESOLVER}" --check-packages --metadata "${mismatch_metadata}" --fixture-file "${FIXTURE_DIR}/mismatched-timescaledb-version-amd64-arm64.json"
expect_fail "mismatched Toolkit package versions" \
  "command: resolve-versions --check-packages" \
  "artifact: ${mismatch_metadata}" \
  "package_type=toolkit" \
  "mismatched package versions" \
  "Choose one package version" \
  "--" \
  "${RESOLVER}" --check-packages --metadata "${mismatch_metadata}" --fixture-file "${FIXTURE_DIR}/mismatched-toolkit-version-amd64-arm64.json"
expect_fail "missing arm64 package" \
  "command: resolve-versions --check-packages" \
  "artifact: ${mismatch_metadata}" \
  "platform=linux/arm64 package_type=timescaledb" \
  "missing package" \
  "Publishable rows require" \
  "--" \
  "${RESOLVER}" --check-packages --metadata "${mismatch_metadata}" --fixture-file "${FIXTURE_DIR}/missing-arm64-package.json"
rm -f "${mismatch_metadata}"

nonpublish_metadata="$(mktemp)"
write_metadata "${nonpublish_metadata}" "18" "trixie" "\"linux/amd64\", \"linux/arm64\"" "false" "false" "timescaledb-toolkit-postgresql-18 PostgreSQL 18 trixie linux/amd64 linux/arm64 unsupported by upstream packagecloud fixture"
"${RESOLVER}" --check-packages --metadata "${nonpublish_metadata}" --fixture-file "${FIXTURE_DIR}/missing-toolkit-nonpublish-skip.json" >/tmp/story-2-2-nonpublish-toolkit.out
rm -f "${nonpublish_metadata}"

nonpublish_incomplete_metadata="$(mktemp)"
write_metadata "${nonpublish_incomplete_metadata}" "18" "trixie" "\"linux/amd64\", \"linux/arm64\"" "false" "false" "timescaledb-toolkit-postgresql-18 PostgreSQL 18 trixie linux/amd64 unsupported by upstream packagecloud fixture"
expect_fail "nonpublish skip reason missing arm64" \
  "command: resolve-versions --check-packages" \
  "artifact: ${nonpublish_incomplete_metadata}" \
  "platform=linux/arm64 package_type=toolkit" \
  "missing package" \
  "every missing platform" \
  "--" \
  "${RESOLVER}" --check-packages --metadata "${nonpublish_incomplete_metadata}" --fixture-file "${FIXTURE_DIR}/missing-toolkit-nonpublish-skip.json"
rm -f "${nonpublish_incomplete_metadata}"

resolver_managed_missing_metadata="$(mktemp)"
resolver_managed_json="$(mktemp)"
write_metadata "${resolver_managed_missing_metadata}" "18" "trixie" "\"linux/amd64\", \"linux/arm64\"" "false" "false" "resolver:old-reason: stale"
"${RESOLVER}" --check-packages --metadata "${resolver_managed_missing_metadata}" --fixture-file "${FIXTURE_DIR}/pg19beta1-cnpg-present-packages-missing.json" --preserve-manual-skip --json >"${resolver_managed_json}"
python3 - "${resolver_managed_json}" <<'PY'
import json
import sys
from pathlib import Path

entry = json.loads(Path(sys.argv[1]).read_text())["entries"][0]
reason = entry["skip_reason"]
required = [
    "timescaledb-2-postgresql-18 PostgreSQL 18 trixie linux/amd64 linux/arm64 missing packages while CNPG exists",
    "timescaledb-toolkit-postgresql-18 PostgreSQL 18 trixie linux/amd64 linux/arm64 missing packages while CNPG exists",
]
missing = [fragment for fragment in required if fragment not in reason]
if missing:
    raise SystemExit(f"resolver-managed skip_reason missed package evidence: {missing}; actual={reason!r}")
PY
rm -f "${resolver_managed_missing_metadata}" "${resolver_managed_json}"

pg19_metadata="$(mktemp)"
write_metadata "${pg19_metadata}" "19beta1" "trixie" "\"linux/amd64\", \"linux/arm64\"" "false" "true" "timescaledb-2-postgresql-19 timescaledb-toolkit-postgresql-19 PostgreSQL 19beta1 trixie linux/amd64 linux/arm64 missing packages while CNPG exists"
"${RESOLVER}" --check-packages --metadata "${pg19_metadata}" --fixture-file "${FIXTURE_DIR}/pg19beta1-cnpg-present-packages-missing.json" >/tmp/story-2-2-pg19.out
rm -f "${pg19_metadata}"

expect_fail "invalid pg19beta1 package name" \
  "command: resolve-versions --check-packages" \
  "artifact: ${FIXTURE_DIR}/invalid-pg19beta1-package-name.json" \
  "expected: package name timescaledb-2-postgresql-19" \
  "actual: timescaledb-2-postgresql-19beta1" \
  "Derive package names" \
  "--" \
  "${RESOLVER}" --check-packages --fixture-file "${FIXTURE_DIR}/invalid-pg19beta1-package-name.json"

pg19_bad_skip_metadata="$(mktemp)"
write_metadata "${pg19_bad_skip_metadata}" "19beta1" "trixie" "\"linux/amd64\", \"linux/arm64\"" "false" "true" "timescaledb-2-postgresql-19beta1 timescaledb-toolkit-postgresql-19beta1 PostgreSQL 19beta1 trixie linux/amd64 linux/arm64 missing packages while CNPG exists"
expect_fail "pg19beta1 skip reason does not satisfy package ABI 19" \
  "command: resolve-versions --check-packages" \
  "artifact: ${pg19_bad_skip_metadata}" \
  "expected=timescaledb-2-postgresql-19" \
  "skip_reason=" \
  "every missing platform" \
  "--" \
  "${RESOLVER}" --check-packages --metadata "${pg19_bad_skip_metadata}" --fixture-file "${FIXTURE_DIR}/pg19beta1-cnpg-present-packages-missing.json"
rm -f "${pg19_bad_skip_metadata}"

pg19_stable_metadata="$(mktemp)"
write_metadata "${pg19_stable_metadata}" "19" "trixie" "\"linux/amd64\", \"linux/arm64\"" "false" "true" "timescaledb-2-postgresql-19 PostgreSQL 19 trixie linux/amd64 linux/arm64 unsupported"
expect_fail "unsupported metadata pg_major 19" \
  "command: resolve-versions --check-packages" \
  "artifact: ${pg19_stable_metadata}" \
  "expected=pg_major in allowed.postgres_majors" \
  "actual: 19" \
  "derive package ABI major separately" \
  "--" \
  "${RESOLVER}" --check-packages --metadata "${pg19_stable_metadata}" --fixture-file "${FIXTURE_DIR}/pg19beta1-cnpg-present-packages-missing.json"
rm -f "${pg19_stable_metadata}"

missing_platform_metadata="$(mktemp)"
write_metadata "${missing_platform_metadata}" "18" "trixie" "\"linux/amd64\"" "true" "false" ""
expect_fail "publishable missing metadata platform" \
  "command: resolve-versions --check-packages" \
  "artifact: ${missing_platform_metadata}" \
  "platform=linux/amd64 package_type=all" \
  "linux/amd64 and linux/arm64" \
  "Publishable rows must check both" \
  "--" \
  "${RESOLVER}" --check-packages --metadata "${missing_platform_metadata}" --fixtures "${FIXTURE_DIR}"
rm -f "${missing_platform_metadata}"

expect_fail "missing option value" \
  "command: resolve-versions --check-packages" \
  "artifact: arguments" \
  "expected: valid package resolver arguments" \
  "remediation:" \
  "--" \
  "${RESOLVER}" --check-packages --fixtures

printf 'PASS story-2.2 packagecloud resolver fixtures\n'
