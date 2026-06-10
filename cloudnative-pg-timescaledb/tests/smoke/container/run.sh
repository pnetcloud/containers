#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/container/fixtures"
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
    diag "${*}" "${description}" "command fails" "passed" "Make invalid container smoke fixtures fail deterministically."
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
      diag "${*}" "${description}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Keep smoke diagnostics actionable for release gates."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

expect_exit() {
  local expected="$1"
  local description="$2"
  local pattern="$3"
  shift 3
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
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Return the expected controlled diagnostic."
    rm -f "${tmp}"
    exit 1
  fi
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
  valid-container \
  valid-pg19beta1-container \
  wrong-debian-release \
  wrong-postgres-major \
  wrong-postgres-server-version \
  missing-control-file \
  missing-label \
  wrong-binary-path \
  runtime-command-missing \
  missing-postgres-user \
  bad-data-dir-permissions \
  postgres-startup-fails; do
  [[ -f "${FIXTURE_DIR}/${fixture}.json" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}.json" "container smoke fixture exists" "missing" "Restore the Story 3.4 fixture set."
    exit 1
  }
done

bash -n "${SCRIPT_DIR}/smoke-test.sh"

SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/valid-container.json" CHECKS=container \
  make -C "${ROOT_DIR}" smoke PG=18 DEBIAN=trixie >/tmp/story-3-4-valid-smoke.out
grep -Fq 'PASS container smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-4-valid-smoke.out || {
  diag "make smoke valid fixture" "${FIXTURE_DIR}/valid-container.json" "PASS marker" "$(cat /tmp/story-3-4-valid-smoke.out)" "Wire root make smoke to the container smoke script."
  exit 1
}

SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/valid-pg19beta1-container.json" \
  "${SCRIPT_DIR}/smoke-test.sh" 19beta1 trixie >/tmp/story-3-4-valid-pg19beta1-smoke.out
grep -Fq 'PASS container smoke image=local/pg19beta1-trixie:skeleton PG=19beta1 DEBIAN=trixie' /tmp/story-3-4-valid-pg19beta1-smoke.out || {
  diag "smoke-test pg19beta1 fixture" "${FIXTURE_DIR}/valid-pg19beta1-container.json" "PASS marker" "$(cat /tmp/story-3-4-valid-pg19beta1-smoke.out)" "Normalize beta PostgreSQL major checks consistently with metadata."
  exit 1
}

tmpdir="$(mktemp -d)"
fake_docker="${tmpdir}/docker"
capture="${tmpdir}/capture.txt"
cat >"${fake_docker}" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${SMOKE_DOCKER_CAPTURE}"
if [[ "$1 $2" == "image inspect" ]]; then
  cat <<'JSON'
[{"Config":{"Labels":{"org.opencontainers.image.created":"2026-06-09","org.opencontainers.image.source":"https://github.com/pnetcloud/containers","org.pnet.cnpg.digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","org.pnet.cnpg.tag":"18.4-standard-trixie","org.pnet.debian.variant":"trixie","org.pnet.postgresql.major":"18","org.pnet.postgresql.version":"18.4","org.pnet.timescaledb.version":"2.27.2","org.pnet.timescaledb_toolkit.version":"1.23.0"}}}]
JSON
  exit 0
fi
if [[ "$1" == "run" ]]; then
  if [[ "$*" == *'RANDOM'* ]]; then
    printf 'RANDOM is not POSIX-safe under /bin/sh -eu\n' >&2
    exit 7
  fi
  cat <<'KV'
debian_release=trixie
postgres_server_version=18.4
postgres_major=18
control_timescaledb=present
control_timescaledb_toolkit=present
control_vector=present
control_pgaudit=present
binary_postgres=ok
binary_path_postgres=/usr/lib/postgresql/18/bin/postgres
binary_initdb=ok
binary_path_initdb=/usr/lib/postgresql/18/bin/initdb
binary_pg_ctl=ok
binary_path_pg_ctl=/usr/lib/postgresql/18/bin/pg_ctl
binary_psql=ok
binary_path_psql=/usr/lib/postgresql/18/bin/psql
postgres_user=present
data_dir_permissions=0700
postgres_startup=ok
KV
  exit 0
