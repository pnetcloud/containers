#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/troubleshooting/fixtures"
DOC="${ROOT_DIR}/docs/troubleshooting.md"
CATALOG="${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

validate_troubleshooting_docs() {
  local doc="$1"
  local catalog="$2"
  python3 - "${doc}" "${catalog}" <<'PY'
import re
import sys
from pathlib import Path

doc = Path(sys.argv[1])
catalog = Path(sys.argv[2])
command = f"validate-troubleshooting-docs {doc} {catalog}"

required_reasons = [
    ("metadata.invalid", "invalid metadata"),
    ("generated.stale", "stale generated files"),
    ("package.unsupported-combination", "unsupported package combinations"),
    ("tag.policy-invalid", "wrong tag policy"),
    ("tag.latest-invalid", "wrong latest"),
    ("postgresql.pg19-experimental-policy", "PostgreSQL 19beta1 experimental failures"),
    ("build.docker-failed", "Docker build failures"),
    ("runtime.postgresql-startup-failed", "PostgreSQL startup failures"),
    ("smoke.sql-extension-failed", "SQL smoke failures"),
    ("evidence.sbom-missing", "missing SBOM"),
    ("evidence.provenance-missing", "missing provenance"),
    ("evidence.signature-missing", "missing signature"),
    ("scan.vulnerability-threshold-failed", "vulnerability threshold failures"),
    ("catalog.reference-invalid", "catalog reference failures"),
]
required_fields = [
    "reason_id",
    "category",
    "applies_to",
    "gate_or_command",
    "hard_fail",
    "publish_false_skip_reason_allowed",
    "local_command",
    "remediation",
    "trixie_bookworm_notes",
]

def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {str(actual).replace(chr(10), ' ')[:420]}\n"
        f"remediation: {remediation}"
    )

def read(path):
    if not path.exists():
        fail(path, "troubleshooting artifact exists", "missing", "Create the troubleshooting doc or generated failure reason catalog.")
    return path.read_text()

def require(pattern, expected, remediation, haystack=None, artifact=None, flags=re.I | re.S):
    value = combined if haystack is None else haystack
    target = artifact or "combined troubleshooting docs"
    if not re.search(pattern, value, flags):
        fail(target, expected, "missing", remediation)

def reject_gate_bypass(text):
    gate_terms = r"(?:scan|SBOM|provenance|signature|signing|publish|catalog|permissions|validation|release-blocking|release\s+gate|gate)"
    action_terms = r"(?:\bbypass\b|\bdisable\b|turn\s+off|\boverride\b|force\s+publish|temporarily\s+ignore|skip\s+(?:the\s+)?(?:scan|SBOM|provenance|signature|signing|publish|catalog|permissions|validation|gate)|mark\s+(?:the\s+)?(?:check|gate|validation)\s+passed)"
    for sentence in re.split(r"(?<=[.!?])\s+|\n+", text):
        if not re.search(action_terms + r".{0,100}" + gate_terms + r"|" + gate_terms + r".{0,100}" + action_terms, sentence, re.I):
            continue
        if re.search(r"\b(?:do\s+not|must\s+not|never|not\s+allowed|not\s+valid|reject|blocked|blocks)\b", sentence, re.I):
            continue
        fail("combined troubleshooting docs", "docs do not recommend bypassing release-blocking gates", sentence.strip(), "Tell maintainers to fix the failure or keep rows publish: false with skip_reason before release, not to bypass gates.")

doc_text = read(doc)
catalog_text = read(catalog)
combined = doc_text + "\n" + catalog_text

entries = {}
for match in re.finditer(r"^## `([^`]+)`\n(.*?)(?=^## `|\Z)", catalog_text, re.M | re.S):
    reason_id = match.group(1)
    body = match.group(2)
    if reason_id in entries:
        fail(catalog, "failure reason catalog reason_id values are unique", reason_id, "Remove duplicate failure reason entries.")
    entries[reason_id] = body

