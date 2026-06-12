#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/verification/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

validate_verification_doc() {
  local doc="$1"
  python3 - "${doc}" <<'PY'
import re
import sys
from pathlib import Path

doc = Path(sys.argv[1])
command = f"validate-verification-docs {doc}"
repo = "ghcr.io/pnetcloud/cloudnative-pg-timescaledb"
issuer = "https://token.actions.githubusercontent.com"
identity = "https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main"

def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {doc}\n"
        f"expected: {expected}\n"
        f"actual: {str(actual).replace(chr(10), ' ')[:280]}\n"
        f"remediation: {remediation}"
    )

def require(pattern, expected, remediation, flags=re.I | re.S):
    if not re.search(pattern, text, flags):
        fail(expected, "missing", remediation)

def reject(pattern, expected, remediation, flags=re.I | re.S):
    match = re.search(pattern, text, flags)
    if match:
        fail(expected, match.group(0), remediation)

def shell_args(command_name):
    for raw in re.findall(rf"(?:^|\n)\s*{command_name}\s+([^\n]+)", command_text):
        yield raw

def option_values(option):
    values = []
    for args in shell_args(r"cosign\s+verify"):
        pattern = rf"{re.escape(option)}\s+(?:\"([^\"]+)\"|'([^']+)'|([^\s]+))"
        for match in re.finditer(pattern, args):
            values.append(next(group for group in match.groups() if group is not None))
    return values

if not doc.exists():
    fail("verification documentation artifact exists", "missing", "Create docs/user-guide/verifying-images.md and README security sections.")

text = doc.read_text()
command_text = re.sub(r"\\\s*\n\s*", " ", text)

require(re.escape(repo) + r"[^\n\s`]*@sha256:[0-9a-f]{64}", "examples verify immutable digest references", "Use ghcr.io/...@sha256:<digest>, not tags alone.")
require(r"cosign\s+verify", "cosign verification command is documented", "Show how to verify keyless signatures.")
issuer_values = option_values("--certificate-oidc-issuer")
if issuer not in issuer_values:
    fail("cosign issuer is GitHub Actions OIDC", issuer_values or "missing", "Require the GitHub Actions OIDC issuer.")
for value in issuer_values:
    if value != issuer:
        fail("cosign issuer is exactly GitHub Actions OIDC", value, "Do not use issuer prefixes or alternate OIDC issuers.")
require(r"--certificate-identity\s+\"?\$EXPECTED_CERTIFICATE_IDENTITY\"?", "cosign uses exact EXPECTED_CERTIFICATE_IDENTITY", "Use exact certificate identity derived from the release ref.")
identity_assignments = re.findall(r"EXPECTED_CERTIFICATE_IDENTITY=(?:\"([^\"]+)\"|'([^']+)'|([^\s`]+))", text)
identity_values = [next(group for group in match if group) for match in identity_assignments]
if identity not in identity_values:
    fail("docs show allowed build workflow certificate identity", identity_values or "missing", "Document the exact main-branch build workflow identity example.")
for value in identity_values:
    if value.startswith("https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main") and value != identity:
        fail("main branch certificate identity is exact", value, "Do not append wildcards or regex fragments to the main branch identity.")
require(r"EXPECTED_CERTIFICATE_IDENTITY=.*\.github/workflows/build\.yml@refs/(?:heads/main|tags/)", "certificate identity is derived from an allowed release ref", "Derive identity from the exact branch or release tag ref.")
reject(r"--certificate-identity-regexp|--certificate-regexp|--certificate-identity-regex", "broad certificate identity regex is not used", "Use exact --certificate-identity instead of regex identity matching.")

for command_name in [r"cosign\s+verify", r"trivy\s+image"]:
    for args in shell_args(command_name):
        for match in re.finditer(re.escape(repo) + r":([^\s`\"']+)", args):
            value = match.group(0)
            if "@sha256:" not in value:
                fail("verification examples do not use tag-only image references", value, "Verify immutable digest references.")
for match in re.finditer(r"(?:IMAGE_REF|image_ref)=(?:\"([^\"]+)\"|'([^']+)'|([^\s`]+))", text):
    value = next(group for group in match.groups() if group is not None)
    if value.startswith(repo + ":") and "@sha256:" not in value:
        fail("verification examples do not use tag-only image references", match.group(0), "Verify immutable digest references.")
reject(r"(?:GH_TOKEN|GITHUB_TOKEN|CR_PAT|PRIVATE_TOKEN|registry password|docker login|--password-stdin)", "public verification examples do not require private credentials or secrets", "Public GHCR image verification must work without private tokens.")

for term in ["SBOM", "provenance"]:
    require(rf"\b{term}\b", f"{term} evidence is documented", "Explain where release evidence attaches SBOM and provenance metadata.")
require(r"per_digest_evidence|index_digest|platform_digests", "SBOM and provenance map to index and platform digests", "Describe index_digest, platform_digests, and per_digest_evidence coverage.")
require(r"sbom_ref|provenance_ref|attestation", "SBOM/provenance refs are named", "Name the evidence fields users inspect.")
require(r"signature_ref|verification_ref|verified", "signature and verification evidence fields are named", "Name signature and verification evidence fields.")
require(r"missing.{0,120}(?:SBOM|provenance|signature|threshold-passing scan)|(?:SBOM|provenance|signature|threshold-passing scan).{0,120}release blocker", "missing evidence is documented as release blocker", "State that missing evidence blocks promotion.")

