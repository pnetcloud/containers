#!/usr/bin/env bash
set -Eeuo pipefail

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

if [[ "$#" -eq 0 ]]; then
  diag "ci-apt-install" "package arguments" "at least one package" "none" "Pass the Debian packages needed by the workflow step."
  exit 64
fi

attempts="${APT_RETRY_ATTEMPTS:-5}"
delay="${APT_RETRY_DELAY_SECONDS:-10}"
if [[ ! "${attempts}" =~ ^[1-9][0-9]*$ || ! "${delay}" =~ ^[0-9]+$ ]]; then
  diag "ci-apt-install" "retry configuration" "positive integer attempts and non-negative integer delay" "APT_RETRY_ATTEMPTS=${attempts} APT_RETRY_DELAY_SECONDS=${delay}" "Use numeric retry environment values."
  exit 64
fi

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

retry_as_root() {
  local attempt status sleep_seconds
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    as_root "$@" && return 0
    status="$?"
    if ((attempt == attempts)); then
      printf 'apt command failed after %s attempts: %q' "${attempts}" "$1" >&2
      shift || true
      printf ' %q' "$@" >&2
      printf '\n' >&2
      return "${status}"
    fi
    sleep_seconds=$((delay * attempt))
    printf 'apt command failed with exit %s; retry %s/%s in %ss\n' "${status}" "$((attempt + 1))" "${attempts}" "${sleep_seconds}" >&2
    sleep "${sleep_seconds}"
  done
}

export DEBIAN_FRONTEND=noninteractive
retry_as_root apt-get update
retry_as_root apt-get install -y --no-install-recommends "$@"
