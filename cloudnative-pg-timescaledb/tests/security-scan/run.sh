#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/security-scan/fixtures"
POLICY="${ROOT_DIR}/cloudnative-pg-timescaledb/config/vulnerability-policy.yaml"
IGNORE="${ROOT_DIR}/cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml"
EVALUATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/evaluate-vulnerability-scan.py"
SCAN_FILE_VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-vulnerability-scan-files.py"
CANDIDATE_METADATA="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures/valid-candidate-metadata.json"
BUILD_WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"
SCAN_WORKFLOW="${ROOT_DIR}/.github/workflows/security-scan.yml"

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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid security scan inputs fail their intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep security scan diagnostics deterministic."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

evaluate_pass_fixture() {
  local output
  output="$(mktemp)"
  "${EVALUATOR}" --policy "${POLICY}" --ignore "${IGNORE}" --candidate-metadata "${CANDIDATE_METADATA}" --scan-json "${FIXTURE_DIR}/valid-scan-pass.json" --output "${output}"
  python3 - "${output}" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
if payload["scan_result"] != "passed" or payload["failure_reason"]:
    raise SystemExit(f"expected passing scan summary: {payload}")
if payload["pg_major"] != "18" or payload["debian_variant"] != "trixie" or not payload["candidate_ref"] or not payload["digest"]:
    raise SystemExit(f"missing candidate summary fields: {payload}")
PY
  rm -f "${output}"
}

evaluate_unfixed_fixture() {
  local output
  output="$(mktemp)"
  "${EVALUATOR}" --policy "${POLICY}" --ignore "${IGNORE}" --candidate-metadata "${CANDIDATE_METADATA}" --scan-json "${FIXTURE_DIR}/unfixed-threshold-reported.json" --output "${output}"
  python3 - "${output}" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
if payload["scan_result"] != "passed" or payload["failure_reason"]:
    raise SystemExit(f"expected unfixed threshold finding to be reported without blocking: {payload}")
if len(payload.get("threshold_findings", [])) != 1:
    raise SystemExit(f"expected threshold finding evidence: {payload}")
if len(payload.get("unfixed_threshold_findings", [])) != 1:
    raise SystemExit(f"expected unfixed threshold finding evidence: {payload}")
if payload.get("release_blocking_findings"):
    raise SystemExit(f"unfixed finding must not be release-blocking by default: {payload}")
PY
  rm -f "${output}"
}

