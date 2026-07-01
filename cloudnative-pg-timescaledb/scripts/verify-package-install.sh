#!/usr/bin/env bash
set -Eeuo pipefail

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

if [[ "$#" -lt 4 || $(( $# % 2 )) -ne 0 ]]; then
  diag "verify-package-install" "arguments" "one or more package/version pairs" "$# arguments" "Pass package/version pairs, for example: <timescaledb_package_name> <timescaledb_package_version> <loader_package_name> <loader_package_version> <toolkit_package_name> <toolkit_package_version>."
  exit 64
fi

verify_exact_package() {
  local package_name="$1"
  local expected_version="$2"
  local actual_version
  if [[ -z "${package_name}" || -z "${expected_version}" ]]; then
    diag "verify-package-install" "${package_name:-missing-package-name}" "non-empty package name and version" "name=${package_name:-}; version=${expected_version:-}" "Resolve package names and exact versions before building publishable images."
    exit 1
  fi
  if ! actual_version="$(dpkg-query -W -f='${Version}' "${package_name}" 2>/tmp/verify-package-install.err)"; then
    diag "verify-package-install" "${package_name}" "installed Debian package" "$(cat /tmp/verify-package-install.err)" "Install the exact package before verification."
    exit 1
  fi
  if [[ "${actual_version}" != "${expected_version}" ]]; then
    diag "verify-package-install" "${package_name}" "version ${expected_version}" "version ${actual_version}" "Install the package version recorded in versions.yaml."
    exit 1
  fi
}

verified_packages=()
while [[ "$#" -gt 0 ]]; do
  package_name="$1"
  package_version="$2"
  verify_exact_package "${package_name}" "${package_version}"
  verified_packages+=("${package_name}")
  shift 2
done

printf 'PASS verify-package-install %s\n' "${verified_packages[*]}"
