#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/build-candidates/fixtures"
WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"
METADATA_VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-candidate-metadata.py"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

expect_fail() {
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
    diag "${*}" "${description}" "command fails" "passed" "Make the invalid candidate fixture fail its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! tr '\n' ' ' <"${tmp}" | grep -E -q "${pattern}"; then
    diag "${*}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep candidate diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

validate_workflow_candidate_gate() {
  local file="$1"
  python3 - "${file}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines()
command = f"validate candidate workflow {path}"


def fail(expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def require(condition, expected, actual, remediation):
    if not condition:
        fail(expected, actual, remediation)


def first_line(pattern):
    for idx, line in enumerate(lines, start=1):
        if re.search(pattern, line):
            return idx
    return 0


require("pull_request:" not in text, "candidate GHCR push workflow excludes pull_request trigger", "pull_request present", "Keep write-token candidate publishing on push/workflow_dispatch only; validate.yml covers PRs.")
require("docker/build-push-action" not in text and "defaultContext" not in text, "Buildx/Bake uses checkout path context, not default Git context", "default Git context marker found", "Use checkout plus docker buildx bake CLI from the repository workspace.")
require("actions/checkout@" in text, "workflow checks out repository before generated-file builds", "checkout missing", "Generated Dockerfiles and Bake files must come from checkout path context.")
if "skipped_summary=\"$(python3 -c" in text:
    require("row.get(\"pg_major\")" in text and "row.get('pg_major')" not in text, "matrix skipped summary inline Python is shell-quoted safely", "unsafe single-quoted row.get found", "Do not put single quotes inside a single-quoted python3 -c workflow command.")
require("qemu-user-static" in text and "update-binfmts --enable qemu-aarch64" in text, "workflow prepares arm64 emulation for per-platform smoke", "qemu/binfmt setup missing", "Enable qemu-aarch64 before running arm64 candidate smoke on ubuntu-latest.")
if path.name == "build.yml":
    require("Buildx bootstrap not ready yet" in text and "sleep 10" in text, "BuildKit bootstrap retries transient Docker Hub or runner network failures", "Buildx bootstrap retry missing", "Retry docker buildx inspect --bootstrap because pulling the BuildKit image can time out on GitHub runners.")
require("docker buildx bake --file cloudnative-pg-timescaledb/docker-bake.hcl" in text, "candidate job uses Docker Buildx Bake", "Buildx Bake command missing", "Build release candidates through generated Bake targets.")
require('.context=.' not in text, "candidate job does not override generated Bake context to repository root", "stale .context=. override found", "Use the generated cloudnative-pg-timescaledb Bake context so generated Dockerfiles can COPY project-local scripts.")
require('imagetools inspect "${candidate_ref}" --raw' in text and "expected_platform" in text and 'manifest.get("platform")' in text, "workflow extracts per-platform digest from raw manifest data", "raw platform digest extraction missing", "Do not record a top-level index digest as a single-platform digest.")
if path.name == "build.yml":
    require("Candidate ref not inspectable yet" in text and "sleep 10" in text, "candidate manifest inspect retries after registry push", "inspect retry missing", "Retry imagetools inspect because GHCR may be briefly eventually consistent after Buildx pushes a new candidate tag.")
require("--sbom=true" in text and "--provenance=mode=max" in text, "candidate Buildx Bake emits SBOM and provenance attestations", "attestation flags missing", "Build the candidate index with BuildKit attestations before release evidence signing.")
require("attestation-manifest" in text, "candidate workflow checks BuildKit attestation manifests exist", "attestation manifest check missing", "Fail candidate metadata when BuildKit does not attach SBOM/provenance attestations.")
require("output=type=registry,push=true" in text, "candidate job pushes candidate refs to registry", "registry push output missing", "Push only candidate references for downstream gates.")
require("candidate-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" in text, "candidate refs are run-scoped", "run-scoped candidate tag missing", "Do not push rolling or final release tags in Story 4.2.")
require("${IMAGE}:latest" not in text and ":latest" not in text, "candidate job does not push latest", "latest reference found", "Leave latest promotion to later publish stories.")
require(not re.search(r"\.tags=\$\{IMAGE\}:[0-9]+-pg", text), "candidate job does not push immutable final release tags", "final release tag push found", "Use candidate-scoped tags only in Story 4.2.")
require("CHECKS=container make smoke" in text and "CHECKS=sql make smoke" in text, "container and SQL smoke run for each platform candidate", "required smoke commands missing", "Run both smoke gates before candidate manifest creation.")
require("SMOKE_EXPECTED_PLATFORM" in text and "dpkg --print-architecture" in text, "runtime architecture is verified and recorded", "architecture smoke marker missing", "Map dpkg architecture to expected platform before metadata emission.")

container_line = first_line(r"CHECKS=container make smoke")
sql_line = first_line(r"CHECKS=sql make smoke")
upload_line = first_line(r"release-candidate-\$\{\{ matrix\.bake_target \}\}")
require(container_line and sql_line and upload_line and container_line < upload_line and sql_line < upload_line, "container and SQL smoke happen before candidate metadata upload", {"container": container_line, "sql": sql_line, "upload": upload_line}, "Do not hand off candidate metadata before every platform smoke gate passes.")
require("validate-candidate-metadata.py --file" in text, "workflow validates candidate metadata before upload", "metadata validator missing", "Reject incomplete or inconsistent candidate artifacts in the build job.")
require("actions/upload-artifact@" in text and "release-candidate-${{ matrix.bake_target }}" in text, "candidate metadata artifact is uploaded", "artifact upload missing", "Expose immutable candidate metadata to downstream release stories.")
require("packages: write" in text, "candidate job has explicit GHCR push permission", "packages write missing", "Use job-level least privilege for GHCR candidate pushes.")
publish_match = re.search(r"\n  publish:\n(?P<body>[\s\S]+?)(?:\n  [A-Za-z0-9_-]+:|\Z)", text)
require(publish_match, "build workflow has publish job", "publish job missing", "Final tag promotion must be explicit and guarded.")
publish_body = publish_match.group("body")
for marker in ["github.event_name == 'workflow_dispatch'", "github.ref == 'refs/heads/main'", "startsWith(github.ref, 'refs/tags/')"]:
    require(marker in publish_body, f"publish job is guarded by {marker}", publish_body[:500], "Restrict final tag promotion to manual, main, or tag release contexts.")
require("needs.matrix.outputs.has_include == 'true'" in publish_body, "publish job still requires non-empty generated matrix", publish_body[:500], "Publish only generated publishable rows.")
PY
}

for fixture in \
  valid-candidate-metadata.json \
  default-git-context.yml \
  smoke-after-publish.yml \
  missing-platform-smoke.json \
  missing-platform-record.json \
  wrong-runtime-architecture.json \
  final-tag-pushed-in-candidate-job.yml \
  experimental-enters-publish-path.json; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 4.2 fixture exists" "missing" "Restore the complete build-candidates fixture set."
    exit 1
  }
done

"${METADATA_VALIDATOR}" --file "${FIXTURE_DIR}/valid-candidate-metadata.json"
expect_fail "missing per-platform smoke digest coverage" "platform_digests keys exactly match platforms" "${METADATA_VALIDATOR}" --file "${FIXTURE_DIR}/missing-platform-smoke.json"
expect_fail "missing per-platform metadata record" "records cover every declared platform" "${METADATA_VALIDATOR}" --file "${FIXTURE_DIR}/missing-platform-record.json"
expect_fail "wrong runtime architecture" "runtime architecture maps" "${METADATA_VALIDATOR}" --file "${FIXTURE_DIR}/wrong-runtime-architecture.json"
expect_fail "experimental row enters publish path with normal tag" "normal rolling/latest" "${METADATA_VALIDATOR}" --file "${FIXTURE_DIR}/experimental-enters-publish-path.json"

validate_workflow_candidate_gate "${WORKFLOW}"
expect_fail "default Git context workflow" "checkout path context" validate_workflow_candidate_gate "${FIXTURE_DIR}/default-git-context.yml"
expect_fail "smoke after publish workflow" "smoke happen before" validate_workflow_candidate_gate "${FIXTURE_DIR}/smoke-after-publish.yml"
expect_fail "final tag pushed in candidate job" "final release tags" validate_workflow_candidate_gate "${FIXTURE_DIR}/final-tag-pushed-in-candidate-job.yml"

grep -Fq 'Release Candidate Metadata Schema' "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md" || {
  diag "grep release candidate schema" "cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md" "schema heading exists" "missing" "Regenerate docs so downstream release stories can consume the candidate artifact schema."
  exit 1
}

printf 'PASS story-4.2 build candidate workflow fixtures\n'
