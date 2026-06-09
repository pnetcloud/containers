#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"
pg="${1:-}"
debian="${2:-}"
require_pg_debian "make smoke" "${pg}" "${debian}"
controlled_unavailable "make smoke PG=${pg} DEBIAN=${debian}" "Stories 3.4-3.5" "Implement runtime and SQL smoke checks before using this target."