expected_ids = [reason for reason, _ in required_reasons]
actual_ids = list(entries)
missing_ids = [reason for reason in expected_ids if reason not in entries]
extra_ids = [reason for reason in actual_ids if reason not in expected_ids]
if missing_ids or extra_ids:
    fail(catalog, "failure reason catalog contains every required reason_id exactly once", {"missing": missing_ids, "extra": extra_ids}, "Regenerate failure-reason-catalog.md from the generator definitions.")

for reason_id, category in required_reasons:
    body = entries[reason_id]
    if f"`reason_id`: `{reason_id}`" not in body:
        fail(catalog, f"entry {reason_id} repeats its reason_id field", "missing", "Keep each catalog entry self-describing.")
    for field in required_fields:
        match = re.search(rf"^- `{re.escape(field)}`: (.+)$", body, re.M)
        if not match or not match.group(1).strip():
            fail(catalog, f"entry {reason_id} includes non-empty {field}", body, "Populate every required catalog field.")
    if not re.search(re.escape(category), combined, re.I):
        fail("combined troubleshooting docs", f"docs cover {category}", "missing", f"Add troubleshooting coverage for {reason_id}.")
    if not re.search(re.escape(reason_id), doc_text):
        fail(doc, f"public troubleshooting docs include reason_id {reason_id}", "missing", "Add each generated failure reason ID to docs/troubleshooting.md, not only to the generated catalog.")
    if not re.search(r"^- `hard_fail`: `(true|false)`$", body, re.M):
        fail(catalog, f"entry {reason_id} has boolean hard_fail", body, "Use true or false for hard_fail.")
    publish_line = re.search(r"^- `publish_false_skip_reason_allowed`: (.+)$", body, re.M).group(1)
    if not re.search(r"\b(?:Yes|No)\b", publish_line):
        fail(catalog, f"entry {reason_id} distinguishes hard-fail from publish false skip_reason", publish_line, "Start with Yes or No and explain the skip_reason rule.")
    notes = re.search(r"^- `trixie_bookworm_notes`: (.+)$", body, re.M).group(1)
    if notes.strip() != "same" and not re.search(r"trixie", notes, re.I) or (notes.strip() != "same" and not re.search(r"bookworm", notes, re.I)):
        fail(catalog, f"entry {reason_id} explicitly describes trixie/bookworm behavior", notes, "Use same or mention both Debian variants.")
    for field in ["local_command", "remediation"]:
        value = re.search(rf"^- `{field}`: (.+)$", body, re.M).group(1)
        if value.strip() in {"", "`"}:
            fail(catalog, f"entry {reason_id} has actionable {field}", value, "Add a concrete command or remediation.")

for evidence_id in ["evidence.sbom-missing", "evidence.provenance-missing", "evidence.signature-missing"]:
    if evidence_id not in entries:
        fail(catalog, f"{evidence_id} is validated independently", "missing", "Keep SBOM, provenance, and signature failure reasons separate.")

require(r"docs/generated/failure-reason-catalog\.md", "public troubleshooting docs reference the generated failure catalog", "Link operators to the generated failure reason catalog.", doc_text, doc)
require(r"publish:\s*false", "docs explain publish false handling", "Document rows that stay unpublished while preserving skip_reason.")
require(r"skip_reason", "docs explain skip_reason handling", "Document skip_reason for non-publishable combinations.")
require(r"hard_fail", "docs expose hard_fail semantics", "Document hard-fail behavior for release-blocking failures.")
require(r"trixie.{0,80}primary|primary.{0,80}trixie", "docs identify trixie as primary", "State that Debian trixie is the primary variant.", doc_text, doc)
require(r"bookworm.{0,80}secondary|secondary.{0,80}bookworm", "docs identify bookworm as secondary", "State that Debian bookworm is the secondary variant.", doc_text, doc)
reject_gate_bypass(combined)
PY
}

