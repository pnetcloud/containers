#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb"
METADATA_FILE="${PROJECT_DIR}/versions.yaml"
README_FILE="${PROJECT_DIR}/README.md"
GENERATED_DOCS_FILE="${ROOT_DIR}/docs/generated-files.md"
FIXTURE_DIR="${PROJECT_DIR}/tests/fixtures"

fail() {
  diag "story-1.1" "n/a" "validation passes" "$*" "Fix the failing Story 1.1 validation condition." >&2
  exit 1
}

run_py() {
  python3 - "$@"
}

diag() {
  local command="$1"
  local artifact="$2"
  local expected="$3"
  local actual="$4"
  local remediation="$5"
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' \
    "$command" "$artifact" "$expected" "$actual" "$remediation"
}

validate_metadata() {
  local file="$1"
  run_py "$file" <<'PY'
from pathlib import Path
import re
import sys

def diag(command, artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )

path = Path(sys.argv[1])
command = f"validate_metadata {path}"

def parse_scalar(raw):
    value = raw.strip()
    if value == "":
        return ""
    if value in {"[]", "{}"}:
        return [] if value == "[]" else {}
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if inner == "":
            return []
        return [parse_scalar(part.strip()) for part in inner.split(",")]
    if value in {"true", "false"}:
        return value == "true"
    if value in {"null", "~"}:
        return None
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    if re.fullmatch(r"-?(0|[1-9][0-9]*)", value):
        return int(value)
    return value

def parse_mapping_item(text, line_no):
    if ":" not in text:
        diag(command, str(path), "parseable Story 1.1 YAML subset", f"line {line_no}: {text!r}", "Use simple key/value YAML for metadata fixtures.")
    key, raw_value = text.split(":", 1)
    return key.strip(), parse_scalar(raw_value)

def parse_versions_yaml(text):
    data = {}
    current_top = None
    current_entry = None

    def assign_mapping(target, key, value, line_no, scope):
        if key in target:
            diag(command, str(path), "unique YAML mapping keys", f"duplicate key {key!r} at line {line_no} in {scope}", "Remove duplicate metadata keys so the source of truth is unambiguous.")
        target[key] = value

    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.rstrip()
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        text = line.lstrip(" ")
        if indent == 0:
            key, value = parse_mapping_item(text, line_no)
            if text.endswith(":"):
                value = [] if key == "entries" else {}
            assign_mapping(data, key, value, line_no, "top-level metadata")
            current_top = key if isinstance(value, (dict, list)) else None
            current_entry = None
            continue
        if indent == 2 and current_top == "entries":
            if not text.startswith("- "):
                diag(command, str(path), "entries list item", f"line {line_no}: {text!r}", "Use '- key: value' entries.")
            rest = text[2:].strip()
            if ":" not in rest:
                data["entries"].append(parse_scalar(rest))
                current_entry = None
                continue
            current_entry = {}
            data["entries"].append(current_entry)
            key, value = parse_mapping_item(rest, line_no)
            assign_mapping(current_entry, key, value, line_no, "entries[] item")
            continue
        if indent == 2 and isinstance(data.get(current_top), dict):
            key, value = parse_mapping_item(text, line_no)
            assign_mapping(data[current_top], key, value, line_no, current_top)
            continue
        if indent == 4 and current_top == "entries" and isinstance(current_entry, dict):
            key, value = parse_mapping_item(text, line_no)
            assign_mapping(current_entry, key, value, line_no, "entries[] item")
            continue
        diag(command, str(path), "parseable Story 1.1 YAML subset", f"line {line_no}: {line!r}", "Use the schema indentation shown in versions.yaml.")
    return data

try:
    data = parse_versions_yaml(path.read_text())
except Exception as exc:
    diag(command, str(path), "parseable YAML mapping", f"parse error: {exc}", "Fix YAML syntax.")

if not isinstance(data, dict):
    diag(command, str(path), "top-level YAML mapping", type(data).__name__, "Use mapping keys schema_version, image, allowed, and entries.")

required_top = {"schema_version", "image", "allowed", "entries"}
missing_top = sorted(required_top - set(data))
if missing_top:
    diag(command, str(path), f"top-level keys include {sorted(required_top)}", f"missing {missing_top}", "Add missing top-level metadata keys.")
extra_top = sorted(set(data) - required_top)
if extra_top:
    diag(command, str(path), f"top-level keys exactly {sorted(required_top)}", f"extra {extra_top}", "Remove unknown top-level metadata keys.")
if data.get("schema_version") != "1":
    diag(command, str(path), "schema_version == '1'", repr(data.get("schema_version")), "Set schema_version to string '1'.")

allowed = data["allowed"]
if not isinstance(allowed, dict):
    diag(command, str(path), "allowed is mapping", type(allowed).__name__, "Set allowed to a mapping with postgres_majors, debian_variants, and platforms.")
expected_allowed = {
    "postgres_majors": ["17", "18", "19beta1"],
    "debian_variants": ["trixie", "bookworm"],
    "platforms": ["linux/amd64", "linux/arm64"],
}
extra_allowed = sorted(set(allowed) - set(expected_allowed))
if extra_allowed:
    diag(command, str(path), f"allowed keys exactly {sorted(expected_allowed)}", f"extra {extra_allowed}", "Remove unknown allowed metadata keys.")
for key, expected in expected_allowed.items():
    if allowed.get(key) != expected:
        diag(command, str(path), f"allowed.{key} == {expected!r}", repr(allowed.get(key)), "Use the Story 1.1 allowed metadata values.")

image = data["image"]
if not isinstance(image, dict):
    diag(command, str(path), "image is mapping", type(image).__name__, "Set image to a mapping with registry, repository, current_major, and primary_debian_variant.")
expected_image_keys = {"registry", "repository", "current_major", "primary_debian_variant"}
extra_image = sorted(set(image) - expected_image_keys)
if extra_image:
    diag(command, str(path), f"image keys exactly {sorted(expected_image_keys)}", f"extra {extra_image}", "Remove unknown image metadata keys.")
for field, expected in {"registry": "ghcr.io", "repository": "pnetcloud/cloudnative-pg-timescaledb"}.items():
    value = image.get(field)
    if not isinstance(value, str) or value == "":
        diag(command, str(path), f"image.{field} is non-empty string", repr(value), f"Set image.{field} to the scaffold repository value.")
    if value != expected:
        diag(command, str(path), f"image.{field} == {expected!r}", repr(value), f"Set image.{field} to {expected!r}.")
if image.get("current_major") != "18":
    diag(command, str(path), "image.current_major == '18'", repr(image.get("current_major")), "Set current_major to '18'.")
if image.get("primary_debian_variant") != "trixie":
    diag(command, str(path), "image.primary_debian_variant == trixie", repr(image.get("primary_debian_variant")), "Set primary_debian_variant to trixie.")

entries = data["entries"]
if not isinstance(entries, list) or not entries:
    diag(command, str(path), "entries is a non-empty list", type(entries).__name__, "Define the six required initial entries.")

required_entry = {
    "pg_major",
    "pg_version",
    "debian_variant",
    "cnpg_tag",
    "cnpg_digest",
    "timescaledb_version",
    "timescaledb_package_version",
    "toolkit_version",
    "toolkit_package_version",
    "platforms",
    "publish",
    "experimental",
    "latest_eligible",
    "skip_reason",
}
expected_entries = {
    ("17", "trixie"),
    ("18", "trixie"),
    ("19beta1", "trixie"),
    ("17", "bookworm"),
    ("18", "bookworm"),
    ("19beta1", "bookworm"),
}
seen = set()
resolver_owned = {
    "cnpg_digest",
    "timescaledb_version",
    "timescaledb_package_version",
    "toolkit_version",
    "toolkit_package_version",
}
string_fields = {
    "pg_major",
    "pg_version",
    "debian_variant",
    "cnpg_tag",
    "cnpg_digest",
    "timescaledb_version",
    "timescaledb_package_version",
    "toolkit_version",
    "toolkit_package_version",
    "skip_reason",
}
bool_fields = {"publish", "experimental", "latest_eligible"}

for idx, entry in enumerate(entries):
    if not isinstance(entry, dict):
        diag(command, str(path), f"entries[{idx}] is mapping", type(entry).__name__, "Set every entry to a YAML mapping.")
    missing = sorted(required_entry - set(entry))
    if missing:
        diag(command, str(path), f"entries[{idx}] contains all required fields", f"missing {missing}", "Add the missing required entry fields.")
    extra_entry = sorted(set(entry) - required_entry)
    if extra_entry:
        diag(command, str(path), f"entries[{idx}] keys exactly {sorted(required_entry)}", f"extra {extra_entry}", "Remove unknown entry metadata keys.")
    for field in string_fields:
        if not isinstance(entry[field], str):
            diag(command, str(path), f"entries[{idx}].{field} is string", type(entry[field]).__name__, f"Set {field} to a YAML string.")
    for field in bool_fields:
        if not isinstance(entry[field], bool):
            diag(command, str(path), f"entries[{idx}].{field} is boolean", type(entry[field]).__name__, f"Set {field} to true or false without quotes.")
    if not isinstance(entry["platforms"], list) or not entry["platforms"]:
        diag(command, str(path), f"entries[{idx}].platforms is non-empty list", type(entry["platforms"]).__name__, "Set platforms to a non-empty YAML list.")
    non_string_platforms = [repr(platform) for platform in entry["platforms"] if not isinstance(platform, str)]
    if non_string_platforms:
        diag(command, str(path), f"entries[{idx}].platforms contains only strings", repr(non_string_platforms), "Use platform strings such as linux/amd64.")
    bad_platforms = sorted(set(entry["platforms"]) - set(expected_allowed["platforms"]))
    if bad_platforms:
        diag(command, str(path), f"platforms subset of {expected_allowed['platforms']}", repr(bad_platforms), "Use only linux/amd64 and linux/arm64.")
    if entry["platforms"] != expected_allowed["platforms"]:
        diag(command, str(path), f"platforms exactly {expected_allowed['platforms']}", repr(entry["platforms"]), "Keep both linux/amd64 and linux/arm64 in each scaffold row.")
    key = (entry["pg_major"], entry["debian_variant"])
    if key in seen:
        diag(command, str(path), "no duplicate pg_major/debian_variant rows", repr(key), "Remove duplicate metadata entry.")
    seen.add(key)
    if entry["pg_major"] not in expected_allowed["postgres_majors"]:
        diag(command, str(path), f"pg_major in {expected_allowed['postgres_majors']}", repr(entry["pg_major"]), "Use only supported PostgreSQL majors.")
    if entry["debian_variant"] not in expected_allowed["debian_variants"]:
        diag(command, str(path), f"debian_variant in {expected_allowed['debian_variants']}", repr(entry["debian_variant"]), "Use only trixie or bookworm.")
    if entry["pg_version"] != entry["pg_major"]:
        diag(command, str(path), "pg_version matches pg_major in Story 1.1 scaffold", f"pg_major={entry['pg_major']!r}, pg_version={entry['pg_version']!r}", "Use the PostgreSQL major as the scaffold pg_version until resolver stories populate exact versions.")
    expected_cnpg_tag = f"{entry['pg_major']}-standard-{entry['debian_variant']}"
    if entry["cnpg_tag"] != expected_cnpg_tag:
        diag(command, str(path), f"cnpg_tag == {expected_cnpg_tag!r}", repr(entry["cnpg_tag"]), "Use the scaffold CNPG tag format {pg_major}-standard-{debian_variant}.")
    if entry["pg_major"] == "19beta1" and entry["experimental"] is not True:
        diag(command, str(path), "19beta1 entries set experimental true", repr(entry["experimental"]), "Set experimental: true for PostgreSQL 19beta1.")
    if entry["pg_major"] != "19beta1" and entry["experimental"] is not False:
        diag(command, str(path), "stable PostgreSQL entries set experimental false", f"pg_major={entry['pg_major']!r}, experimental={entry['experimental']!r}", "Set experimental false for PostgreSQL 17 and 18 scaffold rows.")
    if entry["publish"] is not False:
        diag(command, str(path), "publish false in Story 1.1 scaffold", repr(entry["publish"]), "Leave publish false until resolver and release stories make rows publishable.")
    expected_latest = key == ("18", "trixie")
    if entry["latest_eligible"] is not expected_latest:
        diag(command, str(path), "latest_eligible true only for 18-trixie", f"key={key!r}, latest_eligible={entry['latest_eligible']!r}", "Set only the 18-trixie row latest_eligible true.")
    non_empty_resolver = {field: entry[field] for field in resolver_owned if entry[field] != ""}
    if non_empty_resolver:
        diag(command, str(path), "resolver-owned fields empty in Story 1.1 scaffold", repr(non_empty_resolver), "Leave resolver-owned values empty until Story 2 resolvers populate them.")
    if any(entry[field] == "" for field in resolver_owned):
        if entry["publish"] is not False or entry["skip_reason"].strip() == "":
            diag(command, str(path), "empty resolver-owned values require publish=false and non-empty skip_reason", f"publish={entry['publish']!r}, skip_reason={entry['skip_reason']!r}", "Set publish false and explain skip_reason until resolvers populate values.")
    if entry["cnpg_tag"] == "":
        diag(command, str(path), "cnpg_tag is scaffolded", "empty string", "Set a non-empty scaffold CNPG tag.")

if seen != expected_entries:
    diag(command, str(path), f"entries exactly {sorted(expected_entries)}", sorted(seen), "Define exactly the six required initial PG/Debian entries.")
PY
}

