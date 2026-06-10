#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/dockerfile/fixtures"
GENERATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh"

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
      "tag": "18.4-system-trixie",
      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "platforms": ["linux/amd64", "linux/arm64"]
    },
    {
      "tag": "18.4-standard-trixie",
      "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "platforms": ["linux/amd64"]
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
    diag "generate-dockerfiles ${metadata}" "${description}" "fails" "passed" "Make invalid Dockerfile metadata fail deterministically."
    rm -rf "${tmp_root}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${log}"; then
    diag "generate-dockerfiles ${metadata}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${log}")" "Keep Dockerfile diagnostics deterministic and specific."
    rm -rf "${tmp_root}"
    exit 1
  fi
  rm -rf "${tmp_root}"
}

expect_fail_json() {
  local description="$1"
  local pattern="$2"
  local metadata="$3"
  local tmp_root manifest log status
  tmp_root="$(mktemp -d)"
  manifest="${tmp_root}/manifest.json"
  log="${tmp_root}/log.txt"
  manifest_fixture "${manifest}"
  set +e
  CNPG_MANIFEST_FIXTURE="${manifest}" DOCKERFILE_GENERATED_DATE=2026-06-09 "${GENERATOR}" --metadata "${metadata}" --output "${tmp_root}/generated" --json >"${log}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "generate-dockerfiles --json ${metadata}" "${description}" "fails" "passed" "Make JSON summaries reject invalid publishable Dockerfile metadata."
    rm -rf "${tmp_root}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${log}"; then
    diag "generate-dockerfiles --json ${metadata}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${log}")" "Keep JSON-mode Dockerfile diagnostics deterministic and specific."
    rm -rf "${tmp_root}"
    exit 1
  fi
  rm -rf "${tmp_root}"
}

for fixture in valid-digest-pinned missing-cnpg-digest malformed-cnpg-digest unresolved-or-platform-missing-cnpg-digest skipped-nonpublish-missing-cnpg-digest system-flavor-base vendor-build-context; do
  [[ -f "${FIXTURE_DIR}/${fixture}.yaml" ]] || { diag "test -f" "${FIXTURE_DIR}/${fixture}.yaml" "fixture exists" "missing" "Restore Story 3.1 Dockerfile fixture."; exit 1; }
done

tmp_root="$(mktemp -d)"
manifest="${tmp_root}/manifest.json"
manifest_fixture "${manifest}"
output="${tmp_root}/generated"
run_generate "${FIXTURE_DIR}/valid-digest-pinned.yaml" "${output}" "${manifest}" >/tmp/story-3-1-valid.out
dockerfile="${output}/18/trixie/Dockerfile"
[[ -f "${dockerfile}" ]] || { diag "test -f" "${dockerfile}" "publishable Dockerfile exists" "missing" "Generate Dockerfiles for publish:true entries."; exit 1; }
[[ ! -f "${output}/18/trixie/Dockerfile.skipped.json" ]] || { diag "test ! -f" "${output}/18/trixie/Dockerfile.skipped.json" "publishable skipped marker absent" "present" "Do not mark publishable entries as skipped."; exit 1; }
grep -Eq '^FROM ghcr\.io/cloudnative-pg/postgresql:18\.4-standard-trixie@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$' "${dockerfile}" || { diag "grep FROM" "${dockerfile}" "digest-pinned CNPG standard FROM" "missing" "Use exact CNPG standard tag and digest in FROM."; exit 1; }
for label in org.opencontainers.image.source org.opencontainers.image.created org.pnet.postgresql.major org.pnet.postgresql.version org.pnet.debian.variant org.pnet.cnpg.tag org.pnet.cnpg.digest org.pnet.timescaledb.version org.pnet.timescaledb_toolkit.version; do
  grep -Fq "${label}" "${dockerfile}" || { diag "grep label" "${dockerfile}" "label ${label}" "missing" "Emit all required OCI/custom labels."; exit 1; }
done
if grep -Eq 'system-|vendor/' "${dockerfile}"; then
  diag "grep forbidden" "${dockerfile}" "no system-* or vendor/ in generated Dockerfile" "$(grep -En 'system-|vendor/' "${dockerfile}")" "Use standard CNPG bases and no vendor runtime/build input."
  exit 1
fi
grep -RE "FROM ghcr.io/cloudnative-pg/postgresql:.+@sha256:" "${output}" >/tmp/story-3-1-from.out
grep -Fq 'ARG TARGETARCH' "${dockerfile}" || { diag "grep TARGETARCH" "${dockerfile}" "BuildKit TARGETARCH arg is declared" "missing" "Expose BuildKit TARGETARCH inside the stage for multi-platform builds."; exit 1; }
grep -Fq 'ARG TARGETARCH=amd64' "${dockerfile}" && { diag "grep TARGETARCH default" "${dockerfile}" "no default TARGETARCH" "ARG TARGETARCH=amd64" "Do not override BuildKit TARGETARCH during arm64 builds."; exit 1; }

skipped_output="${tmp_root}/skipped"
run_generate "${FIXTURE_DIR}/skipped-nonpublish-missing-cnpg-digest.yaml" "${skipped_output}" "${manifest}" >/tmp/story-3-1-skipped.out
[[ ! -f "${skipped_output}/18/trixie/Dockerfile" ]] || { diag "test ! -f" "${skipped_output}/18/trixie/Dockerfile" "skipped row has no buildable Dockerfile" "present" "Do not generate buildable output for publish:false entries."; exit 1; }
[[ -f "${skipped_output}/18/trixie/Dockerfile.skipped.json" ]] || { diag "test -f" "${skipped_output}/18/trixie/Dockerfile.skipped.json" "skipped marker exists" "missing" "Emit deterministic skipped marker for publish:false entries."; exit 1; }

expect_fail "missing digest on publishable row" "sha256:<64 lowercase hex>|cnpg_digest" "${FIXTURE_DIR}/missing-cnpg-digest.yaml"
expect_fail "malformed digest on publishable row" "sha256:<64 lowercase hex>|cnpg_digest" "${FIXTURE_DIR}/malformed-cnpg-digest.yaml"
expect_fail "platform missing or unresolved digest" "missing \['linux/arm64'\]|metadata platforms" "${FIXTURE_DIR}/unresolved-or-platform-missing-cnpg-digest.yaml"
expect_fail "deprecated system flavor" "standard-\*|system" "${FIXTURE_DIR}/system-flavor-base.yaml"
expect_fail "vendor build or runtime input" "vendor/" "${FIXTURE_DIR}/vendor-build-context.yaml"

expect_fail_json "missing digest on publishable JSON row" "sha256:<64 lowercase hex>|cnpg_digest" "${FIXTURE_DIR}/missing-cnpg-digest.yaml"
expect_fail_json "malformed digest on publishable JSON row" "sha256:<64 lowercase hex>|cnpg_digest" "${FIXTURE_DIR}/malformed-cnpg-digest.yaml"
expect_fail_json "platform missing or unresolved JSON row" "missing \['linux/arm64'\]|metadata platforms" "${FIXTURE_DIR}/unresolved-or-platform-missing-cnpg-digest.yaml"
expect_fail_json "deprecated system flavor JSON row" "standard-\*|system" "${FIXTURE_DIR}/system-flavor-base.yaml"
expect_fail_json "vendor build or runtime input JSON row" "vendor/" "${FIXTURE_DIR}/vendor-build-context.yaml"

rm -rf "${tmp_root}"
printf 'PASS story-3.1 Dockerfile template fixtures\n'
