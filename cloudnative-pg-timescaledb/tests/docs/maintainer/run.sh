#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/docs/maintainer/fixtures"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

validate_maintainer_docs() {
  local maintainer_doc="$1"
  local generated_doc="$2"
  python3 - "${maintainer_doc}" "${generated_doc}" <<'PY'
import re
import sys
from pathlib import Path

maintainer = Path(sys.argv[1])
generated = Path(sys.argv[2])
command = f"validate-maintainer-docs {maintainer} {generated}"

def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {str(actual).replace(chr(10), ' ')[:320]}\n"
        f"remediation: {remediation}"
    )

def require(pattern, expected, remediation, text=None, artifact=None, flags=re.I | re.S):
    haystack = combined if text is None else text
    target = artifact or "combined maintainer docs"
    if not re.search(pattern, haystack, flags):
        fail(target, expected, "missing", remediation)

def reject(pattern, expected, remediation, text=None, artifact=None, flags=re.I | re.S):
    haystack = combined if text is None else text
    target = artifact or "combined maintainer docs"
    match = re.search(pattern, haystack, flags)
    if match:
        fail(target, expected, match.group(0), remediation)

def reject_unless_negated(pattern, expected, remediation, text=None, artifact=None, flags=re.I | re.S):
    haystack = combined if text is None else text
    target = artifact or "combined maintainer docs"
    for match in re.finditer(pattern, haystack, flags):
        window = haystack[max(0, match.start() - 80):match.end() + 80].lower()
        if re.search(r"\b(?:do\s+not|does\s+not|must\s+not|never|not|out\s+of\s+scope|out\s+of\s+v1|renovate-managed)\b", window):
            continue
        fail(target, expected, match.group(0), remediation)

def reject_generated_hand_edit_allowed(text):
    for sentence in re.split(r"(?<=[.!?])\s+|\n+", text):
        if not re.search(r"\b(?:generated|Dockerfile|matrix|Bake|catalog)\b", sentence, re.I):
            continue
        if not re.search(r"\b(?:hand-edit|hand\s+edit|manually\s+edit|patch\s+by\s+hand)\b", sentence, re.I):
            continue
        positive = re.search(r"\b(?:may|can|should|must|allowed|allow|allows|maintainers?\s+hand-edit|maintainers?\s+may|maintainers?\s+can)\b", sentence, re.I)
        final_fix = re.search(r"\b(?:final\s+fix|release\s+fix|final\s+release\s+fix|release\s+pressure)\b", sentence, re.I)
        if positive and final_fix:
            fail("combined maintainer docs", "docs do not allow generated files to be final hand fixes", sentence.strip(), "Keep generated outputs regenerated from sources.")

def require_all_make_targets(text):
    missing = [target for target in ["help", "update", "generate", "validate", "matrix", "bake-print", "catalog", "build", "smoke"] if not re.search(rf"`make\s+{re.escape(target)}(?:\s|`|$)", text)]
    if missing:
        fail(maintainer, "all root Makefile targets are documented", ",".join(missing), "Document help, update, generate, validate, matrix, bake-print, catalog, build, and smoke.")

for path in [maintainer, generated]:
    if not path.exists():
        fail(path, "documentation artifact exists", "missing", "Create docs/maintainer-guide.md and docs/generated-files.md.")

maintainer_text = maintainer.read_text()
generated_text = generated.read_text()
combined = maintainer_text + "\n" + generated_text

