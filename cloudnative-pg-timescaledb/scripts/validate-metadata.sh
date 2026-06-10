#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/common.sh"
source "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/metadata.sh"

if [[ "$#" -gt 1 ]]; then
  diag "validate-metadata arguments" "cloudnative-pg-timescaledb/scripts/validate-metadata.sh" "zero or one metadata file path" "$*" "Pass a single metadata file path, or omit it to validate versions.yaml."
  exit 64
fi
if [[ "$#" -eq 1 && -z "$1" ]]; then
  diag "validate-metadata arguments" "cloudnative-pg-timescaledb/scripts/validate-metadata.sh" "metadata file path is non-empty" "empty" "Pass a non-empty metadata file path, or omit the argument to validate versions.yaml."
  exit 64
fi

metadata_file="${1:-${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml}"
metadata_validate_file "${metadata_file}"
printf 'PASS validate-metadata %s\n' "${metadata_file}"
