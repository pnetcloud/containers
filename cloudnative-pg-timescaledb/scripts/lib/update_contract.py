#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

from tag_policy import generated_tags


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_METADATA = ROOT / "cloudnative-pg-timescaledb" / "versions.yaml"
RESOLVE_SCRIPT = ROOT / "cloudnative-pg-timescaledb" / "scripts" / "resolve-versions.sh"
GENERATE_SCRIPT = ROOT / "cloudnative-pg-timescaledb" / "scripts" / "generate.sh"
BARMAN_PLUGIN_SCRIPT = ROOT / "cloudnative-pg-timescaledb" / "scripts" / "lib" / "barman-plugin.sh"
SUMMARY_PATH = Path("/tmp") / "cloudnative-pg-timescaledb-update-summary.json"
DEFAULT_TAG_DATE = "20260609"
RESOLVER_FIELDS = [
    "pg_version",
    "cnpg_tag",
    "cnpg_digest",
    "timescaledb_version",
    "timescaledb_package_name",
    "timescaledb_package_version",
    "toolkit_version",
    "toolkit_package_name",
    "toolkit_package_version",
]
POLICY_FIELDS = ["publish", "experimental", "latest_eligible"]
BARMAN_FIELDS = ["release", "manifest_url", "plugin_image", "sidecar_image", "source_url", "updated_at_utc"]
EXPECTED_ROWS = {("17", "trixie"), ("18", "trixie"), ("19beta1", "trixie"), ("17", "bookworm"), ("18", "bookworm"), ("19beta1", "bookworm")}
ALLOWED_PLATFORMS = {"linux/amd64", "linux/arm64"}
BARMAN_FORBIDDEN = re.compile(r"\b((?<!plugin-)barman-cloud|barman\s+package|apt-get\s+install[^\n]*barman|postgresql:.*barman)\b", re.IGNORECASE)


class UpdateError(Exception):
    pass