require(r"##\s+Release Process", "maintainer guide has a Release Process section", "Add ## Release Process to docs/maintainer-guide.md.", maintainer_text, maintainer)
require(r"cloudnative-pg-timescaledb/versions\.yaml.{0,120}only\s+hand-edited\s+image\s+source\s+of\s+truth|only\s+hand-edited\s+image\s+source\s+of\s+truth.{0,120}cloudnative-pg-timescaledb/versions\.yaml", "versions.yaml is the only hand-edited image source of truth", "State the metadata source-of-truth rule explicitly.")
require(r"generated\s+outputs?.{0,120}committed|committed.{0,120}generated\s+outputs?", "generated outputs are committed", "Explain why generated outputs are committed.")
require(r"not\s+be\s+hand-edited\s+as\s+final\s+fixes|must\s+not\s+be\s+hand-edited\s+as\s+final\s+fixes|not\s+patched\s+by\s+hand\s+as\s+final\s+fixes", "generated outputs are not hand-edited as final fixes", "Direct maintainers to metadata/templates/generators instead of hand fixes.")
reject(r"(?:may|can|should|must)\s+(?:hand-edit|patch\s+by\s+hand|manually\s+edit).{0,120}(?:generated|Dockerfile|matrix|Bake|catalog).{0,120}(?:final\s+fix|source\s+of\s+truth|release)", "docs do not allow generated files to be final hand fixes", "Keep generated outputs regenerated from sources.")
reject_generated_hand_edit_allowed(combined)

require_all_make_targets(maintainer_text)
for command_name in ["make update", "make generate", "make validate", "make bake-print", "make build", "make smoke", "make catalog"]:
    require(re.escape(command_name), f"{command_name} is documented", f"Document {command_name} in maintainer release flow.", maintainer_text, maintainer)

require(r"make\s+update.{0,260}(CloudNativePG|CNPG).{0,260}TimescaleDB.{0,260}Toolkit.{0,260}Barman Cloud Plugin|make\s+update.{0,260}Barman Cloud Plugin.{0,260}(CloudNativePG|CNPG).{0,260}TimescaleDB.{0,260}Toolkit", "make update ownership includes CNPG, TimescaleDB, Toolkit, and Barman Cloud Plugin references", "Keep resolver-owned update scope explicit.")
require(r"Renovate.{0,180}(GitHub Actions|static helper)|(?:GitHub Actions|static helper).{0,180}Renovate", "GitHub Actions and static helper dependencies remain Renovate-managed", "Document the Renovate boundary for non-resolver dependencies.")
reject_unless_negated(r"make\s+update.{0,180}(?:updates|refreshes|owns|updating).{0,120}(?:GitHub Actions|static helper)", "make update is not documented as owning GitHub Actions or static helper dependencies", "Keep these surfaces in the Renovate boundary.")

def reject_pat_default(text):
    pat_alias_seen = False
    for sentence in re.split(r"(?<=[.!?])\s+|\n+", text):
        if re.search(r"\b(?:PAT|personal\s+access\s+token)\b", sentence, re.I):
            pat_alias_seen = True
        mentions_fallback_credential = pat_alias_seen and re.search(r"\bfallback\s+(?:credential|token|mechanism)\b", sentence, re.I)
        if not (re.search(r"\b(?:PAT|personal\s+access\s+token)\b", sentence, re.I) or mentions_fallback_credential):
            continue
        if re.search(r"\b(?:default|preferred|recommended|normal)\b", sentence, re.I) and re.search(r"\b(?:autocommit|credential|token|mechanism)\b", sentence, re.I):
            fail("combined maintainer docs", "PAT is not the default autocommit credential", sentence.strip(), "Make GITHUB_TOKEN the default and PAT only an exception.")

def reject_artifact_hub_release_step(text):
    for sentence in re.split(r"(?<=[.!?])\s+|\n+", text):
        if not re.search(r"Artifact Hub", sentence, re.I):
            continue
        positive_action = re.search(r"\b(?:(?:should|must|may|can|run|use|add|include|publish|generate|update|upload)\b|release\s+step|release\s+maintainers)", sentence, re.I)
        if not positive_action:
            continue
        if re.search(r"\b(?:do\s+not|must\s+not|never)\b", sentence, re.I) and not re.search(r"\b(?:but|however|although|also|then)\b.{0,120}\b(?:should|must|may|can|run|use|add|include|publish|generate|update|upload)", sentence, re.I):
            continue
        fail("combined maintainer docs", "Artifact Hub is not a v1 release step", sentence.strip(), "Do not add Artifact Hub metadata steps to v1 release docs.")

