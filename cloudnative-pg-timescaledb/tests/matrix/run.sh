#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-matrix.sh"
VALIDATE_MATRIX_JSON="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-matrix-json.py"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/matrix/fixtures"
PUBLISHABLE_METADATA="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/fixtures/metadata/valid-publishable-targets.yaml"
WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

validate_matrix() {
  local file="$1"
  python3 - "${file}" <<'PY'
from pathlib import Path
import json
import sys

path = Path(sys.argv[1])
command = f"validate matrix fixture {path}"
required_include = {
    "pg_major", "pg_version", "debian_variant", "image", "candidate_ref", "digest",
    "platforms", "bake_target", "dockerfile", "intended_tags", "publish", "experimental",
    "latest_eligible", "scan_result", "sbom_ref", "provenance_ref", "signature_ref",
}
required_skipped = {"pg_major", "pg_version", "debian_variant", "platforms", "publish", "experimental", "latest_eligible", "skip_reason"}

def fail(expected, actual, remediation):
    raise SystemExit(f"command: {command}\nartifact: {path}\nexpected: {expected}\nactual: {actual}\nremediation: {remediation}")

payload = json.loads(path.read_text())
if set(payload) != {"include", "skipped"}:
    fail("top-level keys exactly include and skipped", sorted(payload), "Emit the Story 4.1 matrix schema only.")
include = payload["include"]
skipped = payload["skipped"]
if not isinstance(include, list) or not isinstance(skipped, list):
    fail("include and skipped are arrays", {"include": type(include).__name__, "skipped": type(skipped).__name__}, "Use arrays for GitHub Actions matrix and summaries.")

latest_rows = []
for idx, row in enumerate(include):
    missing = sorted(required_include - set(row))
    extra = sorted(set(row) - required_include)
    if missing or extra:
        fail(f"include[{idx}] required keys", f"missing {missing}, extra {extra}", "Keep downstream workflow keys explicit; do not recompute release fields.")
    if row["publish"] is not True:
        fail(f"include[{idx}].publish is true", row["publish"], "Only publishable rows belong in include[].")
    if row["pg_major"] == "19beta1" and row["experimental"] is not True:
        fail("19beta1 include rows are experimental", row, "Keep PostgreSQL 19 preview rows experimental.")
    if row["latest_eligible"]:
        latest_rows.append((row["pg_major"], row["debian_variant"]))
        if (row["pg_major"], row["debian_variant"]) != ("18", "trixie") or row["experimental"]:
            fail("latest_eligible only for non-experimental 18 trixie", row, "Do not promote bookworm, PostgreSQL 17, or PostgreSQL 19 preview rows to latest.")
    if not row["intended_tags"] or not isinstance(row["intended_tags"], list):
        fail(f"include[{idx}].intended_tags is non-empty array", row["intended_tags"], "Use tag policy output from the generator.")
    immutable = [tag for tag in row["intended_tags"] if "-pg" in tag and "-ts" in tag]
    if not immutable or row["candidate_ref"] != f"{row['image']}:{immutable[0]}":
        fail(f"include[{idx}].candidate_ref uses immutable intended tag", row, "Use immutable tag-policy output for candidate_ref.")

if latest_rows and latest_rows != [("18", "trixie")]:
    fail("exactly one publishable latest row when latest is present", latest_rows, "Keep latest promotion on the primary trixie row only.")

for idx, row in enumerate(skipped):
    missing = sorted(required_skipped - set(row))
    if missing:
        fail(f"skipped[{idx}] required summary keys", f"missing {missing}", "Skipped rows must keep publish:false and skip_reason for summaries.")
    if row["publish"] is not False or not str(row["skip_reason"]).strip():
        fail(f"skipped[{idx}] publish false with skip_reason", row, "Keep skipped summary entries actionable.")
    if row["pg_major"] == "19beta1" and row["experimental"] is not True:
        fail("19beta1 skipped rows are experimental", row, "Keep PostgreSQL 19 preview rows experimental.")
PY
}

