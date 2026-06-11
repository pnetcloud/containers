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

mapfile -d '' workflow_files < <(find "${ROOT_DIR}/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null | sort -z)
if ((${#workflow_files[@]})); then
  run_optional_tool actionlint "${workflow_files[@]}"
fi

if git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mapfile -d '' shell_scripts < <(git -C "${ROOT_DIR}" ls-files -z 'cloudnative-pg-timescaledb/scripts/*.sh' 'cloudnative-pg-timescaledb/scripts/**/*.sh' | sort -z | while IFS= read -r -d '' path; do printf '%s\0' "${ROOT_DIR}/${path}"; done)
else
  mapfile -d '' shell_scripts < <(find "${ROOT_DIR}/cloudnative-pg-timescaledb/scripts" -type f -name '*.sh' -print0 | sort -z)
fi
if ((${#shell_scripts[@]})); then
  run_optional_tool shellcheck "${shell_scripts[@]}"
fi

python3 - "${ROOT_DIR}" "${POLICY_FILE}" <<'PY'
from pathlib import Path
import re
import sys
import yaml

root = Path(sys.argv[1])
policy_path = Path(sys.argv[2])

COMMAND = "validate-workflows"
ACTION_RE = re.compile(r"uses:\s*['\"]?([^\s#'\"]+)['\"]?")
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


def load_workflow(path):
    try:
        payload = yaml.safe_load(path.read_text())
    except Exception as exc:
        diag(path, "workflow YAML parses", str(exc), "Keep workflow files valid YAML.")
    if not isinstance(payload, dict):
        diag(path, "workflow YAML is a mapping", type(payload).__name__, "Use a standard GitHub Actions workflow mapping.")
    return payload


def workflow_triggers(payload):
    raw = payload.get(True, payload.get("on", {}))
    if isinstance(raw, str):
        return {raw}
    if isinstance(raw, list):
        return {str(item) for item in raw}
    if isinstance(raw, dict):
        return {str(key) for key in raw}
    return set()


def workflow_jobs(payload, path):
    jobs = payload.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        diag(path, "workflow jobs is a non-empty mapping", type(jobs).__name__, "Define jobs as a YAML mapping.")
    for job, job_payload in jobs.items():
        if not isinstance(job_payload, dict):
            diag(path, f"job {job} is a mapping", type(job_payload).__name__, "Define each job as a YAML mapping.")
    return {str(job): job_payload for job, job_payload in jobs.items()}


def shell_semicolon_segments(line):
    segments = []
    current = []
    quote = None
    escaped = False
    ansi_single_quote = False
    previous = ""
    for char in line:
        if escaped:
            current.append(char)
            escaped = False
            previous = char
            continue
        if char == "\\" and (quote != "'" or ansi_single_quote):
            current.append(char)
            escaped = True
            previous = char
            continue
        if quote:
            current.append(char)
            if char == quote:
                quote = None
                ansi_single_quote = False
            previous = char
            continue
        if char in {"'", '"'}:
            current.append(char)
            quote = char
            ansi_single_quote = char == "'" and previous == "$"
            previous = char
            continue
        if char == ";":
            segments.append("".join(current))
            current = []
            previous = char
            continue
        current.append(char)
        previous = char
    segments.append("".join(current))
    return segments


def shell_word(value, idx):
    chars = []
    quote = None
    escaped = False
    ansi_single_quote = False
    previous = ""
    while idx < len(value):
        char = value[idx]
        if escaped:
            chars.append(char)
            escaped = False
            previous = char
            idx += 1
            continue
        if char == "\\" and (quote != "'" or ansi_single_quote):
            escaped = True
            previous = char
            idx += 1
            continue
        if quote:
            if char == quote:
                quote = None
                ansi_single_quote = False
            else:
                chars.append(char)
            previous = char
            idx += 1
            continue
        if char in {"'", '"'}:
            quote = char
            ansi_single_quote = char == "'" and previous == "$"
            previous = char
            idx += 1
            continue
        if re.match(r"[\s;|&()<>]", char):
            break
        chars.append(char)
        previous = char
        idx += 1
    return "".join(chars).lstrip("\\"), idx


def heredoc_delimiters(value):
    delimiters = []
    quote = None
    escaped = False
    ansi_single_quote = False
    previous = ""
    idx = 0
    while idx < len(value):
        char = value[idx]
        if escaped:
            escaped = False
            previous = char
            idx += 1
            continue
        if char == "\\" and (quote != "'" or ansi_single_quote):
            escaped = True
            previous = char
            idx += 1
            continue
        if quote:
            if char == quote:
                quote = None
                ansi_single_quote = False
            previous = char
            idx += 1
            continue
        if char in {"'", '"'}:
            quote = char
            ansi_single_quote = char == "'" and previous == "$"
            previous = char
            idx += 1
            continue
        if value.startswith("<<<", idx):
            previous = value[idx + 2]
            idx += 3
            continue
        if value.startswith("<<", idx):
            idx += 2
            if idx < len(value) and value[idx] == "-":
                idx += 1
            while idx < len(value) and value[idx].isspace():
                idx += 1
            delimiter, idx = shell_word(value, idx)
            if delimiter:
                delimiters.append(delimiter)
            continue
        previous = char
        idx += 1
    return delimiters


def executable_run_text(run):
    executable = []
    heredoc_queue = []
    shell_block_depth = 0
    stop_after_unsafe_control = False
    for line in run.splitlines():
        if stop_after_unsafe_control:
            break
        if heredoc_queue:
            if line.strip() == heredoc_queue[0]:
                heredoc_queue.pop(0)
            continue
        uncommented = line.split("#", 1)[0]
        for segment in shell_semicolon_segments(uncommented):
            stripped = segment.strip()
            if not stripped:
                continue
            if re.match(r"^(fi|done|esac)\b", stripped):
                shell_block_depth = max(shell_block_depth - 1, 0)
                trailing = re.sub(r"^(fi|done|esac)\b", "", stripped, count=1).strip()
                if trailing:
                    executable.append(trailing)
                    if trailing.startswith(("||", "&&")):
                        stop_after_unsafe_control = True
                        break
                continue
            if shell_block_depth:
                if re.match(r"^(if|while|until|case|for|select)\b", stripped):
                    shell_block_depth += 1
                continue
            if re.match(r"^(echo|printf)\b", stripped):
                continue
            if re.match(r"^(if|while|until|case|for|select)\b", stripped):
                shell_block_depth += 1
                continue
            heredoc_queue.extend(heredoc_delimiters(stripped))
            executable.append(stripped)
    return "\n".join(executable)


def workflow_run_text(payload, path, unconditional_only=False):
    runs = []
    for job, job_payload in workflow_jobs(payload, path).items():
        if unconditional_only and job_payload.get("if") is not None:
            continue
        steps = job_payload.get("steps", [])
        if steps is None:
            continue
        if not isinstance(steps, list):
            diag(path, f"job {job} steps is a list", type(steps).__name__, "Define workflow steps as a list.")
        for idx, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            run = step.get("run")
            if isinstance(run, str):
                if unconditional_only and step.get("if") is not None:
                    continue
                runs.append(executable_run_text(run))
            elif run is not None:
                diag(path, f"job {job} steps[{idx}].run is a string", type(run).__name__, "Use string run blocks.")
    return "\n".join(runs)


def workflow_actions(payload, path):
    actions = []
    for job, job_payload in workflow_jobs(payload, path).items():
        job_action = job_payload.get("uses")
        if isinstance(job_action, str):
            actions.append((job, job_action))
        elif job_action is not None:
            diag(path, f"job {job}.uses is a string", type(job_action).__name__, "Use string reusable workflow references.")
        steps = job_payload.get("steps", [])
        if steps is None:
            continue
        if not isinstance(steps, list):
            diag(path, f"job {job} steps is a list", type(steps).__name__, "Define workflow steps as a list.")
        for idx, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            action = step.get("uses")
            if isinstance(action, str):
                actions.append((job, action))
            elif action is not None:
                diag(path, f"job {job} steps[{idx}].uses is a string", type(action).__name__, "Use string action references.")
    return actions


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


def permissions_from_value(value):
    if value is None:
        return {}
    if isinstance(value, str):
        if value == "write-all":
            return {"*": "write-all"}
        if value == "read-all":
            return {"*": "read-all"}
        diag("permissions", "permissions value is {}, read-all, write-all, or mapping", value, "Use explicit least-privilege permissions.")
    if isinstance(value, dict):
        return {str(key): str(level).strip('"\'') for key, level in value.items()}
    diag("permissions", "permissions value is mapping or scalar", type(value).__name__, "Use explicit least-privilege permissions.")


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


def permission_allowed(policy, workflow, job, permission, level):
    grant = f"{permission}: {level}"
    matches = [item for item in policy["permission_allowlist"] if item["workflow"] == workflow and item["job"] == job and item["permission"] == grant]
    if not matches:
        return False
    if workflow == ".github/workflows/update.yml" and job == "autocommit" and grant == "contents: write":
        return any(
            item["reason"] == "Commit resolver-owned metadata and generated artifacts after make validate"
            and item["owner_story"] == "2.5"
            for item in matches
        )
    return True


def strict_allowed(policy, path):
    return any(item["path"] == path for item in policy["strict_mode_exceptions"])


def readable_version_comment(lines, idx):
    candidates = []
    if idx > 0:
        previous = lines[idx - 1].strip()
        if previous.startswith("#"):
            candidates.append(previous[1:].strip())
    if "#" in lines[idx]:
        candidates.append(lines[idx].split("#", 1)[1].strip())
    return any(re.search(r"\bv?[0-9]+(?:\.[0-9]+){1,2}\b", candidate) for candidate in candidates)


def command_present(run_text, pattern):
    for line in run_text.splitlines():
        match = re.search(pattern, line)
        if not match:
            continue
        suffix = line[match.end():]
        if "||" in suffix or "|&" in suffix:
            continue
        without_redirects = re.sub(r"\d?>&\d|\d?>[^\s;|&]+|&>[^\s;|&]+", "", suffix)
        if re.search(r"(?<![|&])&(?!=|>)|(?<![|])\|(?![|&])", without_redirects):
            continue
        return True
    return False


def validate_workflow(path, policy):
    text = path.read_text()
    rel = path.relative_to(root).as_posix()
    lines = text.splitlines()
    payload = load_workflow(path)
    yaml_jobs = workflow_jobs(payload, path)
    if path.name == "validate.yml":
        run_text = workflow_run_text(payload, path, unconditional_only=True)
        required = {"pull_request", "push", "workflow_dispatch"}
        actual = workflow_triggers(payload)
        if not required.issubset(actual):
            diag(path, f"validate.yml triggers include {sorted(required)}", sorted(actual), "Add pull_request, push, and workflow_dispatch triggers.")
        if not command_present(run_text, r"^\s*make\s+validate\b"):
            diag(path, "validate workflow runs make validate", "missing", "Call make validate from validate.yml.")
        if not command_present(run_text, r"^\s*find\s+\.github/workflows\s+-type\s+f\b.*\|\s*xargs\s+-0\s+actionlint\b"):
            diag(path, "validate workflow runs actionlint through deterministic workflow discovery", "missing", "Use find .github/workflows -type f ... -print0 | sort -z | xargs -0 actionlint.")
        if not command_present(run_text, r"^\s*git\s+ls-files\s+'cloudnative-pg-timescaledb/scripts/\*\.sh'\s+'cloudnative-pg-timescaledb/scripts/\*\*/\*\.sh'\s+\|\s+sort\s+\|\s+xargs\s+shellcheck\b"):
            diag(path, "validate workflow runs shellcheck against git-tracked script list", "missing", "Use git ls-files 'cloudnative-pg-timescaledb/scripts/*.sh' 'cloudnative-pg-timescaledb/scripts/**/*.sh' | sort | xargs shellcheck.")
        if not command_present(run_text, r"^\s*(sudo\s+)?apt-get\s+install\b[^\n]*(^|\s)shellcheck([:=/][^\s;|&]+)?(?=\s|[;|&]|$)"):
            diag(path, "validate workflow installs or provides real shellcheck", "missing", "Install shellcheck before make validate; bash -n is not a sufficient CI gate.")
        if re.search(r"bash\s+-n", run_text) and "shellcheck" not in run_text:
            diag(path, "bash -n is not the CI shell validation gate", "bash -n only", "Run real shellcheck in CI.")
    if "permissions" not in payload:
        diag(path, "workflow declares explicit top-level permissions", "missing", "Set top-level permissions to contents: read or {} to avoid repository default token scope.")
    top_permissions = permissions_from_value(payload.get("permissions"))
    if top_permissions.get("*") == "write-all":
        diag(path, "no write-all permissions", "write-all", "Use explicit least-privilege permissions.")
    for permission, value in top_permissions.items():
        if value == "write":
            diag(path, "no top-level write permissions", f"{permission}: write", "Move write permissions to named allowlisted jobs only.")
    triggers = workflow_triggers(payload)
    for job, action in workflow_actions(payload, path):
        if action.startswith("./"):
            continue
        if not PINNED_RE.fullmatch(action) and not action_allowed(policy, rel, job, action):
            diag(path, "third-party actions pinned to full commit SHA or allowlisted", action, "Pin action refs to 40-character SHAs with readable version comments.")
    for idx, raw in enumerate(lines):
        match = ACTION_RE.search(raw)
        if match and PINNED_RE.fullmatch(match.group(1)) and not readable_version_comment(lines, idx):
            diag(path, "pinned actions include readable version comments", match.group(1), "Add a nearby version comment such as '# actions/checkout v4.2.2'.")
    for job, job_payload in yaml_jobs.items():
        perms = permissions_from_value(job_payload.get("permissions"))
        if perms.get("*") == "write-all":
            diag(path, "no job write-all permissions", f"job={job} write-all", "Use explicit least-privilege job permissions.")
        for permission, value in perms.items():
            if value != "write":
                continue
            if {"pull_request", "pull_request_target"} & triggers:
                diag(path, "pull_request workflows do not receive write tokens", f"job={job} {permission}: write", "Do not grant write permissions to pull_request workflows.")
            if permission not in RELEASE_WRITE_PERMISSIONS or not permission_allowed(policy, rel, job, permission, value):
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
for path in sorted(list(workflow_dir.glob("*.yml")) + list(workflow_dir.glob("*.yaml"))):
    if path.name in {"validate.yml", "update.yml", "build.yml", "security-scan.yml"} or path.exists():
        validate_workflow(path, policy)
validate_strict_mode(policy)
print("PASS validate-workflows policy gates")
PY
