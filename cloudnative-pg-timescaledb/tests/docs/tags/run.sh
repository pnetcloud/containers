#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/tags/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

validate_tags_doc() {
  local doc="$1"
  python3 - "${doc}" <<'PY'
import re
import sys
from pathlib import Path

doc = Path(sys.argv[1])
command = f"validate-tag-docs {doc}"
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
        window = text[max(0, match.start() - 80):match.end()].lower()
        if re.search(r"\b(?:never|not|no|without|must\s+not|do\s+not|does\s+not)\b", window):
            continue
        fail(expected, match.group(0), remediation)

if not doc.exists():
    fail("tag documentation artifact exists", "missing", "Create docs/image-tags.md and README tag sections.")

text = doc.read_text()
require(r"18-pg18\.4-ts2\.27\.2-20260609", "primary trixie immutable date tag is documented", "Document immutable trixie tags as {major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}.")
require(r"18-pg18\.4-ts2\.27\.2-20260609-bookworm", "secondary bookworm immutable tag uses -bookworm suffix", "Append -bookworm to secondary Debian immutable tags.")
require(r"\b18-bookworm\b", "secondary rolling tag uses -bookworm suffix", "Document rolling secondary tags such as 18-bookworm.")
require(r"\b(?:17|18)\b.{0,120}(?:trixie|primary)|(?:trixie|primary).{0,120}\b(?:17|18)\b", "primary rolling major tags are tied to trixie", "Explain that unsuffixed rolling major tags are for trixie only.")
require(r"`latest`.{0,100}convenience-only|convenience-only.{0,100}`latest`", "latest is convenience-only", "Do not document latest as a primary operator tag.")
require(r"`latest`.{0,120}(?:points\s+only\s+to|points\s+to|only\s+for).{0,80}PostgreSQL\s+`?18`?.{0,80}(?:Debian\s+)?`?trixie`?", "latest points only to PostgreSQL 18 trixie", "Keep latest pinned to the current primary line.")
require(r"PostgreSQL\s+`?19beta1`?.{0,120}experimental|experimental.{0,120}PostgreSQL\s+`?19beta1`?", "PostgreSQL 19beta1 is experimental", "Mark preview PostgreSQL tags as experimental.")
require(r"19beta1-pg19beta1-ts2\.27\.2-20260609", "PostgreSQL 19beta1 uses experimental immutable tags", "Use immutable preview tags for PostgreSQL 19beta1 examples.")
require(r"imageName:\s*" + re.escape(repo) + r":(?:18|18-pg18\.4-ts2\.27\.2-20260609|18-bookworm|18-pg18\.4-ts2\.27\.2-20260609-bookworm)\b", "CloudNativePG imageName examples use major-prefixed non-latest tags", "Use immutable or rolling major-prefixed imageName examples.")

reject(r"imageName:\s*" + re.escape(repo) + r":latest\b", "CloudNativePG imageName examples do not use latest", "Use immutable or major-prefixed tags in operator manifests.")
reject_unless_negated(r"`latest`.{0,100}(?:points\s+to|targets|tracks|can\s+point\s+to|published\s+for|receives?|gets?|uses?|includes?|available\s+for).{0,100}(?:bookworm|18-bookworm|pg18\.4-ts2\.27\.2-20260609-bookworm)", "latest is never documented for bookworm", "Use -bookworm tags without latest for secondary Debian images.")
reject_unless_negated(r"`latest`.{0,100}(?:points\s+to|targets|tracks|can\s+point\s+to|published\s+for|receives?|gets?|uses?|includes?|available\s+for).{0,100}(?:PostgreSQL\s+`?17`?|\b17\b)", "latest is never documented for PostgreSQL 17", "Keep latest assigned only to PostgreSQL 18 trixie.")
reject_unless_negated(r"`latest`.{0,100}(?:points\s+to|targets|tracks|can\s+point\s+to|published\s+for|receives?|gets?|uses?|includes?|available\s+for).{0,100}(?:PostgreSQL\s+`?19beta1`?|19beta1)", "latest is never documented for PostgreSQL 19beta1", "Do not assign latest to experimental PostgreSQL preview rows.")
reject(r"(?:bookworm|secondary)[^\n.]{0,120}\b18-pg18\.4-ts2\.27\.2-20260609\b(?!-bookworm)", "bookworm immutable examples include -bookworm suffix", "Append -bookworm to bookworm immutable tags.")
reject(r"\b18-pg18\.4-ts2\.27\.2\b(?!-[0-9]{8})", "immutable examples include UTC date suffix", "Use {major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}.")
reject_unless_negated(r"imageName:\s*" + re.escape(repo) + r":19beta1\b|(?:PostgreSQL\s+`?19beta1`?|19beta1).{0,100}(?:receives?|gets?|uses?|includes?|publishes?|is\s+published\s+with).{0,100}(?:normal\s+)?rolling\s+tag\s+`?19beta1`?|(?:normal|rolling).{0,80}(?:tag|tags).{0,80}`?19beta1`?.{0,80}(?:available|published|supported|included)", "PostgreSQL 19beta1 has no normal rolling tag", "Use only experimental immutable tags for PostgreSQL 19beta1.")
PY
}

expect_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status
  tmp="$(mktemp)"
  set +e
  validate_tags_doc "${FIXTURE_DIR}/${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-tag-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "fixture fails" "passed" "Make the negative tag docs fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-tag-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep tag docs diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

validate_tags_doc "${ROOT_DIR}/docs/image-tags.md"
validate_tags_doc "${ROOT_DIR}/README.md"
validate_tags_doc "${ROOT_DIR}/cloudnative-pg-timescaledb/README.md"
validate_tags_doc "${FIXTURE_DIR}/valid-tags.md"

expect_fail latest-primary-example.md "imageName examples do not use latest"
expect_fail latest-bookworm.md "latest is never documented for bookworm"
expect_fail latest-pg17.md "latest is never documented for PostgreSQL 17"
expect_fail latest-pg19beta1.md "latest is never documented for PostgreSQL 19beta1"
expect_fail bookworm-missing-suffix.md "bookworm immutable examples include -bookworm suffix|secondary bookworm immutable tag uses -bookworm suffix"
expect_fail missing-immutable-date-tag.md "immutable examples include UTC date suffix|primary trixie immutable date tag is documented"
expect_fail pg19beta1-normal-tag.md "PostgreSQL 19beta1 has no normal rolling tag"

printf 'PASS story-5.2 tag documentation fixtures\n'
