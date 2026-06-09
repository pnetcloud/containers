#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/tests/renovate/fixtures"
RENOVATE_CONFIG="${ROOT_DIR}/renovate.json"
ORIGIN_RULES="${ROOT_DIR}/cloudnative-pg-timescaledb/config/change-origin-rules.json"
CLASSIFIER="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts/classify-update-origin.sh"

python3 - "${ROOT_DIR}" "${FIXTURE_DIR}" "${RENOVATE_CONFIG}" "${ORIGIN_RULES}" "${CLASSIFIER}" <<'PY'
from pathlib import Path
import fnmatch
import json
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
fixture_dir = Path(sys.argv[2])
renovate_config = Path(sys.argv[3])
origin_rules = Path(sys.argv[4])
classifier = Path(sys.argv[5])
command = "tests/renovate/run.sh"

forbidden_fields = {
    "pg_major",
    "pg_version",
    "debian_variant",
    "cnpg_tag",
    "cnpg_digest",
    "timescaledb_version",
    "timescaledb_package_version",
    "toolkit_version",
    "toolkit_package_version",
    "platforms",
    "publish",
    "experimental",
    "latest_eligible",
    "skip_reason",
    "barman_plugin.*",
}
forbidden_terms = forbidden_fields | {
    "standard-",
    "barman-cloud",
    "barman cli",
    "barman-cli",
    "backup-tooling",
    "backup tooling",
}
required_ignore_paths = {
    "vendor/**",
    "cloudnative-pg-timescaledb/versions.yaml",
    "cloudnative-pg-timescaledb/generated/**",
}
required_resolver_paths = {
    "cloudnative-pg-timescaledb/versions.yaml",
    "cloudnative-pg-timescaledb/generated/**",
    "cloudnative-pg-timescaledb/docker-bake.hcl",
    "cloudnative-pg-timescaledb/matrix.json",
}
required_renovate_paths = {
    "renovate.json",
    "package.json",
    "package-lock.json",
    ".github/workflows/*.yml",
}


def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(path, "file exists", "missing", "Create the expected Renovate boundary artifact.")
    except json.JSONDecodeError as exc:
        fail(path, "valid JSON", str(exc), "Fix JSON syntax.")


def walk(value):
    if isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)
    elif isinstance(value, str):
        yield value


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def strings_lower(value):
    return [item.lower() for item in walk(value)]


def contains_term(value, terms):
    strings = strings_lower(value)
    for term in terms:
        lowered = term.lower().rstrip("*")
        if any(lowered in item for item in strings):
            return term
    return None


def manager_file_patterns(manager):
    patterns = []
    for key in ("fileMatch", "managerFilePatterns", "matchPaths", "paths"):
        patterns.extend(str(item) for item in as_list(manager.get(key)))
    return patterns


def validate_origin_rules(path):
    rules = load_json(path)
    for key in ("renovate_originated", "resolver_originated"):
        if not isinstance(rules.get(key), list):
            fail(path, f"{key} is a list", type(rules.get(key)).__name__, "Preserve the origin rules schema.")
    renovate_paths = {item.get("path") for item in rules["renovate_originated"] if isinstance(item, dict)}
    resolver_paths = {item.get("path") for item in rules["resolver_originated"] if isinstance(item, dict)}
    resolver_fields = {item.get("metadata_field") for item in rules["resolver_originated"] if isinstance(item, dict)}
    if not required_renovate_paths.issubset(renovate_paths):
        fail(path, f"renovate paths include {sorted(required_renovate_paths)}", sorted(renovate_paths), "Add missing Renovate-originated path rules.")
    if not required_resolver_paths.issubset(resolver_paths):
        fail(path, f"resolver paths include {sorted(required_resolver_paths)}", sorted(resolver_paths), "Add missing resolver-originated path rules.")
    if not forbidden_fields.issubset(resolver_fields):
        fail(path, f"resolver metadata fields include {sorted(forbidden_fields)}", sorted(resolver_fields), "Classify every resolver-owned metadata field as resolver-originated.")
    return rules


