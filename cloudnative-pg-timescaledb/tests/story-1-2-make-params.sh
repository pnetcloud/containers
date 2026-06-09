#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

run_expect_exit() {
  local expected="$1"
  local description="$2"
  shift 2
  local tmp status
  tmp="$(mktemp)"
  set +e
  "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" != "${expected}" ]]; then
    diag "${*}" "${description}" "exit ${expected}" "exit ${status}: $(tr '\n' ' ' <"${tmp}")" "Return the documented controlled exit code."
    rm -f "${tmp}"
    exit 1
  fi
  if [[ "${expected}" == "69" ]] && ! grep -Eq 'Story|Stories|owned by' "${tmp}"; then
    diag "${*}" "${description}" "owner story named" "$(cat "${tmp}")" "Name the owning story for later target behavior."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

run_make_error() {
  local recipe_code="$1"
  local description="$2"
  shift 2
  local tmp status
  tmp="$(mktemp)"
  set +e
  make -C "${ROOT_DIR}" "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" != "2" ]] || ! grep -Fq "Error ${recipe_code}" "${tmp}"; then
    diag "make -C ${ROOT_DIR} ${*}" "${description}" "make exits 2 with recipe Error ${recipe_code}" "exit ${status}: $(tr '\n' ' ' <"${tmp}")" "Keep root Make target delegated and controlled."
    rm -f "${tmp}"
    exit 1
  fi
  if [[ "${recipe_code}" == "69" ]] && ! grep -Eq 'Story|Stories|owned by' "${tmp}"; then
    diag "make -C ${ROOT_DIR} ${*}" "${description}" "owner story named" "$(cat "${tmp}")" "Name the owning story for later target behavior."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

run_expect_exit 69 "update delegated script" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/update.sh"
run_expect_exit 69 "matrix delegated script" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/matrix.sh"
run_expect_exit 69 "bake-print delegated script" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/bake-print.sh"
run_expect_exit 69 "catalog delegated script" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/catalog.sh"

run_make_error 69 "update Make target" update
run_make_error 69 "matrix Make target" matrix
run_make_error 69 "bake-print Make target" bake-print
run_make_error 69 "catalog Make target" catalog

for target in build smoke; do
  script="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/${target}.sh"
  run_expect_exit 64 "${target} script missing parameters" "${script}"
  run_expect_exit 65 "${target} script unsupported PostgreSQL" "${script}" 16 trixie
  run_expect_exit 65 "${target} script unsupported Alpine" "${script}" 18 alpine
  run_expect_exit 65 "${target} script unsupported bullseye" "${script}" 18 bullseye
  run_expect_exit 69 "${target} script valid controlled unavailable" "${script}" 18 trixie
  run_expect_exit 69 "${target} script experimental controlled unavailable" "${script}" 19beta1 bookworm

  run_make_error 64 "${target} Make target missing parameters" "${target}"
  run_make_error 65 "${target} Make target unsupported PostgreSQL" "${target}" PG=16 DEBIAN=trixie
  run_make_error 65 "${target} Make target unsupported Alpine" "${target}" PG=18 DEBIAN=alpine
  run_make_error 65 "${target} Make target unsupported bullseye" "${target}" PG=18 DEBIAN=bullseye
  run_make_error 69 "${target} Make target valid controlled unavailable" "${target}" PG=18 DEBIAN=trixie
  run_make_error 69 "${target} Make target experimental controlled unavailable" "${target}" PG=19beta1 DEBIAN=bookworm
done

run_expect_exit 2 "unrecognized target" make -C "${ROOT_DIR}" does-not-exist

printf 'PASS story-1.2 make params\n'
