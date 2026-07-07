#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/cleanup-ghcr-versions.py"
FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ghcr-cleanup/fixtures/package-versions.json"
WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"
MANUAL_WORKFLOW="${ROOT_DIR}/.github/workflows/ghcr-cleanup.yml"

summary="$(mktemp)"
recent_summary=""
trap 'rm -f "${summary}" "${recent_summary}"' EXIT

"${SCRIPT}" \
  --owner pnetcloud \
  --owner-kind users \
  --package cloudnative-pg-timescaledb \
  --image ghcr.io/pnetcloud/cloudnative-pg-timescaledb \
  --versions-file "${FIXTURE}" \
  --candidate-prefix candidate- \
  --delete-candidates \
  --delete-signature-tags \
  --delete-untagged \
  --protected-digest sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  --detach-mixed-candidates \
  --dry-run >"${summary}"

python3 - "${summary}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
selected_ids = {row["id"] for row in payload["selected"]}
mixed_ids = {row["id"] for row in payload["skipped_mixed_tags"]}
signature_ids = {row["id"] for row in payload["signature_selected"]}
signature_mixed_ids = {row["id"] for row in payload["signature_skipped_mixed_tags"]}
untagged_ids = {row["id"] for row in payload["untagged_selected"]}
untagged_protected_ids = {row["id"] for row in payload["untagged_skipped_protected"]}
untagged_unknown_ids = {row["id"] for row in payload["untagged_skipped_unknown_digest"]}

if selected_ids != {101, 105}:
    raise SystemExit(f"unexpected selected ids: {sorted(selected_ids)}")
if mixed_ids != {103}:
    raise SystemExit(f"unexpected mixed-tag skipped ids: {sorted(mixed_ids)}")
if signature_ids != {106}:
    raise SystemExit(f"unexpected signature selected ids: {sorted(signature_ids)}")
if signature_mixed_ids != {107}:
    raise SystemExit(f"unexpected signature mixed-tag skipped ids: {sorted(signature_mixed_ids)}")
if untagged_ids != {104}:
    raise SystemExit(f"unexpected untagged selected ids: {sorted(untagged_ids)}")
if untagged_protected_ids != {108}:
    raise SystemExit(f"unexpected protected untagged skipped ids: {sorted(untagged_protected_ids)}")
if untagged_unknown_ids != {109}:
    raise SystemExit(f"unexpected unknown digest untagged skipped ids: {sorted(untagged_unknown_ids)}")
if payload["mixed_candidate_tags"] != ["candidate-123-1-pg17-bookworm-index"]:
    raise SystemExit(f"unexpected mixed candidate tags: {payload['mixed_candidate_tags']}")
if payload["detached_mixed_tags"] != ["candidate-123-1-pg17-bookworm-index"]:
    raise SystemExit(f"unexpected detached mixed tags: {payload['detached_mixed_tags']}")
if payload["deleted_count"] != 0 or not payload["dry_run"]:
    raise SystemExit(f"fixture cleanup must be dry-run only: {payload}")
if payload["selected_count"] != 2 or payload["skipped_mixed_tag_count"] != 1:
    raise SystemExit(f"unexpected cleanup counts: {payload}")
if payload["signature_selected_count"] != 1 or payload["signature_skipped_mixed_tag_count"] != 1:
    raise SystemExit(f"unexpected signature cleanup counts: {payload}")
if payload["signature_deleted_count"] != 0:
    raise SystemExit(f"dry-run must not delete signature versions: {payload}")
if payload["untagged_selected_count"] != 1 or payload["untagged_deleted_count"] != 0:
    raise SystemExit(f"unexpected untagged cleanup counts: {payload}")
if payload["protected_digest_count"] != 1:
    raise SystemExit(f"unexpected protected digest count: {payload}")
if payload["untagged_skipped_protected_count"] != 1 or payload["untagged_skipped_unknown_digest_count"] != 1:
    raise SystemExit(f"unexpected untagged skip counts: {payload}")
if payload["post_detach_deleted_count"] != 0 or payload["post_detach_skipped_mixed_tag_count"] != 0:
    raise SystemExit(f"dry-run must not reload or delete post-detach versions: {payload}")
