#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAKEFILE="${ROOT_DIR}/Makefile"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

for script in make-help.sh update.sh generate.sh validate.sh matrix.sh bake-print.sh catalog.sh build.sh smoke.sh lib/command.sh; do
  path="${SCRIPT_DIR}/${script}"
  if [[ ! -x "${path}" ]]; then
    diag "test -x ${path}" "${path}" "executable script exists" "missing or not executable" "Create executable delegated script entry points."
    exit 1
  fi
done

for target in help update generate validate matrix bake-print catalog build smoke; do
  if ! grep -Eq "^${target}:" "${MAKEFILE}"; then
    diag "grep target ${target}" "Makefile" "target exists" "missing" "Expose the stable root Make target."
    exit 1
  fi
done

assert_make_recipe_delegates() {
  local target="$1"
  local expected="$2"
  shift 2
  local tmp output
  tmp="$(mktemp)"
  if ! make --no-print-directory -n -C "${ROOT_DIR}" "${target}" "$@" >"${tmp}" 2>&1; then
    output="$(cat "${tmp}")"
    rm -f "${tmp}"
    diag "make -n ${target}" "Makefile target ${target}" "dry-run recipe is printable" "${output}" "Keep the target as a valid delegated Make recipe."
    exit 1
  fi
  output="$(sed -e 's/[[:space:]]*$//' -e '/^$/d' "${tmp}")"
  rm -f "${tmp}"
  if [[ "$(wc -l <<<"${output}")" != "1" || "${output}" != "${expected}" ]]; then
    diag "make -n ${target}" "Makefile target ${target}" "exactly one delegated recipe line: ${expected}" "${output}" "Keep each root Make target as a thin facade over its matching script with no inline logic."
    exit 1
  fi
}

assert_make_recipe_delegates help "cloudnative-pg-timescaledb/scripts/make-help.sh"
assert_make_recipe_delegates update "cloudnative-pg-timescaledb/scripts/update.sh"
assert_make_recipe_delegates generate "cloudnative-pg-timescaledb/scripts/generate.sh"
assert_make_recipe_delegates validate "cloudnative-pg-timescaledb/scripts/validate.sh"
assert_make_recipe_delegates matrix "cloudnative-pg-timescaledb/scripts/matrix.sh"
assert_make_recipe_delegates bake-print "cloudnative-pg-timescaledb/scripts/bake-print.sh"
assert_make_recipe_delegates catalog "cloudnative-pg-timescaledb/scripts/catalog.sh"
assert_make_recipe_delegates build 'cloudnative-pg-timescaledb/scripts/build.sh "18" "trixie"' PG=18 DEBIAN=trixie
assert_make_recipe_delegates smoke 'CHECKS="" cloudnative-pg-timescaledb/scripts/smoke.sh "18" "trixie"' PG=18 DEBIAN=trixie

if grep -Eq 'packagecloud|apt-get|docker buildx|docker build|CREATE EXTENSION|ghcr\.io/.+:' "${MAKEFILE}"; then
  diag "scan Makefile" "Makefile" "no resolver/package/build/publish logic inline" "inline implementation logic found" "Move implementation logic to owned scripts in later stories."
  exit 1
fi

