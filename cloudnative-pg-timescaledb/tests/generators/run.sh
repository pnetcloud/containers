#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/fixtures"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

catalog_release_metadata_args() {
  local release_metadata_dir="${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata"
  if compgen -G "${release_metadata_dir}/*.json" >/dev/null; then
    printf '%s\0%s\0' --release-metadata "${release_metadata_dir}"
  fi
}

json_compare() {
  local description="$1"
  local fixture="$2"
  shift 2
  local stdout stderr
  stdout="$(mktemp)"
  stderr="$(mktemp)"
  "$@" >"${stdout}" 2>"${stderr}"
  if [[ -s "${stderr}" ]]; then
    diag "${*}" "${description}" "no stderr when --json succeeds" "$(tr '\n' ' ' <"${stderr}")" "Keep machine JSON on stdout and human diagnostics off the success path."
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  python3 - "$fixture" "${stdout}" <<'PY'
import json
import re
import sys
from pathlib import Path


normalize_dockerfiles = Path(sys.argv[1]).name == "generate-dockerfiles-valid.json"
normalize_matrix = Path(sys.argv[1]).name == "generate-matrix-valid.json"
normalize_catalog = Path(sys.argv[1]).name == "generate-catalog-valid.json"


def normalize(path):
    payload = json.loads(Path(path).read_text())

    def immutable_tag_placeholder(row):
        suffix = "" if row.get("debian_variant") == "trixie" else f"-{row.get('debian_variant')}"
        return f"{row.get('pg_major')}-pg<pg_version>-ts<timescaledb_version>-<date>{suffix}"

    def normalize_tag(tag, row):
        if not isinstance(tag, str):
            return tag
        suffix = "" if row.get("debian_variant") == "trixie" else f"-{re.escape(str(row.get('debian_variant')))}"
        pattern = rf"^{re.escape(str(row.get('pg_major')))}-pg[^-]+-ts[^-]+-[0-9]{{8}}{suffix}$"
        if re.fullmatch(pattern, tag):
            return immutable_tag_placeholder(row)
        return tag

    def normalize_ref(value, row):
        if not isinstance(value, str) or ":" not in value:
            return value
        ref, digest = (value.split("@", 1) + [""])[:2] if "@" in value else (value, "")
        image, tag = ref.rsplit(":", 1)
        normalized = f"{image}:{normalize_tag(tag, row)}"
        return f"{normalized}@{digest}" if digest else normalized

    if normalize_dockerfiles:
        for row in payload.get("dockerfiles", []):
            base_image = row.get("base_image")
            if isinstance(base_image, str):
                row["base_image"] = re.sub(r":[^:@]+@sha256:[0-9a-f]{64}$", ":<cnpg-tag>@sha256:<digest>", base_image)
    if normalize_matrix:
        for row in payload.get("include", []):
            row["pg_version"] = "<pg_version>"
            row["timescaledb_version"] = "<timescaledb_version>"
            row["candidate_ref"] = normalize_ref(row.get("candidate_ref"), row)
            row["intended_tags"] = [normalize_tag(tag, row) for tag in row.get("intended_tags", [])]
    if normalize_catalog:
        for catalog in payload.get("catalogs", []):
            for row in catalog.get("entries", []):
                row["image"] = normalize_ref(row.get("image"), row)
    return payload


expected = normalize(sys.argv[1])
actual = normalize(sys.argv[2])
if actual != expected:
    raise SystemExit(f"expected {sys.argv[1]} but got {actual!r}")
PY
  rm -f "${stdout}" "${stderr}"
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
expected_row_set = set(expected_rows)

def require_exact_rows(actual, label):
    if set(actual) != expected_row_set or len(actual) != len(expected_rows):
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
        if row["context"] != "cloudnative-pg-timescaledb":
            fail("bake target context is project checkout/path context", repr(row["context"]), "Use the project subdirectory as local checkout context instead of Docker Buildx default Git context.")
        if row["publish"] is not True:
            fail("bake target rows are publishable", repr(row), "Only publishable metadata rows should become buildable Bake targets.")
        rows.append((match.group(1), match.group(2)))
    skipped_rows = []
    for row in payload["skipped"]:
        expected_keys = {"pg_major", "debian_variant", "name", "skipped_marker", "publish", "experimental", "skip_reason"}
        require_keys(row, expected_keys, "bake skipped row")
        extra = sorted(set(row) - expected_keys)
        if extra:
            fail("bake skipped rows expose only marker fields", repr(row), "Do not expose buildable Dockerfile paths for skipped Bake rows.")
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
        require_keys(row, {"pg_major", "pg_version", "timescaledb_version", "debian_variant", "image", "candidate_ref", "digest", "platforms", "bake_target", "dockerfile", "intended_tags", "publish", "experimental", "latest_eligible", "scan_result", "sbom_ref", "provenance_ref", "signature_ref"}, "matrix include row")
        if row["publish"] is not True:
            fail("matrix include rows are publishable", repr(row), "Only publishable metadata rows should become build matrix rows.")
        if not row["dockerfile"] or not row["bake_target"] or not row["candidate_ref"] or not row["intended_tags"]:
            fail("publishable matrix rows expose release inputs", repr(row), "Build matrix rows must expose Dockerfile, Bake target, candidate ref, and intended tags.")
        rows.append((row["pg_major"], row["debian_variant"]))
    for row in payload["skipped"]:
        expected_keys = {"pg_major", "pg_version", "debian_variant", "platforms", "bake_target", "skipped_marker", "publish", "experimental", "latest_eligible", "skip_reason"}
        require_keys(row, expected_keys, "matrix skipped row")
        extra = sorted(set(row) - expected_keys)
        if extra:
            fail("matrix skipped rows expose only marker fields", repr(row), "Do not expose publishable build fields for skipped matrix rows.")
        if row["publish"] is not False or not row["skip_reason"]:
            fail("matrix skipped rows are non-publishable with skip_reason", repr(row), "Skipped matrix rows must remain summaries only.")
        if not row["skipped_marker"] or not row["bake_target"]:
            fail("skipped matrix rows expose stable marker paths", repr(row), "Expose skipped marker path and Bake target for skipped rows so consumers do not recompute them.")
        rows.append((row["pg_major"], row["debian_variant"]))
    latest = latest_rows_from_matrix(payload["include"] + payload["skipped"])
    if latest != [("18", "trixie")]:
        fail("matrix latest_eligible exactly 18-trixie and skipped rows false", repr(latest), "Preserve latest eligibility from metadata without recomputing it downstream.")
    require_exact_rows(rows, "matrix include plus skipped")
elif kind == "catalog":
    require_keys(payload, {"catalogs"}, "catalog payload")
    catalog_variants = []
    for catalog in payload["catalogs"]:
        require_keys(catalog, {"debian_variant", "catalog_path", "entries"}, "catalog row")
        catalog_variants.append(catalog["debian_variant"])
        for row in catalog["entries"]:
            base_keys = {"pg_major", "debian_variant", "image", "digest", "publish", "experimental", "latest_eligible", "skip_reason"}
            release_keys = {"major", "tag", "source_entry", "platforms", "release_metadata_record_id"}
            expected_keys = base_keys | (release_keys if row.get("release_metadata_record_id") else set())
            require_keys(row, expected_keys, "catalog entry")
            extra = sorted(set(row) - expected_keys)
            if extra:
                fail("catalog entry exposes only metadata or release-complete fields", repr(row), "Do not mix release-only catalog fields into metadata-only JSON summaries.")
            if row["debian_variant"] != catalog["debian_variant"]:
                fail("catalog row Debian variant matches catalog", repr(row), "Keep trixie and bookworm release catalogs separated.")
    if catalog_variants != ["trixie", "bookworm"]:
        fail("catalog variants exactly trixie and bookworm", repr(catalog_variants), "Generate one stable release catalog per supported Debian variant.")
elif kind == "docs":
    require_keys(payload, {"docs", "generated_docs_manifest"}, "docs payload")
    if len(payload["docs"]) != 1:
        fail("docs payload has exactly one compatibility doc row", repr(payload["docs"]), "Keep Story 1.5 docs contract scoped to compatibility skeleton output.")
    for row in payload["docs"]:
        require_keys(row, {"doc_path", "companion_paths", "source", "sections", "publishable_entries", "experimental_entries"}, "docs row")
        if row["sections"] != ["compatibility"]:
            fail("docs sections exactly compatibility", repr(row["sections"]), "Preserve the documented generated docs contract.")
        if row["companion_paths"] != ["cloudnative-pg-timescaledb/docs/generated/compatibility-table.md"]:
            fail("docs companion paths include generated compatibility-table.md", repr(row["companion_paths"]), "Expose the public README compatibility table as a generated companion artifact.")
    manifest = payload["generated_docs_manifest"]
    if not isinstance(manifest, list) or not manifest:
        fail("docs generated_docs_manifest is a non-empty list", repr(manifest), "Expose every generated docs artifact for drift validation and autocommit consumers.")
    manifest_paths = []
    for row in manifest:
        require_keys(row, {"path", "generator_input", "generator_command", "owner_story", "deterministic_generation_mode"}, "generated docs manifest row")
        manifest_paths.append(row["path"])
    required_manifest_paths = [
        "cloudnative-pg-timescaledb/docs/generated/compatibility.md",
        "cloudnative-pg-timescaledb/docs/generated/compatibility-table.md",
        "cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md",
        "cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md",
        "cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md",
        "cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md",
        "cloudnative-pg-timescaledb/docs/generated/matrix-schema.md",
        "cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md",
    ]
    if manifest_paths != required_manifest_paths:
        fail("docs generated_docs_manifest lists every generated docs artifact in contract order", repr(manifest_paths), "Keep generated docs manifest synchronized with generator outputs.")
else:
    fail("known generator kind", kind, "Use a documented generator schema kind.")
PY
}

