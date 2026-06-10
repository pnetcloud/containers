#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/cloudnative-pg-timescaledb/config/release-rehearsal.yaml"
FIXTURE_FILE=""
REPORT_FILE=""
CHECKOUT_ROOT=""
DATE_VALUE="${DATE:-}"
DRY_RUN_VALUE="${DRY_RUN:-}"
STAGING_NAMESPACE_VALUE="${STAGING_NAMESPACE:-}"
EXPECT_FAILURE="0"
WRITE_REPORT="1"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "${value}" ]]; then
    diag "release-rehearsal" "arguments" "${option} has a value" "missing" "Pass ${option} <value>."
    exit 64
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --config)
      require_value "$1" "${2:-}"
      CONFIG_FILE="$2"
      shift 2
      ;;
    --fixture)
      require_value "$1" "${2:-}"
      FIXTURE_FILE="$2"
      shift 2
      ;;
    --report)
      require_value "$1" "${2:-}"
      REPORT_FILE="$2"
      shift 2
      ;;
    --checkout-root)
      require_value "$1" "${2:-}"
      CHECKOUT_ROOT="$2"
      shift 2
      ;;
    --date)
      require_value "$1" "${2:-}"
      DATE_VALUE="$2"
      shift 2
      ;;
    --staging-namespace)
      require_value "$1" "${2:-}"
      STAGING_NAMESPACE_VALUE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN_VALUE="1"
      shift
      ;;
    --expect-failure)
      EXPECT_FAILURE="1"
      WRITE_REPORT="0"
      shift
      ;;
    --no-report)
      WRITE_REPORT="0"
      shift
      ;;
    *)
      diag "release-rehearsal" "arguments" "known option" "$1" "Use --dry-run, --date, --fixture, --report, --config, --checkout-root, --staging-namespace, --expect-failure, or --no-report."
      exit 64
      ;;
  esac
done

config_value() {
  local key="$1"
  python3 - "${CONFIG_FILE}" "${key}" <<'PY'
import sys
from pathlib import Path
import yaml

payload = yaml.safe_load(Path(sys.argv[1]).read_text()) or {}
value = payload
for part in sys.argv[2].split('.'):
    value = value.get(part, "") if isinstance(value, dict) else ""
print(value if value is not None else "")
PY
}

slug() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '-'
}

