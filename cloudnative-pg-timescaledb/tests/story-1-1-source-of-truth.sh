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
import shlex
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
    def strip_inline_comment(value):
        quote = None
        escaped = False
        for idx, char in enumerate(value):
            if escaped:
                escaped = False
                continue
            if char == "\\":
                escaped = True
                continue
            if quote:
                if char == quote:
                    quote = None
                continue
            if char in {"'", '"'}:
                quote = char
                continue
            if char == "#" and (idx == 0 or value[idx - 1].isspace()):
                return value[:idx]
        return value

    value = strip_inline_comment(raw).strip()
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
    if value[0] in {"'", '"'}:
        quote = value[0]
        if not re.fullmatch(rf"{re.escape(quote)}[^{re.escape(quote)}]*{re.escape(quote)}", value):
            diag(command, str(path), "balanced quoted YAML scalar", repr(value), "Close quoted metadata values or remove the opening quote.")
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

def mapping_header_value(text):
    if ":" not in text:
        return None
    _, raw_value = text.split(":", 1)
    return parse_scalar(raw_value)

def is_mapping_header(text):
    if ":" not in text:
        return False
    _, raw_value = text.split(":", 1)
    return re.fullmatch(r"\s*(?:#.*)?", raw_value) is not None

def parse_versions_yaml(text):
    data = {}
    current_top = None
    current_entry = None
    current_entry_list_key = None
    current_mapping_list_key = None

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
            if is_mapping_header(text):
                value = [] if key == "entries" else {}
            assign_mapping(data, key, value, line_no, "top-level metadata")
            current_top = key if isinstance(value, (dict, list)) else None
            current_entry = None
            current_entry_list_key = None
            current_mapping_list_key = None
            continue
        if indent == 2 and current_top == "entries":
            if not text.startswith("- "):
                diag(command, str(path), "entries list item", f"line {line_no}: {text!r}", "Use '- key: value' entries.")
            rest = text[2:].strip()
            if ":" not in rest:
                data["entries"].append(parse_scalar(rest))
                current_entry = None
                current_entry_list_key = None
                current_mapping_list_key = None
                continue
            current_entry = {}
            current_entry_list_key = None
            current_mapping_list_key = None
            data["entries"].append(current_entry)
            key, value = parse_mapping_item(rest, line_no)
            assign_mapping(current_entry, key, value, line_no, "entries[] item")
            current_entry_list_key = key if value == [] else None
            continue
        if indent == 2 and isinstance(data.get(current_top), dict):
            key, value = parse_mapping_item(text, line_no)
            if is_mapping_header(text):
                value = []
            assign_mapping(data[current_top], key, value, line_no, current_top)
            current_entry_list_key = None
            current_mapping_list_key = key if value == [] else None
            continue
        if indent == 4 and isinstance(data.get(current_top), dict) and current_mapping_list_key:
            if not text.startswith("- "):
                diag(command, str(path), "mapping block-list item", f"line {line_no}: {text!r}", "Use '- value' for block-list metadata values.")
            data[current_top][current_mapping_list_key].append(parse_scalar(text[2:].strip()))
            continue
        if indent == 4 and current_top == "entries" and isinstance(current_entry, dict):
            key, value = parse_mapping_item(text, line_no)
            if is_mapping_header(text):
                value = []
            assign_mapping(current_entry, key, value, line_no, "entries[] item")
            current_entry_list_key = key if value == [] else None
            continue
        if indent == 6 and current_top == "entries" and isinstance(current_entry, dict) and current_entry_list_key:
            if not text.startswith("- "):
                diag(command, str(path), "entry block-list item", f"line {line_no}: {text!r}", "Use '- value' for block-list metadata values.")
            current_entry[current_entry_list_key].append(parse_scalar(text[2:].strip()))
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
optional_top = {"barman_plugin"}
missing_top = sorted(required_top - set(data))
if missing_top:
    diag(command, str(path), f"top-level keys include {sorted(required_top)}", f"missing {missing_top}", "Add missing top-level metadata keys.")
extra_top = sorted(set(data) - required_top - optional_top)
if extra_top:
    diag(command, str(path), f"top-level keys exactly {sorted(required_top)} plus optional {sorted(optional_top)}", f"extra {extra_top}", "Remove unknown top-level metadata keys.")
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
extra_entry_allowed = {
    "timescaledb_package_name",
    "toolkit_package_name",
    "pgvector_source",
    "pgvector_package_version",
    "pgaudit_source",
    "pgaudit_package_version",
    "tags",
}
for idx, entry in enumerate(entries):
    if not isinstance(entry, dict):
        diag(command, str(path), f"entries[{idx}] is mapping", type(entry).__name__, "Set every entry to a YAML mapping.")
    missing = sorted(required_entry - set(entry))
    if missing:
        diag(command, str(path), f"entries[{idx}] contains all required fields", f"missing {missing}", "Add the missing required entry fields.")
    extra_entry = sorted(set(entry) - required_entry - extra_entry_allowed)
    if extra_entry:
        diag(command, str(path), f"entries[{idx}] keys exactly {sorted(required_entry)}", f"extra {extra_entry}", "Remove unknown entry metadata keys.")
    for field in string_fields:
        if not isinstance(entry[field], str):
            diag(command, str(path), f"entries[{idx}].{field} is string", type(entry[field]).__name__, f"Set {field} to a YAML string.")
    if "tags" in entry:
        if not isinstance(entry["tags"], list) or any(not isinstance(tag, str) for tag in entry["tags"]):
            diag(command, str(path), f"entries[{idx}].tags is string list", repr(entry["tags"]), "Use an inline YAML string list for deterministic publish tags.")
        if entry.get("publish") is not True:
            diag(command, str(path), f"entries[{idx}].tags only present on publishable rows", repr(entry["tags"]), "Keep tags off unpublished rows until they enter the release path.")
    if entry["pg_version"].strip() == "":
        diag(command, str(path), "pg_version is non-empty", "empty string", "Set a non-empty scaffold PostgreSQL version.")
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
    key = (entry["pg_major"], entry["debian_variant"])
    if key in seen:
        diag(command, str(path), "no duplicate pg_major/debian_variant rows", repr(key), "Remove duplicate metadata entry.")
    seen.add(key)
    if entry["pg_major"] not in expected_allowed["postgres_majors"]:
        diag(command, str(path), f"pg_major in {expected_allowed['postgres_majors']}", repr(entry["pg_major"]), "Use only supported PostgreSQL majors.")
    if entry["debian_variant"] not in expected_allowed["debian_variants"]:
        diag(command, str(path), f"debian_variant in {expected_allowed['debian_variants']}", repr(entry["debian_variant"]), "Use only trixie or bookworm.")
    if entry["pg_major"] == "19beta1" and entry["experimental"] is not True:
        diag(command, str(path), "19beta1 entries set experimental true", repr(entry["experimental"]), "Set experimental: true for PostgreSQL 19beta1.")
    if entry["pg_major"] != "19beta1" and entry["experimental"] is not False:
        diag(command, str(path), "stable PostgreSQL entries set experimental false", f"pg_major={entry['pg_major']!r}, experimental={entry['experimental']!r}", "Set experimental false for PostgreSQL 17 and 18 scaffold rows.")
    expected_latest = key == ("18", "trixie")
    if entry["latest_eligible"] is not expected_latest:
        diag(command, str(path), "latest_eligible true only for 18-trixie", f"key={key!r}, latest_eligible={entry['latest_eligible']!r}", "Set only the 18-trixie row latest_eligible true.")
    non_empty_resolver = {field: entry[field] for field in resolver_owned if field in entry and entry[field] != ""}
    missing_resolver = sorted(field for field in resolver_owned if field in entry and entry[field] == "")
    if path.name != "versions.yaml" and non_empty_resolver:
        diag(command, str(path), "resolver-owned fields empty in Story 1.1 scaffold", repr(non_empty_resolver), "Leave resolver-owned values empty until the resolver story owns them.")
    if entry["publish"] is True:
        if missing_resolver:
            diag(command, str(path), "publishable rows have resolver-owned values", repr(missing_resolver), "Populate resolver-owned values before setting publish true.")
    else:
        if entry["skip_reason"].strip() == "":
            diag(command, str(path), "non-published rows have non-empty skip_reason", repr(entry["skip_reason"]), "Explain why the row is not publishable.")
    if entry["cnpg_tag"].strip() == "":
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
import shlex
import sys

path = Path(sys.argv[1])
require_positive = sys.argv[2] == "1"
raw_text = path.read_text()
text = raw_text.replace("\r\n", "\n")
text = re.sub(r"\n\s*\n", "\x1e", text)
text = re.sub(r"[ \t]*\n[ \t]*", " ", text)
text = text.replace("\x1e", "\n\n")
def diag(expected, actual, remediation):
    raise SystemExit(
        f"command: validate_docs_source_of_truth {path}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )
sentences = re.split(r"\n\s*\n|(?<=[.!?])\s+", text)
def directly_negates_source_claim(sentence):
    return re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:an?\s+)?(?:independent\s+)?(?:hand-edited|manually edited|edited by hand|maintained by hand)\s+sources? of truth\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:must not|must never|should not|should never|do not|does not|never)\b.{0,30}\b(?:become|be|remain)\b.{0,30}\b(?:an?\s+)?(?:independent\s+)?(?:hand-edited|manually edited|edited by hand|maintained by hand)\s+sources? of truth\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:an?\s+)?(?:independent\s+)?sources? of truth\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:canonical|authoritative|definitive)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:the\s+|an?\s+)?(?:canonical|authoritative|definitive)\s+sources?\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:the\s+|an?\s+)?(?:canonical|authoritative|definitive)\s+(?:metadata source|metadata authority|compatibility metadata|compatibility source)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:the\s+|an?\s+)?(?:metadata source|metadata authority|compatibility metadata|compatibility source)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:the\s+|an?\s+)?(?:sources?|authority)\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:do not|does not|must not|must never|should not|should never|never)\b.{0,30}\b(?:serve|serves|served|act|acts|acted|function|functions|functioned|operate|operates|operated)\s+as\b.{0,40}\b(?:the\s+)?(?:primary\s+)?(?:metadata source|metadata authority|compatibility metadata|compatibility source)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:do not|does not|must not|must never|should not|should never|never)\b.{0,30}\b(?:become|be|remain)\b.{0,40}\b(?:the\s+)?(?:sources?|authority)\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:must not|must never|should not|should never|never)\b.{0,30}\b(?:become|be|remain)\b.{0,40}\b(?:the\s+)?(?:metadata source|metadata authority|compatibility metadata|compatibility source)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:hand-edited|hand edited|manually edited|edited by hand|maintained by hand|manually maintained|hand-maintained|updated by hand|manually updated|hand-updated)\s+(?:image definitions?|image metadata|compatibility metadata)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:must not|must never|should not|should never|do not|does not|never)\b.{0,40}\b(?:be|become|remain)\b.{0,40}\b(?:hand-edited|hand edited|manually edited|edited by hand|maintained by hand|manually maintained|hand-maintained|updated by hand|manually updated|hand-updated)\s+(?:image definitions?|image metadata|compatibility metadata)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:do not|does not|must not|must never|should not|should never|never)\b.{0,40}\b(?:define|defines|provide|provides|form|forms|constitute|constitutes)\b.{0,40}\b(?:the\s+)?sources?\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:do not|does not|must not|must never|should not|should never|never)\b.{0,40}\b(?:serve|serves|served|act|acts|acted|function|functions|functioned|operate|operates|operated)\s+as\b.{0,40}\b(?:the\s+)?sources?\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:is|are|becomes?|remain|become|be)\b\s+(?:not|never)\s+(?:the\s+)?(?:origins?|provenance)\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:do not|does not|must not|must never|should not|should never|never)\b.{0,40}\b(?:provide|provides|supply|supplies)\b.{0,40}\bprovenance\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:do not|does not|must not|must never|should not|should never|never)\b.{0,40}\b(?:control|controls|own|owns|govern|governs)\b.{0,40}\b(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
        sentence,
        re.I,
    ) or re.search(
        r"\b(?:do not|does not|must not|must never|should not|should never|never)\b.{0,30}\b(?:serve|serves|served|act|acts|acted|function|functions|functioned|operate|operates|operated)\s+as\b.{0,40}\b(?:the\s+)?(?:primary\s+)?(?:sources? of truth|canonical source|authoritative source|definitive source)\b",
        sentence,
        re.I,
    ) or re.search(
        r"^\s*(?:not|never)\s+(?:an?\s+)?(?:independent\s+)?(?:hand-edited|manually edited|edited by hand|maintained by hand)\s+sources?(?: of truth|-of-truth)\b",
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
    ) or re.search(
        r"\bnot true that\b.{0,80}versions\.yaml.{0,80}only hand-edited source",
        sentence,
        re.I,
    )

for sentence in sentences:
    if contradicts_versions_claim(sentence):
        diag("versions.yaml remains the only hand-edited source of truth", sentence.strip(), "Remove contradictory source-of-truth language.")
terms = [
    r"Dockerfiles?",
    r"Docker Bake definitions?",
    r"workflow matrices",
    r"matrix\.yaml",
    r"GitHub Actions matrix",
    r"workflow matrix",
    r"CI matrix data",
    r"catalogs?",
    r"catalog manifests",
    r"ClusterImageCatalog manifests",
    r"generated docs?",
    r"generated documentation",
    r"generated outputs?",
    r"generated artifacts?",
    r"generated files?",
    r"README tables?",
    r"compatibility tables?",
    r"examples?",
    r"image tags?",
]
artifact_subject = (
    r"(?:Dockerfiles?|Docker Bake definitions?|workflow matrices|matrix\.yaml|GitHub Actions matrix|workflow matrix|CI matrix data|catalogs?|catalog manifests|"
    r"ClusterImageCatalog manifests|generated docs?|generated documentation|generated outputs?|generated artifacts?|generated files?|README tables?|compatibility tables?|examples?|image tags?)"
)
authority_conflict = re.search(
    rf"\b{artifact_subject}\b.{{0,80}}\bnot\s+(?:canonical|authoritative|definitive)\b.{{0,40}}\bbut\s+(?:(?:they|these|those|it)\s+)?(?:is|are|becomes?|remain|must be|should be|will be)?\s*(?:the\s+)?(?:canonical|authoritative|definitive)\b",
    text,
    re.I,
)
if authority_conflict:
    diag("no generated artifact category is a hand-edited source of truth", "negated authority followed by positive authority", "Make generated artifacts derived from versions.yaml.")
source_conflict = re.search(
    rf"\b{artifact_subject}\b.{{0,80}}\bnot\s+(?:canonical|authoritative|definitive)\b.{{0,40}}\bbut\s+(?:(?:they|these|those|it)\s+)?(?:(?:(?:is|are|becomes?|remain|must be|should be|will be)?\s*(?:the\s+|an?\s+)?)|(?:(?:serve|serves|served|act|acts|acted)\s+as\s+(?:the\s+|an?\s+)?))(?:sources?(?: of truth|-of-truth)|sources?\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)|sources?\s+data\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)|metadata source|metadata authority)\b",
    text,
    re.I,
)
if source_conflict:
    diag("no generated artifact category is a hand-edited source of truth", "negated authority followed by positive source claim", "Make generated artifacts derived from versions.yaml.")
control_conflict = re.search(
    rf"\b{artifact_subject}\b.{{0,80}}\b(?:(?:do not|does not|must not|must never|should not|should never|never)\b.{{0,40}}\b(?:control|controls|own|owns|govern|governs)|not\s+(?:canonical|authoritative|definitive))\b.{{0,80}}\bbut\b.{{0,40}}\b(?:(?:they|these|those|it)\s+)?(?:control|controls|own|owns|govern|governs|define|defines|drive|drives|determine|determines)\b.{{0,40}}\b(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
    text,
    re.I,
)
if control_conflict:
    diag("no generated artifact category is a hand-edited source of truth", "negated control/govern clause followed by positive control/govern claim", "Make generated artifacts derived from versions.yaml.")
