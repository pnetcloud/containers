#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/catalog/fixtures"
GENERATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-catalog.sh"
WORKFLOW="${ROOT_DIR}/.github/workflows/update.yml"
BUILD_WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"
ALLOWLIST="${ROOT_DIR}/cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt"
RELEASE_METADATA_ALLOWLIST="${ROOT_DIR}/cloudnative-pg-timescaledb/config/release-metadata-autocommit-allowlist.txt"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid catalog inputs fail their intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep catalog diagnostics deterministic."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

materialize_release_metadata() {
  local output_dir="$1"
  local mode="${2:-valid}"
  mkdir -p "${output_dir}"
  python3 - "${output_dir}" "${mode}" <<'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
mode = sys.argv[2]
image = "ghcr.io/pnetcloud/cloudnative-pg-timescaledb"


def record(name, tags, digest, amd64, arm64):
    payload = {
        "candidate_digest": amd64,
        "cosign_certificate_identity": "https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main",
        "cosign_certificate_issuer": "https://token.actions.githubusercontent.com",
        "final_tags": tags,
        "image": image,
        "index_digest": digest,
        "platform_digests": {
            "linux/amd64": amd64,
            "linux/arm64": arm64,
        },
        "promotion_status": "validated",
        "provenance_ref": f"{image}@{digest}#provenance",
        "published_digest": digest,
        "release_metadata_record_id": digest,
        "release_metadata_ref": f"{image}@{digest}",
        "sbom_ref": f"{image}@{digest}#sbom",
        "scan_result": "passed",
        "signature_ref": f"{image}@{digest}#signature",
        "verified": True,
    }
    if mode == "unsigned" and name == "17-trixie":
        payload.pop("signature_ref")
    (out / f"{name}.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


record(
    "17-trixie",
    ["17", "17-pg17.10-ts2.27.2-20260609"],
    "sha256:" + "a" * 64,
    "sha256:" + "1" * 64,
    "sha256:" + "2" * 64,
)
record(
    "18-trixie",
    ["18", "18-pg18.4-ts2.27.2-20260609", "latest"],
    "sha256:" + "b" * 64,
    "sha256:" + "3" * 64,
    "sha256:" + "4" * 64,
)
record(
    "17-bookworm",
    ["17-bookworm", "17-pg17.10-ts2.27.2-20260609-bookworm"],
    "sha256:" + "c" * 64,
    "sha256:" + "5" * 64,
    "sha256:" + "6" * 64,
)
record(
    "18-bookworm",
    ["18-bookworm", "18-pg18.4-ts2.27.2-20260609-bookworm"],
    "sha256:" + "d" * 64,
    "sha256:" + "7" * 64,
    "sha256:" + "8" * 64,
)
if mode == "experimental":
    record(
        "19beta1-trixie",
        ["19beta1-pg19beta1-tsunresolved-20260609"],
        "sha256:" + "e" * 64,
        "sha256:" + "9" * 64,
        "sha256:" + "0" * 64,
    )
PY
}

validate_catalog_workflow() {
  local workflow="$1"
  local allowlist="$2"
  python3 - "${workflow}" "${allowlist}" "${ROOT_DIR}/cloudnative-pg-timescaledb/workflow-policy.yaml" <<'PY'
import json
import sys
from pathlib import Path
import yaml

workflow = Path(sys.argv[1])
allowlist = Path(sys.argv[2])
policy = Path(sys.argv[3])
payload = yaml.safe_load(workflow.read_text())
command = "validate catalog autocommit workflow"


def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


jobs = payload.get("jobs") if isinstance(payload, dict) else None
if not isinstance(jobs, dict):
    fail(workflow, "workflow has jobs mapping", type(jobs).__name__, "Keep update.yml parseable for structured workflow validation.")
job = jobs.get("catalog-autocommit")
if not isinstance(job, dict):
    fail(workflow, "catalog-autocommit job exists", "missing", "Add a named release catalog autocommit job.")
for name, value in jobs.items():
    perms = value.get("permissions", {}) if isinstance(value, dict) else {}
    if isinstance(perms, dict) and perms.get("contents") == "write" and name not in {"autocommit", "catalog-autocommit"}:
        fail(workflow, "contents: write is restricted to known autocommit jobs", name, "Do not grant repository write permission to unrelated update jobs.")
if job.get("permissions", {}).get("contents") != "write":
    fail(workflow, "catalog-autocommit has contents: write", job.get("permissions"), "Catalog autocommit needs write permission for catalog-only commits.")
job_if = str(job.get("if", ""))
for marker in ["github-actions[bot]", "head_commit.message", "chore(cnpg-timescaledb): update release catalogs"]:
    if marker not in job_if:
        fail(workflow, f"catalog-autocommit job-level recursion guard contains {marker}", job_if, "Use a job-level if guard so recursive generated catalog commits skip every step.")
needs = job.get("needs", [])
if isinstance(needs, str):
    needs = [needs]
if "autocommit" not in needs:
    fail(workflow, "catalog-autocommit waits for resolver autocommit", needs, "Avoid parallel update jobs racing on branch pushes.")
steps_text = json.dumps(job.get("steps", []), sort_keys=True)
required_markers = [
    "generate-catalog.sh",
    "cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt",
    "autocommit-stage.sh",
    "validate-autocommit-staging.sh",
    "git diff --cached --quiet",
    "No release catalog changes to commit.",
    "Refresh branch tip after resolver autocommit",
    "git fetch --no-tags --prune --depth=1 origin",
    "git checkout -B",
    "Locate release metadata",
    "available=false",
    "steps.catalog_metadata.outputs.available == 'true'",
]
for marker in required_markers:
    if marker not in steps_text:
        fail(workflow, f"catalog-autocommit contains {marker}", "missing", "Keep catalog autocommit path allowlisted, no-op safe, and recursion guarded.")
if "git add cloudnative-pg-timescaledb/" in steps_text:
    fail(workflow, "catalog-autocommit stages only through the catalog allowlist", "raw git add found", "Use autocommit-stage.sh with CATALOG_AUTOCOMMIT allowlist only.")
if 'else\\n            make catalog' in steps_text or 'generate-catalog.sh --check' in steps_text:
    fail(workflow, "missing release metadata does not generate or validate empty catalogs", "fallback catalog generation found", "Make catalog autocommit a no-op until release metadata is available.")
expected = {
    "cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml",
    "cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml",
}
actual = {line.split("#", 1)[0].strip() for line in allowlist.read_text().splitlines() if line.split("#", 1)[0].strip()}
if actual != expected:
    fail(allowlist, "catalog allowlist contains exactly the two stable catalog manifests", sorted(actual), "Do not allow catalog autocommit to stage docs, metadata, workflows, vendor trees, or runtime artifacts.")
policy_text = policy.read_text()
for marker in ["job: catalog-autocommit", "permission: \"contents: write\"", "owner_story: 4.6"]:
    if marker not in policy_text:
        fail(policy, f"workflow policy contains {marker}", "missing", "Record the Story 4.6 permission exception.")
print("PASS catalog autocommit workflow")
PY
}

validate_release_metadata_autocommit_workflow() {
  local workflow="$1"
  local allowlist="$2"
  python3 - "${workflow}" "${allowlist}" "${ROOT_DIR}/cloudnative-pg-timescaledb/workflow-policy.yaml" <<'PY'
import json
import sys
from pathlib import Path
import yaml

workflow = Path(sys.argv[1])
allowlist = Path(sys.argv[2])
policy = Path(sys.argv[3])
payload = yaml.safe_load(workflow.read_text())
command = "validate release metadata autocommit workflow"


def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


jobs = payload.get("jobs") if isinstance(payload, dict) else None
if not isinstance(jobs, dict):
    fail(workflow, "workflow has jobs mapping", type(jobs).__name__, "Keep build.yml parseable for structured workflow validation.")
job = jobs.get("release_metadata_autocommit")
if not isinstance(job, dict):
    fail(workflow, "release_metadata_autocommit job exists", "missing", "Persist successful publish metadata back to the repository.")
for name, value in jobs.items():
    perms = value.get("permissions", {}) if isinstance(value, dict) else {}
    if isinstance(perms, dict) and perms.get("contents") == "write" and name != "release_metadata_autocommit":
        fail(workflow, "build.yml contents: write is restricted to release metadata autocommit", name, "Do not grant repository write permission to unrelated build jobs.")
if job.get("permissions", {}).get("contents") != "write":
    fail(workflow, "release_metadata_autocommit has contents: write", job.get("permissions"), "The metadata persistence job needs repository write permission for allowlisted generated files only.")
needs = job.get("needs", [])
if isinstance(needs, str):
    needs = [needs]
for required_need in ["matrix", "publish"]:
    if required_need not in needs:
        fail(workflow, f"release_metadata_autocommit waits for {required_need}", needs, "Only persist metadata after the matrix is known and publish has completed.")
job_if = str(job.get("if", ""))
for marker in [
    "refs/heads/main",
    "workflow_dispatch",
    "startsWith(github.ref, 'refs/heads/')",
    "github-actions[bot]",
    "head_commit.message",
    "chore(cnpg-timescaledb): update release metadata and catalogs",
]:
    if marker not in job_if:
        fail(workflow, f"release_metadata_autocommit job-level guard contains {marker}", job_if, "Constrain writes to branch release runs and prevent generated metadata commit recursion.")
steps_text = json.dumps(job.get("steps", []), sort_keys=True)
required_markers = [
    "ghcr-release-metadata-*",
    "release-metadata-autocommit/input",
    "release_metadata_record_id",
    "cloudnative-pg-timescaledb/release-metadata",
    "-type f -name '*.json' -delete",
    "generate-catalog.sh --release-metadata",
    "catalog-standard-*.yaml",
    "cloudnative-pg-timescaledb/config/release-metadata-autocommit-allowlist.txt",
    "autocommit-stage.sh",
    "validate-autocommit-staging.sh",
    "git diff --cached --quiet",
    "No release metadata or catalog changes to commit.",
    "git fetch --no-tags --prune --depth=1 origin",
    "git checkout -B",
    "git push origin",
]
for marker in required_markers:
    if marker not in steps_text:
        fail(workflow, f"release_metadata_autocommit contains {marker}", "missing", "Keep release metadata persistence allowlisted, digest-aware, branch-safe, and no-op safe.")
if "git add cloudnative-pg-timescaledb/" in steps_text:
    fail(workflow, "release_metadata_autocommit stages only through the release metadata allowlist", "raw git add found", "Use autocommit-stage.sh with RELEASE_METADATA allowlist only.")
expected = {
    "cloudnative-pg-timescaledb/release-metadata/*.json",
    "cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml",
    "cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml",
}
actual = {line.split("#", 1)[0].strip() for line in allowlist.read_text().splitlines() if line.split("#", 1)[0].strip()}
if actual != expected:
    fail(allowlist, "release metadata allowlist contains exactly release metadata JSON and the two stable catalog manifests", sorted(actual), "Do not allow release metadata autocommit to stage docs, workflows, vendor trees, secrets, or runtime artifacts.")
policy_text = policy.read_text()
for marker in ["job: release_metadata_autocommit", "permission: \"contents: write\"", "owner_story: 4.6"]:
    if marker not in policy_text:
        fail(policy, f"workflow policy contains {marker}", "missing", "Record the Story 4.6 build.yml permission exception.")
print("PASS release metadata autocommit workflow")
PY
}

validate_empty_diff_fixture() {
  local fixture="$1"
  python3 - "${fixture}" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
if "git diff --cached --quiet" not in text or "exit 0" not in text:
    raise SystemExit(
        "command: validate catalog empty-diff fixture\n"
        f"artifact: {sys.argv[1]}\n"
        "expected: empty catalog diff exits cleanly with git diff --cached --quiet and exit 0\n"
        f"actual: {text.strip()}\n"
        "remediation: Keep catalog autocommit no-op behavior explicit."
    )
PY
}

validate_recursive_fixture() {
  local fixture="$1"
  python3 - "${fixture}" "${WORKFLOW}" <<'PY'
import json
import sys
from pathlib import Path
event = json.loads(Path(sys.argv[1]).read_text())
workflow = Path(sys.argv[2]).read_text()
if event.get("actor") != "github-actions[bot]" or event.get("head_commit", {}).get("message") != "chore(cnpg-timescaledb): update release catalogs":
    raise SystemExit("recursive fixture must describe a generated catalog bot commit")
for marker in ["github-actions[bot]", "head_commit.message", "chore(cnpg-timescaledb): update release catalogs"]:
    if marker not in workflow:
        raise SystemExit(
            "command: validate catalog recursive guard\n"
            f"artifact: {sys.argv[2]}\n"
            f"expected: workflow contains recursive guard marker {marker}\n"
            "actual: missing\n"
            "remediation: Prevent generated catalog commits from recursively triggering catalog autocommit."
        )
PY
}

catalog_fixture_as() {
  local fixture="$1"
  local canonical_name="$2"
  local output_dir="$3"
  mkdir -p "${output_dir}"
  cp "${FIXTURE_DIR}/${fixture}" "${output_dir}/${canonical_name}"
  printf '%s/%s\n' "${output_dir}" "${canonical_name}"
}

for fixture in \
  valid-trixie-catalog.yaml \
  valid-bookworm-catalog.yaml \
  unpublished-tag.yaml \
  unsigned-digest.yaml \
  missing-digest.yaml \
  missing-signer-identity.json \
  platform-missing-from-index.json \
  per-platform-digest.yaml \
  wrong-postgres-major.yaml \
  wrong-debian-variant.yaml \
  wrong-catalog-name-variant.yaml \
  pg19beta1-in-stable-catalog.yaml \
  missing-catalog-allowlist.txt \
  catalog-autocommit-stages-unlisted-path.yml \
  catalog-autocommit-diff-empty.txt \
  catalog-autocommit-recursive-build-commit.json; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 4.6 fixture exists" "missing" "Restore the complete catalog fixture set."
    exit 1
  }
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
release_dir="${tmpdir}/release"
materialize_release_metadata "${release_dir}" valid
catalog_case_dir="${tmpdir}/catalog-cases"
valid_trixie="$(catalog_fixture_as valid-trixie-catalog.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/valid-trixie")"
valid_bookworm="$(catalog_fixture_as valid-bookworm-catalog.yaml catalog-standard-bookworm.yaml "${catalog_case_dir}/valid-bookworm")"
unpublished="$(catalog_fixture_as unpublished-tag.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/unpublished")"
missing_digest="$(catalog_fixture_as missing-digest.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/missing-digest")"
per_platform="$(catalog_fixture_as per-platform-digest.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/per-platform")"
wrong_pg="$(catalog_fixture_as wrong-postgres-major.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/wrong-pg")"
wrong_debian="$(catalog_fixture_as wrong-debian-variant.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/wrong-debian")"
wrong_name="$(catalog_fixture_as wrong-catalog-name-variant.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/wrong-name")"
unsigned_catalog="$(catalog_fixture_as unsigned-digest.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/unsigned")"
pg19_catalog="$(catalog_fixture_as pg19beta1-in-stable-catalog.yaml catalog-standard-trixie.yaml "${catalog_case_dir}/pg19")"

