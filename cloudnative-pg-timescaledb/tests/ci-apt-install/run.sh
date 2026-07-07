#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/ci-apt-install.sh"

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

cat >"${tmp}/bin/sudo" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
"$@"
SH
chmod +x "${tmp}/bin/sudo"

cat >"${tmp}/bin/sleep" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'sleep %s\n' "$*" >> "${APT_CAPTURE:?}"
SH
chmod +x "${tmp}/bin/sleep"

cat >"${tmp}/bin/apt-get" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'apt-get %s\n' "$*" >> "${APT_CAPTURE:?}"
case "${1:-}" in
  update)
    count_file="${APT_STATE:?}/update-count"
    count=0
    if [[ -f "${count_file}" ]]; then
      count="$(cat "${count_file}")"
    fi
    count=$((count + 1))
    printf '%s\n' "${count}" > "${count_file}"
    if ((count < 3)); then
      exit 100
    fi
    ;;
  install)
    shift
    if [[ "$*" != "-y --no-install-recommends shellcheck jq" ]]; then
      printf 'unexpected install args: %s\n' "$*" >&2
      exit 64
    fi
    ;;
  *)
    printf 'unexpected apt-get command: %s\n' "${1:-missing}" >&2
    exit 64
    ;;
esac
SH
chmod +x "${tmp}/bin/apt-get"

if "${SCRIPT}" >/tmp/ci-apt-install-empty.out 2>&1; then
  diag "ci-apt-install" "${SCRIPT}" "empty package list fails" "exit 0" "Reject empty package lists so workflow call sites are explicit."
  exit 1
fi
if ! grep -Fq 'at least one package' /tmp/ci-apt-install-empty.out; then
  diag "ci-apt-install" "/tmp/ci-apt-install-empty.out" "empty package diagnostic is actionable" "$(cat /tmp/ci-apt-install-empty.out)" "Use standard diagnostics for invalid helper usage."
  exit 1
fi

PATH="${tmp}/bin:${PATH}" \
APT_CAPTURE="${capture}" \
APT_STATE="${tmp}/state" \
APT_RETRY_ATTEMPTS=3 \
APT_RETRY_DELAY_SECONDS=0 \
  "${SCRIPT}" shellcheck jq >/tmp/ci-apt-install-retry.out 2>&1

update_count="$(grep -c '^apt-get update$' "${capture}")"
install_count="$(grep -c '^apt-get install -y --no-install-recommends shellcheck jq$' "${capture}")"
sleep_count="$(grep -c '^sleep 0$' "${capture}")"
if [[ "${update_count}" != "3" || "${install_count}" != "1" || "${sleep_count}" != "2" ]]; then
  diag "ci-apt-install retry" "${capture}" "update retries twice then installs requested packages" "update=${update_count} install=${install_count} sleep=${sleep_count}: $(tr '\n' ';' <"${capture}")" "Keep apt update/install wrapped in bounded retry for transient runner mirror failures."
  exit 1
fi
if [[ "$(grep -c 'apt command failed with exit 100' /tmp/ci-apt-install-retry.out)" != "2" ]]; then
  diag "ci-apt-install retry diagnostics" "/tmp/ci-apt-install-retry.out" "retry log preserves failing apt exit status" "$(cat /tmp/ci-apt-install-retry.out)" "Capture the failed command status before retrying so CI logs explain transient apt failures."
  exit 1
fi

printf 'PASS ci apt install retry helper\n'
