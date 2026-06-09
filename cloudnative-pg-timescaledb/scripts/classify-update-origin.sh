#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

rules="${ROOT_DIR}/cloudnative-pg-timescaledb/config/change-origin-rules.json"
changed_files=""
while (($#)); do
  case "$1" in
    --rules)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        diag "classify-update-origin" "arguments" "--rules path" "missing" "Pass --rules <path>."
        exit 64
      fi
      rules="${2:-}"
      shift 2
      ;;
    --changed-files)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        diag "classify-update-origin" "arguments" "--changed-files path" "missing" "Pass --changed-files <path>."
        exit 64
      fi
      changed_files="${2:-}"
      shift 2
      ;;
    *)
      diag "classify-update-origin" "arguments" "known option" "$1" "Use --rules <path> and --changed-files <path>."
      exit 64
      ;;
  esac
done

if [[ -z "${changed_files}" ]]; then
  diag "classify-update-origin" "arguments" "--changed-files path" "missing" "Pass a newline-delimited changed files list."
  exit 64
fi

python3 - "${rules}" "${changed_files}" <<'PY'
from pathlib import Path
import fnmatch
import json
import sys

rules_path = Path(sys.argv[1])
changed_path = Path(sys.argv[2])

def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: classify-update-origin\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )

try:
    rules = json.loads(rules_path.read_text())
except FileNotFoundError:
    fail(rules_path, "rules file exists", "missing", "Create change-origin-rules.json.")
except json.JSONDecodeError as exc:
    fail(rules_path, "valid JSON", str(exc), "Fix change-origin-rules.json syntax.")

for key in ["renovate_originated", "resolver_originated"]:
    if key not in rules or not isinstance(rules[key], list):
        fail(rules_path, f"{key} list exists", rules, "Preserve the origin rules schema.")

try:
    changed = [line.strip() for line in changed_path.read_text().splitlines() if line.strip()]
except FileNotFoundError:
    fail(changed_path, "changed files list exists", "missing", "Pass a newline-delimited changed files list.")

def matches(rule, path):
    pattern = rule.get("path")
    return bool(pattern and fnmatch.fnmatchcase(path, pattern))

renovate = []
resolver = []
unknown = []
for path in changed:
    if any(matches(rule, path) for rule in rules["resolver_originated"]):
        resolver.append(path)
    elif any(matches(rule, path) for rule in rules["renovate_originated"]):
        renovate.append(path)
    else:
        unknown.append(path)

print(json.dumps({"renovate_originated": renovate, "resolver_originated": resolver, "unknown": unknown}, separators=(",", ":"), sort_keys=True))
PY