for term in terms:
    for sentence in sentences:
        if not re.search(term, sentence, re.I):
            continue
        bad_patterns = [
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:an?\s+)?(?:independent|separate|also|another)?\s*(?:hand-edited\s+)?sources?(?: of truth|-of-truth)\b",
            r"\b(?:define|defines|form|forms|constitute|constitutes|provide|provides)\b.{0,40}\b(?:an?\s+)?(?:independent|separate|primary)?\s*sources?(?: of truth|-of-truth)\b",
            r"\b(?:serve|serves|served|act|acts|acted|function|functions|functioned|operate|operates|operated)\s+as\b.{0,40}\b(?:the\s+)?(?:primary\s+)?(?:sources?(?: of truth|-of-truth)|canonical source|authoritative source|definitive source)\b",
            r"\b(?:serve|serves|served|act|acts|acted|function|functions|functioned|operate|operates|operated)\s+as\b.{0,40}\b(?:the\s+)?(?:canonical|authoritative|definitive)\s+(?:metadata source|compatibility metadata|compatibility source|metadata authority)\b",
            r"\b(?:serve|serves|served|act|acts|acted|function|functions|functioned|operate|operates|operated)\s+as\b.{0,40}\b(?:the\s+)?(?:metadata source|metadata authority|compatibility metadata|compatibility source)\b",
            r"\b(?:maintained by hand|manually edited|edited by hand|hand edited)\b.{0,80}\bsources?(?: of truth|-of-truth)\b",
            r"\b(?:manually edited|edited by hand|hand edited|maintained by hand|manually maintained|hand-maintained|human-maintained|updated by hand|manually updated|hand-updated)\b.{0,80}\b(?:authoritative|authority|canonical|definitive)\b",
            r"\b(?:authoritative|authority|canonical|definitive)\b.{0,80}\b(?:edited by hand|hand edited|manually edited|maintained by hand|updated by hand|manually updated|hand-updated)\b",
            r"\b(?:hand-maintained|hand edited|manually maintained|updated by hand|manually updated|hand-updated)\b.{0,80}\b(?:authoritative|authority|canonical|definitive)\b",
            r"\b(?:authoritative|authority|canonical|definitive)\b.{0,80}\b(?:hand-maintained|manually maintained|updated by hand|manually updated|hand-updated)\b",
            r"\b(?:manually kept|maintained manually|manually curated|hand-curated|hand curated|hand-authored|human-curated|human-authored|manually authored)\b.{0,80}\b(?:truth|authority|authoritative|canonical|definitive|source)\b",
            r"\b(?:truth|authority|authoritative|canonical|definitive|source)\b.{0,80}\b(?:manually kept|maintained manually|manually curated|hand-curated|hand curated|hand-authored|human-curated|human-authored|manually authored)\b",
            r"\b(?:manually edited|edited by hand|maintained by hand|manually maintained|maintained manually|hand-maintained|updated by hand|manually updated|hand-updated)\b.{0,80}\bfor\b.{0,80}\b(?:image combinations|image metadata|image definitions?|supported image matrix|supported PostgreSQL versions|supported versions|compatibility data)\b",
            r"\b(?:manually edited|edited by hand|maintained by hand|manually maintained|maintained manually|hand-maintained|updated by hand|manually updated|hand-updated)\b.{0,80}\b(?:define|defines|drive|drives|determine|determines)\b.{0,80}\b(?:image combinations|image metadata|image definitions?|supported image matrix|supported PostgreSQL versions|supported versions|compatibility data|combinations)\b",
            r"\b(?:hand-edited|hand edited|manually edited|edited by hand|maintained by hand|manually maintained|hand-maintained|updated by hand|manually updated|hand-updated)\s+(?:image definitions?|image metadata|compatibility metadata)\b",
            r"\b(?:define|defines|provide|provides|form|forms|constitute|constitutes)\b.{0,40}\b(?:the\s+)?sources?\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:control|controls|own|owns|govern|governs)\b.{0,40}\b(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:serve|serves|served|act|acts|acted)\s+as\b.{0,40}\b(?:the\s+)?sources?\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\bsources?\s+data\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:the\s+)?(?:origins?|provenance)\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:provide|provides|supply|supplies)\b.{0,40}\bprovenance\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:the\s+)?(?:basis|foundation)\s+for\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:the\s+)?(?:basis|foundation)\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:form|forms|provide|provides|supply|supplies)\b.{0,40}\b(?:the\s+)?(?:basis|foundation)\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:define|defines|drive|drives|determine|determines)\b.{0,40}\b(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
            r"\b(?:canonical|authoritative|definitive)\b.{0,80}\bplace\b.{0,80}\b(?:edit|maintain)\b.{0,40}\b(?:by hand|manually)\b",
            r"\bsources?(?: of truth|-of-truth)\b.{0,80}\b(?:maintainers?|developers?|humans?)\b.{0,40}\b(?:edit|maintain)\b.{0,20}\bby hand\b",
            r"\b(?:maintainers?|developers?|humans?)\b.{0,40}\b(?:edit|maintain)\b.{0,20}\bby hand\b.{0,80}\bsources?(?: of truth|-of-truth)\b",
            r"\b(?:maintainers?|developers?|humans?)\b.{0,40}\b(?:edit|maintain)\b.{0,20}\b(?:by hand|manually)\b.{0,80}\bas\s+(?:the\s+)?source\b.{0,40}\b(?:for image metadata|for image definitions?|for image combinations|for supported versions|for compatibility data)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,20}\b(?:canonical|authoritative|definitive)\b\s*\.?$",
            r"\bcanonical source\b.{0,80}\b(?:edited by hand|manually edited|maintained by hand)\b",
            r"\b(?:edited by hand|manually edited|maintained by hand)\b.{0,80}\bcanonical source\b",
            r"\b(?:canonical|authoritative|definitive)\b.{0,80}\b(?:edited by hand|manually edited|maintained by hand)\b",
            r"\b(?:edited by hand|manually edited|maintained by hand)\b.{0,80}\b(?:canonical|authoritative|definitive)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:the\s+)?(?:canonical|authoritative|definitive)\s+(?:source|sources|image definitions?|image metadata)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:canonical|authoritative|definitive)\b.{0,20}\b(?:for image metadata|for image definitions?)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:canonical|authoritative|definitive)\b.{0,40}\b(?:for image combinations|for supported PostgreSQL versions|for supported versions|for compatibility data)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:the\s+)?(?:canonical|authoritative|definitive)\s+(?:metadata source|compatibility metadata|compatibility source|metadata authority)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:canonical|authoritative|definitive)\b.{0,40}\b(?:compatibility metadata|metadata source|metadata authority)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:the\s+)?(?:metadata source|metadata authority|compatibility metadata|compatibility source)\b",
            r"\b(?:is|are|becomes?|remain|must be|should be|will be)\b.{0,40}\b(?:the\s+)?(?:sources?|authority)\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions)\b",
            r"\bsources?(?: of truth|-of-truth)\b.{0,80}\b(?:edited by hand|manually edited|maintained by hand)\b",
        ]
        previous_clause = ""
        for clause in re.split(r";|&&|\|\||\bbut\b|\band\b|\bor\b|,\s*(?:and\s+)?", sentence):
            inherited_subject = (
                previous_clause
                and re.search(term, previous_clause, re.I)
                and re.search(r"^\s*(?:(?:and|but)\s+)?(?:(?:they|these|those|it)\s+)?(?:is|are|becomes?|remain|serve|serves|served|act|acts|acted|function|functions|functioned|operate|operates|operated|define|defines|drive|drives|determine|determines|control|controls|own|owns|govern|governs|must be|should be|will be|edited by hand|manually edited|maintained by hand|authoritative|canonical|definitive)\b", clause, re.I)
            )
            inherited_manual_predicate = (
                previous_clause
                and re.search(term, previous_clause, re.I)
                and re.search(r"\b(?:manually edited|edited by hand|maintained by hand|manually maintained|hand-maintained)\b", previous_clause, re.I)
                and re.search(r"^\s*(?:and\s+)?(?:define|defines|drive|drives|determine|determines)\b", clause, re.I)
            )
            if not re.search(term, clause, re.I) and not inherited_subject and not inherited_manual_predicate:
                previous_clause = clause
                continue
            candidate = clause if not (inherited_subject or inherited_manual_predicate) else f"{previous_clause}, {clause}"
            positive_inherited_authority = re.search(
                r"^\s*(?:(?:and|but)\s+)?(?:(?:they|these|those|it)\s+)?(?:is|are|becomes?|remain|must be|should be|will be)\s+(?:the\s+)?(?:canonical|authoritative|definitive)(?:\s+(?:source|sources|image definitions?|image metadata|metadata source|compatibility metadata|compatibility source|metadata authority))?\b",
                clause,
                re.I,
            )
            positive_inherited_source = re.search(
                r"^\s*(?:(?:and|but)\s+)?(?:(?:they|these|those|it)\s+)?(?:(?:(?:is|are|becomes?|remain|must be|should be|will be)\s+(?:the\s+|an?\s+)?)|(?:(?:serve|serves|served|act|acts|acted|function|functions|functioned|operate|operates|operated)\s+as\s+(?:the\s+|an?\s+)?))(?:(?:hand-edited\s+)?sources?(?: of truth|-of-truth)|sources?\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)|sources?\s+data\s+(?:of|for)\s+(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)|metadata source|metadata authority)\b",
                clause,
                re.I,
            )
            positive_inherited_control = re.search(
                r"^\s*(?:(?:and|but)\s+)?(?:(?:they|these|those|it)\s+)?(?:control|controls|own|owns|govern|governs|define|defines|drive|drives|determine|determines)\b.{0,40}\b(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b",
                clause,
                re.I,
            )
            if inherited_subject and positive_inherited_authority and not directly_negates_source_claim(clause):
                diag("no generated artifact category is a hand-edited source of truth", candidate.strip(), "Make generated artifacts derived from versions.yaml.")
            if inherited_subject and positive_inherited_control:
                diag("no generated artifact category is a hand-edited source of truth", candidate.strip(), "Make generated artifacts derived from versions.yaml.")
            if directly_negates_source_claim(clause) or (directly_negates_source_claim(candidate) and not (positive_inherited_authority or positive_inherited_source or positive_inherited_control)):
                previous_clause = clause
                continue
            if any(re.search(pattern, candidate, re.I) for pattern in bad_patterns):
                diag("no generated artifact category is a hand-edited source of truth", candidate.strip(), "Make generated artifacts derived from versions.yaml.")
            previous_clause = clause
for sentence_index, sentence in enumerate(sentences):
    if not re.search(artifact_subject, sentence, re.I):
        continue
    next_sentence = ""
    try:
        next_sentence = sentences[sentence_index + 1]
    except IndexError:
        next_sentence = ""
    if not next_sentence:
        continue
    if re.search(r"^\s*(?:They|These|Those|It)\s+(?:is|are|must be|should be|will be)\s+(?:the\s+)?(?:canonical|authoritative|definitive)\b\s*\.?$", next_sentence, re.I) or re.search(r"^\s*(?:They|These|Those|It)\s+(?:is|are|must be|should be|will be)\s+(?:the\s+)?(?:canonical|authoritative|definitive)\s+(?:source|sources|image definitions?|image metadata)\b", next_sentence, re.I) or re.search(r"^\s*(?:They|These|Those|It)\s+(?:is|are|must be|should be|will be)\s+(?:the\s+)?(?:metadata source|metadata authority|source for image metadata)\b", next_sentence, re.I) or re.search(r"^\s*(?:They|These|Those|It)\s+(?:is|are|must be|should be|will be)\s+(?:the\s+)?(?:canonical|authoritative|definitive)\b.{0,40}\b(?:for image combinations|for supported PostgreSQL versions|for supported versions|for compatibility data)\b", next_sentence, re.I) or re.search(r"^\s*(?:They|These|Those|It)\s+(?:control|controls|own|owns|govern|governs|define|defines|drive|drives|determine|determines)\b.{0,40}\b(?:image metadata|image combinations|compatibility data|supported versions|supported image definitions?)\b", next_sentence, re.I):
        diag("no generated artifact category is a hand-edited source of truth", f"{sentence.strip()} {next_sentence.strip()}", "Make generated artifacts derived from versions.yaml.")
for sentence in sentences:
    previous_clause = ""
    for clause in re.split(r";|&&|\|\||\bbut\b|\band\b|\bor\b|,\s*(?:and\s+)?", sentence):
        if directly_negates_source_claim(clause):
            previous_clause = clause
            continue
        if (
            re.search(r"versions\.yaml.{0,80}\bthe only hand-edited source of truth\b", clause, re.I)
            and len(re.findall(r"\bhand-edited sources? of truth\b", clause, re.I)) == 1
        ):
            previous_clause = clause
            continue
        if (
            re.search(r"^\s*which\s+is\s+the only hand-edited source of truth\b", clause, re.I)
            and re.search(r"versions\.yaml", previous_clause, re.I)
        ):
            previous_clause = clause
            continue
        if (
            re.search(r"^\s*(?:is|remains)\s+the only hand-edited source of truth\b", clause, re.I)
            and re.search(r"versions\.yaml", previous_clause, re.I)
        ):
            previous_clause = clause
            continue
        if re.search(r"\b(?:hand-edited|manually edited|edited by hand|maintained by hand)\s+sources?(?: of truth|-of-truth)\b", clause, re.I):
            diag("only versions.yaml is a hand-edited source of truth", clause.strip(), "Remove competing hand-edited source-of-truth language.")
        previous_clause = clause
versions_positive = any(
    re.search(r"versions\.yaml.{0,80}\b(?:is|remains)\b.{0,20}\bthe only hand-edited source of truth\b", sentence, re.I)
    and not contradicts_versions_claim(sentence)
    for sentence in sentences
)
if require_positive and not versions_positive:
    diag("versions.yaml named as the only hand-edited source of truth", "required phrase missing", "Document versions.yaml as the only hand-edited source of truth.")
PY
}

validate_docs_source_of_truth_negative_fixture() {
  validate_docs_source_of_truth "$1" 0
}

