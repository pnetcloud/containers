#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case " ${*} " in
  *" --check-packages "*)
    source "${SCRIPT_DIR}/lib/packagecloud.sh"
    packagecloud_resolve_versions "$@"
    ;;
  *)
    source "${SCRIPT_DIR}/lib/cnpg.sh"
    cnpg_resolve_versions "$@"
    ;;
esac