build_fixture_input() {
  local fixture="$1"
  local output="$2"
  python3 - "${FIXTURE_DIR}/valid-troubleshooting-docs.md" "${fixture}" "${output}" <<'PY'
import re
import sys
from pathlib import Path

valid = Path(sys.argv[1]).read_text()
fixture = Path(sys.argv[2])
target = Path(sys.argv[3])
spec = fixture.read_text()

remove_match = re.search(r"^fixture_remove_reason_id:\s*([^\s]+)\s*$", spec, re.M)
if remove_match:
    reason_id = remove_match.group(1)
    updated = re.sub(rf"^## `{re.escape(reason_id)}`\n.*?(?=^## `|\Z)", "", valid, flags=re.M | re.S)
    if updated == valid:
        raise SystemExit(f"fixture directive did not remove {reason_id}")
    target.write_text(updated)
    sys.exit(0)

append_match = re.search(r"^fixture_append_bad_content:\s*$\n(.*)", spec, re.M | re.S)
if append_match:
    target.write_text(valid + "\n" + append_match.group(1).strip() + "\n")
    sys.exit(0)

target.write_text(spec)
PY
}

expect_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp input status
  tmp="$(mktemp)"
  input="$(mktemp)"
  build_fixture_input "${FIXTURE_DIR}/${fixture}" "${input}"
  set +e
  validate_troubleshooting_docs "${input}" "${input}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-troubleshooting-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "fixture fails" "passed" "Make the negative troubleshooting fixture fail on its intended invariant."
    rm -f "${tmp}" "${input}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-troubleshooting-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep troubleshooting docs diagnostics deterministic and actionable."
    rm -f "${tmp}" "${input}"
    exit 1
  fi
  for required in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "validate-troubleshooting-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Use the standard validation diagnostic shape."
      rm -f "${tmp}" "${input}"
      exit 1
    fi
  done
  rm -f "${tmp}" "${input}"
}

fixtures=(
  valid-troubleshooting-docs.md
  missing-invalid-metadata.md
  missing-stale-generated-files.md
  missing-unsupported-package-combinations.md
  missing-wrong-tag-policy.md
  missing-wrong-latest.md
  missing-pg19-experimental.md
  missing-build-failure.md
  missing-postgresql-startup-failure.md
  missing-sql-smoke-failure.md
  missing-evidence-sbom-missing.md
  missing-evidence-provenance-missing.md
  missing-evidence-signature-missing.md
  missing-vulnerability-failure.md
  missing-catalog-failure.md
  recommends-bypassing-release-gate.md
)

for fixture in "${fixtures[@]}"; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 5.8 fixture exists" "missing" "Restore the complete troubleshooting fixture set."
    exit 1
  }
done

validate_troubleshooting_docs "${DOC}" "${CATALOG}"
validate_troubleshooting_docs "${FIXTURE_DIR}/valid-troubleshooting-docs.md" "${FIXTURE_DIR}/valid-troubleshooting-docs.md"

expect_fail missing-invalid-metadata.md "metadata\.invalid|required reason_id"
expect_fail missing-stale-generated-files.md "generated\.stale|required reason_id"
expect_fail missing-unsupported-package-combinations.md "package\.unsupported-combination|required reason_id"
expect_fail missing-wrong-tag-policy.md "tag\.policy-invalid|required reason_id"
expect_fail missing-wrong-latest.md "tag\.latest-invalid|required reason_id"
expect_fail missing-pg19-experimental.md "postgresql\.pg19-experimental-policy|required reason_id"
expect_fail missing-build-failure.md "build\.docker-failed|required reason_id"
expect_fail missing-postgresql-startup-failure.md "runtime\.postgresql-startup-failed|required reason_id"
expect_fail missing-sql-smoke-failure.md "smoke\.sql-extension-failed|required reason_id"
expect_fail missing-evidence-sbom-missing.md "evidence\.sbom-missing|required reason_id"
expect_fail missing-evidence-provenance-missing.md "evidence\.provenance-missing|required reason_id"
expect_fail missing-evidence-signature-missing.md "evidence\.signature-missing|required reason_id"
expect_fail missing-vulnerability-failure.md "scan\.vulnerability-threshold-failed|required reason_id"
expect_fail missing-catalog-failure.md "catalog\.reference-invalid|required reason_id"
expect_fail recommends-bypassing-release-gate.md "bypass|release-blocking gates"

printf 'PASS story-5.8 troubleshooting documentation fixtures\n'
