#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALLOWLIST_FILE="${AUTOCOMMIT_ALLOWLIST:-${ROOT_DIR}/cloudnative-pg-timescaledb/config/autocommit-allowlist.txt}"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

if [[ ! -f "${ALLOWLIST_FILE}" ]]; then
  diag "autocommit-stage" "${ALLOWLIST_FILE}" "autocommit allowlist exists" "missing" "Create cloudnative-pg-timescaledb/config/autocommit-allowlist.txt."
  exit 1
fi

pathspecs=()
while IFS= read -r raw || [[ -n "${raw}" ]]; do
  line="${raw%%#*}"
  line="${line#${line%%[![:space:]]*}}"
  line="${line%${line##*[![:space:]]}}"
  [[ -z "${line}" ]] && continue
  pathspecs+=(":(glob)${line}")
done <"${ALLOWLIST_FILE}"

if ((${#pathspecs[@]} == 0)); then
  diag "autocommit-stage" "${ALLOWLIST_FILE}" "at least one allowlisted path" "empty" "Add explicit resolver-owned metadata/generated paths."
  exit 1
fi

git -C "${ROOT_DIR}" add -- "${pathspecs[@]}"
printf 'PASS autocommit-stage allowlisted paths=%s\n' "${#pathspecs[@]}"