run_orchestration() {
  local date_value="${DATE_VALUE:-}"
  local dry_run="${DRY_RUN_VALUE:-}"
  local staging_namespace="${STAGING_NAMESPACE_VALUE:-}"
  local checkout=""
  local checkout_root_supplied=0
  local checkout_real=""
  local report_base_real=""
  local tmp_dir=""
  local logs_dir=""
  local report_path=""
  local report_lstat_path=""
  local source_sha=""
  local matrix_json=""
  local step_index=0

  if [[ -z "${date_value}" ]]; then
    date_value="$(config_value default_date_utc)"
  fi
  if [[ -z "${staging_namespace}" ]]; then
    staging_namespace="$(config_value default_staging_namespace)"
  fi
  if [[ -z "${REPORT_FILE}" ]]; then
    REPORT_FILE="$(config_value report)"
  fi
  if [[ -z "${REPORT_FILE}" ]]; then
    REPORT_FILE="cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md"
  fi
  if [[ -n "${CHECKOUT_ROOT}" ]]; then
    checkout_root_supplied=1
    if [[ ! -d "${CHECKOUT_ROOT}" ]]; then
      diag "release-rehearsal" "${CHECKOUT_ROOT}" "checkout root directory exists" "missing" "Pass --checkout-root to a temporary Git project in tests or omit it to clone the current checkout."
      exit 65
    fi
    checkout="$(cd "${CHECKOUT_ROOT}" && pwd)"
  fi
  report_path="${REPORT_FILE}"
  if [[ "${report_path}" != /* ]]; then
    if [[ -n "${checkout}" ]]; then
      report_path="${checkout}/${report_path}"
    else
      report_path="${ROOT_DIR}/${report_path}"
    fi
  fi
  report_lstat_path="${report_path}"
  if (( checkout_root_supplied == 1 )); then
    checkout_real="$(realpath -m "${checkout}")"
    report_base_real="${checkout_real}"
  else
    report_base_real="$(realpath -e "${ROOT_DIR}")"
  fi
  report_path="$(realpath -m "${report_path}")"
  if [[ "${report_path}" != "${report_base_real}"/* ]]; then
    diag "release-rehearsal" "report" "report path stays inside release rehearsal output root" "${report_path}" "Use a report path under ${report_base_real}."
    exit 64
  fi

  [[ "${date_value}" =~ ^[0-9]{8}$ ]] || { diag "release-rehearsal" "release date" "UTC release date formatted as YYYYMMDD" "${date_value:-missing}" "Pass --date 20260609 or set DATE=20260609."; exit 64; }
  if [[ "${dry_run}" != "1" && "${dry_run}" != "true" && "${dry_run}" != "True" && ! "${staging_namespace}" =~ ^ghcr\.io/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    diag "release-rehearsal" "publish rehearsal mode" "dry-run or valid GHCR staging namespace" "dry_run=${dry_run:-0} staging_namespace=${staging_namespace:-missing}" "Use --dry-run for local runs or pass --staging-namespace ghcr.io/<owner>/<repo>."
    exit 64
  fi

  if [[ -z "${checkout}" ]]; then
    if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=all)" ]]; then
      diag "release-rehearsal" "source checkout" "clean git status before cloning release rehearsal worktree" "dirty" "Commit or stash local changes, then rerun the release rehearsal from a reproducible HEAD."
      exit 65
    fi
    source_sha="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
    tmp_dir="$(mktemp -d)"
    checkout="${tmp_dir}/checkout"
    git clone --quiet --no-local --no-hardlinks "${ROOT_DIR}" "${checkout}"
    git -C "${checkout}" checkout --quiet "${source_sha}"
  fi

  if [[ ! -d "${checkout}/.git" ]]; then
    diag "release-rehearsal" "${checkout}" "clean git checkout exists" "missing .git" "Run release rehearsal from a Git checkout or pass --checkout-root to a temporary Git project in tests."
    exit 65
  fi
  if [[ -n "$(git -C "${checkout}" status --porcelain --untracked-files=all)" ]]; then
    diag "release-rehearsal" "${checkout}" "release rehearsal checkout starts clean" "dirty" "Use a clean checkout before running update, generate, validate, build, smoke, scan, publish, and catalog gates."
    exit 65
  fi

  if [[ -z "${tmp_dir}" ]]; then
    tmp_dir="$(mktemp -d)"
  fi
  logs_dir="${tmp_dir}/release-rehearsal-logs"
  mkdir -p "${logs_dir}"
  local commands_file="${logs_dir}/commands.tsv"
  local last_log_file=""
  : > "${commands_file}"

  run_step() {
    local label="$1"
    shift
    local -a command=("$@")
    if [[ "${#command[@]}" == "0" ]]; then
      diag "release-rehearsal" "${label}" "step has a command" "empty argv" "Wire the release rehearsal step to an explicit command array."
      exit 64
    fi
    step_index=$((step_index + 1))
    local log_slug log
    log_slug="$(slug "${label}")"
    log="${logs_dir}/$(printf '%02d-%s.log' "${step_index}" "${log_slug}")"
    local start end status
    start="$(date -u +%s)"
    printf 'release rehearsal step %02d: %s\n' "${step_index}" "${label}" >&2
    printf '+ ' >&2
    printf '%q ' "${command[@]}" >&2
    printf '\n' >&2
    set +e
    (cd "${checkout}" && "${command[@]}") 2>&1 | tee "${log}"
    status="${PIPESTATUS[0]}"
    set -e
    end="$(date -u +%s)"
    printf '%s\t%s\t%s\t%s\t%s\n' "${step_index}" "${label}" "${status}" "$((end - start))" "${log}" >> "${commands_file}"
    last_log_file="${log}"
    if [[ "${status}" != "0" ]]; then
      printf '\n--- release rehearsal failed step log: %s ---\n' "${log}" >&2
      tail -n 200 "${log}" >&2 || true
      diag "release-rehearsal" "${label}" "command exits 0" "exit ${status}; log=${log}" "Inspect the command log, fix the release gate, and rerun from a clean checkout."
      exit "${status}"
    fi
  }

  run_step "make update" env DATE="${date_value}" DRY_RUN="${dry_run:-0}" STAGING_NAMESPACE="${staging_namespace}" make --no-print-directory update UPDATE_ARGS=--json
  run_step "make generate" env DATE="${date_value}" make --no-print-directory generate
  run_step "make validate" env DATE="${date_value}" make --no-print-directory validate
  run_step "make matrix" make --no-print-directory matrix
  matrix_json="$(cat "${last_log_file}")"
  run_step "make bake-print" make --no-print-directory bake-print

  while IFS=$'\t' read -r pg debian platform; do
    [[ -n "${pg}" ]] || continue
    run_step "make build PG=${pg} DEBIAN=${debian} PLATFORM=${platform}" env PLATFORM="${platform}" make --no-print-directory build PG="${pg}" DEBIAN="${debian}"
    run_step "container smoke PG=${pg} DEBIAN=${debian} PLATFORM=${platform}" env PLATFORM="${platform}" SMOKE_EXPECTED_PLATFORM="${platform}" CHECKS=container make --no-print-directory smoke PG="${pg}" DEBIAN="${debian}"
    run_step "SQL smoke PG=${pg} DEBIAN=${debian} PLATFORM=${platform}" env PLATFORM="${platform}" SMOKE_EXPECTED_PLATFORM="${platform}" CHECKS=sql make --no-print-directory smoke PG="${pg}" DEBIAN="${debian}"
  done < <(python3 - "${matrix_json}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
for row in payload.get("include", []):
    if row.get("publish") is True:
        for platform in row.get("platforms", []):
            print(f"{row['pg_major']}\t{row['debian_variant']}\t{platform}")
PY
  )

  run_step "make catalog" make --no-print-directory catalog
  run_step "validate docs" bash cloudnative-pg-timescaledb/scripts/validate-docs.sh

  if [[ "${WRITE_REPORT}" == "1" ]]; then
    local report_dir
    report_dir="$(dirname "${report_path}")"
    local existing_report_ancestor parent
    existing_report_ancestor="${report_dir}"
    while [[ ! -e "${existing_report_ancestor}" ]]; do
      parent="$(dirname "${existing_report_ancestor}")"
      if [[ "${parent}" == "${existing_report_ancestor}" ]]; then
        diag "release-rehearsal" "report" "report path has an existing ancestor inside release rehearsal output root" "${report_dir}" "Use a report path under ${report_base_real}."
        exit 64
      fi
      existing_report_ancestor="${parent}"
    done
    existing_report_ancestor="$(realpath -e "${existing_report_ancestor}")"
    if [[ "${existing_report_ancestor}" != "${report_base_real}" && "${existing_report_ancestor}" != "${report_base_real}"/* ]]; then
      diag "release-rehearsal" "report" "report existing ancestor stays inside release rehearsal output root" "${existing_report_ancestor}" "Use a report path under ${report_base_real}."
      exit 64
    fi
    mkdir -p "${report_dir}"
    local checked_out_sha report_mode report_display_path
    checked_out_sha="${source_sha:-$(git -C "${checkout}" rev-parse HEAD)}"
    if [[ "${dry_run}" == "1" || "${dry_run}" == "true" || "${dry_run}" == "True" ]]; then
      report_mode="dry-run"
    else
      report_mode="staging"
    fi
    local report_parent
    report_parent="$(realpath -e "$(dirname "${report_path}")")"
    if [[ "${report_parent}" != "${report_base_real}" && "${report_parent}" != "${report_base_real}"/* ]]; then
      diag "release-rehearsal" "report" "report parent stays inside release rehearsal output root" "${report_parent}" "Use a report path under ${report_base_real}."
      exit 64
    fi
    if [[ -L "${report_lstat_path}" ]]; then
      diag "release-rehearsal" "report" "report file is not a symlink" "${report_lstat_path}" "Use a regular checkout-local report file."
      exit 64
    fi
    local report_tmp
    report_tmp="$(mktemp "${report_dir}/.release-rehearsal-report.XXXXXX")"
    {
      printf '# Release Rehearsal Report\n\n'
      printf '<!-- Generated by cloudnative-pg-timescaledb/scripts/release-rehearsal.sh from executed clean-checkout commands. -->\n\n'
      printf "UTC date: \`%s\`\n" "${date_value}"
      printf "Source SHA: \`%s\`\n" "${checked_out_sha}"
      printf "Mode: \`%s\`\n" "${report_mode}"
      printf "Staging namespace: \`%s\`\n\n" "${staging_namespace:-n/a}"
      printf '## Commands Run\n\n'
      awk -F '\t' '{printf "- Step `%02d` `%s` exit `%s`\n", $1, $2, $3}' "${commands_file}"
      printf '\n## Workflow Dispatch Evidence\n\n'
      printf -- "- URL: \`%s\`\n" "${WORKFLOW_RUN_URL:-external gh run view required}"
      printf -- "- Status: \`external gh run view required after completion\`\n"
      printf -- "- Conclusion: \`external gh run view required after completion\`\n"
    } > "${report_tmp}"
    mv -f -T "${report_tmp}" "${report_path}"
  fi

  if [[ "${report_path}" == "${checkout}/"* ]]; then
    report_display_path="${report_path:$(( ${#checkout} + 1 ))}"
  elif [[ "${report_path}" == "${ROOT_DIR}/"* ]]; then
    report_display_path="${report_path:$(( ${#ROOT_DIR} + 1 ))}"
  else
    report_display_path="${report_path}"
  fi
  printf 'PASS release-rehearsal orchestration date=%s dry_run=%s checkout=%s report=%s\n' "${date_value}" "${dry_run:-0}" "${checkout}" "${report_display_path}"
}

if [[ -z "${FIXTURE_FILE}" ]]; then
  run_orchestration
  exit 0
fi

python3 - "${ROOT_DIR}" "${CONFIG_FILE}" "${FIXTURE_FILE}" "${REPORT_FILE}" "${DATE_VALUE}" "${DRY_RUN_VALUE}" "${STAGING_NAMESPACE_VALUE}" "${EXPECT_FAILURE}" "${WRITE_REPORT}" <<'PY'
from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
config_path = Path(sys.argv[2])
fixture_arg = sys.argv[3]
report_arg = sys.argv[4]
date_arg = sys.argv[5]
dry_run_arg = sys.argv[6]
staging_namespace_arg = sys.argv[7]
expect_failure = sys.argv[8] == "1"
write_report = sys.argv[9] == "1"

COMMAND = "release-rehearsal"
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
DATE_RE = re.compile(r"^[0-9]{8}$")
SECRET_RE = re.compile(
    r"(?i)("
    r"ghp_[A-Za-z0-9_]{8,}|github_pat_[A-Za-z0-9_]{8,}|ghs_[A-Za-z0-9_]{8,}|gho_[A-Za-z0-9_]{8,}|"
    r"github[_-]?token\s*=|registry[_-]?password\s*=|signing[_-]?secret\s*=|cosign[_-]?password\s*=|"
    r"aws_access_key_id\s*=|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|\.env\b"
    r")"
)


def diag(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {COMMAND}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def require(condition, artifact, expected, actual, remediation):
    if not condition:
        diag(artifact, expected, actual, remediation)


def iter_strings(value, path="fixture"):
    if isinstance(value, dict):
        for key in sorted(value):
            yield from iter_strings(value[key], f"{path}.{key}")
    elif isinstance(value, list):
        for idx, item in enumerate(value):
            yield from iter_strings(item, f"{path}[{idx}]")
    elif isinstance(value, str):
        yield path, value


def secret_locations(value):
    return [path for path, text in iter_strings(value) if SECRET_RE.search(text)]


def path_has_reference_tree(value):
    parts = [part for part in str(value).replace("\\", "/").split("/") if part and part != "."]
    return "vendor" in parts


def rel(path: Path) -> Path:
    return path if path.is_absolute() else root / path


def load_yaml(path: Path):
    try:
        payload = yaml.safe_load(path.read_text())
    except FileNotFoundError:
        diag(path, "release rehearsal config exists", "missing", "Create cloudnative-pg-timescaledb/config/release-rehearsal.yaml.")
    except Exception as exc:
        diag(path, "parseable YAML", str(exc), "Keep release rehearsal config valid YAML.")
    require(isinstance(payload, dict), path, "config top-level mapping", type(payload).__name__, "Use a structured release rehearsal config.")
    return payload


config = load_yaml(config_path)
default_fixture = config.get("fixtures", {}).get("default")
fixture_path = rel(Path(fixture_arg or default_fixture or ""))
report_path = rel(Path(report_arg or config.get("fixtures", {}).get("report", "cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md")))
date_value = date_arg or str(config.get("default_date_utc", ""))
dry_run = dry_run_arg in {"1", "true", "True", "yes"}
staging_namespace = staging_namespace_arg or str(config.get("default_staging_namespace", ""))

require(DATE_RE.fullmatch(date_value), "release date", "UTC release date formatted as YYYYMMDD", repr(date_value), "Pass --date 20260609 or set DATE=20260609.")
require(dry_run or staging_namespace.startswith("ghcr.io/"), "publish rehearsal mode", "dry-run or GHCR staging namespace", {"dry_run": dry_run, "staging_namespace": staging_namespace}, "Use --dry-run for local runs or a GHCR staging namespace for workflow rehearsal.")


def read_json(path: Path):
    try:
        payload = json.loads(path.read_text())
    except FileNotFoundError:
        diag(path, "release rehearsal fixture exists", "missing", "Restore the fixture listed in the story artifacts.")
    except json.JSONDecodeError as exc:
        diag(path, "valid JSON fixture", str(exc), "Keep release rehearsal fixtures deterministic JSON.")
    require(isinstance(payload, dict), path, "fixture top-level JSON object", type(payload).__name__, "Use a structured release rehearsal fixture object.")
    return payload


def apply_case(payload: dict, case: str) -> dict:
    data = copy.deepcopy(payload)
    candidates = data.setdefault("candidates", [])

    def find(pg: str, debian: str) -> dict:
        for candidate in candidates:
            if candidate.get("pg_major") == pg and candidate.get("debian_variant") == debian:
                return candidate
        diag(f"fixture case {case}", f"candidate {pg}-{debian} exists in base fixture", [f"{c.get('pg_major')}-{c.get('debian_variant')}" for c in candidates], "Keep valid-full-matrix.json complete before deriving negative fixtures.")

    def clone_candidate(pg: str, debian: str, new_debian: str) -> None:
        candidate = copy.deepcopy(find(pg, debian))
        candidate["debian_variant"] = new_debian
        candidate["row_id"] = f"{pg}-{new_debian}"
        candidates.append(candidate)

    def supply_chain(pg: str = "18", debian: str = "trixie") -> dict:
        return find(pg, debian).setdefault("supply_chain", {})

    if case in {"valid-full-matrix", "no-op-update", "changed-update-autocommit"}:
        if case == "no-op-update":
            data.setdefault("update", {})["no_op_passed"] = True
            data["update"]["changed_autocommit_passed"] = True
        if case == "changed-update-autocommit":
            data.setdefault("update", {})["changed_autocommit_passed"] = True
            data["update"]["generated_drift_detected"] = True
        return data
    if case == "missing-publishable-pg-debian-platform":
        data["candidates"] = [c for c in candidates if not (c.get("pg_major") == "17" and c.get("debian_variant") == "trixie")]
    elif case == "missing-smoke-result":
        find("18", "trixie").setdefault("smoke_sql", {}).pop("linux/arm64", None)
    elif case == "missing-sbom":
        supply_chain()["sbom"] = "missing"
    elif case == "missing-provenance":
        supply_chain()["provenance"] = "missing"
    elif case == "missing-signature":
        supply_chain()["signature"] = "missing"
    elif case == "vulnerability-threshold-failed":
        find("18", "trixie").setdefault("vulnerability_scan", {})["status"] = "failed"
    elif case == "scan-wrong-digest":
        find("18", "trixie").setdefault("vulnerability_scan", {})["subject_digest"] = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    elif case == "sbom-wrong-digest":
        supply_chain()["sbom"]["subject_digest"] = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    elif case == "provenance-wrong-digest":
        supply_chain()["provenance"]["subject_digest"] = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    elif case == "signature-wrong-digest":
        supply_chain()["signature"]["subject_digest"] = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    elif case == "wrong-latest":
        data.setdefault("latest", {})["actual_target"] = "17-trixie"
    elif case == "latest-not-pg18-trixie":
        data.setdefault("latest", {})["actual_target"] = "18-bookworm"
    elif case == "stale-generated-files":
        data.setdefault("generated_files", {})["status"] = "stale"
    elif case == "unpublished-catalog-reference":
        find("18", "trixie").setdefault("catalog_ref", {})["present"] = False
    elif case == "secret-in-summary":
        data.setdefault("secret_scan", {})["summaries"] = ["registry_password=super-secret-value"]
    elif case == "secret-in-command":
        data.setdefault("commands_run", []).append("make validate github_token=bad-secret-value")
    elif case == "secret-in-workflow-url":
        data.setdefault("workflow_dispatch", {})["url"] = "https://github.com/pnetcloud/containers/actions/runs/123?token=ghp_badsecretvalue"
    elif case == "secret-in-candidate-metadata":
        find("18", "trixie")["image"] = "ghcr.io/pnetcloud/cloudnative-pg-timescaledb-rehearsal:github_pat_badsecretvalue"
    elif case == "pg19beta1-promoted-to-latest":
        preview = find("19beta1", "trixie")
        preview["final_tags"] = ["latest", "19beta1"]
        data.setdefault("latest", {})["actual_target"] = "19beta1-trixie"
    elif case == "vendor-used-as-build-context":
        find("18", "trixie")["build_context"] = "vendor" + "/postgres-containers"
    elif case == "vendor-used-as-runtime-input":
        find("18", "trixie").setdefault("runtime_inputs", []).append("vendor" + "/cloudnative-pg-timescaledb-postgis-containers")
    elif case == "vendor-exact-build-context":
        find("18", "trixie")["build_context"] = "vendor"
    elif case == "vendor-dot-build-context":
        find("18", "trixie")["build_context"] = "./vendor"
    elif case == "vendor-absolute-runtime-input":
        find("18", "trixie").setdefault("runtime_inputs", []).append("/workspace/" + "vendor" + "/postgres-containers")
    elif case == "alpine-release-candidate":
        clone_candidate("18", "trixie", "alpine")
    elif case == "bullseye-release-candidate":
        clone_candidate("18", "trixie", "bullseye")
    elif case == "unsupported-debian-variant":
        clone_candidate("18", "trixie", "sid")
    elif case == "missing-workflow-dispatch-evidence":
        data["workflow_dispatch"] = {"url": "", "status": "", "conclusion": ""}
    else:
        diag("fixture case", "known release rehearsal fixture case", case, "Use a case implemented by release-rehearsal.sh.")
    return data


def load_fixture(path: Path) -> dict:
    payload = read_json(path)
    if "extends" in payload:
        base_path = path.parent / str(payload["extends"])
        base = load_fixture(base_path)
        merged = apply_case(base, str(payload.get("case", "")))
        for key, value in payload.items():
            if key not in {"extends", "case", "expected_failure"}:
                merged[key] = value
        merged["expected_failure"] = payload.get("expected_failure", "")
        merged["fixture_path"] = path.relative_to(root).as_posix() if path.is_relative_to(root) else str(path)
        return merged
    payload = apply_case(payload, str(payload.get("case", "valid-full-matrix")))
    payload["fixture_path"] = path.relative_to(root).as_posix() if path.is_relative_to(root) else str(path)
    return payload


fixture = load_fixture(fixture_path)
def digest(value, artifact):
    require(isinstance(value, str) and DIGEST_RE.fullmatch(value), artifact, "sha256 digest", repr(value), "Record immutable sha256 digests from the build/publish evidence.")


supported = config.get("supported", {})
allowed_pgs = set(supported.get("postgres_majors", []))
allowed_debians = set(supported.get("debian_variants", []))
allowed_platforms = set(supported.get("platforms", []))
require(allowed_pgs == {"17", "18", "19beta1"}, config_path, "PostgreSQL scope is 17, 18, 19beta1", sorted(allowed_pgs), "Keep the v1 release rehearsal aligned with the approved PostgreSQL scope.")
require(allowed_debians == {"trixie", "bookworm"}, config_path, "Debian scope is trixie and bookworm only", sorted(allowed_debians), "Do not add Alpine, bullseye, or other Debian variants.")
require(allowed_platforms == {"linux/amd64", "linux/arm64"}, config_path, "platform scope is amd64 and arm64", sorted(allowed_platforms), "Release rehearsal must prove both required platforms.")

fixture_date = str(fixture.get("date", date_value))
require(fixture_date == date_value, fixture.get("fixture_path", fixture_path), "fixture date matches requested UTC date", {"fixture": fixture_date, "requested": date_value}, "Regenerate fixture evidence with the requested deterministic UTC date.")

commands = fixture.get("commands_run", [])
require(isinstance(commands, list), "commands_run", "commands_run is an array", type(commands).__name__, "Record every command class executed by the release rehearsal.")
for token in ["make update", "make generate", "make validate", "docker buildx bake", "container smoke", "SQL smoke", "vulnerability scan", "SBOM", "provenance", "cosign", "publish rehearsal", "generate-catalog", "validate-docs"]:
    require(any(token in str(command) for command in commands), "commands_run", f"command list includes {token}", commands, "Record all required release pipeline stages in the rehearsal evidence.")

update = fixture.get("update", {})
require(update.get("no_op_passed") is True, "update.no_op_passed", "no-op update path passes without commit", update, "Run make update in no-op fixture mode and prove it creates no commit.")
require(update.get("changed_autocommit_passed") is True, "update.changed_autocommit_passed", "changed update/autocommit path passes", update, "Run changed update/autocommit fixture mode and prove only allowlisted paths are staged.")
require(update.get("generated_drift_detected") is True, "update.generated_drift_detected", "generated drift fixture blocks release", update, "Prove stale generated files fail before publishing.")

generated = fixture.get("generated_files", {})
require(generated.get("status") == "fresh", "generated_files.status", "generated files are fresh", generated, "Run make generate and make validate before release rehearsal completes.")

workflow = fixture.get("workflow_dispatch", {})
require(workflow.get("url", "").startswith("https://"), "workflow_dispatch.url", "actual release-rehearsal.yml workflow run URL", workflow, "Dispatch release-rehearsal.yml and record gh run view URL evidence.")
require(workflow.get("status") == "completed", "workflow_dispatch.status", "workflow status is completed", workflow, "Run gh run watch until the workflow completes.")
require(workflow.get("conclusion") == "success", "workflow_dispatch.conclusion", "workflow conclusion is success", workflow, "Fix the release-rehearsal workflow before accepting the release candidate.")

publish_rehearsal = fixture.get("publish_rehearsal", {})
require(publish_rehearsal.get("final_tags_promoted") is False, "publish_rehearsal.final_tags_promoted", "final tags are not promoted in dry-run/staging rehearsal", publish_rehearsal, "Use dry-run or staging namespace until all release gates pass.")
require(publish_rehearsal.get("gates_block_on_failure") is True, "publish_rehearsal.gates_block_on_failure", "release gates block failed candidates", publish_rehearsal, "Do not promote final GHCR tags unless every gate passes.")

secret_scan = fixture.get("secret_scan", {})
locations = secret_locations(fixture)
require(secret_scan.get("passed") is True and not locations, "secret_scan", "no secrets or secret-like values in committed files, evidence, or summaries", {"secret_locations": locations}, "Remove credentials and sanitize workflow summaries before release.")

candidates = fixture.get("candidates", [])
require(isinstance(candidates, list) and candidates, "candidates", "candidate matrix is a non-empty array", type(candidates).__name__, "Emit one candidate row per supported PostgreSQL/Debian combination.")

candidate_by_key = {}
for idx, candidate in enumerate(candidates):
    artifact = f"candidates[{idx}]"
    pg = str(candidate.get("pg_major", ""))
    debian = str(candidate.get("debian_variant", ""))
    key = f"{pg}-{debian}"
    require(key not in candidate_by_key, artifact, "candidate key is unique", key, "Do not duplicate release candidate rows.")
    candidate_by_key[key] = candidate
    require(pg in allowed_pgs, artifact, "PostgreSQL major is supported", pg, "Keep release candidates to PostgreSQL 17, 18, and 19beta1.")
    if debian == "alpine":
        diag(artifact, "Alpine release candidates are blocked", debian, "Remove Alpine from v1 release rehearsal scope.")
    if debian == "bullseye":
        diag(artifact, "bullseye release candidates are blocked", debian, "Keep Debian scope to trixie and bookworm.")
    require(debian in allowed_debians, artifact, "Debian variant is trixie or bookworm", debian, "Remove unsupported Debian variants from release metadata.")
    platforms = candidate.get("platforms", [])
    require(set(platforms) == allowed_platforms, artifact, "candidate covers linux/amd64 and linux/arm64", platforms, "Keep every publishable rehearsal row multi-platform.")
    build_context = str(candidate.get("build_context", ""))
    runtime_inputs = [str(item) for item in candidate.get("runtime_inputs", [])]
    require(not path_has_reference_tree(build_context), artifact, "build context excludes reference-only tree", build_context, "Use generated repository sources, not reference trees, as build inputs.")
    bad_runtime_inputs = [item for item in runtime_inputs if path_has_reference_tree(item)]
    require(not bad_runtime_inputs, artifact, "runtime inputs exclude reference-only tree", bad_runtime_inputs, "Do not copy or load runtime assets from reference trees.")
    if candidate.get("publish") is False:
        require(str(candidate.get("skip_reason", "")).strip(), artifact, "publish false rows include skip_reason", candidate, "Explain unsupported or experimental rows before skipping them.")

expected_keys = {f"{pg}-{debian}" for pg in allowed_pgs for debian in allowed_debians}
require(set(candidate_by_key) == expected_keys, "candidates", "matrix enumerates every supported PostgreSQL/Debian combination", {"expected": sorted(expected_keys), "actual": sorted(candidate_by_key)}, "Compare versions.yaml, matrix, Bake, build outputs, smoke outputs, release evidence, publish rehearsal, and catalogs.")

publishable = [candidate for candidate in candidates if candidate.get("publish") is True]
for required_key in config.get("publishable_stable_primary", []):
    required = candidate_by_key.get(required_key)
    require(required and required.get("publish") is True, required_key, "stable primary trixie row is publishable", required, "Enable stable PG17/PG18 trixie rows in rehearsal evidence before release.")

for candidate in publishable:
    key = f"{candidate['pg_major']}-{candidate['debian_variant']}"
    digest(candidate.get("index_digest"), f"{key}.index_digest")
    platform_digests = candidate.get("platform_digests", {})
    require(set(platform_digests) == allowed_platforms, f"{key}.platform_digests", "all platform digests are present", platform_digests, "Bind every smoke/build result to a platform digest.")
    for platform, value in platform_digests.items():
        digest(value, f"{key}.platform_digests[{platform}]")
    for field in ["build_evidence", "smoke_container", "smoke_sql"]:
        evidence = candidate.get(field, {})
        require(all(evidence.get(platform) == "passed" for platform in allowed_platforms), f"{key}.{field}", "every platform evidence row passed", evidence, "Run build and smoke gates for every supported platform.")
    vulnerability_scan = candidate.get("vulnerability_scan", {})
    require(vulnerability_scan.get("status") == "passed", f"{key}.vulnerability_scan", "vulnerability threshold gate passed", vulnerability_scan, "Block release until the vulnerability threshold passes.")
    require(vulnerability_scan.get("subject_digest") == candidate.get("index_digest"), f"{key}.vulnerability_scan.subject_digest", "vulnerability scan is bound to the candidate index digest", vulnerability_scan, "Scan the same immutable manifest-list digest that release would publish.")
    supply_chain = candidate.get("supply_chain", {})
    for field in ["sbom", "provenance"]:
        evidence = supply_chain.get(field)
        require(isinstance(evidence, dict), f"{key}.supply_chain.{field}", f"{field} evidence is structured", evidence, "Record evidence path and subject digest for every supply-chain artifact.")
        require(str(evidence.get("path", "")).strip(), f"{key}.supply_chain.{field}.path", f"{field} evidence path is present", evidence, "Persist the generated supply-chain artifact path.")
        require(evidence.get("subject_digest") == candidate.get("index_digest"), f"{key}.supply_chain.{field}.subject_digest", f"{field} evidence is bound to the candidate index digest", evidence, "Generate evidence for the exact manifest-list digest that release would publish.")
    signature = supply_chain.get("signature")
    require(isinstance(signature, dict), f"{key}.supply_chain.signature", "signature evidence is structured", signature, "Record signature verification result and subject digest.")
    require(signature.get("verified") is True, f"{key}.supply_chain.signature.verified", "signature verification passed", signature, "Verify the keyless signature before publish rehearsal passes.")
    require(signature.get("subject_digest") == candidate.get("index_digest"), f"{key}.supply_chain.signature.subject_digest", "signature evidence is bound to the candidate index digest", signature, "Sign and verify the exact manifest-list digest that release would publish.")
    require(candidate.get("publish", False) is True and candidate.get("publish_rehearsal") == "passed", f"{key}.publish_rehearsal", "publish rehearsal passed for candidate digest", candidate.get("publish_rehearsal"), "Use dry-run/staging publish rehearsal before final tag promotion.")

latest = fixture.get("latest", {})
expected_latest = config.get("latest", {}).get("expected_target", "18-trixie")
require(expected_latest == "18-trixie", "latest.expected_target", "configured latest target is exactly 18-trixie", expected_latest, "Keep latest restricted to PostgreSQL 18 on trixie.")
require(latest.get("expected_target") == expected_latest, "latest.expected_target", "expected latest target is 18-trixie", latest, "Keep latest policy explicit in rehearsal evidence.")
require(latest.get("actual_target") == expected_latest, "latest.actual_target", "latest resolves to 18-trixie", latest, "latest must point only to PostgreSQL 18 on trixie.")
require(expected_latest in candidate_by_key, "latest.expected_target", "latest target exists in candidate matrix", {"expected_latest": expected_latest, "candidates": sorted(candidate_by_key)}, "Keep the release matrix complete before validating latest digest binding.")
latest_candidate = candidate_by_key[expected_latest]
require(latest.get("digest") == latest_candidate.get("index_digest"), "latest.digest", "latest digest equals PG18 trixie manifest-list digest", latest, "Publish latest by immutable PG18 trixie manifest-list digest.")

latest_holders = [f"{c.get('pg_major')}-{c.get('debian_variant')}" for c in candidates if "latest" in c.get("final_tags", [])]
require(latest_holders == [expected_latest], "final_tags.latest", "only PG18 trixie receives latest", latest_holders, "Do not assign latest to PG17, bookworm, or experimental rows.")

for key, candidate in candidate_by_key.items():
    pg = candidate.get("pg_major")
    tags = candidate.get("final_tags", [])
    if pg == "19beta1" or candidate.get("experimental") is True:
        require(candidate.get("publish") is False, key, "PG19beta1 remains experimental and not publishable", candidate, "Keep PostgreSQL 19beta1 out of stable release promotion until policy changes.")
        require("latest" not in tags and "19beta1" not in tags, key, "experimental PG19beta1 has no normal/latest tags", tags, "Use explicit experimental tags only after a metadata policy change.")

catalogs = fixture.get("catalogs", {})
paths = set(catalogs.get("paths", []))
require(paths == {"cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml", "cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml"}, "catalogs.paths", "trixie and bookworm catalogs are generated", sorted(paths), "Generate both stable ClusterImageCatalog files from release metadata.")
for candidate in publishable:
    if candidate.get("experimental"):
        continue
    key = f"{candidate['pg_major']}-{candidate['debian_variant']}"
    catalog_ref = candidate.get("catalog_ref", {})
    require(catalog_ref.get("present") is True, f"{key}.catalog_ref", "publishable stable candidate is referenced in its catalog", catalog_ref, "Regenerate catalogs from complete release metadata and validate references.")


def render_report() -> str:
    lines = [
        "# Release Rehearsal Report",
        "",
        "<!-- Generated by cloudnative-pg-timescaledb/scripts/release-rehearsal.sh from release rehearsal evidence. -->",
        "",
        f"UTC date: `{date_value}`",
        f"Mode: `{'dry-run' if dry_run else 'staging'}`",
        f"Staging namespace: `{staging_namespace or 'n/a'}`",
        "",
        "## Commands Run",
        "",
    ]
    lines.extend(f"- `{command}`" for command in commands)
    lines.extend(["", "## Matrix and Images", "", "| Candidate | Publish | Platforms | Image | Index digest | Tags |", "| --- | --- | --- | --- | --- | --- |"])
    for candidate in candidates:
        key = f"{candidate.get('pg_major')}-{candidate.get('debian_variant')}"
        tags = ", ".join(f"`{tag}`" for tag in candidate.get("final_tags", [])) or "n/a"
        lines.append(
            "| {key} | {publish} | {platforms} | `{image}` | `{digest}` | {tags} |".format(
                key=key,
                publish=str(candidate.get("publish")).lower(),
                platforms=", ".join(candidate.get("platforms", [])),
                image=candidate.get("image", "n/a"),
                digest=candidate.get("index_digest", "n/a"),
                tags=tags,
            )
        )
    lines.extend([
        "",
        "## Latest",
        "",
        f"Expected target: `{expected_latest}`",
        f"Actual target: `{latest.get('actual_target')}`",
        f"Manifest-list digest: `{latest.get('digest')}`",
        "",
        "## Catalogs",
        "",
    ])
    lines.extend(f"- `{path}`" for path in sorted(paths))
    lines.extend(["", "## Security Evidence", ""])
    for candidate in publishable:
        key = f"{candidate.get('pg_major')}-{candidate.get('debian_variant')}"
        supply_chain = candidate.get("supply_chain", {})
        sbom = supply_chain.get("sbom", {})
        provenance = supply_chain.get("provenance", {})
        signature = supply_chain.get("signature", {})
        lines.append(
            f"- `{key}` scan `{candidate.get('vulnerability_scan', {}).get('status')}` for `{candidate.get('vulnerability_scan', {}).get('subject_digest')}`, "
            f"SBOM `{sbom.get('path')}` for `{sbom.get('subject_digest')}`, "
            f"provenance `{provenance.get('path')}` for `{provenance.get('subject_digest')}`, "
            f"signature verified `{str(signature.get('verified')).lower()}` for `{signature.get('subject_digest')}`"
        )
    lines.extend([
        "",
        "## Workflow Dispatch Evidence",
        "",
        f"- URL: `{workflow.get('url')}`",
        f"- Status: `{workflow.get('status')}`",
        f"- Conclusion: `{workflow.get('conclusion')}`",
        "",
        "## Skipped Combinations",
        "",
    ])
    skipped = [candidate for candidate in candidates if candidate.get("publish") is False]
    lines.extend(f"- `{candidate.get('pg_major')}-{candidate.get('debian_variant')}`: {candidate.get('skip_reason')}" for candidate in skipped)
    lines.extend([
        "",
        "## Failure Reasons Exercised",
        "",
        "- `missing-publishable-pg-debian-platform`",
        "- `missing-smoke-result`",
        "- `missing-sbom`",
        "- `missing-provenance`",
        "- `missing-signature`",
        "- `vulnerability-threshold-failed`",
        "- `scan-wrong-digest`",
        "- `sbom-wrong-digest`",
        "- `provenance-wrong-digest`",
        "- `signature-wrong-digest`",
        "- `wrong-latest`",
        "- `latest-not-pg18-trixie`",
        "- `stale-generated-files`",
        "- `catalog-reference-before-publish`",
        "- `secret-in-summary`",
        "- `secret-in-command`",
        "- `secret-in-workflow-url`",
        "- `secret-in-candidate-metadata`",
        "- `pg19beta1-promoted-to-latest`",
        "- `vendor-used-as-build-context`",
        "- `vendor-used-as-runtime-input`",
        "- `vendor-exact-build-context`",
        "- `vendor-dot-build-context`",
        "- `vendor-absolute-runtime-input`",
        "- `alpine-release-candidate`",
        "- `bullseye-release-candidate`",
        "- `unsupported-debian-variant`",
        "- `missing-workflow-dispatch-evidence`",
        "",
        "## Remediation Commands",
        "",
        "- `make update`",
        "- `make generate`",
        "- `make validate`",
        "- `make release-rehearsal DATE=20260609 DRY_RUN=1`",
        "",
    ])
    return "\n".join(lines)


if write_report:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(render_report())

try:
    report_display_path = report_path.relative_to(root).as_posix()
except ValueError:
    report_display_path = report_path.as_posix()

if expect_failure:
    diag(fixture.get("fixture_path", fixture_path), "fixture fails release rehearsal", "passed", "Remove --expect-failure for positive fixtures or break the fixture invariant under test.")

print(f"PASS release-rehearsal date={date_value} dry_run={str(dry_run).lower()} fixture={fixture.get('fixture_path', fixture_path)} report={report_display_path}")
PY
