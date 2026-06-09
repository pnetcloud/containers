#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/fixtures"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

json_compare() {
  local description="$1"
  local fixture="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  "$@" >"${tmp}"
  python3 - "$fixture" "${tmp}" <<'PY'
import json
import sys
from pathlib import Path
expected = json.loads(Path(sys.argv[1]).read_text())
actual = json.loads(Path(sys.argv[2]).read_text())
if actual != expected:
    raise SystemExit(f"expected {sys.argv[1]} but got {actual!r}")
PY
  rm -f "${tmp}"
}

schema_check() {
  local kind="$1"
  local fixture="$2"
  python3 - "$kind" "$fixture" <<'PY'
import json
import sys
from pathlib import Path

kind = sys.argv[1]
path = Path(sys.argv[2])
payload = json.loads(path.read_text())
command = f"validate-generator-schema {kind} {path}"

def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )

def require_keys(obj, keys, label):
    missing = sorted(set(keys) - set(obj))
    if missing:
        fail(f"{label} keys include {sorted(keys)}", f"missing {missing} in {obj!r}", "Preserve the documented generator JSON schema; consumers must reject missing keys.")

def latest_rows_from_matrix(rows):
    return [(row["pg_major"], row["debian_variant"]) for row in rows if row["latest_eligible"]]

expected_rows = [("17", "trixie"), ("18", "trixie"), ("19beta1", "trixie"), ("17", "bookworm"), ("18", "bookworm"), ("19beta1", "bookworm")]

def require_exact_rows(actual, label):
    if actual != expected_rows:
        fail(f"{label} rows exactly {expected_rows}", repr(actual), "Preserve the full PostgreSQL/Debian generator contract without missing or duplicate rows.")

if kind == "dockerfiles":
    require_keys(payload, {"dockerfiles"}, "dockerfiles payload")
    rows = []
    for row in payload["dockerfiles"]:
        require_keys(row, {"pg_major", "debian_variant", "dockerfile", "skipped_marker", "base_image", "source_entry", "publish", "experimental", "skip_reason"}, "dockerfiles row")
        if row["publish"]:
            if not row["dockerfile"] or row["skipped_marker"] or not row["base_image"]:
                fail("publishable dockerfile rows have dockerfile/base_image and no skipped marker", repr(row), "Buildable Dockerfiles must be explicit only for publishable entries.")
        else:
            if row["dockerfile"] or not row["skipped_marker"] or row["base_image"]:
                fail("skipped dockerfile rows have skipped_marker and no dockerfile/base_image", repr(row), "Skipped entries must not expose buildable Dockerfiles.")
        rows.append((row["pg_major"], row["debian_variant"]))
    require_exact_rows(rows, "dockerfiles")
elif kind == "bake":
    require_keys(payload, {"bake_file", "targets", "skipped"}, "bake payload")
    rows = []
    for row in payload["targets"]:
        require_keys(row, {"name", "context", "dockerfile", "platforms", "publish", "experimental"}, "bake target")
        match = __import__("re").fullmatch(r"pg(.+)-(trixie|bookworm)", row["name"])
        if not match:
            fail("bake target names encode pg/debian row", repr(row["name"]), "Use pg<major>-<debian> target names from metadata.")
        if row["context"] != ".":
            fail("bake target context is checkout/path context", repr(row["context"]), "Use local checkout context instead of Docker Buildx default Git context.")
        if row["publish"] is not True:
            fail("bake target rows are publishable", repr(row), "Only publishable metadata rows should become buildable Bake targets.")
        rows.append((match.group(1), match.group(2)))
    skipped_rows = []
    for row in payload["skipped"]:
        require_keys(row, {"pg_major", "debian_variant", "name", "dockerfile", "publish", "experimental", "skip_reason"}, "bake skipped row")
        if row["publish"] is not False:
            fail("bake skipped rows are non-publishable", repr(row), "Do not let skipped combinations become publishable Bake targets.")
        if not row["skip_reason"]:
            fail("bake skipped rows carry skip_reason", repr(row), "Preserve clear diagnostics for skipped combinations.")
        skipped_rows.append((row["pg_major"], row["debian_variant"]))
    require_exact_rows(rows + skipped_rows, "bake target plus skipped")
