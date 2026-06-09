#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="${VALIDATE_WORKFLOWS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
POLICY_FILE="${ROOT_DIR}/cloudnative-pg-timescaledb/workflow-policy.yaml"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

run_optional_tool() {
  local tool="$1"
  shift
  if command -v "${tool}" >/dev/null 2>&1; then
    "${tool}" "$@"
  else
    printf 'SKIP %s unavailable; CI validate.yml installs it before make validate\n' "${tool}" >&2
  fi
}

mapfile -d '' workflow_files < <(find "${ROOT_DIR}/.github/workflows" -maxdepth 1 -type f -name '*.yml' -print0 2>/dev/null | sort -z)
if ((${#workflow_files[@]})); then
  run_optional_tool actionlint "${workflow_files[@]}"
fi

mapfile -d '' shell_scripts < <(find "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts" -type f -name '*.sh' -print0 | sort -z)
if ((${#shell_scripts[@]})); then
  run_optional_tool shellcheck "${shell_scripts[@]}"
fi

python3 - "${ROOT_DIR}" "${POLICY_FILE}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
policy_path = Path(sys.argv[2])

COMMAND = "validate-workflows"
ACTION_RE = re.compile(r"uses:\s*([^\s#]+)")
PINNED_RE = re.compile(r"^[^@]+@[0-9a-f]{40}$")
REQUIRED_POLICY_KEYS = {
    "action_pin_exceptions": {"workflow", "job", "action", "reason", "owner_story"},
    "strict_mode_exceptions": {"path", "reason", "owner_story"},
    "permission_allowlist": {"workflow", "job", "permission", "reason", "owner_story"},
}
RELEASE_WRITE_PERMISSIONS = {"contents", "packages", "id-token", "security-events"}


def diag(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {COMMAND}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def parse_policy(path):
    if not path.exists():
        diag(path, "workflow policy file exists", "missing", "Create cloudnative-pg-timescaledb/workflow-policy.yaml.")
    policy = {key: [] for key in REQUIRED_POLICY_KEYS}
    current = None
    current_item = None
    for line_no, raw in enumerate(path.read_text().splitlines(), start=1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        text = raw.strip()
        if indent == 0:
            if ":" not in text:
                diag(path, "parseable workflow policy YAML subset", f"line {line_no}: {text}", "Use top-level key/value entries.")
            key, value = text.split(":", 1)
            key = key.strip()
            if key not in REQUIRED_POLICY_KEYS:
                diag(path, f"top-level keys exactly {sorted(REQUIRED_POLICY_KEYS)}", key, "Use only documented workflow policy keys.")
            if value.strip() == "[]":
                policy[key] = []
                current = None
            elif value.strip() == "":
                policy[key] = []
                current = key
            else:
                diag(path, "policy values are [] or list blocks", text, "Use documented list-of-maps policy entries.")
            continue
        if indent == 2 and current:
            if not text.startswith("- "):
                diag(path, "policy list item", f"line {line_no}: {text}", "Use '- field: value' list entries.")
            current_item = {}
            policy[current].append(current_item)
            item = text[2:]
            if item:
                if ":" not in item:
                    diag(path, "policy list mapping", f"line {line_no}: {text}", "Use key/value list entries.")
                key, value = item.split(":", 1)
                current_item[key.strip()] = value.strip().strip('"')
            continue
        if indent == 4 and current_item is not None:
            if ":" not in text:
                diag(path, "policy mapping item", f"line {line_no}: {text}", "Use key/value list entries.")
            key, value = text.split(":", 1)
            current_item[key.strip()] = value.strip().strip('"')
            continue
        diag(path, "parseable workflow policy YAML subset", f"line {line_no}: {raw}", "Use documented indentation.")
    if set(policy) != set(REQUIRED_POLICY_KEYS):
        diag(path, f"top-level keys exactly {sorted(REQUIRED_POLICY_KEYS)}", sorted(policy), "Preserve the documented policy schema.")
    for list_name, required in REQUIRED_POLICY_KEYS.items():
        for idx, item in enumerate(policy[list_name]):
            if set(item) != required or any(not str(item[key]).strip() for key in required):
                diag(path, f"{list_name}[{idx}] keys exactly {sorted(required)} with non-empty values", item, "Fix or remove the allowlist entry.")
    return policy


def line_value(line):
    return line.split(":", 1)[1].strip().strip('"')


def workflow_triggers(text):
    triggers = set()
    in_on = False
    for raw in text.splitlines():
        stripped = raw.strip()
        if re.match(r"^on:\s*$", stripped):
            in_on = True
            continue
        if in_on:
            indent = len(raw) - len(raw.lstrip(" "))
            if indent == 0 and stripped and not stripped.startswith("#"):
                break
            match = re.match(r"^\s{2}([A-Za-z_]+):", raw)
            if match:
                triggers.add(match.group(1))
    return triggers


def top_level_block(lines, key):
    start = None
    for idx, raw in enumerate(lines):
        if re.match(rf"^{re.escape(key)}:\s*", raw):
            start = idx
            break
    if start is None:
        return []
    block = [lines[start]]
    for raw in lines[start + 1:]:
        if raw.strip() and not raw.startswith(" "):
            break
        block.append(raw)
    return block


def job_blocks(lines):
    jobs = {}
    in_jobs = False
    current = None
    for raw in lines:
        if re.match(r"^jobs:\s*$", raw):
            in_jobs = True
            continue
        if in_jobs:
            if raw.strip() and not raw.startswith(" "):
                break
            match = re.match(r"^\s{2}([A-Za-z0-9_-]+):\s*$", raw)
            if match:
                current = match.group(1)
                jobs[current] = [raw]
            elif current:
                jobs[current].append(raw)
    return jobs


def permissions_from_block(block):
    if not block:
        return {}
    first = block[0]
    if "write-all" in first:
        return {"*": "write-all"}
    if "read-all" in first:
        return {"*": "read-all"}
    if "{}" in first:
        return {}
    permissions = {}
    for raw in block[1:]:
        match = re.match(r"^\s+([A-Za-z0-9_-]+):\s*([A-Za-z-]+)\s*$", raw)
        if match:
            permissions[match.group(1)] = match.group(2)
    return permissions


def action_allowed(policy, workflow, job, action):
    return any(item["workflow"] == workflow and item["job"] == job and item["action"] == action for item in policy["action_pin_exceptions"])


def permission_allowed(policy, workflow, job, permission):
    return any(item["workflow"] == workflow and item["job"] == job and item["permission"] == permission for item in policy["permission_allowlist"])


def strict_allowed(policy, path):
    return any(item["path"] == path for item in policy["strict_mode_exceptions"])


def readable_version_comment(lines, idx):
    candidates = []
    if idx > 0:
        candidates.append(lines[idx - 1].strip())
    candidates.append(lines[idx].split("#", 1)[1].strip() if "#" in lines[idx] else "")
    return any(re.search(r"\bv?[0-9]+(?:\.[0-9]+){1,2}\b", candidate) for candidate in candidates if candidate.startswith("#") or candidate)


def validate_workflow(path, policy):
    text = path.read_text()
    rel = path.relative_to(root).as_posix()
    lines = text.splitlines()
    if path.name == "validate.yml":
        required = {"pull_request", "push", "workflow_dispatch"}
        actual = workflow_triggers(text)
        if not required.issubset(actual):
            diag(path, f"validate.yml triggers include {sorted(required)}", sorted(actual), "Add pull_request, push, and workflow_dispatch triggers.")
        if "make validate" not in text:
            diag(path, "validate workflow runs make validate", "missing", "Call make validate from validate.yml.")
    top_permissions = permissions_from_block(top_level_block(lines, "permissions"))
    if top_permissions.get("*") == "write-all":
        diag(path, "no write-all permissions", "write-all", "Use explicit least-privilege permissions.")
    for permission, value in top_permissions.items():
        if value == "write":
            diag(path, "no top-level write permissions", f"{permission}: write", "Move write permissions to named allowlisted jobs only.")
    triggers = workflow_triggers(text)
    jobs = job_blocks(lines)
    current_job = "<top-level>"
    for idx, raw in enumerate(lines):
        job_match = re.match(r"^\s{2}([A-Za-z0-9_-]+):\s*$", raw)
        if job_match and any(raw in block for block in jobs.values()):
            current_job = job_match.group(1)
        match = ACTION_RE.search(raw)
        if not match:
            continue
        action = match.group(1)
        if action.startswith("./"):
            continue
        if not PINNED_RE.fullmatch(action) and not action_allowed(policy, rel, current_job, action):
            diag(path, "third-party actions pinned to full commit SHA or allowlisted", action, "Pin action refs to 40-character SHAs with readable version comments.")
        if PINNED_RE.fullmatch(action) and not readable_version_comment(lines, idx):
            diag(path, "pinned actions include readable version comments", action, "Add a nearby version comment such as '# actions/checkout v4.2.2'.")
    for job, block in jobs.items():
        perms = permissions_from_block([line[4:] if line.startswith("    ") else line for line in block if re.match(r"^\s{4}permissions:", line) or re.match(r"^\s{6}[A-Za-z0-9_-]+:", line)])
        if perms.get("*") == "write-all":
            diag(path, "no job write-all permissions", f"job={job} write-all", "Use explicit least-privilege job permissions.")
        for permission, value in perms.items():
            if value != "write":
                continue
            if "pull_request" in triggers:
                diag(path, "pull_request workflows do not receive write tokens", f"job={job} {permission}: write", "Do not grant write permissions to pull_request workflows.")
            if permission not in RELEASE_WRITE_PERMISSIONS or not permission_allowed(policy, rel, job, permission):
                diag(path, "write permissions are explicitly allowlisted for named jobs", f"job={job} {permission}: write", "Add a justified workflow-policy permission_allowlist entry in the owning story.")


def validate_strict_mode(policy):
    paths = sorted((root / "cloudnative-pg-timescaledb/scripts").rglob("*.sh"))
    for path in paths:
        rel = path.relative_to(root).as_posix()
        if strict_allowed(policy, rel):
            continue
        head = "\n".join(path.read_text(errors="ignore").splitlines()[:10])
        if "set -Eeuo pipefail" not in head:
            diag(path, "CI-consumed shell scripts use set -Eeuo pipefail or are allowlisted", "missing strict mode", "Add strict mode near the top or document an exception in workflow-policy.yaml.")


policy = parse_policy(policy_path)
workflow_dir = root / ".github/workflows"
validate_yml = workflow_dir / "validate.yml"
if not validate_yml.exists():
    diag(validate_yml, "validate workflow exists", "missing", "Create .github/workflows/validate.yml.")
for path in sorted(workflow_dir.glob("*.yml")):
    if path.name in {"validate.yml", "update.yml", "build.yml", "security-scan.yml"} or path.exists():
        validate_workflow(path, policy)
validate_strict_mode(policy)
print("PASS validate-workflows policy gates")
PY