generated_dir="${tmpdir}/generated-catalog"
"${GENERATOR}" --release-metadata "${release_dir}" --output "${generated_dir}"
diff -u "${FIXTURE_DIR}/valid-trixie-catalog.yaml" "${generated_dir}/catalog-standard-trixie.yaml"
diff -u "${FIXTURE_DIR}/valid-bookworm-catalog.yaml" "${generated_dir}/catalog-standard-bookworm.yaml"

stale_metadata="${tmpdir}/versions-with-newer-timescaledb.yaml"
python3 - "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${stale_metadata}" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
source = re.sub(r'pg_version: "17\.10"', 'pg_version: "17.11"', source)
source = re.sub(r'pg_version: "18\.4"', 'pg_version: "18.5"', source)
source = re.sub(r'timescaledb_version: "2\.27\.2"', 'timescaledb_version: "2.28.0"', source)
Path(sys.argv[2]).write_text(source)
PY
stale_generated_dir="${tmpdir}/stale-release-metadata-generated-catalog"
"${GENERATOR}" --metadata "${stale_metadata}" --release-metadata "${release_dir}" --output "${stale_generated_dir}"
diff -u "${FIXTURE_DIR}/valid-trixie-catalog.yaml" "${stale_generated_dir}/catalog-standard-trixie.yaml"
diff -u "${FIXTURE_DIR}/valid-bookworm-catalog.yaml" "${stale_generated_dir}/catalog-standard-bookworm.yaml"

