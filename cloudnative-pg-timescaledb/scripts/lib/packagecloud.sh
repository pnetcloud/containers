#!/usr/bin/env bash
set -Eeuo pipefail

packagecloud_resolve_versions() {
  local root_dir
  root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  PACKAGECLOUD_RESOLVER_ROOT="${root_dir}" python3 - "$@" <<'PY'
import argparse
from functools import cmp_to_key
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


ROOT = Path(os.environ["PACKAGECLOUD_RESOLVER_ROOT"])
DEFAULT_METADATA = ROOT / "cloudnative-pg-timescaledb" / "versions.yaml"
DEFAULT_FIXTURE_NAMES = [
    "trixie-amd64-available.json",
    "trixie-arm64-available.json",
    "bookworm-amd64-available.json",
    "bookworm-arm64-available.json",
]
PLATFORM_ARCH = {"linux/amd64": "amd64", "linux/arm64": "arm64"}
DEBIAN_VARIANTS = {"trixie", "bookworm"}
PACKAGE_TYPES = {"timescaledb", "toolkit"}
PACKAGECLOUD_BASE_URL = "https://packagecloud.io"
PACKAGE_INDEX_CACHE = {}


def diag(command, artifact, expected, actual, remediation):
    raise SystemExit(
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
        diag(command, path, "parseable metadata YAML subset", f"line {line_no}: {text!r}", "Use simple key/value YAML for package resolver metadata.")
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
        diag(command, path, "metadata file exists", str(path), "Create metadata before resolving packages.")
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


def validate_metadata(data, command, artifact):
    required_top = {"schema_version", "image", "allowed", "entries"}
    optional_top = {"barman_plugin"}
    if not required_top.issubset(data) or set(data) - required_top - optional_top:
        diag(command, artifact, f"top-level keys include {sorted(required_top)} and optional {sorted(optional_top)}", f"actual {sorted(data)}", "Use the versions.yaml metadata contract.")
    allowed = data["allowed"]
    expected_allowed = {
        "postgres_majors": ["17", "18", "19beta1"],
        "debian_variants": ["trixie", "bookworm"],
        "platforms": ["linux/amd64", "linux/arm64"],
    }
    if not isinstance(allowed, dict) or set(allowed) != set(expected_allowed):
        diag(command, artifact, f"allowed keys exactly {sorted(expected_allowed)}", repr(allowed), "Keep package resolver dimensions explicit.")
    for key, expected in expected_allowed.items():
        if allowed[key] != expected:
            diag(command, artifact, f"allowed.{key} exactly {expected!r}", repr(allowed[key]), "Only PostgreSQL 17, 18, 19beta1, Debian trixie/bookworm, and linux/amd64 plus linux/arm64 are supported.")
    if not isinstance(data["entries"], list) or not data["entries"]:
        diag(command, artifact, "entries is non-empty list", type(data["entries"]).__name__, "Define image entries before resolving packages.")


def pg_package_major(pg_major):
    if pg_major == "19beta1":
        return "19"
    return pg_major


def expected_package_name(package_type, pg_major):
    package_major = pg_package_major(pg_major)
    if package_type == "timescaledb":
        return f"timescaledb-2-postgresql-{package_major}"
    return f"timescaledb-toolkit-postgresql-{package_major}"


def extension_version(package_type, package_version):
    version = package_version.split("~", 1)[0]
    if package_type == "toolkit" and ":" in version:
        version = version.split(":", 1)[1]
    return version


def version_key(version):
    base = extension_version("toolkit", version)
    parts = []
    for item in re.split(r"[^0-9]+", base):
        if item:
            parts.append(int(item))
    return parts or [0]


def debian_order_char(char):
    if char == "":
        return 0
    if char == "~":
        return -1
    if char.isalpha():
        return ord(char)
    return ord(char) + 256


def compare_debian_non_digit(left, right):
    left_index = 0
    right_index = 0
    while left_index < len(left) or right_index < len(right):
        left_char = left[left_index] if left_index < len(left) else ""
        right_char = right[right_index] if right_index < len(right) else ""
        if left_char == right_char:
            left_index += 1 if left_index < len(left) else 0
            right_index += 1 if right_index < len(right) else 0
            if left_char == "":
                return 0
            continue
        left_order = debian_order_char(left_char)
        right_order = debian_order_char(right_char)
        if left_order != right_order:
            return -1 if left_order < right_order else 1
        left_index += 1 if left_index < len(left) else 0
        right_index += 1 if right_index < len(right) else 0
    return 0


def split_debian_version(version):
    parts = []
    cursor = 0
    while cursor < len(version):
        digit_match = re.match(r"[0-9]+", version[cursor:])
        if digit_match:
            token = digit_match.group(0)
            parts.append(("digit", token.lstrip("0") or "0"))
            cursor += len(token)
            continue
        non_digit_match = re.match(r"[^0-9]+", version[cursor:])
        token = non_digit_match.group(0)
        parts.append(("non-digit", token))
        cursor += len(token)
    return parts


def split_debian_epoch(version):
    if ":" not in version:
        return 0, version
    epoch, remainder = version.split(":", 1)
    if re.fullmatch(r"[0-9]+", epoch):
        return int(epoch), remainder
    return 0, version


def compare_debian_version(left, right):
    left_epoch, left = split_debian_epoch(left)
    right_epoch, right = split_debian_epoch(right)
    if left_epoch != right_epoch:
        return -1 if left_epoch < right_epoch else 1
    left_parts = split_debian_version(left)
    right_parts = split_debian_version(right)
    index = 0
    while index < len(left_parts) or index < len(right_parts):
        left_type, left_value = left_parts[index] if index < len(left_parts) else ("non-digit", "")
        right_type, right_value = right_parts[index] if index < len(right_parts) else ("non-digit", "")
        if left_type == "digit" and right_type == "digit":
            if len(left_value) != len(right_value):
                return -1 if len(left_value) < len(right_value) else 1
            if left_value != right_value:
                return -1 if left_value < right_value else 1
        elif left_type == "digit":
            return 1
        elif right_type == "digit":
            return -1
        else:
            result = compare_debian_non_digit(left_value, right_value)
            if result != 0:
                return result
        index += 1
    return 0


def normalize_record(raw, source, command):
    required = {"name", "version", "distribution", "architecture", "pg_major", "package_type", "source_url"}
    if not isinstance(raw, dict):
        diag(command, source, "package fixture record is object", repr(raw), "Use package fixture records with required fields.")
    missing = required - set(raw)
    extra = set(raw) - required
    if missing or extra:
        diag(command, source, f"package fixture record keys exactly {sorted(required)}", f"missing {sorted(missing)}, extra {sorted(extra)}", "Keep package fixture schema aligned with Story 2.2.")
    for key in required:
        if not isinstance(raw[key], str) or not raw[key]:
            diag(command, source, f"package fixture {key} is non-empty string", repr(raw[key]), "Use explicit package fixture strings.")
    if raw["distribution"] not in DEBIAN_VARIANTS:
        diag(command, source, "distribution is trixie or bookworm", raw["distribution"], "Do not use Alpine, bullseye, or Debian aliases in package fixtures.")
    if raw["architecture"] not in {"amd64", "arm64"}:
        diag(command, source, "architecture is amd64 or arm64", raw["architecture"], "Map linux/amd64 to amd64 and linux/arm64 to arm64 only.")
    if raw["pg_major"] not in {"17", "18", "19"}:
        diag(command, source, "package record pg_major is ABI major 17, 18, or 19", raw["pg_major"], "Use PostgreSQL package ABI majors in package records; metadata 19beta1 maps to package major 19.")
    if raw["package_type"] not in PACKAGE_TYPES:
        diag(command, source, "package_type is timescaledb or toolkit", raw["package_type"], "Use only TimescaleDB and Toolkit package records.")
    expected_name = expected_package_name(raw["package_type"], raw["pg_major"])
    if raw["name"] != expected_name:
        diag(command, source, f"package name {expected_name}", raw["name"], "Derive package names from package type and PostgreSQL major.")
    return dict(raw)


def load_fixture_file(path, command):
    try:
        payload = json.loads(path.read_text())
    except FileNotFoundError:
        diag(command, path, "fixture file exists", str(path), "Restore the packagecloud fixture file.")
    except json.JSONDecodeError as exc:
        diag(command, path, "fixture file is JSON", str(exc), "Use JSON packagecloud fixture records.")
    if isinstance(payload, list):
        records = payload
    elif isinstance(payload, dict):
        records = payload.get("packages") or payload.get("records") or []
    else:
        diag(command, path, "fixture payload is object or list", type(payload).__name__, "Use packages[] in packagecloud fixtures.")
    if not isinstance(records, list):
        diag(command, path, "fixture packages is list", repr(records), "Use packages[] in packagecloud fixtures.")
    return [normalize_record(record, path, command) for record in records]


def load_inventory(fixtures_dir, fixture_files, command):
    records = []
    if fixtures_dir:
        for name in DEFAULT_FIXTURE_NAMES:
            records.extend(load_fixture_file(Path(fixtures_dir) / name, command))
    for fixture_file in fixture_files:
        records.extend(load_fixture_file(Path(fixture_file), command))
    inventory = {}
    for record in records:
        key = (record["package_type"], record["pg_major"], record["distribution"], record["architecture"])
        inventory.setdefault(key, []).append(record)
    return inventory


def parse_debian_packages_index(text):
    records = []
    current = {}
    current_key = None
    for raw_line in text.splitlines():
        if raw_line == "":
            if current:
                records.append(current)
                current = {}
                current_key = None
            continue
        if raw_line.startswith((" ", "\t")) and current_key:
            current[current_key] = f"{current[current_key]}\n{raw_line}"
            continue
        if ":" not in raw_line:
            continue
        key, value = raw_line.split(":", 1)
        current[key] = value.strip()
        current_key = key
    if current:
        records.append(current)
    return records


def fetch_package_index(repo, distribution, architecture, command):
    try:
        user, repo_name = repo.split("/", 1)
    except ValueError:
        diag(command, "arguments", "--packagecloud-repo user/repo", repo, "Use the packagecloud repository owner/name format, for example timescale/timescaledb.")
    url = f"{PACKAGECLOUD_BASE_URL}/{quote(user)}/{quote(repo_name)}/debian/dists/{quote(distribution)}/main/binary-{quote(architecture)}/Packages"
    if url in PACKAGE_INDEX_CACHE:
        return url, PACKAGE_INDEX_CACHE[url]
    request = Request(url, headers={"Accept": "text/plain", "User-Agent": "pnet-cloudnative-pg-timescaledb-resolver"})
    try:
        with urlopen(request, timeout=30) as response:
            text = response.read().decode("utf-8")
    except HTTPError as exc:
        if exc.code == 404:
            PACKAGE_INDEX_CACHE[url] = []
            return url, []
        diag(command, url, "public Packagecloud Debian Packages index", f"HTTP {exc.code}", "Retry later or use --fixtures for deterministic validation.")
    except (URLError, TimeoutError, UnicodeDecodeError) as exc:
        diag(command, url, "public Packagecloud Debian Packages index", str(exc), "Retry later or use --fixtures for deterministic validation.")
    PACKAGE_INDEX_CACHE[url] = parse_debian_packages_index(text)
    return url, PACKAGE_INDEX_CACHE[url]


def fetch_package_versions(repo, distribution, architecture, pg_major, package_type, command):
    package_name = expected_package_name(package_type, pg_major)
    url, packages = fetch_package_index(repo, distribution, architecture, command)
    records = []
    for package in packages:
        if package.get("Package") != package_name:
            continue
        version = package.get("Version", "")
        if not version:
            continue
        records.append(
            normalize_record(
                {
                    "name": package_name,
                    "version": version,
                    "distribution": distribution,
                    "architecture": architecture,
                    "pg_major": pg_major,
                    "package_type": package_type,
                    "source_url": url,
                },
                url,
                command,
            )
        )
    return records


def load_live_inventory(data, repo, command):
    records = []
    requested = set()
    for entry in data["entries"]:
        for platform in entry.get("platforms", []):
            arch = PLATFORM_ARCH.get(platform)
            if not arch:
                continue
            for package_type in sorted(PACKAGE_TYPES):
                requested.add((entry["debian_variant"], arch, pg_package_major(entry["pg_major"]), package_type))
    for distribution, arch, pg_major, package_type in sorted(requested):
        records.extend(fetch_package_versions(repo, distribution, arch, pg_major, package_type, command))
    inventory = {}
    for record in records:
        key = (record["package_type"], record["pg_major"], record["distribution"], record["architecture"])
        inventory.setdefault(key, []).append(record)
    return inventory


def fail_entry(command, artifact, entry, package_type, platform, expected, actual, remediation):
    diag(
        command,
        artifact,
        f"pg_major={entry['pg_major']} debian_variant={entry['debian_variant']} platform={platform} package_type={package_type} expected={expected}",
        actual,
        remediation,
    )


def skip_reason_specific(skip_reason, package_name, entry, platform):
    tokens = set(re.split(r"[^A-Za-z0-9_./:+~-]+", skip_reason))
    return package_name in tokens and entry["pg_major"] in tokens and entry["debian_variant"] in tokens and platform in tokens


def manual_skip_preserved(entry, preserve_manual_skip):
    reason = str(entry.get("skip_reason", ""))
    return preserve_manual_skip and reason.strip() and not reason.startswith("resolver:") and not entry["publish"]


def contract_skip_reason(entry, package_name, platforms, detail):
    platform_text = " ".join(platforms)
    return f"{package_name} PostgreSQL {entry['pg_major']} {entry['debian_variant']} {platform_text} {detail}"


def resolve_package(command, artifact, inventory, entry, package_type, preserve_manual_skip=False):
    package_name = expected_package_name(package_type, entry["pg_major"])
    versions_by_platform = {}
    missing_platforms = []
    for platform in entry["platforms"]:
        arch = PLATFORM_ARCH.get(platform)
        if not arch:
            fail_entry(command, artifact, entry, package_type, platform, package_name, f"unsupported platform {platform}", "Use only linux/amd64 and linux/arm64.")
        records = inventory.get((package_type, pg_package_major(entry["pg_major"]), entry["debian_variant"], arch), [])
        versions = {record["version"] for record in records if record["name"] == package_name}
        if not versions:
            actual = f"missing package for architecture {arch}"
            if entry["publish"]:
                fail_entry(command, artifact, entry, package_type, platform, package_name, actual, "Publishable rows require TimescaleDB and Toolkit packages on every required platform.")
            missing_platforms.append((platform, arch))
            continue
        versions_by_platform[platform] = versions
    if missing_platforms:
        missing_platform_names = [platform for platform, _arch in missing_platforms]
        if manual_skip_preserved(entry, preserve_manual_skip):
            return package_name, "", ""
        if preserve_manual_skip and str(entry.get("skip_reason", "")).startswith("resolver:"):
            entry["skip_reason"] = contract_skip_reason(entry, package_name, missing_platform_names, "missing packages while CNPG exists")
        for platform, arch in missing_platforms:
            if not skip_reason_specific(entry["skip_reason"], package_name, entry, platform):
                fail_entry(command, artifact, entry, package_type, platform, package_name, f"missing package for architecture {arch}; skip_reason={entry['skip_reason']!r}", "For publish: false, include package name, PostgreSQL major, Debian variant, and every missing platform in skip_reason.")
        return package_name, "", ""
    common = set.intersection(*versions_by_platform.values()) if versions_by_platform else set()
    if not common:
        actual = "; ".join(f"{platform}={sorted(versions)}" for platform, versions in sorted(versions_by_platform.items()))
        if entry["publish"]:
            fail_entry(command, artifact, entry, package_type, ",".join(entry["platforms"]), package_name, f"mismatched package versions: {actual}", "Choose one package version available on every required platform.")
        if manual_skip_preserved(entry, preserve_manual_skip):
            return package_name, "", ""
        if preserve_manual_skip and str(entry.get("skip_reason", "")).startswith("resolver:"):
            entry["skip_reason"] = contract_skip_reason(entry, package_name, entry["platforms"], "mismatched package versions")
        skip_tokens = set(re.split(r"[^A-Za-z0-9_./:+~-]+", entry["skip_reason"]))
        if package_name not in skip_tokens or "mismatched package versions" not in entry["skip_reason"]:
            fail_entry(command, artifact, entry, package_type, ",".join(entry["platforms"]), package_name, f"mismatched package versions: {actual}; skip_reason={entry['skip_reason']!r}", "For publish: false, include package name and mismatched package versions in skip_reason.")
        return package_name, "", ""
    package_version = sorted(common, key=cmp_to_key(compare_debian_version))[-1]
    return package_name, package_version, extension_version(package_type, package_version)


def resolve_entries(command, artifact, data, inventory, preserve_manual_skip=False):
    results = []
    allowed_pg_majors = set(data["allowed"]["postgres_majors"])
    for idx, entry in enumerate(data["entries"]):
        for required in ["pg_major", "debian_variant", "platforms", "publish", "experimental", "skip_reason"]:
            if required not in entry:
                diag(command, artifact, f"entries[{idx}].{required} exists", f"missing in {entry}", "Use the Story 1 metadata schema before resolving packages.")
        if entry["pg_major"] not in allowed_pg_majors:
            fail_entry(command, artifact, entry, "all", "all", f"pg_major in allowed.postgres_majors {sorted(allowed_pg_majors)}", entry["pg_major"], "Use metadata PostgreSQL majors 17, 18, or 19beta1; derive package ABI major separately.")
        if entry["debian_variant"] not in DEBIAN_VARIANTS:
            fail_entry(command, artifact, entry, "all", "all", "trixie or bookworm", entry["debian_variant"], "Do not use Alpine, bullseye, or Debian aliases.")
        if not isinstance(entry["platforms"], list) or not entry["platforms"]:
            fail_entry(command, artifact, entry, "all", "all", "non-empty platforms", repr(entry["platforms"]), "Set linux/amd64 and/or linux/arm64 explicitly.")
        platform_set = set(entry["platforms"])
        required_platforms = set(PLATFORM_ARCH)
        if entry["publish"] and platform_set != required_platforms:
            fail_entry(command, artifact, entry, "all", ",".join(entry["platforms"]), "linux/amd64 and linux/arm64", sorted(platform_set), "Publishable rows must check both required package platforms.")
        if not entry["publish"] and platform_set != required_platforms:
            missing_platforms = sorted(required_platforms - platform_set)
            if missing_platforms and not all(platform in entry["skip_reason"] for platform in missing_platforms):
                fail_entry(command, artifact, entry, "all", ",".join(entry["platforms"]), f"skip_reason names omitted platforms {missing_platforms}", entry["skip_reason"], "For publish: false with a reduced platform set, name every omitted required platform in skip_reason.")
        ts_name, ts_pkg_version, ts_version = resolve_package(command, artifact, inventory, entry, "timescaledb", preserve_manual_skip)
        tk_name, tk_pkg_version, tk_version = resolve_package(command, artifact, inventory, entry, "toolkit", preserve_manual_skip)
        results.append(
            {
                "pg_major": entry["pg_major"],
                "pg_package_major": pg_package_major(entry["pg_major"]),
                "debian_variant": entry["debian_variant"],
                "platforms": entry["platforms"],
                "timescaledb_version": ts_version,
                "timescaledb_package_name": ts_name,
                "timescaledb_package_version": ts_pkg_version,
                "toolkit_version": tk_version,
                "toolkit_package_name": tk_name,
                "toolkit_package_version": tk_pkg_version,
                "publish": entry["publish"],
                "experimental": entry["experimental"],
                "skip_reason": entry["skip_reason"],
            }
        )
    return results


def build_parser():
    class DiagnosticArgumentParser(argparse.ArgumentParser):
        def error(self, message):
            diag("resolve-versions --check-packages", "arguments", "valid package resolver arguments", message, "Pass required option values, for example --fixtures <dir> or --metadata <path>.")

    parser = DiagnosticArgumentParser(description="Resolve TimescaleDB and Toolkit package versions.")
    parser.add_argument("--check-packages", action="store_true", help="Validate TimescaleDB and Toolkit package availability.")
    parser.add_argument("--metadata", default=str(DEFAULT_METADATA), help="versions.yaml metadata file.")
    parser.add_argument("--fixtures", help="Directory with positive package fixture files.")
    parser.add_argument("--fixture-file", action="append", default=[], help="Additional package fixture JSON file.")
    parser.add_argument("--packagecloud-repo", default="timescale/timescaledb", help="Packagecloud user/repo for live package lookup.")
    parser.add_argument("--preserve-manual-skip", action="store_true", help="Allow update mode to preserve non-prefixed maintainer skip reasons for non-publish rows.")
    parser.add_argument("--json", action="store_true", help="Emit compact JSON resolver output.")
    return parser


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv)
    command = "resolve-versions --check-packages"
    if args.fixtures:
        command += f" --fixtures {args.fixtures}"
    for fixture_file in args.fixture_file:
        command += f" --fixture-file {fixture_file}"
    if not args.check_packages:
        diag(command, "arguments", "--check-packages", "missing", "Story 2.2 only implements the package resolver path.")
    metadata_path = Path(args.metadata)
    data = parse_metadata(metadata_path, command)
    validate_metadata(data, command, metadata_path)
    if args.fixtures or args.fixture_file:
        inventory = load_inventory(args.fixtures, args.fixture_file, command)
    else:
        inventory = load_live_inventory(data, args.packagecloud_repo, command)
    entries = resolve_entries(command, metadata_path, data, inventory, args.preserve_manual_skip)
    payload = {"entries": entries}
    if args.json:
        print(json.dumps(payload, separators=(",", ":"), sort_keys=True))
    else:
        for entry in entries:
            print(f"PACKAGES {entry['pg_major']} {entry['debian_variant']} timescaledb={entry['timescaledb_package_version'] or 'unresolved'} toolkit={entry['toolkit_package_version'] or 'unresolved'}")
        print(f"PASS resolve-versions --check-packages {metadata_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
PY
}