validate_docs_source_of_truth() {
  local file="$1"
  local require_positive="${2:-1}"
  run_py "$file" "$require_positive" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
require_positive = sys.argv[2] == "1"
text = path.read_text()
def diag(expected, actual, remediation):
    raise SystemExit(
        f"command: validate_docs_source_of_truth {path}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )
sentences = re.split(r"(?<=[.!?])\s+", text)
def directly_negates_source_claim(sentence):
    return re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b.{0,40}\b(?:not|never)\b.{0,20}\b(?:an?\s+)?(?:independent\s+)?hand-edited sources? of truth\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:must not|must never|should not|should never|do not|does not|never)\b.{0,30}\b(?:become|be|remain)\b.{0,30}\b(?:an?\s+)?(?:independent\s+)?hand-edited sources? of truth\b",
        sentence,
        re.I,
    )

def contradicts_versions_claim(sentence):
    return re.search(
        r"versions\.yaml.{0,80}\b(?:not|never|no longer|isn't|is not|ceases to be|stops being)\b.{0,80}\bonly hand-edited source",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:not|never|no longer|isn't|is not|ceases to be|stops being)\b.{0,80}versions\.yaml.{0,80}only hand-edited source",
        sentence,
        re.I,
    )

versions_positive = any(
    re.search(r"versions\.yaml.{0,80}\bis\b.{0,20}\bthe only hand-edited source of truth\b", sentence, re.I)
    and not contradicts_versions_claim(sentence)
    for sentence in sentences
)
if require_positive and not versions_positive:
    diag("versions.yaml named as the only hand-edited source of truth", "required phrase missing", "Document versions.yaml as the only hand-edited source of truth.")
