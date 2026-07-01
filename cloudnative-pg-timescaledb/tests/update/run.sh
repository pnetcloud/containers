#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/update/fixtures"
CNPG_FIXTURES="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/cnpg-resolver/fixtures"
PKG_FIXTURES="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/packagecloud/fixtures"
BARMAN_PLUGIN_FIXTURE="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/barman-plugin/fixtures/current-reference.json"
EXECUTED_FIXTURES=()

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

mark_fixture_executed() {
  EXECUTED_FIXTURES+=("$1")
}

prepare_project() {
  local target="$1"
  mkdir -p "${target}"
  cp "${ROOT_DIR}/Makefile" "${target}/Makefile"
  mkdir -p "${target}/cloudnative-pg-timescaledb" "${target}/docs"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/config" "${target}/cloudnative-pg-timescaledb/config"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts" "${target}/cloudnative-pg-timescaledb/scripts"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/templates" "${target}/cloudnative-pg-timescaledb/templates"
  mkdir -p "${target}/cloudnative-pg-timescaledb/tests/release-rehearsal"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures" "${target}/cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/generated" "${target}/cloudnative-pg-timescaledb/generated"
  cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/catalog" "${target}/cloudnative-pg-timescaledb/catalog"
  mkdir -p "${target}/cloudnative-pg-timescaledb/docs/generated"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/compatibility.md" "${target}/cloudnative-pg-timescaledb/docs/generated/compatibility.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/compatibility-table.md" "${target}/cloudnative-pg-timescaledb/docs/generated/compatibility-table.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md" "${target}/cloudnative-pg-timescaledb/docs/generated/matrix-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md" "${target}/cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md" "${target}/cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md" "${target}/cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md"
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
  cp "${BARMAN_PLUGIN_FIXTURE}" "${target}/barman-plugin.json"
}

write_manifest_fixture() {
  local metadata="$1"
  local target="$2"
  python3 - "${ROOT_DIR}" "${metadata}" "${target}" <<'PY'
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(sys.argv[1])
metadata = Path(sys.argv[2])
target = Path(sys.argv[3])
sys.path.insert(0, str(root / "cloudnative-pg-timescaledb" / "scripts" / "lib"))
import generator_contract  # noqa: E402

data = generator_contract.parse_metadata(metadata, "update fixture manifest")
manifests = []
seen = set()
for entry in data.get("entries", []):
    tag = str(entry.get("cnpg_tag", "")).strip()
    digest = str(entry.get("cnpg_digest", "")).strip()
    if not tag or not digest:
        continue
    key = (tag, digest)
    if key in seen:
        continue
    seen.add(key)
    manifests.append({"tag": tag, "digest": digest, "platforms": entry.get("platforms", [])})
target.write_text(json.dumps({"manifests": manifests}, indent=2, sort_keys=True) + "\n")
PY
}