partial_dir="${tmpdir}/partial-release"
materialize_release_metadata "${partial_dir}" valid
rm -f "${partial_dir}/18-bookworm.json"
expect_fail "partial release metadata" "every publishable stable PostgreSQL/Debian row|18-bookworm" "${GENERATOR}" --release-metadata "${partial_dir}" --output "${tmpdir}/partial-generated-catalog"

empty_record_id_dir="${tmpdir}/empty-record-id-release"
materialize_release_metadata "${empty_record_id_dir}" valid
python3 - "${empty_record_id_dir}/18-trixie.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["release_metadata_record_id"] = ""
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
expect_fail "empty release metadata record id" "release_metadata_record_id.*sha256" "${GENERATOR}" --release-metadata "${empty_record_id_dir}" --output "${tmpdir}/empty-record-id-generated-catalog"

"${GENERATOR}" --release-metadata "${release_dir}" --validate-catalog "${valid_trixie}"
"${GENERATOR}" --release-metadata "${release_dir}" --validate-catalog "${valid_bookworm}"

expect_fail "unpublished tag" "final_tags|unpublished" "${GENERATOR}" --release-metadata "${release_dir}" --validate-catalog "${unpublished}"
expect_fail "missing digest" "digest" "${GENERATOR}" --release-metadata "${release_dir}" --validate-catalog "${missing_digest}"
expect_fail "per-platform digest" "per-platform|manifest-list" "${GENERATOR}" --release-metadata "${release_dir}" --validate-catalog "${per_platform}"
expect_fail "wrong PostgreSQL major" "PostgreSQL numeric major" "${GENERATOR}" --release-metadata "${release_dir}" --validate-catalog "${wrong_pg}"
expect_fail "wrong Debian variant" "Debian variant" "${GENERATOR}" --release-metadata "${release_dir}" --validate-catalog "${wrong_debian}"
expect_fail "wrong catalog name variant" "metadata.name variant|file variant" "${GENERATOR}" --release-metadata "${release_dir}" --validate-catalog "${wrong_name}"
expect_fail "missing platform from index" "platform_digests covers every publishable platform" "${GENERATOR}" --release-metadata "${FIXTURE_DIR}/platform-missing-from-index.json" --validate-catalog "${valid_trixie}"
expect_fail "missing signer identity" "cosign_certificate_identity|missing" "${GENERATOR}" --release-metadata "${FIXTURE_DIR}/missing-signer-identity.json" --validate-catalog "${valid_trixie}"

