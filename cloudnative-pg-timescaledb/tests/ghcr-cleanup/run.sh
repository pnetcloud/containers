#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/cleanup-ghcr-versions.py"
FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ghcr-cleanup/fixtures/package-versions.json"
WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"
MANUAL_WORKFLOW="${ROOT_DIR}/.github/workflows/ghcr-cleanup.yml"

summary="$(mktemp)"
trap 'rm -f "${summary}"' EXIT

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

manual = Path(sys.argv[2]).read_text()
for marker in [
    "workflow_dispatch:",
    "dry_run:",
    "default: 'true'",
    "--summary-file ghcr-cleanup/output/cleanup-summary.json",
    "Public GHCR tag list still contains candidate-* or sha256-* tags.",
]:
    if marker not in manual:
        raise SystemExit(f"manual cleanup workflow missing marker: {marker}")
PY

printf 'PASS GHCR candidate cleanup fixtures\n'