elif kind == "matrix":
    require_keys(payload, {"include", "skipped"}, "matrix payload")
    rows = []
    for row in payload["include"]:
        require_keys(row, {"pg_major", "pg_version", "debian_variant", "image", "candidate_ref", "digest", "platforms", "bake_target", "dockerfile", "intended_tags", "publish", "experimental", "latest_eligible", "scan_result", "sbom_ref", "provenance_ref", "signature_ref"}, "matrix include row")
        if row["publish"] is not True:
            fail("matrix include rows are publishable", repr(row), "Only publishable metadata rows should become build matrix rows.")
        if not row["dockerfile"] or not row["bake_target"] or not row["candidate_ref"] or not row["intended_tags"]:
            fail("publishable matrix rows expose release inputs", repr(row), "Build matrix rows must expose Dockerfile, Bake target, candidate ref, and intended tags.")
        rows.append((row["pg_major"], row["debian_variant"]))
    for row in payload["skipped"]:
        require_keys(row, {"pg_major", "pg_version", "debian_variant", "platforms", "publish", "experimental", "latest_eligible", "skip_reason"}, "matrix skipped row")
        if row["publish"] is not False or not row["skip_reason"]:
            fail("matrix skipped rows are non-publishable with skip_reason", repr(row), "Skipped matrix rows must remain summaries only.")
        rows.append((row["pg_major"], row["debian_variant"]))
    latest = latest_rows_from_matrix(payload["include"])
    if latest and latest != [("18", "trixie")]:
        fail("matrix latest_eligible exactly 18-trixie when publishable latest is present", repr(latest), "Preserve latest eligibility from metadata without recomputing it downstream.")
    require_exact_rows(rows, "matrix include plus skipped")
elif kind == "catalog":
    require_keys(payload, {"catalogs"}, "catalog payload")
    latest = []
    catalog_variants = []
    catalog_rows_by_variant = {}
    for catalog in payload["catalogs"]:
        require_keys(catalog, {"debian_variant", "catalog_path", "entries"}, "catalog row")
        catalog_variants.append(catalog["debian_variant"])
        catalog_rows = []
        for row in catalog["entries"]:
            require_keys(row, {"pg_major", "image", "digest", "publish", "experimental", "latest_eligible", "skip_reason"}, "catalog entry")
            catalog_rows.append((row["pg_major"], catalog["debian_variant"]))
            if row["latest_eligible"]:
                latest.append((row["pg_major"], catalog["debian_variant"]))
        catalog_rows_by_variant[catalog["debian_variant"]] = catalog_rows
    if latest != [("18", "trixie")]:
        fail("catalog latest_eligible exactly 18-trixie", repr(latest), "Preserve latest eligibility from metadata without recomputing it downstream.")
    if catalog_variants != ["trixie", "bookworm"]:
        fail("catalog variants exactly trixie and bookworm", repr(catalog_variants), "Generate one catalog skeleton per supported Debian variant.")
    for variant, rows in catalog_rows_by_variant.items():
        expected_catalog_rows = [(pg, variant) for pg in ["17", "18", "19beta1"]]
        if rows != expected_catalog_rows:
            fail(f"catalog {variant} rows exactly {expected_catalog_rows}", repr(rows), "Preserve every PostgreSQL row in each Debian catalog skeleton.")
elif kind == "docs":
    require_keys(payload, {"docs"}, "docs payload")
    if len(payload["docs"]) != 1:
        fail("docs payload has exactly one compatibility doc row", repr(payload["docs"]), "Keep Story 1.5 docs contract scoped to compatibility skeleton output.")
    for row in payload["docs"]:
        require_keys(row, {"doc_path", "source", "sections", "publishable_entries", "experimental_entries"}, "docs row")
        if row["sections"] != ["compatibility"]:
            fail("docs sections exactly compatibility", repr(row["sections"]), "Preserve the documented generated docs contract.")
else:
    fail("known generator kind", kind, "Use a documented generator schema kind.")
PY
}

