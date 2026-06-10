#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/catalog/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

validate_catalog_doc() {
  local doc="$1"
  python3 - "${doc}" <<'PY'
import re
import sys
from pathlib import Path

doc = Path(sys.argv[1])
command = f"validate-catalog-docs {doc}"
repo = "ghcr.io/pnetcloud/cloudnative-pg-timescaledb"

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

def reject(pattern, expected, remediation, flags=re.I | re.S):
    match = re.search(pattern, text, flags)
    if match:
        fail(expected, match.group(0), remediation)

def reject_unless_negated(pattern, expected, remediation, flags=re.I | re.S):
    for match in re.finditer(pattern, text, flags):
        window = text[max(0, match.start() - 100):match.end() + 40].lower()
        if re.search(r"\b(?:never|not|no|without|must\s+not|do\s+not|does\s+not|avoid|instead\s+of|omits?|excluded?)\b", window):
            continue
        if re.search(r"prefer.{0,120}\bover\b", window):
            continue
        fail(expected, match.group(0), remediation)

def reject_unless_explicit_experimental_catalog(pattern, expected, remediation, flags=re.I | re.S):
    for match in re.finditer(pattern, text, flags):
        sentence_start = max(text.rfind(".", 0, match.start()), text.rfind("\n", 0, match.start())) + 1
        sentence_end_candidates = [idx for idx in [text.find(".", match.end()), text.find("\n", match.end())] if idx != -1]
        sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(text)
        sentence = text[sentence_start:sentence_end].lower()
        if re.search(r"\b(?:omit|omits|exclude|excludes|keep\s+it\s+out|must\s+not|do\s+not|unless\s+explicitly\s+marked)\b", sentence):
            continue
        if re.search(r"\b(?:experimental|preview)\s+(?:catalog|example|catalog\s+example)\b|\b(?:catalog\s+example|example)\s+(?:is\s+)?(?:experimental|preview)\b", sentence):
            continue
        fail(expected, match.group(0), remediation)

if not doc.exists():
    fail("catalog documentation artifact exists", "missing", "Create docs/catalog.md and README catalog sections.")

text = doc.read_text()

require(r"ClusterImageCatalog", "CloudNativePG ClusterImageCatalog usage is documented", "Document the CloudNativePG catalog resource users will apply or reference.")
require(r"cloudnative-pg-timescaledb/catalog/catalog-standard-trixie\.yaml", "primary trixie catalog path is documented", "Show how to apply or reference the generated trixie catalog.")
require(r"catalog-standard-trixie\.yaml.{0,160}\bprimary\b|\bprimary\b.{0,160}catalog-standard-trixie\.yaml", "trixie catalog is labeled primary", "Make Debian trixie the primary catalog path.")
require(r"cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm\.yaml", "secondary bookworm catalog path is documented", "Show how to apply or reference the generated bookworm catalog.")
require(r"catalog-standard-bookworm\.yaml.{0,180}\bsecondary\b|\bsecondary\b.{0,180}catalog-standard-bookworm\.yaml", "bookworm catalog is labeled secondary", "Make Debian bookworm clearly secondary.")
require(r"cloudnative-pg-timescaledb-standard-trixie", "trixie catalog resource name is documented", "Map catalog file paths to ClusterImageCatalog resource names.")
require(r"cloudnative-pg-timescaledb-standard-bookworm", "bookworm catalog resource name is documented", "Map catalog file paths to ClusterImageCatalog resource names.")
for major in ["17", "18"]:
    require(rf"major:\s*{major}\b|PostgreSQL\s+`?{major}`?.{{0,180}}major\s+`?{major}`?", f"PostgreSQL {major} maps to a catalog major", "Show how CloudNativePG major selection maps to catalog entries.")
require(r"imageCatalogRef", "Cluster examples use imageCatalogRef", "Use the CloudNativePG imageCatalogRef path for catalog consumption examples.")
require(r"kind:\s*ClusterImageCatalog", "imageCatalogRef names ClusterImageCatalog kind", "Include kind: ClusterImageCatalog in examples.")
require(r"name:\s*cloudnative-pg-timescaledb-standard-(?:trixie|bookworm)", "imageCatalogRef names a generated catalog", "Reference the generated catalog resource name.")
require(r"@sha256:[0-9a-f]{64}", "catalog examples use digest-pinned image references", "Prefer digest-pinned references after release metadata is available.")
require(r"(?:multi-platform\s+index|manifest-list)\s+digest|digest.{0,80}(?:multi-platform\s+index|manifest-list)", "catalog docs prefer published multi-platform index digests", "Document manifest-list digests rather than per-platform digests.")
require(r"release-complete.{0,120}published|published.{0,120}release-complete", "catalogs are generated from release-complete published images", "Document the release metadata gate for generated catalogs.")
require(r"unpublished.{0,120}(?:must\s+not|never|not\s+reference)|(?:must\s+not|never|not\s+reference).{0,120}unpublished", "catalogs must not reference unpublished images", "Warn that generated catalogs must only reference published images.")
require(r"wrong\s+PostgreSQL\s+majors?|wrong\s+Debian\s+variants?|missing\s+digests?|unsigned\s+digests?", "catalog invalid reference classes are documented", "Name the invalid catalog cases operators and maintainers must avoid.")

reject(r"(?:image|imageName):\s*" + re.escape(repo) + r":latest\b", "catalog examples do not use latest as the primary path", "Use imageCatalogRef or immutable digest-pinned catalog entries.")
reject_unless_negated(r"`?latest`?.{0,120}(?:primary|recommended|preferred|operator|CloudNativePG|catalog|imageCatalogRef)", "latest is not documented as the primary CloudNativePG catalog path", "Keep latest convenience-only, outside primary operator examples.")
reject_unless_negated(r"unpublished.{0,100}(?:allowed|accepted|valid|referenced|catalog)", "catalog docs do not allow unpublished image references", "Keep catalogs gated on published release metadata.")
reject_unless_negated(r"per-platform\s+digest.{0,120}(?:allowed|accepted|valid|used|catalog|release)", "catalog docs do not allow per-platform digests as release catalog references", "Use the published multi-platform index digest for catalogs.")
reject_unless_explicit_experimental_catalog(r"(?:stable|standard)\s+catalog.{0,200}19beta1|19beta1.{0,200}(?:stable|standard)\s+catalog", "stable catalog examples do not include PostgreSQL 19beta1", "Keep PG19 beta out of stable examples unless explicitly marked experimental.")
PY
}

