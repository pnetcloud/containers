#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/update/fixtures"
CNPG_FIXTURES="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures"
PKG_FIXTURES="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/packagecloud/fixtures"
BARMAN_PLUGIN_FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/current-reference.json"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

prepare_project() {
  local target="$1"
  mkdir -p "${target}"
  cp "${ROOT_DIR}/Makefile" "${target}/Makefile"
  mkdir -p "${target}/cloudnative-pg-timescaledb" "${target}/docs"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts" "${target}/cloudnative-pg-timescaledb/scripts"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/templates" "${target}/cloudnative-pg-timescaledb/templates"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/generated" "${target}/cloudnative-pg-timescaledb/generated"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/catalog" "${target}/cloudnative-pg-timescaledb/catalog"
  mkdir -p "${target}/cloudnative-pg-timescaledb/docs/generated"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/compatibility.md" "${target}/cloudnative-pg-timescaledb/docs/generated/compatibility.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/compatibility-table.md" "${target}/cloudnative-pg-timescaledb/docs/generated/compatibility-table.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md" "${target}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md" "${target}/cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md" "${target}/cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md" "${target}/cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md" "${target}/cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/versions.yaml" "${target}/cloudnative-pg-timescaledb/versions.yaml"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docker-bake.hcl" "${target}/cloudnative-pg-timescaledb/docker-bake.hcl"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/matrix.json" "${target}/cloudnative-pg-timescaledb/matrix.json"
  if [[ -f "${ROOT_DIR}/docs/generator-contracts.md" ]]; then
    cp "${ROOT_DIR}/docs/generator-contracts.md" "${target}/docs/generator-contracts.md"
  fi
  python3 - "${target}/cloudnative-pg-timescaledb/versions.yaml" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = re.sub(r'(    pg_version: ")17\.[0-9]+("\n    debian_variant:)', r'\g<1>17\2', text)
text = re.sub(r'(    pg_version: ")18\.[0-9]+("\n    debian_variant:)', r'\g<1>18\2', text)
text = re.sub(r'(    cnpg_tag: ")17\.[0-9]+-standard-', r'\g<1>17-standard-', text)
text = re.sub(r'(    cnpg_tag: ")18\.[0-9]+-standard-', r'\g<1>18-standard-', text)
for field in ["cnpg_digest", "timescaledb_version", "timescaledb_package_version", "toolkit_version", "toolkit_package_version"]:
    text = re.sub(rf'(    {field}: )"[^"]*"', rf'\1""', text)
text = re.sub(r'    publish: true', '    publish: false', text)
text = re.sub(r'    skip_reason: ""', '    skip_reason: "Pending resolver update fixture"', text)
text = re.sub(r'\n    tags: \[[^\n]*\]', '', text)
path.write_text(text)
PY
  (cd "${target}" && git init -q && git config user.email test@example.invalid && git config user.name test && git add . && git commit -qm baseline)
}

prepare_upstream() {
  local target="$1"
  mkdir -p "${target}"
  ln -s "${CNPG_FIXTURES}" "${target}/cnpg"
  ln -s "${PKG_FIXTURES}" "${target}/packages"
}

run_update() {
  local project="$1"
  local upstream="$2"
  local stdout_file="$3"
  local stderr_file="$4"
  set +e
  (cd "${project}" && BARMAN_PLUGIN_FIXTURE="${BARMAN_PLUGIN_FIXTURE}" make --no-print-directory update UPDATE_ARGS="--fixtures ${upstream} --json") >"${stdout_file}" 2>"${stderr_file}"
  local status="$?"
  set -e
  return "${status}"
}

assert_json_success() {
  local file="$1"
  local expected_changed="$2"
  python3 - "${file}" "${expected_changed}" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
required = {"changed", "updated_entries", "barman_plugin", "old", "new", "generated", "summary_path", "exit_code", "failure_reason"}
if set(payload) != required:
    raise SystemExit(f"wrong update JSON keys: {sorted(payload)}")
if payload["exit_code"] != 0 or payload["failure_reason"] != "":
    raise SystemExit(f"expected success JSON: {payload}")
expected = sys.argv[2] == "true"
if payload["changed"] is not expected:
    raise SystemExit(f"expected changed={expected}: {payload}")
PY
}

assert_json_failure() {
  local file="$1"
  python3 - "${file}" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
if payload.get("exit_code") == 0 or not payload.get("failure_reason"):
    raise SystemExit(f"expected failure JSON: {payload}")
if payload.get("changed") is not False or payload.get("generated") != []:
    raise SystemExit(f"failure must not report generated changes: {payload}")
PY
}

