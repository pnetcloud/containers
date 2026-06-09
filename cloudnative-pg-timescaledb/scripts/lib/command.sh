#!/usr/bin/env bash
set -Eeuo pipefail

EXIT_USAGE=64
EXIT_UNSUPPORTED=65
EXIT_UNAVAILABLE=69

diag() {
  local command="$1"
  local artifact="$2"
  local expected="$3"
  local actual="$4"
  local remediation="$5"
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' \
    "$command" "$artifact" "$expected" "$actual" "$remediation" >&2
}

controlled_unavailable() {
  local command="$1"
  local owner="$2"
  local remediation="$3"
  diag "$command" "cloudnative-pg-timescaledb/scripts" "implemented behavior owned by ${owner}" "not implemented in Story 1.2" "$remediation"
  exit "${EXIT_UNAVAILABLE}"
}

require_pg_debian() {
  local command="$1"
  local pg="$2"
  local debian="$3"
  if [[ -z "${pg}" || -z "${debian}" ]]; then
    diag "$command" "Makefile parameters" "PG and DEBIAN are provided" "PG='${pg}' DEBIAN='${debian}'" "Run ${command} PG=<17|18|19beta1> DEBIAN=<trixie|bookworm>."
    exit "${EXIT_USAGE}"
  fi
  case "${pg}" in
    17|18|19beta1) ;;
    *)
      diag "$command" "PG" "one of 17, 18, 19beta1" "${pg}" "Use a supported PostgreSQL major from versions.yaml."
      exit "${EXIT_UNSUPPORTED}"
      ;;
  esac
  case "${debian}" in
    trixie|bookworm) ;;
    *)
      diag "$command" "DEBIAN" "one of trixie, bookworm" "${debian}" "Use a supported Debian variant from versions.yaml."
      exit "${EXIT_UNSUPPORTED}"
      ;;
  esac
}
