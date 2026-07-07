#!/usr/bin/env bash
set -Eeuo pipefail

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

if [[ "$#" -eq 0 ]]; then
  diag "ci-retry" "command arguments" "at least one command argument" "none" "Pass the CI command that should tolerate transient network failures."
  exit 64
fi

attempts="${CI_RETRY_ATTEMPTS:-5}"
delay="${CI_RETRY_DELAY_SECONDS:-10}"
if [[ ! "${attempts}" =~ ^[1-9][0-9]*$ || ! "${delay}" =~ ^[0-9]+$ ]]; then
  diag "ci-retry" "retry configuration" "positive integer attempts and non-negative integer delay" "CI_RETRY_ATTEMPTS=${attempts} CI_RETRY_DELAY_SECONDS=${delay}" "Use numeric retry environment values."
  exit 64
fi

retry_command() {
  local attempt status sleep_seconds
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    "$@" && return 0
    status="$?"
    if ((attempt == attempts)); then
      printf 'CI command failed after %s attempts: ' "${attempts}" >&2
      printf '%q ' "$@" >&2
      printf '\n' >&2
      return "${status}"
    fi
    sleep_seconds=$((delay * attempt))
    printf 'CI command failed with exit %s; retry %s/%s in %ss: ' "${status}" "$((attempt + 1))" "${attempts}" "${sleep_seconds}" >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    sleep "${sleep_seconds}"
  done
}

retry_command "$@"
