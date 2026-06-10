#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/barman-plugin/fixtures"
REFERENCE="${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md"
REQUIRED_PHRASE="CloudNativePG Barman Cloud Plugin"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

expect_boundary_fail() {
  local description="$1"
  local pattern="$2"
  local fixture="$3"
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${VALIDATOR}" "${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-barman-boundary ${fixture}" "${description}" "fixture fails" "passed" "Reject legacy in-image Barman guidance and package examples."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-barman-boundary ${fixture}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep Barman boundary diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  for required in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "validate-barman-boundary ${fixture}" "${description}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Use the standard validation diagnostic shape."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

validate_barman_docs() {
  local doc="$1"
  local reference="${2:-${REFERENCE}}"
  python3 - "${doc}" "${reference}" <<'PY'
import re
import sys
from pathlib import Path

doc = Path(sys.argv[1])
reference = Path(sys.argv[2])
command = f"validate-barman-plugin-docs {doc}"
required_phrase = "CloudNativePG Barman Cloud Plugin"
image_repo = "ghcr.io/pnetcloud/cloudnative-pg-timescaledb"

def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {str(actual).replace(chr(10), ' ')[:280]}\n"
        f"remediation: {remediation}"
    )

def require(pattern, expected, remediation, flags=re.I | re.S):
    if not re.search(pattern, text, flags):
        fail(doc, expected, "missing", remediation)

def reject(pattern, expected, remediation, flags=re.I | re.S):
    match = re.search(pattern, text, flags)
    if match:
        fail(doc, expected, match.group(0), remediation)

def legacy_barman_negated(sentence):
    patterns = [
        r"\b(?:do\s+not|must\s+not|does\s+not|never|no)\b.{0,120}\b(?:install|require|recommend|validate|use|run|ship|include|advertise|support)\b.{0,160}\bbarman(?:-cloud)?\b",
        r"\b(?:do\s+not|must\s+not|does\s+not|never|no)\b.{0,160}\bbarman(?:-cloud)?\b",
        r"\bno\b.{0,160}\blegacy\b.{0,160}\bin-image\b.{0,160}\bbarman(?:-cloud)?\b",
        r"\bnot\s+through\b.{0,120}\bbarman(?:-cloud)?\b",
        r"\bwithout\b.{0,120}\bbarman(?:-cloud)?\b",
        r"\bbarman(?:-cloud)?\b.{0,120}\b(?:not|never)\s+(?:supported|required|installed|included|used|validated|part)\b",
        r"\bbackup-tooling-free\b",
    ]
    return any(re.search(pattern, sentence) for pattern in patterns)

def reject_unless_negated(pattern, expected, remediation, flags=re.I | re.S):
    for match in re.finditer(pattern, text, flags):
        sentence_start = max(text.rfind(".", 0, match.start()), text.rfind("\n", 0, match.start())) + 1
        sentence_end_candidates = [idx for idx in [text.find(".", match.end()), text.find("\n", match.end())] if idx != -1]
        sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(text)
        sentence = text[sentence_start:sentence_end].lower()
        if legacy_barman_negated(sentence):
            continue
        fail(doc, expected, match.group(0), remediation)

def reference_field(label):
    pattern = rf"^{re.escape(label)}:\s+`([^`]+)`$"
    match = re.search(pattern, reference_text, re.M)
    if not match:
        fail(reference, f"generated reference contains {label}", "missing", "Regenerate cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md from versions.yaml.")
    return match.group(1)

def require_bound_reference(label, value, field):
    label_pattern = re.escape(label).replace(r"\ ", r"\s+")
    value_pattern = re.escape(value)
    patterns = [
        rf"(?:^|[\n|*-])\s*{label_pattern}\s*:?\s*`{value_pattern}`",
        rf"(?:^|[\n|*-])\s*{label_pattern}\s*:?\s*{value_pattern}(?:\s|$|[|])",
        rf"\|\s*{label_pattern}\s*\|\s*`{value_pattern}`\s*\|",
        rf"\|\s*{label_pattern}\s*\|\s*{value_pattern}\s*\|",
    ]
    if not any(re.search(pattern, text, re.I | re.M) for pattern in patterns):
        fail(doc, f"docs bind {field} to current generated value", "missing", "Keep public Barman reference fields synchronized with cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md.")

if not doc.exists():
    fail(doc, "Barman plugin documentation artifact exists", "missing", "Create docs/barman-plugin.md and README backup sections.")
if not reference.exists():
    fail(reference, "generated Barman plugin reference exists", "missing", "Run make generate to emit the Story 2.7 Barman reference artifact.")

text = doc.read_text()
reference_text = reference.read_text()
fields = {
    "release": reference_field("Release"),
    "manifest_url": reference_field("Manifest URL"),
    "plugin_image": reference_field("Plugin image"),
    "sidecar_image": reference_field("Sidecar image"),
}

if required_phrase not in text:
    fail(doc, f"docs include exact phrase {required_phrase!r}", "missing", "Identify the supported backup path with the canonical plugin name.")
for field, value in fields.items():
    if value not in text:
        fail(doc, f"docs include current generated barman_plugin.{field}", "missing", "Copy Barman plugin reference values only from the generated Story 2.7 artifact.")
require_bound_reference("Release", fields["release"], "barman_plugin.release")
require_bound_reference("Manifest URL", fields["manifest_url"], "barman_plugin.manifest_url")
require_bound_reference("Plugin image", fields["plugin_image"], "barman_plugin.plugin_image")
require_bound_reference("Sidecar image", fields["sidecar_image"], "barman_plugin.sidecar_image")

require(r"supported\s+v1\s+backup\s+integration\s+path|backup\s+integration\s+path.{0,120}supported\s+for\s+v1", "CloudNativePG Barman Cloud Plugin is the supported v1 backup integration path", "State the supported v1 backup integration path explicitly.")
require(r"PostgreSQL.{0,160}extension\s+runtime|extension\s+runtime.{0,160}PostgreSQL", "image scope is PostgreSQL and extension runtime contents", "Separate image runtime contents from backup plugin deployment.")
require(r"plugin\s+mechanisms?|deployed\s+through\s+CloudNativePG", "backup plugin deployment uses CloudNativePG plugin mechanisms", "Do not imply the PostgreSQL image deploys the plugin.")
require(r"imageName:\s*" + re.escape(image_repo) + r":(?:18|18-pg18\.4-ts2\.27\.2-20260609)\b", "direct image tag example remains compatible", "Keep backup guidance compatible with direct CloudNativePG imageName usage.")
require(r"imageCatalogRef", "generated catalog example remains compatible", "Keep backup guidance compatible with generated ClusterImageCatalog usage.")
require(r"kind:\s*ClusterImageCatalog", "catalog example references ClusterImageCatalog kind", "Use the generated catalog path from Story 5.3.")
require(r"name:\s*cloudnative-pg-timescaledb-standard-trixie", "catalog example references generated trixie catalog", "Use the primary generated catalog resource name.")
require(r"major:\s*18\b", "catalog example maps PostgreSQL major", "Map catalog examples to PostgreSQL majors explicitly.")

reject(r"imageName:\s*ghcr\.io/cloudnative-pg/plugin-barman-cloud(?::|@)", "plugin image is not used as the PostgreSQL Cluster imageName", "Keep plugin images in plugin deployment references, not database image examples.")
reject(r"imageName:\s*ghcr\.io/cloudnative-pg/plugin-barman-cloud-sidecar(?::|@)", "sidecar image is not used as the PostgreSQL Cluster imageName", "Keep sidecar images in plugin deployment references, not database image examples.")
reject_unless_negated(r"(?:apt-get\s+install|pip\s+install)[^\n]*(?:barman|barman-cloud)", "docs do not install legacy Barman tooling", "Replace legacy install commands with plugin deployment references.")
reject_unless_negated(r"(?:requires?|must\s+have|needs?|depends\s+on)[^\n.]{0,120}\bbarman-cloud\b", "docs do not require legacy in-image barman-cloud binaries", "Backup guidance must use the CloudNativePG Barman Cloud Plugin path.")
reject_unless_negated(r"(?:use|run|validate|ship|include|install)[^\n.]{0,120}\bbarman-cloud-(?:wal-archive|backup)\b", "docs do not advertise legacy barman-cloud commands", "Do not document legacy in-image Barman commands for v1.")
PY
}

expect_docs_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status
  tmp="$(mktemp)"
  set +e
  validate_barman_docs "${FIXTURE_DIR}/${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-barman-plugin-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "fixture fails" "passed" "Make the negative Barman docs fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-barman-plugin-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep Barman docs diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  for required in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "validate-barman-plugin-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Use the standard validation diagnostic shape."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

for fixture in \
  valid-plugin-docs.md \
  legacy-barman-cloud-install.md \
  legacy-barman-cloud-binary-required.md \
  missing-plugin-reference.md \
  wrong-plugin-image.md \
  direct-image-example-broken.md \
  valid-plugin-doc.md \
  legacy-barman-cloud-required.md \
  legacy-barman-cloud-instead-bypass.md \
  legacy-barman-cloud-negated-first-invalid-later.md \
  dockerfile-installs-barman-cloud \
  missing-plugin-phrase.md; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Barman docs fixture exists" "missing" "Restore the complete Barman docs fixture set."
    exit 1
  }