run_update() {
  local project="$1"
  local upstream="$2"
  local stdout_file="$3"
  local stderr_file="$4"
  set +e
  (cd "${project}" && make --no-print-directory update UPDATE_ARGS="--fixtures ${upstream} --json") >"${stdout_file}" 2>"${stderr_file}"
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
required = {"changed", "updated_entries", "old", "new", "generated", "summary_path", "exit_code", "failure_reason"}
if set(payload) != required:
    raise SystemExit(f"wrong update JSON keys: {sorted(payload)}")
if payload["exit_code"] != 0 or payload["failure_reason"] != "":
    raise SystemExit(f"expected success JSON: {payload}")
expected = sys.argv[2] == "true"
if payload["changed"] is not expected:
    raise SystemExit(f"expected changed={expected}: {payload}")
summary_path = Path(payload["summary_path"])
if not summary_path.is_file():
    raise SystemExit(f"summary_path does not exist: {summary_path}")
summary_payload = json.loads(summary_path.read_text())
if set(summary_payload) != required:
    raise SystemExit(f"wrong summary JSON keys: {sorted(summary_payload)}")
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
summary_path = Path(payload["summary_path"])
if not summary_path.is_file():
    raise SystemExit(f"failure summary_path does not exist: {summary_path}")
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

normalize_fixture_diff() {
  sed -E \
    -e 's/index [0-9a-f]+\.\.[0-9a-f]+/index <old>..<new>/g' \
    -e 's/sha256:[0-9a-f]{64}/sha256:<digest>/g' \
    -e 's/ts[0-9]+\.[0-9]+\.[0-9]+-/ts<timescaledb>-/g' \
    -e 's/[0-9]+\.[0-9]+\.[0-9]+~debian/<timescaledb>~debian/g' \
    -e 's/org\.pnet\.timescaledb\.version="[0-9]+\.[0-9]+\.[0-9]+"/org.pnet.timescaledb.version="<timescaledb>"/g' \
    -e 's/"timescaledb_version": "[0-9]+\.[0-9]+\.[0-9]+"/"timescaledb_version": "<timescaledb>"/g' \
    -e 's/timescaledb_version: "[0-9]+\.[0-9]+\.[0-9]+"/timescaledb_version: "<timescaledb>"/g' \
    "$1"
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
    if [[ -f "${FIXTURE_DIR}/${fixture}/expected-diff.patch" ]] && ! grep -q '^diff --git ' "${FIXTURE_DIR}/${fixture}/expected-diff.patch"; then
      diag "test fixture diff marker" "${FIXTURE_DIR}/${fixture}/expected-diff.patch" "expected diff marker begins with diff --git" "$(cat "${FIXTURE_DIR}/${fixture}/expected-diff.patch")" "Replace prose placeholders with a patch-shaped expected diff marker."
      exit 1
    fi
    if [[ -f "${FIXTURE_DIR}/${fixture}/expected-no-diff" ]] && [[ "$(cat "${FIXTURE_DIR}/${fixture}/expected-no-diff")" != "NO_DIFF" ]]; then
      diag "test fixture no-diff marker" "${FIXTURE_DIR}/${fixture}/expected-no-diff" "NO_DIFF" "$(cat "${FIXTURE_DIR}/${fixture}/expected-no-diff")" "Use a stable sentinel for no-diff fixtures."
      exit 1
    fi
  done
}

assert_all_named_fixtures_executed() {
  local fixture
  for fixture in no-op changed-cnpg changed-packages preserve-policy-fields update-resolver-skip-reason preserve-manual-skip-reason hard-fail-publishable-unavailable reject-unsupported-debian-or-pg reject-latest-moved-from-pg18-trixie reject-barman-tooling-in-image-path; do
    if [[ " ${EXECUTED_FIXTURES[*]} " != *" ${fixture} "* ]]; then
      diag "fixture execution coverage" "${FIXTURE_DIR}/${fixture}" "named fixture scenario executed by run.sh" "not executed" "Keep named Story 2.3 fixture directories mapped to exercised update scenarios."
      exit 1
    fi
  done
}

run_committed_fixture() {
  local fixture="$1"
  local project="${base_tmp}/committed-${fixture}"
  local stdout_file="${base_tmp}/committed-${fixture}.out"
  local stderr_file="${base_tmp}/committed-${fixture}.err"
  local actual_diff="${base_tmp}/committed-${fixture}.diff"
  local fixture_root="${FIXTURE_DIR}/${fixture}"
  prepare_project "${project}"
  if [[ "${fixture}" == "no-op" && -d "${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata" ]]; then
    cp -R "${ROOT_DIR}/cloudnative-pg-timescaledb/release-metadata" "${project}/cloudnative-pg-timescaledb/release-metadata"
  fi
  cp "${fixture_root}/input/versions.yaml" "${project}/cloudnative-pg-timescaledb/versions.yaml"
  if [[ "${fixture}" == "no-op" ]]; then
    local baseline_manifest="${project}/cloudnative-pg-timescaledb/update-fixture-cnpg-manifest.json"
    write_manifest_fixture "${project}/cloudnative-pg-timescaledb/versions.yaml" "${baseline_manifest}"
    (cd "${project}" && CNPG_MANIFEST_FIXTURE="${baseline_manifest}" make --no-print-directory generate >/tmp/story-2-3-${fixture}-baseline-generate.out)
    rm -f "${baseline_manifest}"
  fi
  (cd "${project}" && git add . && if ! git diff --cached --quiet; then git commit -qm "fixture-${fixture}-input"; fi)
  if [[ -f "${fixture_root}/expected-diff.patch" ]]; then
    if ! run_update "${project}" "${fixture_root}/upstream" "${stdout_file}" "${stderr_file}"; then
      diag "make update" "${fixture}" "exit 0" "$(cat "${stderr_file}")" "Committed changed fixtures must update deterministically."
      exit 1
    fi
    assert_json_success "${stdout_file}" true
    assert_allowlisted_status "${project}"
    (cd "${project}" && git diff --binary | sed -E 's/[[:space:]]+$//') >"${actual_diff}"
    local normalized_expected="${base_tmp}/committed-${fixture}.expected.normalized.diff"
    local normalized_actual="${base_tmp}/committed-${fixture}.actual.normalized.diff"
    normalize_fixture_diff "${fixture_root}/expected-diff.patch" >"${normalized_expected}"
    normalize_fixture_diff "${actual_diff}" >"${normalized_actual}"
    local diff_file="/tmp/story-2-3-${fixture}.diff"
    if ! diff -u "${normalized_expected}" "${normalized_actual}" >"${diff_file}"; then
      diag "fixture expected diff" "${fixture}" "actual git diff matches expected-diff.patch" "$(cat "${diff_file}")" "Regenerate the committed expected diff from the fixture input/upstream."
      exit 1
    fi
  else
    case "${fixture}" in
      no-op)
        if ! run_update "${project}" "${fixture_root}/upstream" "${stdout_file}" "${stderr_file}"; then
          diag "make update" "${fixture}" "exit 0" "$(cat "${stderr_file}")" "Committed no-op fixture must succeed."
          exit 1
        fi
        assert_json_success "${stdout_file}" false
        ;;
      *)
        if run_update "${project}" "${fixture_root}/upstream" "${stdout_file}" "${stderr_file}"; then
          diag "make update" "${fixture}" "non-zero" "exit 0" "Committed hard-fail fixture must fail deterministically."
          exit 1
        fi
        assert_json_failure "${stdout_file}"
        if [[ "${fixture}" == "reject-barman-tooling-in-image-path" ]] && ! grep -Eq 'no legacy Barman tooling|CloudNativePG Barman Cloud Plugin|barman-cloud' "${stdout_file}" "${stderr_file}"; then
          diag "make update" "${fixture}" "Barman boundary failure reason" "$(cat "${stderr_file}") $(cat "${stdout_file}")" "Ensure the fixture exercises the legacy Barman tooling guard, not an earlier metadata invariant."
          exit 1
        fi
        ;;
    esac
    status="$(cd "${project}" && git status --porcelain --untracked-files=all)"
    [[ -z "${status}" ]] || { diag "git status" "${fixture}" "clean" "${status}" "Committed no-diff fixtures must not leave partial changes."; exit 1; }
  fi
  mark_fixture_executed "${fixture}"
}