scan_makefile_execution() {
  local makefile_path="$1"
  perl -ne '
    BEGIN {
      $recipe_prefix = "\t";
      $in_recipe = 0;
    }
    chomp;
    my $raw = $_;
    my $line = $raw;
    my $is_recipe = $in_recipe && index($raw, $recipe_prefix) == 0;

    if (!$is_recipe && $raw =~ /^[[:space:]]*#/) {
      next;
    }
    if (!$is_recipe) {
      $line =~ s/[[:space:]]+#.*$//;
    }

    my $unsafe_function = 0;
    while ($line =~ /(\$+)[\(\{](shell|eval)(?=[[:space:]\)\}]|$)/g) {
      if ((length($1) % 2) == 1) {
        $unsafe_function = 1;
        last;
      }
    }
    if (
      $unsafe_function
      || $line =~ /^[ ]*[^#[:space:]][^:=]*!=/
      || $line =~ /^[^#[:space:]][^:=]*:[^#]*[[:space:]][^#[:space:]][^:=]*!=/
    ) {
      print $. . ":" . $_ . "\n";
      $found = 1;
    }

    if (!$is_recipe && $line =~ /^[[:space:]]*\.RECIPEPREFIX[[:space:]]*[:+?]?=[[:space:]]*(.)/) {
      $recipe_prefix = $1;
    }
    if ($is_recipe || $line =~ /^[[:space:]]*$/ || $raw =~ /^[[:space:]]*#/) {
      next;
    }
    if ($line =~ /^[[:space:]]*[^#[:space:]][^:=]*:/ && $line !~ /^[[:space:]]*[^#[:space:]]+[[:space:]]*[:+?]?=/) {
      $in_recipe = 1;
    } else {
      $in_recipe = 0;
    }
    END { exit($found ? 0 : 1) }
  ' "${makefile_path}"
}

assert_makefile_scan_passes() {
  local name="$1"
  local content="$2"
  local fixture output_file
  fixture="$(mktemp)"
  output_file="$(mktemp)"
  printf '%b' "${content}" >"${fixture}"
  if scan_makefile_execution "${fixture}" >"${output_file}"; then
    local output
    output="$(cat "${output_file}")"
    rm -f "${fixture}" "${output_file}"
    diag "scan Makefile fixture ${name}" "Makefile scanner" "fixture passes" "${output}" "Do not reject safe comments or escaped literal Make function text."
    exit 1
  fi
  rm -f "${fixture}" "${output_file}"
}

assert_makefile_scan_fails() {
  local name="$1"
  local content="$2"
  local fixture output_file
  fixture="$(mktemp)"
  output_file="$(mktemp)"
  printf '%b' "${content}" >"${fixture}"
  if ! scan_makefile_execution "${fixture}" >"${output_file}"; then
    local output
    output="$(cat "${output_file}")"
    rm -f "${fixture}" "${output_file}"
    diag "scan Makefile fixture ${name}" "Makefile scanner" "fixture fails" "${output}" "Reject Makefile make-time shell/eval execution and != assignments."
    exit 1
  fi
  rm -f "${fixture}" "${output_file}"
}

# The scanner fixtures intentionally include literal Make function syntax.
# shellcheck disable=SC2016
assert_makefile_scan_passes "top-level tab comment" '\t# $(shell echo harmless top-level comment)\nall:\n\t@echo ok\n'
# shellcheck disable=SC2016
assert_makefile_scan_passes "commented rule semicolon" 'all: # docs; $(shell echo harmless)\n\t@echo ok\n'
# shellcheck disable=SC2016
assert_makefile_scan_passes "escaped recipe literal" 'all:\n\t@printf '"'"'$$(shell date)\n'"'"'\n'
# shellcheck disable=SC2016
assert_makefile_scan_fails "shell assignment" 'VAR := $(shell date)\n'
# shellcheck disable=SC2016
assert_makefile_scan_fails "eval assignment" 'VAR := ${eval GENERATED:=1}\n'
# shellcheck disable=SC2016
assert_makefile_scan_fails "recipe comment shell" 'all:\n\t# $(shell date)\n'
# shellcheck disable=SC2016
assert_makefile_scan_fails "leading-space target recipe comment shell" ' all:\n\t# $(shell date)\n'
# shellcheck disable=SC2016
assert_makefile_scan_fails "recipeprefix comment shell" '.RECIPEPREFIX := >\nall:\n> # $(shell date)\n'
# shellcheck disable=SC2016
assert_makefile_scan_fails "leading-space recipeprefix comment shell" ' .RECIPEPREFIX := >\nall:\n> # $(shell date)\n'
# shellcheck disable=SC2016
assert_makefile_scan_fails "odd dollar shell" 'all:\n\t@printf '"'"'$$$(shell date)\n'"'"'\n'
assert_makefile_scan_fails "shell assignment operator" 'VAR != date\n'
assert_makefile_scan_fails "target-specific shell assignment operator" 'all: VAR != date\n'

if scan_makefile_execution "${MAKEFILE}"; then
  diag "scan Makefile" "Makefile" "no make-time shell/eval execution in command facade" "make-time execution construct found" "Keep root Makefile targets as direct script delegations without hidden expansion-time logic."
  exit 1
fi

if grep -RIn --exclude-dir=tests --exclude='story-1-2-*' 'vendor/' "${MAKEFILE}" "${SCRIPT_DIR}"; then
  diag "scan command surface" "Makefile and scripts" "no command-surface dependency on reference trees" "reference-tree path found" "Remove command-surface dependency on reference-only inputs."
  exit 1
fi

if ! grep -Fq 'story-1-2-make-help.sh' "${SCRIPT_DIR}/validate.sh" \
  || ! grep -Fq 'story-1-2-make-delegation.sh' "${SCRIPT_DIR}/validate.sh" \
  || ! grep -Fq 'story-1-2-make-params.sh' "${SCRIPT_DIR}/validate.sh"; then
  diag "scan validate.sh" "cloudnative-pg-timescaledb/scripts/validate.sh" "make validate runs Story 1.2 gates" "missing Story 1.2 test delegation" "Call the Story 1.2 tests from scripts/validate.sh."
  exit 1
fi

# BEGIN story-1-2 sandbox proof
sandbox="$(mktemp -d)"
trap 'rm -rf "${sandbox}"' EXIT
mkdir -p "${sandbox}/cloudnative-pg-timescaledb/scripts/lib" "${sandbox}/cloudnative-pg-timescaledb/tests"
cp "${MAKEFILE}" "${sandbox}/Makefile"
cp "${ROOT_DIR}/cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh" "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh"
sed -i '/^# BEGIN story-1-2 sandbox proof$/,/^# END story-1-2 sandbox proof$/c\\:' "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh"
chmod +x "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-delegation.sh"

for script in make-help update generate validate matrix bake-print catalog build smoke validate-metadata validate-tags validate-generated validate-docs validate-barman-boundary validate-workflows lib/command; do
    path="${sandbox}/cloudnative-pg-timescaledb/scripts/${script}.sh"
    mkdir -p "$(dirname "${path}")"
    cat >"${path}" <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'STUB %s\n' '${script}'
exit 0
SH
    chmod +x "${path}"
done

assert_sandbox_target_executes_script() {
    local target="$1"
    local marker="$2"
    shift 2
    local tmp output
    tmp="$(mktemp)"
    if ! make -C "${sandbox}" "${target}" "$@" >"${tmp}" 2>&1; then
      output="$(cat "${tmp}")"
      rm -f "${tmp}"
      diag "make ${target} sandbox" "Makefile target ${target}" "target executes successfully with stubbed script" "${output}" "Keep each Make target executable through its delegated script."
      exit 1
    fi
    output="$(cat "${tmp}")"
    rm -f "${tmp}"
    if ! grep -Fq "${marker}" <<<"${output}"; then
      diag "make ${target} sandbox" "Makefile target ${target}" "target executes ${marker}" "${output}" "Do not satisfy delegation checks with comments, echo-only recipes, or unrelated Makefile text."
      exit 1
    fi
}

assert_sandbox_target_executes_script help "STUB make-help"
assert_sandbox_target_executes_script update "STUB update"
assert_sandbox_target_executes_script generate "STUB generate"
assert_sandbox_target_executes_script matrix "STUB matrix"
assert_sandbox_target_executes_script bake-print "STUB bake-print"
assert_sandbox_target_executes_script catalog "STUB catalog"
assert_sandbox_target_executes_script build "STUB build" PG=18 DEBIAN=trixie
assert_sandbox_target_executes_script smoke "STUB smoke" PG=18 DEBIAN=trixie
assert_sandbox_target_executes_script validate "STUB validate"

cp "${SCRIPT_DIR}/validate.sh" "${sandbox}/cloudnative-pg-timescaledb/scripts/validate.sh"
chmod +x "${sandbox}/cloudnative-pg-timescaledb/scripts/validate.sh"
cat >"${sandbox}/cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'PASS story-1.1 source-of-truth validation\n'
SH
cat >"${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'PASS story-1.2 make help\n'
SH
cat >"${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'PASS story-1.2 make params\n'
SH
chmod +x "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-1-source-of-truth.sh" \
  "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-help.sh" \
  "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh"

for runner in \
  metadata tags generators dockerfile package-install bake matrix smoke/container smoke/sql generated-drift cnpg-resolver packagecloud update \
  workflows/permissions workflows/summaries workflows/build-candidates security-scan release-evidence publish-tag-promotion catalog \
  workflows/update-autocommit renovate barman-plugin docs/barman-plugin docs/readme docs/tags docs/catalog docs/verification docs/maintainer \
  docs/troubleshooting release-rehearsal docs-validation; do
  path="${sandbox}/cloudnative-pg-timescaledb/tests/${runner}/run.sh"
  mkdir -p "$(dirname "${path}")"
  cat >"${path}" <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'STUB tests/%s/run.sh\n' '${runner}'
exit 0
SH
  chmod +x "${path}"
done

tmp="$(mktemp)"
if ! make -C "${sandbox}" validate >"${tmp}" 2>&1; then
    output="$(cat "${tmp}")"
    rm -f "${tmp}"
    diag "make validate sandbox" "validate target" "make validate executes Story 1.2 gates through scripts/validate.sh" "${output}" "Keep make validate delegated while avoiding heavy later-story gates in this test sandbox."
    exit 1
fi
output="$(cat "${tmp}")"
rm -f "${tmp}"
for marker in 'PASS story-1.2 make help' 'PASS story-1.2 make delegation' 'PASS story-1.2 make params' 'PASS make validate Story 1.2 command-surface gates' 'PASS make validate Story 1.2 available gates'; do
    if ! grep -Fq "${marker}" <<<"${output}"; then
      diag "make validate sandbox" "validate target" "${marker}" "${output}" "Ensure scripts/validate.sh actually reaches Story 1.2 gates."
      exit 1
    fi
done
line_of() {
  local marker="$1"
  grep -nF "${marker}" <<<"${output}" | head -n1 | cut -d: -f1
}

max_story_gate_line=0
for marker in 'PASS story-1.2 make help' 'PASS story-1.2 make delegation' 'PASS story-1.2 make params'; do
  marker_line="$(line_of "${marker}")"
  if [[ -z "${marker_line}" ]]; then
    diag "make validate sandbox" "validate target" "${marker}" "${output}" "Ensure scripts/validate.sh actually reaches every Story 1.2 gate."
    exit 1
  fi
  if (( marker_line > max_story_gate_line )); then
    max_story_gate_line="${marker_line}"
  fi
done

min_later_validator_line=0
for marker in \
  'PASS make validate Story 1.2 command-surface gates' 'STUB validate-metadata' 'STUB validate-tags' 'STUB validate-generated' 'STUB validate-docs' \
  'STUB validate-barman-boundary' 'STUB validate-workflows' 'STUB tests/metadata/run.sh' 'STUB tests/tags/run.sh' 'STUB tests/generators/run.sh' \
  'STUB tests/dockerfile/run.sh' 'STUB tests/package-install/run.sh' 'STUB tests/bake/run.sh' 'STUB tests/matrix/run.sh' \
  'STUB tests/smoke/container/run.sh' 'STUB tests/smoke/sql/run.sh' 'STUB tests/generated-drift/run.sh' 'STUB tests/cnpg-resolver/run.sh' \
  'STUB tests/packagecloud/run.sh' 'STUB tests/update/run.sh' 'STUB tests/workflows/permissions/run.sh' 'STUB tests/workflows/summaries/run.sh' \
  'STUB tests/workflows/build-candidates/run.sh' 'STUB tests/security-scan/run.sh' 'STUB tests/release-evidence/run.sh' \
  'STUB tests/publish-tag-promotion/run.sh' 'STUB tests/catalog/run.sh' 'STUB tests/workflows/update-autocommit/run.sh' 'STUB tests/renovate/run.sh' \
  'STUB tests/barman-plugin/run.sh' 'STUB tests/docs/barman-plugin/run.sh' 'STUB tests/docs/readme/run.sh' 'STUB tests/docs/tags/run.sh' \
  'STUB tests/docs/catalog/run.sh' 'STUB tests/docs/verification/run.sh' 'STUB tests/docs/maintainer/run.sh' \
  'STUB tests/docs/troubleshooting/run.sh' 'STUB tests/release-rehearsal/run.sh' 'STUB tests/docs-validation/run.sh'; do
  marker_line="$(line_of "${marker}")"
  if [[ -z "${marker_line}" ]]; then
    diag "make validate sandbox" "validate target" "${marker}" "${output}" "Ensure later validators are present in the validate ordering proof."
    exit 1
  fi
  if (( min_later_validator_line == 0 || marker_line < min_later_validator_line )); then
    min_later_validator_line="${marker_line}"
  fi
done

if (( max_story_gate_line >= min_later_validator_line )); then
    diag "make validate sandbox" "validate target" "Story 1.2 gates run before later validators" "${output}" "Run command-surface gates before later-story heavy validation so Story 1.2 failures are visible."
    exit 1
fi

cat >"${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'PASS story-1.2 make params\n'
exit 42
SH
chmod +x "${sandbox}/cloudnative-pg-timescaledb/tests/story-1-2-make-params.sh"
tmp="$(mktemp)"
if make -C "${sandbox}" validate >"${tmp}" 2>&1; then
    output="$(cat "${tmp}")"
    rm -f "${tmp}"
    diag "make validate fail-fast sandbox" "validate target" "Story 1.2 gate failure stops make validate with non-zero status" "${output}" "Do not mask Story 1.2 validation failures before later validators."
    exit 1
fi
output="$(cat "${tmp}")"
rm -f "${tmp}"
if ! grep -Fq 'PASS story-1.2 make params' <<<"${output}"; then
    diag "make validate fail-fast sandbox" "validate target" "failing Story 1.2 gate was reached" "${output}" "Keep Story 1.2 gates directly executed by scripts/validate.sh."
    exit 1
fi
if grep -Fq 'STUB validate-metadata' <<<"${output}"; then
    diag "make validate fail-fast sandbox" "validate target" "later validators do not run after a Story 1.2 failure" "${output}" "Keep scripts/validate.sh fail-fast; avoid '|| true' or equivalent masking around Story 1.2 gates."
    exit 1
fi
# END story-1-2 sandbox proof

printf 'PASS story-1.2 make delegation\n'