PY

recent_summary="$(mktemp)"
"${SCRIPT}" \
  --owner pnetcloud \
  --owner-kind users \
  --package cloudnative-pg-timescaledb \
  --image ghcr.io/pnetcloud/cloudnative-pg-timescaledb \
  --versions-file "${FIXTURE}" \
  --candidate-prefix candidate- \
  --min-candidate-age-minutes 120 \
  --now 2026-06-11T00:30:00Z \
  --delete-candidates \
  --detach-mixed-candidates \
  --dry-run >"${recent_summary}"

python3 - "${recent_summary}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
recent_ids = {row["id"] for row in payload["skipped_recent_candidates"]}
if recent_ids != {101, 103, 105}:
    raise SystemExit(f"unexpected recent candidate ids: {sorted(recent_ids)}")
if payload["selected_count"] != 0 or payload["skipped_mixed_tag_count"] != 0:
    raise SystemExit(f"recent candidate guard must prevent broad cleanup selection: {payload}")
if payload["mixed_candidate_tags"] or payload["detached_mixed_tags"]:
    raise SystemExit(f"recent mixed candidates must not be tombstoned: {payload}")
if payload["min_candidate_age_minutes"] != 120:
    raise SystemExit(f"summary must expose candidate age guard: {payload}")
PY

python3 - "${WORKFLOW}" "${MANUAL_WORKFLOW}" <<'PY'
import sys
from pathlib import Path

required = [
    "--delete-candidates",
    "--delete-signature-tags",
    "--protected-digests-file",
    "--detach-mixed-candidates",
    "Collect protected release digests",
    "inspect_release_ref",
    "attestation-manifest",
    ".platform.architecture",
    "Release ref not inspectable yet",
    "sleep 10",
    "Verify public pulls after cleanup",
    "docker pull --platform",
    "pull_public_ref",
    "--min-candidate-age-minutes",
]
for workflow in sys.argv[1:]:
    text = Path(workflow).read_text()
    missing = [item for item in required if item not in text]
    if missing:
        raise SystemExit(f"workflow cleanup coverage missing in {workflow}: {missing}")
    if "--delete-untagged" not in text:
        raise SystemExit(f"workflow cleanup must support guarded untagged deletion: {workflow}")
    if "ghcr-cleanup/output/protected-digests.txt" not in text:
        raise SystemExit(f"workflow must protect release manifest digests before deleting untagged GHCR versions: {workflow}")
    if "cloudnative-pg-timescaledb/scripts/ci-retry.sh bash -c" not in text or "docker login ghcr.io" not in text or "GHCR_TOKEN" not in text:
        raise SystemExit(f"workflow must retry GHCR cleanup login: {workflow}")

manual = Path(sys.argv[2]).read_text()
for marker in [
    "workflow_dispatch:",
    "dry_run:",
    "default: 'true'",
    "Normalize final release indexes",
    "normalize-release-indexes.sh",
    "normalize_release_index_with_retry",
    "CI_RETRY_ATTEMPTS=3 CI_RETRY_DELAY_SECONDS=20 cloudnative-pg-timescaledb/scripts/ci-retry.sh",
    "curl_json_with_retry",
    "--retry-all-errors",
    "Manual cleanup public pull not ready",
    "--min-candidate-age-minutes 120",
    "skipped_recent_candidate_count",
    "--summary-file ghcr-cleanup/output/cleanup-summary.json",
    "Public GHCR tag list still contains candidate-* or sha256-* tags.",
]:
    if marker not in manual:
        raise SystemExit(f"manual cleanup workflow missing marker: {marker}")
PY

python3 - "${SCRIPT}" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
for marker in [
    "RETRY_HTTP_STATUS",
    "RETRY_ATTEMPTS",
    "urllib.error.URLError",
    "retry_delay(attempt)",
    "tombstone push not ready",
    "skipped_recent_candidates",
    "min_candidate_age_minutes",
]:
    if marker not in text:
        raise SystemExit(f"cleanup script retry coverage missing marker: {marker}")
PY

printf 'PASS GHCR candidate cleanup fixtures\n'