assert_allowlisted_status() {
  local project="$1"
  local status
  status="$(cd "${project}" && git status --porcelain --untracked-files=all)"
  if [[ -z "${status}" ]]; then
    diag "git status" "${project}" "changed update fixture has resolver-owned diff" "clean" "Changed update fixtures must leave a deterministic diff."
    exit 1
  fi
  while IFS= read -r line; do
    path="${line:3}"
    case "${path}" in
      cloudnative-pg-timescaledb/versions.yaml|cloudnative-pg-timescaledb/generated/*|cloudnative-pg-timescaledb/docker-bake.hcl|cloudnative-pg-timescaledb/matrix.json|cloudnative-pg-timescaledb/catalog/*|cloudnative-pg-timescaledb/docs/generated/compatibility.md|cloudnative-pg-timescaledb/docs/generated/compatibility-table.md|cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md|cloudnative-pg-timescaledb/docs/generated/matrix-schema.md|cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md|cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md|cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md|cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md) ;;
      *) diag "git status" "${project}" "only resolver-owned metadata and generated artifacts" "${line}" "Keep update diffs reviewable for autocommit."; exit 1 ;;
    esac
  done <<<"${status}"
}

set_entry_field() {
  local file="$1"
  local pg="$2"
  local debian="$3"
  local field="$4"
  local value="$5"
  python3 - "${file}" "${pg}" "${debian}" "${field}" "${value}" <<'PY'
from pathlib import Path
import sys
path, pg, debian, field, value = sys.argv[1:]
lines = Path(path).read_text().splitlines()
in_entry = False
match = False
for i, line in enumerate(lines):
    if line.startswith("  - pg_major:"):
        in_entry = True
        match = line.split(":", 1)[1].strip().strip('"') == pg
        continue
    if in_entry and line.strip().startswith("debian_variant:"):
        match = match and line.split(":", 1)[1].strip() == debian
    if in_entry and match and line.strip().startswith(f"{field}:"):
        lines[i] = f"    {field}: {value}"
        break
Path(path).write_text("\n".join(lines) + "\n")
PY
}

append_unsupported_row() {
  local file="$1"
  python3 - "${file}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text() + '''  - pg_major: "19"
    pg_version: "19"
    debian_variant: bullseye
    cnpg_tag: "19-standard-bullseye"
    cnpg_digest: ""
    timescaledb_version: ""
    timescaledb_package_version: ""
    toolkit_version: ""
    toolkit_package_version: ""
    platforms: ["linux/amd64", "linux/arm64"]
    publish: false
    experimental: true
    latest_eligible: false
    skip_reason: "unsupported test row"
''')
PY
}

assert_fixture_dirs() {
  local fixture
  for fixture in no-op changed-cnpg changed-packages preserve-policy-fields update-resolver-skip-reason preserve-manual-skip-reason hard-fail-publishable-unavailable reject-unsupported-debian-or-pg reject-latest-moved-from-pg18-trixie reject-barman-tooling-in-image-path; do
    [[ -d "${FIXTURE_DIR}/${fixture}" ]] || { diag "test -d" "${FIXTURE_DIR}/${fixture}" "update fixture directory exists" "missing" "Restore Story 2.3 fixture directory."; exit 1; }
    for child in input upstream expected; do
      [[ -d "${FIXTURE_DIR}/${fixture}/${child}" ]] || { diag "test -d" "${FIXTURE_DIR}/${fixture}/${child}" "fixture ${child}/ directory exists" "missing" "Keep update fixtures reviewable with input, upstream, and expected directories."; exit 1; }
    done
    if [[ ! -f "${FIXTURE_DIR}/${fixture}/expected-diff.patch" && ! -f "${FIXTURE_DIR}/${fixture}/expected-no-diff" ]]; then
      diag "test fixture diff marker" "${FIXTURE_DIR}/${fixture}" "expected-diff.patch or expected-no-diff exists" "missing" "Declare whether each update fixture is expected to leave a deterministic diff."
      exit 1
    fi
  done
}

assert_fixture_dirs

base_tmp="$(mktemp -d)"
upstream="${base_tmp}/upstream"
prepare_upstream "${upstream}"

changed_project="${base_tmp}/changed-cnpg"
prepare_project "${changed_project}"
if ! run_update "${changed_project}" "${upstream}" "${base_tmp}/changed.out" "${base_tmp}/changed.err"; then
  diag "make update" "changed-cnpg" "exit 0" "$(cat "${base_tmp}/changed.err")" "Changed resolver fixtures should update deterministically."
  exit 1
fi
assert_json_success "${base_tmp}/changed.out" true
assert_allowlisted_status "${changed_project}"
grep -Fq '18.4-standard-trixie' "${changed_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep 18.4" "changed-cnpg" "CNPG tag updated" "missing" "Update resolver-owned CNPG fields."; exit 1; }

noop_project="${base_tmp}/no-op"
cp -R "${changed_project}" "${noop_project}"
(cd "${noop_project}" && git add . && git commit -qm updated-baseline)
if ! run_update "${noop_project}" "${upstream}" "${base_tmp}/noop.out" "${base_tmp}/noop.err"; then
  diag "make update" "no-op" "exit 0" "$(cat "${base_tmp}/noop.err")" "No-op update should succeed."
  exit 1
fi
assert_json_success "${base_tmp}/noop.out" false
status="$(cd "${noop_project}" && git status --porcelain --untracked-files=all)"
[[ -z "${status}" ]] || { diag "git status" "no-op" "clean" "${status}" "No-op update must not leave file changes."; exit 1; }

digest_upstream="${base_tmp}/digest-upstream"
mkdir -p "${digest_upstream}/cnpg"
cp "${CNPG_FIXTURES}/standard-trixie-valid.json" "${digest_upstream}/cnpg/standard-trixie-valid.json"
cp "${CNPG_FIXTURES}/standard-bookworm-valid.json" "${digest_upstream}/cnpg/standard-bookworm-valid.json"
ln -s "${PKG_FIXTURES}" "${digest_upstream}/packages"
python3 - "${digest_upstream}/cnpg/standard-trixie-valid.json" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text().replace(
    "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    "sha256:9999999999999999999999999999999999999999999999999999999999999999",
)
path.write_text(text)
PY
digest_project="${base_tmp}/changed-existing-digest"
cp -R "${changed_project}" "${digest_project}"
(cd "${digest_project}" && git add . && git commit -qm digest-baseline)
if ! run_update "${digest_project}" "${digest_upstream}" "${base_tmp}/digest.out" "${base_tmp}/digest.err"; then
  diag "make update" "changed-existing-cnpg-digest" "exit 0" "$(cat "${base_tmp}/digest.err")" "Resolver-owned CNPG digest drift should update instead of hard-failing."
  exit 1
fi
assert_json_success "${base_tmp}/digest.out" true
grep -Fq 'sha256:9999999999999999999999999999999999999999999999999999999999999999' "${digest_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep updated digest" "changed-existing-cnpg-digest" "CNPG digest updated" "missing" "Allow update mode to refresh resolver-owned digest drift."; exit 1; }

policy_project="${base_tmp}/policy"
prepare_project "${policy_project}"
set_entry_field "${policy_project}/cloudnative-pg-timescaledb/versions.yaml" "17" "trixie" "skip_reason" '"Manual maintainer hold"'
set_entry_field "${policy_project}/cloudnative-pg-timescaledb/versions.yaml" "17" "trixie" "publish" 'false'
run_update "${policy_project}" "${upstream}" "${base_tmp}/policy.out" "${base_tmp}/policy.err" || { diag "make update" "preserve-policy-fields" "exit 0" "$(cat "${base_tmp}/policy.err")" "Manual policy fields should be preserved."; exit 1; }
grep -Fq 'skip_reason: "Manual maintainer hold"' "${policy_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep manual skip" "preserve-policy-fields" "manual skip preserved" "changed" "Do not overwrite maintainer-authored skip reasons."; exit 1; }

resolver_skip_project="${base_tmp}/resolver-skip"
prepare_project "${resolver_skip_project}"
set_entry_field "${resolver_skip_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "bookworm" "skip_reason" '"resolver:old-reason: stale"'
bad_upstream="${base_tmp}/bad-upstream"
mkdir -p "${bad_upstream}"
ln -s "${CNPG_FIXTURES}" "${bad_upstream}/cnpg"
mkdir -p "${bad_upstream}/packages"
ln -s "${PKG_FIXTURES}/trixie-amd64-available.json" "${bad_upstream}/packages/trixie-amd64-available.json"
ln -s "${PKG_FIXTURES}/trixie-arm64-available.json" "${bad_upstream}/packages/trixie-arm64-available.json"
ln -s "${PKG_FIXTURES}/bookworm-amd64-available.json" "${bad_upstream}/packages/bookworm-amd64-available.json"
ln -s "${PKG_FIXTURES}/missing-toolkit-bookworm-arm64.json" "${bad_upstream}/packages/bookworm-arm64-available.json"
run_update "${resolver_skip_project}" "${bad_upstream}" "${base_tmp}/resolver-skip.out" "${base_tmp}/resolver-skip.err" || { diag "make update" "update-resolver-skip-reason" "exit 0" "$(cat "${base_tmp}/resolver-skip.err")" "Resolver-prefixed skip reasons should be updateable."; exit 1; }
grep -Fq 'resolver:missing-toolkit:' "${resolver_skip_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep resolver skip" "update-resolver-skip-reason" "resolver skip updated" "missing" "Update resolver-prefixed skip reasons."; exit 1; }

hard_project="${base_tmp}/hard-fail"
prepare_project "${hard_project}"
set_entry_field "${hard_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "bookworm" "publish" 'true'
set_entry_field "${hard_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "bookworm" "skip_reason" '""'
(cd "${hard_project}" && git add . && git commit -qm hard-input)
if run_update "${hard_project}" "${bad_upstream}" "${base_tmp}/hard.out" "${base_tmp}/hard.err"; then
  diag "make update" "hard-fail-publishable-unavailable" "non-zero" "exit 0" "Publishable unavailable packages must hard-fail."
  exit 1
fi
assert_json_failure "${base_tmp}/hard.out"
status="$(cd "${hard_project}" && git status --porcelain --untracked-files=all)"
[[ -z "${status}" ]] || { diag "git status" "hard-fail" "clean" "${status}" "Hard-fail update must not leave partial generated changes."; exit 1; }

generate_fail_project="${base_tmp}/generate-fail"
prepare_project "${generate_fail_project}"
rm -f "${generate_fail_project}/cloudnative-pg-timescaledb/scripts/generate.sh"
(cd "${generate_fail_project}" && git add . && git commit -qm generate-fail-input)
if run_update "${generate_fail_project}" "${upstream}" "${base_tmp}/generate-fail.out" "${base_tmp}/generate-fail.err"; then
  diag "make update" "generate-failure-rollback" "non-zero" "exit 0" "Generator failure after metadata resolution must hard-fail."
  exit 1
fi
assert_json_failure "${base_tmp}/generate-fail.out"
status="$(cd "${generate_fail_project}" && git status --porcelain --untracked-files=all)"
[[ -z "${status}" ]] || { diag "git status" "generate-failure-rollback" "clean" "${status}" "Rollback metadata and generated paths when post-write update steps fail."; exit 1; }

unsupported_project="${base_tmp}/unsupported"
prepare_project "${unsupported_project}"
append_unsupported_row "${unsupported_project}/cloudnative-pg-timescaledb/versions.yaml"
(cd "${unsupported_project}" && git add . && git commit -qm unsupported-input)
if run_update "${unsupported_project}" "${upstream}" "${base_tmp}/unsupported.out" "${base_tmp}/unsupported.err"; then
  diag "make update" "reject-unsupported-debian-or-pg" "non-zero" "exit 0" "Unsupported matrix rows must fail."
  exit 1
fi
assert_json_failure "${base_tmp}/unsupported.out"

latest_project="${base_tmp}/latest"
prepare_project "${latest_project}"
set_entry_field "${latest_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "trixie" "latest_eligible" 'false'
set_entry_field "${latest_project}/cloudnative-pg-timescaledb/versions.yaml" "17" "trixie" "latest_eligible" 'true'
(cd "${latest_project}" && git add . && git commit -qm latest-input)
if run_update "${latest_project}" "${upstream}" "${base_tmp}/latest.out" "${base_tmp}/latest.err"; then
  diag "make update" "reject-latest-moved-from-pg18-trixie" "non-zero" "exit 0" "latest_eligible movement must fail."
  exit 1
fi
assert_json_failure "${base_tmp}/latest.out"

barman_project="${base_tmp}/barman"
prepare_project "${barman_project}"
set_entry_field "${barman_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "trixie" "skip_reason" '"Install barman-cloud in image path"'
(cd "${barman_project}" && git add . && git commit -qm barman-input)
if run_update "${barman_project}" "${upstream}" "${base_tmp}/barman.out" "${base_tmp}/barman.err"; then
  diag "make update" "reject-barman-tooling-in-image-path" "non-zero" "exit 0" "Legacy Barman tooling must fail."
  exit 1
fi
assert_json_failure "${base_tmp}/barman.out"

rm -rf "${base_tmp}"
printf 'PASS story-2.3 deterministic update fixtures\n'
