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
import re
import sys

path = Path(sys.argv[1])
command = f"validate matrix fixture {path}"
required_include = {
    "pg_major", "pg_version", "timescaledb_version", "debian_variant", "image", "candidate_ref", "digest",
    "platforms", "bake_target", "dockerfile", "intended_tags", "publish", "experimental",
    "latest_eligible", "scan_result", "sbom_ref", "provenance_ref", "signature_ref",
}
required_skipped = {"pg_major", "pg_version", "debian_variant", "platforms", "bake_target", "skipped_marker", "publish", "experimental", "latest_eligible", "skip_reason"}

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
seen_identities = set()
seen_bake_targets = set()
for idx, row in enumerate(include):
    missing = sorted(required_include - set(row))
    extra = sorted(set(row) - required_include)
    if missing or extra:
        fail(f"include[{idx}] required keys", f"missing {missing}, extra {extra}", "Keep downstream workflow keys explicit; do not recompute release fields.")
    identity = (row["pg_major"], row["debian_variant"])
    if identity in seen_identities:
        fail(f"include[{idx}] identity is unique across include and skipped", row, "Emit one matrix row per PostgreSQL/Debian pair.")
    seen_identities.add(identity)
    if row["bake_target"] in seen_bake_targets:
        fail(f"include[{idx}].bake_target is unique across include and skipped", row, "Emit one Bake target per PostgreSQL/Debian pair.")
    seen_bake_targets.add(row["bake_target"])
    if row["publish"] is not True:
        fail(f"include[{idx}].publish is true", row["publish"], "Only publishable rows belong in include[].")
    expected_target = f"pg{row['pg_major']}-{row['debian_variant']}"
    expected_dockerfile = f"cloudnative-pg-timescaledb/generated/{row['pg_major']}/{row['debian_variant']}/Dockerfile"
    if row["bake_target"] != expected_target or row["dockerfile"] != expected_dockerfile:
        fail(f"include[{idx}] exposes metadata-derived Dockerfile and target", row, "Build matrix rows must expose metadata-derived Dockerfile and Bake target.")
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

for idx, row in enumerate(skipped):
    missing = sorted(required_skipped - set(row))
    extra = sorted(set(row) - required_skipped)
    if missing or extra:
        fail(f"skipped[{idx}] required summary keys exactly", f"missing {missing}, extra {extra}", "Skipped rows must keep marker, target, publish:false, and skip_reason only.")
    identity = (row["pg_major"], row["debian_variant"])
    if identity in seen_identities:
        fail(f"skipped[{idx}] identity is unique across include and skipped", row, "Emit one matrix row per PostgreSQL/Debian pair.")
    seen_identities.add(identity)
    if row["bake_target"] in seen_bake_targets:
        fail(f"skipped[{idx}].bake_target is unique across include and skipped", row, "Emit one Bake target per PostgreSQL/Debian pair.")
    seen_bake_targets.add(row["bake_target"])
    for key in ["publish", "experimental", "latest_eligible"]:
        if not isinstance(row[key], bool):
            fail(f"skipped[{idx}].{key} is boolean", row[key], "Use JSON booleans for skipped matrix control fields.")
    if not isinstance(row["skip_reason"], str) or not row["skip_reason"].strip():
        fail(f"skipped[{idx}].skip_reason is non-empty string", row["skip_reason"], "Keep skipped summary entries actionable.")
    if row["publish"] is not False:
        fail(f"skipped[{idx}] publish false with skip_reason", row, "Keep skipped summary entries actionable.")
    expected_pg_version = row["pg_major"] if row["pg_major"] == "19beta1" else rf"{re.escape(str(row['pg_major']))}\.[0-9]+"
    if row["pg_major"] == "19beta1" and row["pg_version"] != expected_pg_version:
        fail(f"skipped[{idx}].pg_version matches pg_major", row, "Skipped rows must keep PostgreSQL identity unambiguous.")
    if row["pg_major"] != "19beta1" and not re.fullmatch(expected_pg_version, str(row["pg_version"])):
        fail(f"skipped[{idx}].pg_version matches pg_major version pattern", row, "Skipped rows must keep PostgreSQL identity unambiguous.")
    expected_target = f"pg{row['pg_major']}-{row['debian_variant']}"
    expected_marker = f"cloudnative-pg-timescaledb/generated/{row['pg_major']}/{row['debian_variant']}/Dockerfile.skipped.json"
    if row["bake_target"] != expected_target or row["skipped_marker"] != expected_marker:
        fail(f"skipped[{idx}] exposes marker and target", row, "Skipped rows must expose metadata-derived marker and Bake target.")
    if row["pg_major"] == "19beta1" and row["experimental"] is not True:
        fail("19beta1 skipped rows are experimental", row, "Keep PostgreSQL 19 preview rows experimental.")
    if row["latest_eligible"] is not False:
        fail("skipped latest_eligible is false", row, "Only publishable include[] rows may own latest.")

