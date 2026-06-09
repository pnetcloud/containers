#!/usr/bin/env bash
set -Eeuo pipefail

metadata_validate_file() {
  local metadata_file="$1"
  python3 - "$metadata_file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
command = f"validate-metadata {path}"

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
        fail("parseable metadata YAML subset", f"line {line_no}: {text!r}", "Use simple key/value YAML for metadata fixtures.")
    key, raw_value = text.split(":", 1)
    return key.strip(), parse_scalar(raw_value)

def assign_mapping(target, key, value, line_no, scope):
    if key in target:
        fail("unique YAML mapping keys", f"duplicate key {key!r} at line {line_no} in {scope}", "Remove duplicate metadata keys so versions.yaml is unambiguous.")
    target[key] = value

def parse_versions_yaml(text):
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
            assign_mapping(data, key, value, line_no, "top-level metadata")
            current_top = key if isinstance(value, (dict, list)) else None
            current_entry = None
            continue
        if indent == 2 and current_top == "entries":
            if not text.startswith("- "):
                fail("entries list item", f"line {line_no}: {text!r}", "Use '- key: value' entries.")
            rest = text[2:].strip()
            if ":" not in rest:
                fail("entries[] mapping item", f"line {line_no}: {text!r}", "Use '- pg_major: value' entry mappings.")
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
        fail("parseable metadata YAML subset", f"line {line_no}: {line!r}", "Use the versions.yaml schema indentation.")
    return data

try:
    data = parse_versions_yaml(path.read_text())
except FileNotFoundError:
    fail("metadata file exists", str(path), "Create the metadata file before validating.")

required_top = {"schema_version", "image", "allowed", "entries"}
optional_top = {"barman_plugin"}
if not required_top.issubset(data) or set(data) - required_top - optional_top:
    missing = sorted(required_top - set(data))
    extra = sorted(set(data) - required_top - optional_top)
    fail(f"top-level keys exactly {sorted(required_top)} plus optional {sorted(optional_top)}", f"missing {missing}, extra {extra}", "Use the documented versions.yaml metadata schema.")
if data["schema_version"] != "1":
    fail("schema_version is string '1'", repr(data["schema_version"]), "Quote schema_version as '1'.")

image = data["image"]
if not isinstance(image, dict):
    fail("image is mapping", type(image).__name__, "Use image.registry, image.repository, image.current_major, and image.primary_debian_variant.")
required_image = {"registry", "repository", "current_major", "primary_debian_variant"}
if set(image) != required_image:
    fail(f"image keys exactly {sorted(required_image)}", f"missing {sorted(required_image - set(image))}, extra {sorted(set(image) - required_image)}", "Fix image metadata keys.")
if image["current_major"] != "18":
    fail("image.current_major is string '18'", repr(image["current_major"]), "Set current_major to '18'.")
if image["primary_debian_variant"] != "trixie":
    fail("image.primary_debian_variant is trixie", repr(image["primary_debian_variant"]), "Set primary_debian_variant to trixie.")

allowed = data["allowed"]
if not isinstance(allowed, dict):
    fail("allowed is mapping", type(allowed).__name__, "Use allowed.postgres_majors, allowed.debian_variants, and allowed.platforms.")
expected_allowed = {
    "postgres_majors": ["17", "18", "19beta1"],
    "debian_variants": ["trixie", "bookworm"],
    "platforms": ["linux/amd64", "linux/arm64"],
}
if set(allowed) != set(expected_allowed):
    fail(f"allowed keys exactly {sorted(expected_allowed)}", f"missing {sorted(set(expected_allowed) - set(allowed))}, extra {sorted(set(allowed) - set(expected_allowed))}", "Fix allowed metadata keys.")
for key, expected in expected_allowed.items():
    if allowed[key] != expected:
        fail(f"allowed.{key} exactly {expected!r}", repr(allowed[key]), "Do not broaden supported PostgreSQL, Debian, or platform scope.")

if "barman_plugin" in data:
    barman_plugin = data["barman_plugin"]
    required_barman = {"release", "manifest_url", "plugin_image", "sidecar_image", "source_url", "updated_at_utc"}
    if not isinstance(barman_plugin, dict) or set(barman_plugin) != required_barman:
        fail(f"barman_plugin keys exactly {sorted(required_barman)}", repr(barman_plugin), "Store the CloudNativePG Barman Cloud Plugin reference contract.")
    for field in required_barman:
        if not isinstance(barman_plugin[field], str) or not barman_plugin[field].strip():
            fail(f"barman_plugin.{field} is non-empty string", repr(barman_plugin.get(field)), "Populate the tracked Barman plugin reference fields.")
    release = barman_plugin["release"]
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", release):
        fail("barman_plugin.release is stable vX.Y.Z", repr(release), "Track only stable CloudNativePG Barman Cloud Plugin releases.")
    expected_manifest = f"https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/{release}/manifest.yaml"
    expected_plugin = f"ghcr.io/cloudnative-pg/plugin-barman-cloud:{release}"
    expected_sidecar = f"ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:{release}"
    if barman_plugin["manifest_url"] != expected_manifest or barman_plugin["plugin_image"] != expected_plugin or barman_plugin["sidecar_image"] != expected_sidecar:
        fail("barman_plugin URLs/images match release", repr(barman_plugin), "Derive manifest and image references from barman_plugin.release.")

entries = data["entries"]
if not isinstance(entries, list) or not entries:
    fail("entries is non-empty list", type(entries).__name__, "Define supported image entries.")

required_entry = {
    "pg_major", "pg_version", "debian_variant", "cnpg_tag", "cnpg_digest",
    "timescaledb_version", "timescaledb_package_name", "timescaledb_package_version",
    "toolkit_version", "toolkit_package_name", "toolkit_package_version",
    "pgvector_source", "pgvector_package_version", "pgaudit_source",
    "pgaudit_package_version", "platforms", "publish", "experimental",
    "latest_eligible", "skip_reason",
}
string_fields = required_entry - {"platforms", "publish", "experimental", "latest_eligible"}
bool_fields = {"publish", "experimental", "latest_eligible"}
resolver_owned = {"cnpg_digest", "timescaledb_version", "timescaledb_package_name", "timescaledb_package_version", "toolkit_version", "toolkit_package_name", "toolkit_package_version"}
extension_sources = {"base", "package"}
expected_rows = {("17", "trixie"), ("18", "trixie"), ("19beta1", "trixie"), ("17", "bookworm"), ("18", "bookworm"), ("19beta1", "bookworm")}
seen = set()
latest_rows = []

for idx, entry in enumerate(entries):
    if not isinstance(entry, dict):
        fail(f"entries[{idx}] is mapping", type(entry).__name__, "Use mapping entries.")
    if set(entry) != required_entry:
        fail(f"entries[{idx}] keys exactly {sorted(required_entry)}", f"missing {sorted(required_entry - set(entry))}, extra {sorted(set(entry) - required_entry)}", "Fix entry metadata keys.")
    for field in string_fields:
        if not isinstance(entry[field], str):
            fail(f"entries[{idx}].{field} is string", type(entry[field]).__name__, f"Quote {field} if needed.")
    for field in bool_fields:
        if not isinstance(entry[field], bool):
            fail(f"entries[{idx}].{field} is boolean", type(entry[field]).__name__, f"Use true or false for {field}.")
    platforms = entry["platforms"]
    if not isinstance(platforms, list) or not platforms:
        fail(f"entries[{idx}].platforms is non-empty list", type(platforms).__name__, "Set explicit platform list.")
    if any(not isinstance(platform, str) for platform in platforms):
        fail(f"entries[{idx}].platforms contains strings", repr(platforms), "Use platform strings.")
    bad_platforms = sorted(set(platforms) - set(expected_allowed["platforms"]))
    if bad_platforms:
        fail(f"entries[{idx}].platforms only {expected_allowed['platforms']}", repr(bad_platforms), "Use only linux/amd64 and linux/arm64.")
    if entry["publish"] and (set(platforms) != set(expected_allowed["platforms"]) or len(platforms) != len(expected_allowed["platforms"])):
        fail(f"publishable entries[{idx}].platforms exactly {expected_allowed['platforms']}", repr(platforms), "Publishable entries must support both required platforms.")
    row = (entry["pg_major"], entry["debian_variant"])
    if row in seen:
        fail("unique pg_major/debian_variant rows", repr(row), "Remove duplicate image row.")
    seen.add(row)
    if entry["pg_major"] not in expected_allowed["postgres_majors"]:
        fail("pg_major is one of 17, 18, 19beta1", repr(entry["pg_major"]), "Use only supported PostgreSQL lines; plain 19 is unsupported.")
    if entry["debian_variant"] not in expected_allowed["debian_variants"]:
        fail("debian_variant is trixie or bookworm", repr(entry["debian_variant"]), "Use only trixie or bookworm.")
    pg_version = entry["pg_version"]
    if entry["pg_major"] in {"17", "18"} and not re.fullmatch(rf"{entry['pg_major']}(\.[0-9]+)?", pg_version):
        fail(f"entries[{idx}].pg_version matches pg_major {entry['pg_major']}", repr(pg_version), "Use a PostgreSQL version that belongs to the declared pg_major.")
    if entry["pg_major"] == "19beta1" and pg_version != "19beta1":
        fail("entries[].pg_version for 19beta1 is 19beta1", repr(pg_version), "Use pg_version: 19beta1 for the experimental PostgreSQL 19 preview row.")
    expected_cnpg_tag = f"{pg_version}-standard-{entry['debian_variant']}"
    if entry["cnpg_tag"] != expected_cnpg_tag:
        fail(f"entries[{idx}].cnpg_tag matches pg_version and debian_variant", repr(entry["cnpg_tag"]), f"Set cnpg_tag to {expected_cnpg_tag} so unsupported base variants cannot be hidden in tags.")
    for extension in ["pgvector", "pgaudit"]:
        source_field = f"{extension}_source"
        version_field = f"{extension}_package_version"
        source = entry[source_field]
        version = entry[version_field]
        if source not in extension_sources:
            fail(f"entries[{idx}].{source_field} is base or package", repr(source), "Set explicit extension source metadata to base or package.")
        if source == "package" and not version.strip():
            fail(f"entries[{idx}].{version_field} is non-empty when {source_field}=package", repr(version), "Package-sourced pgvector/PGAudit entries require exact package version metadata.")
        if source == "base" and version.strip():
            fail(f"entries[{idx}].{version_field} is empty when {source_field}=base", repr(version), "Base-sourced pgvector/PGAudit entries are verified from the CNPG base image, not package-installed.")
    if entry["pg_major"] == "19beta1" and entry["experimental"] is not True:
        fail("19beta1 entries are experimental", repr(entry["experimental"]), "Set experimental: true for 19beta1.")
    if entry["pg_major"] != "19beta1" and entry["experimental"] is not False:
        fail("stable PostgreSQL entries are not experimental", f"{entry['pg_major']} experimental={entry['experimental']}", "Set experimental: false for 17 and 18.")
    if entry["latest_eligible"]:
        latest_rows.append(row)
        if row != ("18", "trixie") or entry["experimental"]:
            fail("latest_eligible only for non-experimental 18-trixie", f"row={row}, experimental={entry['experimental']}", "Only 18-trixie may be latest eligible.")
    if row == ("18", "trixie") and entry["latest_eligible"] is not True:
        fail("18-trixie has latest_eligible true", repr(entry["latest_eligible"]), "Set latest_eligible: true on the current latest policy row.")
    if entry["publish"]:
        publish_required = resolver_owned | {"pg_version", "cnpg_tag"}
        empty = sorted(field for field in publish_required if entry[field].strip() == "")
        if empty:
            fail("publishable entries have resolver-owned values", f"empty {empty}", "Populate resolver-owned values before setting publish: true.")
        if entry["skip_reason"].strip():
            fail("publishable entries do not have skip_reason", repr(entry["skip_reason"]), "Clear skip_reason for publishable entries.")
    else:
        if not entry["skip_reason"].strip():
            fail("non-published entries have non-empty skip_reason", repr(entry["skip_reason"]), "Explain why the row is not publishable.")

if seen != expected_rows:
    fail(f"matrix rows exactly {sorted(expected_rows)}", f"actual {sorted(seen)}", "Keep the required PG/Debian matrix complete and exact.")
if latest_rows != [("18", "trixie")]:
    fail("exactly one latest_eligible row: 18-trixie", repr(latest_rows), "Set latest_eligible true only on 18-trixie.")
PY
}