done

validate_barman_docs "${ROOT_DIR}/docs/barman-plugin.md"
validate_barman_docs "${ROOT_DIR}/README.md"
validate_barman_docs "${ROOT_DIR}/cloudnative-pg-timescaledb/README.md"
validate_barman_docs "${FIXTURE_DIR}/valid-plugin-docs.md"

expect_docs_fail legacy-barman-cloud-install.md "legacy Barman tooling|legacy barman-cloud commands|barman-cloud"
expect_docs_fail legacy-barman-cloud-binary-required.md "legacy in-image barman-cloud|barman-cloud"
expect_docs_fail missing-plugin-reference.md "CloudNativePG Barman Cloud Plugin|barman_plugin"
expect_docs_fail wrong-plugin-image.md "barman_plugin.plugin_image|plugin image"
expect_docs_fail direct-image-example-broken.md "direct image tag example|plugin image is not used|Cluster imageName"

"${VALIDATOR}" "${FIXTURE_DIR}/valid-plugin-doc.md" >/tmp/story-3-6-valid-plugin-doc.out
grep -Fq 'PASS validate-barman-boundary plugin path gates' /tmp/story-3-6-valid-plugin-doc.out || {
  diag "validate-barman-boundary valid-plugin-doc.md" "${FIXTURE_DIR}/valid-plugin-doc.md" "PASS marker" "$(cat /tmp/story-3-6-valid-plugin-doc.out)" "Accept docs that use the plugin path and reject legacy in-image backup tooling."
  exit 1
}