assert_fixture_dirs

base_tmp="$(mktemp -d)"
upstream="${base_tmp}/upstream"
prepare_upstream "${upstream}"

for committed_fixture in no-op changed-cnpg changed-packages preserve-policy-fields update-resolver-skip-reason preserve-manual-skip-reason hard-fail-publishable-unavailable reject-unsupported-debian-or-pg reject-latest-moved-from-pg18-trixie reject-barman-tooling-in-image-path; do
  run_committed_fixture "${committed_fixture}"
done

changed_project="${base_tmp}/changed-cnpg"
prepare_project "${changed_project}"
if ! run_update "${changed_project}" "${upstream}" "${base_tmp}/changed.out" "${base_tmp}/changed.err"; then
  diag "make update" "changed-cnpg" "exit 0" "$(cat "${base_tmp}/changed.err")" "Changed resolver fixtures should update deterministically."
  exit 1
fi
assert_json_success "${base_tmp}/changed.out" true
assert_allowlisted_status "${changed_project}"
grep -Fq '18.4-standard-trixie' "${changed_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep 18.4" "changed-cnpg" "CNPG tag updated" "missing" "Update resolver-owned CNPG fields."; exit 1; }
mark_fixture_executed changed-cnpg
mark_fixture_executed changed-packages

newer_cnpg_upstream="${base_tmp}/newer-cnpg-upstream"
mkdir -p "${newer_cnpg_upstream}/cnpg"
cp "${CNPG_FIXTURES}/standard-trixie-valid.json" "${newer_cnpg_upstream}/cnpg/standard-trixie-valid.json"
cp "${CNPG_FIXTURES}/standard-bookworm-valid.json" "${newer_cnpg_upstream}/cnpg/standard-bookworm-valid.json"
ln -s "${PKG_FIXTURES}" "${newer_cnpg_upstream}/packages"
cp "${BARMAN_PLUGIN_FIXTURE}" "${newer_cnpg_upstream}/barman-plugin.json"
python3 - "${newer_cnpg_upstream}/cnpg/standard-trixie-valid.json" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["manifests"].append({
    "tag": "18.5-standard-trixie",
    "digest": "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    "platforms": ["linux/amd64", "linux/arm64"],
})
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
newer_cnpg_project="${base_tmp}/newer-cnpg-package-constrained"
prepare_project "${newer_cnpg_project}"
if ! run_update "${newer_cnpg_project}" "${newer_cnpg_upstream}" "${base_tmp}/newer-cnpg.out" "${base_tmp}/newer-cnpg.err"; then
  diag "make update" "newer-cnpg-package-constrained" "exit 0" "$(cat "${base_tmp}/newer-cnpg.err")" "CNPG update should use the PostgreSQL minor required by TimescaleDB packages."
  exit 1
