#!/usr/bin/env bash
set -Eeuo pipefail

cnpg_resolve_versions() {
  local root_dir
  root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  CNPG_RESOLVER_ROOT="${root_dir}" python3 - "$@" <<'PY'
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(os.environ["CNPG_RESOLVER_ROOT"])
DEFAULT_METADATA = ROOT / "cloudnative-pg-timescaledb" / "versions.yaml"
UPSTREAM_IMAGE = "ghcr.io/cloudnative-pg/postgresql"
DEFAULT_FIXTURE_NAMES = ["standard-trixie-valid.json", "standard-bookworm-valid.json"]


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
        diag(command, path, "parseable metadata YAML subset", f"line {line_no}: {text!r}", "Use simple key/value YAML for CNPG resolver metadata.")
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
        diag(command, path, "metadata file exists", str(path), "Create metadata before resolving CNPG base images.")
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


def validate_resolver_metadata(data, command, artifact):
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
        diag(command, artifact, f"allowed keys exactly {sorted(expected_allowed)}", repr(allowed), "Keep CNPG resolver dimensions explicit.")
    for key, expected in expected_allowed.items():
        if allowed[key] != expected:
            diag(command, artifact, f"allowed.{key} exactly {expected!r}", repr(allowed[key]), "Only PostgreSQL 17, 18, 19beta1 and Debian trixie/bookworm are supported.")
    if not isinstance(data["entries"], list) or not data["entries"]:
        diag(command, artifact, "entries is non-empty list", type(data["entries"]).__name__, "Define image entries before resolving CNPG bases.")


def normalize_manifest(raw, source, command):
    tag = raw.get("tag")
    reference = raw.get("reference") or raw.get("image")
    if reference and not isinstance(reference, str):
        diag(command, source, "fixture manifest reference is string", repr(raw), "Use ghcr.io/cloudnative-pg/postgresql:<tag> references.")
    if isinstance(reference, str) and not reference.startswith(f"{UPSTREAM_IMAGE}:"):
        diag(command, source, f"fixture manifest reference starts with {UPSTREAM_IMAGE}:", reference, "Resolve only ghcr.io/cloudnative-pg/postgresql base images.")
    reference_tag = reference.rsplit(":", 1)[-1].split("@", 1)[0] if reference else ""
    if not tag and reference:
        tag = reference_tag
    if tag and reference_tag and tag != reference_tag:
        diag(command, source, "fixture manifest tag matches reference tag", f"tag={tag} reference={reference}", "Keep fixture tag and ghcr.io/cloudnative-pg/postgresql reference aligned.")
    if not reference and tag:
        reference = f"{UPSTREAM_IMAGE}:{tag}"
    digest = raw.get("digest", "")
    if "@" in reference and not digest:
        digest = reference.split("@", 1)[1]
    platforms = raw.get("platforms", [])
    if not isinstance(tag, str) or not tag:
        diag(command, source, "fixture manifest has tag or reference", repr(raw), "Add a tag or ghcr.io/cloudnative-pg/postgresql reference.")
    if not isinstance(digest, str):
        diag(command, source, "fixture manifest digest is string", repr(raw), "Use a sha256 digest string or an empty string.")
    if digest and not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        diag(command, source, "fixture manifest digest matches sha256:<64 hex>", digest, "Use valid fake or real digest values in fixtures.")
    if not isinstance(platforms, list) or any(not isinstance(platform, str) for platform in platforms):
        diag(command, source, "fixture manifest platforms are string list", repr(platforms), "Use explicit linux/amd64 and linux/arm64 platform strings.")
    return {"tag": tag, "reference": reference, "digest": digest, "platforms": platforms, "source": str(source)}


def load_fixture_file(path, command):
    try:
        payload = json.loads(path.read_text())
    except FileNotFoundError:
        diag(command, path, "fixture file exists", str(path), "Restore the CNPG resolver fixture file.")
    except json.JSONDecodeError as exc:
        diag(command, path, "fixture file is JSON", str(exc), "Use JSON for CNPG upstream fixture inventories.")
    if isinstance(payload, list):
        manifests = payload
    elif isinstance(payload, dict):
        manifests = payload.get("manifests") or payload.get("entries") or []
    else:
        diag(command, path, "fixture payload is object or list", type(payload).__name__, "Use manifests[] in CNPG resolver fixtures.")
    if not isinstance(manifests, list):
        diag(command, path, "fixture manifests is list", repr(manifests), "Use manifests[] in CNPG resolver fixtures.")
    return [normalize_manifest(manifest, path, command) for manifest in manifests]


def load_fixture_inventory(fixtures_dir, fixture_files, command):
    manifests = []
    if fixtures_dir:
        for name in DEFAULT_FIXTURE_NAMES:
            manifests.extend(load_fixture_file(Path(fixtures_dir) / name, command))
    for file_name in fixture_files:
        manifests.extend(load_fixture_file(Path(file_name), command))
    inventory = {}
    for manifest in manifests:
        if "-standard-" in manifest["tag"] and parse_standard_tag(manifest["tag"]) is None:
            match = re.fullmatch(r"(?P<pg>[^-]+)(?:-[0-9]{8,12})?-standard-(?P<debian>[^-]+)", manifest["tag"])
            actual = f"pg_major={match.group('pg') if match else 'unknown'} debian_variant={match.group('debian') if match else 'unknown'} tag={manifest['tag']}"
            diag(command, manifest["source"], "CNPG standard fixture tags use only PostgreSQL 17, 18, 19beta1 and Debian trixie/bookworm", actual, "Remove unsupported upstream CNPG standard tags from deterministic update fixtures.")
        previous = inventory.get(manifest["tag"])
        if previous and previous != manifest:
            diag(command, manifest["source"], "one manifest per CNPG tag", manifest["tag"], "Remove duplicate/conflicting fixture tag entries.")
        inventory[manifest["tag"]] = manifest
    return inventory


def inspect_remote(tag, command, artifact):
    reference = f"{UPSTREAM_IMAGE}:{tag}"
    if not shutil_which("docker"):
        diag(command, artifact, "fixture inventory or Docker CLI for remote resolution", "no --fixtures/--fixture-file and docker missing", "Pass --fixtures in tests or install Docker for live registry resolution.")
    try:
        text = subprocess.check_output(["docker", "buildx", "imagetools", "inspect", reference], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as exc:
        return None, exc.output.strip()
    digest_match = re.search(r"^Digest:\s+(sha256:[0-9a-f]{64})$", text, re.MULTILINE)
    platforms = re.findall(r"^\s*Platform:\s+([^\s]+)\s*$", text, re.MULTILINE)
    if not digest_match:
        return {"tag": tag, "reference": reference, "digest": "", "platforms": platforms, "source": "docker buildx imagetools inspect"}, "missing digest in docker output"
    return {"tag": tag, "reference": reference, "digest": digest_match.group(1), "platforms": platforms, "source": "docker buildx imagetools inspect"}, ""


def registry_request_json(url, command, artifact, token=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode()), response.headers
    except urllib.error.HTTPError as exc:
        if exc.code == 401 and token is None:
            auth = exc.headers.get("WWW-Authenticate", "")
            realm = re.search(r'realm="([^"]+)"', auth)
            service = re.search(r'service="([^"]+)"', auth)
            scope = re.search(r'scope="([^"]+)"', auth)
            if realm and service:
                query = {"service": service.group(1)}
                if scope:
                    query["scope"] = scope.group(1)
                token_url = f"{realm.group(1)}?{urllib.parse.urlencode(query)}"
                token_payload, _ = registry_request_json(token_url, command, artifact, "")
                bearer = token_payload.get("token") or token_payload.get("access_token")
                if bearer:
                    return registry_request_json(url, command, artifact, bearer)
        diag(command, artifact, "GHCR tag inventory request succeeds", f"HTTP {exc.code}: {exc.reason}", "Pass --fixtures in tests or allow anonymous pull access to ghcr.io/cloudnative-pg/postgresql.")
    except Exception as exc:
        diag(command, artifact, "GHCR tag inventory request succeeds", str(exc), "Pass --fixtures in tests or ensure network access to ghcr.io.")


def response_next_url(headers):
    link = headers.get("Link", "")
    match = re.search(r'<([^>]+)>;\s*rel="next"', link)
    if not match:
        return None
    next_url = match.group(1)
    if next_url.startswith("http"):
        return next_url
    return f"https://ghcr.io{next_url}"


def list_remote_tags(command, artifact):
    tags = []
    url = "https://ghcr.io/v2/cloudnative-pg/postgresql/tags/list?n=1000"
    while url:
        payload, headers = registry_request_json(url, command, artifact)
        batch = payload.get("tags")
        if not isinstance(batch, list):
            diag(command, artifact, "GHCR tags/list returns tags[]", repr(payload), "Use a registry endpoint compatible with Docker Registry HTTP API V2.")
        tags.extend(tag for tag in batch if isinstance(tag, str))
        url = response_next_url(headers)
    return sorted(set(tags))


def live_inventory(data, command, artifact):
    if not shutil_which("docker"):
        diag(command, artifact, "Docker CLI for live CNPG manifest inspection", "docker missing", "Pass --fixtures in tests or install Docker for live registry resolution.")
    wanted = {
        (entry["pg_major"], entry["debian_variant"])
        for entry in data["entries"]
    }
    inventory = {}
    for tag in list_remote_tags(command, artifact):
        parsed = parse_standard_tag(tag)
        if not parsed:
            continue
        if (parsed["pg_major"], parsed["debian_variant"]) not in wanted:
            continue
        manifest, actual = inspect_remote(tag, command, artifact)
        if manifest is None:
            diag(command, artifact, f"live CNPG manifest inspect succeeds for {UPSTREAM_IMAGE}:{tag}", actual, "Verify upstream tag availability or use deterministic fixtures.")
        inventory[tag] = manifest
    return inventory


def shutil_which(command):
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        path = Path(directory) / command
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    return None


def expected_tag(entry):
    return f"{entry['pg_version']}-standard-{entry['debian_variant']}"


def parse_standard_tag(tag):
    match = re.fullmatch(r"(?P<version>19beta1)-standard-(?P<debian>trixie|bookworm)", tag)
    if match:
        return {
            "pg_major": "19beta1",
            "pg_version": match.group("version"),
            "debian_variant": match.group("debian"),
            "minor": 0,
            "timestamped": False,
        }
    match = re.fullmatch(r"(?P<major>17|18)(?:\.(?P<minor>[0-9]+))?(?:-[0-9]{8,12})?-standard-(?P<debian>trixie|bookworm)", tag)
    if not match:
        return None
    minor = int(match.group("minor")) if match.group("minor") else -1
    version = match.group("major") if minor < 0 else f"{match.group('major')}.{minor}"
    return {
        "pg_major": match.group("major"),
        "pg_version": version,
        "debian_variant": match.group("debian"),
        "minor": minor,
        "timestamped": bool(re.fullmatch(r".*-[0-9]{8,12}-standard-(trixie|bookworm)", tag)),
    }


def select_standard_manifest(inventory, entry):
    candidates = []
    for tag, manifest in inventory.items():
        parsed = parse_standard_tag(tag)
        if not parsed:
            continue
        if parsed["pg_major"] != entry["pg_major"] or parsed["debian_variant"] != entry["debian_variant"]:
            continue
        candidates.append((parsed, manifest))
    if not candidates:
        return None, None
    candidates.sort(key=lambda item: (item[0]["minor"], not item[0]["timestamped"], item[1]["tag"]))
    return candidates[-1]


def matching_system_tags(inventory, entry):
    if entry["pg_major"] in {"17", "18"}:
        pg = rf"{re.escape(entry['pg_major'])}(?:\.[0-9]+)?"
    else:
        pg = re.escape(entry["pg_version"])
    debian = re.escape(entry["debian_variant"])
    pattern = re.compile(rf"^{pg}(?:-[0-9]{{8,12}})?-system-{debian}$")
    return sorted(tag for tag in inventory if pattern.fullmatch(tag))


def fail_entry(command, artifact, entry, platform, expected_ref, actual, remediation):
    diag(
        command,
        artifact,
        f"pg_major={entry['pg_major']} debian_variant={entry['debian_variant']} platform={platform} expected upstream reference={expected_ref}",
        actual,
        remediation,
    )


def skip_reason_specific(skip_reason, expected_ref, missing_dimension):
    return expected_ref in skip_reason and missing_dimension in skip_reason


def resolver_skip_reason(code, entry, expected_ref, detail):
    return f"resolver:{code}: {expected_ref} PostgreSQL {entry['pg_major']} {entry['debian_variant']} {detail}"


def resolver_owned(skip_reason):
    return not str(skip_reason).strip() or str(skip_reason).startswith("resolver:")


def resolve_entries(data, inventory, use_remote, command, artifact, allow_digest_drift=False, preserve_manual_skip=False):
    resolved = []
    for idx, entry in enumerate(data["entries"]):
        for required in ["pg_major", "pg_version", "debian_variant", "cnpg_tag", "cnpg_digest", "platforms", "publish", "experimental", "skip_reason"]:
            if required not in entry:
                diag(command, artifact, f"entries[{idx}].{required} exists", f"missing in {entry}", "Use the Story 1 metadata schema before resolving CNPG bases.")
        if entry["debian_variant"] not in ["trixie", "bookworm"]:
            fail_entry(command, artifact, entry, "all", f"{UPSTREAM_IMAGE}:{entry.get('cnpg_tag', '')}", f"unsupported Debian variant {entry['debian_variant']}", "Use only Debian trixie or bookworm; Alpine, bullseye, and aliases are out of scope.")
        if "system-" in entry["cnpg_tag"]:
            fail_entry(command, artifact, entry, "all", f"{UPSTREAM_IMAGE}:{expected_tag(entry)}", f"deprecated CNPG system flavor in metadata tag {entry['cnpg_tag']}", "Use CloudNativePG standard-* base image tags for v1.")
        tag = expected_tag(entry)
        expected_ref = f"{UPSTREAM_IMAGE}:{tag}"
        if entry["cnpg_tag"] != tag:
            fail_entry(command, artifact, entry, "all", expected_ref, f"metadata cnpg_tag={entry['cnpg_tag']}", "Set cnpg_tag from pg_version and explicit Debian variant.")
        selected, manifest = select_standard_manifest(inventory, entry)
        if manifest is not None:
            tag = manifest["tag"]
            expected_ref = f"{UPSTREAM_IMAGE}:{tag}"
        remote_actual = ""
        if manifest is None and use_remote:
            manifest, remote_actual = inspect_remote(tag, command, artifact)
            selected = parse_standard_tag(tag)
        systems = matching_system_tags(inventory, entry)
        if manifest is None and systems:
            expected_ref = f"{UPSTREAM_IMAGE}:{systems[-1].replace('-system-', '-standard-')}"
            fail_entry(command, artifact, entry, "all", expected_ref, f"deprecated system flavor available instead: {systems}", "Reject system-* and wait for or select a standard-* CNPG image.")
        if manifest is None:
            actual = remote_actual or "missing tag"
            if entry["publish"]:
                fail_entry(command, artifact, entry, "all", expected_ref, actual, "Publishable rows require an available standard-* CNPG base image tag.")
            if preserve_manual_skip and resolver_owned(entry["skip_reason"]):
                entry["skip_reason"] = resolver_skip_reason("cnpg-unavailable", entry, expected_ref, "missing tag")
            elif not preserve_manual_skip and not skip_reason_specific(entry["skip_reason"], expected_ref, "missing tag"):
                fail_entry(command, artifact, entry, "all", expected_ref, f"{actual}; skip_reason={entry['skip_reason']!r}", "For publish: false, include the upstream reference and missing tag in skip_reason.")
            digest = ""
            platforms = entry["platforms"]
        else:
            digest = manifest["digest"]
            platforms = sorted(manifest["platforms"])
            missing_platforms = []
            if not digest:
                if entry["publish"]:
                    fail_entry(command, artifact, entry, "all", expected_ref, "missing digest", "Publishable rows require a resolved CNPG digest.")
                if preserve_manual_skip and resolver_owned(entry["skip_reason"]):
                    entry["skip_reason"] = resolver_skip_reason("cnpg-unavailable", entry, expected_ref, "missing digest")
                elif not preserve_manual_skip and not skip_reason_specific(entry["skip_reason"], expected_ref, "missing digest"):
                    fail_entry(command, artifact, entry, "all", expected_ref, f"missing digest; skip_reason={entry['skip_reason']!r}", "For publish: false, include the upstream reference and missing digest in skip_reason.")
            for platform in entry["platforms"]:
                if platform not in platforms:
                    missing_platforms.append(platform)
                    actual = f"missing platform {platform}; available platforms={platforms}"
                    if entry["publish"]:
                        fail_entry(command, artifact, entry, platform, expected_ref, actual, "Publishable rows require all metadata platforms in the upstream manifest list.")
                    if preserve_manual_skip and resolver_owned(entry["skip_reason"]):
                        entry["skip_reason"] = resolver_skip_reason("cnpg-unavailable", entry, expected_ref, f"missing platform {platform}")
                    elif not preserve_manual_skip and not skip_reason_specific(entry["skip_reason"], expected_ref, f"missing platform {platform}"):
                        fail_entry(command, artifact, entry, platform, expected_ref, f"{actual}; skip_reason={entry['skip_reason']!r}", "For publish: false, include the upstream reference and missing platform in skip_reason.")
            if missing_platforms:
                digest = ""
            if entry["cnpg_digest"].strip() and entry["cnpg_digest"] != digest and not allow_digest_drift:
                fail_entry(command, artifact, entry, "all", expected_ref, f"metadata cnpg_digest={entry['cnpg_digest']} resolved digest={digest or 'unresolved'}", "Update cnpg_digest through the CNPG resolver only after all required platforms are present.")
        resolved_pg_version = selected["pg_version"] if selected else entry["pg_version"]
        resolved.append(
            {
                "pg_major": entry["pg_major"],
                "pg_version": resolved_pg_version,
                "debian_variant": entry["debian_variant"],
                "cnpg_tag": tag,
                "cnpg_digest": digest,
                "platforms": entry["platforms"],
                "publish": entry["publish"],
                "experimental": entry["experimental"],
                "skip_reason": entry["skip_reason"],
            }
        )
    return resolved


def build_parser():
    class DiagnosticArgumentParser(argparse.ArgumentParser):
        def error(self, message):
            diag("resolve-versions --check-cnpg", "arguments", "valid resolver arguments", message, "Pass required option values, for example --metadata <path> or --fixtures <dir>.")

    parser = DiagnosticArgumentParser(description="Resolve CloudNativePG base image tags and digests.")
    parser.add_argument("--check-cnpg", action="store_true", help="Validate CNPG standard base image availability and digest resolution.")
    parser.add_argument("--metadata", default=str(DEFAULT_METADATA), help="versions.yaml metadata file.")
    parser.add_argument("--fixtures", help="Directory with positive CNPG upstream inventory fixtures.")
    parser.add_argument("--fixture-file", action="append", default=[], help="Additional CNPG upstream inventory fixture JSON file.")
    parser.add_argument("--allow-digest-drift", action="store_true", help="Return resolved digests without failing when metadata contains an older resolver-owned digest.")
    parser.add_argument("--preserve-manual-skip", action="store_true", help="Update resolver-owned CNPG skip reasons while preserving maintainer-authored skip reasons.")
    parser.add_argument("--json", action="store_true", help="Emit compact JSON resolver output.")
    return parser


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv)
    command = "resolve-versions --check-cnpg"
    if args.fixtures:
        command += f" --fixtures {args.fixtures}"
    for fixture_file in args.fixture_file:
        command += f" --fixture-file {fixture_file}"
    if not args.check_cnpg:
        diag(command, "arguments", "--check-cnpg", "missing", "Story 2.1 only implements the CNPG resolver path.")
    metadata_path = Path(args.metadata)
    data = parse_metadata(metadata_path, command)
    validate_resolver_metadata(data, command, metadata_path)
    inventory = load_fixture_inventory(args.fixtures, args.fixture_file, command)
    if not inventory and not args.fixtures and not args.fixture_file:
        inventory = live_inventory(data, command, metadata_path)
    entries = resolve_entries(data, inventory, False, command, metadata_path, args.allow_digest_drift, args.preserve_manual_skip)
    payload = {"entries": entries}
    if args.json:
        print(json.dumps(payload, separators=(",", ":"), sort_keys=True))
    else:
        for entry in entries:
            print(f"CNPG {entry['pg_major']} {entry['debian_variant']} {entry['cnpg_tag']} {entry['cnpg_digest'] or 'unresolved'}")
        print(f"PASS resolve-versions --check-cnpg {metadata_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
PY
}