expect_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status
  tmp="$(mktemp)"
  set +e
  validate_catalog_doc "${FIXTURE_DIR}/${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-catalog-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "fixture fails" "passed" "Make the negative catalog docs fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-catalog-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep catalog docs diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  for required in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "validate-catalog-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Use the standard validation diagnostic shape."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

for fixture in \
  valid-catalog-docs.md \
  missing-trixie-catalog.md \
  missing-bookworm-secondary.md \
  latest-primary-catalog-example.md \
  unpublished-catalog-reference.md \
  per-platform-digest-as-release-catalog.md \
  pg19beta1-stable-catalog-example.md; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 5.3 fixture exists" "missing" "Restore the complete catalog docs fixture set."
    exit 1
  }
done

validate_catalog_doc "${ROOT_DIR}/docs/catalog.md"
validate_catalog_doc "${ROOT_DIR}/README.md"
validate_catalog_doc "${ROOT_DIR}/cloudnative-pg-timescaledb/README.md"
validate_catalog_doc "${FIXTURE_DIR}/valid-catalog-docs.md"

expect_fail missing-trixie-catalog.md "primary trixie catalog path is documented|trixie catalog is labeled primary"
expect_fail missing-bookworm-secondary.md "secondary bookworm catalog path is documented|bookworm catalog is labeled secondary"
expect_fail latest-primary-catalog-example.md "catalog examples do not use latest|latest is not documented as the primary"
expect_fail unpublished-catalog-reference.md "do not allow unpublished|must not reference unpublished"
expect_fail per-platform-digest-as-release-catalog.md "do not allow per-platform digests|prefer published multi-platform"
expect_fail pg19beta1-stable-catalog-example.md "stable catalog examples do not include PostgreSQL 19beta1"

printf 'PASS story-5.3 catalog documentation fixtures\n'
