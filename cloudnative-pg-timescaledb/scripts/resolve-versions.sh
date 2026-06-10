#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case " ${*} " in
  " update "*|*" update "*)
    python3 "${SCRIPT_DIR}/lib/update_contract.py" "$@"
    ;;
  *" --check-packages "*)
    # shellcheck source=cloudnative-pg-timescaledb/scripts/lib/packagecloud.sh
    source "${SCRIPT_DIR}/lib/packagecloud.sh"
    packagecloud_resolve_versions "$@"
    ;;
  *)
    # shellcheck source=cloudnative-pg-timescaledb/scripts/lib/cnpg.sh
    source "${SCRIPT_DIR}/lib/cnpg.sh"
    cnpg_resolve_versions "$@"
    ;;
esac