def reject_env_commit_allowed(text):
    for sentence in re.split(r"(?<=[.!?])\s+|\n+", text):
        if not re.search(r"\.env", sentence, re.I):
            continue
        positive = re.search(r"\b(?:may|can|should|must|allowed|allow|allows|commit|committed|include|check\s+in|checked\s+in)\b", sentence, re.I)
        negative_env = re.search(r"\b(?:never|must\s+not|do\s+not|reject|unstage|no)\b.{0,80}\.env|\.env.{0,80}\b(?:never|must\s+not|do\s+not|reject|unstage|no)\b", sentence, re.I)
        if positive and not negative_env:
            fail("combined maintainer docs", ".env files must never be committed", sentence.strip(), "State that .env files and secret-like values are rejected, never committed.")

require(r"scheduled\s+update.{0,120}no-op|no-op.{0,120}scheduled\s+update", "scheduled update no-op behavior is documented", "Explain that no-op scheduled updates create no commit.")
require(r"no-op.{0,120}(?:no\s+commit|create\s+no\s+commit|must\s+create\s+no\s+commit)", "no-op runs create no commits", "State the no-op autocommit invariant.")
require(r"autocommit.{0,120}allowlist|allowlist.{0,120}autocommit", "autocommit path allowlists are documented", "Document update and catalog allowlists.")
require(r"autocommit-allowlist\.txt", "resolver autocommit allowlist path is documented", "Point maintainers to cloudnative-pg-timescaledb/config/autocommit-allowlist.txt.")
require(r"catalog-autocommit-allowlist\.txt", "catalog autocommit allowlist path is documented", "Point maintainers to cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt.")
require(r"(?:loop\s+prevention|recurs(?:e|ion|ively)|bot/generated)", "autocommit loop prevention is documented", "Document recursive generated commit prevention.")

require(r"GITHUB_TOKEN.{0,120}default|default.{0,120}GITHUB_TOKEN", "GITHUB_TOKEN is the default autocommit mechanism", "Use the repository-scoped GitHub token by default.")
require(r"PAT|personal\s+access\s+token", "PAT fallback is named", "Document the exceptional fallback path.")
require(r"(?:branch-protection|branch protection).{0,160}(?:exception|fallback)|(?:exception|fallback).{0,160}(?:branch-protection|branch protection)", "PAT fallback is limited to branch-protection exception", "Do not present PAT as a normal/default credential.")
require(r"(?:blast\s+radius|broader\s+token|security\s+tradeoff|more\s+scopes)", "PAT security tradeoff is documented", "Explain why PAT fallback is riskier than GITHUB_TOKEN.")
reject_pat_default(combined)

require(r"\.env", ".env files are named in the no-commit policy", "State that .env files must never be committed.")
require(r"(?:never|must\s+not|do\s+not).{0,120}(?:commit|print).{0,160}(?:secret|credential|token|registry\s+password|signing\s+secret)|(?:secret|credential|token|registry\s+password|signing\s+secret).{0,160}(?:never|must\s+not|do\s+not).{0,120}(?:commit|print)", "secrets must never be committed or printed", "Keep credential leakage policy explicit.")
reject_env_commit_allowed(combined)

require(r"Artifact Hub.{0,120}(?:out\s+of\s+v1|out\s+of\s+scope|out\s+of\s+v1\s+scope)|(?:out\s+of\s+v1|out\s+of\s+scope|out\s+of\s+v1\s+scope).{0,120}Artifact Hub", "Artifact Hub metadata is out of v1 release scope", "Keep Artifact Hub out of the v1 release process.")
reject_artifact_hub_release_step(combined)

