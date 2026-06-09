#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"

missing=()
for script in generate-dockerfiles.sh generate-bake.sh generate-matrix.sh generate-catalog.sh generate-docs.sh; do
  path="${SCRIPT_DIR}/${script}"
  if [[ ! -x "${path}" ]]; then
    missing+=("${script}")
  fi
done

if (( ${#missing[@]} > 0 )); then
  controlled_unavailable "make generate" "Story 1.5" "Missing generator entry points: ${missing[*]}. Implement generator contracts before using this target."
fi

for script in generate-dockerfiles.sh generate-bake.sh generate-matrix.sh generate-catalog.sh generate-docs.sh; do
  "${SCRIPT_DIR}/${script}" "$@"
done