"${VALIDATOR}" >/tmp/story-3-6-repo-scan.out
grep -Fq 'PASS validate-barman-boundary plugin path gates' /tmp/story-3-6-repo-scan.out || {
  diag "validate-barman-boundary" "repository scan" "PASS marker" "$(cat /tmp/story-3-6-repo-scan.out)" "Keep generated Dockerfiles and docs within the plugin boundary."
  exit 1
}

expect_boundary_fail "legacy doc requires in-image barman-cloud" "barman-cloud|${REQUIRED_PHRASE}" "${FIXTURE_DIR}/legacy-barman-cloud-required.md"
expect_boundary_fail "legacy doc cannot bypass with bare instead" "barman-cloud|${REQUIRED_PHRASE}" "${FIXTURE_DIR}/legacy-barman-cloud-instead-bypass.md"
expect_boundary_fail "legacy doc cannot hide invalid later guidance behind an earlier negated mention" "barman-cloud|${REQUIRED_PHRASE}" "${FIXTURE_DIR}/legacy-barman-cloud-negated-first-invalid-later.md"
expect_boundary_fail "Dockerfile installs barman-cloud" "barman-cloud|legacy Barman" "${FIXTURE_DIR}/dockerfile-installs-barman-cloud"
expect_boundary_fail "doc missing required plugin phrase" "${REQUIRED_PHRASE}" "${FIXTURE_DIR}/missing-plugin-phrase.md"

if rg -n 'plugin-barman-cloud|CloudNativePG Barman Cloud Plugin|manifest.yaml' "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/smoke-test.sh" "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke" >/tmp/story-3-6-smoke-plugin-scan.out; then
  diag "rg plugin deployment in smoke checks" "cloudnative-pg-timescaledb/scripts/smoke-test.sh cloudnative-pg-timescaledb/tests/smoke" "smoke checks do not deploy or validate the Barman plugin" "$(cat /tmp/story-3-6-smoke-plugin-scan.out)" "Keep smoke checks focused on database runtime and extension behavior."
  exit 1
fi

printf 'PASS story-5.4 Barman plugin documentation fixtures\n'