fi
printf 'unexpected docker args: %s\n' "$*" >&2
exit 2
SH
chmod +x "${fake_docker}"
SMOKE_DOCKER_CAPTURE="${capture}" DOCKER_BIN="${fake_docker}" SMOKE_METADATA="${METADATA_FIXTURE}" \
  "${SCRIPT_DIR}/smoke-test.sh" 18 trixie >/tmp/story-3-4-fake-live-smoke.out
grep -Fq 'PASS container smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-4-fake-live-smoke.out || {
  diag "smoke-test fake Docker live path" "${capture}" "PASS marker" "$(cat /tmp/story-3-4-fake-live-smoke.out)" "Exercise the non-fixture Docker collector path."
  rm -rf "${tmpdir}"
  exit 1
}
grep -Fq 'run --rm --entrypoint /bin/sh' "${capture}" || {
  diag "smoke-test fake Docker live path" "${capture}" "docker run collector invoked" "$(cat "${capture}")" "Exercise the live container collector command path."
  rm -rf "${tmpdir}"
  exit 1
}
rm -rf "${tmpdir}"

SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/valid-container.json" CHECKS=container \
  make -C "${ROOT_DIR}" smoke PG=18 DEBIAN=trixie >/tmp/story-3-4-production-smoke.out
grep -Fq 'PASS container smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-4-production-smoke.out || {
  diag "make smoke production valid fixture" "${FIXTURE_DIR}/valid-container.json" "PASS marker" "$(cat /tmp/story-3-4-production-smoke.out)" "Production PG18 trixie must be smokeable once publishable."
  exit 1
}

SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_SQL_FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/valid-sql-smoke.sql" CHECKS=sql \
  make -C "${ROOT_DIR}" smoke PG=18 DEBIAN=trixie >/tmp/story-3-4-production-sql-smoke.out
grep -Fq 'PASS SQL smoke image=local/pg18-trixie:skeleton PG=18 DEBIAN=trixie' /tmp/story-3-4-production-sql-smoke.out || {
  diag "make smoke production SQL valid fixture" "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/sql/fixtures/valid-sql-smoke.sql" "PASS marker" "$(cat /tmp/story-3-4-production-sql-smoke.out)" "Production PG18 trixie SQL smoke must be runnable once publishable."
  exit 1
}
expect_make_error 64 "unknown smoke checks rejected" "one of container, sql" smoke PG=18 DEBIAN=trixie CHECKS=network

expect_fail "wrong Debian release" "check: Debian release.*expected: 'trixie'.*actual: 'bookworm'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/wrong-debian-release.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "wrong PostgreSQL major" "check: PostgreSQL major.*expected: '18'.*actual: '17'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/wrong-postgres-major.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "wrong PostgreSQL server version" "check: PostgreSQL server version.*expected: '18.4'.*actual: '18.3'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/wrong-postgres-server-version.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "missing control file" "check: control file timescaledb_toolkit.control.*actual: 'missing'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/missing-control-file.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "missing label" "check: label org.pnet.cnpg.tag.*actual: None" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/missing-label.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "wrong binary path" "check: runtime binary path psql.*expected: '/usr/lib/postgresql/18/bin/psql'.*actual: '/usr/bin/psql'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/wrong-binary-path.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "runtime command missing" "check: runtime binary psql.*actual: 'missing'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/runtime-command-missing.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "missing postgres user" "check: postgres user.*actual: 'missing'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/missing-postgres-user.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "bad data dir permissions" "check: data directory permissions.*actual: '0755'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/bad-data-dir-permissions.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie
expect_fail "postgres startup fails" "check: temporary PostgreSQL startup.*actual: 'failed'" env SMOKE_METADATA="${METADATA_FIXTURE}" SMOKE_CONTAINER_FIXTURE="${FIXTURE_DIR}/postgres-startup-fails.json" "${SCRIPT_DIR}/smoke-test.sh" 18 trixie

printf 'PASS story-3.4 container smoke fixtures\n'
