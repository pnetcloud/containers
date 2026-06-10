#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/summaries/fixtures"
HELPER="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/write-step-summary.sh"

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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid summary inputs fail their intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep summary diagnostics deterministic."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

validate_rendered_summary() {
  local path="$1"
  python3 - "${path}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
command = "validate rendered workflow summary"


def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


for marker in ["Status:", "Candidate digest:", "Published digest:", "Failure reason:", "Remediation command:"]:
    if marker not in text:
        fail(f"summary contains {marker}", "missing", "Use the shared summary templates.")
if re.search(r"digest: `(?:|n/a)`", text, re.I):
    fail("digest fields are populated", "missing digest", "Populate candidate and published digest fields for completed release jobs.")
if re.search(r"Status: `(?:failure|failed|cancelled)`", text) and re.search(r"Failure reason: `(?:|none|n/a)`", text):
    fail("failed summaries include actionable failure reason", "missing failure reason", "Set FAILURE_REASON on failed summary writes.")
print("PASS rendered summary")
PY
}

validate_workflow_summaries() {
  python3 - "${ROOT_DIR}" <<'PY'
import json
import sys
from pathlib import Path
import yaml

root = Path(sys.argv[1])
command = "validate workflow summaries"
required = {
    ".github/workflows/update.yml": {
        "autocommit": ["cloudnative-pg-timescaledb/templates/summaries/update.md"],
        "catalog-autocommit": ["cloudnative-pg-timescaledb/templates/summaries/catalog.md"],
    },
    ".github/workflows/build.yml": {
        "candidate": [
            "cloudnative-pg-timescaledb/templates/summaries/build.md",
            "cloudnative-pg-timescaledb/templates/summaries/smoke.md",
        ],
        "release_evidence": [
            "cloudnative-pg-timescaledb/templates/summaries/evidence.md",
            "cloudnative-pg-timescaledb/templates/summaries/sbom.md",
            "cloudnative-pg-timescaledb/templates/summaries/provenance.md",
            "cloudnative-pg-timescaledb/templates/summaries/signing.md",
        ],
        "publish": ["cloudnative-pg-timescaledb/templates/summaries/publish.md"],
    },
    ".github/workflows/security-scan.yml": {
        "scan": ["cloudnative-pg-timescaledb/templates/summaries/vulnerability.md"],
        "upload_sarif": ["cloudnative-pg-timescaledb/templates/summaries/scan-sarif.md"],
    },
}


def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


for rel, jobs in required.items():
    path = root / rel
    payload = yaml.safe_load(path.read_text())
    workflow_jobs = payload.get("jobs", {})
    for job_id, templates in jobs.items():
        job = workflow_jobs.get(job_id)
        if not isinstance(job, dict):
            fail(path, f"workflow contains job {job_id}", "missing", "Keep documented summary coverage jobs present.")
        steps = job.get("steps", [])
        text = json.dumps(steps, sort_keys=True)
        if "write-step-summary.sh" not in text:
            fail(path, f"job {job_id} uses shared write-step-summary helper", "missing", "Do not hand-roll workflow summaries inline.")
        for template in templates:
            if template not in text:
                fail(path, f"job {job_id} writes template {template}", "missing", "Wire the documented summary template through write-step-summary.sh.")
        summary_steps = [step for step in steps if isinstance(step, dict) and "write-step-summary.sh" in str(step.get("run", ""))]
        if not summary_steps:
            fail(path, f"job {job_id} has summary step", "missing", "Add a shared summary step.")
        for step in summary_steps:
            if step.get("if") != "always()":
                fail(path, f"job {job_id} summary step uses if: always()", step.get("if"), "Summaries must run on success and failure.")
            run = str(step.get("run", ""))
            if "--require-failure-reason" not in run:
                fail(path, f"job {job_id} summary enforces failure reasons", "missing --require-failure-reason", "Require actionable failure reasons for failed summaries.")
            if job_id in {"candidate", "release_evidence", "publish", "scan", "upload_sarif"} and "--require-success" not in run:
                fail(path, f"job {job_id} summary enforces required success fields", "missing --require-success", "Require digest/status fields on successful completed release jobs.")
print("PASS workflow summary coverage")
PY
}

for fixture in valid-summary.md missing-digest.md missing-failure-reason.md; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || { diag test "${FIXTURE_DIR}/${fixture}" "fixture exists" missing "Restore Story 4.7 summary fixtures."; exit 1; }
done

validate_rendered_summary "${FIXTURE_DIR}/valid-summary.md"
expect_fail "missing digest fixture" "digest" validate_rendered_summary "${FIXTURE_DIR}/missing-digest.md"
expect_fail "missing failure reason fixture" "failure reason" validate_rendered_summary "${FIXTURE_DIR}/missing-failure-reason.md"

tmp="$(mktemp)"
SUMMARY_STATUS=success \
FINAL_TAGS=18,latest \
LATEST_TARGET=latest \
CANDIDATE_DIGEST=sha256:1111111111111111111111111111111111111111111111111111111111111111 \
PUBLISHED_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
PLATFORM_DIGESTS=linux/amd64=sha256:1111111111111111111111111111111111111111111111111111111111111111 \
SCAN_RESULT=passed \
SBOM_STATUS=present \
PROVENANCE_STATUS=present \
SIGNATURE_STATUS=verified \
SKIPPED_COMBINATIONS=none \
FAILURE_REASON=none \
REMEDIATION_COMMAND=none \
  "${HELPER}" --template "${ROOT_DIR}/cloudnative-pg-timescaledb/templates/summaries/publish.md" --output "${tmp}" --require PUBLISHED_DIGEST
validate_rendered_summary "${tmp}"
rm -f "${tmp}"

expect_fail "helper missing digest" "PUBLISHED_DIGEST" env SUMMARY_STATUS=success "${HELPER}" --template "${ROOT_DIR}/cloudnative-pg-timescaledb/templates/summaries/publish.md" --output /tmp/story-4-7-missing-digest.md --require PUBLISHED_DIGEST
expect_fail "helper missing success digest" "successful summary field PUBLISHED_DIGEST" env SUMMARY_STATUS=success PUBLISHED_DIGEST=n/a "${HELPER}" --template "${ROOT_DIR}/cloudnative-pg-timescaledb/templates/summaries/publish.md" --output /tmp/story-4-7-missing-success-digest.md --require-success PUBLISHED_DIGEST
expect_fail "helper missing failure reason" "FAILURE_REASON" env SUMMARY_STATUS=failure PUBLISHED_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "${HELPER}" --template "${ROOT_DIR}/cloudnative-pg-timescaledb/templates/summaries/publish.md" --output /tmp/story-4-7-missing-failure.md --require-failure-reason

validate_workflow_summaries

printf 'PASS story-4.7 workflow summaries\n'
