#!/usr/bin/env bash
set -Eeuo pipefail

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

if [[ "$#" -ne 4 ]]; then
  diag "verify-package-install" "arguments" "timescaledb package/version and toolkit package/version" "$# arguments" "Pass exactly: <timescaledb_package_name> <timescaledb_package_version> <toolkit_package_name> <toolkit_package_version>."
  exit 64
fi

timescaledb_package_name="$1"
timescaledb_package_version="$2"
toolkit_package_name="$3"
toolkit_package_version="$4"

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

verify_exact_package "${timescaledb_package_name}" "${timescaledb_package_version}"
verify_exact_package "${toolkit_package_name}" "${toolkit_package_version}"

printf 'PASS verify-package-install %s %s\n' "${timescaledb_package_name}" "${toolkit_package_name}"
