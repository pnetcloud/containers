#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

output="$(make -C "${ROOT_DIR}" help)"

for target in help update generate validate matrix bake-print catalog build smoke; do
  if ! grep -Eq "(^|[[:space:]])${target}([[:space:]]|$)" <<<"${output}"; then
    diag "make help" "Makefile help output" "target ${target} listed" "${output}" "Add the missing target to the delegated help script."
    exit 1
  fi
done

for token in "PG:     17, 18, 19beta1" "DEBIAN: trixie, bookworm" "64 missing" "65 unsupported" "69 target behavior"; do
  if ! grep -Fq "${token}" <<<"${output}"; then
    diag "make help" "Makefile help output" "${token}" "${output}" "Document supported parameters and controlled exit codes."
    exit 1
  fi
done

printf 'PASS story-1.2 make help\n'
