#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/barman-plugin/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

prepare_project() {
  local target="$1"
  mkdir -p "${target}/cloudnative-pg-timescaledb" "${target}/docs"
  cp "${ROOT_DIR}/Makefile" "${target}/Makefile"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/config" "${target}/cloudnative-pg-timescaledb/config"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts" "${target}/cloudnative-pg-timescaledb/scripts"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/templates" "${target}/cloudnative-pg-timescaledb/templates"
  mkdir -p "${target}/cloudnative-pg-timescaledb/tests/release-rehearsal"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures" "${target}/cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/generated" "${target}/cloudnative-pg-timescaledb/generated"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/catalog" "${target}/cloudnative-pg-timescaledb/catalog"
  if [[ -d "${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata" ]]; then
    cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata" "${target}/cloudnative-pg-timescaledb/release-metadata"
  fi
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/docs" "${target}/cloudnative-pg-timescaledb/docs"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${target}/cloudnative-pg-timescaledb/versions.yaml"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docker-bake.hcl" "${target}/cloudnative-pg-timescaledb/docker-bake.hcl"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/matrix.json" "${target}/cloudnative-pg-timescaledb/matrix.json"
  (cd "${target}" && git init -q && git config user.email test@example.invalid && git config user.name test && git add . && git commit -qm baseline)
}

prepare_upstream() {
  local target="$1"
  mkdir -p "${target}/cnpg" "${target}/packages"
  python3 - "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${target}" <<'PY'
from pathlib import Path
import json
import sys

metadata = Path(sys.argv[1]).read_text().splitlines()
target = Path(sys.argv[2])

def parse_scalar(value):
    value = value.strip()
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    if value == "true":
        return True
    if value == "false":
        return False
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        return [] if not inner else [item.strip().strip('"') for item in inner.split(",")]
    return value

entries = []
current = None
for raw in metadata:
    if raw.startswith("  - pg_major:"):
        current = {"pg_major": parse_scalar(raw.split(":", 1)[1])}
        entries.append(current)
    elif current is not None and raw.startswith("    ") and ":" in raw:
        key, value = raw.strip().split(":", 1)
        current[key] = parse_scalar(value)

for debian in ["trixie", "bookworm"]:
    manifests = []
    for entry in entries:
        if entry["debian_variant"] == debian:
            manifests.append({"tag": entry["cnpg_tag"], "digest": entry["cnpg_digest"], "platforms": entry["platforms"]})
    (target / "cnpg" / f"standard-{debian}-valid.json").write_text(json.dumps({"manifests": manifests}, indent=2, sort_keys=True) + "\n")

debian_version = {"trixie": "debian13", "bookworm": "debian12"}
for debian in ["trixie", "bookworm"]:
    for arch in ["amd64", "arm64"]:
        packages = []
        for entry in entries:
            if entry["debian_variant"] != debian or entry["pg_major"] == "19beta1":
                continue
            packages.append({
                "name": f"timescaledb-2-postgresql-{entry['pg_major']}",
                "version": entry["timescaledb_package_version"],
                "distribution": debian,
                "architecture": arch,
                "pg_major": entry["pg_major"],
                "package_type": "timescaledb",
                "source_url": f"fixture://{debian}/{arch}/timescaledb/{entry['pg_major']}",
            })
            packages.append({
                "name": f"timescaledb-toolkit-postgresql-{entry['pg_major']}",
                "version": entry["toolkit_package_version"],
                "distribution": debian,
                "architecture": arch,
                "pg_major": entry["pg_major"],
                "package_type": "toolkit",
                "source_url": f"fixture://{debian}/{arch}/toolkit/{entry['pg_major']}",
            })
        (target / "packages" / f"{debian}-{arch}-available.json").write_text(json.dumps({"packages": packages}, indent=2, sort_keys=True) + "\n")
PY
}