duplicate_dir="${tmpdir}/duplicate-release"
materialize_release_metadata "${duplicate_dir}" valid
python3 - "${duplicate_dir}/17-trixie.json" "${duplicate_dir}/17-trixie-duplicate.json" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
payload["published_digest"] = "sha256:" + "f" * 64
payload["index_digest"] = payload["published_digest"]
payload["release_metadata_record_id"] = payload["published_digest"]
payload["release_metadata_ref"] = f"{payload['image']}@{payload['published_digest']}"
for key in ["sbom_ref", "provenance_ref", "signature_ref"]:
    suffix = payload[key].split("#", 1)[1]
    payload[key] = f"{payload['image']}@{payload['published_digest']}#{suffix}"
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
expect_fail "duplicate release metadata" "duplicate_key|one release metadata record" "${GENERATOR}" --release-metadata "${duplicate_dir}" --validate-catalog "${valid_trixie}"

unsigned_dir="${tmpdir}/unsigned-release"
materialize_release_metadata "${unsigned_dir}" unsigned
expect_fail "unsigned digest" "signature_ref|signed" "${GENERATOR}" --release-metadata "${unsigned_dir}" --validate-catalog "${unsigned_catalog}"

experimental_dir="${tmpdir}/experimental-release"
materialize_release_metadata "${experimental_dir}" experimental
expect_fail "pg19beta1 in stable catalog" "experimental PostgreSQL" "${GENERATOR}" --release-metadata "${experimental_dir}" --validate-catalog "${pg19_catalog}"

validate_catalog_workflow "${WORKFLOW}" "${ALLOWLIST}"
validate_release_metadata_autocommit_workflow "${BUILD_WORKFLOW}" "${RELEASE_METADATA_ALLOWLIST}"
expect_fail "missing catalog allowlist entry" "two stable catalog manifests" validate_catalog_workflow "${WORKFLOW}" "${FIXTURE_DIR}/missing-catalog-allowlist.txt"
expect_fail "catalog autocommit stages unlisted path" "allowlist|raw git add|autocommit" validate_catalog_workflow "${FIXTURE_DIR}/catalog-autocommit-stages-unlisted-path.yml" "${ALLOWLIST}"
expect_fail "catalog autocommit missing empty diff no-op" "empty catalog diff" validate_empty_diff_fixture "${FIXTURE_DIR}/catalog-autocommit-diff-empty.txt"
validate_recursive_fixture "${FIXTURE_DIR}/catalog-autocommit-recursive-build-commit.json"

printf 'PASS story-4.6 digest-aware catalog generation\n'
