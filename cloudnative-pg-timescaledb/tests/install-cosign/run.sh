#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/install-cosign.sh"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp}"
}
trap cleanup EXIT

mkdir -p "${tmp}/bin" "${tmp}/state" "${tmp}/install"
capture="${tmp}/capture.log"
github_path="${tmp}/github-path"
source_cosign="${tmp}/source-cosign"

cat >"${source_cosign}" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == "version" ]]; then
  printf 'cosign v3.1.1\n'
  exit 0
fi
printf 'unexpected cosign command: %s\n' "$*" >&2
exit 64
SH
chmod +x "${source_cosign}"
expected_sha256="$(sha256sum "${source_cosign}" | awk '{print $1}')"

cat >"${tmp}/bin/curl" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'curl %s\n' "$*" >> "${COSIGN_TEST_CAPTURE:?}"
output=""
url=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --fail|--location|--silent|--show-error)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
count_file="${COSIGN_TEST_STATE:?}/curl-count"
count=0
if [[ -f "${count_file}" ]]; then
  count="$(cat "${count_file}")"
fi
count=$((count + 1))
printf '%s\n' "${count}" > "${count_file}"
if ((count < 3)); then
  exit 56
fi
if [[ -z "${output}" || "${url}" != "https://example.invalid/cosign-linux-amd64" ]]; then
  printf 'unexpected curl output=%s url=%s\n' "${output}" "${url}" >&2
  exit 64
fi
cp "${COSIGN_TEST_SOURCE:?}" "${output}"
SH
chmod +x "${tmp}/bin/curl"

cat >"${tmp}/bin/sleep" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'sleep %s\n' "$*" >> "${COSIGN_TEST_CAPTURE:?}"
SH
chmod +x "${tmp}/bin/sleep"

PATH="${tmp}/bin:${PATH}" \
COSIGN_TEST_CAPTURE="${capture}" \
COSIGN_TEST_STATE="${tmp}/state" \
COSIGN_TEST_SOURCE="${source_cosign}" \
COSIGN_ARCH=amd64 \
COSIGN_DOWNLOAD_URL="https://example.invalid/cosign-linux-amd64" \
COSIGN_EXPECTED_SHA256="${expected_sha256}" \
COSIGN_INSTALL_DIR="${tmp}/install" \
GITHUB_PATH="${github_path}" \
CI_RETRY_ATTEMPTS=3 \
CI_RETRY_DELAY_SECONDS=0 \
  "${SCRIPT}" >/tmp/install-cosign-success.out 2>&1

curl_count="$(grep -c '^curl ' "${capture}")"
sleep_count="$(grep -c '^sleep 0$' "${capture}")"
if [[ "${curl_count}" != "3" || "${sleep_count}" != "2" ]]; then
  diag "install-cosign retry" "${capture}" "download retries twice then succeeds" "curl=${curl_count} sleep=${sleep_count}: $(tr '\n' ';' <"${capture}")" "Keep cosign installation wrapped in ci-retry.sh so transient GitHub release download failures do not fail release jobs."
  exit 1
fi
if [[ ! -x "${tmp}/install/cosign" ]]; then
  diag "test -x" "${tmp}/install/cosign" "installed executable cosign" "missing or not executable" "Install the verified cosign binary into the requested install directory."
  exit 1
fi
if ! "${tmp}/install/cosign" version >/tmp/install-cosign-version.out; then
  diag "cosign version" "${tmp}/install/cosign" "installed cosign runs" "$(cat /tmp/install-cosign-version.out)" "Run a post-install cosign version check before release signing jobs continue."
  exit 1
fi
if ! grep -Fxq "${tmp}/install" "${github_path}"; then
  diag "install-cosign GitHub path" "${github_path}" "install directory exported for later workflow steps" "$(cat "${github_path}")" "Append the cosign install directory to GITHUB_PATH so later release steps can run cosign."
  exit 1
fi

bad_out="${tmp}/bad-checksum.out"
mkdir -p "${tmp}/bad-state"
printf '2\n' > "${tmp}/bad-state/curl-count"
if PATH="${tmp}/bin:${PATH}" \
  COSIGN_TEST_CAPTURE="${capture}" \
  COSIGN_TEST_STATE="${tmp}/bad-state" \
  COSIGN_TEST_SOURCE="${source_cosign}" \
  COSIGN_ARCH=amd64 \
  COSIGN_DOWNLOAD_URL="https://example.invalid/cosign-linux-amd64" \
  COSIGN_EXPECTED_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
  COSIGN_INSTALL_DIR="${tmp}/bad-install" \
  CI_RETRY_ATTEMPTS=1 \
  CI_RETRY_DELAY_SECONDS=0 \
    "${SCRIPT}" >"${bad_out}" 2>&1; then
  diag "install-cosign checksum" "${SCRIPT}" "bad checksum fails" "exit 0" "Reject downloaded cosign binaries that do not match the pinned release checksum."
  exit 1
fi
if ! grep -Fq 'sha256 0000000000000000000000000000000000000000000000000000000000000000' "${bad_out}"; then
  diag "install-cosign checksum diagnostic" "${bad_out}" "diagnostic includes expected SHA256" "$(cat "${bad_out}")" "Make checksum failures actionable in CI logs."
  exit 1
fi

printf 'PASS cosign install helper\n'
