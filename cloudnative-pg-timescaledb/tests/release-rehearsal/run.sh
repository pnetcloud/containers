#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/release-rehearsal.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures"
REPORT="$(mktemp)"
cleanup() {
  rm -f "${REPORT}"
}
trap cleanup EXIT
WORKFLOW="${ROOT_DIR}/.github/workflows/release-rehearsal.yml"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

require_fixture() {
  local name="$1"
  if [[ ! -f "${FIXTURE_DIR}/${name}" ]]; then
    diag "test -f" "${FIXTURE_DIR}/${name}" "fixture exists" "missing" "Restore the Story 5.9 release rehearsal fixture."
    exit 1
  fi
}

require_workflow_arm64_emulation() {
  local workflow="$1"
  local qemu_line rehearsal_line
  if [[ ! -f "${workflow}" ]]; then
    diag "test -f" "${workflow}" "release rehearsal workflow exists" "missing" "Restore .github/workflows/release-rehearsal.yml."
    exit 1
  fi
  for token in \
    'cloudnative-pg-timescaledb/scripts/ci-apt-install.sh binfmt-support qemu-user-static' \
    'binfmt-support' \
    'qemu-user-static' \
    'update-binfmts --enable qemu-aarch64' \
    'make release-rehearsal'; do
    if ! grep -Fq "${token}" "${workflow}"; then
      diag "grep ${token}" "${workflow}" "workflow prepares arm64 emulation before release rehearsal" "missing ${token}" "Enable qemu-aarch64 before release rehearsal builds linux/arm64 candidates on ubuntu-latest."
      exit 1
    fi
  done
  if grep -Eq 'sudo apt-get (update|install)' "${workflow}"; then
    diag "grep bare apt-get" "${workflow}" "workflow package installs use retrying apt helper" "bare apt-get found" "Use ci-apt-install.sh so transient apt mirror failures do not fail release rehearsal."
    exit 1
  fi
  qemu_line="$(grep -nF 'update-binfmts --enable qemu-aarch64' "${workflow}" | head -n1 | cut -d: -f1)"
  rehearsal_line="$(grep -nF 'make release-rehearsal' "${workflow}" | head -n1 | cut -d: -f1)"
  if [[ -z "${qemu_line}" || -z "${rehearsal_line}" || "${qemu_line}" -ge "${rehearsal_line}" ]]; then
    diag "workflow step order" "${workflow}" "qemu-aarch64 is enabled before make release-rehearsal" "qemu line ${qemu_line:-missing}, rehearsal line ${rehearsal_line:-missing}" "Keep arm64 emulation setup before the release rehearsal build/smoke orchestration."
    exit 1
  fi
}

expect_pass() {
  local fixture="$1"
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${SCRIPT}" --dry-run --date 20260609 --fixture "${FIXTURE_DIR}/${fixture}" --no-report >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" != "0" ]]; then
    diag "release-rehearsal ${fixture}" "positive fixture passes" "exit 0" "exit ${status}: $(tr '\n' ' ' <"${tmp}")" "Keep positive release rehearsal evidence complete and aligned."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -Fq 'PASS release-rehearsal date=20260609' "${tmp}"; then
    diag "release-rehearsal ${fixture}" "positive fixture emits PASS marker" "PASS marker" "$(cat "${tmp}")" "Keep release rehearsal output machine-readable."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

expect_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status
  tmp="$(mktemp)"
  set +e
  WORKFLOW_RUN_URL=https://github.com/pnetcloud/containers/actions/runs/1234567890 \
    "${SCRIPT}" --dry-run --date 20260609 --fixture "${FIXTURE_DIR}/${fixture}" --expect-failure >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "release-rehearsal ${fixture}" "negative fixture fails" "non-zero" "exit 0" "Make the fixture break its intended release gate."
    rm -f "${tmp}"
    exit 1
  fi
  for token in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${token}" "${tmp}"; then
      diag "release-rehearsal ${fixture}" "diagnostic includes ${token}" "present" "$(cat "${tmp}")" "Keep release rehearsal diagnostics deterministic and actionable."
      rm -f "${tmp}"
      exit 1
    fi
  done
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "release-rehearsal ${fixture}" "diagnostic matches ${pattern}" "match" "$(tr '\n' ' ' <"${tmp}")" "Fail on the intended release-blocking condition."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

positive_fixtures=(
  valid-full-matrix.json
  no-op-update.json
  changed-update-autocommit.json
)