validate_no_vendor_build_context() {
  local file="$1"
  run_py "$file" <<'PY'
from pathlib import Path
import re
import shlex
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = re.sub(r"\\\r?\n\s*", " ", text)
text = re.sub(r"""(['"])\$(?:PWD|\{PWD\})\1/""", "$PWD/", text)
vendor_assignment = r"(?:(?:\$PWD|\$\{PWD\})/[^\"'\s]*/?|/|\./|(?:\.\./)+)?vendor(?:/\.?|/[^\"'\s]*)?"
vendor_value_re = re.compile(rf"^(?:{vendor_assignment})$")
shell_c = r"(?:sh|bash)(?:\s+-[A-Za-z]+)*\s+-[A-Za-z]*c[A-Za-z]*(?:\s+-[A-Za-z]+)*"
def expand_var_refs(value, name, replacement):
    return re.sub(
        rf"\$\{{{name}(?:(?::[?+\-=][^}}]*)|(?::[0-9][^}}]*)|(?:[%#]{{1,2}}[^}}]*))?\}}|\${name}\b",
        replacement,
        value,
    )
text = re.sub(rf"\$\{{[A-Za-z_][A-Za-z0-9_]*(?::[-=+]|-)[\"']?({vendor_assignment})[\"']?\}}", lambda match: match.group(1), text)
for anchor_name in re.findall(rf"(?m)^\s*[A-Za-z0-9_.-]+\s*:\s*&([A-Za-z0-9_-]+)\s*[\"']?({vendor_assignment})[\"']?\s*$", text):
    name = re.escape(anchor_name[0])
    text = re.sub(rf"\*{name}\b", "vendor/", text)
for anchor_name in re.findall(rf"(?m)^\s*-\s*&([A-Za-z0-9_-]+)\s*[\"']?({vendor_assignment})[\"']?\s*$", text):
    name = re.escape(anchor_name[0])
    text = re.sub(rf"\*{name}\b", "vendor/", text)
for anchor_name in re.findall(rf"&([A-Za-z0-9_-]+)\s*[\"']?({vendor_assignment})[\"']?", text):
    name = re.escape(anchor_name[0])
    text = re.sub(rf"\*{name}\b", "vendor/", text)
def bash_words_to_values(words, base=None):
    result = list(base or [])
    for token in words:
        indexed = re.fullmatch(r"\[([^\]]+)\]=(.*)", token)
        if indexed and indexed.group(1).lstrip("-").isdigit():
            idx = int(indexed.group(1))
            if idx < 0:
                idx = len(result) + idx
            if idx >= 0:
                while len(result) <= idx:
                    result.append("")
                result[idx] = indexed.group(2)
            continue
        result.append(token)
    return result
bash_arrays = {}
for array_match in re.finditer(r"(?m)(?:^|[;\s])([A-Za-z_][A-Za-z0-9_]*)=\(([^)]*)\)(?=\s|;|$)", text):
    try:
        bash_arrays[array_match.group(1)] = bash_words_to_values(shlex.split(array_match.group(2)))
    except ValueError:
        bash_arrays[array_match.group(1)] = bash_words_to_values(array_match.group(2).split())
for append_match in re.finditer(r"(?m)(?:^|[;\s])([A-Za-z_][A-Za-z0-9_]*)\+=\(([^)]*)\)(?=\s|;|$)", text):
    try:
        values = shlex.split(append_match.group(2))
    except ValueError:
        values = append_match.group(2).split()
    current = bash_arrays.setdefault(append_match.group(1), [])
    bash_arrays[append_match.group(1)] = bash_words_to_values(values, current)
for direct_state in re.finditer(r"(?m)(?:^|[;\s])([A-Za-z_][A-Za-z0-9_]*)\[(-?\d+)\]=(?:\"([^\"]*)\"|'([^']*)'|([^;\n\s]+))(?=\s|;|$)", text):
    values = bash_arrays.setdefault(direct_state.group(1), [])
    idx = int(direct_state.group(2))
    if str(path).endswith(".zsh") and idx > 0:
        idx -= 1
    if idx < 0:
        idx = len(values) + idx
    if idx < 0:
        continue
    while len(values) <= idx:
        values.append("")
    values[idx] = next(group for group in direct_state.groups()[2:] if group is not None)
for direct_match in re.finditer(rf"(?m)(?:^|[;\s])([A-Za-z_][A-Za-z0-9_]*)\[([^\]]+)\]=(?:[\"']?)({vendor_assignment})(?:[\"']?)(?=\s|;|$)", text):
    values = bash_arrays.setdefault(direct_match.group(1), [])
    raw_name = direct_match.group(1)
    key = direct_match.group(2)
    if key.lstrip("-").isdigit():
        continue
    else:
        clean_key = key.strip("\"'")
        key_ref = rf"(?:{re.escape(clean_key)}|\"{re.escape(clean_key)}\"|'{re.escape(clean_key)}')"
        text = re.sub(rf"\$\{{{re.escape(raw_name)}\[{key_ref}\](?::[^}}]+)?\}}", "vendor", text)
        text = re.sub(rf"\${re.escape(raw_name)}\[{key_ref}\]", "vendor", text)
        text = re.sub(rf"\$\{{{re.escape(raw_name)}(?:\[@\]|\[\*\])\}}", "vendor", text)
for assoc_match in re.finditer(rf"(?m)(?:^|[;\s])(?:declare|typeset|local)(?:\s+-[A-Za-z]+)*\s+([A-Za-z_][A-Za-z0-9_]*)=\(([^)]*)\)(?=\s|;|$)", text):
    assoc_name = assoc_match.group(1)
    for key, value in re.findall(rf"\[([^\]]+)\]=(?:[\"']?)({vendor_assignment})(?:[\"']?)", assoc_match.group(2)):
        key = key.strip("\"'")
        key_ref = rf"(?:{re.escape(key)}|\"{re.escape(key)}\"|'{re.escape(key)}')"
        text = re.sub(rf"\$\{{{re.escape(assoc_name)}\[{key_ref}\](?::[^}}]+)?\}}", "vendor", text)
        text = re.sub(rf"\${re.escape(assoc_name)}\[{key_ref}\]", "vendor", text)
        text = re.sub(rf"\$\{{{re.escape(assoc_name)}(?:\[@\]|\[\*\])\}}", "vendor", text)

def bash_index(value, length):
    try:
        parsed = int(value)
    except ValueError:
        return None
    return parsed if parsed >= 0 else length + parsed

is_zsh = str(path).endswith(".zsh")
for raw_name, values in bash_arrays.items():
    name = re.escape(raw_name)
    vendor_indexes = [idx for idx, value in enumerate(values) if vendor_value_re.fullmatch(value)]
    vendor_aliases = {idx + 1 for idx in vendor_indexes} if is_zsh else {idx for idx in vendor_indexes}
    vendor_aliases.update(idx - len(values) for idx in vendor_indexes)
    for idx in vendor_aliases:
        text = re.sub(rf"\$\{{{name}\[{idx}\](?::[^}}]+)?\}}", "vendor", text)
        text = re.sub(rf"\${name}\[{idx}\]", "vendor", text)
    def bash_slice_repl(match):
        start = bash_index(match.group(1), len(values))
        length = bash_index(match.group(2), len(values)) if match.group(2) else len(values)
        if start is None or length is None:
            return match.group(0)
        selected = set(range(max(start, 0), min(start + length, len(values))))
        return "vendor" if selected.intersection(vendor_indexes) else match.group(0)
    text = re.sub(rf"\$\{{{name}\[@\]:\s*(-?\d+)(?::(-?\d+))?\}}", bash_slice_repl, text)
    text = re.sub(rf"\$\{{{name}\[\*\]:\s*(-?\d+)(?::(-?\d+))?\}}", bash_slice_repl, text)
    if vendor_indexes:
        text = re.sub(rf"\$\{{{name}(?:\[@\]|\[\*\])\}}", "vendor", text)
    if 0 in vendor_indexes:
        text = re.sub(rf"\$\{{{name}\}}|\${name}\b", "vendor", text)
for alias_name, target_name in re.findall(r"(?m)(?:^|[;\s])([A-Za-z_][A-Za-z0-9_]*)=([A-Za-z_][A-Za-z0-9_]*)(?=\s|;|$)", text):
    if re.search(rf"(?m)(?:^|[;\s]){re.escape(target_name)}=(?:[\"']?)({vendor_assignment})(?:[\"']?)(?=\s|;|$)", text):
        text = re.sub(rf"\$\{{!{re.escape(alias_name)}\}}", "vendor", text)
for alias_name, target_name in re.findall(r"(?m)(?:^|[;\s])(?:declare|typeset|local)\s+-n\s+([A-Za-z_][A-Za-z0-9_]*)=([A-Za-z_][A-Za-z0-9_]*)(?=\s|;|$)", text):
    if re.search(rf"(?m)(?:^|[;\s]){re.escape(target_name)}=(?:[\"']?)({vendor_assignment})(?:[\"']?)(?=\s|;|$)", text):
        text = re.sub(rf"\$\{{{re.escape(alias_name)}\}}|\${re.escape(alias_name)}\b", "vendor", text)
for var_name in re.findall(rf"(?m)^\s*(?:(?:export|local|readonly)\s+|(?:declare|typeset)(?:\s+-[A-Za-z]+)*\s+)?([A-Za-z_][A-Za-z0-9_]*)=(?:[\"']?)({vendor_assignment})(?:[\"']?)\s*$", text):
    name = re.escape(var_name[0])
    text = expand_var_refs(text, name, "vendor")
for var_name in re.findall(rf"(?m)(?:^|[;\s])(?:export\s+)?(?:[A-Za-z_][A-Za-z0-9_]*=[^;\n\s]+\s+)*([A-Za-z_][A-Za-z0-9_]*)=(?:[\"']?)({vendor_assignment})(?:[\"']?)(?=\s|;|$)", text):
    name = re.escape(var_name[0])
    text = expand_var_refs(text, name, "vendor")
make_name = r"[A-Za-z_][A-Za-z0-9_.-]*"
make_func_bodies = {}
make_simple_vars = {}
make_passthrough_args = {}
make_definitions = []
for define_match in re.finditer(rf"(?ms)^\s*(?:(?:override|export|private)\s+)*define\s+({make_name})[^\n]*\n(.*?)^\s*endef\b", text):
    make_definitions.append((define_match.start(), define_match.group(1), define_match.group(2).strip()))
for assign_match in re.finditer(rf"(?m)^\s*(?:(?:[A-Za-z0-9_.-]+\s*:\s*)?(?:(?:export|override|private)\s+)*)?({make_name})\s*(?::::=|::=|:=|\?=|\+=|!=|=)\s*(.+?)\s*(?:#.*)?$", text):
    make_definitions.append((assign_match.start(), assign_match.group(1), assign_match.group(2).strip()))
for _, func_name, body in sorted(make_definitions):
    stripped_body = body.strip()
    if re.fullmatch(make_name, stripped_body) and not re.search(vendor_assignment, stripped_body):
        make_simple_vars[func_name] = stripped_body
    elif re.fullmatch(r"[A-Za-z0-9_./-]+", stripped_body):
        make_simple_vars[func_name] = stripped_body
    if re.search(r"\$\(\d+\)|\$\{\d+\}", body) or re.search(vendor_assignment, body):
        make_func_bodies[func_name] = stripped_body
for func_name, body in make_func_bodies.items():
    args = {
        int(number)
        for match in re.findall(r"\$\((\d+)\)|\$\{(\d+)\}", body)
        for number in match
        if number
    }
    if args:
        make_passthrough_args[func_name] = args
def split_make_args(raw):
    args = []
    start = 0
    depth = 0
    quote = None
    i = 0
    while i < len(raw):
        char = raw[i]
        if quote:
            if char == quote:
                quote = None
            i += 1
            continue
        if char in "\"'":
            quote = char
            i += 1
            continue
        if raw.startswith("$(", i) or raw.startswith("${", i):
            depth += 1
            i += 2
            continue
        if char in ")}" and depth:
            depth -= 1
            i += 1
            continue
        if char == "," and depth == 0:
            args.append(raw[start:i].strip())
            start = i + 1
        i += 1
    args.append(raw[start:].strip())
    return args
def strip_make_quotes(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value
def eval_simple_make_expr(value):
    value = value.strip()
    shell_echo_match = re.fullmatch(rf"(?:echo(?:\s+-n)?|{shell_c}\s+[\"']echo)\s+[\"']?({vendor_assignment})[\"']?", value)
    if shell_echo_match:
        return shell_echo_match.group(1)
    shell_printf_match = re.fullmatch(rf"printf(?:\s+(?:%s|[\"'][^\"']*%s(?:\\n)?[\"']))?\s+[\"']?({vendor_assignment})[\"']?", value)
    if shell_printf_match:
        return shell_printf_match.group(1)
    shell_sh_printf_match = re.fullmatch(rf"{shell_c}\s+[\"']printf(?:\s+(?:%s|[\"'][^\"']*%s(?:\\n)?[\"']))?\s+[\"']?({vendor_assignment})[\"']?[\"']", value)
    if shell_sh_printf_match:
        return shell_sh_printf_match.group(1)
    if re.fullmatch(rf"{shell_c}\s+[\"']echo\s+vendor[\"']", value):
        return "vendor"
    if re.fullmatch(r"printf\s+[\"']?vendor[\"']?", value):
        return "vendor"
    for _ in range(8):
        previous = value
        value = re.sub(
            rf"\$\(({make_name})\)|\$\{{({make_name})\}}",
            lambda match: make_simple_vars.get(next(group for group in match.groups() if group), match.group(0)),
            value,
        )
        if value == previous:
            break
    def make_transform_values(raw):
        try:
            return shlex.split(raw)
        except ValueError:
            return raw.split()
    def subst_repl(match):
        return " ".join(item.replace(match.group(1).strip(), match.group(2).strip()) for item in make_transform_values(match.group(3)))
    def patsubst_repl(match):
        pattern = match.group(1).strip()
        replacement = match.group(2).strip()
        transformed = []
        for item in make_transform_values(match.group(3)):
            regex = "^" + re.escape(pattern).replace("%", "(.*)") + "$"
            stem_match = re.match(regex, item)
            if stem_match:
                stem = stem_match.group(1) if "%" in pattern else ""
                transformed.append(replacement.replace("%", stem))
            else:
                transformed.append(item)
        return " ".join(transformed)
    value = re.sub(r"\$\(subst\s+([^,]+),([^,]+),([^\)]*)\)", subst_repl, value)
    value = re.sub(r"\$\(patsubst\s+([^,]+),([^,]+),([^\)]*)\)", patsubst_repl, value)
    value = re.sub(r"\$\(addprefix\s+([^,]+),([^\)]*)\)", lambda match: " ".join(f"{match.group(1).strip()}{item}" for item in make_transform_values(match.group(2))), value)
    value = re.sub(r"\$\(addsuffix\s+([^,]+),([^\)]*)\)", lambda match: " ".join(f"{item}{match.group(1).strip()}" for item in make_transform_values(match.group(2))), value)
    value = re.sub(r"\$\(strip\s+([^\)]*)\)", lambda match: " ".join(make_transform_values(match.group(1))), value)
    value = re.sub(r"\$\(sort\s+([^\)]*)\)", lambda match: " ".join(sorted(set(make_transform_values(match.group(1))))), value)
    value = re.sub(rf"\$\(shell\s+echo(?:\s+-n)?\s+[\"']?({vendor_assignment})[\"']?\s*\)", lambda match: match.group(1), value)
    value = re.sub(rf"\$\(shell\s+printf(?:\s+(?:%s|[\"'][^\"']*%s(?:\\n)?[\"']))?\s+[\"']?({vendor_assignment})[\"']?\s*\)", lambda match: match.group(1), value)
    value = re.sub(rf"\$\(shell\s+{shell_c}\s+[\"']echo\s+[\"']?({vendor_assignment})[\"']?[\"']\s*\)", lambda match: match.group(1), value)
    value = re.sub(rf"\$\(shell\s+{shell_c}\s+[\"']printf(?:\s+(?:%s|[\"'][^\"']*%s(?:\\n)?[\"']))?\s+[\"']?({vendor_assignment})[\"']?[\"']\s*\)", lambda match: match.group(1), value)
    value = re.sub(r"\$\(shell\s+pwd\s*\)/(?:(?:\./|(?:\.\./)+))*vendor(?:/[^\s\)]*)?", "vendor", value)
    value = re.sub(r"\$\((?:abspath|realpath|wildcard)\s+(?:(?:\$\((?:CURDIR|PWD)\)|\$\{(?:CURDIR|PWD)\})/(?:(?:\./|(?:\.\./)+))?|(?:\./|(?:\.\./)+))?vendor(?:/[^\)]*)?\)", "vendor", value)
    value = re.sub(r"\$\((?:CURDIR|PWD)\)/(?:(?:\./|(?:\.\./)+))*vendor|\$\{(?:CURDIR|PWD)\}/(?:(?:\./|(?:\.\./)+))*vendor", "vendor", value)
    def join_repl(match):
        left = make_transform_values(match.group(1))
        right = make_transform_values(match.group(2))
        limit = max(len(left), len(right))
        return " ".join((left[idx] if idx < len(left) else "") + (right[idx] if idx < len(right) else "") for idx in range(limit))
    value = re.sub(r"\$\(join\s+([^,]+),([^\)]*)\)", join_repl, value)
    return value.strip()
for _, var_name, body in sorted(make_definitions):
    resolved_body = eval_simple_make_expr(body.strip())
    if resolved_body != body.strip() and re.fullmatch(r"[A-Za-z0-9_./-]+", resolved_body):
        make_simple_vars[var_name] = resolved_body
def expand_make_simple_vars(value):
    previous = None
    while value != previous:
        previous = value
        value = re.sub(
            rf"\$\(({make_name})\)|\$\{{({make_name})\}}",
            lambda match: make_simple_vars.get(next(group for group in match.groups() if group), match.group(0)),
            value,
        )
    return value
def resolve_make_func_name(func_name):
    current = func_name.strip()
    for _ in range(8):
        previous = current
        if current in make_func_bodies:
            return current
        nested = re.fullmatch(rf"\$\(\$\(({make_name})\)\)|\$\{{\$\{{({make_name})\}}\}}", current)
        if nested:
            ref_name = next(group for group in nested.groups() if group)
            current = make_simple_vars.get(make_simple_vars.get(ref_name, ref_name), current)
        current = expand_make_simple_vars(current)
        current = eval_simple_make_expr(current)
        if current in make_simple_vars:
            current = make_simple_vars[current]
        if current == previous:
            break
    return current
def make_values_contain_vendor(raw):
    try:
        values = shlex.split(raw)
    except ValueError:
        values = raw.split()
    return any(vendor_value_re.fullmatch(strip_make_quotes(value)) for value in values)
def make_vendor_replacement(raw):
    try:
        values = shlex.split(raw)
    except ValueError:
        values = raw.split()
    for value in values:
        stripped = strip_make_quotes(value)
        if vendor_value_re.fullmatch(stripped):
            return stripped
    return ""
def eval_make_call_body(func_name, args, variable_name=None, variable_values=None):
    func_name = resolve_make_func_name(func_name)
    body = make_func_bodies.get(func_name)
    if body is None:
        return ""
    expanded_args = []
    variable_ref = None
    if variable_name:
        variable_ref = re.compile(rf"\$\({variable_name}\)|\$\{{{variable_name}\}}")
    for arg in args:
        stripped = strip_make_quotes(arg)
        if variable_ref and variable_ref.fullmatch(stripped):
            expanded_args.append(" ".join(variable_values or []))
        else:
            expanded_args.append(stripped)
    expanded = body
    for index, arg in enumerate(expanded_args, 1):
        expanded = re.sub(rf"\$\({index}\)|\$\{{{index}\}}", arg, expanded)
    return eval_simple_make_expr(expanded)
def make_body_is_exact_passthrough(func_name, arg_number):
    func_name = resolve_make_func_name(func_name)
    body = make_func_bodies.get(func_name, "").strip()
    return body in {f"$({arg_number})", f"${{{arg_number}}}"}
def rewrite_make_calls(source, resolver):
    output = []
    cursor = 0
    pattern = re.compile(r"\$[\(\{]call\s+")
    while True:
        match = pattern.search(source, cursor)
        if not match:
            output.append(source[cursor:])
            break
        func_start = match.end()
        depth = 0
        quote = None
        comma = func_start
        while comma < len(source):
            char = source[comma]
            if quote:
                if char == quote:
                    quote = None
                comma += 1
                continue
            if char in "\"'":
                quote = char
                comma += 1
                continue
            if source.startswith("$(", comma) or source.startswith("${", comma):
                depth += 1
                comma += 2
                continue
            if char in ")}" and depth:
                depth -= 1
                comma += 1
                continue
            if char == "," and depth == 0:
                break
            comma += 1
        if comma >= len(source) or source[comma] != ",":
            output.append(source[cursor:match.end()])
            cursor = match.end()
            continue
        func_name = source[func_start:comma].strip()
        depth = 1
        quote = None
        index = comma + 1
        while index < len(source):
            char = source[index]
            if quote:
                if char == quote:
                    quote = None
                index += 1
                continue
            if char in "\"'":
                quote = char
                index += 1
                continue
            if source.startswith("$(", index) or source.startswith("${", index):
                depth += 1
                index += 2
                continue
            if char in ")}":
                depth -= 1
                index += 1
                if depth == 0:
                    break
                continue
            index += 1
        if depth != 0:
            output.append(source[cursor:])
            break
        original = source[match.start():index]
        args = split_make_args(source[comma + 1:index - 1])
        output.append(source[cursor:match.start()])
        output.append(resolver(func_name, args, original))
        cursor = index
    return "".join(output)
def literal_make_call_repl(func_name, args, original):
    expanded_body = eval_make_call_body(func_name, args)
    replacement = make_vendor_replacement(expanded_body)
    if replacement:
        return replacement
    passthrough_args = make_passthrough_args.get(func_name, set())
    for arg_number in passthrough_args:
        if arg_number <= len(args) and make_body_is_exact_passthrough(func_name, arg_number) and vendor_value_re.fullmatch(strip_make_quotes(args[arg_number - 1])):
            return strip_make_quotes(args[arg_number - 1])
    return original
text = rewrite_make_calls(text, literal_make_call_repl)
def rewrite_literal_make_foreach(source):
    output = []
    cursor = 0
    pattern = re.compile(r"\$[\(\{]foreach\s+([A-Za-z_][A-Za-z0-9_]*)\s*,")
    while True:
        match = pattern.search(source, cursor)
        if not match:
            output.append(source[cursor:])
            break
        depth = 1
        quote = None
        index = match.end()
        while index < len(source):
            char = source[index]
            if quote:
                if char == quote:
                    quote = None
                index += 1
                continue
            if char in "\"'":
                quote = char
                index += 1
                continue
            if source.startswith("$(", index) or source.startswith("${", index):
                depth += 1
                index += 2
                continue
            if char in ")}":
                depth -= 1
                index += 1
                if depth == 0:
                    break
                continue
            index += 1
        if depth != 0:
            output.append(source[cursor:])
            break
        original = source[match.start():index]
        parts = split_make_args(source[match.end():index - 1])
        replacement = original
        if len(parts) >= 2:
            list_expr = eval_simple_make_expr(parts[0])
            if "$" in list_expr:
                output.append(source[cursor:match.start()])
                output.append(original)
                cursor = index
                continue
            try:
                values = shlex.split(list_expr)
            except ValueError:
                values = list_expr.split()
            body = ",".join(parts[1:])
            expanded = [
                eval_simple_make_expr(re.sub(rf"\$\({re.escape(match.group(1))}\)|\$\{{{re.escape(match.group(1))}\}}", value, body))
                for value in values
            ]
            replacement = next((make_vendor_replacement(value) for value in expanded if make_vendor_replacement(value)), ".")
        output.append(source[cursor:match.start()])
        output.append(replacement)
        cursor = index
    return "".join(output)
text = rewrite_literal_make_foreach(text)
def rewrite_make_foreach(source, variable_name, values):
    output = []
    cursor = 0
    pattern = re.compile(rf"\$[\(\{{]foreach\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(?:\$\({variable_name}\)|\$\{{{variable_name}\}})\s*,")
    while True:
        match = pattern.search(source, cursor)
        if not match:
            output.append(source[cursor:])
            break
        depth = 1
        quote = None
        index = match.end()
        while index < len(source):
            char = source[index]
            if quote:
                if char == quote:
                    quote = None
                index += 1
                continue
            if char in "\"'":
                quote = char
                index += 1
                continue
            if source.startswith("$(", index) or source.startswith("${", index):
                depth += 1
                index += 2
                continue
            if char in ")}":
                depth -= 1
                index += 1
                if depth == 0:
                    break
                continue
            index += 1
        if depth != 0:
            output.append(source[cursor:])
            break
        loop_name = match.group(1)
        body = source[match.end():index - 1]
        expanded = []
        for value in values:
            replaced = re.sub(rf"\$\({re.escape(loop_name)}\)|\$\{{{re.escape(loop_name)}\}}", value, body)
            expanded.append(eval_simple_make_expr(replaced))
        output.append(source[cursor:match.start()])
        output.append(next((make_vendor_replacement(value) for value in expanded if make_vendor_replacement(value)), "."))
        cursor = index
    return "".join(output)
for var_name in re.findall(rf"(?ms)^\s*(?:(?:override|export|private)\s+)*define\s+({make_name})(?:\s*(?::::=|::=|:=|\?=|\+=|!=|=))?\s*\n\s*(?:[\"']?)({vendor_assignment})(?:[\"']?)\s*\n\s*endef\b", text):
    name = re.escape(var_name[0])
    text = re.sub(rf"\$\({name}\)", "vendor", text)
    text = expand_var_refs(text, name, "vendor")
for var_name in re.findall(rf"(?m)^\s*(?:(?:[A-Za-z0-9_.-]+\s*:\s*)?(?:(?:export|override|private)\s+)*)?({make_name})\s*(?::::=|::=|:=|\?=|\+=|!=|=)\s*(?:[\"']?)({vendor_assignment})(?:[\"']?)\s*(?:#.*)?$", text):
    name = re.escape(var_name[0])
    pass
for make_list in re.finditer(rf"(?m)^\s*(?:(?:[A-Za-z0-9_.-]+\s*:\s*)?(?:(?:export|override|private)\s+)*)?({make_name})\s*(?::::=|::=|:=|\?=|\+=|!=|=)\s*(.+?)\s*(?:#.*)?$", text):
    raw_name = make_list.group(1)
    try:
        values = shlex.split(eval_simple_make_expr(make_list.group(2)))
    except ValueError:
        values = eval_simple_make_expr(make_list.group(2)).split()
    vendor_positions = {idx + 1 for idx, value in enumerate(values) if vendor_value_re.fullmatch(value)}
    name = re.escape(raw_name)
    def replace_make_transform(pattern, transform):
        def repl(match):
            transformed = [transform(value, match) for value in values]
            return "vendor/" if any(vendor_value_re.fullmatch(value) for value in transformed) else "."
        return re.sub(pattern, repl, text)
    text = replace_make_transform(
        rf"\$\(subst\s+([^,]+),([^,]+),\s*\$\({name}\)\s*\)",
        lambda value, match: value.replace(match.group(1).strip(), match.group(2).strip()),
    )
    text = replace_make_transform(
        rf"\$\(subst\s+([^,]+),([^,]+),\s*\$\{{{name}\}}\s*\)",
        lambda value, match: value.replace(match.group(1).strip(), match.group(2).strip()),
    )
    def patsubst_value(value, match):
        pattern = match.group(1).strip()
        replacement = match.group(2).strip()
        regex = "^" + re.escape(pattern).replace("%", "(.*)") + "$"
        stem_match = re.match(regex, value)
        if not stem_match:
            return value
        stem = stem_match.group(1) if "%" in pattern else ""
        return replacement.replace("%", stem)
    text = replace_make_transform(rf"\$\(patsubst\s+([^,]+),([^,]+),\s*\$\({name}\)\s*\)", patsubst_value)
    text = replace_make_transform(rf"\$\(patsubst\s+([^,]+),([^,]+),\s*\$\{{{name}\}}\s*\)", patsubst_value)
    text = replace_make_transform(rf"\$\(addprefix\s+([^,]+),\s*\$\({name}\)\s*\)", lambda value, match: f"{match.group(1).strip()}{value}")
    text = replace_make_transform(rf"\$\(addprefix\s+([^,]+),\s*\$\{{{name}\}}\s*\)", lambda value, match: f"{match.group(1).strip()}{value}")
    text = replace_make_transform(rf"\$\(addsuffix\s+([^,]+),\s*\$\({name}\)\s*\)", lambda value, match: f"{value}{match.group(1).strip()}")
    text = replace_make_transform(rf"\$\(addsuffix\s+([^,]+),\s*\$\{{{name}\}}\s*\)", lambda value, match: f"{value}{match.group(1).strip()}")
    text = rewrite_make_foreach(text, name, values)
    def make_foreach_repl(match):
        loop_name = match.group(1)
        body = match.group(2)
        expanded = [
            eval_simple_make_expr(re.sub(rf"\$\({re.escape(loop_name)}\)|\$\{{{re.escape(loop_name)}\}}", value, body))
            for value in values
        ]
        return "vendor/" if any(make_values_contain_vendor(value) for value in expanded) else "."
    foreach_passthrough = "vendor" if vendor_positions else "."
    text = re.sub(rf"\$\(foreach\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*\$\({name}\)\s*,\s*\$\(\1\)\s*\)", foreach_passthrough, text)
    text = re.sub(rf"\$\(foreach\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*\$\({name}\)\s*,\s*\$\{{\1\}}\s*\)", foreach_passthrough, text)
    text = re.sub(rf"\$\(foreach\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*\$\({name}\)\s*,([^\)]*)\)", make_foreach_repl, text)
    text = re.sub(rf"\$\(foreach\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*\$\{{{name}\}}\s*,([^\)]*)\)", make_foreach_repl, text)
    def variable_make_call_repl(func_name, args, original):
        expanded_body = eval_make_call_body(func_name, args, name, values)
        replacement = make_vendor_replacement(expanded_body)
        if replacement:
            return replacement
        passthrough_args = make_passthrough_args.get(func_name, set())
        for arg_number in passthrough_args:
            if arg_number > len(args):
                continue
            arg = args[arg_number - 1]
            if make_body_is_exact_passthrough(func_name, arg_number) and vendor_value_re.fullmatch(strip_make_quotes(arg)):
                return "vendor"
            if make_body_is_exact_passthrough(func_name, arg_number) and vendor_positions and re.fullmatch(rf"\$\({name}\)|\$\{{{name}\}}", arg.strip()):
                return "vendor"
        return original
    text = rewrite_make_calls(text, variable_make_call_repl)
    if not vendor_positions:
        continue
    if values and vendor_value_re.fullmatch(values[0]):
        text = re.sub(rf"\$\(firstword\s+\$\({name}\)\s*\)", "vendor", text)
        text = re.sub(rf"\$\(firstword\s+\$\{{{name}\}}\s*\)", "vendor", text)
    if values and vendor_value_re.fullmatch(values[-1]):
        text = re.sub(rf"\$\(lastword\s+\$\({name}\)\s*\)", "vendor", text)
        text = re.sub(rf"\$\(lastword\s+\$\{{{name}\}}\s*\)", "vendor", text)
    for idx in vendor_positions:
        text = re.sub(rf"\$\(word\s+{idx}\s*,\s*\$\({name}\)\s*\)", "vendor", text)
        text = re.sub(rf"\$\(word\s+{idx}\s*,\s*\$\{{{name}\}}\s*\)", "vendor", text)
    if any(vendor_value_re.fullmatch(value) for value in values):
        whole_ref = re.compile(rf"\$\({name}\)|\$\{{{name}\}}")
        def make_whole_repl(match):
            prefix = text[max(0, match.start() - 32):match.start()]
            if re.search(r"\$\((?:firstword|lastword)\s+$|\$\(word\s+\d+\s*,\s*$", prefix):
                return match.group(0)
            return "vendor"
        text = whole_ref.sub(make_whole_repl, text)
text = re.sub(rf"\$\(shell\s+echo(?:\s+-n)?\s+[\"']?({vendor_assignment})[\"']?\s*\)", lambda match: match.group(1), text)
text = re.sub(rf"\$\(shell\s+printf(?:\s+(?:%s|[\"'][^\"']*%s(?:\\n)?[\"']))?\s+[\"']?({vendor_assignment})[\"']?\s*\)", lambda match: match.group(1), text)
text = re.sub(rf"\$\(shell\s+{shell_c}\s+[\"']echo\s+[\"']?({vendor_assignment})[\"']?[\"']\s*\)", lambda match: match.group(1), text)
text = re.sub(rf"\$\(shell\s+{shell_c}\s+[\"']printf(?:\s+(?:%s|[\"'][^\"']*%s(?:\\n)?[\"']))?\s+[\"']?({vendor_assignment})[\"']?[\"']\s*\)", lambda match: match.group(1), text)
text = re.sub(r"\$\(shell\s+pwd\s*\)/(?:(?:\./|(?:\.\./)+))*vendor(?:/[^\s\)]*)?", "vendor", text)
text = re.sub(r"\$\((?:abspath|realpath|wildcard)\s+(?:(?:\$\((?:CURDIR|PWD)\)|\$\{(?:CURDIR|PWD)\})/(?:(?:\./|(?:\.\./)+))?|(?:\./|(?:\.\./)+))?vendor(?:/[^\)]*)?\)", "vendor", text)
text = re.sub(r"\$\((?:CURDIR|PWD)\)/(?:(?:\./|(?:\.\./)+))*vendor|\$\{(?:CURDIR|PWD)\}/(?:(?:\./|(?:\.\./)+))*vendor", "vendor", text)
fish_vars = {}
def fish_values(raw):
    try:
        return shlex.split(raw)
    except ValueError:
        return raw.split()
def fish_flag_enabled(flags, short, long_name):
    for flag in flags.split():
        if flag == f"-{short}" or flag == f"--{long_name}":
            return True
        if re.fullmatch(rf"-[A-Za-z]*{short}[A-Za-z]*", flag):
            return True
    return False
def normalize_fish_index(value, length):
    try:
        parsed = int(value)
    except ValueError:
        return None
    return parsed if parsed > 0 else length + parsed + 1
for fish_match in re.finditer(r"(?m)^\s*set\s+(?P<flags>(?:(?:-{1,2}[A-Za-z][A-Za-z-]*|-[A-Za-z]+)\s+)*)(?P<name>[A-Za-z_][A-Za-z0-9_]*)(?:\[(?P<index>(?:-?\d+)?\.\.(?:-?\d+)?|-?\d+)\])?\s+(?P<values>[^\n#]+?)\s*$", text):
    raw_name = fish_match.group("name")
    values = fish_values(fish_match.group("values"))
    indexed = fish_match.group("index")
    if indexed is not None:
        current = list(fish_vars.get(raw_name, []))
        if ".." in indexed:
            start_raw, end_raw = indexed.split("..", 1)
            start = 1 if start_raw.strip() == "" else normalize_fish_index(start_raw, len(current))
            end = len(current) if end_raw.strip() == "" else normalize_fish_index(end_raw, len(current))
            if start and end and start > 0 and end > 0:
                low, high = sorted((start, end))
                while len(current) < high:
                    current.append("")
                current[low - 1:high] = values
                fish_vars[raw_name] = current
        else:
            target = normalize_fish_index(indexed, len(current))
            if target and target > 0:
                while len(current) < target:
                    current.append("")
                current[target - 1:target] = values
                fish_vars[raw_name] = current
        continue
    flags = fish_match.group("flags")
    current = fish_vars.get(raw_name, [])
    if fish_flag_enabled(flags, "a", "append"):
        fish_vars[raw_name] = [*current, *values]
    elif fish_flag_enabled(flags, "p", "prepend"):
        fish_vars[raw_name] = [*values, *current]
    else:
        fish_vars[raw_name] = values
for raw_name, values in fish_vars.items():
    name = re.escape(raw_name)
    vendor_indexes = [idx + 1 for idx, value in enumerate(values) if vendor_value_re.fullmatch(value)]
    vendor_aliases = {idx for idx in vendor_indexes}
    vendor_aliases.update(idx - len(values) - 1 for idx in vendor_indexes)
    def fish_index_selects_vendor(match):
        expr = match.group(1).strip()
        if ".." in expr:
            start_raw, end_raw = expr.split("..", 1)
            start = 1 if start_raw.strip() == "" else normalize_fish_index(start_raw, len(values))
            end = len(values) if end_raw.strip() == "" else normalize_fish_index(end_raw, len(values))
            if start is None or end is None:
                return match.group(0)
            low, high = sorted((start, end))
            return "vendor" if any(low <= idx <= high for idx in vendor_indexes) else match.group(0)
        idx = normalize_fish_index(expr, len(values))
        return "vendor" if idx in vendor_indexes else match.group(0)
    text = re.sub(rf"\${name}\[([^\]]+)\]", fish_index_selects_vendor, text)
    if vendor_indexes:
        text = re.sub(rf"\${name}\b(?!\[)", "vendor", text)
for var_name in re.findall(rf"(?im)^\s*(?:ARG|ENV)\s+([A-Za-z_][A-Za-z0-9_]*)=(?:[\"']?)({vendor_assignment})(?:[\"']?)\s*$", text):
    name = re.escape(var_name[0])
    text = expand_var_refs(text, name, "vendor")
for var_name in re.findall(rf"(?im)^\s*(?:ARG|ENV)\s+([A-Za-z_][A-Za-z0-9_]*)=(?:[\"']?)\$\{{[A-Za-z_][A-Za-z0-9_]*(?::[-=+]|-)[\"']?({vendor_assignment})[\"']?\}}(?:[\"']?)\s*$", text):
    name = re.escape(var_name[0])
    text = expand_var_refs(text, name, "vendor")
for var_name in re.findall(rf"(?im)^\s*ENV\s+([A-Za-z_][A-Za-z0-9_]*)\s+(?:[\"']?)({vendor_assignment})(?:[\"']?)\s*$", text):
    name = re.escape(var_name[0])
    text = expand_var_refs(text, name, "vendor")
for env_line in re.findall(r"(?im)^\s*ENV\s+(.+)$", text):
    for var_name in re.findall(rf"(?:^|\s)([A-Za-z_][A-Za-z0-9_]*)=(?:[\"']?)({vendor_assignment})(?:[\"']?)(?=\s|$)", env_line):
        name = re.escape(var_name[0])
        text = expand_var_refs(text, name, "vendor")
is_dockerfile = re.search(r"(?i)(?:^|/)(?:Dockerfile[^/]*|[^/]+\.Dockerfile|Containerfile[^/]*|[^/]+\.Containerfile)$", str(path)) is not None
def diag(expected, actual, remediation):
    raise SystemExit(
        f"command: validate_no_vendor_build_context {path}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )
vendor_path = r"[\"']?(?:/|\./|(?:\.\./)+|[A-Za-z0-9_.-]+/)*vendor(?:/|[\"']|\s|,|]|\)|$)"
patterns = [
    r"^\s*(?-i:COPY|ADD)\s+(?:--[^\s]+\s+)*" + vendor_path,
    r"^\s*`+\s*(?i:copy|add)\s+(?:--[^\s]+\s+)*" + vendor_path,
    r"^\s*[-*]\s+`?\s*(?i:copy|add)\s+(?:--[^\s]+\s+)*" + vendor_path,
    r"^\s*(?i:copy|add)\s+(?:--[^\s]+\s+)*\[[^\]\n]*[\"'](?:/|\./|(?:\.\./)+)?vendor(?:/[^\"']*)?[\"'][^\]\n]*,\s*[\"'][^\"']+[\"']\s*\]",
    r"\b(?:cp|rsync)\b[^\n;]{0,80}(?:\./)?vendor(?:/|\s|$)",
    r"(?:^|[;&|]|\n\s*[-*]?\s*)\s*(?:exec\s+)?(?:\./|/|(?:\.\./)+)?vendor/[^\s;]+",
    r"\b(?:bash|sh|python3?|node|ruby|perl)\s+(?:\./|(?:\.\./)+)?vendor/",
    r"\bmake\s+(?:-C|--directory(?:=|\s+))\s*(?:\./|(?:\.\./)+)?vendor/?\b",
    r"\bcd\s+(?:\./|(?:\.\./)+)?vendor/?\b",
    r"\btar\b[^\n;]{0,80}(?:\s-C\s+|\s--directory(?:=|\s+))(?:\./|(?:\.\./)+)?vendor/?\b",
    r"\btar\b[^\n;]{0,120}\s(?:/|\./|(?:\.\./)+)?vendor(?:/|\s|$)",
    r"--mount=[^\n;]*(?:source|src)=[\"']?(?:[^\s,\"']*/)?vendor(?:/|[\"']|,|\s|$)",
    r"\b(?:docker|podman)\s+run\b(?:(?![;&|]).){0,200}(?:-v|--volume)(?:\s+|=)[\"']?(?:[^\s\"']*/)?vendor(?:/|:|[\"']|\s|$)",
    r"\b(?:docker|podman)\s+run\b(?:(?![;&|]).){0,200}--mount\s+(?:type=bind,)?[^\n;]*(?:source|src)=[\"']?(?:[^\s,\"']*/)?vendor(?:/|,|[\"']|\s|$)",
    r"--build-context(?:\s+|=)[^=\s]+=[\"']?(?:[^\s\"']*/)?vendor(?:/[^\s\"']*)?(?:[\"']|\s|$)",
    r"\b(?:source|src)=[\"']?(?:[^\s,\"']*/)?vendor(?:/|[\"']|,|\s|$)",
    r"\b(?:docker\s+(?:(?:image\s+)?build|buildx\s+(?:build|bake))|podman\s+build|nerdctl\s+build|buildah\s+bud)\b(?:\s+\.)?[^\n;.]{0,120}(?:-f|--file)(?:\s+|=)[\"']?(?:[^\s\"']*/)?vendor/",
    r"\bdocker\s+(?:(?:image\s+)?build|buildx\s+build)\b(?:(?![;&|]).){0,160}<\s*[\"']?(?:[^\s\"']*/)?vendor/",
    r"\bdocker\s+buildx(?:\s+(?:--(?:builder|builder-instance|config)\s+[^\s]+|--[^\s=]+(?:=[^\s]+)?|-[A-Za-z]+))*\s+bake\b(?:(?![;&|]).){0,200}--set(?:\s+|=)[\"']?[^\"'\s=]+\.contexts?(?:\.[A-Za-z0-9_.-]+)?=[\"']?(?:[^\s\"']*/)?vendor(?:/\.?|/[^\s\"']*)?(?:[\"']|\s|$)",
    r"\b(?:docker(?:\s+(?:--(?:context|host|config|log-level)\s+[^\s]+|--[^\s=]+(?:=[^\s]+)?|-[A-Za-z]+))*\s+(?:(?:image\s+)?build|buildx\s+build)|podman\s+build|nerdctl\s+build|buildah\s+bud)\b(?:(?![;&|]).){0,160}(?:^|\s)[\"']?(?:[^\s\"']*/)?vendor(?:/\.?|/[^\s\"']*)?(?:[\"']|\s|$)",
    r"\bdocker\s+buildx(?:\s+(?:--(?:builder|builder-instance|config)\s+[^\s]+|--[^\s=]+(?:=[^\s]+)?|-[A-Za-z]+))*\s+build\b(?:(?![;&|]).){0,160}(?:^|\s)[\"']?(?:[^\s\"']*/)?vendor(?:/\.?|/[^\s\"']*)?(?:[\"']|\s|$)",
    r"\bdocker\s+compose\b(?:(?![;&|]).){0,120}(?:-f|--file)(?:\s+|=)[\"']?(?:[^\s\"']*/)?vendor/",
    r"\bbuild\s*:\s*[\"']?(?:[^\n\"']*/)?vendor/?\b",
    r"\buses\s*:\s*[\"']?(?:\./|(?:\.\./)+|[A-Za-z0-9_.-]+/)*vendor(?:/|[\"']?\s*$)",
    r"\b(?:include|includes|files?)\s*[:=]\s*\[[^\]\n]*[\"']?(?:\./)?vendor/",
    r"\b(?:include|includes|files?)\s*[:=]\s*[\"']?(?:\./)?vendor/",
    r"[\"']?dockerfile[\"']?\s*[:=]\s*[\"']?(?:[^\n\"']*/)?vendor/",
    r"[\"']?context[\"']?\s*[:=]\s*[\"']?(?:[^\n\"']*/)?vendor(?:/[^\"'\s]*)?(?:[\"']|\s|$)",
    r"[\"']?context[\"']?\s*[:=]\s*(?:join\([^;\n]*)?[\"']vendor[\"']",
    r"\badditional_contexts\s*:\s*\n(?:\s+[A-Za-z0-9_.-]+\s*:\s*[\"']?(?:/|\./|(?:\.\./)+)?vendor/?[\"']?\s*\n?)+",
    r"\bcontexts\s*=\s*\{[\s\S]{0,400}=\s*[\"'][^\"']*/?vendor(?:/[^\"']*)?[\"']",
    r"\bbuild context\s+(?:\./)?vendor/?\b",
    r"\bbuild context\b.{0,80}\b(?:from|comes from|is loaded from)\s+(?:[^\s\"']*/)?vendor/?\b",
    r"(?:\./)?vendor/?\b.{0,80}\b(?:docker\s+)?build context\b",
    r"\bruntime (?:inputs?|dependenc(?:y|ies))\s+(?:\./)?vendor/?\b",
    r"\bruntime (?:inputs?|dependenc(?:y|ies))\b[^\n;]{0,80}\bfrom\s+(?:[^\s\"']*/)?vendor/?\b",
    r"\bruntime (?:inputs?|dependenc(?:y|ies))\b[^\n;]{0,80}\b(?:from|loaded from|provided by)\s+(?:the\s+)?(?:vendor tree|vendored examples|vendored reference)\b",
    r"\bcopied source tree\s+(?:\./)?vendor/?\b",
    r"\bpackage source\s+(?:\./)?vendor/?\b",
    r"\b(?:use\s+)?(?:the\s+)?(?:vendor tree|vendored examples|vendored reference|vendor)\s+as\s+(?:an?\s+)?(?:package source|runtime dependency|runtime input|build input|build context)\b",
    r"\b(?:install|apt(?:-get)?|package|packages?)\b[^\n;]{0,80}\bfrom\s+(?:[^\s\"']*/)?vendor/?\b",
    r"\binstall\b[^\n;]{0,120}(?:\./|/|(?:\.\./)+)?vendor/[^\s;]+",
    r"\b(?:apt(?:-get)?|dpkg)\b[^\n;]{0,120}(?:\./|/|(?:\.\./)+)?vendor/[^\s;]+",
    r"\b(?:vendor tree|vendored examples|vendored reference)\b.{0,80}\b(?:runtime inputs?|runtime dependenc(?:y|ies)|package sources?|build inputs?|build context|copied source tree)\b",
    r"\b(?:install|apt(?:-get)?|packages)\b[^\n;]{0,80}\bfrom\s+(?:the\s+)?(?:vendor tree|vendored examples|vendored reference)\b",
    r"\b(?:production image builds?|image builds?|builds?)\b[^\n;]{0,80}\b(?:use|uses)\b[^\n;]{0,80}\b(?:vendor tree|vendored examples|vendored reference)\b",
    r"\b(?:production image builds?|image builds?|builds?)\b[^\n;]{0,80}\b(?:use|uses)\b[^\n;]{0,80}\b(?:vendor tree|vendored examples|vendored reference)\b[^\n;]{0,80}\b(?:package sources?|runtime|build inputs?)\b",
    r"(?:\./)?vendor/.{0,80}(?:runtime inputs?|runtime dependenc(?:y|ies)|copied source tree|package source)",
]
safe_negations = [
    r"\b(?:do not|don't|must not|should not|never|avoid|forbidden to)\s+(?:run\s+)?(?:docker\s+(?:(?:image\s+)?build|buildx\s+(?:build|bake))|podman\s+build|nerdctl\s+build|buildah\s+bud)\b(?:\s+\.)?[^\n;.]{0,120}(?:-f|--file)(?:\s+|=)(?:[^\s\"']*/)?vendor/",
    r"\b(?:do not|don't|must not|should not|never|avoid|forbidden to)\s+(?:run\s+)?docker\s+buildx\b[^\n;.]{0,160}\bbake\b[^\n;.]{0,200}--set(?:\s+|=)[\"']?[^\"'\s=]+\.contexts?(?:\.[A-Za-z0-9_.-]+)?=[\"']?(?:[^\s\"']*/)?vendor(?:/\.?|/[^\s\"']*)?(?:[\"']|\s|$)",
    r"\b(?:do not|don't|must not|should not|never|avoid|forbidden to)\s+(?:run\s+)?(?:docker(?:\s+(?:--(?:context|host|config|log-level)\s+[^\s]+|--[^\s=]+(?:=[^\s]+)?|-[A-Za-z]+))*\s+(?:(?:image\s+)?build|buildx\s+build)|podman\s+build|nerdctl\s+build|buildah\s+bud)\b[^\n;.]{0,160}(?:^|\s)(?:\./|(?:\.\./)+)?vendor/?\.?(?:\s|$)",
    r"\b(?:do not|don't|must not|should not|never|avoid|forbidden to)\s+(?:copy|add|cp|rsync)\b[^\n;]{0,80}(?:\./)?vendor(?:/|\s|$)",
    r"\b(?:do not|don't|must not|should not|never|avoid|forbidden to)\s+(?:use\s+)?(?:\./)?vendor/?(?:\b|(?=\s|$)).{0,80}\b(?:as\s+)?(?:the\s+)?(?:(?:docker\s+)?build context|build input|runtime input|runtime dependency|package source)",
    r"(?:\./)?vendor/?(?:\b|(?=\s|$)).{0,80}\b(?:is not|is never|must not be|must never be)\b.{0,80}(?:an?\s+)?(?:(?:docker\s+)?build context|build input|runtime input|runtime dependency|package source)",
    r"(?:\./)?vendor/.{0,80}\b(?:must not|must never|does not|do not|never)\b.{0,80}(?:runtime inputs?|runtime dependenc(?:y|ies)|copied source tree|package source)",
    r"\b(?:do not|don't|must not|should not|never|avoid|forbidden to)\b.{0,80}(?:runtime inputs?|runtime dependenc(?:y|ies)|copied source tree|package source)\s+(?:\./)?vendor/?\b",
    r"\b(?:vendor tree|vendored examples|vendored reference)\b.{0,80}\b(?:must not|must never|does not|do not|never|is not|are not|is never|are never)\b.{0,80}(?:runtime inputs?|runtime dependenc(?:y|ies)|package sources?|build inputs?|build context|copied source tree)",
    r"\b(?:do not|don't|must not|should not|never|avoid|forbidden to)\b.{0,80}(?:use|install|build|runtime|package).{0,80}\b(?:the\s+)?(?:vendor tree|vendored examples|vendored reference)\b.{0,80}(?:runtime inputs?|runtime dependenc(?:y|ies)|package sources?|build inputs?|build context|copied source tree)?",
]
if re.search(r"(?ims)^\s*(?:copy|add)\s+(?:--[^\s]+\s+)*\[[^\]]*[\"'](?:/|\./|(?:\.\./)+)?vendor(?:/[^\"']*)?[\"'][^\]]*,\s*[\"'][^\"']+[\"']\s*\]", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "multiline COPY/ADD vendor/", "Do not copy vendor/ into production image definitions or examples.")
if is_dockerfile and (
    re.search(r"(?im)^\s*(?:copy|add)\s+(?!--from=)(?:--[^\s]+\s+)*(?:/|\./|(?:\.\./)+)?vendor(?:/|\s|\"|,|]|\)|$)", text)
    or re.search(r"(?im)^\s*(?:copy|add)\s+(?:--[^\s]+\s+)*\[[^\]\n]*[\"'](?:/|\./|(?:\.\./)+)?vendor(?:/[^\"']*)?[\"'][^\]\n]*,\s*[\"'][^\"']+[\"']\s*\]", text)
):
    diag("vendor/ is reference-only and not build/runtime/package input", "Dockerfile COPY/ADD vendor/", "Do not copy vendor/ into production image definitions.")
if re.search(r"(?m)^\s*uses\s*:\s*[\"']?(?:\./|(?:\.\./)+|[A-Za-z0-9_.-]+/)*vendor(?:/|[\"']?\s*$)", text, re.I):
    diag("vendor/ is reference-only and not build/runtime/package input", "workflow uses: ./vendor", "Use checked-in project actions/scripts, not vendor/ runtime dependencies.")
if re.search(r"(?mi)^\s*(?:build|context|dockerfile)\s*[:=]\s*\n\s*[\"']?(?:\./)?vendor(?:/|[\"']?\s*$)", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "multiline build context/dockerfile vendor/", "Keep vendor/ out of build configuration values.")
if re.search(r"(?mi)^\s*additional_contexts\s*:\s*\n(?:\s+[\"']?[A-Za-z0-9_.-]+[\"']?\s*:\s*[\"']?(?:/|\./|(?:\.\./)+)?vendor(?:/[^\"'\s]*)?[\"']?\s*$)+", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "compose additional_contexts vendor/", "Keep vendor/ out of Docker Compose named build contexts.")
if re.search(r"(?mi)^\s*additional_contexts\s*:\s*\n(?:\s+[\"']?[A-Za-z0-9_.-]+[\"']?\s*:\s*[>|][-+]?\s*\n\s*[\"']?(?:/|\./|(?:\.\./)+)?vendor(?:/[^\"'\s]*)?[\"']?\s*$)+", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "compose folded additional_contexts vendor/", "Keep vendor/ out of Docker Compose named build contexts.")
if re.search(r"(?mi)^\s*additional_contexts\s*:\s*\n(?:\s*-\s*[A-Za-z0-9_.-]+=[\"']?(?:/|\./|(?:\.\./)+)?vendor(?:/[^\"'\s]*)?[\"']?\s*$)+", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "compose additional_contexts list vendor/", "Keep vendor/ out of Docker Compose named build contexts.")
if re.search(r"(?mi)^\s*additional_contexts\s*:\s*\{[^}\n]*:\s*[\"']?(?:/|\./|(?:\.\./)+)?vendor(?:/[^\"'\s}]*)?[\"']?[^}\n]*\}", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "compose additional_contexts inline vendor/", "Keep vendor/ out of Docker Compose named build contexts.")
if re.search(r"(?mi)^\s*additional_contexts\s*:\s*\[[^\]\n]*[\"']?[A-Za-z0-9_.-]+=[\"']?(?:/|\./|(?:\.\./)+)?vendor(?:/[^\"'\s\]]*)?[\"']?[^\]\n]*\]", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "compose additional_contexts flow-list vendor/", "Keep vendor/ out of Docker Compose named build contexts.")
def hcl_resolved_value_is_vendor_path(value):
    normalized = value.replace("${path.module}/", "/")
    return re.search(r"(^|/)vendor(/|$)", normalized) is not None
def hcl_split_args(raw):
    args = []
    start = 0
    quote = None
    depth = 0
    for index, char in enumerate(raw):
        if quote:
            if char == quote:
                quote = None
            continue
        if char in "\"'":
            quote = char
            continue
        if char in "([":
            depth += 1
            continue
        if char in ")]" and depth:
            depth -= 1
            continue
        if char == "," and depth == 0:
            args.append(raw[start:index].strip())
            start = index + 1
    args.append(raw[start:].strip())
    return args
def hcl_string_value_is_vendor_path(value):
    return hcl_resolved_value_is_vendor_path(value)
for contexts_string in re.finditer(r"(?is)\bcontexts\s*=\s*\{.{0,400}=\s*[\"']([^\"']+)[\"']", text):
    if hcl_string_value_is_vendor_path(contexts_string.group(1)):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL contexts map vendor/", "Keep vendor/ out of named build contexts.")
for context_string in re.finditer(r"(?im)\bcontext\s*=\s*\"([^\"]+)\"", text):
    if hcl_string_value_is_vendor_path(context_string.group(1)):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context string", "Keep vendor/ out of Docker Bake contexts.")
def hcl_parse_call(expr, name):
    stripped = expr.strip()
    prefix = f"{name}("
    if not stripped.startswith(prefix) or not stripped.endswith(")"):
        return None
    inner = stripped[len(prefix):-1]
    quote = None
    depth = 0
    for char in inner:
        if quote:
            if char == quote:
                quote = None
            continue
        if char in "\"'":
            quote = char
            continue
        if char in "([":
            depth += 1
            continue
        if char in ")]":
            if depth == 0:
                return None
            depth -= 1
    return inner if depth == 0 and quote is None else None
def hcl_eval_expr(expr, ref_name):
    stripped = expr.strip().rstrip(",")
    escaped_ref = re.escape(ref_name)
    list_index = re.fullmatch(r"(.+?)\[\s*([0-9]+)\s*\]", stripped)
    if list_index:
        list_expr = list_index.group(1).strip()
        index = int(list_index.group(2))
        for list_func in ("tolist", "list"):
            wrapped = hcl_parse_call(list_expr, list_func)
            if wrapped is not None:
                list_expr = wrapped.strip()
                break
        if list_expr.startswith("[") and list_expr.endswith("]"):
            items = hcl_split_args(list_expr[1:-1])
            if index < len(items):
                return hcl_eval_expr(items[index], ref_name)
            return "base"
    format_inner = hcl_parse_call(stripped, "format")
    if format_inner is not None:
        parts = hcl_split_args(format_inner)
        if not parts:
            return "base"
        fmt = parts[0].strip()
        if len(fmt) >= 2 and fmt[0] == fmt[-1] == '"':
            return hcl_eval_format_result(fmt[1:-1], ",".join(parts[1:]), ref_name)
        return "base"
    replace_inner = hcl_parse_call(stripped, "replace")
    if replace_inner is not None:
        return hcl_eval_replace_result(replace_inner, ref_name)
    for path_func in ("abspath", "realpath"):
        path_inner = hcl_parse_call(stripped, path_func)
        if path_inner is not None:
            args = hcl_split_args(path_inner)
            return hcl_eval_expr(args[0], ref_name) if args else "base"
    if re.fullmatch(rf"(?:local\.)?{escaped_ref}", stripped) or re.fullmatch(rf"\$\{{(?:local\.)?{escaped_ref}\}}", stripped):
        return "vendor"
    if stripped in {"path.module", "${path.module}"}:
        return "base"
    if len(stripped) >= 2 and stripped[0] == stripped[-1] == '"':
        value = stripped[1:-1]
        value = re.sub(rf"\$\{{(?:local\.)?{escaped_ref}\}}", "vendor", value)
        return value
    return "base"
def hcl_arg_vendor_value(arg, ref_name):
    return hcl_eval_expr(arg, ref_name)
def hcl_arg_resolved_value(arg, ref_name):
    return hcl_eval_expr(arg, ref_name)
def hcl_eval_format_result(format_string, raw_args, ref_name):
    result = format_string
    for arg in hcl_split_args(raw_args):
        result = result.replace("%s", hcl_eval_expr(arg, ref_name), 1)
    return result
def hcl_eval_replace_result(raw_args, ref_name):
    args = hcl_split_args(raw_args)
    if len(args) != 3:
        return "base"
    source = hcl_eval_expr(args[0], ref_name)
    search = hcl_eval_expr(args[1], ref_name)
    replacement = hcl_eval_expr(args[2], ref_name)
    if search == "":
        return source
    return source.replace(search, replacement)
for direct_list_context in re.finditer(r"(?is)\bcontext\s*=\s*\[(.*?)\]\s*\[\s*([0-9]+)\s*\]", text):
    items = hcl_split_args(direct_list_context.group(1))
    index = int(direct_list_context.group(2))
    if index < len(items) and hcl_resolved_value_is_vendor_path(hcl_eval_expr(items[index], "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context multiline list index", "Keep vendor/ out of Docker Bake context list expressions.")
for named_list_context in re.finditer(r"(?is)\bcontexts\s*=\s*\{.{0,600}=\s*\[(.*?)\]\s*\[\s*([0-9]+)\s*\]", text):
    items = hcl_split_args(named_list_context.group(1))
    index = int(named_list_context.group(2))
    if index < len(items) and hcl_resolved_value_is_vendor_path(hcl_eval_expr(items[index], "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor named-context multiline list index", "Keep vendor/ out of Docker Bake named context list expressions.")
for format_match in re.finditer(r"(?im)\bcontext\s*=\s*format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*)\)", text):
    if hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_match.group(1), format_match.group(2), "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context function", "Keep vendor/ out of Docker Bake context functions.")
for format_replace_match in re.finditer(r"(?im)\bcontext\s*=\s*format\(\"([^\"]*%s[^\"]*)\"\s*,\s*(replace\([^\)]*\))\s*\)", text):
    if hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_replace_match.group(1), format_replace_match.group(2), "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context function", "Keep vendor/ out of Docker Bake context functions.")
for replace_match in re.finditer(r"(?im)\bcontext\s*=\s*replace\(\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*,\s*\"vendor\"\s*\)", text):
    if hcl_resolved_value_is_vendor_path(replace_match.group(1).replace(replace_match.group(2), "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context function", "Keep vendor/ out of Docker Bake context functions.")
for replace_format_match in re.finditer(r"(?im)\bcontext\s*=\s*replace\(format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*)\)\s*,\s*\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*\)", text):
    replaced = hcl_eval_format_result(replace_format_match.group(1), replace_format_match.group(2), "__literal_vendor__").replace("__literal_vendor__", "vendor").replace(replace_format_match.group(3), replace_format_match.group(4))
    if hcl_resolved_value_is_vendor_path(replaced):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context function", "Keep vendor/ out of Docker Bake context functions.")
for function_context in re.finditer(r"(?im)\bcontext\s*=\s*((?:format|replace|abspath|realpath)\([^\n#]+\))\s*(?:#.*)?$", text):
    if hcl_resolved_value_is_vendor_path(hcl_eval_expr(function_context.group(1), "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context function", "Keep vendor/ out of Docker Bake context functions.")
for list_index_context in re.finditer(r"(?im)\bcontext\s*=\s*((?:(?:tolist|list)\(\[[^\]]+\]\)|\[[^\]]+\])\s*\[\s*[0-9]+\s*\])\s*(?:#.*)?$", text):
    if hcl_resolved_value_is_vendor_path(hcl_eval_expr(list_index_context.group(1), "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context list index", "Keep vendor/ out of Docker Bake context list expressions.")
if re.search(r"(?im)\bcontext\s*=\s*join\([^;\n]*(?:\$\{path\.module\}/vendor(?:/|[\"'])|/vendor(?:/|[\"'])|[\"']vendor[\"'])", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor context function", "Keep vendor/ out of Docker Bake context functions.")
hcl_contexts_map_prefix = r"\bcontexts\s*=\s*\{(?:(?:\$\{[^}]*\})|[^}]){0,600}"
for format_match in re.finditer(rf"(?is){hcl_contexts_map_prefix}=\s*format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*)\)", text):
    if hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_match.group(1), format_match.group(2), "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor named-context function", "Keep vendor/ out of Docker Bake named context functions.")
for format_replace_match in re.finditer(rf"(?is){hcl_contexts_map_prefix}=\s*format\(\"([^\"]*%s[^\"]*)\"\s*,\s*(replace\([^\)]*\))\s*\)", text):
    if hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_replace_match.group(1), format_replace_match.group(2), "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor named-context function", "Keep vendor/ out of Docker Bake named context functions.")
for replace_match in re.finditer(rf"(?is){hcl_contexts_map_prefix}=\s*replace\(\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*,\s*\"vendor\"\s*\)", text):
    if hcl_resolved_value_is_vendor_path(replace_match.group(1).replace(replace_match.group(2), "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor named-context function", "Keep vendor/ out of Docker Bake named context functions.")
for replace_format_match in re.finditer(rf"(?is){hcl_contexts_map_prefix}=\s*replace\(format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*)\)\s*,\s*\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*\)", text):
    replaced = hcl_eval_format_result(replace_format_match.group(1), replace_format_match.group(2), "__literal_vendor__").replace("__literal_vendor__", "vendor").replace(replace_format_match.group(3), replace_format_match.group(4))
    if hcl_resolved_value_is_vendor_path(replaced):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor named-context function", "Keep vendor/ out of Docker Bake named context functions.")
for function_named_context in re.finditer(rf"(?is){hcl_contexts_map_prefix}=\s*((?:format|replace|abspath|realpath)\([^\n#]+\))", text):
    if hcl_resolved_value_is_vendor_path(hcl_eval_expr(function_named_context.group(1), "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor named-context function", "Keep vendor/ out of Docker Bake named context functions.")
for list_index_named_context in re.finditer(rf"(?is){hcl_contexts_map_prefix}=\s*((?:(?:tolist|list)\(\[[^\]]+\]\)|\[[^\]]+\])\s*\[\s*[0-9]+\s*\])", text):
    if hcl_resolved_value_is_vendor_path(hcl_eval_expr(list_index_named_context.group(1), "__literal_vendor__").replace("__literal_vendor__", "vendor")):
        diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor named-context list index", "Keep vendor/ out of Docker Bake named context list expressions.")
if re.search(rf"(?is){hcl_contexts_map_prefix}=\s*join\([^\n]*(?:\$\{{path\.module\}}/vendor(?:/|[\"'])|/vendor(?:/|[\"'])|[\"']vendor[\"'])", text):
    diag("vendor/ is reference-only and not build/runtime/package input", "HCL direct vendor named-context function", "Keep vendor/ out of Docker Bake named context functions.")
hcl_text = re.sub(r"(?<=[A-Za-z0-9_\]])\[['\"]([^'\"]+)['\"]\]", lambda match: "." + match.group(1), text)
def collapse_hcl_multiline_functions(source):
    output = []
    buffer = []
    depth = 0
    quote = None
    for line in source.splitlines():
        candidate = line.rstrip()
        starts_pending_assignment = re.search(r"=\s*(?:\[\s*)?$", candidate) is not None
        if not buffer and not starts_pending_assignment and not re.search(r"(?:=|\[|,)\s*(?:format|replace)\(", candidate):
            output.append(candidate)
            continue
        buffer.append(candidate.strip() if buffer else candidate)
        for char in candidate:
            if quote:
                if char == quote:
                    quote = None
                continue
            if char in "\"'":
                quote = char
                continue
            if char in "([":
                depth += 1
                continue
            if char in ")]" and depth:
                depth -= 1
        if depth == 0 and quote is None and not starts_pending_assignment:
            output.append(" ".join(part.strip() for part in buffer))
            buffer = []
    if buffer:
        output.extend(buffer)
    return "\n".join(output)
hcl_text = collapse_hcl_multiline_functions(hcl_text)
vendor_hcl_refs = set()
hcl_stack = []
hcl_key = r"(?:[\"']([^\"']+)[\"']|([A-Za-z_][A-Za-z0-9_]*))"
hcl_vendor_value = rf"(?:\"(?:{vendor_assignment}|\$\{{path\.module\}}/vendor(?:/[^\"]*)?)\"|join\([^;\n]*(?:\$\{{path\.module\}}/vendor(?:/|[\"'])|/vendor(?:/|[\"'])|[\"']vendor[\"'])[^;\n]*\))"
def hcl_function_rhs_resolves_vendor_path(rhs):
    return hcl_resolved_value_is_vendor_path(hcl_eval_expr(rhs, "__literal_vendor__").replace("__literal_vendor__", "vendor"))
def add_hcl_list_refs(target, rhs):
    stripped_rhs = rhs.strip()
    wrapped = re.fullmatch(r"(?:tolist|list)\((\[[\s\S]*\])\)", stripped_rhs)
    if wrapped:
        stripped_rhs = wrapped.group(1)
    if not (stripped_rhs.startswith("[") and stripped_rhs.endswith("]")):
        return
    stripped_rhs = re.sub(r"/\*.*?\*/", "", stripped_rhs, flags=re.S)
    items = []
    current = []
    quote = ""
    depth = 0
    for char in stripped_rhs[1:-1]:
        if quote:
            current.append(char)
            if char == quote:
                quote = ""
            continue
        if char in ("'", '"'):
            quote = char
            current.append(char)
            continue
        if char == "(":
            depth += 1
            current.append(char)
            continue
        if char == ")" and depth:
            depth -= 1
            current.append(char)
            continue
        if char == "," and depth == 0:
            items.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    items.append("".join(current).strip())
    for idx, item in enumerate(items):
        item = re.sub(r"/\*.*?\*/", "", item, flags=re.S).strip()
        item = re.sub(r"\s*(?:#|//).*$", "", item).strip()
        if item and re.fullmatch(hcl_vendor_value, item):
            vendor_hcl_refs.add(f"{target}[{idx}]")
        elif item and hcl_function_rhs_resolves_vendor_path(item):
            vendor_hcl_refs.add(f"{target}[{idx}]")
for list_match in re.finditer(rf"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\[[^\]]+\])", hcl_text):
    add_hcl_list_refs(list_match.group(1), list_match.group(2))
for list_match in re.finditer(rf"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:tolist|list)\((\[[^\]]+\])\)", hcl_text):
    add_hcl_list_refs(list_match.group(1), list_match.group(2))
for object_name, key_name, list_rhs in re.findall(rf"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[^}}]{{0,800}}\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*((?:\[[^\]]+\])|(?:(?:tolist|list)\(\[[^\]]+\]\)))", hcl_text):
    add_hcl_list_refs(f"{object_name}.{key_name}", list_rhs)
for object_name, key_name, list_rhs in re.findall(rf"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[^}}]{{0,800}}[\"']([^\"']+)[\"']\s*=\s*((?:\[[^\]]+\])|(?:(?:tolist|list)\(\[[^\]]+\]\)))", hcl_text):
    add_hcl_list_refs(f"{object_name}.{key_name}", list_rhs)
for raw_line in hcl_text.splitlines():
    stripped = raw_line.strip()
    while stripped.startswith("}") and hcl_stack:
        hcl_stack.pop()
        stripped = stripped[1:].lstrip()
    object_match = re.match(rf"{hcl_key}\s*=\s*\{{\s*(?:#.*)?$", stripped)
    if object_match:
        hcl_stack.append(object_match.group(1) or object_match.group(2))
        continue
    scalar_match = re.match(rf"{hcl_key}\s*=\s*{hcl_vendor_value}\s*(?:#.*)?$", stripped)
    if scalar_match and hcl_stack:
        vendor_hcl_refs.add(".".join([*hcl_stack, scalar_match.group(1) or scalar_match.group(2)]))
    function_match = re.match(rf"{hcl_key}\s*=\s*((?:format|replace|abspath|realpath)\([^\n]+\))\s*(?:#.*)?$", stripped)
    if function_match and hcl_stack and hcl_function_rhs_resolves_vendor_path(function_match.group(3)):
        vendor_hcl_refs.add(".".join([*hcl_stack, function_match.group(1) or function_match.group(2)]))
    list_match = re.match(rf"{hcl_key}\s*=\s*(\[[^\]]+\])\s*(?:#.*)?$", stripped)
    if list_match:
        list_name = list_match.group(1) or list_match.group(2)
        add_hcl_list_refs(".".join([*hcl_stack, list_name]) if hcl_stack else list_name, list_match.group(3))
for hcl_var in re.findall(rf"(?is)\bvariable\s+\"([A-Za-z_][A-Za-z0-9_]*)\"\s*\{{[^}}]*\bdefault\s*=\s*{hcl_vendor_value}", hcl_text):
    vendor_hcl_refs.add(hcl_var)
for locals_block in re.findall(r"(?is)\blocals\s*\{([^}]*)\}", hcl_text):
    for hcl_local in re.findall(rf"(?im)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{hcl_vendor_value}", locals_block):
        vendor_hcl_refs.add(hcl_local)
    for hcl_local, rhs in re.findall(r"(?im)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*((?:format|replace|abspath|realpath)\([^\n]+\))", locals_block):
        if hcl_function_rhs_resolves_vendor_path(rhs):
            vendor_hcl_refs.add(hcl_local)
for hcl_local in re.findall(rf"(?im)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{hcl_vendor_value}\s*$", hcl_text):
    vendor_hcl_refs.add(hcl_local)
for hcl_local, rhs in re.findall(r"(?im)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*((?:format|replace|abspath|realpath)\([^\n]+\))\s*$", hcl_text):
    if hcl_function_rhs_resolves_vendor_path(rhs):
        vendor_hcl_refs.add(hcl_local)
for object_name, key_name in re.findall(rf"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[^}}]{{0,400}}\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{hcl_vendor_value}", hcl_text):
    vendor_hcl_refs.add(f"{object_name}.{key_name}")
for object_name, key_name in re.findall(rf"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[^}}]{{0,400}}[\"']([^\"']+)[\"']\s*=\s*{hcl_vendor_value}", hcl_text):
    vendor_hcl_refs.add(f"{object_name}.{key_name}")
for object_name, key_name, rhs in re.findall(r"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{[\s\S]{0,400}\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*((?:format|replace|abspath|realpath)\([^\n]*?\))", hcl_text):
    if hcl_function_rhs_resolves_vendor_path(rhs):
        vendor_hcl_refs.add(f"{object_name}.{key_name}")
for object_name, key_name, rhs in re.findall(r"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{[\s\S]{0,400}[\"']([^\"']+)[\"']\s*=\s*((?:format|replace|abspath|realpath)\([^\n]*?\))", hcl_text):
    if hcl_function_rhs_resolves_vendor_path(rhs):
        vendor_hcl_refs.add(f"{object_name}.{key_name}")
for object_name, nested_name, key_name in re.findall(rf"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[\s\S]{{0,600}}\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[\s\S]{{0,400}}\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{hcl_vendor_value}", hcl_text):
    vendor_hcl_refs.add(f"{object_name}.{nested_name}.{key_name}")
for object_name, nested_a, nested_b, key_name in re.findall(rf"(?is)\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[\s\S]{{0,900}}\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[\s\S]{{0,700}}\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{{[\s\S]{{0,500}}\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{hcl_vendor_value}", hcl_text):
    vendor_hcl_refs.add(f"{object_name}.{nested_a}.{nested_b}.{key_name}")
def hcl_rhs_refs_vendor_ref(rhs, refs):
    for ref_name in sorted(refs, key=len, reverse=True):
        escaped_ref = re.escape(ref_name)
        boundary = r"\b" if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*", ref_name) else ""
        if re.search(rf"(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}}", rhs):
            resolved_rhs = hcl_eval_expr(rhs, ref_name)
            if resolved_rhs != "base":
                return hcl_resolved_value_is_vendor_path(resolved_rhs)
            stripped_rhs = rhs.strip()
            wrapped_list = re.fullmatch(r"(?:tolist|list)\((\[[\s\S]*\])\)", stripped_rhs)
            if wrapped_list:
                stripped_rhs = wrapped_list.group(1)
            if stripped_rhs.startswith("[") and stripped_rhs.endswith("]"):
                for item in hcl_split_args(stripped_rhs[1:-1]):
                    if re.search(rf"(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}}", item) and hcl_resolved_value_is_vendor_path(hcl_eval_expr(item, ref_name)):
                        return True
        format_replace_rhs = re.search(rf"format\(\"([^\"]*%s[^\"]*)\"\s*,\s*(replace\([^\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\)]*\))\s*\)", rhs)
        if format_replace_rhs:
            return hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_replace_rhs.group(1), format_replace_rhs.group(2), ref_name))
        format_rhs = re.search(r"format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*)\)", rhs)
        if format_rhs and re.search(rf"(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}}", format_rhs.group(2)):
            return hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_rhs.group(1), format_rhs.group(2), ref_name))
        replace_format_rhs = re.search(r"replace\(format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*)\)\s*,\s*\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*\)", rhs)
        if replace_format_rhs and re.search(rf"(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}}", replace_format_rhs.group(2)):
            replaced = hcl_eval_format_result(replace_format_rhs.group(1), replace_format_rhs.group(2), ref_name).replace(replace_format_rhs.group(3), replace_format_rhs.group(4))
            return hcl_resolved_value_is_vendor_path(replaced)
        replace_rhs = re.search(r"replace\(([^;\n\)]*)\)", rhs)
        if replace_rhs and re.search(rf"(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}}", replace_rhs.group(1)):
            return hcl_resolved_value_is_vendor_path(hcl_eval_replace_result(replace_rhs.group(1), ref_name))
        quoted_ref_rhs = re.fullmatch(rf"\"([^\"]*(?:\$\{{(?:local\.)?{escaped_ref}\}})[^\"]*)\"", rhs.strip())
        if quoted_ref_rhs:
            return hcl_resolved_value_is_vendor_path(hcl_arg_resolved_value(rhs, ref_name))
        if re.search(rf"\b(?:local\.)?{escaped_ref}{boundary}", rhs) or re.search(rf"\$\{{(?:local\.)?{escaped_ref}\}}", rhs):
            return True
    return False
def add_hcl_derived_refs():
    changed = False
    stack = []
    for raw_line in hcl_text.splitlines():
        stripped = raw_line.strip()
        while stripped.startswith("}") and stack:
            stack.pop()
            stripped = stripped[1:].lstrip()
        object_match = re.match(rf"{hcl_key}\s*=\s*\{{\s*(?:#.*)?$", stripped)
        if object_match:
            stack.append(object_match.group(1) or object_match.group(2))
            continue
        assign_match = re.match(rf"{hcl_key}\s*=\s*(.+?)\s*(?:#.*)?$", stripped)
        if not assign_match:
            continue
        name = assign_match.group(1) or assign_match.group(2)
        target = ".".join([*stack, name]) if stack else name
        rhs = assign_match.group(3)
        if hcl_rhs_refs_vendor_ref(rhs, vendor_hcl_refs) and target not in vendor_hcl_refs:
            vendor_hcl_refs.add(target)
            changed = True
    return changed
while add_hcl_derived_refs():
    pass
for ref_name in vendor_hcl_refs:
    escaped_ref = re.escape(ref_name)
    boundary = r"\b" if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*", ref_name) else ""
    context_expr = re.search(rf"(?im)\bcontext\s*=\s*([^\n#]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\n#]*)", hcl_text)
    named_context_expr = re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*=\s*([^\n#}}]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\n#}}]*)", hcl_text)
    format_context = re.search(rf"(?im)\bcontext\s*=\s*format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\)]*)\)", hcl_text)
    format_replace_context = re.search(rf"(?im)\bcontext\s*=\s*format\(\"([^\"]*%s[^\"]*)\"\s*,\s*(replace\([^\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\)]*\))\s*\)", hcl_text)
    replace_format_context = re.search(rf"(?im)\bcontext\s*=\s*replace\(format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\)]*)\)\s*,\s*\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*\)", hcl_text)
    replace_context = re.search(rf"(?im)\bcontext\s*=\s*replace\(\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*,\s*(?:local\.)?{escaped_ref}{boundary}\s*\)", hcl_text)
    replace_context_any = re.search(rf"(?im)\bcontext\s*=\s*replace\(([^\n\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\n\)]*)\)", hcl_text)
    format_named_context = re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\)]*)\)", hcl_text)
    format_replace_named_context = re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*format\(\"([^\"]*%s[^\"]*)\"\s*,\s*(replace\([^\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\)]*\))\s*\)", hcl_text)
    replace_format_named_context = re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*replace\(format\(\"([^\"]*%s[^\"]*)\"\s*,\s*([^\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\)]*)\)\s*,\s*\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*\)", hcl_text)
    replace_named_context = re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*replace\(\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*,\s*(?:local\.)?{escaped_ref}{boundary}\s*\)", hcl_text)
    replace_named_context_any = re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*replace\(([^\)]*(?:(?:local\.)?{escaped_ref}{boundary}|\$\{{(?:local\.)?{escaped_ref}\}})[^\)]*)\)", hcl_text)
    if (
        re.search(rf"(?im)\bcontext\s*=\s*(?:local\.)?{escaped_ref}{boundary}", hcl_text)
        or (context_expr and hcl_resolved_value_is_vendor_path(hcl_eval_expr(context_expr.group(1), ref_name)))
        or re.search(rf"(?im)\bcontext\s*=\s*\"\$\{{(?:local\.)?{escaped_ref}\}}(?:/[^\"']*)?\"", hcl_text)
        or re.search(rf"(?im)\bcontext\s*=\s*\"\$\{{path\.module\}}/\$\{{(?:local\.)?{escaped_ref}\}}(?:/[^\"']*)?\"", hcl_text)
        or re.search(rf"(?im)\bcontext\s*=\s*\"[^\"]*/\$\{{(?:local\.)?{escaped_ref}\}}(?:/[^\"']*)?\"", hcl_text)
        or re.search(rf"(?im)\bcontext\s*=\s*join\([^;\n]*(?:local\.)?{escaped_ref}{boundary}", hcl_text)
        or re.search(rf"(?im)\bcontext\s*=\s*abspath\([^;\n]*(?:local\.)?{escaped_ref}{boundary}", hcl_text)
        or (format_context and hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_context.group(1), format_context.group(2), ref_name)))
        or (format_replace_context and hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_replace_context.group(1), format_replace_context.group(2), ref_name)))
        or (replace_format_context and hcl_resolved_value_is_vendor_path(hcl_eval_format_result(replace_format_context.group(1), replace_format_context.group(2), ref_name).replace(replace_format_context.group(3), replace_format_context.group(4))))
        or (replace_context and hcl_resolved_value_is_vendor_path(replace_context.group(1).replace(replace_context.group(2), "vendor")))
        or (replace_context_any and hcl_resolved_value_is_vendor_path(hcl_eval_replace_result(replace_context_any.group(1), ref_name)))
        or re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*=\s*(?:local\.)?{escaped_ref}{boundary}(?:\s*[,}}])", hcl_text)
        or (named_context_expr and hcl_resolved_value_is_vendor_path(hcl_eval_expr(named_context_expr.group(1), ref_name)))
        or re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*\"\$\{{(?:local\.)?{escaped_ref}\}}(?:/[^\"']*)?\"", hcl_text)
        or re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*\"\$\{{path\.module\}}/\$\{{(?:local\.)?{escaped_ref}\}}(?:/[^\"']*)?\"", hcl_text)
        or re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*\"[^\"]*/\$\{{(?:local\.)?{escaped_ref}\}}(?:/[^\"']*)?\"", hcl_text)
        or re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*join\([^}}]*(?:local\.)?{escaped_ref}{boundary}", hcl_text)
        or re.search(rf"(?is)\bcontexts\s*=\s*\{{[^}}]*abspath\([^}}]*(?:local\.)?{escaped_ref}{boundary}", hcl_text)
        or (format_named_context and hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_named_context.group(1), format_named_context.group(2), ref_name)))
        or (format_replace_named_context and hcl_resolved_value_is_vendor_path(hcl_eval_format_result(format_replace_named_context.group(1), format_replace_named_context.group(2), ref_name)))
        or (replace_format_named_context and hcl_resolved_value_is_vendor_path(hcl_eval_format_result(replace_format_named_context.group(1), replace_format_named_context.group(2), ref_name).replace(replace_format_named_context.group(3), replace_format_named_context.group(4))))
        or (replace_named_context and hcl_resolved_value_is_vendor_path(replace_named_context.group(1).replace(replace_named_context.group(2), "vendor")))
        or (replace_named_context_any and hcl_resolved_value_is_vendor_path(hcl_eval_replace_result(replace_named_context_any.group(1), ref_name)))
    ):
        diag("vendor/ is reference-only and not build/runtime/package input", f"HCL vendor context indirection {ref_name}", "Keep vendor/ out of Docker Bake context variables and locals.")

