#!/usr/bin/env bash
set -Eeuo pipefail

tags_validate_file() {
  local metadata_file="$1"
  local release_date="$2"
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 - "$metadata_file" "$release_date" "$lib_dir" <<'PY'
from datetime import datetime
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[3])
from tag_policy import generated_tags

path = Path(sys.argv[1])
release_date = sys.argv[2]
command = f"validate-tags --metadata {path} --date {release_date}"

def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )

def parse_scalar(raw):
    value = raw.strip()
    if value == "":
        return ""
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(part.strip()) for part in inner.split(",")]
    if value == "true":
        return True
    if value == "false":
        return False
    if value in {"null", "~"}:
        return None
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    if re.fullmatch(r"-?(0|[1-9][0-9]*)", value):
        return int(value)
    return value

def parse_mapping_item(text, line_no):
    if ":" not in text:
        fail("parseable tag metadata YAML subset", f"line {line_no}: {text!r}", "Use simple key/value YAML for tag fixtures.")
    key, raw_value = text.split(":", 1)
    return key.strip(), parse_scalar(raw_value)

def assign_mapping(target, key, value, line_no, scope):
    if key in target:
        fail("unique YAML mapping keys", f"duplicate key {key!r} at line {line_no} in {scope}", "Remove duplicate metadata keys so tag validation is unambiguous.")
    target[key] = value

def parse_yaml_subset(text):
    data = {}
    current_top = None
    current_entry = None
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
            assign_mapping(data, key, value, line_no, "top-level tag metadata")
            current_top = key if isinstance(value, (dict, list)) else None
            current_entry = None
            continue
        if indent == 2 and current_top == "entries":
            if not text.startswith("- "):
                fail("entries list item", f"line {line_no}: {text!r}", "Use '- key: value' entries.")
            rest = text[2:].strip()
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
        fail("parseable tag metadata YAML subset", f"line {line_no}: {line!r}", "Use the versions.yaml schema indentation.")
    return data

if not re.fullmatch(r"[0-9]{8}", release_date):
    fail("UTC release date in YYYYMMDD", release_date, "Pass --date as an explicit UTC date, for example 20260609.")
try:
    datetime.strptime(release_date, "%Y%m%d")
except ValueError:
    fail("valid UTC calendar date in YYYYMMDD", release_date, "Use a real UTC calendar date.")

try:
    data = parse_yaml_subset(path.read_text(encoding="utf-8"))
except FileNotFoundError:
    fail("metadata file exists", str(path), "Create the metadata file before validating tags.")
except IsADirectoryError:
    fail("metadata file is a regular UTF-8 YAML file", str(path), "Pass a metadata YAML file path, not a directory.")
except PermissionError as exc:
    fail("metadata file is readable", repr(exc), "Fix file permissions before validating tags.")
except UnicodeDecodeError as exc:
    fail("metadata file is UTF-8 text", repr(exc), "Write tag metadata files as UTF-8 YAML text.")
except OSError as exc:
    fail("metadata file is readable", repr(exc), "Fix the metadata file path or filesystem error before validating tags.")

required_top = {"schema_version", "image", "allowed", "entries"}
optional_top = {"barman_plugin"}
if not required_top.issubset(data) or set(data) - required_top - optional_top:
    fail(f"top-level keys include {sorted(required_top)} and optional {sorted(optional_top)}", f"actual {sorted(data)}", "Use the versions.yaml metadata shape for tag validation.")
if data["schema_version"] != "1":
    fail("schema_version is string '1'", repr(data["schema_version"]), "Quote schema_version as '1'.")

allowed = data["allowed"]
expected_allowed = {
    "postgres_majors": ["17", "18", "19beta1"],
    "debian_variants": ["trixie", "bookworm"],
    "platforms": ["linux/amd64", "linux/arm64"],
}
if not isinstance(allowed, dict) or set(allowed) != set(expected_allowed):
    fail(f"allowed keys exactly {sorted(expected_allowed)}", repr(allowed), "Keep supported tag dimensions explicit.")
for key, expected in expected_allowed.items():
    if allowed[key] != expected:
        fail(f"allowed.{key} exactly {expected!r}", repr(allowed[key]), "Do not broaden tag policy outside planned PostgreSQL, Debian, or platform scope.")

entries = data["entries"]
if not isinstance(entries, list) or not entries:
    fail("entries is non-empty list", type(entries).__name__, "Define image entries before validating tags.")

required_entry = {
    "pg_major", "pg_version", "debian_variant", "cnpg_tag", "cnpg_digest",
    "timescaledb_version", "timescaledb_package_name", "timescaledb_package_version",
    "toolkit_version", "toolkit_package_name", "toolkit_package_version",
    "pgvector_source", "pgvector_package_version", "pgaudit_source",
    "pgaudit_package_version", "platforms", "publish", "experimental",
    "latest_eligible", "skip_reason",
}
optional_entry = {"tags"}
string_fields = required_entry - {"platforms", "publish", "experimental", "latest_eligible"}
bool_fields = {"publish", "experimental", "latest_eligible"}
latest_rows = []
tag_owners = {}

