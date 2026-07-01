#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/publish-tag-promotion/fixtures"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-publish-gates.sh"
WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"

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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid publish gate inputs fail their intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep publish gate diagnostics deterministic."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

materialize_fixture() {
  local descriptor="$1"
  local output="$2"
  python3 - "${FIXTURE_DIR}/valid-publish-release.json" "${descriptor}" "${output}" <<'PY'
import copy
import json
import sys
from pathlib import Path

base = json.loads(Path(sys.argv[1]).read_text())
descriptor = Path(sys.argv[2])
out = Path(sys.argv[3])
case = json.loads(descriptor.read_text()).get("case")
payload = copy.deepcopy(base)


def records():
    return payload["candidate_metadata"]


def index_evidence():
    index_digest = payload["candidate_metadata"][0]["index_digest"]
    for row in payload["release_evidence"]["per_digest_evidence"]:
        if row.get("digest") == index_digest:
            return row
    raise SystemExit("base fixture missing index evidence")


if case == "missing-build-gate":
    payload["gates"].pop("candidate_build", None)
elif case == "missing-smoke-gate":
    payload["gates"].pop("smoke_container", None)
    records()[0]["smoke_container_status"] = "missing"
elif case == "missing-scan-gate":
    payload["gates"].pop("vulnerability_scan", None)
elif case == "missing-sbom":
    payload["gates"].pop("sbom", None)
    index_evidence().pop("sbom_ref", None)
elif case == "missing-provenance":
    payload["gates"].pop("provenance", None)
    index_evidence().pop("provenance_ref", None)
elif case == "missing-signature":
    payload["gates"].pop("signature", None)
    index_evidence().pop("signature_ref", None)
elif case == "verification-not-passed":
    payload["gates"]["verification"] = "failed"
    payload["release_evidence"]["verified"] = False
    index_evidence()["verified"] = False
elif case == "missing-tag-validation-gate":
    payload["gates"].pop("tag_validation", None)
elif case == "metadata-record-mismatch":
    payload["release_metadata_record_id"] = "sha256:" + "0" * 64
elif case == "digest-mismatch":
    payload["release_evidence"]["index_digest"] = "sha256:" + "b" * 64
elif case == "wrong-latest-bookworm":
    for row in records():
        row["bake_target"] = "pg18-bookworm"
        row["debian_variant"] = "bookworm"
        row["dockerfile"] = "cloudnative-pg-timescaledb/generated/18/bookworm/Dockerfile"
        row["intended_tags"] = ["18-bookworm", "18-pg18.4-ts2.27.2-20260609-bookworm", "latest"]
        row["latest_eligible"] = False
    payload["release_metadata_ref"] = f"{records()[0]['image']}@{records()[0]['index_digest']}"
elif case == "pg19beta1-normal-tag":
    for row in records():
        row["bake_target"] = "pg19beta1-trixie"
        row["dockerfile"] = "cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile"
        row["experimental"] = True
        row["intended_tags"] = ["19beta1", "19beta1-pg19beta1-ts2.27.2-20260609"]
        row["latest_eligible"] = False
        row["pg_major"] = "19beta1"
        row["pg_version"] = "19beta1"
elif case == "valid-bookworm-release":
    for row in records():
        row["bake_target"] = "pg18-bookworm"
        row["debian_variant"] = "bookworm"
        row["dockerfile"] = "cloudnative-pg-timescaledb/generated/18/bookworm/Dockerfile"
        row["intended_tags"] = ["18-bookworm", "18-pg18.4-ts2.27.2-20260609-bookworm"]
        row["latest_eligible"] = False
    payload["release_metadata_ref"] = f"{records()[0]['image']}@{records()[0]['index_digest']}"
elif case == "valid-pg19beta1-experimental-release":
    for row in records():
        row["bake_target"] = "pg19beta1-trixie"
        row["dockerfile"] = "cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile"
        row["experimental"] = True
        row["intended_tags"] = ["19beta1-pg19beta1-ts2.27.2-20260609"]
        row["latest_eligible"] = False
        row["pg_major"] = "19beta1"
        row["pg_version"] = "19beta1"
    payload["release_metadata_ref"] = f"{records()[0]['image']}@{records()[0]['index_digest']}"
elif case:
    raise SystemExit(f"unknown fixture case {case!r}")
else:
    raise SystemExit(f"fixture {descriptor} does not contain case")

out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

validate_publish_workflow() {
  local file="$1"
  python3 - "${file}" "${ROOT_DIR}/cloudnative-pg-timescaledb/workflow-policy.yaml" <<'PY'
from pathlib import Path
import json
import sys
import yaml

workflow = Path(sys.argv[1])
policy = Path(sys.argv[2])
payload = yaml.safe_load(workflow.read_text())
command = f"validate publish workflow {workflow}"


def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {workflow}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def require(condition, expected, actual, remediation):
    if not condition:
        fail(expected, actual, remediation)


def body(name):
    require(name in jobs, f"build workflow has {name} job", "missing", f"Add {name} to build.yml.")
    return jobs[name]


def needs(job):
    value = job.get("needs", [])
    if isinstance(value, str):
        return {value}
    return set(value)


def steps_text(job):
    return json.dumps(job.get("steps", []), sort_keys=True)


require(isinstance(payload, dict) and isinstance(payload.get("jobs"), dict), "workflow YAML parses with jobs mapping", type(payload).__name__, "Keep build.yml parseable as YAML for structured validation.")
jobs = payload["jobs"]
candidate = body("candidate")
security_scan = body("security_scan")
release_evidence = body("release_evidence")
tag_validation = body("tag_validation")
publish = body("publish")

publish_needs = needs(publish)
security_needs = needs(security_scan)
evidence_needs = needs(release_evidence)
tag_needs = needs(tag_validation)
require({"matrix", "candidate", "security_scan", "release_evidence", "tag_validation"}.issubset(publish_needs), "publish has explicit same-run needs on matrix, candidate, security_scan, release_evidence, tag_validation", sorted(publish_needs), "Make final tag promotion depend on every prior release gate.")
publish_if = str(publish.get("if", ""))
for marker in ["github.event_name == 'workflow_dispatch'", "github.ref == 'refs/heads/main'", "startsWith(github.ref, 'refs/tags/')"]:
    require(marker in publish_if, f"publish job if guard contains {marker}", publish_if, "Restrict final tag promotion to manual, main, or tag release contexts.")
require("needs.matrix.outputs.has_include == 'true'" in publish_if, "publish job if guard requires non-empty generated matrix", publish_if, "Publish only generated publishable rows.")
require("candidate" in security_needs, "security_scan needs candidate", sorted(security_needs), "Scan the same candidate metadata built and smoked in this run.")
require({"candidate", "security_scan"}.issubset(evidence_needs), "release_evidence needs candidate and security_scan", sorted(evidence_needs), "Sign and verify only after candidate and scan gates pass.")
require({"candidate", "security_scan", "release_evidence"}.issubset(tag_needs), "tag_validation needs candidate, security_scan, and release_evidence", sorted(tag_needs), "Create release gate metadata only after all upstream gates pass.")

candidate_text = steps_text(candidate)
evidence_text = steps_text(release_evidence)
tag_text = steps_text(tag_validation)
publish_text = steps_text(publish)

for marker in ["CHECKS=container make smoke", "CHECKS=sql make smoke"]:
    require(marker in candidate_text, f"candidate job contains {marker}", "missing", "Candidate job must include per-platform smoke gates before publish.")
for marker in ["--sbom=true", "--provenance=mode=max"]:
    require(marker in candidate_text, f"candidate job emits {marker}", "missing", "Candidate build must produce BuildKit supply-chain evidence.")
for marker in ["cosign sign --yes", "cosign verify", "validate-release-evidence.py"]:
    require(marker in evidence_text, f"release_evidence job contains {marker}", "missing", "Publish must depend on signed and verified release evidence.")
for marker in [
    "validate-tags.sh",
    "validate-publish-gates.sh",
    "--tag-validation-status",
    "--gate-output",
    "release-gate-metadata-${{ matrix.bake_target }}",
]:
    require(marker in tag_text, f"tag_validation job contains {marker}", "missing", "Tag validation must emit same-run release gate metadata before publish.")
for marker in [
    "release-candidate-${{ matrix.bake_target }}",
    "vulnerability-scan-summary-${{ matrix.bake_target }}",
    "release-evidence-${{ matrix.bake_target }}",
    "release-gate-metadata-${{ matrix.bake_target }}",
    "validate-publish-gates.sh",
    "--release-gate-metadata",
    "docker buildx imagetools create",
    "published.raw.json",
    "published-digests.txt",
    "published platform digest mismatch",
    "final-refs.txt",
    "cosign sign --yes",
    "published_digest",
    "final_tags",
    "docker logout ghcr.io",
    "docker pull --platform",
    "ghcr-release-metadata-${{ matrix.bake_target }}",
    "GITHUB_STEP_SUMMARY",
]:
    require(marker in publish_text, f"publish job contains {marker}", "missing", "Publish must validate same-digest gates, promote exact final tags, and emit metadata evidence.")
require(publish_text.index("docker buildx imagetools create") < publish_text.index("docker logout ghcr.io") < publish_text.index("docker pull"), "publish verifies public anonymous pulls after final tag promotion", "wrong order", "Promote final tags first, then logout and pull anonymously to prove public GHCR availability.")
require("--tag-validation-status passed" not in publish_text, "publish job does not synthesize tag validation status", "found", "Publish must consume release gate metadata from the tag_validation job.")
perms = publish.get("permissions", {})
require(perms.get("contents") == "read" and perms.get("packages") == "write" and perms.get("id-token") == "write", "publish permissions are contents read, packages write, and id-token write", perms, "Use least privilege for clean GHCR tag promotion and published digest signing.")
policy_text = policy.read_text()
require("job: publish" in policy_text and "permission: \"packages: write\"" in policy_text and "permission: \"id-token: write\"" in policy_text and "owner_story: 4.5" in policy_text, "workflow policy allowlists publish packages/id-token write for Story 4.5", "missing", "Add the publish permission allowlist entries.")
PY
}

for fixture in \
  valid-publish-release.json \
  valid-bookworm-release.json \
  valid-pg19beta1-experimental-release.json \
  missing-build-gate.json \
  missing-smoke-gate.json \
  missing-scan-gate.json \
  missing-sbom.json \
  missing-provenance.json \
  missing-signature.json \
  verification-not-passed.json \
  missing-tag-validation-gate.json \
  metadata-record-mismatch.json \
  digest-mismatch.json \
  wrong-latest-bookworm.json \
  pg19beta1-normal-tag.json; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 4.5 publish fixture exists" "missing" "Restore the complete publish tag promotion fixture set."
    exit 1
  }
