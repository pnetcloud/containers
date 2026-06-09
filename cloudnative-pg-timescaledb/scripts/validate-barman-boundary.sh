#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if (($#)); then
  scan_paths=("$@")
else
  scan_paths=(
    "cloudnative-pg-timescaledb/templates/Dockerfile.tmpl"
    "cloudnative-pg-timescaledb/templates"
    "cloudnative-pg-timescaledb/generated"
    "cloudnative-pg-timescaledb/docs"
    "docs"
    "cloudnative-pg-timescaledb/README.md"
  )
fi

python3 - "${ROOT_DIR}" "${scan_paths[@]}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
paths = sys.argv[2:]
command = "validate-barman-boundary"
required_phrase = "CloudNativePG Barman Cloud Plugin"

docker_forbidden = [
    re.compile(r"apt-get\s+install[^\n]*(?:barman|barman-cli|barman-cloud)", re.I),
    re.compile(r"pip\s+install[^\n]*barman", re.I),
    re.compile(r"barman-cloud-wal-archive", re.I),
    re.compile(r"barman-cloud-backup", re.I),
    re.compile(r"(?:COPY|ADD)\s+[^\n]*(?:plugin-barman-cloud|(?<!plugin-)barman-cloud)\b", re.I),
]
doc_forbidden = [
    re.compile(r"(?:use|uses|using|run|runs|requires|required|includes|ships|install|installs)[^\n.]{0,120}barman-cloud", re.I),
    re.compile(r"in-image[^\n.]{0,80}barman", re.I),
    re.compile(r"legacy[^\n.]{0,80}barman-cloud", re.I),
]


def fail(path, expected, actual, remediation):
    excerpt = str(actual).replace("\n", " ")[:240]
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {path}\n"
        f"expected: {expected}\n"
        f"actual: {excerpt}\n"
        f"remediation: {remediation}"
    )


def files_for(path):
    target = root / path if not Path(path).is_absolute() else Path(path)
    if not target.exists():
        return []
    if target.is_file():
        return [target]
    return [child for child in target.rglob("*") if child.is_file()]


def is_dockerfile(path):
    name = path.name.lower()
    return name == "dockerfile" or name.endswith(".dockerfile") or "dockerfile" in name


def is_doc(path):
    return path.suffix.lower() == ".md"


def normalize_dockerfile(text):
    return re.sub(r"\\\s*\n\s*", " ", text)


def is_negated(text, start):
    window = text[max(0, start - 120):start + 160].lower()
    return any(phrase in window for phrase in ["must not", "do not", "does not", "must never", "not appear", "reserved for the cloudnativepg barman cloud plugin"])


for raw in paths:
    for path in files_for(raw):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if is_dockerfile(path):
            docker_text = normalize_dockerfile(text)
            for pattern in docker_forbidden:
                match = pattern.search(docker_text)
                if match:
                    fail(path, f"PostgreSQL image Dockerfiles do not install legacy Barman tooling; expected {required_phrase} path", match.group(0), "Remove legacy Barman packages/binaries from image content and document the plugin path instead.")
        if is_doc(path) and re.search(r"\bbarman\b", text, re.I):
            if required_phrase not in text:
                fail(path, f"docs that discuss Barman include exact phrase {required_phrase!r}", text[:240], "Describe Barman support through the CloudNativePG Barman Cloud Plugin path.")
            for pattern in doc_forbidden:
                match = pattern.search(text)
                if match:
                    if is_negated(text, match.start()):
                        continue
                    fail(path, f"docs do not direct users to legacy in-image barman-cloud; expected {required_phrase} wording", match.group(0), "Replace legacy in-image backup guidance with CloudNativePG Barman Cloud Plugin guidance.")

print("PASS validate-barman-boundary plugin path gates")
PY
