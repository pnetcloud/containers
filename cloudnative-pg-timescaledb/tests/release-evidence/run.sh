#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-evidence/fixtures"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-release-evidence.py"
WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"
EXPECTED_CERTIFICATE_IDENTITY="https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main"
COSIGN_CERTIFICATE_ISSUER="https://token.actions.githubusercontent.com"

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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid release evidence inputs fail their intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep release evidence diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

validate_release_evidence_workflow() {
  local file="$1"
  python3 - "${file}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
command = f"validate release evidence workflow {path}"


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


def job_body(name):
    match = re.search(rf"\n  {re.escape(name)}:\n(?P<body>[\s\S]+?)(?:\n  [A-Za-z0-9_-]+:|\Z)", text)
    require(match, f"build workflow has {name} job", "missing", f"Add the {name} job to the same release workflow.")
    return match.group("body")


candidate = job_body("candidate")
scan = job_body("security_scan")
evidence = job_body("release_evidence")

require("--sbom=true" in candidate, "candidate Buildx Bake emits SBOM attestation", "missing --sbom=true", "Use BuildKit/buildx attestations for candidate images.")
require("--provenance=mode=max" in candidate, "candidate Buildx Bake emits provenance attestation", "missing --provenance=mode=max", "Use BuildKit/buildx provenance for candidate images.")
require("needs:" in evidence and "security_scan" in evidence and "candidate" in evidence, "release_evidence needs candidate and security_scan", evidence[:500], "Do not sign or publish evidence until build, smoke, and vulnerability gates pass.")
require("id-token: write" in evidence, "release_evidence has id-token write for GitHub OIDC", "missing", "Grant OIDC only to the signing job.")
require("contents: read" in evidence, "release_evidence has contents read", "missing", "Keep workflow permissions explicit.")
require("packages: write" in evidence, "release_evidence can upload cosign signature artifacts to GHCR", "missing", "Cosign registry signatures require GHCR package write on the signing job.")
require("sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6" in evidence and "cosign-release: v3.1.1" in evidence, "workflow installs pinned cosign", "missing pinned cosign installer", "Pin the third-party installer action and cosign release.")
require("EXPECTED_CERTIFICATE_IDENTITY: https://github.com/${{ github.repository }}/.github/workflows/build.yml@${{ github.ref }}" in evidence, "workflow derives exact certificate identity from current ref", "missing", "Use the repository workflow identity for the active release ref.")
require("COSIGN_CERTIFICATE_ISSUER: https://token.actions.githubusercontent.com" in evidence, "workflow uses GitHub Actions OIDC issuer", "missing", "Verify with GitHub's OIDC issuer only.")
require("cloudnative-pg-timescaledb/scripts/ci-retry.sh cosign sign --yes" in evidence, "workflow signs immutable digest references through retry helper", "retrying cosign sign missing", "Sign ghcr.io/...@sha256 digest references before publish and retry transient GHCR signature upload failures.")
require("COSIGN_REPOSITORY: ghcr.io/${{ github.repository_owner }}/cloudnative-pg-timescaledb-signatures" in evidence, "workflow stores cosign signatures outside the main image package", "COSIGN_REPOSITORY missing", "Keep release signatures in the dedicated signatures package so the main GHCR package only carries release tags.")
require("cosign verify --certificate-identity \\\"${EXPECTED_CERTIFICATE_IDENTITY}\\\"" in evidence, "workflow verifies with exact certificate identity", "missing exact certificate identity verify", "Do not use a broad certificate identity regexp.")
require("cosign_verify_with_retry" in evidence and "registry propagation delay" in evidence and "sleep 10" in evidence, "workflow retries cosign verification after signing", "missing cosign verify retry", "Retry cosign verify because GHCR signature artifacts may be briefly eventually consistent after upload.")
require("inspect_attestation_with_retry" in evidence and "BuildKit attestation manifest not inspectable yet" in evidence, "workflow retries BuildKit attestation inspection after candidate push", "attestation inspect retry missing", "Retry docker buildx imagetools inspect --raw because GHCR may briefly hide new BuildKit attestations after candidate publish.")
require("--certificate-oidc-issuer" in evidence and "https://token.actions.githubusercontent.com" in evidence, "workflow verifies issuer", "issuer verify missing", "Require the GitHub Actions OIDC issuer.")
require("digests = [index_digest, *platform_digests.values()]" in evidence, "workflow iterates index digest plus every platform digest", "missing digest iteration", "Sign and verify the final index and every platform manifest.")
require("actual_scans != expected_scans" in evidence and "platform_digest" in evidence, "workflow binds scan summary to candidate refs and platform digests", "missing scan binding", "Do not accept a passing scan summary for a different candidate digest.")
require("validate-release-evidence.py" in evidence, "workflow validates release evidence before upload", "validator missing", "Fail closed before later publish jobs consume evidence.")
require("release-evidence-${{ matrix.bake_target }}" in evidence and "actions/upload-artifact@" in evidence, "workflow uploads release evidence artifact", "upload missing", "Persist release evidence for later promotion gates.")
require("GITHUB_STEP_SUMMARY" in evidence and "SBOM" in evidence and "provenance" in evidence and "signature" in evidence and "verification" in evidence, "workflow emits Step Summary evidence", "summary missing evidence fields", "Expose evidence refs and verification result in the job summary.")

publish = re.search(r"\n  publish:\n(?P<body>[\s\S]+?)(?:\n  [A-Za-z0-9_-]+:|\Z)", text)
if publish:
    body = publish.group("body")
    require("release_evidence" in body and "security_scan" in body, "publish job depends on scan and release evidence", body[:500], "Final tag promotion must require scan and signed evidence gates for the same digest.")
PY
}

