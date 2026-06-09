#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TAG_VALIDATION_DATE="${TAG_VALIDATION_DATE:-20260609}"

"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-metadata.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-tags.sh" --metadata "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" --date "${TAG_VALIDATION_DATE}"
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-generated.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh"
STORY_1_2_VALIDATE_REENTRY=1 "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh"
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/metadata/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/metadata/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/tags/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/tags/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generators/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/dockerfile/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/dockerfile/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/package-install/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/package-install/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/bake/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/matrix/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/matrix/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/container/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/container/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/sql/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/smoke/sql/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generated-drift/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/generated-drift/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/cnpg-resolver/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/cnpg-resolver/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/packagecloud/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/packagecloud/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/update/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/update/run.sh"
fi
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-workflows.sh"
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/build-candidates/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/security-scan/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/security-scan/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-evidence/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-evidence/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/update-autocommit/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/renovate/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/renovate/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/barman-plugin/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/barman-plugin/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/barman-plugin/run.sh"
fi
printf 'PASS make validate Story 1.2 available gates\n'
