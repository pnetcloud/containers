#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/sql/fixtures"
METADATA_FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/fixtures/metadata/valid-publishable-targets.yaml"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

expect_fail() {
  local description="$1"
  local pattern="$2"
  shift 2
  local tmp status
  tmp="$(mktemp)"
  set +e
  "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "${*}" "${description}" "command fails" "passed" "Make invalid SQL smoke fixtures fail deterministically."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Include image, PG, DEBIAN, check, expected value, actual value, and remediation."
    rm -f "${tmp}"
    exit 1
  fi
  for required in 'image:' 'PG: 18' 'DEBIAN: trixie' 'check:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "${*}" "${description}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Keep SQL smoke diagnostics actionable for release gates."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

expect_make_error() {
  local recipe_code="$1"
  local description="$2"
  local pattern="$3"
  shift 3
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
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "make -C ${ROOT_DIR} ${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Return the expected controlled diagnostic."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

for fixture in \
  valid-sql-smoke.sql \
  missing-timescaledb-extension.sql \
  wrong-timescaledb-version.sql \
  missing-timescaledb-library.sql \
  missing-toolkit-extension.sql \
  missing-shared-preload-libraries.sql \
  non-creatable-extension-allowed.yaml \
  non-creatable-extension-two-allowed.sql \
  non-creatable-extension-two-allowed.yaml \
  non-creatable-extension-denied.yaml \
  non-creatable-extension-missing-validation-target.yaml \
  non-creatable-extension-wrong-validation-target.yaml; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "SQL smoke fixture exists" "missing" "Restore the Story 3.5 fixture set."
    exit 1
  }
done

bash -n "${SCRIPT_DIR}/smoke-test.sh"

SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/valid-sql-smoke.sql" CHECKS=sql \
  make -C "${ROOT_DIR}" smoke PG=18 DEBIAN=trixie >/tmp/story-3-5-valid-sql.out
grep -Fq 'PASS SQL smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-5-valid-sql.out || {
  diag "make smoke SQL valid fixture" "${FIXTURE_DIR}/valid-sql-smoke.sql" "PASS marker" "$(cat /tmp/story-3-5-valid-sql.out)" "Wire root make smoke CHECKS=sql to the SQL smoke path."
  exit 1
}

tmpdir="$(mktemp -d)"
fake_docker="${tmpdir}/docker"
capture="${tmpdir}/capture.txt"
cat >"${fake_docker}" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${SMOKE_SQL_DOCKER_CAPTURE}"
if [[ "$1" == "run" ]]; then
  cat <<'KV'
select.version=ok
show.server_version=18.4 (Debian 18.4-1.pgdg13+1)
show.shared_preload_libraries=timescaledb,pgaudit
library.timescaledb=present
create.timescaledb=ok
extversion.timescaledb=2.27.2
create.timescaledb_toolkit=ok
extversion.timescaledb_toolkit=1.23.0
create.vector=ok
extversion.vector=0.8.1
create.pgaudit=ok
extversion.pgaudit=1.8.0
control.vector=vector.control:present
control.pgaudit=pgaudit.control:present
KV
  exit 0
fi
printf 'unexpected docker args: %s\n' "$*" >&2
exit 2
SH
chmod +x "${fake_docker}"
SMOKE_SQL_DOCKER_CAPTURE="${capture}" DOCKER_BIN="${fake_docker}" SMOKE_METADATA="${METADATA_FIXTURE}" CHECKS=sql \
  "${SCRIPT_DIR}/smoke-test.sh" 18 trixie >/tmp/story-3-5-fake-live-sql.out
