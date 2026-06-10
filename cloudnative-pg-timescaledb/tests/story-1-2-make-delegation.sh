#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAKEFILE="${ROOT_DIR}/Makefile"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

for script in make-help.sh update.sh generate.sh validate.sh matrix.sh bake-print.sh catalog.sh build.sh smoke.sh lib/command.sh; do
  path="${SCRIPT_DIR}/${script}"
  if [[ ! -x "${path}" ]]; then
    diag "test -x ${path}" "${path}" "executable script exists" "missing or not executable" "Create executable delegated script entry points."
    exit 1
  fi
done

for target in help update generate validate matrix bake-print catalog build smoke; do
  if ! grep -Eq "^${target}:" "${MAKEFILE}"; then
    diag "grep target ${target}" "Makefile" "target exists" "missing" "Expose the stable root Make target."
    exit 1
  fi
done

for script in make-help update generate validate matrix bake-print catalog build smoke; do
  # The Makefile may use either shell-expanded or Make-expanded SCRIPT_DIR syntax.
  # shellcheck disable=SC2016
  if ! grep -Fq "$(printf '%s' '${SCRIPT_DIR}')/${script}.sh" "${MAKEFILE}" && ! grep -Fq "$(printf '%s' '$(SCRIPT_DIR)')/${script}.sh" "${MAKEFILE}"; then
    diag "grep delegated script ${script}" "Makefile" "Makefile delegates to ${script}.sh" "delegation not found" "Keep root Makefile as a thin script facade."
    exit 1
  fi
done

if grep -Eq 'packagecloud|apt-get|docker buildx|docker build|CREATE EXTENSION|ghcr\.io/.+:' "${MAKEFILE}"; then
  diag "scan Makefile" "Makefile" "no resolver/package/build/publish logic inline" "inline implementation logic found" "Move implementation logic to owned scripts in later stories."
  exit 1
fi

if grep -RIn --exclude-dir=tests --exclude='story-1-2-*' 'vendor/' "${MAKEFILE}" "${SCRIPT_DIR}"; then
  diag "scan command surface" "Makefile and scripts" "no command-surface dependency on reference trees" "reference-tree path found" "Remove command-surface dependency on reference-only inputs."
  exit 1
fi

if ! grep -Fq 'story-1-2-make-help.sh' "${SCRIPT_DIR}/validate.sh" \
  || ! grep -Fq 'story-1-2-make-delegation.sh' "${SCRIPT_DIR}/validate.sh" \
  || ! grep -Fq 'story-1-2-make-params.sh' "${SCRIPT_DIR}/validate.sh"; then
  diag "scan validate.sh" "cloudnative-pg-timescaledb/scripts/validate.sh" "make validate runs Story 1.2 gates" "missing Story 1.2 test delegation" "Call the Story 1.2 tests from scripts/validate.sh."
  exit 1
fi

if [[ "${STORY_1_2_VALIDATE_REENTRY:-0}" != "1" ]]; then
  make -n -C "${ROOT_DIR}" validate >/tmp/story-1-2-validate.out
  if ! grep -Fq 'cloudnative-pg-timescaledb/scripts/validate.sh' /tmp/story-1-2-validate.out; then
    diag "make -n validate" "validate target" "root Makefile delegates validate to scripts/validate.sh" "$(cat /tmp/story-1-2-validate.out)" "Keep make validate as a thin facade over the validation script."
    exit 1
  fi
fi

printf 'PASS story-1.2 make delegation\n'