expect_schema_fail() {
  local description="$1"
  local kind="$2"
  local fixture="$3"
  local pattern="$4"
  local stdout stderr status
  stdout="$(mktemp)"
  stderr="$(mktemp)"
  set +e
  schema_check "${kind}" "${fixture}" >"${stdout}" 2>"${stderr}"
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-generator-schema ${kind} ${fixture}" "${description}" "fixture fails" "passed" "Make malformed generator JSON fail schema validation."
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  if [[ -s "${stdout}" ]]; then
    diag "validate-generator-schema ${kind} ${fixture}" "${description}" "schema diagnostics go to stderr only" "$(tr '\n' ' ' <"${stdout}")" "Keep schema validation output stream-safe for consumers."
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${stderr}"; then
    diag "validate-generator-schema ${kind} ${fixture}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${stderr}")" "Make the fixture fail on its intended schema invariant."
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  rm -f "${stdout}" "${stderr}"
}

expect_command_fail() {
  local description="$1"
  local pattern="$2"
  shift 2
  local stdout stderr status
  stdout="$(mktemp)"
  stderr="$(mktemp)"
  set +e
  "$@" >"${stdout}" 2>"${stderr}"
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "${*}" "${description}" "command fails" "passed" "Make invalid generator command usage fail deterministically."
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  if [[ -s "${stdout}" ]]; then
    diag "${*}" "${description}" "failure diagnostics go to stderr only" "$(tr '\n' ' ' <"${stdout}")" "Keep stdout reserved for successful --json payloads."
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${stderr}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${stderr}")" "Make command fail on its intended invariant."
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  rm -f "${stdout}" "${stderr}"
}