def diag(command, artifact, expected, actual, remediation):
    raise UpdateError(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
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


def parse_mapping_item(text, line_no, command, path):
    if ":" not in text:
        diag(command, path, "parseable metadata YAML subset", f"line {line_no}: {text!r}", "Use simple key/value YAML for update metadata.")
    key, raw_value = text.split(":", 1)
    return key.strip(), parse_scalar(raw_value)


def assign_mapping(target, key, value, line_no, scope, command, path):
    if key in target:
        diag(command, path, "unique YAML mapping keys", f"duplicate key {key!r} at line {line_no} in {scope}", "Remove duplicate metadata keys.")
    target[key] = value


def parse_metadata(path, command):
    data = {}
    current_top = None
    current_entry = None
    try:
        text = path.read_text()
    except FileNotFoundError:
        diag(command, path, "metadata file exists", str(path), "Create versions.yaml before update.")
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.rstrip()
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        item = line.lstrip(" ")
        if indent == 0:
            key, value = parse_mapping_item(item, line_no, command, path)
            if item.endswith(":"):
                value = [] if key == "entries" else {}
            assign_mapping(data, key, value, line_no, "top-level metadata", command, path)
            current_top = key if isinstance(value, (dict, list)) else None
            current_entry = None
            continue
        if indent == 2 and current_top == "entries":
            if not item.startswith("- "):
                diag(command, path, "entries list item", f"line {line_no}: {item!r}", "Use '- key: value' entry mappings.")
            current_entry = {}
            data["entries"].append(current_entry)
            key, value = parse_mapping_item(item[2:].strip(), line_no, command, path)
            assign_mapping(current_entry, key, value, line_no, "entries[] item", command, path)
            continue
        if indent == 2 and isinstance(data.get(current_top), dict):
            key, value = parse_mapping_item(item, line_no, command, path)
            assign_mapping(data[current_top], key, value, line_no, current_top, command, path)
            continue
        if indent == 4 and current_top == "entries" and isinstance(current_entry, dict):
            key, value = parse_mapping_item(item, line_no, command, path)
            assign_mapping(current_entry, key, value, line_no, "entries[] item", command, path)
            continue
        diag(command, path, "parseable metadata YAML subset", f"line {line_no}: {line!r}", "Use the versions.yaml schema indentation.")
    return data


def quote_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return "[" + ", ".join(json.dumps(item) for item in value) + "]"
    if isinstance(value, str):
        if value == "" or value in {"1", "17", "18", "19beta1"} or any(ch in value for ch in [":", "~", " ", "-", ".", "/"]):
            return json.dumps(value)
        return value
    return json.dumps(value)


def render_metadata(data):
    lines = [
        f"schema_version: {quote_value(data['schema_version'])}",
        "image:",
        f"  registry: {quote_value(data['image']['registry'])}",
        f"  repository: {quote_value(data['image']['repository'])}",
        f"  current_major: {quote_value(data['image']['current_major'])}",
        f"  primary_debian_variant: {quote_value(data['image']['primary_debian_variant'])}",
        "allowed:",
        f"  postgres_majors: {quote_value(data['allowed']['postgres_majors'])}",
        f"  debian_variants: {quote_value(data['allowed']['debian_variants'])}",
        f"  platforms: {quote_value(data['allowed']['platforms'])}",
    ]
    if "barman_plugin" in data:
        lines.append("barman_plugin:")
        for field in BARMAN_FIELDS:
            lines.append(f"  {field}: {quote_value(data['barman_plugin'][field])}")
    lines.append("entries:")
    field_order = [
        "pg_major", "pg_version", "debian_variant", "cnpg_tag", "cnpg_digest",
        "timescaledb_version", "timescaledb_package_name", "timescaledb_package_version",
        "toolkit_version", "toolkit_package_name", "toolkit_package_version",
        "pgvector_source", "pgvector_package_version", "pgaudit_source",
        "pgaudit_package_version", "platforms", "publish", "experimental",
        "latest_eligible", "skip_reason",
    ]
    for entry in data["entries"]:
        lines.append(f"  - pg_major: {quote_value(entry['pg_major'])}")
        for field in field_order[1:]:
            lines.append(f"    {field}: {quote_value(entry[field])}")
        if "tags" in entry:
            lines.append(f"    tags: {quote_value(entry['tags'])}")
    return "\n".join(lines) + "\n"


def materialize_tags(data, release_date):
    for entry in data["entries"]:
        if entry["publish"]:
            entry["tags"] = generated_tags(entry, release_date)
        else:
            entry.pop("tags", None)


def validate_invariants(data, command, artifact):
    rows = {(entry["pg_major"], entry["debian_variant"]) for entry in data["entries"]}
    if len(data["entries"]) != len(EXPECTED_ROWS):
        diag(command, artifact, f"exactly {len(EXPECTED_ROWS)} matrix entries", len(data["entries"]), "Do not duplicate supported PostgreSQL/Debian rows during update.")
    if rows != EXPECTED_ROWS:
        diag(command, artifact, f"matrix rows exactly {sorted(EXPECTED_ROWS)}", sorted(rows), "Do not add unsupported PostgreSQL or Debian rows during update.")
    latest = [(entry["pg_major"], entry["debian_variant"]) for entry in data["entries"] if entry["latest_eligible"]]
    if latest != [("18", "trixie")]:
        diag(command, artifact, "latest_eligible only on 18/trixie", latest, "Keep latest pinned to PostgreSQL 18 trixie.")
    for entry in data["entries"]:
        if entry["pg_major"] == "19beta1" and entry["experimental"] is not True:
            diag(command, artifact, "19beta1 remains experimental", entry, "Do not promote PostgreSQL 19 preview in update.")
        if set(entry["platforms"]) - ALLOWED_PLATFORMS:
            diag(command, artifact, "platforms only linux/amd64 and linux/arm64", entry["platforms"], "Do not add unsupported platforms during update.")
        if entry["publish"] and str(entry["skip_reason"]).strip():
            diag(command, artifact, "publishable entries have empty skip_reason", f"{entry['pg_major']}/{entry['debian_variant']} skip_reason={entry['skip_reason']!r}", "Clear skip_reason before setting publish true, or keep publish false.")
        if str(entry.get("skip_reason", "")).startswith("resolver:"):
            if not re.match(r"^resolver:[a-z0-9-]+:", entry["skip_reason"]):
                diag(command, artifact, "resolver skip_reason prefix resolver:<code>:", entry["skip_reason"], "Use stable lowercase kebab-case resolver reason codes.")
    text = render_metadata(data)
    if BARMAN_FORBIDDEN.search(text):
        diag(command, artifact, "no legacy Barman tooling in image metadata", "barman-cloud or Barman package reference", "Use only CloudNativePG Barman Cloud Plugin references in later docs stories.")
    if "barman_plugin" in data:
        plugin = data["barman_plugin"]
        missing = [field for field in BARMAN_FIELDS if field not in plugin or not isinstance(plugin[field], str) or not plugin[field].strip()]
        if missing:
            diag(command, artifact, f"barman_plugin fields {BARMAN_FIELDS}", f"missing/empty {missing}", "Populate the CloudNativePG Barman Cloud Plugin reference fields.")
        release = plugin["release"]
        if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", release):
            diag(command, artifact, "barman_plugin.release stable vX.Y.Z", release, "Track only stable CloudNativePG Barman Cloud Plugin releases.")
        expected = {
            "manifest_url": f"https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/{release}/manifest.yaml",
            "plugin_image": f"ghcr.io/cloudnative-pg/plugin-barman-cloud:{release}",
            "sidecar_image": f"ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:{release}",
        }
        drift = {field: {"expected": value, "actual": plugin[field]} for field, value in expected.items() if plugin[field] != value}
        if drift:
            diag(command, artifact, "barman_plugin references derive from release", drift, "Update Barman plugin manifest and image references together.")


def run_json(args, command, artifact, env=None):
    proc = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if proc.returncode != 0:
        diag(command, artifact, "resolver command succeeds", proc.stderr.strip() or proc.stdout.strip(), "Fix upstream fixtures or metadata before update.")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        diag(command, artifact, "resolver JSON output", f"{exc}: {proc.stdout[:200]}", "Resolver --json must emit compact JSON on stdout only.")


def result_map(payload):
    return {(entry["pg_major"], entry["debian_variant"]): entry for entry in payload["entries"]}


def update_entries(data, cnpg, packages):
    updated = []
    cnpg_by_row = result_map(cnpg)
    pkg_by_row = result_map(packages)
    for entry in data["entries"]:
        row = (entry["pg_major"], entry["debian_variant"])
        old = {field: entry[field] for field in RESOLVER_FIELDS + ["skip_reason"]}
        cnpg_row = cnpg_by_row[row]
        pkg_row = pkg_by_row[row]
        pg_version = cnpg_row["pg_version"]
        cnpg_tag = cnpg_row["cnpg_tag"]
        if cnpg_row["cnpg_digest"] and pg_version == entry["pg_major"] and entry["pg_major"] in {"17", "18"}:
            match = re.search(rf"-{entry['pg_major']}(?P<minor>[0-9]{{2}})(?:$|[^0-9])", pkg_row["timescaledb_package_version"])
            if match:
                pg_version = f"{entry['pg_major']}.{int(match.group('minor'))}"
                cnpg_tag = f"{pg_version}-standard-{entry['debian_variant']}"
        entry["pg_version"] = pg_version
        entry["cnpg_tag"] = cnpg_tag
        entry["cnpg_digest"] = cnpg_row["cnpg_digest"]
        entry["timescaledb_version"] = pkg_row["timescaledb_version"]
        entry["timescaledb_package_name"] = pkg_row["timescaledb_package_name"]
        entry["timescaledb_package_version"] = pkg_row["timescaledb_package_version"]
        entry["toolkit_version"] = pkg_row["toolkit_version"]
        entry["toolkit_package_name"] = pkg_row["toolkit_package_name"]
        entry["toolkit_package_version"] = pkg_row["toolkit_package_version"]
        missing = []
        if not entry["cnpg_digest"]:
            missing.append("cnpg")
        if not entry["timescaledb_package_version"]:
            missing.append("timescaledb")
        if not entry["toolkit_package_version"]:
            missing.append("toolkit")
        current_reason = entry["skip_reason"]
        if missing:
            reason = ""
            if missing == ["cnpg"]:
                reason = cnpg_row.get("skip_reason", "")
            if not reason:
                reason = pkg_row.get("skip_reason", "")
            if not reason and "cnpg" in missing:
                reason = cnpg_row.get("skip_reason", "")
            if not reason or reason == current_reason:
                reason = f"resolver:missing-{'-'.join(missing)}: {entry['pg_major']} {entry['debian_variant']} unresolved {'/'.join(missing)}"
            if current_reason == "" or current_reason.startswith("resolver:"):
                entry["skip_reason"] = reason
        elif current_reason.startswith("resolver:"):
            entry["skip_reason"] = f"resolver:available-unpublished: {entry['pg_major']} {entry['debian_variant']} resolved but publish policy remains false"
        new = {field: entry[field] for field in RESOLVER_FIELDS + ["skip_reason"]}
        changed_fields = {field: {"old": old[field], "new": new[field]} for field in new if old[field] != new[field]}
        if changed_fields:
            updated.append({"pg_major": row[0], "debian_variant": row[1], "fields": changed_fields})
    return updated


def update_barman_plugin(data, reference):
    old = {field: data.get("barman_plugin", {}).get(field, "") for field in BARMAN_FIELDS}
    updated_at_utc = reference["checked_at_utc"]
    if old["release"] == reference["release"] and old["updated_at_utc"]:
        updated_at_utc = old["updated_at_utc"]
    data["barman_plugin"] = {
        "release": reference["release"],
        "manifest_url": reference["manifest_url"],
        "plugin_image": reference["plugin_image"],
        "sidecar_image": reference["sidecar_image"],
        "source_url": reference["source_url"],
        "updated_at_utc": updated_at_utc,
    }
    new = {field: data["barman_plugin"][field] for field in BARMAN_FIELDS}
    changed_fields = {field: {"old": old[field], "new": new[field]} for field in BARMAN_FIELDS if old[field] != new[field]}
    return {
        "old_reference": old["release"],
        "new_reference": new["release"],
        "changed": bool(changed_fields),
        "noop": not bool(changed_fields),
        "changed_fields": changed_fields,
        "manifest_url": new["manifest_url"],
        "plugin_image": new["plugin_image"],
        "sidecar_image": new["sidecar_image"],
        "backup_tooling_free": True,
    }


def scan_barman_outputs(paths, command):
    for path in paths:
        target = ROOT / path
        if target.is_dir():
            for child in target.rglob("*"):
                if child.is_file() and BARMAN_FORBIDDEN.search(child.read_text(errors="ignore")):
                    diag(command, child, "no legacy Barman tooling in generated outputs", "barman-cloud or Barman package reference", "Keep Barman support limited to the CloudNativePG Barman Cloud Plugin story.")
        elif target.is_file() and BARMAN_FORBIDDEN.search(target.read_text(errors="ignore")):
            diag(command, target, "no legacy Barman tooling in generated outputs", "barman-cloud or Barman package reference", "Keep Barman support limited to the CloudNativePG Barman Cloud Plugin story.")


def capture_paths(paths):
    snapshots = {}
    for path in paths:
        target = ROOT / path if not Path(path).is_absolute() else Path(path)
        if target.is_dir():
            snapshots[target] = ("dir", {child.relative_to(target): child.read_bytes() for child in target.rglob("*") if child.is_file()})
        elif target.is_file():
            snapshots[target] = ("file", target.read_bytes())
        else:
            snapshots[target] = ("missing", None)
    return snapshots


def paths_changed(snapshots):
    return snapshots != capture_paths(snapshots.keys())


def restore_paths(snapshots):
    for target, (kind, payload) in snapshots.items():
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists():
            target.unlink()
        if kind == "dir":
            target.mkdir(parents=True, exist_ok=True)
            for relative, content in payload.items():
                child = target / relative
                child.parent.mkdir(parents=True, exist_ok=True)
                child.write_bytes(content)
        elif kind == "file":
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)