generated_paths = [
    r"cloudnative-pg-timescaledb/generated/\{pg\}/\{debian_variant\}/Dockerfile",
    r"cloudnative-pg-timescaledb/docker-bake\.hcl",
    r"cloudnative-pg-timescaledb/matrix\.json",
    r"cloudnative-pg-timescaledb/catalog/catalog-standard-trixie\.yaml",
    r"cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm\.yaml",
    r"cloudnative-pg-timescaledb/docs/generated/\*\*",
    r"cloudnative-pg-timescaledb/config/generated/\*\*",
    r"\.github/workflows/\*\*",
]
missing_paths = [pattern for pattern in generated_paths if not re.search(pattern, generated_text)]
if missing_paths:
    fail(generated, "generated file ownership matrix includes required paths", ",".join(missing_paths), "Add every required generated path/glob to docs/generated-files.md.")
for phrase in ["Source of truth", "Generator command", "Commit policy", "Hand-edit policy"]:
    require(re.escape(phrase), f"generated files matrix has {phrase} column", "Keep the ownership matrix complete.", generated_text, generated)

for required_command in ["make generate", "make update", "make catalog", "make validate", "make matrix", "make bake-print"]:
    require(re.escape(required_command), f"{required_command} appears in generated file policy", f"Document {required_command} where generated ownership uses it.", generated_text, generated)
PY
}

expect_fail() {
  local fixture="$1"
  local pattern="$2"
  local tmp status
  tmp="$(mktemp)"
  set +e
  validate_maintainer_docs "${FIXTURE_DIR}/${fixture}" "${FIXTURE_DIR}/${fixture}" >"${tmp}" 2>&1
  status="$?"
  set -e
  if [[ "${status}" == "0" ]]; then
    diag "validate-maintainer-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "fixture fails" "passed" "Make the negative maintainer docs fixture fail on its intended invariant."
    rm -f "${tmp}"
    exit 1
  fi
  if ! grep -E -q "${pattern}" "${tmp}"; then
    diag "validate-maintainer-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic matches ${pattern}" "$(tr '\n' ' ' <"${tmp}")" "Keep maintainer docs diagnostics deterministic and actionable."
    rm -f "${tmp}"
    exit 1
  fi
  for required in 'command:' 'artifact:' 'expected:' 'actual:' 'remediation:'; do
    if ! grep -Fq "${required}" "${tmp}"; then
      diag "validate-maintainer-docs ${fixture}" "${FIXTURE_DIR}/${fixture}" "diagnostic includes ${required}" "$(tr '\n' ' ' <"${tmp}")" "Use the standard validation diagnostic shape."
      rm -f "${tmp}"
      exit 1
    fi
  done
  rm -f "${tmp}"
}

for fixture in \
  valid-maintainer-docs.md \
  generated-files-hand-edit-allowed.md \
  missing-make-target.md \
  pat-default-token.md \
  missing-no-env-policy.md \
  artifact-hub-release-step.md; do
  [[ -f "${FIXTURE_DIR}/${fixture}" ]] || {
    diag "test -f" "${FIXTURE_DIR}/${fixture}" "Story 5.6 fixture exists" "missing" "Restore the complete maintainer docs fixture set."
    exit 1
  }
done

validate_maintainer_docs "${ROOT_DIR}/docs/maintainer-guide.md" "${ROOT_DIR}/docs/generated-files.md"
validate_maintainer_docs "${FIXTURE_DIR}/valid-maintainer-docs.md" "${FIXTURE_DIR}/valid-maintainer-docs.md"

expect_fail generated-files-hand-edit-allowed.md "hand-edit|generated outputs|final"
expect_fail missing-make-target.md "Makefile targets|make bake-print|make smoke|make matrix"
expect_fail pat-default-token.md "PAT is not the default|GITHUB_TOKEN"
expect_fail missing-no-env-policy.md "\.env|secrets"
expect_fail artifact-hub-release-step.md "Artifact Hub is not a v1 release step|out of v1"

printf 'PASS story-5.6 maintainer documentation fixtures\n'
