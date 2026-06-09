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

run_expect_exit 69 "matrix delegated script" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/matrix.sh"
run_expect_exit 69 "catalog delegated script" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/catalog.sh"

run_make_error 69 "matrix Make target" matrix
run_make_error 69 "catalog Make target" catalog

build_script="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/build.sh"
run_expect_exit 64 "build script missing parameters" "${build_script}"
run_expect_exit 65 "build script unsupported PostgreSQL" "${build_script}" 16 trixie
run_expect_exit 65 "build script unsupported Alpine" "${build_script}" 18 alpine
run_expect_exit 65 "build script unsupported bullseye" "${build_script}" 18 bullseye
run_expect_exit 65 "build script valid skipped until publishable" "${build_script}" 18 trixie
run_expect_exit 65 "build script experimental skipped until publishable" "${build_script}" 19beta1 bookworm

run_make_error 64 "build Make target missing parameters" build
run_make_error 65 "build Make target unsupported PostgreSQL" build PG=16 DEBIAN=trixie
run_make_error 65 "build Make target unsupported Alpine" build PG=18 DEBIAN=alpine
run_make_error 65 "build Make target unsupported bullseye" build PG=18 DEBIAN=bullseye
run_make_error 65 "build Make target valid skipped until publishable" build PG=18 DEBIAN=trixie
run_make_error 65 "build Make target experimental skipped until publishable" build PG=19beta1 DEBIAN=bookworm

for target in smoke; do
  script="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/${target}.sh"
  run_expect_exit 64 "${target} script missing parameters" "${script}"
  run_expect_exit 65 "${target} script unsupported PostgreSQL" "${script}" 16 trixie
  run_expect_exit 65 "${target} script unsupported Alpine" "${script}" 18 alpine
  run_expect_exit 65 "${target} script unsupported bullseye" "${script}" 18 bullseye
  run_expect_exit 65 "${target} script valid skipped until publishable" "${script}" 18 trixie
  run_expect_exit 65 "${target} script experimental skipped until publishable" "${script}" 19beta1 bookworm
  run_expect_exit 69 "${target} script SQL controlled unavailable" env CHECKS=sql "${script}" 18 trixie

  run_make_error 64 "${target} Make target missing parameters" "${target}"
  run_make_error 65 "${target} Make target unsupported PostgreSQL" "${target}" PG=16 DEBIAN=trixie
  run_make_error 65 "${target} Make target unsupported Alpine" "${target}" PG=18 DEBIAN=alpine
  run_make_error 65 "${target} Make target unsupported bullseye" "${target}" PG=18 DEBIAN=bullseye
  run_make_error 65 "${target} Make target valid skipped until publishable" "${target}" PG=18 DEBIAN=trixie CHECKS=container
  run_make_error 65 "${target} Make target experimental skipped until publishable" "${target}" PG=19beta1 DEBIAN=bookworm CHECKS=container
  run_make_error 69 "${target} Make target SQL controlled unavailable" "${target}" PG=18 DEBIAN=trixie CHECKS=sql
done

run_expect_exit 2 "unrecognized target" make -C "${ROOT_DIR}" does-not-exist

printf 'PASS story-1.2 make params\n'