negative_fixtures=(
  missing-publishable-pg-debian-platform.json
  missing-smoke-result.json
  missing-sbom.json
  missing-provenance.json
  missing-signature.json
  vulnerability-threshold-failed.json
  scan-wrong-digest.json
  sbom-wrong-digest.json
  provenance-wrong-digest.json
  signature-wrong-digest.json
  wrong-latest.json
  latest-not-pg18-trixie.json
  stale-generated-files.json
  unpublished-catalog-reference.json
  secret-in-summary.json
  secret-in-command.json
  secret-in-workflow-url.json
  secret-in-candidate-metadata.json
  pg19beta1-promoted-to-latest.json
  vendor-used-as-build-context.json
  vendor-used-as-runtime-input.json
  vendor-exact-build-context.json
  vendor-dot-build-context.json
  vendor-absolute-runtime-input.json
  alpine-release-candidate.json
  bullseye-release-candidate.json
  unsupported-debian-variant.json
  missing-workflow-dispatch-evidence.json
)

for fixture in "${positive_fixtures[@]}" "${negative_fixtures[@]}"; do
  require_fixture "${fixture}"
done

require_workflow_arm64_emulation "${WORKFLOW}"

for fixture in "${positive_fixtures[@]}"; do
  expect_pass "${fixture}"
done

expect_fail missing-publishable-pg-debian-platform.json 'matrix enumerates every supported PostgreSQL/Debian combination|17-trixie'
expect_fail missing-smoke-result.json 'smoke_sql|every platform evidence row passed'
expect_fail missing-sbom.json 'sbom|SBOM'
expect_fail missing-provenance.json 'provenance'
expect_fail missing-signature.json 'signature'
expect_fail vulnerability-threshold-failed.json 'vulnerability threshold gate passed'
expect_fail scan-wrong-digest.json 'vulnerability scan is bound to the candidate index digest'
expect_fail sbom-wrong-digest.json 'sbom evidence is bound to the candidate index digest'
expect_fail provenance-wrong-digest.json 'provenance evidence is bound to the candidate index digest'
expect_fail signature-wrong-digest.json 'signature evidence is bound to the candidate index digest'
expect_fail wrong-latest.json 'latest resolves to 18-trixie'
expect_fail latest-not-pg18-trixie.json 'latest resolves to 18-trixie'
expect_fail stale-generated-files.json 'generated files are fresh'
expect_fail unpublished-catalog-reference.json 'referenced in its catalog'
expect_fail secret-in-summary.json 'no secrets'
expect_fail secret-in-command.json 'no secrets|secret_locations'
expect_fail secret-in-workflow-url.json 'no secrets|secret_locations'
expect_fail secret-in-candidate-metadata.json 'no secrets|secret_locations'
expect_fail pg19beta1-promoted-to-latest.json 'latest resolves to 18-trixie|experimental PG19beta1'
expect_fail vendor-used-as-build-context.json 'build context excludes reference-only tree'
expect_fail vendor-used-as-runtime-input.json 'runtime inputs exclude reference-only tree'
expect_fail vendor-exact-build-context.json 'build context excludes reference-only tree'
expect_fail vendor-dot-build-context.json 'build context excludes reference-only tree'
expect_fail vendor-absolute-runtime-input.json 'runtime inputs exclude reference-only tree'
expect_fail alpine-release-candidate.json 'Alpine release candidates are blocked'
expect_fail bullseye-release-candidate.json 'bullseye release candidates are blocked'
expect_fail unsupported-debian-variant.json 'Debian variant is trixie or bookworm'
expect_fail missing-workflow-dispatch-evidence.json 'workflow_dispatch.url|actual release-rehearsal.yml workflow run URL'

"${SCRIPT}" --dry-run --date 20260609 --fixture "${FIXTURE_DIR}/valid-full-matrix.json" --report "${REPORT}" >/tmp/story-5-9-report.out

# shellcheck disable=SC2016
for token in \
  '# Release Rehearsal Report' \
  'UTC date: `20260609`' \
  'Expected target: `18-trixie`' \
  'Actual target: `18-trixie`' \
  'sha256:4444444444444444444444444444444444444444444444444444444444444444' \
  'cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml' \
  'cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml' \
  'https://github.com/pnetcloud/containers/actions/runs/1234567890' \
  'make release-rehearsal DATE=20260609 DRY_RUN=1'; do
  if ! grep -Fq "${token}" "${REPORT}"; then
    diag "grep ${token}" "${REPORT}" "report includes ${token}" "missing" "Regenerate the release rehearsal report from the valid fixture."
    exit 1
  fi
