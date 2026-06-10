#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VALIDATOR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate-metadata.sh"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/metadata/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

expect_fail() {
  local description="$1"
  local pattern="$2"
  local file="$3"
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${VALIDATOR}" "${file}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "${VALIDATOR} ${file}" "${description}" "fixture fails" "passed" "Make invalid metadata fail validation."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${VALIDATOR} ${file}" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Make the fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

expect_arg_fail() {
  local description="$1"
  local pattern="$2"
  shift 2
  local tmp status
  tmp="$(mktemp)"
  set +e
  "${VALIDATOR}" "$@" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" != "64" ]]; then
    diag "${VALIDATOR} $*" "${description}" "exit 64" "exit ${status}; $(tr '\n' ' ' <"${tmp}")" "Use controlled argument diagnostics for invalid validate-metadata usage."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "${VALIDATOR} $*" "${description}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Print deterministic argument failure diagnostics."
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
}

policy_fixture() {
  local output="$1"
  local extension="$2"
  local creatable="$3"
  local reason="$4"
  local mode="$5"
  local target="$6"
  python3 - "${FIXTURE_DIR}/valid.yaml" "${output}" "${extension}" "${creatable}" "${reason}" "${mode}" "${target}" <<'PY'
from pathlib import Path
import sys

source, output, extension, creatable, reason, mode, target = sys.argv[1:]
lines = Path(source).read_text().splitlines()
insert = [f"    extensions.{extension}.creatable: {creatable}"]
if reason != "__omit__":
    insert.append(f"    extensions.{extension}.non_creatable_reason: {reason}")
if mode != "__omit__":
    insert.append(f"    extensions.{extension}.validation_mode: {mode}")
if target != "__omit__":
    insert.append(f"    extensions.{extension}.validation_target: {target}")

result = []
in_latest_row = False
inserted = False
for line in lines:
    result.append(line)
    if line == '    latest_eligible: true':
        in_latest_row = True
        continue
    if in_latest_row and line.startswith('    skip_reason:') and not inserted:
        result.extend(insert)
        inserted = True
        in_latest_row = False
if not inserted:
    raise SystemExit('failed to inject extension policy fixture')
Path(output).write_text('\n'.join(result) + '\n')
PY
}

replace_line_fixture() {
  local output="$1"
  local pattern="$2"
  local replacement="$3"
  python3 - "${FIXTURE_DIR}/valid.yaml" "${output}" "${pattern}" "${replacement}" <<'PY'
from pathlib import Path
import sys

source, output, pattern, replacement = sys.argv[1:]
lines = Path(source).read_text().splitlines()
replaced = False
result = []
for line in lines:
    if not replaced and pattern in line:
        result.append(replacement)
        replaced = True
    else:
        result.append(line)
if not replaced:
    raise SystemExit(f"failed to replace fixture line containing {pattern!r}")
Path(output).write_text("\n".join(result) + "\n")
PY
}

assert_make_validate_metadata_gate() {
  local sandbox output
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/cloudnative-pg-timescaledb/scripts" "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth" "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2"
  cp "${ROOT_DIR}/Makefile" "${sandbox}/Makefile"
  cp "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/validate.sh" "${sandbox}/cloudnative-pg-timescaledb/scripts/validate.sh"
  chmod +x "${sandbox}/cloudnative-pg-timescaledb/scripts/validate.sh"
  for path in \
    cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh \
    cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh \
    cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh \
    cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh; do
    mkdir -p "${sandbox}/$(dirname "${path}")"
    cat >"${sandbox}/${path}" <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'STUB %s\n' '${path}'
SH
    chmod +x "${sandbox}/${path}"
  done
  cat >"${sandbox}/cloudnative-pg-timescaledb/scripts/validate-metadata.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'STUB validate-metadata failed\n'
exit 42
SH
  chmod +x "${sandbox}/cloudnative-pg-timescaledb/scripts/validate-metadata.sh"
  for script in validate-tags validate-generated validate-docs validate-barman-boundary validate-workflows; do
    cat >"${sandbox}/cloudnative-pg-timescaledb/scripts/${script}.sh" <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'STUB %s\n' '${script}'
SH
    chmod +x "${sandbox}/cloudnative-pg-timescaledb/scripts/${script}.sh"
  done
  output="$(mktemp)"
  if make -C "${sandbox}" validate >"${output}" 2>&1; then
    diag "make validate sandbox" "Makefile validate target" "metadata validator failure stops make validate" "$(cat "${output}")" "Do not bypass validate-metadata.sh in make validate."
    rm -rf "${sandbox}" "${output}"
    exit 1
  fi
  if ! grep -Fq 'STUB validate-metadata failed' "${output}" || grep -Fq 'STUB validate-tags' "${output}"; then
    diag "make validate sandbox" "Makefile validate target" "validate-metadata.sh runs before later validators and fails fast" "$(cat "${output}")" "Call validate-metadata.sh directly and before downstream validators."
    rm -rf "${sandbox}" "${output}"
    exit 1
  fi
  rm -rf "${sandbox}" "${output}"
}

"${VALIDATOR}" "${FIXTURE_DIR}/valid.yaml" >/tmp/story-1-3-valid.out
"${VALIDATOR}" "${FIXTURE_DIR}/valid-extension-sources.yaml" >/tmp/story-3-2-valid-extension-sources.out

valid_policy_fixture="$(mktemp)"
valid_true_unsupported_mode_fixture="$(mktemp)"
missing_reason_fixture="$(mktemp)"
missing_target_fixture="$(mktemp)"
unsupported_mode_fixture="$(mktemp)"
unknown_extension_fixture="$(mktemp)"
invalid_registry_fixture="$(mktemp)"
invalid_repository_fixture="$(mktemp)"
invalid_registry_whitespace_fixture="$(mktemp)"
invalid_registry_path_fixture="$(mktemp)"
invalid_repository_whitespace_fixture="$(mktemp)"
invalid_repository_uppercase_fixture="$(mktemp)"
trap 'rm -f "${valid_policy_fixture}" "${valid_true_unsupported_mode_fixture}" "${missing_reason_fixture}" "${missing_target_fixture}" "${unsupported_mode_fixture}" "${unknown_extension_fixture}" "${invalid_registry_fixture}" "${invalid_repository_fixture}" "${invalid_registry_whitespace_fixture}" "${invalid_registry_path_fixture}" "${invalid_repository_whitespace_fixture}" "${invalid_repository_uppercase_fixture}"' EXIT
policy_fixture "${valid_policy_fixture}" pgaudit false "PGAudit is validated by control file" control-file pgaudit.control
policy_fixture "${valid_true_unsupported_mode_fixture}" pgaudit true __omit__ sql-only __omit__
policy_fixture "${missing_reason_fixture}" pgaudit false __omit__ control-file pgaudit.control
policy_fixture "${missing_target_fixture}" pgaudit false "PGAudit is validated by control file" control-file __omit__
policy_fixture "${unsupported_mode_fixture}" pgaudit false "PGAudit is validated by control file" sql-only pgaudit.control
policy_fixture "${unknown_extension_fixture}" postgis false "PostGIS is outside this image contract" control-file postgis.control
replace_line_fixture "${invalid_registry_fixture}" "  registry:" "  registry: []"
replace_line_fixture "${invalid_repository_fixture}" "  repository:" "  repository: \"\""
replace_line_fixture "${invalid_registry_whitespace_fixture}" "  registry:" "  registry: \" ghcr.io\""
replace_line_fixture "${invalid_registry_path_fixture}" "  registry:" "  registry: \"ghcr.io/pnetcloud\""
replace_line_fixture "${invalid_repository_whitespace_fixture}" "  repository:" "  repository: \"pnetcloud/cloudnative pg-timescaledb\""
replace_line_fixture "${invalid_repository_uppercase_fixture}" "  repository:" "  repository: \"pnetcloud/CloudNative-PG-TimescaleDB\""
"${VALIDATOR}" "${valid_policy_fixture}" >/tmp/story-3-5-valid-extension-policy.out

expect_fail "missing top-level key" "top-level keys exactly" "${FIXTURE_DIR}/missing-top-level-key.yaml"
expect_fail "wrong current major" "image.current_major" "${FIXTURE_DIR}/wrong-current-major.yaml"
expect_fail "wrong primary Debian" "image.primary_debian_variant" "${FIXTURE_DIR}/wrong-primary-debian-variant.yaml"
expect_fail "invalid image registry" "image.registry is non-empty string" "${invalid_registry_fixture}"
expect_fail "invalid image repository" "image.repository is non-empty string" "${invalid_repository_fixture}"
expect_fail "image registry whitespace" "image.registry has no whitespace" "${invalid_registry_whitespace_fixture}"
expect_fail "image registry path component" "image.registry is OCI registry" "${invalid_registry_path_fixture}"
expect_fail "image repository whitespace" "image.repository has no whitespace" "${invalid_repository_whitespace_fixture}"
expect_fail "image repository uppercase" "image.repository is lowercase" "${invalid_repository_uppercase_fixture}"
expect_fail "wrong allowed PostgreSQL majors" "allowed.postgres_majors" "${FIXTURE_DIR}/wrong-allowed-postgres-majors.yaml"
expect_fail "wrong allowed Debian variants" "allowed.debian_variants" "${FIXTURE_DIR}/wrong-allowed-debian-variants.yaml"
expect_fail "wrong allowed platforms" "allowed.platforms" "${FIXTURE_DIR}/wrong-allowed-platforms.yaml"
expect_fail "invalid field types" "is boolean|is non-empty list|is string" "${FIXTURE_DIR}/invalid-field-types.yaml"
expect_fail "pg version mismatch" "pg_version matches pg_major" "${FIXTURE_DIR}/invalid-pg-version-mismatch.yaml"
expect_fail "cnpg tag variant mismatch" "cnpg_tag matches pg_version and debian_variant" "${FIXTURE_DIR}/invalid-cnpg-tag-variant-mismatch.yaml"
expect_fail "duplicate row" "unique pg_major/debian_variant" "${FIXTURE_DIR}/duplicate-pg-debian-row.yaml"
expect_fail "missing matrix row" "matrix rows exactly" "${FIXTURE_DIR}/missing-required-pg-debian-row.yaml"
expect_fail "missing required field" "keys exactly" "${FIXTURE_DIR}/missing-required-field.yaml"
expect_fail "Alpine unsupported" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/invalid-debian-variant-alpine.yaml"
expect_fail "bullseye unsupported" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/invalid-debian-variant-bullseye.yaml"
expect_fail "non-Debian unsupported" "debian_variant is trixie or bookworm" "${FIXTURE_DIR}/invalid-debian-variant-non-debian.yaml"
expect_fail "old PostgreSQL major unsupported" "pg_major is one of" "${FIXTURE_DIR}/invalid-postgres-major.yaml"
expect_fail "plain PostgreSQL 19 unsupported" "pg_major is one of" "${FIXTURE_DIR}/invalid-postgres-major-19.yaml"
expect_fail "19beta1 unmarked" "19beta1 entries are experimental" "${FIXTURE_DIR}/unmarked-pg19beta1.yaml"
expect_fail "latest outside 18-trixie" "latest_eligible only" "${FIXTURE_DIR}/invalid-latest-eligible-not-18-trixie.yaml"
expect_fail "missing latest" "18-trixie has latest_eligible true|exactly one latest_eligible" "${FIXTURE_DIR}/invalid-latest-eligible-missing-18-trixie.yaml"
expect_fail "multiple latest" "latest_eligible only|exactly one latest_eligible" "${FIXTURE_DIR}/invalid-latest-eligible-multiple.yaml"
expect_fail "invalid platform" "platforms only" "${FIXTURE_DIR}/invalid-platform.yaml"
expect_fail "missing platforms" "non-empty list" "${FIXTURE_DIR}/missing-platforms.yaml"
expect_fail "publish missing required platform" "publishable entries.*platforms exactly" "${FIXTURE_DIR}/publish-true-missing-required-platform.yaml"
expect_fail "publish empty resolver-owned" "publishable entries have resolver-owned values" "${FIXTURE_DIR}/publish-true-empty-resolver-owned.yaml"
expect_fail "publish whitespace resolver-owned" "publishable entries have resolver-owned values" "${FIXTURE_DIR}/publish-true-whitespace-resolver-owned.yaml"
expect_fail "publish empty CNPG tag" "cnpg_tag matches pg_version and debian_variant|publishable entries have resolver-owned values" "${FIXTURE_DIR}/publish-true-empty-cnpg-tag.yaml"
expect_fail "publish false without skip" "non-published entries have non-empty skip_reason" "${FIXTURE_DIR}/publish-false-without-skip-reason.yaml"
expect_fail "invalid extension source" "pgvector_source is base or package|pgaudit_source is base or package" "${FIXTURE_DIR}/invalid-extension-source.yaml"
expect_fail "package extension source missing package version" "package_version.*non-empty when .*_source=package" "${FIXTURE_DIR}/package-source-missing-package-version.yaml"
expect_fail "extension policy missing reason" "non_creatable_reason" "${missing_reason_fixture}"
expect_fail "extension policy missing target" "validation_target" "${missing_target_fixture}"
expect_fail "extension policy unsupported mode" "extensions.pgaudit.validation_mode is supported" "${unsupported_mode_fixture}"
expect_fail "extension policy unsupported mode when creatable true" "extensions.pgaudit.validation_mode is supported" "${valid_true_unsupported_mode_fixture}"
expect_fail "extension policy unknown extension" "extensions.<ext> uses supported extension names" "${unknown_extension_fixture}"

expect_arg_fail "validate-metadata extra args" "zero or one metadata file path" "${FIXTURE_DIR}/valid.yaml" "${FIXTURE_DIR}/invalid-postgres-major.yaml"
expect_arg_fail "validate-metadata empty explicit arg" "metadata file path is non-empty" ""
assert_make_validate_metadata_gate

printf 'PASS story-1.3 metadata validation fixtures\n'