grep -Fq 'PASS SQL smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-5-fake-live-sql.out || {
  diag "smoke-test SQL fake Docker live path" "${capture}" "PASS marker" "$(cat /tmp/story-3-5-fake-live-sql.out)" "Exercise the non-fixture Docker SQL collector path."
  rm -rf "${tmpdir}"
  exit 1
}
grep -Fq 'run --rm --entrypoint /bin/sh' "${capture}" || {
  diag "smoke-test SQL fake Docker live path" "${capture}" "docker run collector invoked" "$(cat "${capture}")" "Exercise the live SQL collector command path."
  rm -rf "${tmpdir}"
  exit 1
}
for probe in 'SELECT version()' 'SHOW server_version' "shared_preload_libraries = 'timescaledb,pgaudit'" 'CREATE EXTENSION IF NOT EXISTS'; do
  grep -Fq "${probe}" "${capture}" || {
    diag "smoke-test SQL fake Docker live path" "${capture}" "collector script contains ${probe}" "$(cat "${capture}")" "Keep the live SQL collector aligned with Story 3.5 acceptance criteria."
    rm -rf "${tmpdir}"
    exit 1
  }
done
rm -rf "${tmpdir}"

tmpdir="$(mktemp -d)"
fake_docker="${tmpdir}/docker"
capture="${tmpdir}/capture.txt"
cat >"${fake_docker}" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${SMOKE_SQL_DOCKER_CAPTURE}"
if [[ "$1" == "run" ]]; then
  cat <<'KV'
select.version=ok
show.server_version=18.4
show.shared_preload_libraries=timescaledb,pgaudit
library.timescaledb=present
create.timescaledb=ok
extversion.timescaledb=2.27.2
create.timescaledb_toolkit=ok
extversion.timescaledb_toolkit=1.23.0
control.vector=vector.control:present
control.pgaudit=pgaudit.control:present
validation.vector.target=vector.control
validation.vector.result=present
validation.pgaudit.target=pgaudit.control
validation.pgaudit.result=present
KV
  exit 0
fi
printf 'unexpected docker args: %s\n' "$*" >&2
exit 2
SH
chmod +x "${fake_docker}"
SMOKE_SQL_DOCKER_CAPTURE="${capture}" DOCKER_BIN="${fake_docker}" SMOKE_METADATA="${FIXTURE_DIR}/non-creatable-extension-two-allowed.yaml" CHECKS=sql \
  "${SCRIPT_DIR}/smoke-test.sh" 18 trixie >/tmp/story-3-5-fake-live-sql-non-creatable.out
grep -Fq 'PASS SQL smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-5-fake-live-sql-non-creatable.out || {
  diag "smoke-test SQL fake Docker live non-creatable path" "${capture}" "PASS marker" "$(cat /tmp/story-3-5-fake-live-sql-non-creatable.out)" "Exercise the live validation-only SQL collector path."
  rm -rf "${tmpdir}"
  exit 1
}
for probe in 'non_creatable="pgaudit vector"' 'validation.vector.target' 'validation.pgaudit.target'; do
  grep -Fq "${probe}" "${capture}" || {
    diag "smoke-test SQL fake Docker live non-creatable path" "${capture}" "collector script contains ${probe}" "$(cat "${capture}")" "Keep live validation-only SQL smoke driven by selected metadata policy."
    rm -rf "${tmpdir}"
    exit 1
  }
done
for forbidden in 'CREATE EXTENSION IF NOT EXISTS vector' 'CREATE EXTENSION IF NOT EXISTS pgaudit'; do
  if grep -Fq "${forbidden}" "${capture}"; then
    diag "smoke-test SQL fake Docker live non-creatable path" "${capture}" "collector does not create metadata non-creatable extension" "${forbidden}" "Skip CREATE EXTENSION for extensions marked creatable:false."
    rm -rf "${tmpdir}"
    exit 1
  fi
done
rm -rf "${tmpdir}"

SMOKE_METADATA="${FIXTURE_DIR}/non-creatable-extension-allowed.yaml" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/non-creatable-extension-allowed.sql" CHECKS=sql \
  "${SCRIPT_DIR}/smoke-test.sh" 18 trixie >/tmp/story-3-5-non-creatable-allowed.out
