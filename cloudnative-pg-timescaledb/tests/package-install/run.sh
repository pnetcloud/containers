#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/package-install/fixtures"
GENERATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh"
VERIFY="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/verify-package-install.sh"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

manifest_fixture() {
  local target="$1"
  cat >"${target}" <<'JSON'
{
  "manifests": [
    {
      "tag": "18.4-standard-trixie",
      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "platforms": ["linux/amd64", "linux/arm64"]
    },
    {
      "tag": "18.4-standard-bookworm",
      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "platforms": ["linux/amd64", "linux/arm64"]
    }
  ]
}
JSON
}

run_generate() {
  local metadata="$1"
  local output="$2"
  local manifest="$3"
  CNPG_MANIFEST_FIXTURE="${manifest}" DOCKERFILE_GENERATED_DATE=2026-06-09 "${GENERATOR}" --metadata "${metadata}" --output "${output}"
}

expect_fail() {
  local description="$1"
  local pattern="$2"
  local metadata="$3"
  local tmp_root manifest log status
  tmp_root="$(mktemp -d)"
  manifest="${tmp_root}/manifest.json"
  log="${tmp_root}/log.txt"
  manifest_fixture "${manifest}"
  set +e
  run_generate "${metadata}" "${tmp_root}/generated" "${manifest}" >"${log}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "generate-dockerfiles ${metadata}" "${description}" "fails" "passed" "Reject incomplete package-install metadata before producing an image."
    rm -rf "${tmp_root}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${log}"; then
    diag "generate-dockerfiles ${metadata}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${log}")" "Keep package-install diagnostics deterministic and specific."
    rm -rf "${tmp_root}"
    exit 1
  fi
  rm -rf "${tmp_root}"
}

run_verify_with_fake_dpkg() {
  local mode="$1"
  local tmp_root fakebin log status
  tmp_root="$(mktemp -d)"
  fakebin="${tmp_root}/bin"
  log="${tmp_root}/log.txt"
  mkdir -p "${fakebin}"
  cat >"${fakebin}/dpkg-query" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${DPKG_QUERY_LOG}"
package="${@: -1}"
case "${DPKG_QUERY_MODE}:${package}" in
  pass:timescaledb-2-postgresql-18) printf '2.27.2~debian13-1804' ;;
  pass:timescaledb-toolkit-postgresql-18) printf '1:1.23.0~debian13' ;;
  mismatch:timescaledb-2-postgresql-18) printf '0.0.0' ;;
  mismatch:timescaledb-toolkit-postgresql-18) printf '1:1.23.0~debian13' ;;
  missing:timescaledb-2-postgresql-18) printf 'package not found' >&2; exit 1 ;;
  missing:timescaledb-toolkit-postgresql-18) printf '1:1.23.0~debian13' ;;
  *) printf 'unexpected package %s' "${package}" >&2; exit 2 ;;
esac
SH
  chmod +x "${fakebin}/dpkg-query"
  set +e
  PATH="${fakebin}:${PATH}" DPKG_QUERY_MODE="${mode}" DPKG_QUERY_LOG="${tmp_root}/dpkg-query.log" \
    "${VERIFY}" \
    timescaledb-2-postgresql-18 2.27.2~debian13-1804 \
    timescaledb-toolkit-postgresql-18 1:1.23.0~debian13 >"${log}" 2>&1
  status="$?"
  set -e
  case "${mode}" in
    pass)
      if [[ "${status}" != "0" ]]; then
        diag "${VERIFY} fake dpkg-query" "${mode}" "passes" "$(tr '\n' ' ' <"${log}")" "Exact installed versions must pass verification."
        rm -rf "${tmp_root}"
        exit 1
      fi
      ;;
    missing|mismatch)
      if [[ "${status}" == "0" ]]; then
        diag "${VERIFY} fake dpkg-query" "${mode}" "fails" "passed" "Missing packages and version mismatches must fail verification."
        rm -rf "${tmp_root}"
        exit 1
      fi
      ;;
  esac
  grep -Fq -- "-W -f=\${Version} timescaledb-2-postgresql-18" "${tmp_root}/dpkg-query.log" || { diag "grep dpkg-query log" "${tmp_root}/dpkg-query.log" "dpkg-query exact Version format for TimescaleDB" "missing" "verify-package-install must query exact Debian package versions."; exit 1; }
  if [[ "${mode}" == "pass" ]]; then
    grep -Fq -- "-W -f=\${Version} timescaledb-toolkit-postgresql-18" "${tmp_root}/dpkg-query.log" || { diag "grep dpkg-query log" "${tmp_root}/dpkg-query.log" "dpkg-query exact Version format for Toolkit" "missing" "verify-package-install must query exact Debian package versions."; exit 1; }
  fi
  rm -rf "${tmp_root}"
}

for fixture in \
  valid-timescaledb-toolkit-package \
  valid-trixie-amd64 \
  valid-trixie-arm64 \
  valid-bookworm-amd64 \
  valid-bookworm-arm64 \
  missing-timescaledb-package \
  missing-toolkit-publishable \
  pgvector-base-source \
  pgvector-package-source \
  pgaudit-base-source \
  pgaudit-package-source \
  pgvector-source-mismatch \
  pgaudit-source-mismatch \
  missing-extension-source \
  wrong-apt-codename \
  wrong-apt-architecture; do
  [[ -f "${FIXTURE_DIR}/${fixture}.yaml" ]] || { diag "test -f" "${FIXTURE_DIR}/${fixture}.yaml" "package-install fixture exists" "missing" "Restore Story 3.2 package-install fixture."; exit 1; }