def validate_renovate_config(path, *, expect_valid):
    config = load_json(path)
    errors = []

    enabled = set(config.get("enabledManagers", []))
    if enabled and not enabled.issubset({"github-actions", "npm"}):
        errors.append(f"enabledManagers={sorted(enabled)}")

    ignore_paths = set(config.get("ignorePaths", []))
    missing_ignores = required_ignore_paths - ignore_paths
    if missing_ignores:
        errors.append(f"missing ignorePaths={sorted(missing_ignores)}")

    for idx, rule in enumerate(config.get("packageRules", [])):
        managers = set(rule.get("matchManagers", []))
        update_types = set(rule.get("matchUpdateTypes", []))
        if "major" in update_types and rule.get("automerge") is True:
            errors.append(f"packageRules[{idx}] automerges major updates")
        if rule.get("automerge") is True:
            broad = not managers
            release_sensitive = "github-actions" in managers or contains_term(rule, {"release-sensitive", "workflow"})
            npm_patch_minor_only = managers == {"npm"} and update_types.issubset({"patch", "minor"}) and update_types
            if (broad or release_sensitive) and not npm_patch_minor_only:
                errors.append(f"packageRules[{idx}] has broad/release-sensitive automerge")

    managers = []
    for key in ("customManagers", "regexManagers"):
        for manager in as_list(config.get(key)):
            if isinstance(manager, dict):
                managers.append((key, manager))
    for idx, (key, manager) in enumerate(managers):
        patterns = manager_file_patterns(manager)
        targets_versions = any(
            "versions.yaml" in pattern or fnmatch.fnmatchcase("cloudnative-pg-timescaledb/versions.yaml", pattern)
            for pattern in patterns
        )
        term = contains_term(manager, forbidden_terms)
        if targets_versions or term:
            errors.append(f"{key}[{idx}] targets resolver-owned surface term={term or 'versions.yaml'}")

    global_forbidden = contains_term(config.get("customManagers", []), forbidden_terms) or contains_term(config.get("regexManagers", []), forbidden_terms)
    if global_forbidden:
        errors.append(f"custom manager references forbidden term={global_forbidden}")

    if expect_valid and errors:
        fail(path, "Renovate boundary config is accepted", errors, "Restrict Renovate to safe dependency surfaces.")
    if not expect_valid and not errors:
        fail(path, "Renovate boundary fixture is rejected", "accepted", "Add validation logic for the forbidden fixture.")


def validate_classifier_fixture(path):
    fixture = load_json(path)
    changed_files = fixture.get("changed_files")
    expected = fixture.get("expected")
    if not isinstance(changed_files, list) or not isinstance(expected, dict):
        fail(path, "changed_files list and expected object", fixture, "Preserve the summary-origin fixture schema.")
    with tempfile.TemporaryDirectory() as tmp:
        changed_path = Path(tmp) / "changed-files.txt"
        changed_path.write_text("\n".join(changed_files) + "\n", encoding="utf-8")
        proc = subprocess.run(
            [str(classifier), "--rules", str(origin_rules), "--changed-files", str(changed_path)],
            cwd=root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    if proc.returncode != 0:
        fail(path, "classifier exits 0", proc.stderr.strip(), "Fix classify-update-origin.sh diagnostics or rules.")
    actual = json.loads(proc.stdout)
    if actual != expected:
        fail(path, expected, actual, "Update change-origin-rules.json or the expected fixture labels.")


validate_origin_rules(origin_rules)
validate_renovate_config(renovate_config, expect_valid=True)
validate_renovate_config(fixture_dir / "valid-renovate.json", expect_valid=True)

for name in [
    "broad-automerge-release-sensitive.json",
    "resolver-owned-cnpg-manager.json",
    "resolver-owned-versions-yaml-fields.json",
    "resolver-owned-pg-debian-matrix-fields.json",
    "forbidden-legacy-barman-manager.json",
    "forbidden-barman-plugin-metadata-manager.json",
    "major-update-automerge.json",
]:
    validate_renovate_config(fixture_dir / name, expect_valid=False)

validate_classifier_fixture(fixture_dir / "summary-origin-labels.json")
print("PASS renovate boundary gates")
PY