for sentence in sentences:
    if contradicts_versions_claim(sentence):
        diag("versions.yaml remains the only hand-edited source of truth", sentence.strip(), "Remove contradictory source-of-truth language.")
terms = [
    r"Dockerfiles?",
    r"Docker Bake definitions?",
    r"workflow matrices",
    r"GitHub Actions matrix",
    r"workflow matrix",
    r"CI matrix data",
    r"catalogs?",
    r"catalog manifests",
    r"ClusterImageCatalog manifests",
    r"generated docs?",
    r"generated documentation",
    r"README tables?",
    r"compatibility tables?",
    r"examples?",
    r"image tags?",
]
for term in terms:
    for sentence in sentences:
        if not re.search(term, sentence, re.I):
            continue
        bad_patterns = [
            r"\b(?:is|are|becomes?|remain)\b.{0,40}\b(?:an?\s+)?(?:independent|separate|also|another)?\s*(?:hand-edited\s+)?sources? of truth\b",
            r"\b(?:maintained by hand|manually edited|edited by hand)\b.{0,80}\bsources? of truth\b",
            r"\bcanonical source\b.{0,80}\b(?:edited by hand|manually edited|maintained by hand)\b",
            r"\b(?:edited by hand|manually edited|maintained by hand)\b.{0,80}\bcanonical source\b",
            r"\bsources? of truth\b.{0,80}\b(?:edited by hand|manually edited|maintained by hand)\b",
        ]
        for clause in re.split(r";|\bbut\b|,\s*(?:and\s+)?", sentence):
            if not re.search(term, clause, re.I):
                continue
            if directly_negates_source_claim(clause):
                continue
            if any(re.search(pattern, clause, re.I) for pattern in bad_patterns):
                diag("no generated artifact category is a hand-edited source of truth", clause.strip(), "Make generated artifacts derived from versions.yaml.")
