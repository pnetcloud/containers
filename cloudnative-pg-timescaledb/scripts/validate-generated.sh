#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"
source "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/lib/common.sh"

contract_root="${ROOT_DIR}"
metadata="${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml"
generated_root="cloudnative-pg-timescaledb/generated"
bake_file="cloudnative-pg-timescaledb/docker-bake.hcl"
matrix_file="cloudnative-pg-timescaledb/matrix.json"
catalog_root="cloudnative-pg-timescaledb/catalog"
docs_file="cloudnative-pg-timescaledb/docs/generated/compatibility.md"

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "${value}" ]]; then
    diag "validate-generated" "arguments" "${option} has a value" "missing" "Pass ${option} <path>."
    exit 64
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --metadata)
      require_value "$1" "${2:-}"
      metadata="${2:-}"
      shift 2
      ;;
    --contract-root)
      require_value "$1" "${2:-}"
      contract_root="${2:-}"
      shift 2
      ;;
    --generated-root)
      require_value "$1" "${2:-}"
      generated_root="${2:-}"
      shift 2
      ;;
    --bake-file)
      require_value "$1" "${2:-}"
      bake_file="${2:-}"
      shift 2
      ;;
    --matrix-file)
      require_value "$1" "${2:-}"
      matrix_file="${2:-}"
      shift 2
      ;;
    --catalog-root)
      require_value "$1" "${2:-}"
      catalog_root="${2:-}"
      shift 2
      ;;
    --docs-file)
      require_value "$1" "${2:-}"
      docs_file="${2:-}"
      shift 2
      ;;
    *)
      diag "validate-generated" "arguments" "known validate-generated option" "$1" "Use --metadata, --contract-root, --generated-root, --bake-file, --matrix-file, --catalog-root, or --docs-file."
      exit 64
      ;;
  esac
done

contract_script_dir="${contract_root}/cloudnative-pg-timescaledb/scripts"

required_paths=(
  "docs/generator-contracts.md"
  "cloudnative-pg-timescaledb/tests/generators/run.sh"
  "cloudnative-pg-timescaledb/tests/generators/fixtures/generate-dockerfiles-valid.json"
  "cloudnative-pg-timescaledb/tests/generators/fixtures/generate-bake-valid.json"
  "cloudnative-pg-timescaledb/tests/generators/fixtures/generate-matrix-valid.json"
  "cloudnative-pg-timescaledb/tests/generators/fixtures/generate-catalog-valid.json"
  "cloudnative-pg-timescaledb/tests/generators/fixtures/generate-docs-valid.json"
)

for path in "${required_paths[@]}"; do
  if [[ ! -f "${contract_root}/${path}" ]]; then
    diag "validate-generated" "${path}" "Story 1.5 generator contract artifact exists" "missing" "Restore the generator contract artifact from Story 1.5."
    exit 1
  fi
done

