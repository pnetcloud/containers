#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"
export PYTHONDONTWRITEBYTECODE=1
# shellcheck source=cloudnative-pg-timescaledb/scripts/lib/common.sh
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
  local expected_doc expected_diff
  expected_doc="$(mktemp)"
  expected_diff="$(mktemp)"
  cat >"${expected_doc}" <<'EOF'
# Generator Contracts

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for image generator inputs. Generator scripts derive Dockerfile paths or skipped markers, Bake targets, matrix rows, stable catalog paths, and generated documentation from that metadata and release metadata.

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
{"dockerfiles":[{"pg_major":"18","debian_variant":"trixie","dockerfile":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile","skipped_marker":"","base_image":"ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie@sha256:...","source_entry":"18-trixie","publish":true,"experimental":false,"skip_reason":""}]}
```

Consumers must require `pg_major`, `debian_variant`, `dockerfile`, `skipped_marker`, `base_image`, `source_entry`, `publish`, `experimental`, and `skip_reason` for every row. Publishable rows expose `dockerfile` and `base_image` and leave `skipped_marker` empty. Skipped rows expose `skipped_marker` and leave `dockerfile` and `base_image` empty so non-publishable rows cannot be built accidentally.

## Bake

Command: `cloudnative-pg-timescaledb/scripts/generate-bake.sh`

Default output: `cloudnative-pg-timescaledb/docker-bake.hcl`

Required JSON keys:

```json
{"bake_file":"cloudnative-pg-timescaledb/docker-bake.hcl","targets":[],"skipped":[]}
```

Consumers must require `bake_file` plus target `name`, `context`, `dockerfile`, `platforms`, `publish`, and `experimental` for every target. The buildable target list contains only publishable entries. Skipped rows remain in `skipped[]` with `pg_major`, `debian_variant`, `name`, `skipped_marker`, `publish`, `experimental`, and `skip_reason`.

## Matrix

Command: `cloudnative-pg-timescaledb/scripts/generate-matrix.sh`

Default outputs: `cloudnative-pg-timescaledb/matrix.json` and `cloudnative-pg-timescaledb/docs/generated/matrix-schema.md`

Required JSON keys:

```json
{"include":[{"bake_target":"pg18-trixie","candidate_ref":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609","debian_variant":"trixie","digest":"","dockerfile":"cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile","experimental":false,"image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb","intended_tags":["18","18-pg18.4-ts2.27.2-20260609","latest"],"latest_eligible":true,"pg_major":"18","pg_version":"18.4","platforms":["linux/amd64","linux/arm64"],"provenance_ref":"","publish":true,"sbom_ref":"","scan_result":"pending","signature_ref":"","timescaledb_version":"2.27.2"}],"skipped":[{"bake_target":"pg19beta1-trixie","debian_variant":"trixie","experimental":true,"latest_eligible":false,"pg_major":"19beta1","pg_version":"19beta1","platforms":["linux/amd64","linux/arm64"],"publish":false,"skip_reason":"Experimental PostgreSQL 19beta1 pending upstream support","skipped_marker":"cloudnative-pg-timescaledb/generated/19beta1/trixie/Dockerfile.skipped.json"}]}
```

Consumers must require `include[]` rows with `pg_major`, `pg_version`, `timescaledb_version`, `debian_variant`, `image`, `candidate_ref`, `digest`, `platforms`, `bake_target`, `dockerfile`, `intended_tags`, `publish`, `experimental`, `latest_eligible`, `scan_result`, `sbom_ref`, `provenance_ref`, and `signature_ref`. Skipped rows must require `pg_major`, `pg_version`, `debian_variant`, `platforms`, `bake_target`, `skipped_marker`, `publish`, `experimental`, `latest_eligible`, and `skip_reason` and must expose marker paths, not buildable Dockerfile paths. Generator summaries preserve metadata `latest_eligible`; workflow validators reject skipped rows that try to own `latest` and require the sole publishable `latest_eligible: true` row to be PostgreSQL `18` on Debian `trixie`.

## Catalog

Command: `cloudnative-pg-timescaledb/scripts/generate-catalog.sh`

Default output root: `cloudnative-pg-timescaledb/catalog/`

Required JSON keys:

```json
{"catalogs":[{"debian_variant":"trixie","catalog_path":"cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml","entries":[{"pg_major":"18","debian_variant":"trixie","image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-00000000","digest":"","publish":true,"experimental":false,"latest_eligible":true,"skip_reason":""}]},{"debian_variant":"bookworm","catalog_path":"cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml","entries":[{"pg_major":"18","debian_variant":"bookworm","image":"ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-00000000-bookworm","digest":"","publish":true,"experimental":false,"latest_eligible":false,"skip_reason":""}]}]}
```

Consumers must require top-level `catalogs[]` rows with `debian_variant`, `catalog_path`, and `entries`. Catalog JSON entries always include metadata-derived `pg_major`, `debian_variant`, `image`, `digest`, `publish`, `experimental`, `latest_eligible`, and `skip_reason`; without release-complete metadata, `digest` is empty and the rendered stable catalog YAML intentionally contains `spec.images: []`. When `--release-metadata` is supplied, each release-complete catalog entry must also require numeric `major`, immutable `tag`, `source_entry`, `platforms`, and `release_metadata_record_id`. Stable catalog YAML contains only release-complete PostgreSQL `17` and `18` rows for their matching Debian variant; experimental PostgreSQL `19beta1` stays out of stable catalogs unless a later explicit experimental catalog is introduced.

The catalog generator still preserves the Story 1.5 metadata-derived contract by keeping every JSON row tied to the metadata variant. Metadata-only JSON rows may include placeholder tag references with empty `digest`; they are summaries, not release catalog candidates. Stable `ClusterImageCatalog` YAML entries are emitted only after the publish workflow supplies the digest, immutable tag, platform digest set, signature, SBOM, provenance, and release metadata record that prove the row is safe to reference from CloudNativePG.

## Docs

Command: `cloudnative-pg-timescaledb/scripts/generate-docs.sh`

Default output: `cloudnative-pg-timescaledb/docs/generated/compatibility.md` plus generated docs owned by the docs generator in the same directory: `compatibility-table.md`, `release-candidate-schema.md`, `release-evidence-schema.md`, `failure-reason-catalog.md`, and `barman-plugin-reference.md` when CloudNativePG Barman Cloud Plugin metadata exists. The generated docs manifest also enumerates `matrix-schema.md` from `generate-matrix.sh` and `release-rehearsal-report.md` from `release-rehearsal.sh` so drift validation and autocommit paths cover the full generated docs set.

Required JSON keys (abridged example; the manifest list in generated output is canonical and must enumerate every generated docs artifact in contract order):

```json
{"docs":[{"doc_path":"cloudnative-pg-timescaledb/docs/generated/compatibility.md","companion_paths":["cloudnative-pg-timescaledb/docs/generated/compatibility-table.md"],"source":"cloudnative-pg-timescaledb/versions.yaml","sections":["compatibility"],"publishable_entries":4,"experimental_entries":2}],"generated_docs_manifest":[{"path":"cloudnative-pg-timescaledb/docs/generated/compatibility.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"1.5","deterministic_generation_mode":"metadata-rendered compatibility skeleton"},{"path":"cloudnative-pg-timescaledb/docs/generated/compatibility-table.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"5.1","deterministic_generation_mode":"metadata-rendered compatibility table"},{"path":"cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"4.2","deterministic_generation_mode":"static generated schema documentation"},{"path":"cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"4.4","deterministic_generation_mode":"static generated schema documentation"},{"path":"cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"5.8","deterministic_generation_mode":"static generated failure reason catalog"},{"path":"cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md","generator_input":"cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/valid-full-matrix.json;cloudnative-pg-timescaledb/config/release-rehearsal.yaml;DATE=20260609;DRY_RUN=1","generator_command":"cloudnative-pg-timescaledb/scripts/release-rehearsal.sh","owner_story":"5.9","deterministic_generation_mode":"dry-run release rehearsal report"},{"path":"cloudnative-pg-timescaledb/docs/generated/matrix-schema.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-matrix.sh","owner_story":"4.1","deterministic_generation_mode":"static generated matrix schema documentation"},{"path":"cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md","generator_input":"cloudnative-pg-timescaledb/versions.yaml","generator_command":"cloudnative-pg-timescaledb/scripts/generate-docs.sh","owner_story":"2.7","deterministic_generation_mode":"metadata-rendered Barman Cloud Plugin reference"}]}
```

Consumers must require `docs[]` rows with `doc_path`, `companion_paths`, `source`, `sections`, `publishable_entries`, and `experimental_entries`. Consumers must also require `generated_docs_manifest[]` rows with `path`, `generator_input`, `generator_command`, `owner_story`, and `deterministic_generation_mode`. `make generate` regenerates the release rehearsal report from deterministic fixture evidence instead of preserving stale docs from a prior checkout.
EOF
  if ! diff -u "${expected_doc}" "${doc_path}" >"${expected_diff}"; then
    diag "validate-generated" "${doc_path}" "docs/generator-contracts.md matches current generator contract" "$(cat "${expected_diff}")" "Restore the canonical generator contract text or update validate-generated.sh with the new reviewed contract."
    rm -f "${expected_doc}" "${expected_diff}"
    exit 1
  fi
  rm -f "${expected_doc}" "${expected_diff}"
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
file_set_diff_tmp="$(mktemp)"
manifest_tmp=""
release_report_tmp="$(mktemp)"
release_report_diff_tmp="$(mktemp)"
cleanup() {
  rm -f "${expected_tmp}" "${actual_tmp}" "${file_set_diff_tmp}" "${release_report_tmp}" "${release_report_diff_tmp}"
  if [[ -n "${manifest_tmp}" ]]; then
    rm -f "${manifest_tmp}"
  fi
}
trap cleanup EXIT

write_manifest_fixture() {
  local metadata_path="$1"
  local fixture_path="$2"
  python3 - "${SCRIPT_DIR}" "${metadata_path}" "${fixture_path}" <<'PY'
import json
import sys
from pathlib import Path

script_dir = Path(sys.argv[1])
metadata = Path(sys.argv[2])
fixture = Path(sys.argv[3])
sys.path.insert(0, str(script_dir / "lib"))
import generator_contract  # noqa: E402

data = generator_contract.parse_metadata(metadata, "validate-generated")
entries = data.get("entries", [])
manifests = []
seen = set()
for entry in entries:
    tag = str(entry.get("cnpg_tag", "")).strip()
    digest = str(entry.get("cnpg_digest", "")).strip()
    platforms = entry.get("platforms", [])
    if not tag or not digest:
        continue
    key = (tag, digest)
    if key in seen:
        continue
    seen.add(key)
    manifests.append({"tag": tag, "digest": digest, "platforms": platforms})
fixture.write_text(json.dumps({"manifests": manifests}, indent=2, sort_keys=True) + "\n")
PY
}

if [[ -z "${CNPG_MANIFEST_FIXTURE:-}" ]]; then
  manifest_tmp="$(mktemp)"
  write_manifest_fixture "${metadata}" "${manifest_tmp}"
  export CNPG_MANIFEST_FIXTURE="${manifest_tmp}"
fi

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
  generated_json="$("${SCRIPT_DIR}"/generate-dockerfiles.sh --metadata "${metadata}" --output "${generated_root}" --json)"
  catalog_json="$("${SCRIPT_DIR}"/generate-catalog.sh --metadata "${metadata}" --output "${catalog_root}" --json)"
  docs_json="$("${SCRIPT_DIR}"/generate-docs.sh --metadata "${metadata}" --output "${docs_file}" --json)"
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
        for companion in row.get("companion_paths", []):
            print(companion)
    for row in data.get("generated_docs_manifest", []):
        print(row["path"])
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

catalog_release_metadata_args() {
  local metadata_dir release_metadata_dir
  metadata_dir="$(cd "$(dirname "${metadata}")" && pwd)"
  release_metadata_dir="${metadata_dir}/release-metadata"
  if compgen -G "${release_metadata_dir}/*.json" >/dev/null; then
    printf '%s\0%s\0' --release-metadata "${release_metadata_dir}"
  fi
}

mapfile -d '' -t catalog_release_metadata_args_array < <(catalog_release_metadata_args)

collect_expected_files | sort -u >"${expected_tmp}"
collect_actual_files | sort >"${actual_tmp}"
if ! diff -u "${expected_tmp}" "${actual_tmp}" >"${file_set_diff_tmp}"; then
  diag "validate-generated" "generated artifact file set" "actual generated files exactly match generator contract" "$(cat "${file_set_diff_tmp}")" "Remove stale generated artifacts or run make generate after updating metadata/generators."
  exit 1
fi

"${SCRIPT_DIR}/generate-dockerfiles.sh" --metadata "${metadata}" --output "${generated_root}" --check
"${SCRIPT_DIR}/generate-bake.sh" --metadata "${metadata}" --output "${bake_file}" --check
"${SCRIPT_DIR}/generate-matrix.sh" --metadata "${metadata}" --output "${matrix_file}" --check
"${SCRIPT_DIR}/generate-catalog.sh" --metadata "${metadata}" "${catalog_release_metadata_args_array[@]}" --output "${catalog_root}" --check
"${SCRIPT_DIR}/generate-docs.sh" --metadata "${metadata}" --output "${docs_file}" --check
if ! "${SCRIPT_DIR}/release-rehearsal.sh" \
  --fixture "${SCRIPT_DIR}/../tests/release-rehearsal/fixtures/valid-full-matrix.json" \
  --date 20260609 \
  --dry-run \
  --report "${release_report_tmp}" \
  >/dev/null; then
  diag "validate-generated" "cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md" "release rehearsal report can be generated" "failed" "Fix release rehearsal fixture/config inputs before validating generated report drift."
  exit 1
fi
release_report_file="$(dirname "${docs_file}")/release-rehearsal-report.md"
if ! diff -u "${release_report_tmp}" "${release_report_file}" >"${release_report_diff_tmp}"; then
  diag "validate-generated" "${release_report_file}" "committed output matches generated content" "$(cat "${release_report_diff_tmp}")" "Run make generate and commit the regenerated release rehearsal report."
  exit 1
fi

printf 'PASS validate-generated Epic 1 skeleton drift\n'