done

prepare_orchestration_project() {
  local project="$1"
  mkdir -p "${project}/cloudnative-pg-timescaledb/scripts"
  mkdir -p "${project}/cloudnative-pg-timescaledb/tests/barman-plugin/fixtures"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/current-reference.json" "${project}/cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/current-reference.json"
  printf 'SHELL := /usr/bin/env bash\n' > "${project}/Makefile"
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\nprintf "validate-docs\\n" >> "${RELEASE_REHEARSAL_CAPTURE:?}"\n' > "${project}/cloudnative-pg-timescaledb/scripts/validate-docs.sh"
  chmod +x "${project}/cloudnative-pg-timescaledb/scripts/validate-docs.sh"
  (cd "${project}" && git init -q && git config user.email test@example.invalid && git config user.name test && git add . && git commit -qm baseline)
}

prepare_orchestration_shims() {
  local bin_dir="$1"
  mkdir -p "${bin_dir}"
  cat > "${bin_dir}/make" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
args=()
for arg in "$@"; do
  [[ "${arg}" == "--no-print-directory" ]] && continue
  args+=("${arg}")
done
target="${args[0]:-}"
pg="${PG:-}"
debian="${DEBIAN:-}"
for arg in "${args[@]:1}"; do
  case "${arg}" in
    PG=*) pg="${arg#PG=}" ;;
    DEBIAN=*) debian="${arg#DEBIAN=}" ;;
  esac
done
printf 'make %s PG=%s DEBIAN=%s PLATFORM=%s CHECKS=%s\n' "${target}" "${pg}" "${debian}" "${PLATFORM:-}" "${CHECKS:-}" >> "${RELEASE_REHEARSAL_CAPTURE:?}"
if [[ "${target}" == "update" && "${RELEASE_REHEARSAL_DIRTY_UPDATE:-0}" == "1" ]]; then
  mkdir -p cloudnative-pg-timescaledb/generated
  printf 'dirty update marker\n' > cloudnative-pg-timescaledb/generated/dirty-update-marker
fi
if [[ "${target}" == "matrix" ]]; then
  printf '{"include":[{"pg_major":"18","debian_variant":"trixie","publish":true,"platforms":["linux/amd64","linux/arm64"]}],"skipped":[]}\n'
fi
if [[ "${target}" == "build" && "${RELEASE_REHEARSAL_FAIL_BUILD:-0}" == "1" ]]; then
  exit 42
fi
SH
  chmod +x "${bin_dir}/make"
}

orchestration_tmp="$(mktemp -d)"
orchestration_project="${orchestration_tmp}/project"
orchestration_bin="${orchestration_tmp}/bin"
orchestration_capture="${orchestration_tmp}/commands.log"
orchestration_report="${orchestration_project}/release-rehearsal-report.md"
prepare_orchestration_project "${orchestration_project}"
prepare_orchestration_shims "${orchestration_bin}"

RELEASE_REHEARSAL_CAPTURE="${orchestration_capture}" PATH="${orchestration_bin}:${PATH}" \
  WORKFLOW_RUN_URL=https://github.com/pnetcloud/containers/actions/runs/1234567890 \
  "${SCRIPT}" --dry-run --date 20260609 --checkout-root "${orchestration_project}" --report "${orchestration_report}" >/tmp/story-5-9-orchestration.out

# shellcheck disable=SC2016
for token in \
  'make update' \
  'make generate' \
  'make validate' \
  'make matrix' \
  'make bake-print' \
  'make build PG=18 DEBIAN=trixie PLATFORM=linux/amd64' \
  'make smoke PG=18 DEBIAN=trixie PLATFORM=linux/amd64 CHECKS=container' \
  'make smoke PG=18 DEBIAN=trixie PLATFORM=linux/amd64 CHECKS=sql' \
  'make build PG=18 DEBIAN=trixie PLATFORM=linux/arm64' \
  'make smoke PG=18 DEBIAN=trixie PLATFORM=linux/arm64 CHECKS=container' \
  'make smoke PG=18 DEBIAN=trixie PLATFORM=linux/arm64 CHECKS=sql' \
  'make catalog' \
  'validate-docs'; do
  if ! grep -Fq "${token}" "${orchestration_capture}"; then
    diag "release rehearsal orchestration" "${orchestration_capture}" "orchestration runs ${token}" "$(cat "${orchestration_capture}")" "Default release rehearsal must execute commands, not only validate fixture evidence."
    exit 1
  fi