validate_contract_docs() {
  local doc_path="${contract_root}/docs/generator-contracts.md"
  python3 - "${doc_path}" <<'PY'
from pathlib import Path
import difflib
import sys

path = Path(sys.argv[1])
expected = r'''# Generator Contracts

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for image generator inputs. Generator scripts derive Dockerfile paths, Bake targets, matrix rows, catalog skeletons, and generated compatibility docs from that metadata.

All generator scripts support the same interface:

```bash
cloudnative-pg-timescaledb/scripts/<generator>.sh \
  --metadata cloudnative-pg-timescaledb/versions.yaml \
  --output <path> \
  --check \
  --json
```

`--metadata` defaults to `cloudnative-pg-timescaledb/versions.yaml`. `--output` overrides the default output file or root for generators that write a single artifact. `--check` compares generated content with committed output and exits non-zero on drift. `--json` writes compact machine JSON to stdout. Human diagnostics go to stderr.

## Dockerfiles

Command: `cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh`

Default output root: `cloudnative-pg-timescaledb/generated/`

Required JSON keys:

```json
{"dockerfiles":[{"pg_major":"18","debian_variant":"trixie","dockerfile":"","skipped_marker":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile.skipped.json","base_image":"","source_entry":"18-trixie","publish":false,"experimental":false,"skip_reason":"Pending Story 2 resolver population"}]}
```

Consumers must require `pg_major`, `debian_variant`, `dockerfile`, `skipped_marker`, `base_image`, `source_entry`, `publish`, `experimental`, and `skip_reason` for every row. Publishable rows expose `dockerfile` and `base_image` and leave `skipped_marker` empty. Skipped rows expose `skipped_marker` and leave `dockerfile` and `base_image` empty.

## Bake

Command: `cloudnative-pg-timescaledb/scripts/generate-bake.sh`

Default output: `cloudnative-pg-timescaledb/docker-bake.hcl`

Required JSON keys:

```json
{"bake_file":"cloudnative-pg-timescaledb/docker-bake.hcl","targets":[]}
```

Consumers must require `bake_file` plus target `name`, `context`, `dockerfile`, `platforms`, `publish`, and `experimental` for every target. The target list contains only publishable entries; it may be empty when all metadata rows are skipped.

## Matrix

Command: `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`

Default output: `cloudnative-pg-timescaledb/matrix.json`

Required JSON keys:

```json
{"include":[{"pg_major":"18","pg_version":"18.4","debian_variant":"trixie","platforms":["linux/amd64","linux/arm64"],"dockerfile":"","skipped_marker":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile.skipped.json","bake_target":"","publish":false,"experimental":false,"latest_eligible":true,"skip_reason":"Pending Story 2 resolver population"}]}
```

Consumers must require `include` rows with `pg_major`, `pg_version`, `debian_variant`, `platforms`, `dockerfile`, `skipped_marker`, `bake_target`, `publish`, `experimental`, `latest_eligible`, and `skip_reason`. Publishable rows expose `dockerfile` and `bake_target`; skipped rows expose `skipped_marker` only. Consumers must reject rows where `18-trixie` is not the sole `latest_eligible: true` row.

## Catalog

Command: `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`

Default output root: `cloudnative-pg-timescaledb/catalog/`

Required JSON keys:

```json
{"catalogs":[{"debian_variant":"trixie","catalog_path":"cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml","entries":[{"pg_major":"18","image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18-tsunresolved-00000000","digest":"","publish":false,"experimental":false,"latest_eligible":true,"skip_reason":"Pending Story 2 resolver population"}]}]}
```

Consumers must require `debian_variant`, `catalog_path`, and entry `pg_major`, `image`, `digest`, `publish`, `experimental`, `latest_eligible`, and `skip_reason`. Catalog generators preserve metadata `latest_eligible`; final digest-aware catalog behavior is owned by Story 4.6.

## Docs

Command: `cloudnative-pg-timescaledb/scripts/generate-docs.sh`

Default output: `cloudnative-pg-timescaledb/docs/generated/compatibility.md`

Required JSON keys:

```json
{"docs":[{"doc_path":"cloudnative-pg-timescaledb/docs/generated/compatibility.md","source":"cloudnative-pg-timescaledb/versions.yaml","sections":["compatibility"],"publishable_entries":0,"experimental_entries":2}]}
```

Consumers must require `doc_path`, `source`, `sections`, `publishable_entries`, and `experimental_entries`. Final public documentation validation is owned by Epic 5.
'''
actual = path.read_text()
if actual != expected:
    diff = ''.join(difflib.unified_diff(actual.splitlines(True), expected.splitlines(True), fromfile=str(path), tofile='expected-generator-contracts.md'))
    raise SystemExit(
        f"command: validate-generated\n"
        f"artifact: {path}\n"
        f"expected: docs/generator-contracts.md matches Story 1.5 generator contract\n"
        f"actual: {diff[:1200]}\n"
        f"remediation: Restore the documented generator contract content from Story 1.5."
    )
PY
}

validate_contract_docs

generators=(
  generate-dockerfiles.sh
  generate-bake.sh
  generate-matrix.sh
  generate-catalog.sh
  generate-docs.sh
)

