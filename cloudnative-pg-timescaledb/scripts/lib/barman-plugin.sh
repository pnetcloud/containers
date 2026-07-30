#!/usr/bin/env bash
set -Eeuo pipefail

barman_plugin_resolve_reference() {
  python3 - "$@" <<'PY'
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SOURCE_URL = "https://github.com/cloudnative-pg/plugin-barman-cloud/releases"
API_URL = os.environ.get("BARMAN_PLUGIN_API_URL", "https://api.github.com/repos/cloudnative-pg/plugin-barman-cloud/releases?per_page=100")
TAG_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
BARMAN_PLUGIN_RETRY_STATUS = {429, 500, 502, 503, 504}
BARMAN_PLUGIN_RETRY_PATTERNS = ("timeout", "timed out", "temporary", "connection reset", "bad gateway", "service unavailable", "rate limit")


def diag(command, artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def env_int(name, default, minimum=1):
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError:
        diag("barman-plugin", name, f"integer >= {minimum}", raw, f"Unset {name} or set it to a bounded integer retry count.")
    if value < minimum:
        diag("barman-plugin", name, f"integer >= {minimum}", raw, f"Unset {name} or set it to a bounded integer retry count.")
    return value


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


def retry_delay(attempt):
    delay = os.environ.get("BARMAN_PLUGIN_RETRY_DELAY_SECONDS")
    if delay is None:
        time.sleep(attempt * 2)
        return
    try:
        seconds = float(delay)
    except ValueError:
        seconds = 0
    if seconds > 0:
        time.sleep(seconds)


def retryable_error(actual):
    lowered = actual.lower()
    return any(pattern in lowered for pattern in BARMAN_PLUGIN_RETRY_PATTERNS)


def trusted_token_hosts():
    raw = os.environ.get("BARMAN_PLUGIN_TRUSTED_TOKEN_HOSTS", "api.github.com")
    return {item.strip().lower() for item in raw.split(",") if item.strip()}


def url_host(url):
    return (urllib.parse.urlparse(url).hostname or "").lower()


def should_authorize_url(url):
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme == "https" and (parsed.hostname or "").lower() in trusted_token_hosts()


def response_next_url(headers):
    link = headers.get("Link", "")
    match = re.search(r'<([^>]+)>;\s*rel="next"', link)
    return match.group(1) if match else None


def semver_key(tag):
    if not TAG_RE.fullmatch(tag):
        return ()
    return tuple(int(part) for part in tag[1:].split("."))


def fetch_releases_page(url, headers, token, attempts_limit):
    attempts = []
    for attempt in range(1, attempts_limit + 1):
        request_headers = dict(headers)
        if token and should_authorize_url(url):
            request_headers["Authorization"] = f"Bearer {token}"
        request = urllib.request.Request(url, headers=request_headers)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8")), response.headers
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            actual = f"invalid JSON response: {exc}"
            attempts.append(f"attempt {attempt}: {actual}")
            if attempt < attempts_limit:
                retry_delay(attempt)
                continue
            diag("barman-plugin", url, f"GitHub releases page returns parseable JSON within {attempts_limit} attempts", "; ".join(attempts), "Retry later or use BARMAN_PLUGIN_FIXTURE for offline deterministic update tests.")
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")[:280]
            actual = f"HTTP {exc.code}: {body}"
            attempts.append(f"attempt {attempt}: {actual}")
            if (exc.code in BARMAN_PLUGIN_RETRY_STATUS or retryable_error(actual)) and attempt < attempts_limit:
                retry_delay(attempt)
                continue
            diag("barman-plugin", url, f"GitHub releases page is reachable within {attempts_limit} attempts", "; ".join(attempts), "Retry later or use BARMAN_PLUGIN_FIXTURE for offline deterministic update tests.")
        except (urllib.error.URLError, TimeoutError) as exc:
            actual = repr(exc)
            attempts.append(f"attempt {attempt}: {actual}")
            if attempt < attempts_limit:
                retry_delay(attempt)
                continue
            diag("barman-plugin", url, f"GitHub releases page is reachable within {attempts_limit} attempts", "; ".join(attempts), "Retry later or use BARMAN_PLUGIN_FIXTURE for offline deterministic update tests.")
        except Exception as exc:
            actual = repr(exc)
            attempts.append(f"attempt {attempt}: {actual}")
            if retryable_error(actual) and attempt < attempts_limit:
                retry_delay(attempt)
                continue
            diag("barman-plugin", url, f"GitHub releases page is reachable within {attempts_limit} attempts", "; ".join(attempts), "Retry later or use BARMAN_PLUGIN_FIXTURE for offline deterministic update tests.")
    diag("barman-plugin", url, f"GitHub releases page is reachable within {attempts_limit} attempts", "; ".join(attempts), "Retry later or use BARMAN_PLUGIN_FIXTURE for offline deterministic update tests.")


def fetch_latest(checked_at):
    attempts_limit = env_int("BARMAN_PLUGIN_LIVE_RESOLVE_ATTEMPTS", 5)
    max_pages = env_int("BARMAN_PLUGIN_MAX_PAGES", 5)
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "pnetcloud-containers-update",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    stable_tags = set()
    url = API_URL
    first_host = url_host(API_URL)
    page = 0
    while url and page < max_pages:
        page += 1
        if url_host(url) != first_host:
            diag("barman-plugin", url, f"pagination remains on release API host {first_host}", url_host(url), "Do not follow cross-host GitHub Link pagination URLs.")
        releases, response_headers = fetch_releases_page(url, headers, token, attempts_limit)
        if not isinstance(releases, list):
            diag("barman-plugin", url, "GitHub releases API returns a JSON list", repr(releases), "Use the GitHub releases API or a deterministic BARMAN_PLUGIN_FIXTURE.")
        for release in releases:
            tag = release.get("tag_name", "") if isinstance(release, dict) else ""
            if isinstance(release, dict) and not release.get("draft") and not release.get("prerelease") and TAG_RE.fullmatch(tag):
                stable_tags.add(tag)
        url = response_next_url(response_headers)
    if url:
        diag("barman-plugin", API_URL, f"all release pages are scanned within BARMAN_PLUGIN_MAX_PAGES={max_pages}", "pagination limit reached before the last page", "Increase BARMAN_PLUGIN_MAX_PAGES or use a deterministic BARMAN_PLUGIN_FIXTURE.")
    if not stable_tags:
        diag("barman-plugin", API_URL, "at least one stable vX.Y.Z release", "no stable release found in scanned pages", "Publish or fixture a stable CloudNativePG Barman Cloud Plugin release.")
    return reference_for_release(sorted(stable_tags, key=semver_key)[-1], checked_at)


parser = argparse.ArgumentParser()
parser.add_argument("--json", action="store_true")
parser.add_argument("--checked-at-utc", default=os.environ.get("BARMAN_PLUGIN_CHECKED_AT_UTC", datetime.now(timezone.utc).date().isoformat()))
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
