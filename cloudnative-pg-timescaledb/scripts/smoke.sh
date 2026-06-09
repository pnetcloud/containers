#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"
pg="${1:-}"
debian="${2:-}"
require_pg_debian "make smoke" "${pg}" "${debian}"
checks="${CHECKS:-container}"
case "${checks}" in
  container)
    "${SCRIPT_DIR}/smoke-test.sh" "${pg}" "${debian}"
    ;;
  sql)
    controlled_unavailable "make smoke PG=${pg} DEBIAN=${debian} CHECKS=sql" "Story 3.5" "Implement SQL extension smoke checks before using CHECKS=sql."
    ;;
  *)
    diag "make smoke PG=${pg} DEBIAN=${debian}" "CHECKS" "one of container, sql" "${checks}" "Use CHECKS=container for Story 3.4 or CHECKS=sql after Story 3.5."
    exit "${EXIT_USAGE}"
    ;;
esac