grep -Fq 'PASS SQL smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-5-non-creatable-allowed.out || {
  diag "smoke-test SQL non-creatable allowed" "${FIXTURE_DIR}/non-creatable-extension-allowed.yaml" "PASS marker" "$(cat /tmp/story-3-5-non-creatable-allowed.out)" "Allow validation-only smoke only for documented non-creatable extensions."
  exit 1
}

SMOKE_METADATA="${FIXTURE_DIR}/non-creatable-extension-two-allowed.yaml" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/non-creatable-extension-two-allowed.sql" CHECKS=sql \
  "${SCRIPT_DIR}/smoke-test.sh" 18 trixie >/tmp/story-3-5-two-non-creatable-allowed.out
grep -Fq 'PASS SQL smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-5-two-non-creatable-allowed.out || {
  diag "smoke-test SQL two non-creatable allowed" "${FIXTURE_DIR}/non-creatable-extension-two-allowed.yaml" "PASS marker" "$(cat /tmp/story-3-5-two-non-creatable-allowed.out)" "Allow validation-only smoke for each documented non-creatable extension."
  exit 1
}

SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/valid-sql-smoke.sql" CHECKS=sql \
  make -C "${ROOT_DIR}" smoke PG=18 DEBIAN=trixie >/tmp/story-3-5-production-sql.out
grep -Fq 'PASS SQL smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-5-production-sql.out || {
  diag "make smoke SQL production valid fixture" "${FIXTURE_DIR}/valid-sql-smoke.sql" "PASS marker" "$(cat /tmp/story-3-5-production-sql.out)" "Production PG18 trixie SQL smoke must be runnable once publishable."
  exit 1
}

expect_fail "missing TimescaleDB extension" "check: CREATE EXTENSION timescaledb.*actual: 'missing'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/missing-timescaledb-extension.sql" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "wrong TimescaleDB version" "check: pg_extension.extversion timescaledb.*expected: '2.27.2'.*actual: '2.26.0'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/wrong-timescaledb-version.sql" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "missing TimescaleDB library" "check: TimescaleDB shared library.*expected: 'present'.*actual: 'missing'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/missing-timescaledb-library.sql" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "missing Toolkit extension" "check: CREATE EXTENSION timescaledb_toolkit.*actual: 'missing'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/missing-toolkit-extension.sql" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "missing preload" "check: shared_preload_libraries.*expected: 'timescaledb,pgaudit'.*actual: 'timescaledb'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/missing-shared-preload-libraries.sql" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "env-only non-creatable policy rejected" "SMOKE_EXTENSION_POLICY.*check: non-creatable extension policy source" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/non-creatable-extension-allowed.sql" SMOKE_EXTENSION_POLICY="${FIXTURE_DIR}/non-creatable-extension-allowed.yaml" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "non-creatable denied" "check: extension pgaudit creatable: false.*missing \['non_creatable_reason'\]" env SMOKE_METADATA="${FIXTURE_DIR}/non-creatable-extension-denied.yaml" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/non-creatable-extension-allowed.sql" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "non-creatable missing validation target" "check: extension pgaudit creatable: false.*missing \['validation_target'\]" env SMOKE_METADATA="${FIXTURE_DIR}/non-creatable-extension-missing-validation-target.yaml" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/non-creatable-extension-allowed.sql" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "non-creatable wrong validation target" "check: extension pgaudit creatable: false validation target.*expected: 'pgaudit.control'.*actual: 'wrong.control'" env SMOKE_METADATA="${FIXTURE_DIR}/non-creatable-extension-wrong-validation-target.yaml" SMOKE_SQL_FIXTURE="${FIXTURE_DIR}/non-creatable-extension-wrong-validation-target.sql" CHECKS=sql "${SCRIPT_DIR}/smoke-test.sh" 18 trixie

printf 'PASS story-3.5 SQL smoke fixtures\n'
