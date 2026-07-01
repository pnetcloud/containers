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

assert_authenticated_release_fetch() {
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
        if self.headers.get("Authorization") != "Bearer test-token":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'{"message":"rate limit exceeded"}')
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
    diag "barman-plugin auth server" "${port_file}" "server writes API URL" "missing" "Keep authenticated resolver test server start-up reliable."
    rm -rf "${tmp_dir}"
    exit 1
  fi
  api_url="$(cat "${port_file}")"
  if ! BARMAN_PLUGIN_API_URL="${api_url}" GITHUB_TOKEN="test-token" BARMAN_PLUGIN_CHECKED_AT_UTC="2026-07-01" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/barman-plugin.sh" --json >"${tmp_dir}/auth.out"; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    diag "barman-plugin --json" "authenticated GitHub API request" "exit 0" "$(cat "${tmp_dir}/auth.out" 2>/dev/null)" "Use GITHUB_TOKEN/GH_TOKEN for release API requests to avoid anonymous rate limits."
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
    raise SystemExit(f"expected authenticated latest stable release v0.99.0, got {payload}")
if payload.get("checked_at_utc") != "2026-07-01":
    raise SystemExit(f"expected deterministic checked_at_utc, got {payload}")
PY
  rm -rf "${tmp_dir}"
}

base_tmp="$(mktemp -d)"
upstream="${base_tmp}/upstream"
prepare_upstream "${upstream}"

current_project="${base_tmp}/current"
prepare_project "${current_project}"
if ! run_update "${current_project}" "${upstream}" "${FIXTURE_DIR}/current-reference.json" "${base_tmp}/current.out" "${base_tmp}/current.err"; then
  diag "make update" "current-reference" "exit 0" "$(cat "${base_tmp}/current.err")" "Current Barman reference should be a deterministic no-op."
  exit 1
fi
assert_barman_json "${base_tmp}/current.out" false
status="$(cd "${current_project}" && git status --porcelain --untracked-files=all)"
[[ -z "${status}" ]] || { diag "git status" "current-reference" "clean no-op" "${status}" "Current Barman reference must not rewrite metadata or docs."; exit 1; }

changed_project="${base_tmp}/changed"
prepare_project "${changed_project}"
if ! run_update "${changed_project}" "${upstream}" "${FIXTURE_DIR}/changed-reference.json" "${base_tmp}/changed.out" "${base_tmp}/changed.err"; then
  diag "make update" "changed-reference" "exit 0" "$(cat "${base_tmp}/changed.err")" "Changed Barman reference should update metadata and generated docs deterministically."
  exit 1
fi
assert_barman_json "${base_tmp}/changed.out" true
status="$(cd "${changed_project}" && git status --porcelain --untracked-files=all)"
expected_status=$' M cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md\n M cloudnative-pg-timescaledb/versions.yaml'
[[ "${status}" == "${expected_status}" ]] || { diag "git status" "changed-reference" "only versions.yaml and generated Barman doc change" "${status}" "Keep Barman updates deterministic and reviewable."; exit 1; }
grep -Fq 'CloudNativePG Barman Cloud Plugin' "${changed_project}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" || { diag "grep" "barman-plugin-reference.md" "required plugin phrase" "missing" "Generated docs must use the plugin path wording."; exit 1; }
grep -Fq 'ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.14.0' "${changed_project}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" || { diag "grep" "barman-plugin-reference.md" "new plugin image" "missing" "Generated docs must include the new plugin image."; exit 1; }

"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile" "barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile-continuation" "barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile-copy" "plugin-barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-docs.md" "CloudNativePG Barman Cloud Plugin"
assert_authenticated_release_fetch

rm -rf "${base_tmp}"
printf 'PASS story-2.7 Barman plugin reference fixtures\n'