write_barman_fixture_from_metadata() {
  local metadata="$1"
  local target="$2"
  local expected_changed="$3"
  python3 - "${metadata}" "${target}" "${expected_changed}" <<'PY'
from pathlib import Path
import json
import re
import sys

metadata = Path(sys.argv[1])
target = Path(sys.argv[2])
expected_changed = sys.argv[3] == "true"
text = metadata.read_text().splitlines()
fields = {}
in_barman = False
for raw in text:
    if raw == "barman_plugin:":
        in_barman = True
        continue
    if in_barman and raw and not raw.startswith("  "):
        break
    if in_barman and raw.startswith("  ") and ":" in raw:
        key, value = raw.strip().split(":", 1)
        fields[key] = value.strip().strip('"')

release = fields["release"]
if expected_changed:
    match = re.fullmatch(r"v([0-9]+)\.([0-9]+)\.([0-9]+)", release)
    if not match:
        raise SystemExit(f"cannot bump release {release!r}")
    major, minor, patch = (int(part) for part in match.groups())
    release = f"v{major}.{minor}.{patch + 1}"

payload = {
    "release": release,
    "manifest_url": f"https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/{release}/manifest.yaml",
    "plugin_image": f"ghcr.io/cloudnative-pg/plugin-barman-cloud:{release}",
    "sidecar_image": f"ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:{release}",
    "source_url": fields["source_url"],
    "checked_at_utc": fields["updated_at_utc"],
    "expected_changed": expected_changed,
}
target.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

run_update() {
  local project="$1"
  local upstream="$2"
  local fixture="$3"
  local stdout_file="$4"
  local stderr_file="$5"
  cp "${fixture}" "${upstream}/barman-plugin.json"
  set +e
  (cd "${project}" && make --no-print-directory update UPDATE_ARGS="--fixtures ${upstream} --json") >"${stdout_file}" 2>"${stderr_file}"
  local status="$?"
  set -e
  return "${status}"
}

assert_barman_json() {
  local file="$1"
  local expected_changed="$2"
  python3 - "${file}" "${expected_changed}" <<'PY'
from pathlib import Path
import json
import sys
payload = json.loads(Path(sys.argv[1]).read_text())
expected_changed = sys.argv[2] == "true"
required = {"changed", "updated_entries", "old", "new", "generated", "summary_path", "exit_code", "failure_reason"}
if set(payload) != required:
    raise SystemExit(f"wrong update JSON keys: {sorted(payload)}")
if payload.get("changed") is not expected_changed:
    raise SystemExit(f"top-level changed should reflect Barman update: {payload}")
if payload.get("exit_code") != 0 or payload.get("failure_reason") != "":
    raise SystemExit(f"expected success JSON: {payload}")
PY
}

expect_boundary_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh" "${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-barman-boundary ${fixture}" "legacy Barman fixture is rejected" "exit 0" "Remove legacy in-image Barman guidance from fixtures."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-barman-boundary ${fixture}" "diagnostic mentions ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep Barman boundary diagnostics actionable."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

assert_non_github_override_does_not_receive_token() {
  local tmp_dir port_file server_pid api_url
  tmp_dir="$(mktemp -d)"
  port_file="${tmp_dir}/port"
  python3 - "${port_file}" <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import sys

port_file = Path(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization"):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'{"message":"unexpected authorization header"}')
            return
        payload = [
            {"tag_name": "v0.99.0", "draft": False, "prerelease": False},
            {"tag_name": "v0.100.0-rc1", "draft": False, "prerelease": True},
        ]
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


server = HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(f"http://127.0.0.1:{server.server_port}/releases\n")
server.serve_forever()
PY
  server_pid="$!"
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    sleep 0.1
  done
  if [[ ! -s "${port_file}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin override server" "${port_file}" "server writes API URL" "missing" "Keep resolver override test server start-up reliable."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  api_url="$(cat "${port_file}")"
  if ! BARMAN_PLUGIN_API_URL="${api_url}" GITHUB_TOKEN="test-token" BARMAN_PLUGIN_CHECKED_AT_UTC="2026-07-01" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh" --json >"${tmp_dir}/auth.out"; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin --json" "non-GitHub API override does not receive GitHub token" "exit 0" "$(cat "${tmp_dir}/auth.out" 2>/dev/null)" "Send GITHUB_TOKEN only to the trusted GitHub API host."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  kill "${server_pid}" 2>/dev/null || true
  wait "${server_pid}" 2>/dev/null || true
  python3 - "${tmp_dir}/auth.out" <<'PY'
from pathlib import Path
import json
import sys
payload = json.loads(Path(sys.argv[1]).read_text())
if payload.get("release") != "v0.99.0":
    raise SystemExit(f"expected latest stable release v0.99.0 from override API, got {payload}")
if payload.get("checked_at_utc") != "2026-07-01":
    raise SystemExit(f"expected deterministic checked_at_utc, got {payload}")
PY
  rm -rf "${tmp_dir}"
}

assert_trusted_http_override_does_not_receive_token() {
  local tmp_dir port_file server_pid api_url
  tmp_dir="$(mktemp -d)"
  port_file="${tmp_dir}/port"
  python3 - "${port_file}" <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import sys

port_file = Path(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization"):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'{"message":"authorization header on insecure HTTP"}')
            return
        payload = [{"tag_name": "v0.86.0", "draft": False, "prerelease": False}]
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


server = HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(f"http://127.0.0.1:{server.server_port}/releases\n")
server.serve_forever()
PY
  server_pid="$!"
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    sleep 0.1
  done
  if [[ ! -s "${port_file}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin trusted-http server" "${port_file}" "server writes API URL" "missing" "Keep trusted HTTP token-scope test server start-up reliable."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  api_url="$(cat "${port_file}")"
  if ! BARMAN_PLUGIN_API_URL="${api_url}" BARMAN_PLUGIN_TRUSTED_TOKEN_HOSTS="127.0.0.1" GITHUB_TOKEN="test-token" BARMAN_PLUGIN_CHECKED_AT_UTC="2026-07-05" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh" --json >"${tmp_dir}/trusted-http.out"; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin --json" "trusted HTTP API override does not receive GitHub token" "exit 0" "$(cat "${tmp_dir}/trusted-http.out" 2>/dev/null)" "Send GITHUB_TOKEN only to HTTPS release API URLs."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  kill "${server_pid}" 2>/dev/null || true
  wait "${server_pid}" 2>/dev/null || true
  python3 - "${tmp_dir}/trusted-http.out" <<'PY'
from pathlib import Path
import json
import sys

payload = json.loads(Path(sys.argv[1]).read_text())
if payload.get("release") != "v0.86.0":
    raise SystemExit(f"expected latest stable release v0.86.0 from trusted HTTP override, got {payload}")
PY
  rm -rf "${tmp_dir}"
}

assert_retrying_release_fetch() {
  local tmp_dir port_file count_file server_pid api_url
  tmp_dir="$(mktemp -d)"
  port_file="${tmp_dir}/port"
  count_file="${tmp_dir}/count"
  python3 - "${port_file}" "${count_file}" <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import sys

port_file = Path(sys.argv[1])
count_file = Path(sys.argv[2])
count_file.write_text("0\n")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        count = int(count_file.read_text().strip()) + 1
        count_file.write_text(f"{count}\n")
        if count < 3:
            body = b'{"message":"temporary upstream failure"}'
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        payload = [{"tag_name": "v0.88.0", "draft": False, "prerelease": False}]
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


server = HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(f"http://127.0.0.1:{server.server_port}/releases\n")
server.serve_forever()
PY
  server_pid="$!"
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    sleep 0.1
  done
  if [[ ! -s "${port_file}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin retry server" "${port_file}" "server writes API URL" "missing" "Keep retry test server start-up reliable."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  api_url="$(cat "${port_file}")"
  if ! BARMAN_PLUGIN_API_URL="${api_url}" BARMAN_PLUGIN_CHECKED_AT_UTC="2026-07-02" BARMAN_PLUGIN_RETRY_DELAY_SECONDS=0 "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh" --json >"${tmp_dir}/retry.out"; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin --json" "transient GitHub API failures" "eventual exit 0" "$(cat "${tmp_dir}/retry.out" 2>/dev/null)" "Retry retryable GitHub API failures before failing scheduled metadata updates."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  kill "${server_pid}" 2>/dev/null || true
  wait "${server_pid}" 2>/dev/null || true
  python3 - "${tmp_dir}/retry.out" "${count_file}" <<'PY'
from pathlib import Path
import json
import sys

payload = json.loads(Path(sys.argv[1]).read_text())
count = int(Path(sys.argv[2]).read_text().strip())
if payload.get("release") != "v0.88.0":
    raise SystemExit(f"expected retried latest stable release v0.88.0, got {payload}")
if count != 3:
    raise SystemExit(f"expected exactly 3 HTTP attempts, got {count}")
PY
  rm -rf "${tmp_dir}"
}

assert_invalid_json_release_fetch_retries() {
  local tmp_dir port_file count_file server_pid api_url
  tmp_dir="$(mktemp -d)"
  port_file="${tmp_dir}/port"
  count_file="${tmp_dir}/count"
  python3 - "${port_file}" "${count_file}" <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import sys

port_file = Path(sys.argv[1])
count_file = Path(sys.argv[2])
count_file.write_text("0\n")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        count = int(count_file.read_text().strip()) + 1
        count_file.write_text(f"{count}\n")
        if count == 1:
            body = b"{not-json"
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        payload = [{"tag_name": "v0.87.0", "draft": False, "prerelease": False}]
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


server = HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(f"http://127.0.0.1:{server.server_port}/releases\n")
server.serve_forever()
PY
  server_pid="$!"
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    sleep 0.1
  done
  if [[ ! -s "${port_file}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin invalid-json server" "${port_file}" "server writes API URL" "missing" "Keep invalid JSON retry test server start-up reliable."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  api_url="$(cat "${port_file}")"
  if ! BARMAN_PLUGIN_API_URL="${api_url}" BARMAN_PLUGIN_CHECKED_AT_UTC="2026-07-04" BARMAN_PLUGIN_RETRY_DELAY_SECONDS=0 "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh" --json >"${tmp_dir}/invalid-json.out"; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin --json" "transient invalid JSON API response" "eventual exit 0" "$(cat "${tmp_dir}/invalid-json.out" 2>/dev/null)" "Retry malformed transient API responses before failing scheduled metadata updates."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  kill "${server_pid}" 2>/dev/null || true
  wait "${server_pid}" 2>/dev/null || true
  python3 - "${tmp_dir}/invalid-json.out" "${count_file}" <<'PY'
from pathlib import Path
import json
import sys

payload = json.loads(Path(sys.argv[1]).read_text())
count = int(Path(sys.argv[2]).read_text().strip())
if payload.get("release") != "v0.87.0":
    raise SystemExit(f"expected retried release v0.87.0 after invalid JSON, got {payload}")
if count != 2:
    raise SystemExit(f"expected exactly 2 HTTP attempts, got {count}")
PY
  rm -rf "${tmp_dir}"
}

assert_paged_semver_release_fetch() {
  local tmp_dir port_file server_pid api_url
  tmp_dir="$(mktemp -d)"
  port_file="${tmp_dir}/port"
  python3 - "${port_file}" <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import sys

port_file = Path(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if "page=2" in self.path:
            payload = [
                {"tag_name": "v0.100.0", "draft": False, "prerelease": False},
                {"tag_name": "v0.101.0-rc1", "draft": False, "prerelease": True},
            ]
            body = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        payload = [
            {"tag_name": "v0.99.0", "draft": False, "prerelease": False},
            {"tag_name": "v0.101.0-rc1", "draft": False, "prerelease": True},
        ]
        body = json.dumps(payload).encode("utf-8")
        next_url = f"http://127.0.0.1:{self.server.server_port}/releases?page=2"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Link", f"<{next_url}>; rel=\"next\"")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


server = HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(f"http://127.0.0.1:{server.server_port}/releases\n")
server.serve_forever()
PY
  server_pid="$!"
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    sleep 0.1
  done
  if [[ ! -s "${port_file}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin pagination server" "${port_file}" "server writes API URL" "missing" "Keep pagination test server start-up reliable."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  api_url="$(cat "${port_file}")"
  if ! BARMAN_PLUGIN_API_URL="${api_url}" BARMAN_PLUGIN_CHECKED_AT_UTC="2026-07-03" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh" --json >"${tmp_dir}/paged.out"; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin --json" "paginated GitHub release API" "exit 0" "$(cat "${tmp_dir}/paged.out" 2>/dev/null)" "Scan paginated releases and choose the highest stable semver tag."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  kill "${server_pid}" 2>/dev/null || true
  wait "${server_pid}" 2>/dev/null || true
  python3 - "${tmp_dir}/paged.out" <<'PY'
from pathlib import Path
import json
import sys

payload = json.loads(Path(sys.argv[1]).read_text())
if payload.get("release") != "v0.100.0":
    raise SystemExit(f"expected highest paginated stable release v0.100.0, got {payload}")
PY
  rm -rf "${tmp_dir}"
}

assert_pagination_limit_with_stable_tags_fails() {
  local tmp_dir port_file server_pid api_url status
  tmp_dir="$(mktemp -d)"
  port_file="${tmp_dir}/port"
  python3 - "${port_file}" <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import sys

port_file = Path(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        payload = [{"tag_name": "v0.85.0", "draft": False, "prerelease": False}]
        body = json.dumps(payload).encode("utf-8")
        next_url = f"http://127.0.0.1:{self.server.server_port}/releases?page=2"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Link", f"<{next_url}>; rel=\"next\"")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


server = HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(f"http://127.0.0.1:{server.server_port}/releases\n")
server.serve_forever()
PY
  server_pid="$!"
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    sleep 0.1
  done
  if [[ ! -s "${port_file}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin pagination-limit server" "${port_file}" "server writes API URL" "missing" "Keep pagination limit test server start-up reliable."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  api_url="$(cat "${port_file}")"
  set +e
  BARMAN_PLUGIN_API_URL="${api_url}" BARMAN_PLUGIN_MAX_PAGES=1 BARMAN_PLUGIN_CHECKED_AT_UTC="2026-07-06" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh" --json >"${tmp_dir}/pagination-limit.out" 2>&1
  status="$?"
  set -e
  kill "${server_pid}" 2>/dev/null || true
  wait "${server_pid}" 2>/dev/null || true
  if [[ "${status}" == "0" ]]; then
    diag "barman-plugin --json" "truncated pagination with stable tags fails closed" "non-zero exit" "$(cat "${tmp_dir}/pagination-limit.out" 2>/dev/null)" "Do not choose a Barman release from an incomplete paginated scan."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  if ! grep -q "pagination limit reached before the last page" "${tmp_dir}/pagination-limit.out"; then
    diag "barman-plugin --json" "truncated pagination diagnostic" "mentions pagination limit" "$(tr '\n' ' ' <"${tmp_dir}/pagination-limit.out")" "Keep incomplete-scan diagnostics actionable."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  rm -rf "${tmp_dir}"
}

base_tmp="$(mktemp -d)"
upstream="${base_tmp}/upstream"
prepare_upstream "${upstream}"
current_reference="${base_tmp}/current-reference.json"
changed_reference="${base_tmp}/changed-reference.json"
write_barman_fixture_from_metadata "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${current_reference}" false
write_barman_fixture_from_metadata "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${changed_reference}" true

current_project="${base_tmp}/current"
prepare_project "${current_project}"
if ! run_update "${current_project}" "${upstream}" "${current_reference}" "${base_tmp}/current.out" "${base_tmp}/current.err"; then
  diag "make update" "current-reference" "exit 0" "$(cat "${base_tmp}/current.err")" "Current Barman reference should be a deterministic no-op."
  exit 1
fi
assert_barman_json "${base_tmp}/current.out" false
status="$(cd "${current_project}" && git status --porcelain --untracked-files=all)"
[[ -z "${status}" ]] || { diag "git status" "current-reference" "clean no-op" "${status}" "Current Barman reference must not rewrite metadata or docs."; exit 1; }

changed_project="${base_tmp}/changed"
prepare_project "${changed_project}"
if ! run_update "${changed_project}" "${upstream}" "${changed_reference}" "${base_tmp}/changed.out" "${base_tmp}/changed.err"; then
  diag "make update" "changed-reference" "exit 0" "$(cat "${base_tmp}/changed.err")" "Changed Barman reference should update metadata and generated docs deterministically."
  exit 1
fi
assert_barman_json "${base_tmp}/changed.out" true
status="$(cd "${changed_project}" && git status --porcelain --untracked-files=all)"
expected_status=$' M cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md\n M cloudnative-pg-timescaledb/versions.yaml'
[[ "${status}" == "${expected_status}" ]] || { diag "git status" "changed-reference" "only versions.yaml and generated Barman doc change" "${status}" "Keep Barman updates deterministic and reviewable."; exit 1; }
grep -Fq 'CloudNativePG Barman Cloud Plugin' "${changed_project}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" || { diag "grep" "barman-plugin-reference.md" "required plugin phrase" "missing" "Generated docs must use the plugin path wording."; exit 1; }
expected_plugin_image="$(python3 - "${changed_reference}" <<'PY'
from pathlib import Path
import json
import sys
print(json.loads(Path(sys.argv[1]).read_text())["plugin_image"])
PY
)"
grep -Fq "${expected_plugin_image}" "${changed_project}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" || { diag "grep" "barman-plugin-reference.md" "new plugin image ${expected_plugin_image}" "missing" "Generated docs must include the new plugin image."; exit 1; }

"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile" "barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile-continuation" "barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile-copy" "plugin-barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-docs.md" "CloudNativePG Barman Cloud Plugin"
assert_non_github_override_does_not_receive_token
assert_trusted_http_override_does_not_receive_token
assert_retrying_release_fetch
assert_invalid_json_release_fetch_retries
assert_paged_semver_release_fetch
assert_pagination_limit_with_stable_tags_fails

rm -rf "${base_tmp}"
printf 'PASS story-2.7 Barman plugin reference fixtures\n'