if latest_rows != [("18", "trixie")]:
    fail("exactly one latest row across include and skipped", latest_rows, "Keep latest promotion on the primary trixie row only.")
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
  if grep -Eq 'pg_major:\s*["'\'' ]?(17|18|19beta1)|debian_variant:\s*["'\'' ]?(trixie|bookworm)|(^|[^-])standard-(trixie|bookworm)' "${file}"; then
    diag "validate build workflow" "${file}" "no hard-coded PostgreSQL/Debian workflow rows" "$(grep -En 'pg_major:|debian_variant:|(^|[^-])standard-(trixie|bookworm)' "${file}")" "Consume generated matrix rows instead of duplicating metadata."
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

generated="$(mktemp)"
DATE=20260610 "${SCRIPT}" --metadata "${PUBLISHABLE_METADATA}" --json >"${generated}"
python3 - "${generated}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
tags = [tag for row in payload["include"] for tag in row["intended_tags"]]
candidate_refs = [row["candidate_ref"] for row in payload["include"]]
if not tags or not all("20260610" in tag for tag in tags if "-pg" in tag and "-ts" in tag):
    raise SystemExit(f"DATE fallback did not reach intended immutable tags: {tags}")
if not candidate_refs or not all("20260610" in ref for ref in candidate_refs):
    raise SystemExit(f"DATE fallback did not reach candidate refs: {candidate_refs}")
PY
rm -f "${generated}"

expect_command_fail "invalid TAG_VALIDATION_DATE calendar date" "valid UTC YYYYMMDD|valid UTC calendar date" env TAG_VALIDATION_DATE=20261340 "${SCRIPT}" --metadata "${PUBLISHABLE_METADATA}" --json
invalid_tag_metadata="$(mktemp)"
python3 - "${PUBLISHABLE_METADATA}" "${invalid_tag_metadata}" <<'PY'
from pathlib import Path
import sys

source, output = sys.argv[1:]
text = Path(source).read_text()
text = text.replace('timescaledb_version: "2.27.2"', 'timescaledb_version: "2.27.2/bad"', 1)
Path(output).write_text(text)
PY
expect_command_fail "generator rejects invalid Docker tag grammar" "generated tags use valid Docker tag grammar|invalid Docker tag" "${SCRIPT}" --metadata "${invalid_tag_metadata}" --json
rm -f "${invalid_tag_metadata}"

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
extra_include_key_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${extra_include_key_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["unexpected"] = "extra"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects extra include key" "extra .*unexpected|required keys exactly" "${VALIDATE_MATRIX_JSON}" --file "${extra_include_key_matrix}"
rm -f "${extra_include_key_matrix}"
include_publish_false_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${include_publish_false_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["publish"] = False
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects non-publishable include rows" "publish is true" "${VALIDATE_MATRIX_JSON}" --file "${include_publish_false_matrix}"
rm -f "${include_publish_false_matrix}"
wrong_include_path_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${wrong_include_path_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["dockerfile"] = "cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile.skipped.json"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects wrong include Dockerfile path" "metadata-derived Dockerfile and target" "${VALIDATE_MATRIX_JSON}" --file "${wrong_include_path_matrix}"
rm -f "${wrong_include_path_matrix}"
missing_skipped_key_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${missing_skipped_key_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload.pop("skipped", None)
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects missing skipped key" "top-level keys exactly include and skipped" "${VALIDATE_MATRIX_JSON}" --file "${missing_skipped_key_matrix}"
rm -f "${missing_skipped_key_matrix}"
invalid_tag_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${invalid_tag_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["intended_tags"][1] = "18-pg18.4-ts2.27.2/bad-20260609"
payload["include"][0]["candidate_ref"] = f"{payload['include'][0]['image']}:{payload['include'][0]['intended_tags'][1]}"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects invalid Docker tags" "Docker tag grammar" "${VALIDATE_MATRIX_JSON}" --file "${invalid_tag_matrix}"
rm -f "${invalid_tag_matrix}"
digest_candidate_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${digest_candidate_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["candidate_ref"] = f"{payload['include'][0]['image']}@sha256:{'a' * 64}"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects digest candidate refs" "candidate_ref equals image:immutable-tag" "${VALIDATE_MATRIX_JSON}" --file "${digest_candidate_matrix}"
rm -f "${digest_candidate_matrix}"
fake_immutable_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${fake_immutable_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["intended_tags"] = ["17", "foo-pgbar-tsbaz"]
payload["include"][0]["candidate_ref"] = f"{payload['include'][0]['image']}:foo-pgbar-tsbaz"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects fake immutable tags" "policy immutable tag" "${VALIDATE_MATRIX_JSON}" --file "${fake_immutable_matrix}"
rm -f "${fake_immutable_matrix}"
wrong_timescale_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${wrong_timescale_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["intended_tags"][1] = payload["include"][0]["intended_tags"][1].replace("ts2.27.2", "ts9.99.9")
payload["include"][0]["candidate_ref"] = f"{payload['include'][0]['image']}:{payload['include'][0]['intended_tags'][1]}"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects wrong TimescaleDB immutable tag" "policy immutable tag" "${VALIDATE_MATRIX_JSON}" --file "${wrong_timescale_matrix}"
rm -f "${wrong_timescale_matrix}"
bookworm_latest_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${bookworm_latest_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][1]["latest_eligible"] = True
payload["include"][1]["intended_tags"].append("latest")
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects bookworm latest" "latest_eligible only" "${VALIDATE_MATRIX_JSON}" --file "${bookworm_latest_matrix}"
rm -f "${bookworm_latest_matrix}"
missing_latest_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${missing_latest_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["latest_eligible"] = False
payload["include"][0]["intended_tags"] = [tag for tag in payload["include"][0]["intended_tags"] if tag != "latest"]
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator requires latest owner" "latest_eligible true|exactly one latest owner" "${VALIDATE_MATRIX_JSON}" --file "${missing_latest_matrix}"
rm -f "${missing_latest_matrix}"
trixie_suffix_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${trixie_suffix_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["intended_tags"][1] = "18-pg18.4-ts2.27.2-20260609-bookworm"
payload["include"][0]["candidate_ref"] = f"{payload['include'][0]['image']}:{payload['include'][0]['intended_tags'][1]}"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects trixie Debian suffix" "policy immutable tag|trixie immutable tag" "${VALIDATE_MATRIX_JSON}" --file "${trixie_suffix_matrix}"
rm -f "${trixie_suffix_matrix}"
unsupported_pg_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${unsupported_pg_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
row = payload["include"][0]
row["pg_major"] = "20"
row["pg_version"] = "20.1"
row["intended_tags"] = ["20", "20-pg20.1-ts2.27.2-20260609"]
row["candidate_ref"] = f"{row['image']}:{row['intended_tags'][1]}"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects unsupported PostgreSQL" "pg_major is supported" "${VALIDATE_MATRIX_JSON}" --file "${unsupported_pg_matrix}"
rm -f "${unsupported_pg_matrix}"
unsupported_debian_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${unsupported_debian_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
row = payload["include"][0]
row["debian_variant"] = "alpine"
row["intended_tags"][1] = f"{row['pg_major']}-pg{row['pg_version']}-ts{row['timescaledb_version']}-20260609-alpine"
row["candidate_ref"] = f"{row['image']}:{row['intended_tags'][1]}"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects unsupported Debian" "debian_variant is supported" "${VALIDATE_MATRIX_JSON}" --file "${unsupported_debian_matrix}"
rm -f "${unsupported_debian_matrix}"
invalid_platform_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${invalid_platform_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["include"][0]["platforms"] = ["linux/amd64"]
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects incomplete platforms" "platforms exactly" "${VALIDATE_MATRIX_JSON}" --file "${invalid_platform_matrix}"
rm -f "${invalid_platform_matrix}"
missing_skipped_path_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${missing_skipped_path_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["skipped"][0].pop("bake_target", None)
payload["skipped"][0].pop("skipped_marker", None)
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects skipped rows without marker paths" "skipped\\[0\\] required keys|bake_target|skipped_marker" "${VALIDATE_MATRIX_JSON}" --file "${missing_skipped_path_matrix}"
rm -f "${missing_skipped_path_matrix}"
wrong_skipped_path_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${wrong_skipped_path_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["skipped"][0]["skipped_marker"] = "cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects wrong skipped marker path" "exposes metadata-derived marker and target|exposes marker and target" "${VALIDATE_MATRIX_JSON}" --file "${wrong_skipped_path_matrix}"
rm -f "${wrong_skipped_path_matrix}"
extra_skipped_dockerfile_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${extra_skipped_dockerfile_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["skipped"][0]["dockerfile"] = "cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects extra skipped dockerfile" "extra .*dockerfile|required keys exactly" "${VALIDATE_MATRIX_JSON}" --file "${extra_skipped_dockerfile_matrix}"
rm -f "${extra_skipped_dockerfile_matrix}"
string_skipped_latest_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${string_skipped_latest_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["skipped"][0]["latest_eligible"] = "false"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects string skipped latest" "latest_eligible is boolean" "${VALIDATE_MATRIX_JSON}" --file "${string_skipped_latest_matrix}"
rm -f "${string_skipped_latest_matrix}"
null_skip_reason_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${null_skip_reason_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["skipped"][0]["skip_reason"] = None
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects null skip_reason" "skip_reason is non-empty string" "${VALIDATE_MATRIX_JSON}" --file "${null_skip_reason_matrix}"
rm -f "${null_skip_reason_matrix}"
wrong_skipped_pg_version_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${wrong_skipped_pg_version_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["skipped"][0]["pg_version"] = "19.0"
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects wrong skipped pg_version" "pg_version matches pg_major|pg_version starts with pg_major" "${VALIDATE_MATRIX_JSON}" --file "${wrong_skipped_pg_version_matrix}"
rm -f "${wrong_skipped_pg_version_matrix}"
malformed_stable_skipped_pg_version_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${malformed_stable_skipped_pg_version_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
stable = payload["include"][1].copy()
stable["publish"] = False
stable["skip_reason"] = "Publish disabled until release gate enables image builds"
stable["skipped_marker"] = f"cloudnative-pg-timescaledb/generated/{stable['pg_major']}/{stable['debian_variant']}/Dockerfile.skipped.json"
stable["latest_eligible"] = False
stable["pg_version"] = f"{stable['pg_major']}.bad"
for key in ["timescaledb_version", "image", "candidate_ref", "digest", "dockerfile", "intended_tags", "scan_result", "sbom_ref", "provenance_ref", "signature_ref"]:
    stable.pop(key, None)
payload["skipped"].append(stable)
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects malformed stable skipped pg_version" "pg_version matches pg_major version pattern" "${VALIDATE_MATRIX_JSON}" --file "${malformed_stable_skipped_pg_version_matrix}"
rm -f "${malformed_stable_skipped_pg_version_matrix}"
duplicate_skipped_identity_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${duplicate_skipped_identity_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["skipped"].append(payload["skipped"][0].copy())
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects duplicate skipped rows" "identity is unique|bake_target is unique" "${VALIDATE_MATRIX_JSON}" --file "${duplicate_skipped_identity_matrix}"
rm -f "${duplicate_skipped_identity_matrix}"
skipped_latest_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${skipped_latest_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
payload["skipped"][0]["latest_eligible"] = True
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects skipped latest" "latest_eligible is false|matrix has exactly one latest owner" "${VALIDATE_MATRIX_JSON}" --file "${skipped_latest_matrix}"
rm -f "${skipped_latest_matrix}"
skipped_18_latest_matrix="$(mktemp)"
python3 - "${FIXTURE_DIR}/valid-publishable-matrix.json" "${skipped_18_latest_matrix}" <<'PY'
from pathlib import Path
import json
import sys

source, output = sys.argv[1:]
payload = json.loads(Path(source).read_text())
latest = payload["include"].pop(0)
latest["publish"] = False
latest["skip_reason"] = "Publish disabled until release gate enables image builds"
latest["skipped_marker"] = f"cloudnative-pg-timescaledb/generated/{latest['pg_major']}/{latest['debian_variant']}/Dockerfile.skipped.json"
for key in ["timescaledb_version", "image", "candidate_ref", "digest", "dockerfile", "intended_tags", "scan_result", "sbom_ref", "provenance_ref", "signature_ref"]:
    latest.pop(key, None)
payload["skipped"].append(latest)
Path(output).write_text(json.dumps(payload, separators=(",", ":")))
PY
expect_command_fail "shared workflow validator rejects skipped 18-trixie latest" "skipped\\[[0-9]+\\]\\.latest_eligible is false|matrix has exactly one latest owner" "${VALIDATE_MATRIX_JSON}" --file "${skipped_18_latest_matrix}"
rm -f "${skipped_18_latest_matrix}"
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
