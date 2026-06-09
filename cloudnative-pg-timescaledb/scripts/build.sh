#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"
pg="${1:-}"
debian="${2:-}"
require_pg_debian "make build" "${pg}" "${debian}"
controlled_unavailable "make build PG=${pg} DEBIAN=${debian}" "Story 3.3" "Implement local build execution before using this target."
