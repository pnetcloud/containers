#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh"
STORY_1_2_VALIDATE_REENTRY=1 "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh"
printf 'PASS make validate Story 1.2 available gates\n'
