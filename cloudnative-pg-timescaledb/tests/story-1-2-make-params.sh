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

run_expect_json() {
  local expected_key="$1"
  local description="$2"
  shift 2
  local tmp status
  tmp="$(mktemp)"
  set +e
  "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" != "0" ]] || ! python3 -m json.tool "${tmp}" >/dev/null 2>&1; then
    diag "${*}" "${description}" "exit 0 with valid JSON" "exit ${status}: $(tr '\n' ' ' <"${tmp}")" "Implemented JSON-producing targets should stay delegated and machine-readable."
    rm -f "${tmp}"
    exit 1
  fi
  if [[ "${expected_key}" == "matrix" ]] && (! grep -Fq '"include"' "${tmp}" || ! grep -Fq '"skipped"' "${tmp}"); then
    diag "${*}" "${description}" "matrix JSON contains include and skipped" "$(cat "${tmp}")" "Preserve the Story 4.1 matrix contract."
    rm -f "${tmp}"
    exit 1
  fi
  if [[ "${expected_key}" == "catalog" ]] && ! grep -Fq '"catalogs"' "${tmp}"; then
    diag "${*}" "${description}" "catalog JSON contains catalogs" "$(cat "${tmp}")" "Preserve the Story 4.6 catalog contract."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

run_expect_json matrix "matrix delegated script" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/matrix.sh"
run_expect_json catalog "catalog delegated script" "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/catalog.sh" --json

run_expect_json matrix "matrix Make target" make --no-print-directory -C "${ROOT_DIR}" matrix
run_expect_json catalog "catalog Make target" make --no-print-directory -C "${ROOT_DIR}" catalog CATALOG_ARGS=--json

build_script="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/build.sh"
run_expect_exit 64 "build script missing parameters" "${build_script}"
run_expect_exit 65 "build script unsupported PostgreSQL" "${build_script}" 16 trixie
run_expect_exit 65 "build script unsupported Alpine" "${build_script}" 18 alpine
run_expect_exit 65 "build script unsupported bullseye" "${build_script}" 18 bullseye
run_expect_exit 65 "build script experimental skipped until publishable" "${build_script}" 19beta1 bookworm

tmpdir="$(mktemp -d)"
fake_docker="${tmpdir}/docker"
cat >"${fake_docker}" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$*" == buildx\ bake* ]]; then
  exit 0
fi
printf 'unexpected docker args: %s\n' "$*" >&2
exit 2
SH
chmod +x "${fake_docker}"
run_expect_exit 0 "build script stable production row is publishable" env DOCKER_BIN="${fake_docker}" "${build_script}" 18 trixie

run_make_error 64 "build Make target missing parameters" build
run_make_error 65 "build Make target unsupported PostgreSQL" build PG=16 DEBIAN=trixie
run_make_error 65 "build Make target unsupported Alpine" build PG=18 DEBIAN=alpine
run_make_error 65 "build Make target unsupported bullseye" build PG=18 DEBIAN=bullseye
run_expect_exit 0 "build Make target stable production row is publishable" env DOCKER_BIN="${fake_docker}" make --no-print-directory -C "${ROOT_DIR}" build PG=18 DEBIAN=trixie
run_make_error 65 "build Make target experimental skipped until publishable" build PG=19beta1 DEBIAN=bookworm

for target in smoke; do
  script="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/${target}.sh"
  run_expect_exit 64 "${target} script missing parameters" "${script}"
  run_expect_exit 65 "${target} script unsupported PostgreSQL" "${script}" 16 trixie
  run_expect_exit 65 "${target} script unsupported Alpine" "${script}" 18 alpine
  run_expect_exit 65 "${target} script unsupported bullseye" "${script}" 18 bullseye
  run_expect_exit 65 "${target} script experimental skipped until publishable" "${script}" 19beta1 bookworm
  run_expect_exit 0 "${target} script stable production container smoke is publishable" env SMOKE_METADATA="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/fixtures/metadata/valid-publishable-targets.yaml" SMOKE_CONTAINER_FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/container/fixtures/valid-container.json" "${script}" 18 trixie
  run_expect_exit 0 "${target} script stable production SQL smoke is publishable" env SMOKE_METADATA="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/fixtures/metadata/valid-publishable-targets.yaml" CHECKS=sql SMOKE_SQL_FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/valid-sql-smoke.sql" "${script}" 18 trixie

  run_make_error 64 "${target} Make target missing parameters" "${target}"
  run_make_error 65 "${target} Make target unsupported PostgreSQL" "${target}" PG=16 DEBIAN=trixie
  run_make_error 65 "${target} Make target unsupported Alpine" "${target}" PG=18 DEBIAN=alpine
  run_make_error 65 "${target} Make target unsupported bullseye" "${target}" PG=18 DEBIAN=bullseye
  run_make_error 65 "${target} Make target experimental skipped until publishable" "${target}" PG=19beta1 DEBIAN=bookworm CHECKS=container
  run_expect_exit 0 "${target} Make target stable production container smoke is publishable" env SMOKE_METADATA="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/fixtures/metadata/valid-publishable-targets.yaml" SMOKE_CONTAINER_FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/container/fixtures/valid-container.json" make --no-print-directory -C "${ROOT_DIR}" "${target}" PG=18 DEBIAN=trixie CHECKS=container
  run_expect_exit 0 "${target} Make target stable production SQL smoke is publishable" env SMOKE_METADATA="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/fixtures/metadata/valid-publishable-targets.yaml" SMOKE_SQL_FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/valid-sql-smoke.sql" make --no-print-directory -C "${ROOT_DIR}" "${target}" PG=18 DEBIAN=trixie CHECKS=sql
done

rm -rf "${tmpdir}"

run_expect_exit 2 "unrecognized target" make -C "${ROOT_DIR}" does-not-exist

printf 'PASS story-1.2 make params\n'
