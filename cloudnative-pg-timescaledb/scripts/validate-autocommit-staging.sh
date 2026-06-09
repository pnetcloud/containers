#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALLOWLIST_FILE="${AUTOCOMMIT_ALLOWLIST:-${ROOT_DIR}/cloudnative-pg-timescaledb/config/autocommit-allowlist.txt}"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

python3 - "${ROOT_DIR}" "${ALLOWLIST_FILE}" <<'PY'
from pathlib import Path
import fnmatch
import subprocess
import sys

root = Path(sys.argv[1])
allowlist_path = Path(sys.argv[2])
command = "validate-autocommit-staging"

SECRET_NAMES = (".env", "secret", "secrets", "credential", "credentials", "token", "password", "passwd", "private-key", "private_key")
RUNTIME_SUFFIXES = (".tar", ".log", ".tmp", ".pid", ".sock")
RUNTIME_PARTS = {".cache", "cache", "tmp", "dist", "build", "coverage", "node_modules", "__pycache__"}


def diag(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def load_patterns(path):
    if not path.exists():
        diag(path, "autocommit allowlist exists", "missing", "Create cloudnative-pg-timescaledb/config/autocommit-allowlist.txt.")
    patterns = []
    for line_no, raw in enumerate(path.read_text().splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("/") or ".." in Path(line).parts:
            diag(path, "relative repository allowlist paths", f"line {line_no}: {line}", "Use explicit relative paths under the repository.")
        patterns.append(line)
    if not patterns:
        diag(path, "at least one allowlist pattern", "empty", "Add resolver-owned metadata/generated paths.")
    return patterns


def staged_paths():
    proc = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        diag(root, "git staged diff is readable", proc.stderr.strip(), "Run inside a git checkout before validating autocommit staging.")
    return [line for line in proc.stdout.splitlines() if line]


def tracked_and_untracked_vendor_paths():
    proc = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all", "--", "vendor", "cloudnative-pg-timescaledb/vendor"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        diag(root, "git vendor status is readable", proc.stderr.strip(), "Run inside a git checkout before validating autocommit staging.")
    return [line for line in proc.stdout.splitlines() if line]


def allowed(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def secret_like(path):
    lowered = path.lower()
    name = Path(path).name.lower()
    return name.startswith(".env") or any(part in lowered for part in SECRET_NAMES)


def runtime_artifact(path):
    lowered = path.lower()
    parts = set(Path(path).parts)
    return lowered.endswith(RUNTIME_SUFFIXES) or bool(parts & RUNTIME_PARTS)


patterns = load_patterns(allowlist_path)
paths = staged_paths()
for path in paths:
    if not allowed(path, patterns):
        diag(path, "staged path is listed in autocommit allowlist", path, "Stage only resolver-owned metadata and generated artifacts.")
    vendor_prefix = "vendor" + "/"
    vendor_segment = "/" + "vendor" + "/"
    if path.startswith(vendor_prefix) or vendor_segment in path:
        diag(path, "no vendor paths staged", path, "Remove vendor files from autocommit staging.")
    if secret_like(path):
        diag(path, "no .env, credential, token, password, or secret-like paths staged", path, "Unstage secret-like files and rotate any exposed credentials.")
    if runtime_artifact(path):
        diag(path, "no runtime/build artifacts staged", path, "Unstage runtime outputs, logs, archives, caches, and build artifacts.")
vendor_status = tracked_and_untracked_vendor_paths()
if vendor_status:
    diag("vendor", "no tracked or untracked vendor changes during autocommit", "; ".join(vendor_status), "Remove vendor changes before an update autocommit.")
print(f"PASS validate-autocommit-staging staged_paths={len(paths)}")
PY
