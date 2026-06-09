#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"
pg="${1:-}"
debian="${2:-}"
require_pg_debian "make build" "${pg}" "${debian}"
if (( $# > 2 )); then
  diag "make build PG=${pg} DEBIAN=${debian}" "BUILD_ARGS" "no extra Docker Bake passthrough args in Epic 3 local builds" "${*:3}" "Use PLATFORM=<linux/amd64|linux/arm64> for the local platform override; publish and output overrides belong to Epic 4 release workflows."
  exit "${EXIT_USAGE}"
fi

metadata="${BAKE_METADATA:-${SCRIPT_DIR}/../versions.yaml}"
bake_file="${BAKE_FILE:-${SCRIPT_DIR}/../docker-bake.hcl}"
docker_bin="${DOCKER_BIN:-docker}"
platform="${PLATFORM:-linux/amd64}"
target="pg${pg}-${debian}"
context="."

"${SCRIPT_DIR}/generate-bake.sh" --metadata "${metadata}" --output "${bake_file}" --check >/dev/null

selection_json="$(${SCRIPT_DIR}/generate-bake.sh --metadata "${metadata}" --output "${bake_file}" --json)"
selection="$(${PYTHON:-python3} - "${selection_json}" "${target}" "${platform}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
target_name = sys.argv[2]
platform = sys.argv[3]
for row in payload.get("targets", []):
    if row["name"] == target_name:
        if platform not in row["platforms"]:
            print(json.dumps({"status": "platform-missing", "row": row, "platform": platform}, sort_keys=True))
        else:
            print(json.dumps({"status": "buildable", "row": row}, sort_keys=True))
        raise SystemExit(0)
for row in payload.get("skipped", []):
    if row["name"] == target_name:
        print(json.dumps({"status": "skipped", "row": row}, sort_keys=True))
        raise SystemExit(0)
print(json.dumps({"status": "missing", "row": {}}, sort_keys=True))
PY
)"

status="$(${PYTHON:-python3} - "${selection}" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["status"])
PY
)"

dockerfile="$(${PYTHON:-python3} - "${selection}" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("row", {}).get("dockerfile", ""))
PY
)"

case "${status}" in
  buildable)
    ;;
  skipped)
    skip_reason="$(${PYTHON:-python3} - "${selection}" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["row"].get("skip_reason", ""))
PY
)"
    diag "make build PG=${pg} DEBIAN=${debian}" "${metadata}" "publishable Bake target ${target}" "skipped: ${skip_reason}; target=${target}; dockerfile=${dockerfile}; context=${context}; platform=${platform}; PG=${pg}; DEBIAN=${debian}" "Resolve and mark the combination publishable before local image builds, or choose a publishable PG/DEBIAN row."
    exit "${EXIT_UNSUPPORTED}"
    ;;
  platform-missing)
    diag "make build PG=${pg} DEBIAN=${debian}" "${metadata}" "${target} supports platform ${platform}" "target=${target}; dockerfile=${dockerfile}; context=${context}; platform=${platform}; PG=${pg}; DEBIAN=${debian}" "Use one of the platforms declared in versions.yaml for this image combination."
    exit "${EXIT_UNSUPPORTED}"
    ;;
  *)
    diag "make build PG=${pg} DEBIAN=${debian}" "${metadata}" "metadata contains target ${target}" "missing; context=${context}; platform=${platform}; PG=${pg}; DEBIAN=${debian}" "Regenerate Bake output from versions.yaml or choose a supported PG/DEBIAN row."
    exit "${EXIT_UNSUPPORTED}"
    ;;
esac

if [[ ! -f "${SCRIPT_DIR}/../../${dockerfile}" && ! -f "${dockerfile}" ]]; then
  diag "make build PG=${pg} DEBIAN=${debian}" "${dockerfile}" "generated Dockerfile exists for ${target}" "missing; target=${target}; context=${context}; platform=${platform}; PG=${pg}; DEBIAN=${debian}" "Run make generate and ensure the selected metadata row is publishable."
  exit "${EXIT_UNAVAILABLE}"
fi

printf 'local build: PG=%s DEBIAN=%s target=%s dockerfile=%s context=%s platform=%s bake_file=%s\n' "${pg}" "${debian}" "${target}" "${dockerfile}" "${context}" "${platform}" "${bake_file}" >&2

set +e
"${docker_bin}" buildx bake --file "${bake_file}" "${target}" \
  --set "${target}.platform=${platform}" \
  --set "${target}.output=type=docker"
build_status="$?"
set -e
if [[ "${build_status}" != "0" ]]; then
  diag "make build PG=${pg} DEBIAN=${debian}" "${dockerfile}" "docker buildx bake succeeds locally without push" "exit ${build_status}; target=${target}; context=${context}; platform=${platform}; PG=${pg}; DEBIAN=${debian}" "Inspect the selected generated Dockerfile and rerun the exact local build target."
  exit "${build_status}"
fi