for sentence in sentences:
    if directly_negates_source_claim(sentence):
        continue
    if re.search(r"versions\.yaml.{0,80}\bthe only hand-edited source of truth\b", sentence, re.I):
        continue
    if re.search(r"\bhand-edited sources? of truth\b", sentence, re.I):
        diag("only versions.yaml is a hand-edited source of truth", sentence.strip(), "Remove competing hand-edited source-of-truth language.")
PY
}

validate_no_vendor_build_context() {
  local file="$1"
  run_py "$file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
def diag(expected, actual, remediation):
    raise SystemExit(
        f"command: validate_no_vendor_build_context {path}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )
patterns = [
    r"\b(?:COPY|ADD)\b[^\n]*(?:\./)?vendor(?:/|\"|\s|$)",
    r"\b(?:cp|rsync)\b.{0,80}(?:\./)?vendor(?:/|\s|$)",
    r"\bdocker\s+(?:build|buildx\s+build)\b[^\n]*(?:-f|--file)\s+(?:[^\s\"']*/)?vendor/",
    r"\bdocker\s+(?:build|buildx\s+build)\b.{0,80}(?:\./)?vendor/?\b",
    r"[\"']?dockerfile[\"']?\s*[:=]\s*[\"']?(?:[^\n\"']*/)?vendor/",
    r"[\"']?context[\"']?\s*[:=]\s*[\"']?(?:[^\n\"']*/)?vendor/?\b",
    r"\bbuild context\s+(?:\./)?vendor/?\b",
    r"\bruntime (?:inputs?|dependenc(?:y|ies))\s+(?:\./)?vendor/?\b",
    r"\bcopied source tree\s+(?:\./)?vendor/?\b",
    r"\bpackage source\s+(?:\./)?vendor/?\b",
    r"(?:\./)?vendor/.{0,80}(?:runtime inputs?|runtime dependenc(?:y|ies)|copied source tree|package source)",
]
safe_negations = [
    r"\b(?:do not|don't|must not|never|avoid|forbidden to)\s+(?:run\s+)?docker\s+(?:build|buildx\s+build)\b[^\n]*(?:-f|--file)\s+(?:[^\s\"']*/)?vendor/",
    r"\b(?:do not|don't|must not|never|avoid|forbidden to)\s+(?:run\s+)?docker\s+(?:build|buildx\s+build)\b.{0,80}(?:\./)?vendor/?\b",
    r"\b(?:do not|don't|must not|never|avoid|forbidden to)\s+(?:copy|add|cp|rsync)\b.{0,80}(?:\./)?vendor(?:/|\s|$)",
    r"(?:\./)?vendor/.{0,80}\b(?:must not|must never|does not|do not|never)\b.{0,80}(?:runtime inputs?|runtime dependenc(?:y|ies)|copied source tree|package source)",
    r"\b(?:do not|don't|must not|never|avoid|forbidden to)\b.{0,80}(?:runtime inputs?|runtime dependenc(?:y|ies)|copied source tree|package source)\s+(?:\./)?vendor/?\b",
]
for pattern in patterns:
    for match in re.finditer(pattern, text, re.I):
        sentence_start = max(text.rfind("\n", 0, match.start()), text.rfind(".", 0, match.start())) + 1
        sentence_end_candidates = [idx for idx in [text.find("\n", match.end()), text.find(".", match.end())] if idx != -1]
        sentence_end = min(sentence_end_candidates) if sentence_end_candidates else len(text)
        sentence = text[sentence_start:sentence_end]
        if any(re.search(safe, sentence, re.I) for safe in safe_negations):
            continue
        diag("vendor/ is reference-only and not build/runtime/package input", f"matched {pattern}", "Remove production use of vendor/ and keep it as reference-only text.")
PY
}

expect_fail() {
  local description="$1"
  shift
  local expected_pattern=""
  if [[ "${1:-}" == "--contains" ]]; then
    expected_pattern="$2"
    shift 2
  fi
  local artifact="${*: -1}"
  test -f "${artifact}" || {
    diag "${*}" "${artifact}" "fixture exists" "missing" "Restore the required negative fixture before running Story 1.1 validation." >&2
    exit 1
  }
  local tmp
  tmp="$(mktemp)"
  if "$@" >"${tmp}" 2>&1; then
    cat "${tmp}" >&2 || true
    rm -f "${tmp}"
    diag "${*}" "${description}" "negative fixture fails" "negative fixture passed" "Update the validator or fixture so this invalid case is rejected." >&2
    exit 1
  fi
  if [[ -n "${expected_pattern}" ]] && ! grep -E -q "${expected_pattern}" "${tmp}"; then
    local actual
    actual="$(tr '\n' ' ' <"${tmp}")"
    rm -f "${tmp}"
    diag "${*}" "${description}" "failure diagnostic matches ${expected_pattern}" "${actual}" "Make this fixture fail on its intended invariant instead of an unrelated earlier validation rule." >&2
    exit 1
  fi
  rm -f "${tmp}"
}

git_product_files() {
  git -C "${ROOT_DIR}" ls-files -z --cached -- \
    ':(exclude)vendor/**' \
    ':(exclude)_bmad/**' \
    ':(exclude)_bmad-output/**' \
    ':(exclude).agents/**' \
    ':(exclude)cloudnative-pg-timescaledb/tests/**'
}

test -f "${METADATA_FILE}" || { diag "test -f ${METADATA_FILE}" "${METADATA_FILE}" "file exists" "missing" "Create cloudnative-pg-timescaledb/versions.yaml."; exit 1; }
test -f "${README_FILE}" || { diag "test -f ${README_FILE}" "${README_FILE}" "file exists" "missing" "Create cloudnative-pg-timescaledb/README.md."; exit 1; }
test -f "${GENERATED_DOCS_FILE}" || { diag "test -f ${GENERATED_DOCS_FILE}" "${GENERATED_DOCS_FILE}" "file exists" "missing" "Create docs/generated-files.md."; exit 1; }

validate_metadata "${METADATA_FILE}"
validate_docs_source_of_truth "${README_FILE}"
validate_docs_source_of_truth "${GENERATED_DOCS_FILE}"
validate_no_vendor_build_context "${README_FILE}"
validate_no_vendor_build_context "${GENERATED_DOCS_FILE}"

validate_metadata "${FIXTURE_DIR}/metadata/valid-minimal.yaml"
expect_fail "missing top-level keys" --contains "top-level keys include" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-top-level.yaml"
expect_fail "missing required entry field" --contains "contains all required fields" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-required-entry-field.yaml"
expect_fail "pg19beta1 not experimental" --contains "19beta1 entries set experimental true" validate_metadata "${FIXTURE_DIR}/metadata/invalid-pg19beta1-not-experimental.yaml"
expect_fail "latest eligible on non-current row" --contains "latest_eligible true only for 18-trixie" validate_metadata "${FIXTURE_DIR}/metadata/invalid-latest-eligible-not-18-trixie.yaml"
expect_fail "missing latest eligible on 18-trixie" --contains "latest_eligible true only for 18-trixie" validate_metadata "${FIXTURE_DIR}/metadata/invalid-latest-eligible-missing-18-trixie.yaml"
expect_fail "empty resolver values without skip" --contains "empty resolver-owned values require" validate_metadata "${FIXTURE_DIR}/metadata/invalid-empty-resolver-owned-without-skip.yaml"
expect_fail "publishable without digest" --contains "publish false in Story 1.1 scaffold" validate_metadata "${FIXTURE_DIR}/metadata/invalid-publishable-without-digest.yaml"
expect_fail "unsupported postgres major" --contains "pg_major in" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unsupported-postgres-major.yaml"
expect_fail "unsupported debian variant" --contains "debian_variant in" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unsupported-debian-variant.yaml"
expect_fail "unsupported platform" --contains "platforms subset" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unsupported-platform.yaml"
expect_fail "missing required platform" --contains "platforms exactly" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-platform.yaml"
expect_fail "duplicate entry" --contains "no duplicate pg_major/debian_variant rows" validate_metadata "${FIXTURE_DIR}/metadata/invalid-duplicate-entry.yaml"
expect_fail "duplicate YAML key" --contains "unique YAML mapping keys" validate_metadata "${FIXTURE_DIR}/metadata/invalid-duplicate-key.yaml"
expect_fail "missing matrix combination" --contains "entries exactly" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-matrix-combination.yaml"
expect_fail "wrong type" --contains "is boolean|is non-empty list" validate_metadata "${FIXTURE_DIR}/metadata/invalid-wrong-types.yaml"
expect_fail "unquoted numeric string field" --contains "schema_version == '1'|is string" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unquoted-numeric.yaml"
expect_fail "bad YAML structure" --contains "image is mapping|allowed is mapping|entries\[0\] is mapping" validate_metadata "${FIXTURE_DIR}/metadata/invalid-bad-structure.yaml"
expect_fail "missing image fields" --contains "image\.(registry|repository)" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-image-field.yaml"
expect_fail "unknown top-level metadata field" --contains "top-level keys exactly" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unknown-top-level.yaml"
expect_fail "unknown entry metadata field" --contains "entries\[0\] keys exactly" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unknown-entry-field.yaml"
expect_fail "mismatched pg version and cnpg tag" --contains "pg_version matches pg_major|cnpg_tag ==" validate_metadata "${FIXTURE_DIR}/metadata/invalid-mismatched-version-tag.yaml"
expect_fail "non-empty resolver field" --contains "resolver-owned fields empty" validate_metadata "${FIXTURE_DIR}/metadata/invalid-non-empty-resolver-field.yaml"
expect_fail "stable pg marked experimental" --contains "stable PostgreSQL entries set experimental false" validate_metadata "${FIXTURE_DIR}/metadata/invalid-stable-experimental.yaml"
expect_fail "blank skip reason" --contains "empty resolver-owned values require" validate_metadata "${FIXTURE_DIR}/metadata/invalid-blank-skip-reason.yaml"
source_truth_fixtures=(
  "${FIXTURE_DIR}/docs/invalid-source-of-truth.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-workflow-matrices.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-github-actions-matrix.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-catalogs.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-generated-docs.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-readme-tables.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-paraphrase.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-plural.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-reverse-canonical.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-leading-negation.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-other-file.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-bake.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-unrelated-not.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-no-longer.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-mixed-safe-conflict.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-negated.md"
)
for file in "${source_truth_fixtures[@]}"; do
  test -f "${file}" || { diag "test -f ${file}" "${file}" "fixture exists" "missing" "Restore the required docs source-of-truth fixture."; exit 1; }
  expect_fail "competing source of truth docs ${file}" --contains "source of truth|hand-edited" validate_docs_source_of_truth "${file}"
done
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-non-source-of-truth-negation.md"
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-generated-from-versions.md"
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-plural-negation.md" 0
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-first-negation.md"
expect_fail "vendor build context docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-build-context.md"
expect_fail "vendor copy source docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-copy-source.md"
expect_fail "vendor dockerfile forms" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-forms.md"
expect_fail "vendor docker build command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build.md"
expect_fail "vendor docker buildx command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildx.md"
expect_fail "vendor json context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-json-context.md"
expect_fail "vendor absolute context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-absolute-context.md"
expect_fail "vendor unrelated negation" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-unrelated-negation.md"
expect_fail "vendor masked second match" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-masked-second-match.md"
expect_fail "vendor dockerfile path" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-path.md"
expect_fail "vendor runtime dependencies" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-runtime-dependencies.md"
expect_fail "vendor runtime dependencies vendor-first" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-runtime-dependencies-vendor-first.md"

while IFS= read -r -d '' file; do
  full_path="${ROOT_DIR}/${file}"
  [[ -f "${full_path}" ]] || continue
  case "${file}" in
    *Dockerfile|Makefile|*.mk|*.hcl|*.json|*.toml|*.md|*.yml|*.yaml|*.sh)
      validate_no_vendor_build_context "${full_path}"
      ;;
  esac
done < <(git_product_files)

while IFS= read -r -d '' file; do
  full_path="${ROOT_DIR}/${file}"
  [[ -f "${full_path}" ]] || continue
  case "${file}" in
    *.md)
      validate_docs_source_of_truth "${full_path}" 0
      ;;
  esac
done < <(git_product_files)

printf 'PASS story-1.1 source-of-truth validation\n'