done

dirty_update_capture="${orchestration_tmp}/dirty-update-commands.log"
dirty_update_project="${orchestration_tmp}/dirty-project"
dirty_update_report="${dirty_update_project}/dirty-update-report.md"
prepare_orchestration_project "${dirty_update_project}"
RELEASE_REHEARSAL_DIRTY_UPDATE=1 RELEASE_REHEARSAL_CAPTURE="${dirty_update_capture}" PATH="${orchestration_bin}:${PATH}" \
  WORKFLOW_RUN_URL=https://github.com/pnetcloud/containers/actions/runs/1234567890 \
  "${SCRIPT}" --dry-run --date 20260609 --checkout-root "${dirty_update_project}" --report "${dirty_update_report}" >/tmp/story-5-9-dirty-update.out
if [[ -e "${dirty_update_project}/cloudnative-pg-timescaledb/generated/dirty-update-marker" ]]; then
  diag "release rehearsal dirty update reset" "${dirty_update_project}/cloudnative-pg-timescaledb/generated/dirty-update-marker" "marker removed before validate" "still exists" "Reset the rehearsal checkout after make update before running clean-checkout validation gates."
  exit 1
fi
if ! grep -Fq 'make validate' "${dirty_update_capture}"; then
  diag "release rehearsal dirty update reset" "${dirty_update_capture}" "validate runs after dirty update reset" "$(cat "${dirty_update_capture}")" "Reset update output and continue the clean-checkout validation path."
  exit 1
fi
rm -f "${dirty_update_report}"

# shellcheck disable=SC2016
for token in \
  '# Release Rehearsal Report' \
  'Mode: `dry-run`' \
  'make build PG=18 DEBIAN=trixie PLATFORM=linux/arm64' \
  'https://github.com/pnetcloud/containers/actions/runs/1234567890'; do
  if ! grep -Fq "${token}" "${orchestration_report}"; then
    diag "release rehearsal orchestration report" "${orchestration_report}" "report includes ${token}" "$(cat "${orchestration_report}" 2>/dev/null || true)" "Default release rehearsal must write an uploadable report after executed commands."
    exit 1
  fi
done
rm -f "${orchestration_report}"

default_report_capture="${orchestration_tmp}/default-report-commands.log"
RELEASE_REHEARSAL_CAPTURE="${default_report_capture}" PATH="${orchestration_bin}:${PATH}" \
  WORKFLOW_RUN_URL=https://github.com/pnetcloud/containers/actions/runs/1234567890 \
  "${SCRIPT}" --dry-run --date 20260609 --checkout-root "${orchestration_project}" >/tmp/story-5-9-default-report.out

if ! grep -Fq 'report=cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md' /tmp/story-5-9-default-report.out; then
  diag "release rehearsal default report path" "/tmp/story-5-9-default-report.out" "default report path is the generated report file" "$(cat /tmp/story-5-9-default-report.out)" "Read the top-level release rehearsal report path from config before writing the default report."
  exit 1
fi
rm -f "${orchestration_project}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md"

outside_report="${orchestration_tmp}/outside-report.md"
set +e
RELEASE_REHEARSAL_CAPTURE="${orchestration_tmp}/outside-report-commands.log" PATH="${orchestration_bin}:${PATH}" \
  "${SCRIPT}" --dry-run --date 20260609 --checkout-root "${orchestration_project}" --report "${outside_report}" >/tmp/story-5-9-outside-report.out 2>&1
outside_status="$?"
set -e
if [[ "${outside_status}" == "0" ]]; then
  diag "release rehearsal outside report path" "${outside_report}" "outside report path fails" "passed" "Keep release rehearsal reports inside the checked-out project."
  exit 1
fi
if ! grep -Fq 'report path stays inside release rehearsal output root' /tmp/story-5-9-outside-report.out; then
  diag "release rehearsal outside report path" "/tmp/story-5-9-outside-report.out" "structured containment diagnostic" "$(cat /tmp/story-5-9-outside-report.out)" "Reject report paths outside the checkout before writing release evidence."
  exit 1
fi

