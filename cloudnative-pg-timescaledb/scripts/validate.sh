#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TAG_VALIDATION_DATE="${TAG_VALIDATION_DATE:-${DATE:-}}"

"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh"
printf 'PASS make validate Story 1.2 command-surface gates\n'
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-metadata.sh"
if [[ -z "${TAG_VALIDATION_DATE}" ]]; then
  TAG_VALIDATION_DATE="$(python3 - "${ROOT_DIR}" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "cloudnative-pg-timescaledb" / "scripts" / "lib"))
from generator_contract import parse_metadata, release_date  # noqa: E402

metadata = root / "cloudnative-pg-timescaledb" / "versions.yaml"
data = parse_metadata(metadata, "make validate")
print(release_date("make validate", data["entries"], metadata))
PY
)"
fi
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-tags.sh" --metadata "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" --date "${TAG_VALIDATION_DATE}"
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-generated.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-docs.sh"
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-barman-boundary.sh"
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
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ci-apt-install/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ci-apt-install/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ci-retry/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ci-retry/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ci-git-push/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ci-git-push/run.sh"
fi
"${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-workflows.sh"
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/permissions/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/workflows/summaries/run.sh"
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
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/publish-tag-promotion/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ghcr-cleanup/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/ghcr-cleanup/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/catalog/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/catalog/run.sh"
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
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/readme/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/readme/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/tags/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/tags/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/catalog/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/catalog/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/verification/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/verification/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/maintainer/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/troubleshooting/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/troubleshooting/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-rehearsal/run.sh"
fi
if [[ -x "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs-validation/run.sh" ]]; then
  "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs-validation/run.sh"
fi
printf 'PASS make validate Story 1.2 available gates\n'