fi
grep -Fq 'cnpg_tag: "18.4-standard-trixie"' "${newer_cnpg_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep constrained cnpg tag" "newer-cnpg-package-constrained" "18.4-standard-trixie" "missing" "Keep CNPG tag constrained to the TimescaleDB package PostgreSQL suffix."; exit 1; }
grep -Fq 'cnpg_digest: "sha256:184219ecec559d15fa03932b0d3005e0372f7027746bb682aca478bc4918f776"' "${newer_cnpg_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep constrained cnpg digest" "newer-cnpg-package-constrained" "18.4 digest" "missing" "Use the digest for the final CNPG tag, not a newer minor tag."; exit 1; }
if grep -Fq 'sha256:5555555555555555555555555555555555555555555555555555555555555555' "${newer_cnpg_project}/cloudnative-pg-timescaledb/versions.yaml"; then
  diag "grep newer cnpg digest" "newer-cnpg-package-constrained" "newer minor digest absent" "present" "Do not pair a package-constrained CNPG tag with a digest from a newer PostgreSQL minor."
  exit 1
fi

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
mark_fixture_executed no-op

digest_upstream="${base_tmp}/digest-upstream"
mkdir -p "${digest_upstream}/cnpg"
cp "${CNPG_FIXTURES}/standard-trixie-valid.json" "${digest_upstream}/cnpg/standard-trixie-valid.json"
cp "${CNPG_FIXTURES}/standard-bookworm-valid.json" "${digest_upstream}/cnpg/standard-bookworm-valid.json"
ln -s "${PKG_FIXTURES}" "${digest_upstream}/packages"
cp "${BARMAN_PLUGIN_FIXTURE}" "${digest_upstream}/barman-plugin.json"
python3 - "${digest_upstream}/cnpg/standard-trixie-valid.json" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text().replace(
    "sha256:184219ecec559d15fa03932b0d3005e0372f7027746bb682aca478bc4918f776",
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
(cd "${policy_project}" && git add . && git commit -qm policy-input)
run_update "${policy_project}" "${upstream}" "${base_tmp}/policy.out" "${base_tmp}/policy.err" || { diag "make update" "preserve-policy-fields" "exit 0" "$(cat "${base_tmp}/policy.err")" "Manual policy fields should be preserved."; exit 1; }
grep -Fq 'skip_reason: "Manual maintainer hold"' "${policy_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep manual skip" "preserve-policy-fields" "manual skip preserved" "changed" "Do not overwrite maintainer-authored skip reasons."; exit 1; }
mark_fixture_executed preserve-policy-fields
mark_fixture_executed preserve-manual-skip-reason