done

metadata_output="$(mktemp)"
"${VALIDATOR}" --release "${FIXTURE_DIR}/valid-publish-release.json" --output "${metadata_output}"
python3 - "${metadata_output}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
required = {
    "image", "release_metadata_record_id", "release_metadata_ref", "published_digest",
    "final_tags", "scan_result", "sbom_ref", "provenance_ref", "signature_ref",
    "verified", "cosign_certificate_identity", "cosign_certificate_issuer",
    "candidate_digest", "index_digest", "platform_digests", "promotion_status",
}
missing = sorted(required - set(payload))
if missing:
    raise SystemExit(f"missing release metadata keys: {missing}")
if payload["promotion_status"] != "validated" or payload["scan_result"] != "passed" or payload["verified"] is not True:
    raise SystemExit(f"unexpected release metadata status: {payload}")
if payload["final_tags"] != ["18", "18-pg18.4-ts2.27.2-20260609", "latest"]:
    raise SystemExit(f"unexpected final tags: {payload['final_tags']}")
PY
rm -f "${metadata_output}"

for fixture in valid-bookworm-release.json valid-pg19beta1-experimental-release.json; do
  valid="$(mktemp)"
  materialize_fixture "${FIXTURE_DIR}/${fixture}" "${valid}"
  "${VALIDATOR}" --release "${valid}" >/dev/null
  rm -f "${valid}"
