#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cloudnative-pg-timescaledb/scripts/lib/command.sh
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

if (( $# > 0 )); then
  if [[ "$#" -ne 1 || "$1" != "--check" ]]; then
    diag "make generate" "GENERATE_ARGS" "empty or --check only" "$*" "Use make generate for the default transactional write path, make generate GENERATE_ARGS=--check for drift checks, or call the specific generator script directly for custom outputs."
    exit "${EXIT_USAGE}"
  fi
  for script in generate-dockerfiles.sh generate-bake.sh generate-matrix.sh generate-catalog.sh generate-docs.sh; do
    "${SCRIPT_DIR}/${script}" --check
  done
  exit 0
fi

tmpdir="$(mktemp -d)"
backup_dir="$(mktemp -d)"
promoting=0
cleanup() {
  local status="$?"
  if (( status != 0 && promoting == 1 )); then
    rm -rf \
      "${SCRIPT_DIR}/../generated" \
      "${SCRIPT_DIR}/../docker-bake.hcl" \
      "${SCRIPT_DIR}/../matrix.json" \
      "${SCRIPT_DIR}/../catalog" \
      "${SCRIPT_DIR}/../docs/generated"
    for name in generated docker-bake.hcl matrix.json catalog docs-generated; do
      if [[ -e "${backup_dir}/${name}" ]]; then
        case "${name}" in
          docs-generated)
            mkdir -p "${SCRIPT_DIR}/../docs"
            mv "${backup_dir}/${name}" "${SCRIPT_DIR}/../docs/generated"
            ;;
          *)
            mv "${backup_dir}/${name}" "${SCRIPT_DIR}/../${name}"
            ;;
        esac
      fi
    done
  fi
  rm -rf "${tmpdir}" "${backup_dir}"
}
trap cleanup EXIT

"${SCRIPT_DIR}/generate-dockerfiles.sh" --output "${tmpdir}/generated"
"${SCRIPT_DIR}/generate-bake.sh" --output "${tmpdir}/docker-bake.hcl"
"${SCRIPT_DIR}/generate-matrix.sh" --output "${tmpdir}/matrix.json"
"${SCRIPT_DIR}/generate-catalog.sh" --output "${tmpdir}/catalog"
"${SCRIPT_DIR}/generate-docs.sh" --output "${tmpdir}/docs/generated/compatibility.md"

promoting=1
[[ ! -e "${SCRIPT_DIR}/../generated" ]] || mv "${SCRIPT_DIR}/../generated" "${backup_dir}/generated"
[[ ! -e "${SCRIPT_DIR}/../docker-bake.hcl" ]] || mv "${SCRIPT_DIR}/../docker-bake.hcl" "${backup_dir}/docker-bake.hcl"
[[ ! -e "${SCRIPT_DIR}/../matrix.json" ]] || mv "${SCRIPT_DIR}/../matrix.json" "${backup_dir}/matrix.json"
[[ ! -e "${SCRIPT_DIR}/../catalog" ]] || mv "${SCRIPT_DIR}/../catalog" "${backup_dir}/catalog"
if [[ -e "${SCRIPT_DIR}/../docs/generated" ]]; then
  mkdir -p "${backup_dir}"
  mv "${SCRIPT_DIR}/../docs/generated" "${backup_dir}/docs-generated"
fi

mkdir -p "${SCRIPT_DIR}/../docs"
mv "${tmpdir}/generated" "${SCRIPT_DIR}/../generated"
mv "${tmpdir}/docker-bake.hcl" "${SCRIPT_DIR}/../docker-bake.hcl"
mv "${tmpdir}/matrix.json" "${SCRIPT_DIR}/../matrix.json"
mv "${tmpdir}/catalog" "${SCRIPT_DIR}/../catalog"
mkdir -p "${SCRIPT_DIR}/../docs/generated"
if [[ -e "${backup_dir}/docs-generated" ]]; then
  cp -a "${backup_dir}/docs-generated/." "${SCRIPT_DIR}/../docs/generated/"
fi
cp -a "${tmpdir}/docs/generated/." "${SCRIPT_DIR}/../docs/generated/"
promoting=0