expect_matrix_fail() {
  local description="$1"
  local pattern="$2"
  local file="$3"
  local tmp status
  tmp="$(mktemp)"
  set +e
  validate_matrix "${file}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate matrix fixture ${file}" "${description}" "fixture fails" "passed" "Make invalid matrix fixtures fail their intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "validate matrix fixture ${file}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep matrix diagnostics deterministic."
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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid matrix inputs fail their intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep matrix diagnostics deterministic."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

validate_workflow() {
  local file="$1"
  if ! grep -Fq 'fromJSON(' "${file}"; then
    diag "validate build workflow" "${file}" "workflow consumes matrix with fromJSON" "missing" "Use generated matrix JSON instead of hard-coded workflow rows."
    return 1
  fi
  if ! grep -Eq 'outputs:|GITHUB_OUTPUT|build_matrix|matrix:' "${file}"; then
    diag "validate build workflow" "${file}" "workflow uses job outputs or generated matrix data" "missing" "Pass generated matrix data between jobs."
    return 1
  fi
  if ! grep -Fq 'validate-matrix-json.py' "${file}"; then
    diag "validate build workflow" "${file}" "workflow rejects missing required matrix keys with shared validator" "missing" "Call validate-matrix-json.py before exposing matrix outputs."
    return 1
  fi
  if grep -Eq 'pg_major:\s*["'\'' ]?(17|18|19beta1)|debian_variant:\s*["'\'' ]?(trixie|bookworm)|standard-(trixie|bookworm)' "${file}"; then
    diag "validate build workflow" "${file}" "no hard-coded PostgreSQL/Debian workflow rows" "$(grep -En 'pg_major:|debian_variant:|standard-(trixie|bookworm)' "${file}")" "Consume generated matrix rows instead of duplicating metadata."
    return 1
  fi
}

for fixture in \
  valid-publishable-matrix.json \
  missing-required-key.json \
  hardcoded-workflow-row.yml \
  pg19beta1-not-experimental.json \
  bookworm-latest-eligible.json; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 4.1 matrix fixture exists" "missing" "Restore the matrix fixture set."
    exit 1
  }
done

generated="$(mktemp)"
TAG_VALIDATION_DATE=20260609 "${SCRIPT}" --metadata "${PUBLISHABLE_METADATA}" --json >"${generated}"
python3 - "${generated}" "${FIXTURE_DIR}/valid-publishable-matrix.json" <<'PY'
from pathlib import Path
import json
import sys
actual = json.loads(Path(sys.argv[1]).read_text())
expected = json.loads(Path(sys.argv[2]).read_text())
if actual != expected:
    raise SystemExit(f"generated publishable matrix drifted\nactual={actual}\nexpected={expected}")
PY
rm -f "${generated}"

validate_matrix "${FIXTURE_DIR}/valid-publishable-matrix.json"
python3 - "${ROOT_DIR}" "${PUBLISHABLE_METADATA}" "${FIXTURE_DIR}/valid-publishable-matrix.json" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])
metadata = Path(sys.argv[2])
matrix = json.loads(Path(sys.argv[3]).read_text())
sys.dont_write_bytecode = True
sys.path.insert(0, str(root / "cloudnative-pg-timescaledb" / "scripts" / "lib"))
from generator_contract import parse_metadata
from tag_policy import generated_tags

data = parse_metadata(metadata, "test-matrix-tag-policy")
entries = {(entry["pg_major"], entry["debian_variant"]): entry for entry in data["entries"]}
for row in matrix["include"]:
    entry = entries[(row["pg_major"], row["debian_variant"])]
    expected = generated_tags(entry, "20260609")
    if row["intended_tags"] != expected:
        raise SystemExit(f"matrix intended_tags diverged from tag_policy: row={row} expected={expected}")
PY
validate_matrix "${ROOT_DIR}/cloudnative-pg-timescaledb/matrix.json"
"${VALIDATE_MATRIX_JSON}" --file "${FIXTURE_DIR}/valid-publishable-matrix.json"
expect_command_fail "shared workflow validator rejects missing required key" "missing .*digest" "${VALIDATE_MATRIX_JSON}" --file "${FIXTURE_DIR}/missing-required-key.json"
expect_matrix_fail "missing required key" "missing .*digest" "${FIXTURE_DIR}/missing-required-key.json"
expect_matrix_fail "19beta1 must be experimental" "19beta1 .*experimental" "${FIXTURE_DIR}/pg19beta1-not-experimental.json"
expect_matrix_fail "bookworm cannot be latest" "latest_eligible only" "${FIXTURE_DIR}/bookworm-latest-eligible.json"

validate_workflow "${WORKFLOW}"
if validate_workflow "${FIXTURE_DIR}/hardcoded-workflow-row.yml" >/tmp/story-4-1-hardcoded-workflow.out 2>&1; then
  diag "validate build workflow" "${FIXTURE_DIR}/hardcoded-workflow-row.yml" "hard-coded workflow row fails" "passed" "Reject hand-written PostgreSQL/Debian workflow rows."
  exit 1
fi

grep -Fq 'candidate_ref' "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md" || {
  diag "grep matrix schema" "cloudnative-pg-timescaledb/docs/generated/matrix-schema.md" "candidate_ref documented" "missing" "Document downstream release matrix fields."
  exit 1
}

printf 'PASS story-4.1 matrix fixtures\n'
