#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/ci-git-push.sh"

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
printf 'sleep %s\n' "$*" >> "${CI_GIT_PUSH_CAPTURE:?}"
SH
chmod +x "${tmp}/bin/sleep"

cat >"${tmp}/bin/git" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'git %s\n' "$*" >> "${CI_GIT_PUSH_CAPTURE:?}"
case "${1:-}" in
  push)
    count_file="${CI_GIT_PUSH_STATE:?}/push-count"
    count=0
    if [[ -f "${count_file}" ]]; then
      count="$(cat "${count_file}")"
    fi
    count=$((count + 1))
    printf '%s\n' "${count}" > "${count_file}"
    fail_count="${CI_GIT_PUSH_FAIL_COUNT:-0}"
    if ((count <= fail_count)); then
      exit 1
    fi
    ;;
  fetch)
    ;;
  rebase)
    ;;
  *)
    printf 'unexpected git command: %s\n' "${1:-missing}" >&2
    exit 64
    ;;
esac
SH
chmod +x "${tmp}/bin/git"

if CI_RETRY_ATTEMPTS=bad "${SCRIPT}" >/tmp/ci-git-push-bad-config.out 2>&1; then
  diag "ci-git-push" "${SCRIPT}" "invalid retry config fails" "exit 0" "Reject invalid retry settings before issuing git commands."
  exit 1
fi
if ! grep -Fq 'positive integer attempts' /tmp/ci-git-push-bad-config.out; then
  diag "ci-git-push" "/tmp/ci-git-push-bad-config.out" "invalid config diagnostic is actionable" "$(cat /tmp/ci-git-push-bad-config.out)" "Use standard diagnostics for invalid helper configuration."
  exit 1
fi

PATH="${tmp}/bin:${PATH}" \
CI_GIT_PUSH_CAPTURE="${capture}" \
CI_GIT_PUSH_STATE="${tmp}/state" \
CI_GIT_PUSH_FAIL_COUNT=2 \
CI_RETRY_ATTEMPTS=3 \
CI_RETRY_DELAY_SECONDS=0 \
  "${SCRIPT}" origin HEAD:main >/tmp/ci-git-push-retry.out 2>&1

push_count="$(grep -c '^git push origin HEAD:main$' "${capture}")"
sleep_count="$(grep -c '^sleep 0$' "${capture}")"
if [[ "${push_count}" != "3" || "${sleep_count}" != "2" ]]; then
  diag "ci-git-push retry" "${capture}" "push retries twice then succeeds" "push=${push_count} sleep=${sleep_count}: $(tr '\n' ';' <"${capture}")" "Keep autocommit pushes wrapped in bounded retry for transient GitHub transport failures."
  exit 1
fi

: > "${capture}"
rm -f "${tmp}/state/push-count"
PATH="${tmp}/bin:${PATH}" \
CI_GIT_PUSH_CAPTURE="${capture}" \
CI_GIT_PUSH_STATE="${tmp}/state" \
CI_GIT_PUSH_FAIL_COUNT=1 \
CI_RETRY_ATTEMPTS=2 \
CI_RETRY_DELAY_SECONDS=0 \
CI_GIT_PUSH_FETCH_REF=main \
CI_GIT_PUSH_REBASE_REF=origin/main \
  "${SCRIPT}" >/tmp/ci-git-push-rebase.out 2>&1

python3 - "${capture}" <<'PY'
import sys
from pathlib import Path

actual = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "git push",
    "git fetch --no-tags --prune --depth=1 origin main",
    "git rebase origin/main",
    "sleep 0",
    "git push",
]
if actual != expected:
    raise SystemExit(
        "command: ci-git-push rebase\n"
        f"artifact: {sys.argv[1]}\n"
        "expected: failed push refreshes branch and rebases before retry\n"
        f"actual: {';'.join(actual)}\n"
        "remediation: Recover from non-fast-forward autocommit races by rebasing generated commits onto the fresh branch tip before retrying push."
    )
PY

printf 'PASS ci git push helper\n'
