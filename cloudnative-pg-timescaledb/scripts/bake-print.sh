#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cloudnative-pg-timescaledb/scripts/lib/command.sh
source "${SCRIPT_DIR}/lib/command.sh"

metadata="${BAKE_METADATA:-${SCRIPT_DIR}/../versions.yaml}"
bake_file="${BAKE_FILE:-${SCRIPT_DIR}/../docker-bake.hcl}"
docker_bin="${DOCKER_BIN:-docker}"

"${SCRIPT_DIR}/generate-bake.sh" --metadata "${metadata}" --output "${bake_file}" --check >/dev/null

set +e
"${docker_bin}" buildx bake --file "${bake_file}" --print "$@"
status="$?"
set -e
if [[ "${status}" != "0" ]]; then
  diag "make bake-print" "${bake_file}" "docker buildx bake --print succeeds for generated local Bake file" "exit ${status}" "Install Docker Buildx or regenerate Bake output from metadata before printing the plan."
  exit "${status}"
fi
