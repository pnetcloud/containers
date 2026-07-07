#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/ci-retry.sh"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp}"
}
trap cleanup EXIT

mkdir -p "${tmp}/bin" "${tmp}/state"
capture="${tmp}/capture.log"

cat >"${tmp}/bin/sleep" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'sleep %s\n' "$*" >> "${CI_RETRY_CAPTURE:?}"
SH
chmod +x "${tmp}/bin/sleep"

cat >"${tmp}/bin/flaky-download" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'flaky-download %s\n' "$*" >> "${CI_RETRY_CAPTURE:?}"
count_file="${CI_RETRY_STATE:?}/count"
count=0
if [[ -f "${count_file}" ]]; then
  count="$(cat "${count_file}")"
fi
count=$((count + 1))
printf '%s\n' "${count}" > "${count_file}"
if ((count < 3)); then
  exit 42
fi
SH
chmod +x "${tmp}/bin/flaky-download"

if "${SCRIPT}" >/tmp/ci-retry-empty.out 2>&1; then
  diag "ci-retry" "${SCRIPT}" "empty command fails" "exit 0" "Reject empty retry invocations so workflow call sites remain explicit."
  exit 1
fi
if ! grep -Fq 'at least one command argument' /tmp/ci-retry-empty.out; then
  diag "ci-retry" "/tmp/ci-retry-empty.out" "empty command diagnostic is actionable" "$(cat /tmp/ci-retry-empty.out)" "Use standard diagnostics for invalid helper usage."
  exit 1
fi

PATH="${tmp}/bin:${PATH}" \
CI_RETRY_CAPTURE="${capture}" \
CI_RETRY_STATE="${tmp}/state" \
CI_RETRY_ATTEMPTS=3 \
CI_RETRY_DELAY_SECONDS=0 \
  "${SCRIPT}" flaky-download module-cache >/tmp/ci-retry-success.out 2>&1

command_count="$(grep -c '^flaky-download module-cache$' "${capture}")"
sleep_count="$(grep -c '^sleep 0$' "${capture}")"
if [[ "${command_count}" != "3" || "${sleep_count}" != "2" ]]; then
  diag "ci-retry retry" "${capture}" "command retries twice then succeeds" "command=${command_count} sleep=${sleep_count}: $(tr '\n' ';' <"${capture}")" "Keep dependency download commands wrapped in bounded retry for transient network failures."
  exit 1
fi
if [[ "$(grep -c 'CI command failed with exit 42' /tmp/ci-retry-success.out)" != "2" ]]; then
  diag "ci-retry diagnostics" "/tmp/ci-retry-success.out" "retry log preserves failing command exit status" "$(cat /tmp/ci-retry-success.out)" "Capture the failed command status before retrying so CI logs explain transient failures."
  exit 1
fi

printf 'PASS ci retry helper\n'