assert_json_field() {
  local description="$1"
  local expected="$2"
  shift 2
  local stdout stderr actual
  stdout="$(mktemp)"
  stderr="$(mktemp)"
  "$@" >"${stdout}" 2>"${stderr}"
  if [[ -s "${stderr}" ]]; then
    diag "${*}" "${description}" "no stderr when --json succeeds" "$(tr '\n' ' ' <"${stderr}")" "Keep machine JSON output stream-safe."
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  actual="$(python3 - "$stdout" <<'PY'
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
    rm -f "${stdout}" "${stderr}"
    exit 1
  fi
  rm -f "${stdout}" "${stderr}"
}

"${SCRIPT_DIR}/generate-dockerfiles.sh" --check
"${SCRIPT_DIR}/generate-bake.sh" --check
"${SCRIPT_DIR}/generate-matrix.sh" --check
mapfile -d '' -t catalog_release_metadata_args_array < <(catalog_release_metadata_args)
"${SCRIPT_DIR}/generate-catalog.sh" "${catalog_release_metadata_args_array[@]}" --check
"${SCRIPT_DIR}/generate-docs.sh" --check

expect_command_fail "dockerfiles check-json detects missing output root" "committed output matches generated content" "${SCRIPT_DIR}/generate-dockerfiles.sh" --output /tmp/story-1-5-missing-generated --check --json
expect_command_fail "matrix check-json detects missing output" "committed output matches generated content" "${SCRIPT_DIR}/generate-matrix.sh" --output /tmp/story-1-5-missing-matrix.json --check --json