expect_schema_fail() {
  local description="$1"
  local kind="$2"
  local fixture="$3"
  local pattern="$4"
  local tmp status
  tmp="$(mktemp)"
  set +e
  schema_check "${kind}" "${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-generator-schema ${kind} ${fixture}" "${description}" "fixture fails" "passed" "Make malformed generator JSON fail schema validation."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-generator-schema ${kind} ${fixture}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Make the fixture fail on its intended schema invariant."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

expect_command_fail() {
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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid generator command usage fail deterministically."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Make command fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

assert_json_field() {
  local description="$1"
  local expected="$2"
  shift 2
  local tmp actual
  tmp="$(mktemp)"
  "$@" >"${tmp}"
  actual="$(python3 - "$tmp" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
if "bake_file" in payload:
    print(payload["bake_file"])
else:
    print(payload["docs"][0]["doc_path"])
PY
)"
  if [[ "${actual}" != "${expected}" ]]; then
    diag "${*}" "${description}" "json artifact path ${expected}" "${actual}" "Reflect --output in machine JSON summaries."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

make -C "${ROOT_DIR}" generate >/tmp/story-1-5-generate.out

"${SCRIPT_DIR}/generate-dockerfiles.sh" --check
"${SCRIPT_DIR}/generate-bake.sh" --check
"${SCRIPT_DIR}/generate-matrix.sh" --check
"${SCRIPT_DIR}/generate-catalog.sh" --check
"${SCRIPT_DIR}/generate-docs.sh" --check

expect_command_fail "dockerfiles check-json detects missing output root" "committed output matches generated content" "${SCRIPT_DIR}/generate-dockerfiles.sh" --output /tmp/story-1-5-missing-generated --check --json
expect_command_fail "matrix check-json detects missing output" "committed output matches generated content" "${SCRIPT_DIR}/generate-matrix.sh" --output /tmp/story-1-5-missing-matrix.json --check --json

assert_json_field "bake output json path" "/tmp/story-1-5-custom-bake.hcl" "${SCRIPT_DIR}/generate-bake.sh" --output /tmp/story-1-5-custom-bake.hcl --json
assert_json_field "docs output json path" "/tmp/story-1-5-custom-compatibility.md" "${SCRIPT_DIR}/generate-docs.sh" --output /tmp/story-1-5-custom-compatibility.md --json

json_compare "dockerfiles json" "${FIXTURE_DIR}/generate-dockerfiles-valid.json" "${SCRIPT_DIR}/generate-dockerfiles.sh" --json
json_compare "bake json" "${FIXTURE_DIR}/generate-bake-valid.json" "${SCRIPT_DIR}/generate-bake.sh" --json
json_compare "matrix json" "${FIXTURE_DIR}/generate-matrix-valid.json" "${SCRIPT_DIR}/generate-matrix.sh" --json
json_compare "catalog json" "${FIXTURE_DIR}/generate-catalog-valid.json" "${SCRIPT_DIR}/generate-catalog.sh" --json
json_compare "docs json" "${FIXTURE_DIR}/generate-docs-valid.json" "${SCRIPT_DIR}/generate-docs.sh" --json

schema_check dockerfiles "${FIXTURE_DIR}/generate-dockerfiles-valid.json"
schema_check bake "${FIXTURE_DIR}/generate-bake-valid.json"
schema_check matrix "${FIXTURE_DIR}/generate-matrix-valid.json"
schema_check catalog "${FIXTURE_DIR}/generate-catalog-valid.json"
schema_check docs "${FIXTURE_DIR}/generate-docs-valid.json"

expect_schema_fail "dockerfiles missing dockerfile" dockerfiles "${FIXTURE_DIR}/generate-dockerfiles-missing-dockerfile.json" "missing.*dockerfile"
expect_schema_fail "dockerfiles missing matrix row" dockerfiles "${FIXTURE_DIR}/generate-dockerfiles-missing-row.json" "rows exactly"
expect_schema_fail "bake missing target name" bake "${FIXTURE_DIR}/generate-bake-missing-target.json" "missing.*name"
expect_schema_fail "matrix missing include key" matrix "${FIXTURE_DIR}/generate-matrix-missing-include-key.json" "missing.*digest"
expect_schema_fail "matrix duplicate row" matrix "${FIXTURE_DIR}/generate-matrix-duplicate-row.json" "rows exactly"
expect_schema_fail "matrix wrong latest" matrix "${FIXTURE_DIR}/generate-matrix-wrong-latest-eligible.json" "latest_eligible exactly 18-trixie"
expect_schema_fail "catalog missing catalog path" catalog "${FIXTURE_DIR}/generate-catalog-missing-catalog-path.json" "missing.*catalog_path"
expect_schema_fail "catalog missing variant" catalog "${FIXTURE_DIR}/generate-catalog-missing-variant.json" "catalog variants exactly"
expect_schema_fail "catalog wrong latest" catalog "${FIXTURE_DIR}/generate-catalog-wrong-latest-eligible.json" "latest_eligible exactly 18-trixie"
expect_schema_fail "docs missing doc path" docs "${FIXTURE_DIR}/generate-docs-missing-doc-path.json" "missing.*doc_path"

printf 'PASS story-1.5 generator contracts\n'
