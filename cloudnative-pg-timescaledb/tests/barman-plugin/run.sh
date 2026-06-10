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
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts" "${target}/cloudnative-pg-timescaledb/scripts"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/templates" "${target}/cloudnative-pg-timescaledb/templates"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/generated" "${target}/cloudnative-pg-timescaledb/generated"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/catalog" "${target}/cloudnative-pg-timescaledb/catalog"
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
  set +e
  (cd "${project}" && BARMAN_PLUGIN_FIXTURE="${fixture}" make --no-print-directory update UPDATE_ARGS="--fixtures ${upstream} --json") >"${stdout_file}" 2>"${stderr_file}"
  local status="$?"
  set -e
  return "${status}"
}

assert_barman_json() {
  local file="$1"
  local expected_changed="$2"
  local expected_old="$3"
  local expected_new="$4"
  python3 - "${file}" "${expected_changed}" "${expected_old}" "${expected_new}" <<'PY'
from pathlib import Path
import json
import sys
payload = json.loads(Path(sys.argv[1]).read_text())
expected_changed = sys.argv[2] == "true"
expected_old = sys.argv[3]
expected_new = sys.argv[4]
plugin = payload.get("barman_plugin", {})
required = {"old_reference", "new_reference", "changed", "noop", "manifest_url", "plugin_image", "sidecar_image", "backup_tooling_free", "changed_fields"}
if not required.issubset(plugin):
    raise SystemExit(f"missing barman summary fields: {plugin}")
if plugin["old_reference"] != expected_old or plugin["new_reference"] != expected_new:
    raise SystemExit(f"wrong old/new reference: {plugin}")
if plugin["changed"] is not expected_changed or plugin["noop"] is not (not expected_changed):
    raise SystemExit(f"wrong changed/noop: {plugin}")
if plugin["backup_tooling_free"] is not True:
    raise SystemExit(f"expected backup_tooling_free true: {plugin}")
if payload.get("changed") is not expected_changed:
    raise SystemExit(f"top-level changed should reflect Barman update: {payload}")
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

base_tmp="$(mktemp -d)"
upstream="${base_tmp}/upstream"
prepare_upstream "${upstream}"

current_project="${base_tmp}/current"
prepare_project "${current_project}"
if ! run_update "${current_project}" "${upstream}" "${FIXTURE_DIR}/current-reference.json" "${base_tmp}/current.out" "${base_tmp}/current.err"; then
  diag "make update" "current-reference" "exit 0" "$(cat "${base_tmp}/current.err")" "Current Barman reference should be a deterministic no-op."
  exit 1
fi
assert_barman_json "${base_tmp}/current.out" false "v0.12.0" "v0.12.0"
status="$(cd "${current_project}" && git status --porcelain --untracked-files=all)"
[[ -z "${status}" ]] || { diag "git status" "current-reference" "clean no-op" "${status}" "Current Barman reference must not rewrite metadata or docs."; exit 1; }

changed_project="${base_tmp}/changed"
prepare_project "${changed_project}"
if ! run_update "${changed_project}" "${upstream}" "${FIXTURE_DIR}/changed-reference.json" "${base_tmp}/changed.out" "${base_tmp}/changed.err"; then
  diag "make update" "changed-reference" "exit 0" "$(cat "${base_tmp}/changed.err")" "Changed Barman reference should update metadata and generated docs deterministically."
  exit 1
fi
assert_barman_json "${base_tmp}/changed.out" true "v0.12.0" "v0.13.0"
status="$(cd "${changed_project}" && git status --porcelain --untracked-files=all)"
expected_status=$' M cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md\n M cloudnative-pg-timescaledb/versions.yaml'
[[ "${status}" == "${expected_status}" ]] || { diag "git status" "changed-reference" "only versions.yaml and generated Barman doc change" "${status}" "Keep Barman updates deterministic and reviewable."; exit 1; }
grep -Fq 'CloudNativePG Barman Cloud Plugin' "${changed_project}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" || { diag "grep" "barman-plugin-reference.md" "required plugin phrase" "missing" "Generated docs must use the plugin path wording."; exit 1; }
grep -Fq 'ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.13.0' "${changed_project}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" || { diag "grep" "barman-plugin-reference.md" "new plugin image" "missing" "Generated docs must include the new plugin image."; exit 1; }

"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile" "barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile-continuation" "barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-dockerfile-copy" "plugin-barman-cloud"
expect_boundary_fail "${FIXTURE_DIR}/legacy-barman-cloud-docs.md" "CloudNativePG Barman Cloud Plugin"

rm -rf "${base_tmp}"
printf 'PASS story-2.7 Barman plugin reference fixtures\n'