deterministic_report_a="${orchestration_project}/deterministic-a.md"
deterministic_report_b="${orchestration_project}/deterministic-b.md"
deterministic_copy_a="${orchestration_tmp}/deterministic-a.md"
deterministic_copy_b="${orchestration_tmp}/deterministic-b.md"
RELEASE_REHEARSAL_CAPTURE="${orchestration_tmp}/deterministic-a-commands.log" PATH="${orchestration_bin}:${PATH}" \
  WORKFLOW_RUN_URL=https://github.com/pnetcloud/containers/actions/runs/1234567890 \
  "${SCRIPT}" --dry-run --date 20260609 --checkout-root "${orchestration_project}" --report "${deterministic_report_a}" >/tmp/story-5-9-deterministic-a.out
cp "${deterministic_report_a}" "${deterministic_copy_a}"
rm -f "${deterministic_report_a}"
RELEASE_REHEARSAL_CAPTURE="${orchestration_tmp}/deterministic-b-commands.log" PATH="${orchestration_bin}:${PATH}" \
  WORKFLOW_RUN_URL=https://github.com/pnetcloud/containers/actions/runs/1234567890 \
  "${SCRIPT}" --dry-run --date 20260609 --checkout-root "${orchestration_project}" --report "${deterministic_report_b}" >/tmp/story-5-9-deterministic-b.out
cp "${deterministic_report_b}" "${deterministic_copy_b}"
rm -f "${deterministic_report_b}"
if ! diff -u "${deterministic_copy_a}" "${deterministic_copy_b}" >/tmp/story-5-9-deterministic-report.diff; then
  diag "release rehearsal deterministic report" "${deterministic_copy_a} ${deterministic_copy_b}" "same inputs produce byte-identical report" "$(cat /tmp/story-5-9-deterministic-report.diff)" "Do not include elapsed time or temporary log paths in the committed release rehearsal report."
  exit 1
fi

symlink_capture="${orchestration_tmp}/symlink-report-commands.log"
symlink_target="${orchestration_tmp}/outside-report.md"
ln -s "${symlink_target}" "${orchestration_project}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md"
set +e
RELEASE_REHEARSAL_CAPTURE="${symlink_capture}" PATH="${orchestration_bin}:${PATH}" \
  "${SCRIPT}" --dry-run --date 20260609 --checkout-root "${orchestration_project}" >/tmp/story-5-9-symlink-report.out 2>&1
symlink_status="$?"
set -e
if [[ "${symlink_status}" == "0" ]]; then
  diag "release rehearsal report symlink" "${orchestration_project}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md" "symlink report path fails" "passed" "Do not follow report symlinks outside the checkout."
  exit 1
fi
if ! grep -Eq 'report file is not a symlink|report path stays inside release rehearsal output root' /tmp/story-5-9-symlink-report.out; then
  diag "release rehearsal report symlink" "/tmp/story-5-9-symlink-report.out" "structured symlink diagnostic" "$(cat /tmp/story-5-9-symlink-report.out)" "Reject report symlinks before writing release evidence."
  exit 1
fi
rm -f "${orchestration_project}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md" "${symlink_target}"

fail_capture="${orchestration_tmp}/fail-commands.log"
set +e
RELEASE_REHEARSAL_CAPTURE="${fail_capture}" RELEASE_REHEARSAL_FAIL_BUILD=1 PATH="${orchestration_bin}:${PATH}" \
  "${SCRIPT}" --dry-run --date 20260609 --checkout-root "${orchestration_project}" --no-report >/tmp/story-5-9-orchestration-fail.out 2>&1
fail_status="$?"
set -e
if [[ "${fail_status}" == "0" ]]; then
  diag "release rehearsal orchestration fail-fast" "build step" "non-zero exit" "exit 0" "Fail the release rehearsal when any required command fails."
  exit 1
fi
if grep -Fq 'make smoke' "${fail_capture}"; then
  diag "release rehearsal orchestration fail-fast" "${fail_capture}" "no smoke after failed build" "$(cat "${fail_capture}")" "Stop after the first failed release gate."
  exit 1
fi
if ! grep -Fq 'command exits 0' /tmp/story-5-9-orchestration-fail.out; then
  diag "release rehearsal orchestration diagnostics" "/tmp/story-5-9-orchestration-fail.out" "structured failure diagnostic" "$(cat /tmp/story-5-9-orchestration-fail.out)" "Keep orchestration failures actionable."
  exit 1
fi

printf 'PASS story-5.9 release rehearsal fixtures\n'
