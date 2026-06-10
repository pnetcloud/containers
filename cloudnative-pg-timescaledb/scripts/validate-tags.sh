#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/common.sh"
source "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/tags.sh"

metadata_file=""
release_date=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --metadata)
      if [[ "$#" -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        diag "validate-tags" "arguments" "--metadata <path>" "${2:-missing}" "Pass a non-empty metadata file path after --metadata."
        exit 64
      fi
      metadata_file="${2:-}"
      shift 2
      ;;
    --date)
      if [[ "$#" -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        diag "validate-tags" "arguments" "--date <YYYYMMDD>" "${2:-missing}" "Pass a non-empty UTC release date after --date."
        exit 64
      fi
      release_date="${2:-}"
      shift 2
      ;;
    *)
      diag "validate-tags" "arguments" "--metadata <path> --date <YYYYMMDD>" "$1" "Use explicit metadata and UTC release date arguments."
      exit 64
      ;;
  esac
done

if [[ -z "${metadata_file}" || -z "${release_date}" ]]; then
  diag "validate-tags" "arguments" "--metadata <path> --date <YYYYMMDD>" "metadata='${metadata_file}' date='${release_date}'" "Pass both required arguments."
  exit 64
fi

tags_validate_file "${metadata_file}" "${release_date}"
printf 'PASS validate-tags %s %s\n' "${metadata_file}" "${release_date}"
