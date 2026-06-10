#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/fixtures"
METADATA_FIXTURE="${FIXTURE_DIR}/metadata/valid-publishable-targets.yaml"
TEMP_DOCKERFILE=""
TEMP_DOCKERFILE_CREATED=0
TEMP_BAKE=""
TEMP_DIR=""

cleanup() {
  if [[ "${TEMP_DOCKERFILE_CREATED}" == "1" && -n "${TEMP_DOCKERFILE}" ]]; then
    rm -f "${TEMP_DOCKERFILE}"
  fi
  [[ -n "${TEMP_BAKE}" ]] && rm -f "${TEMP_BAKE}"
  [[ -n "${TEMP_DIR}" ]] && rm -rf "${TEMP_DIR}"
  return 0
}
trap cleanup EXIT

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

json_compare() {
  local description="$1"
  local fixture="$2"
  shift 2
  local tmp
  tmp="$(mktemp)"
  "$@" >"${tmp}"
  python3 - "$fixture" "${tmp}" <<'PY'
import json
import sys
from pathlib import Path

expected = json.loads(Path(sys.argv[1]).read_text())
actual = json.loads(Path(sys.argv[2]).read_text())
if actual != expected:
    raise SystemExit(f"expected {sys.argv[1]} but got {actual!r}")
PY
  rm -f "${tmp}"
}

validate_bake_summary() {
  local fixture="$1"
  python3 - "$fixture" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text())
command = f"validate-bake-summary {path}"

def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )

def require_keys(obj, keys, label):
    missing = sorted(set(keys) - set(obj))
    if missing:
        fail(f"{label} keys include {sorted(keys)}", f"missing {missing} in {obj!r}", "Keep the Bake generator JSON schema stable for local build consumers.")

require_keys(payload, {"bake_file", "targets", "skipped"}, "bake payload")
if not isinstance(payload["targets"], list) or not isinstance(payload["skipped"], list):
    fail("targets and skipped are lists", repr(payload), "Emit structured Bake target and skipped rows.")

skipped_names = set()
for row in payload["skipped"]:
    require_keys(row, {"pg_major", "debian_variant", "name", "dockerfile", "publish", "experimental", "skip_reason"}, "skipped row")
    if row["publish"] is not False:
        fail("skipped rows have publish=false", repr(row), "Do not mark skipped combinations as publishable.")
    if not row["skip_reason"]:
        fail("skipped rows carry skip_reason", repr(row), "Explain why omitted combinations are not buildable.")
    skipped_names.add(row["name"])

target_names = set()
for row in payload["targets"]:
    require_keys(row, {"name", "context", "dockerfile", "platforms", "publish", "experimental"}, "bake target")
    if row["name"] in target_names:
        fail("target names are unique", row["name"], "Generate one Bake target per PostgreSQL/Debian pair.")
    target_names.add(row["name"])
    if row["name"] in skipped_names:
        fail("skipped combinations are omitted from publishable targets", row["name"], "Keep skipped metadata rows out of local build targets.")
    match = re.fullmatch(r"pg(.+)-(trixie|bookworm)", row["name"])
    if not match:
        fail("target name uses pg<major>-<debian>", row["name"], "Encode PostgreSQL major and Debian variant in every target name.")
    if row["context"] not in {".", "./", "cloudnative-pg-timescaledb"} and not row["context"].startswith("./"):
        fail("target context is checkout/path context", row["context"], "Use local checkout context, not Docker Buildx default Git context.")
    forbidden_context = ["{{defaultContext}}", "http://", "https://", "git://", "github.com/"]
    if any(marker in row["context"] for marker in forbidden_context):
        fail("target context is not default Git context", row["context"], "Set context to '.' or another explicit local checkout path.")
    if row["publish"] is not True:
        fail("target rows have publish=true", repr(row), "Only publishable metadata rows should become buildable Bake targets.")
    if sorted(row["platforms"]) != ["linux/amd64", "linux/arm64"]:
        fail("targets preserve amd64 and arm64 platforms", repr(row["platforms"]), "Propagate platforms from metadata without narrowing architecture coverage.")
    outputs = row.get("output", []) or []
    if any("push=true" in item or "type=registry" in item for item in outputs):
        fail("local Bake target output does not push or publish", repr(outputs), "Keep Epic 3 local builds load-only; registry push belongs to Epic 4.")
PY
}