for idx, entry in enumerate(entries):
    if not isinstance(entry, dict):
        fail(f"entries[{idx}] is mapping", type(entry).__name__, "Use mapping entries.")
    extra = set(entry) - required_entry - optional_entry
    missing = required_entry - set(entry)
    if missing or extra:
        fail(f"entries[{idx}] has required metadata keys plus optional tags", f"missing {sorted(missing)}, extra {sorted(extra)}", "Fix entry keys before tag validation.")
    for field in string_fields:
        if not isinstance(entry[field], str):
            fail(f"entries[{idx}].{field} is string", type(entry[field]).__name__, f"Quote {field} if needed.")
    for field in bool_fields:
        if not isinstance(entry[field], bool):
            fail(f"entries[{idx}].{field} is boolean", type(entry[field]).__name__, f"Use true or false for {field}.")
    if "tags" in entry and (not isinstance(entry["tags"], list) or any(not isinstance(tag, str) for tag in entry["tags"])):
        fail(f"entries[{idx}].tags is string list", repr(entry.get("tags")), "Use an inline YAML string list for expected tags.")
    if "tags" in entry and entry["publish"] is not True:
        fail(f"entries[{idx}].tags only present on publishable rows", repr(entry["tags"]), "Remove tags from skipped rows until publish: true.")
    if entry["pg_major"] not in expected_allowed["postgres_majors"]:
        fail("pg_major is one of 17, 18, 19beta1", repr(entry["pg_major"]), "Use only supported PostgreSQL lines; plain 19 is unsupported.")
    if entry["debian_variant"] not in expected_allowed["debian_variants"]:
        fail("debian_variant is trixie or bookworm", repr(entry["debian_variant"]), "Use only trixie or bookworm; Alpine and bullseye are unsupported.")
    if entry["pg_major"] in {"17", "18"} and not re.fullmatch(rf"{entry['pg_major']}(\.[0-9]+)?", entry["pg_version"]):
        fail(f"entries[{idx}].pg_version matches pg_major {entry['pg_major']}", repr(entry["pg_version"]), "Use a PostgreSQL version that belongs to the declared pg_major.")
    if entry["pg_major"] == "19beta1" and (entry["pg_version"] != "19beta1" or entry["experimental"] is not True):
        fail("19beta1 entries use pg_version 19beta1 and experimental true", f"pg_version={entry['pg_version']!r}, experimental={entry['experimental']}", "Keep PostgreSQL 19 preview tags experimental.")
    expected_cnpg_tag = f"{entry['pg_version']}-standard-{entry['debian_variant']}"
    if entry["cnpg_tag"] != expected_cnpg_tag:
        fail(f"entries[{idx}].cnpg_tag matches pg_version and debian_variant", repr(entry["cnpg_tag"]), f"Set cnpg_tag to {expected_cnpg_tag} so tags cannot point at a different CNPG base image line.")
    if entry["pg_major"] != "19beta1" and entry["experimental"] is not False:
        fail("stable PostgreSQL entries are not experimental", f"{entry['pg_major']} experimental={entry['experimental']}", "Set experimental: false for 17 and 18.")
    if entry["latest_eligible"]:
        latest_rows.append((entry["pg_major"], entry["debian_variant"]))
        if entry["pg_major"] != "18" or entry["debian_variant"] != "trixie" or entry["experimental"]:
            fail("latest only for non-experimental 18 trixie", f"row={(entry['pg_major'], entry['debian_variant'])}, experimental={entry['experimental']}", "Move latest_eligible to PostgreSQL 18 trixie only.")
    if entry["pg_major"] == "18" and entry["debian_variant"] == "trixie" and entry["experimental"] is False and entry["latest_eligible"] is not True:
        fail("PostgreSQL 18 trixie has latest_eligible true", repr(entry["latest_eligible"]), "Set latest_eligible: true so latest is emitted exactly for the current primary line.")
    if entry["publish"] or "tags" in entry:
        required_for_tags = ["pg_major", "pg_version", "debian_variant", "timescaledb_version"]
        empty = sorted(field for field in required_for_tags if entry[field].strip() == "")
        if empty:
            fail("taggable entries have required tag inputs", f"empty {empty}", "Populate PostgreSQL, Debian, and TimescaleDB values before generating tags.")
        if entry["publish"] and "tags" not in entry:
            fail(f"entries[{idx}].tags is present for publishable rows", "missing", "Materialize deterministic policy tags before an image row becomes publishable.")
        try:
            actual = generated_tags(entry, release_date)
        except ValueError as exc:
            fail("generated Docker tags use valid tag grammar", str(exc), "Use only Docker tag-safe PostgreSQL, Debian, TimescaleDB, and date values.")
        for tag in actual:
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", tag):
                fail("generated Docker tags use valid tag grammar", repr(tag), "Use only Docker tag-safe PostgreSQL, Debian, TimescaleDB, and date values.")
            owner = tag_owners.setdefault(tag, f"entries[{idx}] {entry['pg_major']}/{entry['debian_variant']}")
            if owner != f"entries[{idx}] {entry['pg_major']}/{entry['debian_variant']}":
                fail("each generated tag has exactly one image row owner", f"{tag!r} owned by {owner} and entries[{idx}] {entry['pg_major']}/{entry['debian_variant']}", "Do not assign rolling, immutable, or latest tags to multiple metadata rows.")
        if "tags" in entry and entry["tags"] != actual:
            fail(f"entries[{idx}].tags exactly generated policy tags", repr(entry["tags"]), f"Use deterministic tags {actual!r} for this PG/Debian/date combination.")

if latest_rows != [("18", "trixie")]:
    fail("latest emitted exactly for PostgreSQL 18 trixie", repr(latest_rows), "Only the current primary PostgreSQL line may receive latest.")
PY
}