resolver_skip_project="${base_tmp}/resolver-skip"
prepare_project "${resolver_skip_project}"
set_entry_field "${resolver_skip_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "bookworm" "skip_reason" '"resolver:old-reason: stale"'
(cd "${resolver_skip_project}" && git add . && git commit -qm resolver-skip-input)
bad_upstream="${base_tmp}/bad-upstream"
mkdir -p "${bad_upstream}"
ln -s "${CNPG_FIXTURES}" "${bad_upstream}/cnpg"
mkdir -p "${bad_upstream}/packages"
cp "${BARMAN_PLUGIN_FIXTURE}" "${bad_upstream}/barman-plugin.json"
ln -s "${PKG_FIXTURES}/trixie-amd64-available.json" "${bad_upstream}/packages/trixie-amd64-available.json"
ln -s "${PKG_FIXTURES}/trixie-arm64-available.json" "${bad_upstream}/packages/trixie-arm64-available.json"
ln -s "${PKG_FIXTURES}/bookworm-amd64-available.json" "${bad_upstream}/packages/bookworm-amd64-available.json"
cp "${PKG_FIXTURES}/bookworm-arm64-available.json" "${bad_upstream}/packages/bookworm-arm64-available.json"
python3 - "${bad_upstream}/packages/bookworm-arm64-available.json" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["packages"] = [
    package for package in payload["packages"]
    if not (
        package["pg_major"] == "18"
        and package["package_type"] == "toolkit"
        and package["architecture"] == "arm64"
    )
]
path.write_text(json.dumps(payload, separators=(",", ":")))
PY
run_update "${resolver_skip_project}" "${bad_upstream}" "${base_tmp}/resolver-skip.out" "${base_tmp}/resolver-skip.err" || { diag "make update" "update-resolver-skip-reason" "exit 0" "$(cat "${base_tmp}/resolver-skip.err")" "Resolver-prefixed skip reasons should be updateable."; exit 1; }
grep -Fq 'skip_reason: "resolver:package-unavailable: timescaledb-toolkit-postgresql-18 PostgreSQL 18 bookworm linux/arm64 missing packages while CNPG exists"' "${resolver_skip_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep resolver skip" "update-resolver-skip-reason" "package/platform skip reason updated" "missing" "Update resolver-prefixed skip reasons to package-specific evidence."; exit 1; }
mark_fixture_executed update-resolver-skip-reason