def is_safe_match(clause, unsafe_match):
    for safe in safe_negations:
        for safe_match in re.finditer(safe, clause, re.I):
            if unsafe_match.start() < safe_match.start() or unsafe_match.end() > safe_match.end():
                continue
            prefix = clause[safe_match.start():unsafe_match.start()]
            if re.search(r"[,.:]\s*\S", prefix):
                continue
            return True
    return False

for clause in re.split(r"\n|;|,\s*then\b|\bthen\b|&&|\|\||\bbut\b|\band\b|\bor\b", text):
    for pattern in patterns:
        for match in re.finditer(pattern, clause, re.I):
            if re.search(r"\b(?:COPY|ADD)\s+--from=vendor\b", match.group(0), re.I):
                continue
            if is_safe_match(clause, match):
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
  git -C "${ROOT_DIR}" ls-files -z --cached --others --exclude-standard -- \
    'cloudnative-pg-timescaledb/**' \
    'docs/generated-files.md' \
    ':(exclude)vendor/**' \
    ':(exclude)cloudnative-pg-timescaledb/vendor/**' \
    ':(exclude)_bmad/**' \
    ':(exclude)_bmad-output/**' \
    ':(exclude).agents/**' \
    ':(exclude)**/__pycache__/**' \
    ':(exclude)**/*.pyc' \
    ':(exclude)cloudnative-pg-timescaledb/tests/**'
}

