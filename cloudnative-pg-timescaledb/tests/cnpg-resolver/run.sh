#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RESOLVER="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/resolve-versions.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

expect_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    diag "test -f ${file}" "${file}" "CNPG resolver fixture exists" "missing" "Restore the Story 2.1 fixture set."
    exit 1
  fi
}

expect_fail() {
  local description="$1"
  shift
  local patterns=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    patterns+=("$1")
    shift
  done
  if [[ "$#" -eq 0 ]]; then
    diag "expect_fail" "${description}" "pattern list is followed by -- and command" "missing --" "Keep CNPG negative test calls explicit."
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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid CNPG resolver input fail deterministically."
    rm -f "${tmp}"
    exit 1
  fi
  local pattern
  for pattern in "${patterns[@]}"; do
    if ! grep -F -q "${pattern}" "${tmp}"; then
      diag "${*}" "${description}" "diagnostic contains ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Report command, artifact, expected upstream reference, actual result, and remediation."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

for fixture in \
  standard-trixie-valid.json \
  standard-bookworm-valid.json \
  system-flavor-deprecated.json \
  missing-platform-arm64.json \
  unavailable-nonpublish-pg19beta1.json \
  unavailable-publishable.yaml; do
  expect_file "${FIXTURE_DIR}/${fixture}"
done

fixture_metadata="$(mktemp)"
python3 - "${fixture_metadata}" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text('''schema_version: "1"
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
  - pg_major: "17"
    pg_version: "17.10"
    debian_variant: trixie
    cnpg_tag: "17.10-standard-trixie"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: false
    latest_eligible: false
    skip_reason: "fixture non-publish row"
  - pg_major: "18"
    pg_version: "18.4"
    debian_variant: trixie
    cnpg_tag: "18.4-standard-trixie"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: false
    latest_eligible: true
    skip_reason: "fixture non-publish row"
  - pg_major: "19beta1"
    pg_version: "19beta1"
    debian_variant: trixie
    cnpg_tag: "19beta1-standard-trixie"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: true
    latest_eligible: false
    skip_reason: "fixture non-publish row"
  - pg_major: "17"
    pg_version: "17.10"
    debian_variant: bookworm
    cnpg_tag: "17.10-standard-bookworm"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: false
    latest_eligible: false
    skip_reason: "fixture non-publish row"
  - pg_major: "18"
    pg_version: "18.4"
    debian_variant: bookworm
    cnpg_tag: "18.4-standard-bookworm"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: false
    latest_eligible: false
    skip_reason: "fixture non-publish row"
  - pg_major: "19beta1"
    pg_version: "19beta1"
    debian_variant: bookworm
    cnpg_tag: "19beta1-standard-bookworm"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: true
    latest_eligible: false
    skip_reason: "fixture non-publish row"
''')
PY

"${RESOLVER}" --check-cnpg --metadata "${fixture_metadata}" --fixtures "${FIXTURE_DIR}" >/tmp/story-2-1-positive.out

json_output="$(mktemp)"
"${RESOLVER}" --check-cnpg --metadata "${fixture_metadata}" --fixtures "${FIXTURE_DIR}" --json >"${json_output}"
python3 - "${json_output}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
required = {"pg_major", "pg_version", "debian_variant", "cnpg_tag", "cnpg_digest", "platforms", "publish", "experimental", "skip_reason"}
entries = payload.get("entries")
if not isinstance(entries, list) or len(entries) != 6:
    raise SystemExit("expected six CNPG JSON entries")
for entry in entries:
    if set(entry) != required:
        raise SystemExit(f"wrong CNPG JSON keys: {sorted(entry)}")
    if entry["debian_variant"] not in {"trixie", "bookworm"}:
        raise SystemExit(f"unsupported Debian variant leaked into JSON: {entry}")
    if not entry["cnpg_tag"].endswith(f"standard-{entry['debian_variant']}"):
        raise SystemExit(f"non-standard CNPG tag leaked into JSON: {entry}")
    if not entry["cnpg_digest"].startswith("sha256:"):
        raise SystemExit(f"missing resolved digest in JSON: {entry}")
expected_versions = {
    ("17", "trixie"): ("17.10", "17.10-standard-trixie"),
    ("18", "trixie"): ("18.4", "18.4-standard-trixie"),
    ("19beta1", "trixie"): ("19beta1", "19beta1-standard-trixie"),
    ("17", "bookworm"): ("17.10", "17.10-standard-bookworm"),
    ("18", "bookworm"): ("18.4", "18.4-standard-bookworm"),
    ("19beta1", "bookworm"): ("19beta1", "19beta1-standard-bookworm"),
}
for entry in entries:
    expected_version, expected_tag = expected_versions[(entry["pg_major"], entry["debian_variant"])]
    if entry["pg_version"] != expected_version or entry["cnpg_tag"] != expected_tag:
        raise SystemExit(f"wrong resolved CNPG version/tag: {entry}")
PY
rm -f "${json_output}"

newer_minor_fixture="$(mktemp)"
python3 - "${newer_minor_fixture}" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('''{"manifests":[{"tag":"18.5-standard-trixie","digest":"sha256:5555555555555555555555555555555555555555555555555555555555555555","platforms":["linux/amd64","linux/arm64"]}]}
''')
PY
exact_json="$(mktemp)"
"${RESOLVER}" --check-cnpg --metadata "${fixture_metadata}" --fixtures "${FIXTURE_DIR}" --fixture-file "${newer_minor_fixture}" --json >"${exact_json}"
python3 - "${exact_json}" <<'PY'
import json
import sys
from pathlib import Path

entries = json.loads(Path(sys.argv[1]).read_text())["entries"]
entry = next(item for item in entries if item["pg_major"] == "18" and item["debian_variant"] == "trixie")
if entry["cnpg_tag"] != "18.4-standard-trixie":
    raise SystemExit(f"exact pg_version must keep exact CNPG tag, got {entry}")
if entry["cnpg_digest"] == "sha256:5555555555555555555555555555555555555555555555555555555555555555":
    raise SystemExit(f"exact pg_version used digest from newer minor: {entry}")
PY
rm -f "${newer_minor_fixture}" "${exact_json}"

expect_fail \
  "deprecated system flavor" \
  "command: resolve-versions --check-cnpg" \
  "artifact:" \
  "expected: pg_major=18 debian_variant=trixie platform=all expected upstream reference=ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie" \
  "actual: deprecated system flavor available instead" \
  "18.4-system-trixie" \
  "remediation: Reject system-*" \
  -- \
  "${RESOLVER}" --check-cnpg --metadata "${fixture_metadata}" --fixture-file "${FIXTURE_DIR}/system-flavor-deprecated.json"

publishable_fixture_metadata="$(mktemp)"
python3 - "${publishable_fixture_metadata}" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text('''schema_version: "1"
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
  - pg_major: "18"
    pg_version: "18.4"
    debian_variant: trixie
    cnpg_tag: "18.4-standard-trixie"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: true
    experimental: false
    latest_eligible: true
    skip_reason: ""
''')
PY
expect_fail \
  "missing arm64 platform" \
  "command: resolve-versions --check-cnpg" \
  "artifact:" \
  "expected: pg_major=18 debian_variant=trixie platform=linux/arm64 expected upstream reference=ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie" \
  "actual: missing platform linux/arm64" \
  "remediation: Publishable rows require all metadata platforms" \
  -- \
  "${RESOLVER}" --check-cnpg --metadata "${publishable_fixture_metadata}" --fixture-file "${FIXTURE_DIR}/missing-platform-arm64.json"

rm -f "${fixture_metadata}" "${publishable_fixture_metadata}"

partial_nonpublish_metadata="$(mktemp)"
python3 - "${partial_nonpublish_metadata}" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text('''schema_version: "1"
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
  - pg_major: "18"
    pg_version: "18"
    debian_variant: trixie
    cnpg_tag: "18-standard-trixie"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: false
    latest_eligible: true
    skip_reason: "ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie missing platform linux/arm64 upstream manifest incomplete"
''')
PY
partial_json="$(mktemp)"
"${RESOLVER}" --check-cnpg --metadata "${partial_nonpublish_metadata}" --fixture-file "${FIXTURE_DIR}/missing-platform-arm64.json" --json >"${partial_json}"
python3 - "${partial_json}" <<'PY'
import json
import sys
from pathlib import Path

entry = json.loads(Path(sys.argv[1]).read_text())["entries"][0]
if entry["cnpg_digest"] != "":
    raise SystemExit(f"partial platform manifest must not emit cnpg_digest: {entry}")
PY
rm -f "${partial_json}" "${partial_nonpublish_metadata}"

nonpublish_metadata="$(mktemp)"
python3 - "${nonpublish_metadata}" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text('''schema_version: "1"
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
  - pg_major: "19beta1"
    pg_version: "19beta1"
    debian_variant: trixie
    cnpg_tag: "19beta1-standard-trixie"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: true
    latest_eligible: false
    skip_reason: "ghcr.io/cloudnative-pg/postgresql:19beta1-standard-trixie missing tag upstream unavailable for experimental PostgreSQL 19beta1"
''')
PY
"${RESOLVER}" --check-cnpg --metadata "${nonpublish_metadata}" --fixture-file "${FIXTURE_DIR}/unavailable-nonpublish-pg19beta1.json" >/tmp/story-2-1-nonpublish.out
rm -f "${nonpublish_metadata}"

empty_inventory="$(mktemp)"
python3 - "${empty_inventory}" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('{"manifests": []}\n')
PY
expect_fail \
  "unavailable publishable base" \
  "command: resolve-versions --check-cnpg" \
  "artifact:" \
  "expected: pg_major=18 debian_variant=trixie platform=all expected upstream reference=ghcr.io/cloudnative-pg/postgresql:18-standard-trixie" \
  "actual: missing tag" \
  "remediation: Publishable rows require an available standard-* CNPG base image tag." \
  -- \
  "${RESOLVER}" --check-cnpg --metadata "${FIXTURE_DIR}/unavailable-publishable.yaml" --fixture-file "${empty_inventory}"
rm -f "${empty_inventory}"

wrong_repo_inventory="$(mktemp)"
python3 - "${wrong_repo_inventory}" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('{"manifests": [{"reference": "ghcr.io/other/postgresql:18.4-standard-trixie", "digest": "sha256:9999999999999999999999999999999999999999999999999999999999999999", "platforms": ["linux/amd64", "linux/arm64"]}]}\n')
PY
expect_fail \
  "wrong upstream repository" \
  "command: resolve-versions --check-cnpg" \
  "expected: fixture manifest reference starts with ghcr.io/cloudnative-pg/postgresql:" \
  "actual: ghcr.io/other/postgresql:18.4-standard-trixie" \
  "remediation: Resolve only ghcr.io/cloudnative-pg/postgresql base images." \
  -- \
  "${RESOLVER}" --check-cnpg --fixture-file "${wrong_repo_inventory}"
rm -f "${wrong_repo_inventory}"

expect_fail \
  "missing option value" \
  "command: resolve-versions --check-cnpg" \
  "artifact: arguments" \
  "expected: valid resolver arguments" \
  "remediation: Pass required option values" \
  -- \
  "${RESOLVER}" --check-cnpg --metadata

printf 'PASS story-2.1 CNPG resolver fixtures\n'