cnpg_skip_project="${base_tmp}/cnpg-resolver-skip"
prepare_project "${cnpg_skip_project}"
set_entry_field "${cnpg_skip_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "bookworm" "skip_reason" '"resolver:old-cnpg-reason: stale"'
(cd "${cnpg_skip_project}" && git add . && git commit -qm cnpg-skip-input)
missing_cnpg_upstream="${base_tmp}/missing-cnpg-upstream"
mkdir -p "${missing_cnpg_upstream}/cnpg"
cp "${CNPG_FIXTURES}/standard-trixie-valid.json" "${missing_cnpg_upstream}/cnpg/standard-trixie-valid.json"
cp "${CNPG_FIXTURES}/standard-bookworm-valid.json" "${missing_cnpg_upstream}/cnpg/standard-bookworm-valid.json"
python3 - "${missing_cnpg_upstream}/cnpg/standard-bookworm-valid.json" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["manifests"] = [
    manifest for manifest in payload["manifests"]
    if manifest.get("tag") != "18.4-standard-bookworm"
]
path.write_text(json.dumps(payload, separators=(",", ":")))
PY
ln -s "${PKG_FIXTURES}" "${missing_cnpg_upstream}/packages"
cp "${BARMAN_PLUGIN_FIXTURE}" "${missing_cnpg_upstream}/barman-plugin.json"
run_update "${cnpg_skip_project}" "${missing_cnpg_upstream}" "${base_tmp}/cnpg-skip.out" "${base_tmp}/cnpg-skip.err" || { diag "make update" "update-cnpg-resolver-skip-reason" "exit 0" "$(cat "${base_tmp}/cnpg-skip.err")" "Resolver-prefixed CNPG skip reasons should be updateable."; exit 1; }
grep -Fq 'skip_reason: "resolver:cnpg-unavailable: ghcr.io/cloudnative-pg/postgresql:18.4-standard-bookworm PostgreSQL 18 bookworm missing tag"' "${cnpg_skip_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep cnpg resolver skip" "update-cnpg-resolver-skip-reason" "CNPG missing-tag skip reason updated" "missing" "Update resolver-prefixed CNPG skip reasons to upstream evidence."; exit 1; }
grep -Fq 'cnpg_tag: "18.4-standard-bookworm"' "${cnpg_skip_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep cnpg unresolved tag" "update-cnpg-resolver-skip-reason" "unresolved CNPG tag remains aligned with package-constrained missing-tag evidence" "missing" "Derive CNPG tag from package versions before CNPG resolution so missing-tag diagnostics name the final required base."; exit 1; }

manual_cnpg_project="${base_tmp}/manual-cnpg-skip"
prepare_project "${manual_cnpg_project}"
set_entry_field "${manual_cnpg_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "bookworm" "skip_reason" '"Manual CNPG hold"'
(cd "${manual_cnpg_project}" && git add . && git commit -qm manual-cnpg-input)
run_update "${manual_cnpg_project}" "${missing_cnpg_upstream}" "${base_tmp}/manual-cnpg.out" "${base_tmp}/manual-cnpg.err" || { diag "make update" "preserve-manual-cnpg-skip-reason" "exit 0" "$(cat "${base_tmp}/manual-cnpg.err")" "Manual CNPG skip reasons should be preserved."; exit 1; }
grep -Fq 'skip_reason: "Manual CNPG hold"' "${manual_cnpg_project}/cloudnative-pg-timescaledb/versions.yaml" || { diag "grep manual cnpg skip" "preserve-manual-cnpg-skip-reason" "manual CNPG skip preserved" "changed" "Do not overwrite maintainer-authored CNPG skip reasons."; exit 1; }

dirty_project="${base_tmp}/dirty-generated"
prepare_project "${dirty_project}"
printf 'local scratch\n' >"${dirty_project}/cloudnative-pg-timescaledb/docs/generated/local-scratch.md"
if run_update "${dirty_project}" "${upstream}" "${base_tmp}/dirty.out" "${base_tmp}/dirty.err"; then
  diag "make update" "dirty-generated-guard" "non-zero" "exit 0" "Dirty generated paths must fail before update."
  exit 1
fi
assert_json_failure "${base_tmp}/dirty.out"