done

tmpdir="$(mktemp -d)"
python3 - "${FIXTURE_DIR}/valid-publish-release.json" "${tmpdir}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
(out / "candidate.json").write_text(json.dumps(payload["candidate_metadata"], indent=2, sort_keys=True) + "\n")
(out / "evidence.json").write_text(json.dumps(payload["release_evidence"], indent=2, sort_keys=True) + "\n")
(out / "scan.json").write_text(json.dumps(payload["scan_summary"], indent=2, sort_keys=True) + "\n")
PY
"${VALIDATOR}" --candidate-metadata "${tmpdir}/candidate.json" --release-evidence "${tmpdir}/evidence.json" --scan-summary "${tmpdir}/scan.json" --tag-validation-status passed --gate-output "${tmpdir}/release-gate-metadata.json"
"${VALIDATOR}" --candidate-metadata "${tmpdir}/candidate.json" --release-evidence "${tmpdir}/evidence.json" --scan-summary "${tmpdir}/scan.json" --release-gate-metadata "${tmpdir}/release-gate-metadata.json" --output "${tmpdir}/metadata.json"
python3 - "${tmpdir}/release-gate-metadata.json" "${tmpdir}/missing-record-id.json" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
payload.pop("release_metadata_record_id", None)
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
expect_fail "release gate metadata missing record id" "release_metadata_record_id" "${VALIDATOR}" --candidate-metadata "${tmpdir}/candidate.json" --release-evidence "${tmpdir}/evidence.json" --scan-summary "${tmpdir}/scan.json" --release-gate-metadata "${tmpdir}/missing-record-id.json" --output "${tmpdir}/metadata-missing-record-id.json"
python3 - "${tmpdir}/release-gate-metadata.json" "${tmpdir}/missing-record-ref.json" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
payload.pop("release_metadata_ref", None)
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
expect_fail "release gate metadata missing record ref" "release_metadata_ref" "${VALIDATOR}" --candidate-metadata "${tmpdir}/candidate.json" --release-evidence "${tmpdir}/evidence.json" --scan-summary "${tmpdir}/scan.json" --release-gate-metadata "${tmpdir}/missing-record-ref.json" --output "${tmpdir}/metadata-missing-record-ref.json"
expect_fail "publish without release gate metadata" "release-gate-metadata" "${VALIDATOR}" --candidate-metadata "${tmpdir}/candidate.json" --release-evidence "${tmpdir}/evidence.json" --scan-summary "${tmpdir}/scan.json" --output "${tmpdir}/metadata-missing-gate.json"
rm -rf "${tmpdir}"

declare -A patterns=(
  [missing-build-gate.json]="candidate_build"
  [missing-smoke-gate.json]="smoke_container"
  [missing-scan-gate.json]="vulnerability_scan"
  [missing-sbom.json]="sbom"
  [missing-provenance.json]="provenance"
  [missing-signature.json]="signature"
  [verification-not-passed.json]="verification"
  [missing-tag-validation-gate.json]="tag_validation"
  [metadata-record-mismatch.json]="release_metadata_record_id"
  [digest-mismatch.json]="index_digest"
  [wrong-latest-bookworm.json]="latest|secondary Debian"
  [pg19beta1-normal-tag.json]="experimental PostgreSQL rows"
)

for fixture in "${!patterns[@]}"; do
  invalid="$(mktemp)"
  materialize_fixture "${FIXTURE_DIR}/${fixture}" "${invalid}"
  expect_fail "${fixture}" "${patterns[${fixture}]}" "${VALIDATOR}" --release "${invalid}"
  rm -f "${invalid}"
done

validate_publish_workflow "${WORKFLOW}"

printf 'PASS story-4.5 publish tag promotion fixtures\n'
