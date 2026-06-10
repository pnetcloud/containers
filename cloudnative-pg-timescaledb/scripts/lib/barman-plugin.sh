#!/usr/bin/env bash
set -Eeuo pipefail

barman_plugin_resolve_reference() {
  python3 - "$@" <<'PY'
import argparse
from datetime import date
import json
import os
from pathlib import Path
import re
import sys
import urllib.request

SOURCE_URL = "https://github.com/cloudnative-pg/plugin-barman-cloud/releases"
API_URL = "https://api.github.com/repos/cloudnative-pg/plugin-barman-cloud/releases?per_page=30"
TAG_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")


def diag(command, artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def reference_for_release(release, checked_at):
    return {
        "release": release,
        "manifest_url": f"https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/{release}/manifest.yaml",
        "plugin_image": f"ghcr.io/cloudnative-pg/plugin-barman-cloud:{release}",
        "sidecar_image": f"ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:{release}",
        "source_url": SOURCE_URL,
        "checked_at_utc": checked_at,
    }


def load_fixture(path):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        diag("barman-plugin", path, "fixture exists", "missing", "Create the requested Barman plugin fixture.")
    except json.JSONDecodeError as exc:
        diag("barman-plugin", path, "valid fixture JSON", str(exc), "Fix fixture JSON syntax.")
    required = {"release", "manifest_url", "plugin_image", "sidecar_image", "source_url", "checked_at_utc", "expected_changed"}
    if set(data) != required:
        diag("barman-plugin", path, f"fixture keys exactly {sorted(required)}", sorted(data), "Preserve the Barman plugin fixture schema.")
    if not TAG_RE.fullmatch(data["release"]):
        diag("barman-plugin", path, "stable release tag vX.Y.Z", data["release"], "Use a stable plugin release tag.")
    return {key: data[key] for key in ["release", "manifest_url", "plugin_image", "sidecar_image", "source_url", "checked_at_utc"]}


def fetch_latest(checked_at):
    try:
        with urllib.request.urlopen(API_URL, timeout=30) as response:
            releases = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        diag("barman-plugin", API_URL, "GitHub releases are reachable", repr(exc), "Use BARMAN_PLUGIN_FIXTURE for offline deterministic update tests.")
    for release in releases:
        tag = release.get("tag_name", "")
        if release.get("draft") or release.get("prerelease") or not TAG_RE.fullmatch(tag):
            continue
        return reference_for_release(tag, checked_at)
    diag("barman-plugin", API_URL, "at least one stable vX.Y.Z release", releases[:3], "Publish or fixture a stable CloudNativePG Barman Cloud Plugin release.")


parser = argparse.ArgumentParser()
parser.add_argument("--json", action="store_true")
parser.add_argument("--checked-at-utc", default=os.environ.get("BARMAN_PLUGIN_CHECKED_AT_UTC", date.today().isoformat()))
args = parser.parse_args()
fixture = os.environ.get("BARMAN_PLUGIN_FIXTURE", "")
payload = load_fixture(fixture) if fixture else fetch_latest(args.checked_at_utc)
if args.json:
    print(json.dumps(payload, separators=(",", ":"), sort_keys=True))
else:
    print(payload["release"])
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  barman_plugin_resolve_reference "$@"
fi
