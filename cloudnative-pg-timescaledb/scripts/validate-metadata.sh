#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/common.sh"
source "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/metadata.sh"

metadata_file="${1:-${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml}"
metadata_validate_file "${metadata_file}"
printf 'PASS validate-metadata %s\n' "${metadata_file}"