require(r"cloudnative-pg-timescaledb/config/vulnerability-policy\.yaml", "vulnerability policy file path is documented", "Point users to the policy source file.")
require(r"cloudnative-pg-timescaledb/config/vulnerability-ignore\.yaml", "vulnerability ignore file path is documented", "Point users to the explicit ignore file.")
require(r"trivy\s+image\s+--scanners\s+vuln\s+--severity\s+HIGH,CRITICAL", "Trivy command shape and threshold are documented", "Reproduce the required scanner command shape.")
require(r"--ignorefile\s+cloudnative-pg-timescaledb/config/vulnerability-ignore\.yaml", "Trivy ignore file is included", "Use the committed ignore policy file.")
require(r"--format\s+sarif\s+--output\s+<sarif>", "SARIF output command is documented", "Document SARIF output for code scanning.")
require(r"security-scan\.json|vulnerability-scan-json", "scanner JSON artifact is documented", "Tell users where scanner JSON is surfaced.")
require(r"security-scan\.sarif|vulnerability-scan-sarif", "SARIF artifact is documented", "Tell users where SARIF is surfaced.")
require(r"GITHUB_STEP_SUMMARY|Step Summary", "Step Summary scan result is documented", "Point users to workflow summaries.")
require(r"unignored\s+`?HIGH`?.{0,80}`?CRITICAL`?|`?HIGH`?.{0,80}`?CRITICAL`?.{0,120}fails", "HIGH/CRITICAL threshold failure is documented", "State that unignored HIGH or CRITICAL findings fail the gate.")
require(r"fail\s+closed|database.{0,120}fail", "scanner database fail-closed behavior is documented", "State that scanner DB failures block release.")
require(r"undeclared\s+ignores?.{0,80}reject", "undeclared ignores are rejected", "Do not tell users to bypass vulnerability policy.")
reject(r"\b(?:bypass|ignore)\b.{0,80}(?:HIGH|CRITICAL).{0,80}(?:normal|release)", "docs do not tell users to bypass vulnerability policy", "Only declared reviewed ignores are allowed.")

labels = [
    "org.opencontainers.image.source",
    "org.opencontainers.image.created",
    "org.pnet.postgresql.major",
    "org.pnet.postgresql.version",
    "org.pnet.debian.variant",
    "org.pnet.cnpg.tag",
    "org.pnet.cnpg.digest",
    "org.pnet.timescaledb.version",
    "org.pnet.timescaledb_toolkit.version",
]
for label in labels:
    require(re.escape(label), f"image label {label} is documented", "Document label-to-metadata mapping.")
require(r"versions\.yaml", "labels map back to versions.yaml", "Explain how labels map to metadata rows.")
require(r"source\s+revision|workflow\s+identity|org\.opencontainers\.image\.source", "source revision/source mapping is documented", "Document source repository and workflow identity linkage.")
require(r"release\s+date|org\.opencontainers\.image\.created", "release date label mapping is documented", "Document release date/created label mapping.")
PY
}

validate_root_verification_links() {
  local doc="$1"
  python3 - "${doc}" <<'PY'
import re
import sys
from pathlib import Path

doc = Path(sys.argv[1])
command = f"validate-root-verification-links {doc}"

def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {doc}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )

def require(pattern, expected, remediation, flags=re.I | re.S):
    if not re.search(pattern, text, flags):
        fail(expected, "missing", remediation)

if not doc.exists():
    fail("root README exists", "missing", "Keep root README available as the repository entrypoint.")
text = doc.read_text()
require(r"docs/user-guide/verifying-images\.md", "root README links to image verification guidance", "Keep detailed verification guidance in docs/user-guide/verifying-images.md and link to it from the root README.")
require(r"SECURITY\.md", "root README links to security reporting guidance", "Make sensitive reporting guidance discoverable from the root README.")
PY
}

expect_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status
  tmp="$(mktemp)"
  set +e
  validate_verification_doc "${FIXTURE_DIR}/${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-verification-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "fixture fails" "passed" "Make the negative verification docs fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-verification-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep verification docs diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  for required in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "validate-verification-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Use the standard validation diagnostic shape."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

for fixture in \
  valid-verification-docs.md \
  missing-cosign-issuer.md \
  missing-cosign-identity.md \
  tag-without-digest.md \
  private-token-required.md \
  missing-sbom-provenance.md \
  missing-vulnerability-policy.md \
  missing-label-metadata-mapping.md; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 5.5 fixture exists" "missing" "Restore the complete verification docs fixture set."
    exit 1
  }
done

validate_verification_doc "${ROOT_DIR}/docs/user-guide/verifying-images.md"
validate_root_verification_links "${ROOT_DIR}/README.md"
validate_verification_doc "${ROOT_DIR}/cloudnative-pg-timescaledb/README.md"
validate_verification_doc "${FIXTURE_DIR}/valid-verification-docs.md"

expect_fail missing-cosign-issuer.md "cosign issuer is GitHub Actions OIDC"
expect_fail missing-cosign-identity.md "exact EXPECTED_CERTIFICATE_IDENTITY|allowed build workflow certificate identity|broad certificate"
expect_fail tag-without-digest.md "tag-only|immutable digest"
expect_fail private-token-required.md "private credentials|secrets"
expect_fail missing-sbom-provenance.md "SBOM|provenance|per_digest_evidence"
expect_fail missing-vulnerability-policy.md "vulnerability policy|Trivy|HIGH|CRITICAL"
expect_fail missing-label-metadata-mapping.md "image label|versions.yaml"

printf 'PASS story-5.5 image verification documentation fixtures\n'
