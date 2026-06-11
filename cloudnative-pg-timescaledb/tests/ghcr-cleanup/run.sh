#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/cleanup-ghcr-versions.py"
FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ghcr-cleanup/fixtures/package-versions.json"

summary="$(mktemp)"
trap 'rm -f "${summary}"' EXIT

"${SCRIPT}" \
  --owner pnetcloud \
  --owner-kind users \
  --package cloudnative-pg-timescaledb \
  --versions-file "${FIXTURE}" \
  --candidate-prefix candidate- \
  --delete-candidates \
  --dry-run >"${summary}"

python3 - "${summary}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
selected_ids = {row["id"] for row in payload["selected"]}
mixed_ids = {row["id"] for row in payload["skipped_mixed_tags"]}

if selected_ids != {101, 105}:
    raise SystemExit(f"unexpected selected ids: {sorted(selected_ids)}")
if mixed_ids != {103}:
    raise SystemExit(f"unexpected mixed-tag skipped ids: {sorted(mixed_ids)}")
if payload["deleted_count"] != 0 or not payload["dry_run"]:
    raise SystemExit(f"fixture cleanup must be dry-run only: {payload}")
if payload["selected_count"] != 2 or payload["skipped_mixed_tag_count"] != 1:
    raise SystemExit(f"unexpected cleanup counts: {payload}")
PY

printf 'PASS GHCR candidate cleanup fixtures\n'
