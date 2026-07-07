#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

version="${COSIGN_VERSION:-v3.1.1}"
default_install_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pnet-cosign/bin"
install_dir="${COSIGN_INSTALL_DIR:-${default_install_dir}}"
arch="${COSIGN_ARCH:-$(uname -m)}"

case "${arch}" in
  x86_64|amd64)
    asset="cosign-linux-amd64"
    expected_sha256="${COSIGN_EXPECTED_SHA256:-ae1ecd212663f3693ad9edf8b1a183900c9a52d3155ba6e354237f9a0f6463fc}"
    ;;
  aarch64|arm64)
    asset="cosign-linux-arm64"
    expected_sha256="${COSIGN_EXPECTED_SHA256:-2ec865872e331c32fd12b08dae15332d3f92c0aa029219589684a4903ca85d11}"
    ;;
  *)
    diag "install-cosign" "runner architecture" "amd64 or arm64" "${arch}" "Run on a supported GitHub-hosted Linux architecture or extend the pinned checksum map."
    exit 64
    ;;
esac

url="${COSIGN_DOWNLOAD_URL:-https://github.com/sigstore/cosign/releases/download/${version}/${asset}}"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

download_path="${tmp_dir}/${asset}"
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/ci-retry.sh" \
  curl --fail --location --silent --show-error --output "${download_path}" "${url}"

if ! printf '%s  %s\n' "${expected_sha256}" "${download_path}" | sha256sum --check --status; then
  actual_sha256="$(sha256sum "${download_path}" | awk '{print $1}')"
  diag "install-cosign" "${url}" "sha256 ${expected_sha256}" "sha256 ${actual_sha256}" "Update the pinned cosign version and checksum together only after reviewing the upstream release."
  exit 1
fi

mkdir -p "${install_dir}"
install -m 0755 "${download_path}" "${install_dir}/cosign"
"${install_dir}/cosign" version >/dev/null
if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "${install_dir}" >>"${GITHUB_PATH}"
fi
printf 'Installed cosign %s to %s/cosign\n' "${version}" "${install_dir}"