done

bash -n "${VERIFY}"
if "${VERIFY}" >/tmp/story-3-2-verify-args.out 2>&1; then
  diag "${VERIFY}" "arguments" "missing args fail" "passed" "verify-package-install must reject incomplete calls."
  exit 1
fi
run_verify_with_fake_dpkg pass
run_verify_with_fake_dpkg missing
run_verify_with_fake_dpkg mismatch

tmp_root="$(mktemp -d)"
manifest="${tmp_root}/manifest.json"
manifest_fixture "${manifest}"

for tuple in \
  "valid-trixie-amd64 trixie amd64 2.27.2~debian13-1804 1:1.23.0~debian13" \
  "valid-trixie-arm64 trixie arm64 2.27.2~debian13-1804 1:1.23.0~debian13" \
  "valid-bookworm-amd64 bookworm amd64 2.27.2~debian12-1804 1:1.23.0~debian12" \
  "valid-bookworm-arm64 bookworm arm64 2.27.2~debian12-1804 1:1.23.0~debian12"; do
  read -r fixture debian arch ts_version tk_version <<<"${tuple}"
  output_dir="${tmp_root}/${fixture}"
  run_generate "${FIXTURE_DIR}/${fixture}.yaml" "${output_dir}" "${manifest}" >/tmp/story-3-2-positive-fixture.out
  dockerfile="${output_dir}/18/${debian}/Dockerfile"
  grep -Fq "${debian}:${arch}" "${dockerfile}" || { diag "grep" "${dockerfile}" "apt guard includes ${debian}:${arch}" "missing" "Positive package-install fixtures must exercise every Debian/architecture combination."; exit 1; }
  grep -Fq "timescaledb-2-postgresql-18=${ts_version}" "${dockerfile}" || { diag "grep" "${dockerfile}" "TimescaleDB exact version ${ts_version}" "missing" "Render exact TimescaleDB package version for ${fixture}."; exit 1; }
  grep -Fq "timescaledb-toolkit-postgresql-18=${tk_version}" "${dockerfile}" || { diag "grep" "${dockerfile}" "Toolkit exact version ${tk_version}" "missing" "Render exact Toolkit package version for ${fixture}."; exit 1; }
done

run_generate "${FIXTURE_DIR}/valid-timescaledb-toolkit-package.yaml" "${tmp_root}/generated" "${manifest}" >/tmp/story-3-2-valid-package.out
dockerfile="${tmp_root}/generated/18/trixie/Dockerfile"
for expected in \
  'COPY scripts/verify-package-install.sh /usr/local/bin/verify-package-install' \
  'https://packagecloud.io/timescale/timescaledb/debian/ trixie main' \
  'trixie:amd64|trixie:arm64|bookworm:amd64|bookworm:arm64' \
  '. /etc/os-release' \
  'dpkg --print-architecture' \
  'timescaledb-2-postgresql-18=2.27.2~debian13-1804' \
  'timescaledb-toolkit-postgresql-18=1:1.23.0~debian13' \
  '/usr/local/bin/verify-package-install' \
  '/usr/share/postgresql/18/extension/vector.control' \
  '/usr/share/postgresql/18/extension/pgaudit.control'; do
  grep -Fq "${expected}" "${dockerfile}" || { diag "grep" "${dockerfile}" "contains ${expected}" "missing" "Render exact package install and extension verification logic."; exit 1; }
done

run_generate "${FIXTURE_DIR}/pgvector-package-source.yaml" "${tmp_root}/pgvector-package" "${manifest}" >/tmp/story-3-2-pgvector-package.out
grep -Fq 'postgresql-18-pgvector=0.8.1-1.pgdg13+1' "${tmp_root}/pgvector-package/18/trixie/Dockerfile" || { diag "grep" "pgvector package Dockerfile" "exact pgvector package install" "missing" "Package-sourced pgvector must install and verify exact version."; exit 1; }

run_generate "${FIXTURE_DIR}/pgaudit-package-source.yaml" "${tmp_root}/pgaudit-package" "${manifest}" >/tmp/story-3-2-pgaudit-package.out
grep -Fq 'postgresql-18-pgaudit=1.8.0-1.pgdg13+1' "${tmp_root}/pgaudit-package/18/trixie/Dockerfile" || { diag "grep" "pgaudit package Dockerfile" "exact pgaudit package install" "missing" "Package-sourced PGAudit must install and verify exact version."; exit 1; }

expect_fail "missing TimescaleDB package" "package names/versions|timescaledb" "${FIXTURE_DIR}/missing-timescaledb-package.yaml"
expect_fail "missing Toolkit package" "package names/versions|toolkit" "${FIXTURE_DIR}/missing-toolkit-publishable.yaml"
expect_fail "pgvector source mismatch" "pgvector base source has empty package version" "${FIXTURE_DIR}/pgvector-source-mismatch.yaml"
expect_fail "pgaudit source mismatch" "pgaudit base source has empty package version" "${FIXTURE_DIR}/pgaudit-source-mismatch.yaml"
expect_fail "missing extension source" "pgvector_source is base or package|missing" "${FIXTURE_DIR}/missing-extension-source.yaml"
expect_fail "wrong apt codename" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/wrong-apt-codename.yaml"
expect_fail "wrong apt architecture" "platforms exactly linux/amd64 and linux/arm64" "${FIXTURE_DIR}/wrong-apt-architecture.yaml"

rm -rf "${tmp_root}"
printf 'PASS story-3.2 package install fixtures\n'