for script in "${generators[@]}"; do
  if [[ ! -x "${contract_script_dir}/${script}" ]]; then
    diag "validate-generated" "cloudnative-pg-timescaledb/scripts/${script}" "generator entrypoint is executable" "missing or not executable" "Restore executable generator scripts and run make generate."
    exit 1
  fi
done

expected_tmp="$(mktemp)"
actual_tmp="$(mktemp)"
cleanup() {
  rm -f "${expected_tmp}" "${actual_tmp}"
}
trap cleanup EXIT

rel_path() {
  local path="$1"
  python3 - "$path" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
try:
    print(path.resolve().relative_to(Path.cwd().resolve()))
except ValueError:
    print(path)
PY
}

collect_expected_files() {
  local generated_json catalog_json docs_json
  generated_json="$(${SCRIPT_DIR}/generate-dockerfiles.sh --metadata "${metadata}" --output "${generated_root}" --json)"
  catalog_json="$(${SCRIPT_DIR}/generate-catalog.sh --metadata "${metadata}" --output "${catalog_root}" --json)"
  docs_json="$(${SCRIPT_DIR}/generate-docs.sh --metadata "${metadata}" --output "${docs_file}" --json)"
  python3 - "${metadata}" "${docs_file}" "${generated_json}" "${catalog_json}" "${docs_json}" <<'PY'
import json
import sys
from pathlib import Path
metadata = Path(sys.argv[1]).read_text()
docs_file = Path(sys.argv[2])
for payload in sys.argv[3:]:
    data = json.loads(payload)
    for row in data.get("dockerfiles", []):
        if row.get("dockerfile"):
            print(row["dockerfile"])
        if row.get("skipped_marker"):
            print(row["skipped_marker"])
    for row in data.get("catalogs", []):
        print(row["catalog_path"])
    for row in data.get("docs", []):
        print(row["doc_path"])
if "\nbarman_plugin:" in "\n" + metadata:
    print((docs_file.parent / "barman-plugin-reference.md").as_posix())
PY
}

collect_actual_files() {
  local path
  if [[ -d "${generated_root}" ]]; then
    while IFS= read -r -d '' path; do
      rel_path "${path}"
    done < <(find "${generated_root}" -type f \( -name Dockerfile -o -name Dockerfile.skipped.json \) -print0)
  fi
  if [[ -d "${catalog_root}" ]]; then
    while IFS= read -r -d '' path; do
      rel_path "${path}"
    done < <(find "${catalog_root}" -type f -name 'catalog-standard-*.yaml' -print0)
  fi
  docs_dir="$(dirname "${docs_file}")"
  if [[ -d "${docs_dir}" ]]; then
    while IFS= read -r -d '' path; do
      rel_path "${path}"
    done < <(find "${docs_dir}" -maxdepth 1 -type f -name '*.md' -print0)
  fi
}

collect_expected_files | sort >"${expected_tmp}"
collect_actual_files | sort >"${actual_tmp}"
if ! diff -u "${expected_tmp}" "${actual_tmp}" >/tmp/validate-generated-file-set.diff; then
  diag "validate-generated" "generated artifact file set" "actual generated files exactly match generator contract" "$(cat /tmp/validate-generated-file-set.diff)" "Remove stale generated artifacts or run make generate after updating metadata/generators."
  exit 1
fi

"${SCRIPT_DIR}/generate-dockerfiles.sh" --metadata "${metadata}" --output "${generated_root}" --check
"${SCRIPT_DIR}/generate-bake.sh" --metadata "${metadata}" --output "${bake_file}" --check
"${SCRIPT_DIR}/generate-matrix.sh" --metadata "${metadata}" --output "${matrix_file}" --check
"${SCRIPT_DIR}/generate-catalog.sh" --metadata "${metadata}" --output "${catalog_root}" --check
"${SCRIPT_DIR}/generate-docs.sh" --metadata "${metadata}" --output "${docs_file}" --check

printf 'PASS validate-generated Epic 1 skeleton drift\n'