def require_clean_owned_paths(paths, command):
    relative_paths = []
    for path in paths:
        target = ROOT / path if not Path(path).is_absolute() else Path(path)
        try:
            relative_paths.append(str(target.relative_to(ROOT)))
        except ValueError:
            relative_paths.append(str(target))
    proc = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all", "--", *relative_paths],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        return
    dirty = proc.stdout.strip()
    if dirty:
        diag(command, "git status", "clean resolver-owned metadata/generated paths before update", dirty, "Commit, stash, or remove changes under update-owned paths before running make update.")


def resolve_fixture_path(fixture_root, relative, command, artifact):
    path = fixture_root / relative
    if not path.exists():
        diag(command, artifact, f"--fixtures includes {relative}", str(path), "Provide a complete deterministic fixture root; update tests must not depend on live upstream.")
    return path


def build_parser():
    parser = argparse.ArgumentParser(description="Deterministically update resolver-owned metadata.")
    parser.add_argument("mode", choices=["update"])
    parser.add_argument("--metadata", default=str(DEFAULT_METADATA))
    parser.add_argument("--fixtures", help="Complete fixture root containing cnpg/, packages/, and barman-plugin.json inventories.")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--summary", default=str(SUMMARY_PATH))
    parser.add_argument("--tag-date", default=os.environ.get("TAG_VALIDATION_DATE") or os.environ.get("DATE") or DEFAULT_TAG_DATE, help="UTC release date used to materialize deterministic image tags.")
    parser.add_argument("--generate", action="store_true", help="Run generators after metadata update.")
    return parser