should_scan_vendor_file() {
  case "$1" in
    *Dockerfile*|*dockerfile*|*Containerfile*|*containerfile*|Makefile|*/Makefile|*.mk|*.hcl|*.json|*.toml|*.md|*.yml|*.yaml|*.sh|*.bash|*.zsh|*.ksh|*.fish|cloudnative-pg-timescaledb/scripts/*|scripts/*|bin/*)
      return 0
      ;;
  esac
  return 1
}

is_shebang_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 1
  [[ "$(head -c 2 "${file}" 2>/dev/null || true)" == "#!" ]]
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
inline_comment_metadata="$(mktemp)"
sed 's/schema_version: "1"/schema_version: "1" # scaffold metadata/' "${FIXTURE_DIR}/metadata/valid-minimal.yaml" >"${inline_comment_metadata}"
validate_metadata "${inline_comment_metadata}"
rm -f "${inline_comment_metadata}"
inline_comment_headers_metadata="$(mktemp)"
sed -e 's/image:/image: # scaffold image metadata/' -e 's/allowed:/allowed: # allowed values/' -e 's/entries:/entries: # matrix rows/' "${FIXTURE_DIR}/metadata/valid-minimal.yaml" >"${inline_comment_headers_metadata}"
validate_metadata "${inline_comment_headers_metadata}"
rm -f "${inline_comment_headers_metadata}"
block_platforms_metadata="$(mktemp)"
sed 's|platforms: \\["linux/amd64", "linux/arm64"\\]|platforms:\\n      - "linux/amd64"\\n      - "linux/arm64"|g' "${FIXTURE_DIR}/metadata/valid-minimal.yaml" >"${block_platforms_metadata}"
validate_metadata "${block_platforms_metadata}"
rm -f "${block_platforms_metadata}"
block_allowed_metadata="$(mktemp)"
sed \
  -e 's|postgres_majors: \\["17", "18", "19beta1"\\]|postgres_majors:\\n    - "17"\\n    - "18"\\n    - "19beta1"|' \
  -e 's|debian_variants: \\["trixie", "bookworm"\\]|debian_variants:\\n    - trixie\\n    - bookworm|' \
  -e 's|platforms: \\["linux/amd64", "linux/arm64"\\]|platforms:\\n    - "linux/amd64"\\n    - "linux/arm64"|' \
  "${FIXTURE_DIR}/metadata/valid-minimal.yaml" >"${block_allowed_metadata}"
validate_metadata "${block_allowed_metadata}"
rm -f "${block_allowed_metadata}"
expect_fail "missing top-level keys" --contains "top-level keys include" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-top-level.yaml"
expect_fail "empty entries list" --contains "entries is a non-empty list" validate_metadata "${FIXTURE_DIR}/metadata/invalid-empty-entries.yaml"
expect_fail "missing required entry field" --contains "contains all required fields" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-required-entry-field.yaml"
expect_fail "pg19beta1 not experimental" --contains "19beta1 entries set experimental true" validate_metadata "${FIXTURE_DIR}/metadata/invalid-pg19beta1-not-experimental.yaml"
expect_fail "latest eligible on non-current row" --contains "latest_eligible true only for 18-trixie" validate_metadata "${FIXTURE_DIR}/metadata/invalid-latest-eligible-not-18-trixie.yaml"
expect_fail "missing latest eligible on 18-trixie" --contains "latest_eligible true only for 18-trixie" validate_metadata "${FIXTURE_DIR}/metadata/invalid-latest-eligible-missing-18-trixie.yaml"
expect_fail "empty resolver values without skip" --contains "non-published rows have non-empty skip_reason" validate_metadata "${FIXTURE_DIR}/metadata/invalid-empty-resolver-owned-without-skip.yaml"
expect_fail "publishable without digest" --contains "publishable rows have resolver-owned values" validate_metadata "${FIXTURE_DIR}/metadata/invalid-publishable-without-digest.yaml"
expect_fail "publishable with resolver values" --contains "resolver-owned fields empty" validate_metadata "${FIXTURE_DIR}/metadata/invalid-publishable-with-resolver-values.yaml"
expect_fail "unsupported postgres major" --contains "pg_major in" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unsupported-postgres-major.yaml"
expect_fail "unsupported debian variant" --contains "debian_variant in" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unsupported-debian-variant.yaml"
expect_fail "unsupported platform" --contains "platforms subset" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unsupported-platform.yaml"
expect_fail "missing required platform" --contains "is non-empty list" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-platform.yaml"
expect_fail "duplicate entry" --contains "no duplicate pg_major/debian_variant rows" validate_metadata "${FIXTURE_DIR}/metadata/invalid-duplicate-entry.yaml"
expect_fail "duplicate YAML key" --contains "unique YAML mapping keys" validate_metadata "${FIXTURE_DIR}/metadata/invalid-duplicate-key.yaml"
expect_fail "missing matrix combination" --contains "entries exactly" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-matrix-combination.yaml"
expect_fail "wrong type" --contains "is boolean|is non-empty list" validate_metadata "${FIXTURE_DIR}/metadata/invalid-wrong-types.yaml"
expect_fail "unquoted numeric string field" --contains "schema_version == '1'|is string" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unquoted-numeric.yaml"
expect_fail "numeric entry string field" --contains "entries\\[0\\]\\.pg_major is string" validate_metadata "${FIXTURE_DIR}/metadata/invalid-entry-string-field-numeric.yaml"
expect_fail "unbalanced quoted scalar" --contains "balanced quoted YAML scalar" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unbalanced-quote.yaml"
expect_fail "quoted scalar trailing junk" --contains "balanced quoted YAML scalar" validate_metadata "${FIXTURE_DIR}/metadata/invalid-quoted-scalar-trailing-junk.yaml"
expect_fail "empty pg_version" --contains "pg_version is non-empty" validate_metadata "${FIXTURE_DIR}/metadata/invalid-empty-pg-version.yaml"
expect_fail "bad YAML structure" --contains "image is mapping|allowed is mapping|entries\[0\] is mapping" validate_metadata "${FIXTURE_DIR}/metadata/invalid-bad-structure.yaml"
expect_fail "missing image fields" --contains "image\.(registry|repository)" validate_metadata "${FIXTURE_DIR}/metadata/invalid-missing-image-field.yaml"
expect_fail "unknown top-level metadata field" --contains "top-level keys exactly" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unknown-top-level.yaml"
expect_fail "unknown entry metadata field" --contains "entries\[0\] keys exactly" validate_metadata "${FIXTURE_DIR}/metadata/invalid-unknown-entry-field.yaml"
expect_fail "non-empty resolver field" --contains "resolver-owned fields empty" validate_metadata "${FIXTURE_DIR}/metadata/invalid-non-empty-resolver-field.yaml"
expect_fail "stable pg marked experimental" --contains "stable PostgreSQL entries set experimental false" validate_metadata "${FIXTURE_DIR}/metadata/invalid-stable-experimental.yaml"
expect_fail "blank skip reason" --contains "non-published rows have non-empty skip_reason" validate_metadata "${FIXTURE_DIR}/metadata/invalid-blank-skip-reason.yaml"
expect_fail "blank cnpg tag" --contains "cnpg_tag is scaffolded" validate_metadata "${FIXTURE_DIR}/metadata/invalid-blank-cnpg-tag.yaml"
source_truth_fixtures=(
  "${FIXTURE_DIR}/docs/invalid-source-of-truth.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-workflow-matrices.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-github-actions-matrix.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-catalogs.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-generated-docs.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-generated-files.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-readme-tables.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-paraphrase.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-plural.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-reverse-canonical.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-leading-negation.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-other-file.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-matrix-manual.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-bake.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-unrelated-not.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-no-longer.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-mixed-safe-conflict.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-comma-subject.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-safe-prefix.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-and-safe-prefix.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-which-other-file.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-authoritative.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-authority-edited-by-hand.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-hand-maintained-authoritative.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-manual-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-manually-edited-combinations.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-maintained-by-hand-matrix.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-manually-curated-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-hand-curated-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-hand-curated-space-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-hand-authored-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-human-maintained-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-human-curated-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-human-authored-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-maintained-manually-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-maintainer-edit-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-manually-authored-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-manually-edited-and-authoritative.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-manually-maintained-defines.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-maintained-manually-definitions.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-hand-edited-unhyphenated.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-hand-edited-image-definitions.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-updated-by-hand-matrix.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-canonical-edit-place.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-defines-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-defines-metadata-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-forms-metadata-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-forms-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-canonical-definitions.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-authoritative-pure.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-canonical-pure.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-canonical-metadata-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-readme-canonical-compatibility.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-serve-metadata-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-act-metadata-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-serve-metadata-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-is-metadata-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-source-of-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-origin-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-provenance-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-provides-provenance-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-basis-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-forms-basis-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-foundation-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-generated-outputs-basis.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-generated-outputs-drive-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-generated-outputs-control-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-generated-outputs-govern-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-source-data.md"
      "${FIXTURE_DIR}/docs/invalid-source-of-truth-source-for-image-combinations.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-sources-for-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-authority-for-image-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-serve-as.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-inherited-canonical.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-pronoun-canonical.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-pronoun-metadata-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-pronoun-source-for-metadata.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-authoritative-combinations.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-definitive-supported.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-modal-canonical.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-modal-pronoun.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-modal-edit-by-hand.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-and-modal-mask.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-pronoun-combinations.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-pronoun-govern.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-pronoun-determine.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-same-sentence-pronoun.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-same-sentence-pronoun-govern.md"
      "${FIXTURE_DIR}/docs/invalid-source-of-truth-bare-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-negated-then-bare-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-negated-canonical-then-source.md"
      "${FIXTURE_DIR}/docs/invalid-source-of-truth-negated-govern-then-govern.md"
      "${FIXTURE_DIR}/docs/invalid-source-of-truth-not-canonical-but-govern.md"
      "${FIXTURE_DIR}/docs/invalid-source-of-truth-not-canonical-but-source.md"
	  "${FIXTURE_DIR}/docs/invalid-source-of-truth-not-canonical-but-authoritative.md"
	  "${FIXTURE_DIR}/docs/invalid-source-of-truth-not-canonical-but-serve-source.md"
	  "${FIXTURE_DIR}/docs/invalid-source-of-truth-not-canonical-but-served-source.md"
	  "${FIXTURE_DIR}/docs/invalid-source-of-truth-function-as-source.md"
	  "${FIXTURE_DIR}/docs/invalid-source-of-truth-operate-as-source.md"
	  "${FIXTURE_DIR}/docs/invalid-source-of-truth-pronoun-bare-authority.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-hyphenated.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-negated.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-wrapped-source.md"
  "${FIXTURE_DIR}/docs/invalid-source-of-truth-wrapped-canonical.md"
)
for file in "${source_truth_fixtures[@]}"; do
  test -f "${file}" || { diag "test -f ${file}" "${file}" "fixture exists" "missing" "Restore the required docs source-of-truth fixture."; exit 1; }
  expect_fail "competing source of truth docs ${file}" --contains "no generated artifact category|only versions.yaml|versions.yaml remains" validate_docs_source_of_truth_negative_fixture "${file}"
done
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-non-source-of-truth-negation.md"
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-generated-from-versions.md"
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-generated-from-versions-remains.md"
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-generated-from-versions-apposition.md"
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-plural-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-synonym-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-generic-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-image-tags-canonical.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-serve-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-comma-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-list-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-canonical-source-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-metadata-source-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-bare-metadata-authority-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-serve-metadata-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-authority-for-metadata-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-source-authority-of-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-leading-source-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-plural-source-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-do-not-plural-source-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-hand-edited-image-definitions-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-metadata-source-verb-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-generated-outputs-control-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-function-as-negation.md" 0
validate_docs_source_of_truth "${FIXTURE_DIR}/docs/valid-source-of-truth-operate-as-negation.md" 0
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-prose-add.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-build-context-imperative-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-first-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-stage-alias.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-stage-alias.Dockerfile"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-copy-destination.Dockerfile"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-label.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-build-context-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-build-context-imperative-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-build-context-should-not.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-buildx-bake-set-context-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-vendored-examples-runtime-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-tree-build-input-negation.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-shell-array-scalar-non-first.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-shell-array-slice-non-vendor.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-shell-direct-array-overwrite.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-make-firstword-nonvendor.mk"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-make-word-nonvendor.mk"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-make-subst-remove-build-context.mk"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-make-addsuffix-nonvendor.mk"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-make-foreach-nonvendor.mk"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-shell-concat-nonvendor.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-make-concat-nonvendor.mk"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-fish-concat-nonvendor.fish"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-make-call-concat-nonvendor.mk"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-local-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-format-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-literal-format-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-literal-replace-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-derived-format-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-derived-interpolation-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-named-format-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-local-format-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-local-replace-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-direct-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-abspath-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-local-abspath-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-list-abspath-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-abspath-format-concat-nonvendor.hcl"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-hcl-local-abspath-format-concat-nonvendor.hcl"
expect_fail "vendor build context docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-build-context.md"
expect_fail "vendor reverse build context docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-build-context-reverse.md"
expect_fail "vendor build context comes from docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-build-context-comes-from.md"
expect_fail "vendor buildkit mount" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildkit-mount.md"
expect_fail "vendor copy source docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-copy-source.md"
expect_fail "vendor dockerfile forms" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-forms.md"
expect_fail "vendor dockerfile json form only" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-json-only.Dockerfile"
expect_fail "vendor dockerfile json second source" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-json-second-source.Dockerfile"
expect_fail "vendor dockerfile json copy with flag" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-json-copy-with-flag.Dockerfile"
expect_fail "vendor dockerfile multiline json form" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-multiline-json.Dockerfile"
expect_fail "vendor dockerfile arg copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-arg-copy.Dockerfile"
expect_fail "vendor dockerfile arg default copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-arg-default-copy.Dockerfile"
expect_fail "vendor dockerfile arg quoted default copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-arg-quoted-default-copy.Dockerfile"
expect_fail "vendor dockerfile arg dot copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-arg-dot.Dockerfile"
expect_fail "vendor dockerfile env space copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-env-space-copy.Dockerfile"
expect_fail "vendor dockerfile env multi assignment copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-env-multi-copy.Dockerfile"
expect_fail "vendor dockerfile leading slash copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-leading-slash.Dockerfile"
expect_fail "vendor markdown lowercase copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-markdown-lowercase-copy.md"
expect_fail "vendor markdown list copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-markdown-list-copy.md"
expect_fail "vendor markdown list lowercase copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-markdown-list-lowercase-copy.md"
expect_fail "vendor lowercase dockerfile copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-lowercase-copy.Dockerfile"
expect_fail "vendor containerfile copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-containerfile-copy.Containerfile"
expect_fail "vendor docker build command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build.md"
expect_fail "vendor parent-relative docker build command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-parent-relative-build.md"
expect_fail "vendor docker build subdir command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build-subdir.md"
expect_fail "vendor docker image build command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-image-build.md"
expect_fail "vendor docker build platform option" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build-platform.md"
expect_fail "vendor docker build tag option" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build-tag.md"
expect_fail "vendor docker build absolute context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build-absolute.md"
expect_fail "vendor docker build normalized context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build-normalized.md"
expect_fail "vendor split quoted pwd context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-split-quoted-pwd.md"
expect_fail "vendor docker stdin file" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-stdin-file.md"
expect_fail "vendor quoted docker build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-build-context-quoted.md"
expect_fail "vendor quoted build context flag" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-build-context-quoted-build-context.md"
expect_fail "vendor equals build context flag" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-build-context-equals.md"
expect_fail "vendor build context subdir flag" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-build-context-subdir.md"
expect_fail "vendor docker debug build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-debug-build.md"
expect_fail "vendor docker short debug build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-short-debug-build.md"
expect_fail "vendor docker global option build" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-global-option-build.md"
expect_fail "vendor docker buildx command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildx.md"
expect_fail "vendor docker buildx builder option command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildx-builder-option.md"
expect_fail "vendor dockerfile flag after dot context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build-dot-file.md"
expect_fail "vendor docker build line continuation" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-build-line-continuation.md"
expect_fail "vendor docker buildx bake file" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildx-bake-file.md"
expect_fail "vendor podman build command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-podman-build.md"
expect_fail "vendor podman build subdir command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-podman-build-subdir.md"
expect_fail "vendor nerdctl build command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-nerdctl-build.md"
expect_fail "vendor buildah bud command" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildah-bud.md"
expect_fail "vendor json context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-json-context.md"
expect_fail "vendor config include" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-config-include.md"
expect_fail "vendor config files" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-config-files.md"
expect_fail "vendor hcl join context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-join-context.hcl"
expect_fail "vendor hcl contexts map" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-contexts-map.hcl"
expect_fail "vendor hcl contexts map subdir" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-contexts-map-subdir.hcl"
expect_fail "vendor hcl prefixed contexts map" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-contexts-prefixed.hcl"
expect_fail "vendor hcl variable context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-variable-context.hcl"
expect_fail "vendor hcl local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-local-context.hcl"
expect_fail "vendor hcl path module local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-path-module-local-context.hcl"
expect_fail "vendor hcl object local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-object-local-context.hcl"
expect_fail "vendor hcl nested object local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-nested-object-local-context.hcl"
expect_fail "vendor hcl variable interpolated context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-variable-interpolated-context.hcl"
expect_fail "vendor hcl variable join context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-variable-join-context.hcl"
expect_fail "vendor hcl variable format context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-variable-format-context.hcl"
expect_fail "vendor hcl variable replace context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-variable-replace-context.hcl"
expect_fail "vendor hcl format prefixed context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-prefixed-context.hcl"
expect_fail "vendor hcl format replace context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-replace-context.hcl"
expect_fail "vendor hcl format interpolation arg context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-interpolation-arg-context.hcl"
expect_fail "vendor hcl format replace local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-replace-local-context.hcl"
expect_fail "vendor hcl format replace derived local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-replace-derived-local-context.hcl"
expect_fail "vendor hcl format replace list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-replace-list-index-context.hcl"
expect_fail "vendor hcl format format context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-format-context.hcl"
expect_fail "vendor hcl format format derived local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-format-derived-local-context.hcl"
expect_fail "vendor hcl format format list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-format-list-index-context.hcl"
expect_fail "vendor hcl multiline format format context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-multiline-format-format-context.hcl"
expect_fail "vendor hcl multiline format format derived local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-multiline-format-format-derived-local-context.hcl"
expect_fail "vendor hcl multiline format format list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-multiline-format-format-list-index-context.hcl"
expect_fail "vendor hcl assignment-break format derived local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-assignment-break-format-derived-local-context.hcl"
expect_fail "vendor hcl assignment-break format list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-assignment-break-format-list-index-context.hcl"
expect_fail "vendor hcl replace prefixed context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-replace-prefixed-context.hcl"
expect_fail "vendor hcl replace first-arg context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-replace-first-arg-context.hcl"
expect_fail "vendor hcl replace nested-format context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-replace-nested-format-context.hcl"
expect_fail "vendor hcl replace literal-format context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-replace-literal-format-context.hcl"
expect_fail "vendor hcl replace literal-format named context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-replace-literal-format-named-context.hcl"
expect_fail "vendor hcl replace replace context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-replace-replace-context.hcl"
expect_fail "vendor hcl replace replace derived local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-replace-replace-derived-local-context.hcl"
expect_fail "vendor hcl replace replace list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-replace-replace-list-index-context.hcl"
expect_fail "vendor hcl multiline replace replace context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-multiline-replace-replace-context.hcl"
expect_fail "vendor hcl multiline replace replace derived local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-multiline-replace-replace-derived-local-context.hcl"
expect_fail "vendor hcl multiline replace replace list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-multiline-replace-replace-list-index-context.hcl"
expect_fail "vendor hcl format second arg context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-format-second-arg-context.hcl"
expect_fail "vendor hcl local abspath context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-local-abspath-context.hcl"
expect_fail "vendor hcl local path module interpolation context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-local-path-module-interpolation-context.hcl"
expect_fail "vendor hcl local prefixed interpolation context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-local-prefixed-interpolation-context.hcl"
expect_fail "vendor buildkit build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildkit-build-context.md"
expect_fail "vendor workflow uses local action" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-workflow-uses.md"
expect_fail "vendor absolute context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-absolute-context.md"
expect_fail "vendor compose build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-build.md"
expect_fail "vendor compose file input" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-file.md"
expect_fail "vendor compose additional contexts" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts.yaml"
expect_fail "vendor compose quoted additional contexts key" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-quoted-key.yaml"
expect_fail "vendor compose folded additional contexts" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-folded.yaml"
expect_fail "vendor compose chomped folded additional contexts" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-chomped-folded.yaml"
expect_fail "vendor compose additional contexts list" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-list.yaml"
expect_fail "vendor compose additional contexts inline" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-inline.yaml"
expect_fail "vendor compose additional contexts subdir" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-subdir.yaml"
expect_fail "vendor compose additional contexts list subdir" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-list-subdir.yaml"
expect_fail "vendor compose anchor context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-anchor-context.yaml"
expect_fail "vendor compose anchor additional context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-anchor-additional-context.yaml"
expect_fail "vendor compose sequence anchor context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-sequence-anchor-context.yaml"
expect_fail "vendor compose inline-map anchor additional context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-inline-map-anchor-additional-context.yaml"
expect_fail "vendor compose additional contexts flow list" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-flow-list.yaml"
expect_fail "vendor compose additional contexts quoted flow list" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-compose-additional-contexts-quoted-flow-list.yaml"
expect_fail "vendor multiline build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-multiline-context.yaml"
expect_fail "vendor unrelated negation" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-unrelated-negation.md"
expect_fail "vendor masked second match" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-masked-second-match.md"
expect_fail "vendor same-line safe prefix" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-same-line-safe-prefix.md"
expect_fail "vendor and safe prefix" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-and-safe-prefix.md"
expect_fail "vendor comma then safe prefix" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-comma-then-safe-prefix.md"
expect_fail "vendor package source from" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-package-source-from.md"
expect_fail "vendor execute helper" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-execute-helper.md"
expect_fail "vendor direct executable" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-direct-exec.md"
expect_fail "vendor apt package file" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-apt-file.md"
expect_fail "vendor dpkg package file" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dpkg-file.md"
expect_fail "vendor install file" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-install-file.Dockerfile"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-vendor-tree-negation.md"
expect_fail "vendor tree runtime docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-tree-runtime.md"
expect_fail "vendor tree package docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-tree-package.md"
expect_fail "vendored examples package docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-vendored-examples.md"
expect_fail "vendored examples build docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-vendored-examples-build.md"
expect_fail "vendored examples copied source docs" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-vendored-examples-copied-source.md"
expect_fail "vendor dockerfile path" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-path.md"
expect_fail "vendor quoted dockerfile path" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-quoted-file.md"
expect_fail "vendor dockerfile no slash" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-dockerfile-no-slash.md"
expect_fail "vendor runtime dependencies" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-runtime-dependencies.md"
expect_fail "vendor runtime dependencies vendor-first" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-runtime-dependencies-vendor-first.md"
expect_fail "vendor runtime from" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-runtime-from.md"
expect_fail "vendor runtime loaded from tree" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-runtime-loaded-from-tree.md"
expect_fail "vendor as package source" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-as-package-source.md"
expect_fail "vendor docker run volume" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-docker-run-volume.md"
expect_fail "vendor podman run mount" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-podman-run-mount.md"
expect_fail "vendor make -C usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-c.md"
expect_fail "vendor make --directory usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-directory.md"
expect_fail "vendor make --directory= usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-directory-equals.md"
expect_fail "vendor make variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-variable.mk"
expect_fail "vendor make shell assignment variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-assignment-variable.mk"
expect_fail "vendor make shell assignment sh -c variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-assignment-sh-c-variable.mk"
expect_fail "vendor make shell assignment sh -c printf variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-assignment-sh-c-printf-variable.mk"
expect_fail "vendor make shell assignment sh -c quoted printf variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-assignment-sh-c-printf-quoted-variable.mk"
expect_fail "vendor make shell function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-function-build-context.mk"
expect_fail "vendor make shell echo function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-echo-function-build-context.mk"
expect_fail "vendor make shell echo relative function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-echo-relative-function-build-context.mk"
expect_fail "vendor make shell sh -c echo relative function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-sh-c-echo-relative-function-build-context.mk"
expect_fail "vendor make shell bash -lc echo relative function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-bash-lc-echo-relative-function-build-context.mk"
expect_fail "vendor make shell sh -ec echo relative function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-sh-ec-echo-relative-function-build-context.mk"
expect_fail "vendor make shell bash -l -c echo relative function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-bash-l-c-echo-relative-function-build-context.mk"
expect_fail "vendor make shell sh -e -c echo relative function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-sh-e-c-echo-relative-function-build-context.mk"
expect_fail "vendor make shell printf format function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-printf-format-function-build-context.mk"
expect_fail "vendor make shell printf quoted format function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-printf-quoted-format-function-build-context.mk"
expect_fail "vendor make shell sh -c printf function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-sh-c-printf-function-build-context.mk"
expect_fail "vendor make shell sh -c printf relative function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-sh-c-printf-relative-function-build-context.mk"
expect_fail "vendor make shell sh -c quoted printf function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-sh-c-printf-quoted-format-function-build-context.mk"
expect_fail "vendor make shell pwd vendor build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-pwd-vendor-build-context.mk"
expect_fail "vendor make shell pwd dot vendor build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-shell-pwd-dot-vendor-build-context.mk"
expect_fail "vendor make abspath function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-abspath-function-build-context.mk"
expect_fail "vendor make abspath relative function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-abspath-relative-function-build-context.mk"
expect_fail "vendor make realpath parent function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-realpath-parent-function-build-context.mk"
expect_fail "vendor make direct abspath relative build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-direct-abspath-relative-build-context.mk"
expect_fail "vendor make abspath CURDIR dot function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-abspath-curdir-dot-function-build-context.mk"
expect_fail "vendor make CURDIR variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-curdir-variable-build-context.mk"
expect_fail "vendor make CURDIR dot variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-curdir-dot-variable-build-context.mk"
expect_fail "vendor make ::= variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-colon-colon-equals-variable.mk"
expect_fail "vendor make :::= variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-colon-colon-colon-equals-variable.mk"
expect_fail "vendor make variable comment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-variable-comment.mk"
expect_fail "vendor make export variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-export-variable.mk"
expect_fail "vendor make override variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-override-variable.mk"
expect_fail "vendor make target-specific variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-target-specific-variable.mk"
expect_fail "vendor make private variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-private-variable.mk"
expect_fail "vendor make target private variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-target-private-variable.mk"
expect_fail "vendor make define variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-define-variable.mk"
expect_fail "vendor make define equals variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-define-equals-variable.mk"
expect_fail "vendor make define colon-equals variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-define-colon-equals-variable.mk"
expect_fail "vendor make override define variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-override-define-variable.mk"
expect_fail "vendor make export define variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-export-define-variable.mk"
expect_fail "vendor make hyphen variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-hyphen-variable.mk"
expect_fail "vendor make variable dot build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-variable-dot.mk"
expect_fail "vendor make variable subdir build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-variable-subdir.mk"
expect_fail "vendor make word function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-word-function-build-context.mk"
expect_fail "vendor make firstword function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-firstword-function-build-context.mk"
expect_fail "vendor make lastword function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-lastword-function-build-context.mk"
expect_fail "vendor make addprefix function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-addprefix-function-build-context.mk"
expect_fail "vendor make subst function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-subst-function-build-context.mk"
expect_fail "vendor make subst producing function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-subst-produce-build-context.mk"
expect_fail "vendor make patsubst wildcard build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-patsubst-wildcard-build-context.mk"
expect_fail "vendor make join build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-join-build-context.mk"
expect_fail "vendor make join variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-join-vars-build-context.mk"
expect_fail "vendor make join function variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-join-function-var-build-context.mk"
expect_fail "vendor make addsuffix function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-addsuffix-function-build-context.mk"
expect_fail "vendor make addsuffix producing function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-addsuffix-produce-build-context.mk"
expect_fail "vendor make foreach function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-foreach-function-build-context.mk"
expect_fail "vendor make foreach producing function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-foreach-produce-build-context.mk"
expect_fail "vendor make foreach suffix build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-foreach-suffix-build-context.mk"
expect_fail "vendor make foreach addsuffix build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-foreach-addsuffix-build-context.mk"
expect_fail "vendor make foreach literal build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-foreach-literal-build-context.mk"
expect_fail "vendor make foreach sort build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-foreach-sort-build-context.mk"
expect_fail "vendor make call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-call-function-build-context.mk"
expect_fail "vendor make brace call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-brace-call-function-build-context.mk"
expect_fail "vendor make target-specific call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-target-call-function-build-context.mk"
expect_fail "vendor make indirect call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-indirect-call-function-build-context.mk"
expect_fail "vendor make redefined call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-call-redefined-function-build-context.mk"
expect_fail "vendor make define override call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-define-override-call-function-build-context.mk"
expect_fail "vendor make override define call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-override-define-call-build-context.mk"
expect_fail "vendor make export define call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-export-define-call-build-context.mk"
expect_fail "vendor make nested indirect call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-nested-indirect-call-function-build-context.mk"
expect_fail "vendor make subst call function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-subst-call-function-build-context.mk"
expect_fail "vendor make call literal function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-call-literal-function-build-context.mk"
expect_fail "vendor make call literal body build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-call-literal-body-build-context.mk"
expect_fail "vendor make call prefix body build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-call-prefix-body-build-context.mk"
expect_fail "vendor make call variable function build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-call-variable-function-build-context.mk"
expect_fail "vendor make call variable literal build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-make-call-variable-literal-build-context.mk"
expect_fail "vendor cd usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-cd.md"
expect_fail "vendor tar -C usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-tar-c.md"
expect_fail "vendor tar --directory usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-tar-directory.md"
expect_fail "vendor tar source usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-tar-source.md"
validate_no_vendor_build_context "${FIXTURE_DIR}/docs/valid-extensionless-script.md"
expect_fail "extensionless script vendor usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-extensionless-script.md"
expect_fail "bash extension vendor usage" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-extension-bash.bash"
expect_fail "safe vendor prohibition cannot mask later unsafe use" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-safe-period-mask.md"
expect_fail "safe copy prohibition cannot mask comma unsafe use" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-safe-comma-mask.md"
expect_fail "vendor variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-variable-build-context.md"
expect_fail "vendor inline variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-inline-variable-build-context.md"
expect_fail "vendor shell parameter-default variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-param-default-variable-build-context.md"
expect_fail "vendor shell parameter-default direct build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-param-default-direct-build-context.md"
expect_fail "vendor shell parameter-default direct build context without colon" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-param-default-nocolon-direct-build-context.md"
expect_fail "vendor shell quoted parameter-default direct build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-param-default-quoted-direct-build-context.md"
expect_fail "vendor shell alternate-value direct build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-param-alt-direct-build-context.md"
expect_fail "vendor shell alternate-value variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-param-alt-variable-build-context.md"
expect_fail "vendor shell assigned variable error parameter build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-assigned-param-error-build-context.md"
expect_fail "vendor shell assigned variable substring build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-assigned-param-substring-build-context.md"
expect_fail "vendor shell assigned variable trim build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-assigned-param-trim-build-context.md"
expect_fail "vendor shell array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-array-build-context.md"
expect_fail "vendor shell multi array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-array-multi-build-context.md"
expect_fail "vendor shell array scalar build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-array-scalar-build-context.md"
expect_fail "vendor shell second array element build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-array-second-element-build-context.md"
expect_fail "vendor shell negative array index build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-array-negative-index-build-context.md"
expect_fail "vendor shell associative array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-associative-array-build-context.md"
expect_fail "vendor shell associative array declared then assigned build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-associative-array-declared-assigned-build-context.md"
expect_fail "vendor shell quoted associative array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-quoted-associative-array-build-context.md"
expect_fail "vendor shell quoted associative reference build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-quoted-associative-reference-build-context.md"
expect_fail "vendor shell associative whole array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-associative-whole-array-build-context.md"
expect_fail "vendor shell associative assigned whole array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-associative-assigned-whole-array-build-context.md"
expect_fail "vendor shell direct array assignment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-direct-array-assignment-build-context.md"
expect_fail "vendor shell direct named array assignment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-direct-named-array-assignment-build-context.md"
expect_fail "vendor shell negative direct array assignment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-negative-direct-array-assignment-build-context.md"
expect_fail "vendor shell negative direct array assignment with direct state build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-negative-direct-array-state-build-context.md"
expect_fail "vendor shell appended array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-appended-array-build-context.md"
expect_fail "vendor shell compound indexed array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-compound-indexed-array-build-context.md"
expect_fail "vendor shell spaced negative array slice build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-array-spaced-negative-slice-build-context.md"
expect_fail "vendor shell indirect build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-indirect-build-context.md"
expect_fail "vendor shell nameref build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-nameref-build-context.md"
expect_fail "vendor shell typeset nameref build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-typeset-nameref-build-context.md"
expect_fail "vendor shell local nameref build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-local-nameref-build-context.md"
expect_fail "vendor fish variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-variable-build-context.fish"
expect_fail "vendor fish local variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-local-variable-build-context.fish"
expect_fail "vendor fish exported variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-exported-variable-build-context.fish"
expect_fail "vendor fish long exported variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-long-exported-variable-build-context.fish"
expect_fail "vendor fish global exported variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-global-exported-variable-build-context.fish"
expect_fail "vendor fish list variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-list-variable-build-context.fish"
expect_fail "vendor fish second list variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-second-list-variable-build-context.fish"
expect_fail "vendor fish negative list variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-negative-list-variable-build-context.fish"
expect_fail "vendor fish range list variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-range-list-variable-build-context.fish"
expect_fail "vendor fish open-ended range list variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-open-ended-range-list-variable-build-context.fish"
expect_fail "vendor fish leading open-ended range list variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-leading-open-range-list-variable-build-context.fish"
expect_fail "vendor fish indexed set assignment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-indexed-set-build-context.fish"
expect_fail "vendor fish indexed set negative assignment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-indexed-set-negative-build-context.fish"
expect_fail "vendor fish indexed set range assignment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-indexed-set-range-build-context.fish"
expect_fail "vendor fish append indexed build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-append-indexed-build-context.fish"
expect_fail "vendor fish range set assignment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-fish-range-set-build-context.fish"
expect_fail "vendor zsh one-based array build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-zsh-one-based-array-build-context.zsh"
expect_fail "vendor zsh direct indexed assignment build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-zsh-direct-indexed-assignment-build-context.zsh"
expect_fail "vendor exported variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-export-variable-build-context.md"
expect_fail "vendor export multi variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-export-multi-variable-build-context.md"
expect_fail "vendor local variable build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-local-variable-build-context.md"
expect_fail "vendor shell variable pwd parent build context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-shell-variable-pwd-parent.md"
expect_fail "vendor markdown multiline json copy" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-markdown-multiline-json-copy.md"
expect_fail "vendor nested workflow uses local action" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-workflow-uses-nested.md"
expect_fail "vendor parent workflow uses local action" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-workflow-uses-parent.md"
expect_fail "vendor buildx bake set context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildx-bake-set-context.md"
expect_fail "vendor buildx bake set named context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-buildx-bake-set-named-context.md"
expect_fail "vendor deeply nested HCL local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-deep-nested-object-local-context.hcl"
expect_fail "vendor deeply nested HCL local context with other local" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-deep-nested-object-local-with-other.hcl"
expect_fail "vendor HCL bracket local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-bracket-local-context.hcl"
expect_fail "vendor HCL nested bracket local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-nested-bracket-local-context.hcl"
expect_fail "vendor HCL quoted-key bracket local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-quoted-key-bracket-local-context.hcl"
expect_fail "vendor HCL inline quoted-key bracket local context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-inline-quoted-key-bracket-local-context.hcl"
expect_fail "vendor HCL direct function context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-direct-function-context.hcl"
expect_fail "vendor HCL named context function" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-named-context-function.hcl"
expect_fail "vendor HCL local function context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-local-function-context.hcl"
expect_fail "vendor HCL object local function context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-object-local-function-context.hcl"
expect_fail "vendor HCL inline object local function context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-inline-object-local-function-context.hcl"
expect_fail "vendor HCL derived local function context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-derived-local-function-context.hcl"
expect_fail "vendor HCL list local index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-list-local-index-context.hcl"
expect_fail "vendor HCL direct list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-direct-list-index-context.hcl"
expect_fail "vendor HCL direct tolist index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-direct-tolist-index-context.hcl"
expect_fail "vendor HCL named tolist index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-named-tolist-index-context.hcl"
expect_fail "vendor HCL direct multiline list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-direct-multiline-list-index-context.hcl"
expect_fail "vendor HCL named multiline list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-named-multiline-list-index-context.hcl"
expect_fail "vendor HCL multiline list local index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-multiline-list-local-index-context.hcl"
expect_fail "vendor HCL list format index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-list-format-index-context.hcl"
expect_fail "vendor HCL object list local index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-object-list-local-index-context.hcl"
expect_fail "vendor HCL tolist index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-tolist-index-context.hcl"
expect_fail "vendor HCL quoted-key list local index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-quoted-key-list-local-index-context.hcl"
expect_fail "vendor HCL inline single list index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-inline-single-list-index-context.hcl"
expect_fail "vendor HCL list comment index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-list-comment-index-context.hcl"
expect_fail "vendor HCL list slash-comment index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-list-slash-comment-index-context.hcl"
expect_fail "vendor HCL list block-comment index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-list-block-comment-index-context.hcl"
expect_fail "vendor HCL list multiline block-comment index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-list-multiline-block-comment-index-context.hcl"
expect_fail "vendor HCL list block-comma-comment index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-list-block-comma-comment-index-context.hcl"
expect_fail "vendor HCL list immediate slash-comment index context" --contains "vendor/ is reference-only" validate_no_vendor_build_context "${FIXTURE_DIR}/docs/invalid-vendor-hcl-list-immediate-slash-comment-index-context.hcl"

should_scan_vendor_file "cloudnative-pg-timescaledb/generated/Dockerfile.pg18-trixie" || {
  diag "should_scan_vendor_file Dockerfile.pg18-trixie" "cloudnative-pg-timescaledb/generated/Dockerfile.pg18-trixie" "vendor scan enabled" "not scanned" "Scan Dockerfile variant names for vendor misuse."
  exit 1
}
should_scan_vendor_file "cloudnative-pg-timescaledb/generated/pg18.Dockerfile" || {
  diag "should_scan_vendor_file pg18.Dockerfile" "cloudnative-pg-timescaledb/generated/pg18.Dockerfile" "vendor scan enabled" "not scanned" "Scan Dockerfile suffix names for vendor misuse."
  exit 1
}
should_scan_vendor_file "cloudnative-pg-timescaledb/generated/Containerfile.pg18-trixie" || {
  diag "should_scan_vendor_file Containerfile.pg18-trixie" "cloudnative-pg-timescaledb/generated/Containerfile.pg18-trixie" "vendor scan enabled" "not scanned" "Scan Containerfile variant names for vendor misuse."
  exit 1
}
should_scan_vendor_file "cloudnative-pg-timescaledb/Makefile" || {
  diag "should_scan_vendor_file cloudnative-pg-timescaledb/Makefile" "cloudnative-pg-timescaledb/Makefile" "vendor scan enabled" "not scanned" "Scan project Makefiles for vendor misuse."
  exit 1
}
should_scan_vendor_file "cloudnative-pg-timescaledb/scripts/build.bash" || {
  diag "should_scan_vendor_file build.bash" "cloudnative-pg-timescaledb/scripts/build.bash" "vendor scan enabled" "not scanned" "Scan shell extension scripts for vendor misuse."
  exit 1
}
is_shebang_file "${FIXTURE_DIR}/docs/valid-extensionless-script.md" || {
  diag "is_shebang_file valid-extensionless-script" "${FIXTURE_DIR}/docs/valid-extensionless-script.md" "shebang detected" "not detected" "Scan extensionless executables for vendor misuse."
  exit 1
}

while IFS= read -r -d '' file; do
  case "${file}" in
    cloudnative-pg-timescaledb/*|docs/generated-files.md)
      ;;
    *)
      diag "git_product_files scope" "${file}" "Story 1.1-owned product path" "unrelated repository path" "Limit Story 1.1 product scans to this image family and docs/generated-files.md."
      exit 1
      ;;
  esac
done < <(git_product_files)

while IFS= read -r -d '' file; do
  full_path="${ROOT_DIR}/${file}"
  [[ -f "${full_path}" ]] || continue
  if should_scan_vendor_file "${file}" || is_shebang_file "${full_path}"; then
    validate_no_vendor_build_context "${full_path}"
  fi
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