validate_security_scan_workflow() {
  local file="$1"
  python3 - "${file}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
command = f"validate security scan workflow {path}"


def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def require(condition, expected, actual, remediation):
    if not condition:
        fail(expected, actual, remediation)


require("workflow_call:" in text, "security-scan.yml is reusable through workflow_call", "workflow_call missing", "Make security scans a required same-run reusable workflow.")
require("vulnerability-policy.yaml" in text and "vulnerability-ignore.yaml" in text, "workflow consumes encoded policy and ignore files", "policy markers missing", "Do not hard-code scanner policy only in shell steps.")
require("docker.io/aquasec/trivy:0.65.0" in text and "trivy" in text, "workflow encodes scanner command/image", "Trivy command missing", "Run the configured scanner against candidate image references.")
require("--severity" in text and "HIGH,CRITICAL" in text, "workflow encodes HIGH/CRITICAL threshold", "severity threshold missing", "Block unacceptable high-severity findings.")
require("scanner_metadata_status" in text and "db_update_status" in text, "workflow fails closed when scanner DB metadata is unavailable", "fail-closed marker missing", "Do not publish when scanner metadata cannot be fetched.")
require("scanner_failed: ${{ steps.scan.outputs.scanner_failed }}" in text, "workflow exposes scanner_failed as a scan job output", "scanner_failed output missing", "Make scanner and SARIF generation failures explicit before downstream jobs run.")
require("SARIF output is missing; vulnerability scanner or SARIF generation failed" in text, "workflow writes deterministic SARIF diagnostics when SARIF generation fails", "SARIF diagnostic placeholder missing", "Create a diagnostic SARIF artifact before upload-artifact runs so the gate fails for the scanner reason, not a missing file.")
require("vulnerability scanner or SARIF generation failed" in text, "workflow summaries distinguish scanner/SARIF failure from policy failure", "scanner failure summary reason missing", "Surface infrastructure scanner failures separately from vulnerability policy failures.")
require("validate-vulnerability-scan-files.py" in text, "workflow validates scanner JSON file coverage and candidate identity before evaluation", "scan file validator missing", "Fail closed when scanner JSON output is missing or mismatched.")
require("evaluate-vulnerability-scan.py" in text, "workflow evaluates scanner JSON with repository policy", "evaluator missing", "Convert scanner output into a deterministic release gate result.")
require("actions/upload-artifact@" in text and "vulnerability-scan-json" in text and "vulnerability-scan-summary" in text, "workflow always stores scanner JSON and summary artifacts", "JSON artifact upload missing", "Persist scan evidence even when the gate fails.")
require("vulnerability-scan-sarif" in text and "upload-sarif@" in text, "workflow stores and uploads SARIF", "SARIF upload missing", "Upload SARIF when code scanning is enabled.")
require("needs.scan.outputs.scanner_failed == 'false'" in text, "SARIF upload job skips scanner-generated diagnostic SARIF after scanner failure", "scanner_failed upload guard missing", "Do not run CodeQL SARIF upload when scanner or SARIF generation failed.")
require("security-events: write" in text, "SARIF upload job has security-events write", "security-events write missing", "Grant code scanning upload permission only for SARIF upload.")
require(not re.search(r"secrets\." , text), "workflow does not require explicit secrets", "secrets context used", "Use GitHub token only for same-repository candidate access.")
PY
}

validate_build_scan_gate() {
  local file="$1"
  python3 - "${file}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
command = f"validate build scan gate {path}"


def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def require(condition, expected, actual, remediation):
    if not condition:
        fail(expected, actual, remediation)


require("security_scan:" in text, "build workflow has required security_scan job", "security_scan job missing", "Wire scans into the same build run.")
require("uses: ./.github/workflows/security-scan.yml" in text, "build workflow invokes required reusable security-scan.yml", "reusable workflow call missing", "Do not replace the required scan workflow with inline helper steps.")
require(re.search(r"security_scan:[\s\S]*needs:[\s\S]*candidate", text), "security_scan needs candidate", "candidate dependency missing", "Scan only release candidates that passed build and smoke gates.")
require("artifact_name: release-candidate-${{ matrix.bake_target }}" in text, "security_scan consumes candidate metadata artifact from Story 4.2", "candidate artifact input missing", "Scan the same candidate metadata that later publish gates consume.")
require("security-events: write" in text, "build delegates SARIF upload permission to security scan gate", "security-events permission missing", "Reusable scan workflow needs permission for code scanning upload.")
publish_match = re.search(r"\n  publish:\n(?P<body>[\s\S]+?)(?:\n  [A-Za-z0-9_-]+:|\Z)", text)
if publish_match:
    body = publish_match.group("body")
    require("security_scan" in body, "publish job depends on security_scan when present", body[:400], "Final tag promotion must consume the scan result for the same digest.")
PY
}

for fixture in \
  valid-scan-pass.json \
  unfixed-threshold-reported.json \
  high-threshold-exceeded.json \
  scanner-db-unavailable.json \
  valid-scan-pass-arm64.json \
  mismatched-scan-artifact.json \
  missing-sarif-upload.yml \
  scan-not-required-by-build.yml; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 4.3 security scan fixture exists" "missing" "Restore the complete security scan fixture set."
    exit 1
  }
done