unsupported_upstream_project="${base_tmp}/unsupported-upstream"
prepare_project "${unsupported_upstream_project}"
unsupported_cnpg_upstream="${base_tmp}/unsupported-cnpg-upstream"
mkdir -p "${unsupported_cnpg_upstream}/cnpg"
cp "${CNPG_FIXTURES}/standard-trixie-valid.json" "${unsupported_cnpg_upstream}/cnpg/standard-trixie-valid.json"
cp "${CNPG_FIXTURES}/standard-bookworm-valid.json" "${unsupported_cnpg_upstream}/cnpg/standard-bookworm-valid.json"
python3 - "${unsupported_cnpg_upstream}/cnpg/standard-trixie-valid.json" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
payload = json.loads(path.read_text())
payload["manifests"].append({
    "tag": "20-standard-trixie",
    "digest": "sha256:2020202020202020202020202020202020202020202020202020202020202020",
    "platforms": ["linux/amd64", "linux/arm64"],
})
path.write_text(json.dumps(payload, separators=(",", ":")))
PY
ln -s "${PKG_FIXTURES}" "${unsupported_cnpg_upstream}/packages"
cp "${BARMAN_PLUGIN_FIXTURE}" "${unsupported_cnpg_upstream}/barman-plugin.json"
if run_update "${unsupported_upstream_project}" "${unsupported_cnpg_upstream}" "${base_tmp}/unsupported-upstream.out" "${base_tmp}/unsupported-upstream.err"; then
  diag "make update" "reject-unsupported-upstream-cnpg-tuple" "non-zero" "exit 0" "Unsupported upstream CNPG tuples must hard-fail."
  exit 1
fi
assert_json_failure "${base_tmp}/unsupported-upstream.out"
grep -Eq -q 'pg_major=20 debian_variant=trixie|20-standard-trixie' "${base_tmp}/unsupported-upstream.err" "${base_tmp}/unsupported-upstream.out" || { diag "grep unsupported upstream tuple" "reject-unsupported-upstream-cnpg-tuple" "diagnostic names rejected tuple" "$(cat "${base_tmp}/unsupported-upstream.err") $(cat "${base_tmp}/unsupported-upstream.out")" "Name unsupported upstream CNPG tuples in failure diagnostics."; exit 1; }
status="$(cd "${unsupported_upstream_project}" && git status --porcelain --untracked-files=all)"
[[ -z "${status}" ]] || { diag "git status" "reject-unsupported-upstream-cnpg-tuple" "clean" "${status}" "Unsupported upstream tuple failures must not leave partial changes."; exit 1; }
mark_fixture_executed reject-unsupported-debian-or-pg

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
mark_fixture_executed hard-fail-publishable-unavailable

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
mark_fixture_executed reject-latest-moved-from-pg18-trixie

barman_project="${base_tmp}/barman"
prepare_project "${barman_project}"
set_entry_field "${barman_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "trixie" "publish" 'false'
set_entry_field "${barman_project}/cloudnative-pg-timescaledb/versions.yaml" "18" "trixie" "skip_reason" '"Install barman-cloud in image path"'
(cd "${barman_project}" && git add . && git commit -qm barman-input)
if run_update "${barman_project}" "${upstream}" "${base_tmp}/barman.out" "${base_tmp}/barman.err"; then
  diag "make update" "reject-barman-tooling-in-image-path" "non-zero" "exit 0" "Legacy Barman tooling must fail."
  exit 1
fi
assert_json_failure "${base_tmp}/barman.out"
grep -Eq 'no legacy Barman tooling|CloudNativePG Barman Cloud Plugin|barman-cloud' "${base_tmp}/barman.out" "${base_tmp}/barman.err" || { diag "grep barman failure" "reject-barman-tooling-in-image-path" "Barman boundary failure reason" "$(cat "${base_tmp}/barman.err") $(cat "${base_tmp}/barman.out")" "Exercise the legacy Barman tooling guard."; exit 1; }
mark_fixture_executed reject-barman-tooling-in-image-path

assert_all_named_fixtures_executed

rm -rf "${base_tmp}"
printf 'PASS story-2.3 deterministic update fixtures\n'