for fixture in \
  valid-evidence.json \
  missing-sbom.json \
  missing-provenance.json \
  missing-signature.json \
  missing-verification.json \
  verification-failed.json \
  wrong-cosign-identity.json \
  wrong-cosign-issuer.json \
  wrong-digest-signed.json \
  wrong-verification-output-digest.json \
  missing-attestation-output.json \
  missing-platform-digest-evidence.json; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 4.4 release evidence fixture exists" "missing" "Restore the complete release evidence fixture set."
    exit 1
  }
done

"${VALIDATOR}" --file "${FIXTURE_DIR}/valid-evidence.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "missing SBOM evidence" "sbom_ref|contains keys" "${VALIDATOR}" --file "${FIXTURE_DIR}/missing-sbom.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "missing provenance evidence" "provenance_ref|contains keys" "${VALIDATOR}" --file "${FIXTURE_DIR}/missing-provenance.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "missing signature evidence" "signature_ref|contains keys" "${VALIDATOR}" --file "${FIXTURE_DIR}/missing-signature.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "missing verification evidence" "verification_ref|contains keys" "${VALIDATOR}" --file "${FIXTURE_DIR}/missing-verification.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "verification failed" "verified is true" "${VALIDATOR}" --file "${FIXTURE_DIR}/verification-failed.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "wrong cosign identity" "expected_certificate_identity equals|verification_identity matches" "${VALIDATOR}" --file "${FIXTURE_DIR}/wrong-cosign-identity.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "wrong cosign issuer" "cosign_certificate_issuer is GitHub Actions OIDC|verification_issuer matches" "${VALIDATOR}" --file "${FIXTURE_DIR}/wrong-cosign-issuer.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "wrong digest signed" "signed_digest matches digest" "${VALIDATOR}" --file "${FIXTURE_DIR}/wrong-digest-signed.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "wrong verification output digest" "cosign verification output proves digest" "${VALIDATOR}" --file "${FIXTURE_DIR}/wrong-verification-output-digest.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "missing attestation output" "attestation_path exists" "${VALIDATOR}" --file "${FIXTURE_DIR}/missing-attestation-output.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"
expect_fail "missing platform digest evidence" "covers index_digest and every platform digest" "${VALIDATOR}" --file "${FIXTURE_DIR}/missing-platform-digest-evidence.json" --expected-certificate-identity "${EXPECTED_CERTIFICATE_IDENTITY}" --cosign-certificate-issuer "${COSIGN_CERTIFICATE_ISSUER}"

validate_release_evidence_workflow "${WORKFLOW}"
grep -Fq 'Release Evidence Schema' "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md" || {
  diag "grep release evidence schema" "cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md" "schema heading exists" "missing" "Regenerate docs so release evidence consumers have the schema."
  exit 1
}

printf 'PASS story-4.4 release evidence fixtures\n'