expect_summary_fail() {
  local description="$1"
  local fixture="$2"
  local pattern="$3"
  local tmp status
  tmp="$(mktemp)"
  set +e
  validate_bake_summary "${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-bake-summary ${fixture}" "${description}" "fixture fails" "passed" "Make malformed Bake fixtures fail validation."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-bake-summary ${fixture}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Make the fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

expect_command_fail() {
  local description="$1"
  local pattern="$2"
  shift 2
  local tmp status
  tmp="$(mktemp)"
  set +e
  "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "${*}" "${description}" "command fails" "passed" "Make invalid Bake command behavior fail deterministically."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Return actionable build diagnostics with target context."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

json_compare "publishable bake json" "${FIXTURE_DIR}/valid-publishable-targets.json" "${SCRIPT_DIR}/generate-bake.sh" --metadata "${METADATA_FIXTURE}" --json
validate_bake_summary "${FIXTURE_DIR}/valid-publishable-targets.json"
expect_summary_fail "skipped row leaked into targets" "${FIXTURE_DIR}/skipped-combination.json" "skipped combinations are omitted"
expect_summary_fail "default git context rejected" "${FIXTURE_DIR}/default-git-context.json" "checkout/path context|default Git context"
expect_summary_fail "publish output rejected" "${FIXTURE_DIR}/publish-output-enabled.json" "does not push or publish"

tmp_bake="$(mktemp)"
TEMP_BAKE="${tmp_bake}"
"${SCRIPT_DIR}/generate-bake.sh" --metadata "${METADATA_FIXTURE}" --output "${tmp_bake}" >/tmp/story-3-3-bake-generate.out
grep -q 'target "pg18-trixie"' "${tmp_bake}" || {
  diag "generate-bake publishable fixture" "${tmp_bake}" "pg18-trixie target exists" "missing" "Generate Bake targets from publishable metadata rows."
  rm -f "${tmp_bake}"
  exit 1
}
grep -q 'context = "cloudnative-pg-timescaledb"' "${tmp_bake}" || {
  diag "generate-bake publishable fixture" "${tmp_bake}" "cloudnative-pg-timescaledb checkout/path context" "missing" "Use the project subdirectory as local checkout context for Buildx Bake."
  rm -f "${tmp_bake}"
  exit 1
}
if grep -q 'type=registry\|push=true\|ghcr.io' "${tmp_bake}"; then
  diag "generate-bake publishable fixture" "${tmp_bake}" "local Bake output has no registry push" "publish output found" "Keep publish behavior out of Epic 3 local builds."
  rm -f "${tmp_bake}"
  exit 1
fi

tmpdir="$(mktemp -d)"
TEMP_DIR="${tmpdir}"
fake_docker="${tmpdir}/docker"
capture="${tmpdir}/capture.txt"
cat >"${fake_docker}" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${DOCKER_CAPTURE}"
if [[ "$*" == *" --print"* ]]; then
  printf '{"group":{"default":{"targets":["pg18-trixie"]}},"target":{"pg18-trixie":{"context":"."}}}\n'
fi
SH
chmod +x "${fake_docker}"

dockerfile_path="${ROOT_DIR}/cloudnative-pg-timescaledb/generated/18/trixie/Dockerfile"
TEMP_DOCKERFILE="${dockerfile_path}"
created_dockerfile=0
if [[ ! -e "${dockerfile_path}" ]]; then
  created_dockerfile=1
  TEMP_DOCKERFILE_CREATED=1
  printf '# temporary Story 3.3 bake test Dockerfile\n' >"${dockerfile_path}"
fi

DOCKER_CAPTURE="${capture}" DOCKER_BIN="${fake_docker}" BAKE_METADATA="${METADATA_FIXTURE}" BAKE_FILE="${tmp_bake}" make -C "${ROOT_DIR}" bake-print >/tmp/story-3-3-bake-print.out
grep -q 'buildx bake --file' "${capture}" || {
  diag "bake-print fake docker" "${capture}" "docker buildx bake --file is called" "$(cat "${capture}")" "Wire make bake-print to Docker Buildx Bake."
  exit 1
}

: >"${capture}"
DOCKER_CAPTURE="${capture}" DOCKER_BIN="${fake_docker}" BAKE_METADATA="${METADATA_FIXTURE}" BAKE_FILE="${tmp_bake}" make -C "${ROOT_DIR}" build PG=18 DEBIAN=trixie >/tmp/story-3-3-build.out
if ! grep -q 'pg18-trixie.platform=linux/amd64' "${capture}" || ! grep -q 'pg18-trixie.output=type=docker' "${capture}"; then
  diag "build fake docker" "${capture}" "local build overrides platform and output=type=docker" "$(cat "${capture}")" "Keep local builds load-only and single-platform by default."
  exit 1
fi
if grep -q 'push=true\|type=registry\|ghcr.io' "${capture}"; then
  diag "build fake docker" "${capture}" "local build command does not publish" "$(cat "${capture}")" "Do not push images during Epic 3 local build execution."
  exit 1
fi

: >"${capture}"
expect_command_fail "unsafe build args rejected before docker" "no extra Docker Bake passthrough args" env DOCKER_CAPTURE="${capture}" DOCKER_BIN="${fake_docker}" BAKE_METADATA="${METADATA_FIXTURE}" BAKE_FILE="${tmp_bake}" make -C "${ROOT_DIR}" build PG=18 DEBIAN=trixie BUILD_ARGS='--set pg18-trixie.output=type=registry,push=true'
if [[ -s "${capture}" ]]; then
  diag "build unsafe args" "${capture}" "Docker is not invoked after unsafe BUILD_ARGS" "$(cat "${capture}")" "Reject passthrough Bake args before calling Docker."
  exit 1
fi

expect_command_fail "skipped build diagnostic" "target=pg19beta1-trixie.*PG=19beta1.*DEBIAN=trixie|PG=19beta1.*DEBIAN=trixie.*target=pg19beta1-trixie" env BAKE_METADATA="${METADATA_FIXTURE}" BAKE_FILE="${tmp_bake}" "${SCRIPT_DIR}/build.sh" 19beta1 trixie

[[ "${created_dockerfile}" == "1" ]] && rm -f "${dockerfile_path}"
TEMP_DOCKERFILE_CREATED=0
rm -rf "${tmpdir}" "${tmp_bake}"
TEMP_DIR=""
TEMP_BAKE=""

printf 'PASS story-3.3 bake contracts\n'