missing_metadata="$(mktemp)"
python3 - "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${missing_metadata}" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text().splitlines()
removed = False
out = []
for line in source:
    if not removed and line.strip() == "latest_eligible: true":
        removed = True
        continue
    out.append(line)
Path(sys.argv[2]).write_text("\n".join(out) + "\n")
PY
expect_command_fail "metadata missing latest_eligible emits structured diagnostic" "entries\\[[0-9]+\\] keys include.*latest_eligible" "${SCRIPT_DIR}/generate-matrix.sh" --metadata "${missing_metadata}" --json
rm -f "${missing_metadata}"

null_tags_metadata="$(mktemp)"
python3 - "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${null_tags_metadata}" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text().splitlines()
inserted = False
out = []
for line in source:
    out.append(line)
    if not inserted and line.strip() == '- pg_major: "19beta1"':
        out.append("    tags: null")
        inserted = True
if not inserted:
    raise SystemExit("failed to inject tags:null into metadata fixture")
Path(sys.argv[2]).write_text("\n".join(out) + "\n")
PY
expect_command_fail "metadata tags null emits structured diagnostic" "tags is a list when present" "${SCRIPT_DIR}/generate-matrix.sh" --metadata "${null_tags_metadata}" --json
rm -f "${null_tags_metadata}"

latest_skipped_metadata="$(mktemp)"
latest_skipped_matrix="$(mktemp)"
python3 - "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${latest_skipped_metadata}" <<'PY'
from pathlib import Path
import sys

source, output = sys.argv[1:]
lines = Path(source).read_text().splitlines()
out = []
in_pg18_trixie = False
patched_publish = False
patched_reason = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("- pg_major:"):
        in_pg18_trixie = stripped == '- pg_major: "18"' and not patched_publish
    if in_pg18_trixie and stripped == "debian_variant: trixie":
        out.append(line)
        continue
    if in_pg18_trixie and stripped == "publish: true":
        out.append(line.replace("true", "false"))
        patched_publish = True
        continue
    if in_pg18_trixie and stripped == 'skip_reason: ""':
        out.append('    skip_reason: "Publish disabled until release gate enables image builds"')
        patched_reason = True
        in_pg18_trixie = False
        continue
    out.append(line)
if not patched_publish or not patched_reason:
    raise SystemExit("failed to patch pg18 trixie publish/skip_reason")
Path(output).write_text("\n".join(out) + "\n")
PY
"${SCRIPT_DIR}/generate-matrix.sh" --metadata "${latest_skipped_metadata}" --json >"${latest_skipped_matrix}"
python3 - "${latest_skipped_matrix}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
rows = [row for row in payload["skipped"] if row["pg_major"] == "18" and row["debian_variant"] == "trixie"]
if len(rows) != 1:
    raise SystemExit(f"expected one skipped 18-trixie row, got {rows!r}")
if rows[0]["latest_eligible"] is not True:
    raise SystemExit(f"generator must preserve metadata latest_eligible in skipped summaries: {rows[0]!r}")
PY
expect_command_fail "shared matrix validator rejects skipped latest owner" "latest_eligible is false|exactly one latest owner" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-matrix-json.py" --file "${latest_skipped_matrix}"
rm -f "${latest_skipped_metadata}" "${latest_skipped_matrix}"

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
expect_schema_fail "catalog missing digest" catalog "${FIXTURE_DIR}/generate-catalog-wrong-latest-eligible.json" "missing.*digest"
expect_schema_fail "docs missing doc path" docs "${FIXTURE_DIR}/generate-docs-missing-doc-path.json" "missing.*doc_path"

printf 'PASS story-1.5 generator contracts\n'