grep -Fq 'severity_threshold: HIGH' "${POLICY}" || { diag "grep policy" "${POLICY}" "HIGH severity threshold encoded" "missing" "Encode the vulnerability severity threshold in config."; exit 1; }
grep -Fq 'fail_on_fixable_threshold_exceeded: true' "${POLICY}" || { diag "grep policy" "${POLICY}" "fixable threshold findings block release" "missing" "Block release when a fixed package version exists but the image has not consumed it."; exit 1; }
grep -Fq 'fail_on_unfixed_threshold_exceeded: false' "${POLICY}" || { diag "grep policy" "${POLICY}" "unfixed threshold findings are reported without blocking by default" "missing" "Keep release automation green when upstream has not published a fixed package, while recording evidence."; exit 1; }
grep -Fq 'undeclared_ignores: reject' "${IGNORE}" || { diag "grep ignore policy" "${IGNORE}" "undeclared ignores rejected" "missing" "Keep ignores explicit and reviewable."; exit 1; }
grep -Fq 'fail closed' "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/vulnerability-policy.md" || { diag "grep vulnerability docs" "cloudnative-pg-timescaledb/docs/vulnerability-policy.md" "fail-closed behavior documented" "missing" "Document scanner DB failure behavior."; exit 1; }
grep -Fq 'FixedVersion' "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/vulnerability-policy.md" || { diag "grep vulnerability docs" "cloudnative-pg-timescaledb/docs/vulnerability-policy.md" "fixable versus unfixed threshold behavior documented" "missing" "Document which vulnerabilities block release and which remain evidence-only."; exit 1; }

evaluate_pass_fixture
evaluate_unfixed_fixture
scan_dir="$(mktemp -d)"
cp "${FIXTURE_DIR}/valid-scan-pass.json" "${scan_dir}/pg18-trixie-linux-amd64.json"
cp "${FIXTURE_DIR}/valid-scan-pass-arm64.json" "${scan_dir}/pg18-trixie-linux-arm64.json"
"${SCAN_FILE_VALIDATOR}" --candidate-metadata "${CANDIDATE_METADATA}" --scan-dir "${scan_dir}"
empty_scan_dir="$(mktemp -d)"
expect_fail "missing scanner JSON output" "scanner JSON files exactly" "${SCAN_FILE_VALIDATOR}" --candidate-metadata "${CANDIDATE_METADATA}" --scan-dir "${empty_scan_dir}"
missing_platform_scan_dir="$(mktemp -d)"
cp "${FIXTURE_DIR}/valid-scan-pass.json" "${missing_platform_scan_dir}/pg18-trixie-linux-amd64.json"
expect_fail "missing platform scanner JSON output" "scanner JSON files exactly" "${SCAN_FILE_VALIDATOR}" --candidate-metadata "${CANDIDATE_METADATA}" --scan-dir "${missing_platform_scan_dir}"
rm -rf "${scan_dir}" "${empty_scan_dir}" "${missing_platform_scan_dir}"
expect_fail "HIGH threshold exceeded" "release-blocking vulnerabilities at or above HIGH" "${EVALUATOR}" --policy "${POLICY}" --ignore "${IGNORE}" --candidate-metadata "${CANDIDATE_METADATA}" --scan-json "${FIXTURE_DIR}/high-threshold-exceeded.json"
expect_fail "scanner DB unavailable" "scanner database or metadata unavailable" "${EVALUATOR}" --policy "${POLICY}" --ignore "${IGNORE}" --candidate-metadata "${CANDIDATE_METADATA}" --scan-json "${FIXTURE_DIR}/scanner-db-unavailable.json"
expect_fail "mismatched scanner artifact identity" "ArtifactName matches one candidate_ref@platform_digest" "${EVALUATOR}" --policy "${POLICY}" --ignore "${IGNORE}" --candidate-metadata "${CANDIDATE_METADATA}" --scan-json "${FIXTURE_DIR}/mismatched-scan-artifact.json"

validate_security_scan_workflow "${SCAN_WORKFLOW}"
validate_build_scan_gate "${BUILD_WORKFLOW}"
expect_fail "missing SARIF upload" "SARIF upload" validate_security_scan_workflow "${FIXTURE_DIR}/missing-sarif-upload.yml"
expect_fail "scan not required by build" "security_scan job missing" validate_build_scan_gate "${FIXTURE_DIR}/scan-not-required-by-build.yml"

printf 'PASS story-4.3 security scan fixtures\n'
