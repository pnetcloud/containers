#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/cloudnative-pg-timescaledb/scripts"
DOCS_ROOT="${ROOT_DIR}"

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "${value}" ]]; then
    diag "validate-docs" "arguments" "${option} has a value" "missing" "Pass ${option} <path>."
    exit 64
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$1" "${2:-}"
      DOCS_ROOT="${2:-}"
      shift 2
      ;;
    *)
      diag "validate-docs" "arguments" "known validate-docs option" "$1" "Use --root <path> for fixture validation."
      exit 64
      ;;
  esac
done

python3 - "${ROOT_DIR}" "${DOCS_ROOT}" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
docs_root = Path(sys.argv[2]).resolve()
command = "validate-docs"
repo = "ghcr.io/pnetcloud/cloudnative-pg-timescaledb"

def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {str(actual).replace(chr(10), ' ')[:500]}\n"
        f"remediation: {remediation}"
    )

def load_yaml(path):
    try:
        import yaml
    except ImportError as exc:
        fail(path, "PyYAML available", str(exc), "Install PyYAML in the validation environment.")
    try:
        return yaml.safe_load(path.read_text())
    except Exception as exc:
        fail(path, "YAML parses", str(exc), "Keep metadata and catalogs valid YAML.")

def run_json(args, artifact):
    proc = subprocess.run(args, cwd=root, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        fail(artifact, "command exits 0", proc.stderr or proc.stdout, "Fix the generator before validating docs.")
    stdout = proc.stdout
    if not stdout.endswith("\n") or "\n" in stdout[:-1]:
        fail(artifact, "stdout is one compact JSON line", repr(stdout[:200]), "Emit compact machine JSON to stdout only.")
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as exc:
        fail(artifact, "stdout is valid JSON", str(exc), "Emit machine-readable JSON on stdout.")
    if proc.stderr.strip().startswith("{") or proc.stderr.strip().startswith("["):
        fail(artifact, "stderr contains human diagnostics only", proc.stderr[:200], "Do not write JSON payloads to stderr.")
    return payload, proc

def run_plain(args, artifact):
    proc = subprocess.run(args, cwd=root, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        fail(artifact, "command exits 0", proc.stderr or proc.stdout, "Fix the generator before validating docs.")
    return proc

def compare(path, expected_content, remediation):
    artifact = docs_root / path
    if not artifact.exists():
        fail(artifact, "generated documentation artifact exists", "missing", remediation)
    actual = artifact.read_text()
    if actual != expected_content:
        fail(artifact, "committed generated docs match regenerated output", "stale or modified generated documentation", remediation)

def markdown_files():
    if (docs_root / ".git").exists():
        proc = subprocess.run(["git", "ls-files", "*.md"], cwd=docs_root, text=True, capture_output=True, check=False)
        if proc.returncode != 0:
            fail(docs_root, "git ls-files succeeds", proc.stderr, "Run inside a git checkout or use fixture roots with markdown files.")
        candidates = [docs_root / line for line in proc.stdout.splitlines()]
    else:
        candidates = sorted(docs_root.rglob("*.md"))
    result = []
    reference_tree = "vendor"
    slash = "/"
    reference_prefix = reference_tree + slash
    for path in candidates:
        rel = path.relative_to(docs_root).as_posix()
        if rel.startswith(("_bmad-output/", reference_prefix, "cloudnative-pg-timescaledb/tests/")):
            continue
        if slash + reference_prefix in rel or "/tests/" in rel:
            continue
        result.append(path)
    return result

def is_negated(sentence):
    return bool(
        re.search(r"\b(?:never|not|no|without|must\s+not|do\s+not|does\s+not|avoid|instead\s+of|excluded?|out\s+of\s+scope|out\s+of\s+v1)\b", sentence, re.I)
        or re.search(r"\bprefer\b.{0,120}\bover\b", sentence, re.I)
        or re.search(r"\blatest\b.{0,40}\beligib", sentence, re.I)
    )

def validate_references():
    files = markdown_files()
    if not files:
        fail(docs_root, "at least one public Markdown file is validated", "none", "Add README.md, docs/*.md, or fixture Markdown files.")
    for path in files:
        text = path.read_text(errors="ignore")
        for match in re.finditer(rf"(?:image|imageName):\s*{re.escape(repo)}:latest\b", text):
            fail(path, "latest is not used as a primary image example", match.group(0), "Use immutable tags or digest-pinned references in primary examples.")
        for sentence in re.split(r"(?<=[.!?])\s+|\n+", text):
            if re.search(r"(?:`latest`|\blatest\b).{0,120}(?:primary|recommended|preferred|operator|CloudNativePG|catalog|imageCatalogRef)", sentence, re.I) and not is_negated(sentence):
                fail(path, "latest is convenience-only, not primary docs guidance", sentence.strip(), "Document latest only as convenience pointing to PostgreSQL 18 on trixie.")
            if re.search(r"unpublished.{0,120}(?:allowed|accepted|valid|referenced|catalog)", sentence, re.I) and not is_negated(sentence):
                fail(path, "catalog docs do not allow unpublished image references", sentence.strip(), "Gate catalogs on release-complete published metadata.")
            if re.search(r"(?:install|apt-get|apt\s+install|package|binary|required).{0,120}barman-cloud|barman-cloud.{0,120}(?:install|apt-get|apt\s+install|package|binary|required)", sentence, re.I) and not is_negated(sentence):
                fail(path, "docs reject legacy in-image barman-cloud guidance", sentence.strip(), "Use the CloudNativePG Barman Cloud Plugin boundary.")

metadata = docs_root / "cloudnative-pg-timescaledb/versions.yaml"
if not metadata.exists():
    fail(metadata, "metadata exists", "missing", "Provide cloudnative-pg-timescaledb/versions.yaml for docs validation.")
load_yaml(metadata)

tmpdir = Path(tempfile.mkdtemp(prefix="validate-docs-"))
try:
    generated_doc = tmpdir / "docs/generated/compatibility.md"
    payload, _ = run_json([str(root / "cloudnative-pg-timescaledb/scripts/generate-docs.sh"), "--metadata", str(metadata), "--json"], "generate-docs --json")
    manifest = payload.get("generated_docs_manifest")
    if not isinstance(manifest, list) or not manifest:
        fail("generate-docs --json", "generated_docs_manifest lists generated docs", payload, "Add manifest entries with path, generator input, owner story, and deterministic mode.")
    required_manifest_paths = {
        "cloudnative-pg-timescaledb/docs/generated/compatibility.md",
        "cloudnative-pg-timescaledb/docs/generated/compatibility-table.md",
        "cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md",
        "cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md",
        "cloudnative-pg-timescaledb/docs/generated/matrix-schema.md",
        "cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md",
    }
    actual_manifest_paths = {str(row.get("path")) for row in manifest if isinstance(row, dict)}
    missing = sorted(required_manifest_paths - actual_manifest_paths)
    if missing:
        fail("generate-docs --json", "manifest covers all generated docs from completed stories", missing, "Include compatibility, tables, schemas, and Barman reference docs.")
    for row in manifest:
        if not isinstance(row, dict):
            fail("generate-docs --json", "manifest rows are objects", row, "Use structured manifest rows.")
        missing_keys = sorted({"path", "generator_input", "generator_command", "owner_story", "deterministic_generation_mode"} - set(row))
        if missing_keys:
            fail("generate-docs --json", "manifest row includes required keys", missing_keys, "Expose path, generator input, owner story, and deterministic mode.")

    run_plain([str(root / "cloudnative-pg-timescaledb/scripts/generate-docs.sh"), "--metadata", str(metadata), "--output", str(generated_doc)], "generate-docs temp")
    compare("cloudnative-pg-timescaledb/docs/generated/compatibility.md", generated_doc.read_text(), "Run make generate and commit regenerated compatibility docs.")
    for name in ["compatibility-table.md", "release-candidate-schema.md", "release-evidence-schema.md", "barman-plugin-reference.md"]:
        compare(f"cloudnative-pg-timescaledb/docs/generated/{name}", (generated_doc.parent / name).read_text(), f"Run make generate and commit regenerated {name}.")
    matrix_tmp = tmpdir / "matrix.json"
    run_plain([str(root / "cloudnative-pg-timescaledb/scripts/generate-matrix.sh"), "--metadata", str(metadata), "--output", str(matrix_tmp)], "generate-matrix temp")
    compare("cloudnative-pg-timescaledb/docs/generated/matrix-schema.md", (matrix_tmp.parent / "docs/generated/matrix-schema.md").read_text(), "Run make generate and commit regenerated matrix schema docs.")

    for args, name in [
        ([str(root / "cloudnative-pg-timescaledb/scripts/generate-docs.sh"), "--metadata", str(metadata), "--json"], "generate-docs --json"),
        ([str(root / "cloudnative-pg-timescaledb/scripts/generate-matrix.sh"), "--metadata", str(metadata), "--json"], "generate-matrix --json"),
        ([str(root / "cloudnative-pg-timescaledb/scripts/generate-catalog.sh"), "--metadata", str(metadata), "--json"], "generate-catalog --json"),
        ([str(root / "cloudnative-pg-timescaledb/scripts/generate-bake.sh"), "--metadata", str(metadata), "--json"], "generate-bake --json"),
    ]:
        run_json(args, name)

    validate_references()
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

print("PASS validate-docs generated docs and public references")
PY
