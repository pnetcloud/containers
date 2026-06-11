#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
        if rel.startswith((reference_prefix, "cloudnative-pg-timescaledb/tests/")):
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
    expected_manifest = {
        "cloudnative-pg-timescaledb/docs/generated/compatibility.md": {
            "generator_command": "cloudnative-pg-timescaledb/scripts/generate-docs.sh",
            "generator_input": "cloudnative-pg-timescaledb/versions.yaml",
            "owner_story": "1.5",
            "deterministic_generation_mode": "metadata-rendered compatibility skeleton",
        },
        "cloudnative-pg-timescaledb/docs/generated/compatibility-table.md": {
            "generator_command": "cloudnative-pg-timescaledb/scripts/generate-docs.sh",
            "generator_input": "cloudnative-pg-timescaledb/versions.yaml",
            "owner_story": "5.1",
            "deterministic_generation_mode": "metadata-rendered compatibility table",
        },
        "cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md": {
            "generator_command": "cloudnative-pg-timescaledb/scripts/generate-docs.sh",
            "generator_input": "cloudnative-pg-timescaledb/versions.yaml",
            "owner_story": "4.2",
            "deterministic_generation_mode": "static generated schema documentation",
        },
        "cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md": {
            "generator_command": "cloudnative-pg-timescaledb/scripts/generate-docs.sh",
            "generator_input": "cloudnative-pg-timescaledb/versions.yaml",
            "owner_story": "4.4",
            "deterministic_generation_mode": "static generated schema documentation",
        },
        "cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md": {
            "generator_command": "cloudnative-pg-timescaledb/scripts/generate-docs.sh",
            "generator_input": "cloudnative-pg-timescaledb/versions.yaml",
            "owner_story": "5.8",
            "deterministic_generation_mode": "static generated failure reason catalog",
        },
        "cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md": {
            "generator_command": "cloudnative-pg-timescaledb/scripts/release-rehearsal.sh",
            "generator_input": "cloudnative-pg-timescaledb/tests/release-rehearsal/fixtures/valid-full-matrix.json;cloudnative-pg-timescaledb/config/release-rehearsal.yaml;DATE=20260609;DRY_RUN=1",
            "owner_story": "5.9",
            "deterministic_generation_mode": "dry-run release rehearsal report",
        },
        "cloudnative-pg-timescaledb/docs/generated/matrix-schema.md": {
            "generator_command": "cloudnative-pg-timescaledb/scripts/generate-matrix.sh",
            "generator_input": "cloudnative-pg-timescaledb/versions.yaml",
            "owner_story": "4.1",
            "deterministic_generation_mode": "static generated matrix schema documentation",
        },
        "cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md": {
            "generator_command": "cloudnative-pg-timescaledb/scripts/generate-docs.sh",
            "generator_input": "cloudnative-pg-timescaledb/versions.yaml",
            "owner_story": "2.7",
            "deterministic_generation_mode": "metadata-rendered Barman Cloud Plugin reference",
        },
    }
    expected_manifest_paths = list(expected_manifest)
    actual_manifest_paths = [str(row.get("path")) for row in manifest if isinstance(row, dict)]
    if actual_manifest_paths != expected_manifest_paths:
        fail("generate-docs --json", "manifest paths exactly match generated docs contract order", actual_manifest_paths, "Emit exactly the completed generated docs manifest paths in deterministic order.")
    manifest_by_path = {}
    for row in manifest:
        if not isinstance(row, dict):
            fail("generate-docs --json", "manifest rows are objects", row, "Use structured manifest rows.")
        required_manifest_keys = {"path", "generator_input", "generator_command", "owner_story", "deterministic_generation_mode"}
        missing_keys = sorted(required_manifest_keys - set(row))
        extra_keys = sorted(set(row) - required_manifest_keys)
        if missing_keys or extra_keys:
            fail("generate-docs --json", "manifest row includes exactly required keys", {"missing": missing_keys, "extra": extra_keys, "row": row}, "Expose only path, generator input, owner story, and deterministic mode.")
        path = str(row.get("path"))
        if path in manifest_by_path:
            fail("generate-docs --json", "manifest paths are unique", path, "Emit one manifest row per generated document.")
        manifest_by_path[path] = row
    for path, expected in expected_manifest.items():
        row = manifest_by_path[path]
        for key, value in expected.items():
            if row.get(key) != value:
                fail("generate-docs --json", f"{path} manifest {key} is deterministic", row, f"Set {key} to {value!r}.")

    run_plain([str(root / "cloudnative-pg-timescaledb/scripts/generate-docs.sh"), "--metadata", str(metadata), "--output", str(generated_doc)], "generate-docs temp")
    compare("cloudnative-pg-timescaledb/docs/generated/compatibility.md", generated_doc.read_text(), "Run make generate and commit regenerated compatibility docs.")
    for name in ["compatibility-table.md", "release-candidate-schema.md", "release-evidence-schema.md", "failure-reason-catalog.md", "barman-plugin-reference.md"]:
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
