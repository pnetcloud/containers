#!/usr/bin/env bash
set -Eeuo pipefail

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

attempts="${CI_RETRY_ATTEMPTS:-5}"
delay="${CI_RETRY_DELAY_SECONDS:-10}"
if [[ ! "${attempts}" =~ ^[1-9][0-9]*$ || ! "${delay}" =~ ^[0-9]+$ ]]; then
  diag "ci-git-push" "retry configuration" "positive integer attempts and non-negative integer delay" "CI_RETRY_ATTEMPTS=${attempts} CI_RETRY_DELAY_SECONDS=${delay}" "Use numeric retry environment values."
  exit 64
fi

fetch_remote="${CI_GIT_PUSH_FETCH_REMOTE:-origin}"
fetch_ref="${CI_GIT_PUSH_FETCH_REF:-}"
rebase_ref="${CI_GIT_PUSH_REBASE_REF:-}"

refresh_and_rebase() {
  if [[ -z "${rebase_ref}" ]]; then
    return 0
  fi
  if [[ -n "${fetch_ref}" ]]; then
    git fetch --no-tags --prune --depth=1 "${fetch_remote}" "${fetch_ref}"
  else
    git fetch --no-tags --prune --depth=1 "${fetch_remote}"
  fi
  git rebase "${rebase_ref}"
}

retry_push() {
  local attempt status sleep_seconds
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if git push "$@"; then
      return 0
    fi
    status="$?"
    if ((attempt == attempts)); then
      printf 'git push failed after %s attempts: git push ' "${attempts}" >&2
      printf '%q ' "$@" >&2
      printf '\n' >&2
      return "${status}"
    fi
    if ! refresh_and_rebase; then
      git rebase --abort >/dev/null 2>&1 || true
    fi
    sleep_seconds=$((delay * attempt))
    printf 'git push failed with exit %s; retry %s/%s in %ss: git push ' "${status}" "$((attempt + 1))" "${attempts}" "${sleep_seconds}" >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    sleep "${sleep_seconds}"
  done
}

retry_push "$@"