def summary_path_from_argv(argv):
    for index, value in enumerate(argv):
        if value == "--summary" and index + 1 < len(argv):
            return Path(argv[index + 1])
        if value.startswith("--summary="):
            return Path(value.split("=", 1)[1])
    return SUMMARY_PATH


def failure_summary(summary_path, message):
    summary = {
        "changed": False,
        "updated_entries": [],
        "old": "",
        "new": "",
        "generated": [],
        "summary_path": str(summary_path),
        "exit_code": 1,
        "failure_reason": message,
    }
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv)
    command = "resolve-versions update"
    metadata = Path(args.metadata)
    before_text = metadata.read_text()
    data = parse_metadata(metadata, command)
    validate_invariants(data, command, metadata)
    generated_paths = [
        "cloudnative-pg-timescaledb/generated",
        "cloudnative-pg-timescaledb/docker-bake.hcl",
        "cloudnative-pg-timescaledb/matrix.json",
        "cloudnative-pg-timescaledb/catalog",
        "cloudnative-pg-timescaledb/docs/generated",
    ]
    require_clean_owned_paths([metadata] + generated_paths, command)
    cnpg_args = [str(RESOLVE_SCRIPT), "--check-cnpg", "--metadata", str(metadata), "--json", "--allow-digest-drift", "--preserve-manual-skip"]
    pkg_args = [str(RESOLVE_SCRIPT), "--check-packages", "--metadata", str(metadata), "--json", "--preserve-manual-skip"]
    barman_env = None
    if args.fixtures:
        fixture_root = Path(args.fixtures)
        cnpg_args.extend(["--fixtures", str(resolve_fixture_path(fixture_root, "cnpg", command, metadata))])
        pkg_args.extend(["--fixtures", str(resolve_fixture_path(fixture_root, "packages", command, metadata))])
        barman_env = os.environ.copy()
        barman_env["BARMAN_PLUGIN_FIXTURE"] = str(resolve_fixture_path(fixture_root, "barman-plugin.json", command, metadata))
    cnpg = run_json(cnpg_args, command, metadata)
    packages = run_json(pkg_args, command, metadata)
    barman_reference = run_json([str(BARMAN_PLUGIN_SCRIPT), "--json"], command, metadata, env=barman_env)
    updated = update_entries(data, cnpg, packages)
    barman_plugin = update_barman_plugin(data, barman_reference)
    materialize_tags(data, args.tag_date)
    validate_invariants(data, command, metadata)
    after_text = render_metadata(data)
    metadata_changed = before_text != after_text
    generated = []
    snapshots = capture_paths([metadata] + generated_paths)
    generated_changed = False
    try:
        if metadata_changed:
            metadata.write_text(after_text)
        if args.generate:
            try:
                proc = subprocess.run([str(GENERATE_SCRIPT)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            except OSError as exc:
                diag(command, "make generate", "generators succeed", str(exc), "Fix generator entrypoint availability before update can complete.")
            if proc.returncode != 0:
                diag(command, "make generate", "generators succeed", proc.stderr.strip() or proc.stdout.strip(), "Fix generator drift before update can complete.")
            generated = generated_paths
            generated_changed = paths_changed(snapshots)
            scan_barman_outputs(generated, command)
    except UpdateError:
        restore_paths(snapshots)
        raise
    changed = metadata_changed or generated_changed
    summary = {
        "changed": changed,
        "updated_entries": updated,
        "old": before_text if metadata_changed else "",
        "new": after_text if metadata_changed else "",
        "generated": generated,
        "summary_path": str(Path(args.summary)),
        "exit_code": 0,
        "failure_reason": "",
    }
    Path(args.summary).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    if args.json:
        print(json.dumps(summary, separators=(",", ":"), sort_keys=True))
    else:
        print(f"PASS resolve-versions update changed={str(changed).lower()}", file=sys.stderr)


if __name__ == "__main__":
    summary_path = summary_path_from_argv(sys.argv[1:])
    try:
        main(sys.argv[1:])
    except UpdateError as exc:
        message = str(exc)
        print(message, file=sys.stderr)
        if "--json" in sys.argv:
            print(json.dumps(failure_summary(summary_path, message), separators=(",", ":"), sort_keys=True))
        sys.exit(1)
